#!/bin/bash
# Solaris support for a Proxmox node.
#
#   ./solaris.sh                 # say what is missing, do not change the node
#   ./solaris.sh patch           # install missing packages and apply the patches
#   ./solaris.sh vm --iso DVD.iso --vmid 100 --hostname sol --ip 10.10.10.10
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PAYLOAD=""
LOG=/var/log/solaris-host/last.log

CMD=""
REFRESH=0
DO_START=0
VMID=100
NAME=sol
DISK_GB=100
SWAP_MB=
HOME_MB=
MEMORY=2048
STORAGE=local-lvm
BRIDGE=vmbr1
HOSTNAME=sol
GUEST_IP=10.10.10.10
IP_SET=0
NETMASK=255.0.0.0
GATEWAY=10.10.10.1
GUEST_MAC=
IDPROM_MAC=52:54:00:12:34:56
JUMPSTART=
EXPORT_NET=10.10.10.0/24
ISO=/var/lib/vz/template/iso/sol-10-u11-ga-sparc-dvd.iso

WSH_PACKAGES=(pve-manager qemu-server pve-qemu-kvm)
BUILD_PACKAGES=(build-essential git gcc-sparc64-linux-gnu fcode-utils xsltproc libxml2-utils zlib1g-dev pkg-config python3)
JUMP_PACKAGES=(nfs-kernel-server rarpd bootparamd)

usage() {
	cat << 'EOF'
Usage: solaris.sh <command> [options]

Commands:
  status       Show packages and patches. Changes nothing.
  patch        Install any missing package and apply the Solaris patches.
               Skips a package that is already installed and a fix that is already applied.
  vm           Create one guest and add that guest to JumpStart.
  jumpstart    Add or update one JumpStart client without creating a VM.
  help         Show this text.

With no command, the script only reports what to run next.
There is no install command. patch installs whatever is missing.

Each JumpStart is its own directory, created the first time you use that name:

  /export/jumpstart/<name>/profile
  /export/jumpstart/<name>/rules
  /export/jumpstart/<name>/rules.ok
  /export/jumpstart/<name>/finishssh
  /export/jumpstart/<name>/mountcd
  /export/jumpstart/<name>/clients/<hostname>/sysidcfg

The default name is the hostname. A later run keeps those files, including
your edits. rules.ok is rebuilt from rules so the checksum still matches.
--swap and --home are written into profile only when that file is created.

Patch the node first. Add --refresh only when the QEMU and OpenBIOS files
should be copied and patched again:

  ./solaris.sh patch
  ./solaris.sh patch --refresh

Every vm and jumpstart command below lists every option for that command.

Create one guest. --disk 100 is the whole 100 GB disk. --swap 2048 is the
swap slice in MB. --home 10240 is a 10 GB /export/home. The rest of the
disk is /. Slice 2 is the Solaris overlap of the whole disk and holds no
files. Leave --home out and there is no separate home slice:

  ./solaris.sh vm \
    --iso /var/lib/vz/template/iso/sol-10-u11-ga-sparc-dvd.iso \
    --vmid 100 \
    --name sol \
    --hostname sol \
    --jumpstart sol \
    --ip 10.10.10.10 \
    --netmask 255.0.0.0 \
    --gateway 10.10.10.1 \
    --bridge vmbr1 \
    --mac BC:24:11:56:A5:3B \
    --idprom 52:54:00:12:34:56 \
    --disk 100 \
    --swap 2048 \
    --home 10240 \
    --memory 2048 \
    --storage local-lvm \
    --export-net 10.10.10.0/24 \
    --start

A second SPARC guest is refused. QEMU sends 52:54:00:12:34:56 for every
guest, so this command prints the duplicate MAC and creates nothing:

  ./solaris.sh vm \
    --iso /var/lib/vz/template/iso/sol-10-u11-ga-sparc-dvd.iso \
    --vmid 101 \
    --name sol2 \
    --hostname sol2 \
    --jumpstart sol2 \
    --ip 10.10.10.11 \
    --netmask 255.0.0.0 \
    --gateway 10.10.10.1 \
    --bridge vmbr1 \
    --mac BC:24:11:56:A5:3C \
    --idprom 52:54:00:12:34:56 \
    --disk 100 \
    --swap 2048 \
    --home 10240 \
    --memory 2048 \
    --storage local-lvm \
    --export-net 10.10.10.0/24 \
    --start

Reusing a JumpStart directory is the same rule. The profile stays, and the
new guest is still refused while another SPARC guest has the wire MAC:

  ./solaris.sh vm \
    --iso /var/lib/vz/template/iso/sol-10-u11-ga-sparc-dvd.iso \
    --vmid 102 \
    --name sol3 \
    --hostname sol3 \
    --jumpstart sol \
    --ip 10.10.10.12 \
    --netmask 255.0.0.0 \
    --gateway 10.10.10.1 \
    --bridge vmbr1 \
    --mac BC:24:11:56:A5:3D \
    --idprom 52:54:00:12:34:56 \
    --disk 100 \
    --swap 2048 \
    --home 10240 \
    --memory 2048 \
    --storage local-lvm \
    --export-net 10.10.10.0/24 \
    --start

Add or update a JumpStart client without creating a VM:

  ./solaris.sh jumpstart \
    --iso /var/lib/vz/template/iso/sol-10-u11-ga-sparc-dvd.iso \
    --vmid 100 \
    --hostname sol \
    --jumpstart sol \
    --ip 10.10.10.10 \
    --netmask 255.0.0.0 \
    --gateway 10.10.10.1 \
    --bridge vmbr1 \
    --mac BC:24:11:56:A5:3B \
    --idprom 52:54:00:12:34:56 \
    --disk 100 \
    --swap 2048 \
    --home 10240 \
    --memory 2048 \
    --export-net 10.10.10.0/24

An empty disk has no boot block, so the VM boots the CD with `- install`
and JumpStart runs. After Solaris is installed, the same VM boots the disk.
QEMU always sends RARP from 52:54:00:12:34:56. --idprom does not change
that address. A guest is not created when that MAC, or the sunhme MAC,
is already used.

Options:
  --iso PATH         Solaris 10 sparc DVD
  --vmid N           VM id (default 100)
  --name NAME        Proxmox VM name (default sol)
  --hostname NAME    Solaris hostname and default JumpStart name (default sol)
  --jumpstart NAME   Directory under /export/jumpstart (default: the hostname)
  --ip ADDR          Guest address (default 10.10.10.10)
  --netmask MASK     Guest netmask (default 255.0.0.0)
  --gateway ADDR     Bridge address and JumpStart server (default 10.10.10.1)
  --bridge NAME      Bridge (default vmbr1)
  --mac MAC          sunhme MAC. Generated when omitted
  --idprom MAC       Recorded for RARP. QEMU still sends 52:54:00:12:34:56
  --disk GB          Whole virtual disk in GB (default 100)
  --swap MB          Swap slice in MB when profile is created (default: --memory)
  --home MB          Optional /export/home slice in MB. Omit for no separate home
  --memory MB        RAM in MB (default 2048)
  --storage NAME     Proxmox storage for the disk (default local-lvm)
  --export-net CIDR  NFS clients allowed to mount JumpStart (default 10.10.10.0/24)
  --start            Boot the VM after vm
  --refresh          Re-copy the QEMU and OpenBIOS files and patch them again

patch prints what it will change, and stops before touching Proxmox
packages if this node is not ready.

Root password of a JumpStart guest is Sol10install.
JumpStart installs the SSH packages and enables ssh on every boot.
The console can look ready a few minutes before port 22 answers, because
ssh waits for the network and the local filesystems.

Proxmox Shutdown logs into the guest and halts Solaris, then waits until
the disks are synced. Use Shutdown. The Stop button cuts power while
Solaris is still running, and the next boot can hang on the disk.

When --ip is on the same network as this Proxmox host, and the guest
bridge is a different interface, the host answers for that address and
forwards it to the guest. Each guest keeps its own host route. Adding
192.168.1.181/32 leaves an existing 192.168.1.180/32 in place. A later
--ip for the same VM removes that VM's previous route and adds the new
one. An address on the private JumpStart network stays on that bridge
and gets no host route. patch applies the same routes again and does
not add a second copy.

If --bridge does not exist, it is created at --gateway with --netmask.
That is the private JumpStart network. A bridge is not created on top
of the network this host already uses. --gateway is this host's address
on the guest network, because JumpStart mounts its files from there.

  ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 \
      -o HostKeyAlgorithms=+ssh-rsa \
      -o PubkeyAcceptedAlgorithms=+ssh-rsa \
      root@10.10.10.10
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	install)
		echo "patch installs missing packages. There is no separate install command."
		echo "  ./solaris.sh patch"
		exit 1
		;;
	status|patch|vm|jumpstart|help)
		if [[ -n "$CMD" ]]; then
			echo "Only one command is allowed ($CMD and $1)."
			exit 1
		fi
		CMD=$1
		shift
		;;
	--iso) ISO=${2:?--iso needs a path}; shift 2 ;;
	--vmid) VMID=${2:?--vmid needs a number}; shift 2 ;;
	--name) NAME=${2:?--name needs a value}; shift 2 ;;
	--hostname) HOSTNAME=${2:?--hostname needs a value}; shift 2 ;;
	--jumpstart) JUMPSTART=${2:?--jumpstart needs a name}; shift 2 ;;
	--ip) GUEST_IP=${2:?--ip needs an address}; IP_SET=1; shift 2 ;;
	--netmask) NETMASK=${2:?--netmask needs a mask}; shift 2 ;;
	--gateway) GATEWAY=${2:?--gateway needs an address}; shift 2 ;;
	--bridge) BRIDGE=${2:?--bridge needs a name}; shift 2 ;;
	--mac) GUEST_MAC=${2:?--mac needs an address}; shift 2 ;;
	--idprom) IDPROM_MAC=${2:?--idprom needs an address}; shift 2 ;;
	--disk) DISK_GB=${2:?--disk needs a size in GB}; shift 2 ;;
	--swap) SWAP_MB=${2:?--swap needs a size in MB}; shift 2 ;;
	--home) HOME_MB=${2:?--home needs a size in MB}; shift 2 ;;
	--memory) MEMORY=${2:?--memory needs a size in MB}; shift 2 ;;
	--storage) STORAGE=${2:?--storage needs a name}; shift 2 ;;
	--export-net) EXPORT_NET=${2:?--export-net needs a CIDR}; shift 2 ;;
	--start) DO_START=1; shift ;;
	--refresh) REFRESH=1; shift ;;
	--help|-h) usage; exit 0 ;;
	--host-only|--no-vm)
		echo "$1 was removed. Use: ./solaris.sh patch"
		exit 1
		;;
	*)
		echo "Unknown argument: $1"
		echo "Run: ./solaris.sh help"
		exit 1
		;;
	esac
done

if [[ "$CMD" == "help" ]]; then
	usage
	exit 0
fi
extract_payloads() {
	local dest=$1
	mkdir -p "$dest/lib" "$dest/patches" "$dest/files" "$dest/jumpstart"
	cat > "$dest/lib/patch_qemuserver.py" << 'END_PATCH_QEMUSERVER'
#!/usr/bin/env python3
"""Patch a stock wsh qemu-server so sparc64 Solaris can boot.

Idempotent. Exits 0 when the file already has the fixes or they were applied.
Exits 1 when the stock anchors are gone, which means a newer package needs a
new patch.
"""
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8", errors="surrogateescape").read()
original = text

SERIAL_OLD = """\
            my $socket = "/var/run/qemu-server/${vmid}.serial$i";
            push @$devices, '-chardev', "socket,id=serial$i,path=$socket,server=on,wait=off";
            # On aarch64, serial0 is the UART device. QEMU only allows
            # connecting UART devices via the '-serial' command line, as
            # the device has a fixed slot on the hardware...
            if ($arch eq 'aarch64' && $i == 0) {
                push @$devices, '-serial', "chardev:serial$i";
            } else {
                push @$devices, '-device', "isa-serial,chardev=serial$i";
            }
"""

SERIAL_NEW = """\
            my $socket = "/var/run/qemu-server/${vmid}.serial$i";
            # The sparc UART only answers the first socket client. QEMU listens
            # on a private socket; sparc-serial-proxy holds it and serves the
            # path the Proxmox console opens.
            $socket .= '.qemu' if $arch =~ m/^sparc/ && $i == 0;
            push @$devices, '-chardev', "socket,id=serial$i,path=$socket,server=on,wait=off";
            # On aarch64, serial0 is the UART device. QEMU only allows
            # connecting UART devices via the '-serial' command line, as
            # the device has a fixed slot on the hardware...
            if (($arch eq 'aarch64' || $arch =~ m/^sparc/) && $i == 0) {
                push @$devices, '-serial', "chardev:serial$i";
            } else {
                push @$devices, '-device', "isa-serial,chardev=serial$i";
            }
"""

DRIVE_ANCHOR = """\
            $drive->{bootindex} = $bootorder->{$ds} if $bootorder->{$ds};

            if ($drive->{interface} eq 'virtio') {
"""

DRIVE_INSERT = """\
            $drive->{bootindex} = $bootorder->{$ds} if $bootorder->{$ds};

            # Solaris on sun4u boots from onboard IDE. The DVD is IDE 1
            # (OpenBIOS cdrom:f). The disk keeps its index, normally 0,
            # and OpenBIOS names it dad@0,0. LSI and mptsas never finish init.
            # Do not add a second disk: its index would collide with the DVD.
            if ($arch eq 'sparc64' && ($drive->{interface} eq 'scsi' || $drive->{interface} eq 'ide')) {
                my $volid = $drive->{file} // '';
                return if !$volid || $volid eq 'none';
                my $is_cdrom = drive_is_cdrom($drive);
                my $path = PVE::Storage::path($storecfg, $volid);
                if ($is_cdrom) {
                    push @$devices, '-drive', "file=$path,if=ide,index=1,media=cdrom,format=raw,read-only=on";
                } else {
                    my $index = $drive->{index};
                    push @$devices, '-drive', "file=$path,if=ide,index=$index,media=disk,format=raw";
                }
                return;
            }

            if ($drive->{interface} eq 'virtio') {
"""

VMGEN_OLD = """\
    if ($conf->{vmgenid}) {
        push @$devices, '-device', 'vmgenid,guid=' . $conf->{vmgenid};
    }
"""

VMGEN_NEW = """\
    # vmgenid is an x86/aarch64 device; qemu-system-sparc* has no such model.
    if ($conf->{vmgenid} && $arch !~ m/^sparc/) {
        push @$devices, '-device', 'vmgenid,guid=' . $conf->{vmgenid};
    }
"""


def need(label, old, new, marker):
    global text
    if marker in text:
        print(f"qemuserver: {label} already patched")
        return
    count = text.count(old)
    if count < 1:
        sys.exit(f"qemuserver: cannot find the stock {label} block in {path}")
    text = text.replace(old, new)
    print(f"qemuserver: {label} patched ({count})")


need("serial", SERIAL_OLD, SERIAL_NEW, "$socket .= '.qemu' if $arch =~ m/^sparc/")
need("vmgenid", VMGEN_OLD, VMGEN_NEW, "vmgenid} && $arch !~ m/^sparc/")

if "if=ide,index=1,media=cdrom" in text or "sparc64' && ($drive->{interface} eq 'scsi'" in text:
    print("qemuserver: ide drive routing already patched")
else:
    count = text.count(DRIVE_ANCHOR)
    if count != 1:
        sys.exit(f"qemuserver: drive-loop anchor found {count} times in {path}")
    text = text.replace(DRIVE_ANCHOR, DRIVE_INSERT, 1)
    print("qemuserver: ide drive routing patched")

if text == original:
    print("qemuserver: no changes")
else:
    open(path, "w", encoding="utf-8", errors="surrogateescape").write(text)
    print(f"qemuserver: wrote {path}")
END_PATCH_QEMUSERVER
	cat > "$dest/lib/patch_cmd646.py" << 'END_PATCH_CMD646'
#!/usr/bin/env python3
"""Stop Solaris from missing the CMD646 IDE interrupt.

Solaris SET FEATURES latches ARTTIM23/CFR. Stock QEMU clears those bits when
it drops the PCI line, so the driver times out with
"Interrupt not seen after set_features" and the disk never appears.

The two `and $imm,%eax` instructions (0xfb and 0xef) become `and $0xff`,
which leaves the latched bits set. cmd646_set_irq still clears MRDMODE and
lowers the PCI line. Leaving the line high livelocks the guest.

That latch fix lets SET FEATURES succeed, so Solaris switches the disk to
multiword DMA mode 2. DMA completion never arrives and the boot stops on
"ATA transport failed". The disk IDENTIFY data is therefore changed so
multiword DMA (word 63) and UDMA (word 88) are not advertised. Solaris
stays in PIO, which is what actually mounts the root disk.

Each pattern is unique in pve-qemu-kvm 11.1.3-1+wsh2. A different QEMU
build needs this checked again; the script refuses to guess.
"""
import sys

path = sys.argv[1]
data = bytearray(open(path, "rb").read())

# 64 bytes at cmd646_update_dma_interrupts, stock immediates 0xfb then 0xef.
IRQ_STOCK = bytes.fromhex(
    "488b97a80000000fb6425089c183e0fb83c904f64271040f45c1884250"
    "488b97a80000000fb6425789c183e0ef83c910f64271080f45c1884257"
    "31c031d231c931ffc3"
)
IRQ_PATCHED = bytearray(IRQ_STOCK)
IRQ_PATCHED[15] = 0xFF  # was 0xfb, file offset 0x46c7df in 11.1.3-1+wsh2
IRQ_PATCHED[44] = 0xFF  # was 0xef, file offset 0x46c7fc

# IDENTIFY words 62-65. The second word is word 63 (MW-DMA modes 0-2).
MDMA_STOCK = bytes.fromhex("070007000300b400")
MDMA_PIO = bytes.fromhex("070000000300b400")
# mov $0x203f,%eax ; mov $1,0x34(%rbx) ; mov %ax,0xe8(%rbx)  (word 88)
UDMA_STOCK = bytes.fromhex("b83f200000c7433401000000668983e8000000")
UDMA_PIO = bytes.fromhex("b800000000c7433401000000668983e8000000")


def find_all(needle):
    hits = []
    start = 0
    while True:
        i = data.find(needle, start)
        if i < 0:
            return hits
        hits.append(i)
        start = i + 1


def apply_one(stock, patched, label):
    already = find_all(patched)
    hits = find_all(stock)
    if len(already) == 1 and not hits:
        print(f"{label}: already patched at {already[0]:#x}")
        return False
    if len(hits) != 1 or already:
        sys.exit(
            f"{label}: stock found {len(hits)} times and patched found "
            f"{len(already)} times in {path}. This QEMU build is not "
            "11.1.3-1+wsh2; the patch was not applied."
        )
    at = hits[0]
    data[at : at + len(stock)] = patched
    print(f"{label}: patched {path} at {at:#x}")
    return True


changed = False
changed |= apply_one(IRQ_STOCK, bytes(IRQ_PATCHED), "cmd646")
changed |= apply_one(MDMA_STOCK, MDMA_PIO, "identify-mdma")
changed |= apply_one(UDMA_STOCK, UDMA_PIO, "identify-udma")
if changed:
    open(path, "wb").write(data)
END_PATCH_CMD646
	cat > "$dest/patches/openbios-solaris.patch" << 'END_OPENBIOS_PATCH'
diff --git a/arch/sparc64/tree.fs b/arch/sparc64/tree.fs
index f390f6c..02522a3 100644
--- a/arch/sparc64/tree.fs
+++ b/arch/sparc64/tree.fs
@@ -6,9 +6,14 @@ include config.fs
 
 : decode-unit-upa ( str len -- id lun )
   2 parse-nhex
+  \ Solaris rootnex names the sabre from upa-portid 1f. Registers stay at 1fe.
+  dup h# 1f = if drop h# 1fe then
+  swap dup h# 1f = if drop h# 1fe then swap
 ;
 
 : encode-unit-upa ( id lun -- str len)
+  dup h# 1fe = if drop h# 1f then
+  swap dup h# 1fe = if drop h# 1f then swap
   swap
   pocket tohexstr
   " ," pocket tmpstrcat >r
diff --git a/drivers/ide.c b/drivers/ide.c
index 4cc572c..9158ae7 100644
--- a/drivers/ide.c
+++ b/drivers/ide.c
@@ -34,6 +34,7 @@ do { printk("IDE - %s: " fmt, __func__ , ##args); } while (0)
 /* DECLARE data structures for the nodes.  */
 DECLARE_UNNAMED_NODE( ob_ide, 0, sizeof(struct ide_drive*) );
 DECLARE_UNNAMED_NODE( ob_ide_ctrl, 0, sizeof(int));
+DECLARE_UNNAMED_NODE( ob_ide_ata_addr, 0, 0);
 
 /*
  * define to 2 for the standard 2 channels only
@@ -1347,6 +1348,71 @@ static void set_ide_alias(const char *path)
 	set_property(aliases, idestr, path, strlen(path) + 1);
 }
 
+
+/* Solaris uata addresses a disk as dad@target,lun under the PCI IDE node.
+ * phys.hi is the target and phys.lo is the lun.
+ */
+static void
+ob_ide_decode_tgtlun(int *idx)
+{
+	char *arg = pop_fstr_copy();
+	char *ptr = arg;
+	unsigned long target = 0, lun = 0;
+	int digit;
+
+	(void)idx;
+	while (*ptr) {
+		digit = -1;
+		if (*ptr >= '0' && *ptr <= '9')
+			digit = *ptr - '0';
+		else if (*ptr >= 'a' && *ptr <= 'f')
+			digit = *ptr - 'a' + 10;
+		else if (*ptr >= 'A' && *ptr <= 'F')
+			digit = *ptr - 'A' + 10;
+		else
+			break;
+		target = (target << 4) | (unsigned long)digit;
+		ptr++;
+	}
+	if (*ptr == ',') {
+		ptr++;
+		while (*ptr) {
+			digit = -1;
+			if (*ptr >= '0' && *ptr <= '9')
+				digit = *ptr - '0';
+			else if (*ptr >= 'a' && *ptr <= 'f')
+				digit = *ptr - 'a' + 10;
+			else if (*ptr >= 'A' && *ptr <= 'F')
+				digit = *ptr - 'A' + 10;
+			else
+				break;
+			lun = (lun << 4) | (unsigned long)digit;
+			ptr++;
+		}
+	}
+	free(arg);
+	PUSH(lun);
+	PUSH(target);
+}
+
+static void
+ob_ide_encode_tgtlun(int *idx)
+{
+	char buf[32];
+	unsigned long target = (unsigned long)POP();
+	unsigned long lun = (unsigned long)POP();
+
+	(void)idx;
+	snprintf(buf, sizeof(buf), "%lx,%lx", target, lun);
+	push_str(buf);
+}
+
+NODE_METHODS(ob_ide_ata_addr) = {
+	{ "ata-unit-address",	ob_ide_decode_tgtlun	},
+	{ "decode-unit",	ob_ide_decode_tgtlun	},
+	{ "encode-unit",	ob_ide_encode_tgtlun	},
+};
+
 int ob_ide_init(const char *path, uint32_t io_port0, uint32_t ctl_port0,
 		uint32_t io_port1, uint32_t ctl_port1)
 {
@@ -1363,6 +1429,19 @@ int ob_ide_init(const char *path, uint32_t io_port0, uint32_t ctl_port0,
 	io_ports[1] = io_port1;
 	ctl_ports[1] = ctl_port1;
 
+	/* Direct children: dad@target,lun. No channel package in between. */
+	{
+		phandle_t parent = get_cur_dev();
+
+		set_int_property(parent, "#address-cells", 2);
+		set_int_property(parent, "#size-cells", 0);
+		set_property(parent, "ata", "dada", sizeof("dada"));
+		set_property(parent, "class", "ata", sizeof("ata"));
+		BIND_NODE_METHODS(parent, ob_ide_ata_addr);
+		if (0)
+			BIND_NODE_METHODS(parent, ob_ide_ctrl);
+	}
+
 	for (i = 0; i < IDE_NUM_CHANNELS; i++, current_channel++) {
 
 		chan = malloc(sizeof(struct ide_channel));
@@ -1404,38 +1483,6 @@ int ob_ide_init(const char *path, uint32_t io_port0, uint32_t ctl_port0,
 
 		ob_ide_identify_drives(chan);
 
-		fword("new-device");
-		dnode = get_cur_dev();
-
-		PUSH(pointer2cell(chan));
-		feval("value chan");
-
-		BIND_NODE_METHODS(get_cur_dev(), ob_ide_ctrl);
-
-#if !defined(CONFIG_PPC) && !defined(CONFIG_SPARC64)
-		props[0]=14; props[1]=0;
-		set_property(dnode, "interrupts",
-			     (char *)&props, 2*sizeof(props[0]));
-#endif
-
-		props[0] = __cpu_to_be32(current_channel);
-		props[1] = __cpu_to_be32(0);
-		props[2] = 0;
-		set_property(dnode, "reg", (char *)&props, 3*sizeof(props[0]));
-
-		set_int_property(dnode, "#address-cells", 1);
-		set_int_property(dnode, "#size-cells", 0);
-
-		push_str(DEV_NAME);
-		fword("device-name");
-
-		push_str(DEV_TYPE);
-		fword("device-type");
-
-		IDE_DPRINTF(DEV_NAME": [io ports 0x%x-0x%x,0x%x]\n",
-		            current_channel, chan->io_regs[0],
-		            chan->io_regs[0] + 7, chan->io_regs[8]);
-
 		for (j = 0; j < 2; j++) {
 			struct ide_drive *drive = &chan->drives[j];
                         const char *media = "UNKNOWN";
@@ -1456,7 +1503,7 @@ int ob_ide_init(const char *path, uint32_t io_port0, uint32_t ctl_port0,
 					media = "mo";
 					break;
 				case ide_media_disk:
-					media = "disk";
+					media = "dad";
 					break;
 			}
 
@@ -1464,7 +1511,10 @@ int ob_ide_init(const char *path, uint32_t io_port0, uint32_t ctl_port0,
 
 			fword("new-device");
 			dnode = get_cur_dev();
-			set_int_property(dnode, "reg", j);
+			/* phys.hi = target, phys.lo = lun */
+			props[0] = __cpu_to_be32(j);
+			props[1] = __cpu_to_be32(0);
+			set_property(dnode, "reg", (char *)&props, 2 * sizeof(props[0]));
 			push_str(media);
 			fword("device-name");
 
@@ -1488,8 +1538,6 @@ int ob_ide_init(const char *path, uint32_t io_port0, uint32_t ctl_port0,
 			if (drive->media == ide_media_disk)
 				set_hd_alias(nodebuff);
 		}
-
-		fword("finish-device");
 	}
 
 	return 0;
END_OPENBIOS_PATCH
	cat > "$dest/files/sparc-serial-proxy.py" << 'END_SERIAL_PROXY'
#!/usr/bin/env python3
"""Hold the one QEMU sparc serial client and let the Proxmox console reconnect.

qemu-system-sparc64 accepts a TCP/unix chardev connection, then later clients
get a live socket and no bytes. QemuServer is patched to listen on
/var/run/qemu-server/<vmid>.serial0.qemu. This process is the only client of
that socket and serves /var/run/qemu-server/<vmid>.serial0, which is what
`qm terminal` and the web console open.
"""
import os
import socket
import threading
import time

RUN = "/var/run/qemu-server"
MAX_REPLAY = 256 * 1024


class Port:
    def __init__(self, vmid):
        self.vmid = vmid
        self.qemu_path = os.path.join(RUN, f"{vmid}.serial0.qemu")
        self.listen_path = os.path.join(RUN, f"{vmid}.serial0")
        self.lock = threading.Lock()
        self.replay = bytearray()
        self.clients = []
        self.qemu = None
        self.server = None

    def add_replay(self, data):
        self.replay.extend(data)
        if len(self.replay) > MAX_REPLAY:
            del self.replay[: len(self.replay) - MAX_REPLAY]

    def qemu_reader(self, sock):
        try:
            while True:
                data = sock.recv(8192)
                if not data:
                    break
                with self.lock:
                    self.add_replay(data)
                    dead = []
                    for client in self.clients:
                        try:
                            client.sendall(data)
                        except Exception:
                            dead.append(client)
                    for client in dead:
                        self.clients.remove(client)
                        try:
                            client.close()
                        except Exception:
                            pass
        finally:
            with self.lock:
                if self.qemu is sock:
                    self.qemu = None
            try:
                sock.close()
            except Exception:
                pass

    def connect_qemu(self):
        while True:
            if not os.path.exists(self.qemu_path):
                time.sleep(0.2)
                continue
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                sock.connect(self.qemu_path)
            except Exception:
                sock.close()
                time.sleep(0.2)
                continue
            with self.lock:
                self.replay = bytearray()
                self.qemu = sock
            threading.Thread(target=self.qemu_reader, args=(sock,), daemon=True).start()
            while True:
                with self.lock:
                    alive = self.qemu is sock
                if not alive:
                    break
                time.sleep(0.2)

    def client_reader(self, conn):
        try:
            while True:
                data = conn.recv(8192)
                if not data:
                    break
                with self.lock:
                    target = self.qemu
                if target is not None:
                    try:
                        target.sendall(data)
                    except Exception:
                        pass
        finally:
            with self.lock:
                if conn in self.clients:
                    self.clients.remove(conn)
            try:
                conn.close()
            except Exception:
                pass

    def bind_server(self, existing=None):
        if existing is not None:
            try:
                existing.close()
            except Exception:
                pass
        # Only replace the console socket. Never unlink the .qemu socket.
        if os.path.exists(self.listen_path):
            os.unlink(self.listen_path)
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(self.listen_path)
        os.chmod(self.listen_path, 0o660)
        sock.listen(8)
        return sock

    def serve(self):
        os.makedirs(RUN, exist_ok=True)
        self.server = self.bind_server()
        threading.Thread(target=self.connect_qemu, daemon=True).start()

        def keep_path():
            while True:
                time.sleep(0.5)
                if not os.path.exists(self.listen_path):
                    self.server = self.bind_server(self.server)

        threading.Thread(target=keep_path, daemon=True).start()
        while True:
            try:
                conn, _addr = self.server.accept()
            except Exception:
                time.sleep(0.2)
                continue
            with self.lock:
                if self.replay:
                    try:
                        conn.sendall(self.replay)
                    except Exception:
                        conn.close()
                        continue
                self.clients.append(conn)
            threading.Thread(target=self.client_reader, args=(conn,), daemon=True).start()


def main():
    ports = {}
    lock = threading.Lock()

    def watch():
        while True:
            try:
                names = os.listdir(RUN)
            except FileNotFoundError:
                time.sleep(0.5)
                continue
            for name in names:
                if not name.endswith(".serial0.qemu"):
                    continue
                vmid = name[: -len(".serial0.qemu")]
                if not vmid.isdigit():
                    continue
                with lock:
                    if vmid in ports:
                        continue
                    port = Port(vmid)
                    ports[vmid] = port
                threading.Thread(target=port.serve, daemon=True).start()
            time.sleep(1)

    watch()


if __name__ == "__main__":
    main()
END_SERIAL_PROXY
	cat > "$dest/files/sparc-serial-proxy.service" << 'END_SERIAL_UNIT'
[Unit]
Description=SPARC serial console proxy
After=pve-cluster.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/sbin/sparc-serial-proxy.py
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
END_SERIAL_UNIT
	cat > "$dest/jumpstart/sysidcfg.in" << 'END_SYSIDCFG'
system_locale=C
timezone=UTC
terminal=vt100
timeserver=localhost
name_service=NONE
security_policy=NONE
nfs4_domain=dynamic
root_password=$1$solinst$on9.1EhsQ7mfThRVGlg3m0
auto_reg=disable
network_interface=PRIMARY {hostname=@HOSTNAME@ ip_address=@GUEST_IP@ netmask=@NETMASK@ protocol_ipv6=no default_route=@GATEWAY@}
END_SYSIDCFG
	cat > "$dest/jumpstart/profile.in" << 'END_PROFILE'
install_type    initial_install
system_type     standalone
partitioning    explicit
filesys         rootdisk.s1 @SWAP@ swap
@HOME@
filesys         rootdisk.s0 free /
cluster         SUNWCreq
cluster         SUNWCssh        add
package         SUNWuiu8        add
END_PROFILE
	cat > "$dest/jumpstart/rules" << 'END_RULES'
any - mountcd profile finishssh
END_RULES
	cat > "$dest/jumpstart/rules.ok" << 'END_RULES_OK'
any - mountcd profile finishssh
# version=2 checksum=3001
END_RULES_OK
	cat > "$dest/jumpstart/mountcd.in" << 'END_MOUNTCD'
#!/bin/sh
if [ ! -f /cdrom/.cdtoc ]; then
	/sbin/mount -F nfs -o ro,vers=3 @GATEWAY@:/mnt/soliso /cdrom
fi
if [ ! -f /cdrom/.cdtoc ]; then
	echo "DVD mount failed"
	/sbin/mount
	exit 1
fi
echo "DVD ready: `/bin/ls /cdrom/.cdtoc`"
exit 0
END_MOUNTCD
	cat > "$dest/jumpstart/finishssh" << 'END_FINISHSSH'
#!/bin/sh
# uata-pio shutdown-key
# Runs in the Solaris miniroot. /a is the new root. Do not use grep -q:
# Solaris grep treats -q as a filename and the test fails.
ROOT=/a
CFG=$ROOT/etc/ssh/sshd_config
if [ -f "$CFG" ]; then
	sed 's/^PermitRootLogin.*/PermitRootLogin yes/' "$CFG" > "$CFG.new"
	mv "$CFG.new" "$CFG"
fi

SYS=$ROOT/etc/system
touch "$SYS"
for m in drv/uata misc/dada misc/cmlb drv/dad; do
	grep "forceload: $m" "$SYS" >/dev/null 2>&1 || echo "forceload: $m" >> "$SYS"
done

NM=$ROOT/etc/name_to_major
if [ -f "$NM" ]; then
	grep '^uata[ 	]' "$NM" >/dev/null 2>&1 || echo "uata 135" >> "$NM"
	grep '^dad[ 	]' "$NM" >/dev/null 2>&1 || echo "dad 136" >> "$NM"
fi

DA=$ROOT/etc/driver_aliases
if [ -f "$DA" ]; then
	grep 'pci1095,646' "$DA" >/dev/null 2>&1 || echo 'uata "pci1095,646"' >> "$DA"
	grep 'ide-disk' "$DA" >/dev/null 2>&1 || echo 'dad "ide-disk"' >> "$DA"
fi

# DMA reads on this CMD646 never finish. These four words keep Solaris 10
# Update 11's sparcv9 uata on PIO, including the retry after a timeout.
UATA=$ROOT/platform/sun4u/kernel/drv/sparcv9/uata
if [ -f "$UATA" ]; then
	patch_at() {
		label=$1
		skip=$2
		shift 2
		got=/tmp/uata-got
		old=/tmp/uata-old
		neu=/tmp/uata-new
		dd if="$UATA" bs=1 skip="$skip" count=4 of="$got" 2>/dev/null
		nawk -v a="$1" -v b="$2" -v c="$3" -v d="$4" \
			'BEGIN { printf "%c%c%c%c", a, b, c, d }' > "$old"
		nawk -v a="$5" -v b="$6" -v c="$7" -v d="$8" \
			'BEGIN { printf "%c%c%c%c", a, b, c, d }' > "$neu"
		if cmp -s "$got" "$neu"; then
			echo "uata $label already patched"
		elif cmp -s "$got" "$old"; then
			dd if="$neu" of="$UATA" bs=1 seek="$skip" conv=notrunc 2>/dev/null
			echo "uata $label patched"
		else
			echo "uata $label left unchanged"
		fi
	}
	patch_at mode 14704 154 16 32 165 154 16 32 0
	patch_at mode-word 14752 178 16 32 165 178 16 32 0
	patch_at set-feature 12956 2 64 0 12 16 128 0 50
	patch_at timeout 6092 18 64 0 17 16 128 0 17
else
	echo "uata driver not found; PIO patch skipped"
fi

if [ -n "$SI_CONFIG_DIR" ] && [ -f "$SI_CONFIG_DIR/shutdown.pub" ]; then
	mkdir -p "$ROOT/.ssh"
	cp "$SI_CONFIG_DIR/shutdown.pub" "$ROOT/.ssh/authorized_keys"
	chmod 700 "$ROOT/.ssh"
	chmod 600 "$ROOT/.ssh/authorized_keys"
	echo "shutdown key installed for root"
fi

if [ -x /usr/sbin/bootadm ]; then
	/usr/sbin/bootadm update-archive -R /a || echo "bootadm update-archive failed"
elif [ -x /sbin/bootadm ]; then
	/sbin/bootadm update-archive -R /a || echo "bootadm update-archive failed"
fi

cat > $ROOT/etc/rc3.d/S99localssh << "EOS"
#!/sbin/sh
if [ -x /usr/sbin/svcadm ]; then
	/usr/sbin/svcadm enable network/ssh
fi
EOS
chmod 744 $ROOT/etc/rc3.d/S99localssh
exit 0
END_FINISHSSH
	chmod 755 "$dest/lib/patch_qemuserver.py" "$dest/lib/patch_cmd646.py" \
		"$dest/files/sparc-serial-proxy.py" "$dest/jumpstart/finishssh"
}

fail() {
	echo ""
	echo "FAILED: $1"
	shift || true
	while [[ $# -gt 0 ]]; do
		echo "  $1"
		shift
	done
	if [[ -f "$LOG" ]]; then
		echo ""
		echo "Last lines of ${LOG}:"
		tail -30 "$LOG" || true
	fi
	echo ""
	echo "Then run: ./solaris.sh status"
	exit 1
}

need_root() {
	if [[ $(id -u) -ne 0 ]]; then
		echo "Run as root on the Proxmox node."
		echo "  ./solaris.sh $CMD"
		exit 1
	fi
	mkdir -p /var/log/solaris-host
}

pkg_ver() {
	dpkg-query -W -f '${Status} ${Version}' "$1" 2>/dev/null || true
}

pkg_ok() {
	local ver
	ver=$(pkg_ver "$1")
	[[ "$ver" == *"install ok installed"* && "$ver" == *+wsh* ]]
}

missing_wsh() {
	local p ver
	for p in "${WSH_PACKAGES[@]}"; do
		ver=$(pkg_ver "$p")
		if [[ "$ver" != *"install ok installed"* ]]; then
			echo "  $p is not installed"
		elif [[ "$ver" != *+wsh* ]]; then
			echo "  $p is ${ver##* }, which is not a wsh build"
		fi
	done
	if [[ ! -f /usr/share/perl5/PVE/QemuServer/CPUConfig.pm ]]; then
		echo "  /usr/share/perl5/PVE/QemuServer/CPUConfig.pm is missing"
	elif ! grep -q sparc64 /usr/share/perl5/PVE/QemuServer/CPUConfig.pm; then
		echo "  qemu-server does not list sparc64"
	fi
	if [[ ! -x /usr/bin/qemu-system-sparc64 ]]; then
		echo "  /usr/bin/qemu-system-sparc64 is missing"
	fi
}

missing_debs() {
	local p
	for p in "$@"; do
		dpkg-query -W -f '${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || echo "  $p"
	done
}

cmd646_state() {
	if ! command -v python3 >/dev/null 2>&1; then
		echo "unknown"
		return 0
	fi
	python3 - "$1" << 'PY'
import sys
path = sys.argv[1]
try:
    data = open(path, "rb").read()
except OSError as exc:
    print(f"unreadable {exc}")
    sys.exit(0)
irq_stock = bytes.fromhex(
    "488b97a80000000fb6425089c183e0fb83c904f64271040f45c1884250"
    "488b97a80000000fb6425789c183e0ef83c910f64271080f45c1884257"
    "31c031d231c931ffc3"
)
irq = bytearray(irq_stock)
irq[15] = 0xFF
irq[44] = 0xFF
mdma_stock = bytes.fromhex("070007000300b400")
mdma_pio = bytes.fromhex("070000000300b400")
udma_stock = bytes.fromhex("b83f200000c7433401000000668983e8000000")
udma_pio = bytes.fromhex("b800000000c7433401000000668983e8000000")
irq_ok = data.find(bytes(irq)) >= 0
pio_ok = data.find(mdma_pio) >= 0 and data.find(udma_pio) >= 0
stock_left = (
    data.find(irq_stock) >= 0
    or data.find(mdma_stock) >= 0
    or data.find(udma_stock) >= 0
)
if irq_ok and pio_ok and not stock_left:
    print("patched")
elif stock_left or irq_ok or pio_ok:
    print("stock")
else:
    print("unknown")
PY
}

serial_proxy_ok() {
	[[ -f /usr/local/sbin/sparc-serial-proxy.py ]] || return 1
	grep -q 'endswith(".serial0.qemu")' /usr/local/sbin/sparc-serial-proxy.py || return 1
	systemctl is-active --quiet sparc-serial-proxy.service
}

patches_applied() {
	local qs=/usr/share/perl5/PVE/QemuServer.pm
	local bios=/usr/share/kvm/openbios-sparc64
	[[ -f "$qs" ]] || return 1
	grep -q "if=ide,index=1,media=cdrom" "$qs" || return 1
	grep -q 'socket .= .\.qemu. if $arch =~ m/\^sparc/' "$qs" || return 1
	grep -q 'vmgenid} && $arch !~ m/\^sparc/' "$qs" || return 1
	[[ -x /usr/bin/qemu-system-sparc64 ]] || return 1
	[[ "$(cmd646_state /usr/bin/qemu-system-sparc64)" == "patched" ]] || return 1
	[[ -f /var/lib/solaris-host/openbios.stamp && -f "$bios" ]] || return 1
	serial_proxy_ok || return 1
}

status_cmd() {
	local missing
	echo "Packages"
	local p ver
	for p in "${WSH_PACKAGES[@]}"; do
		ver=$(pkg_ver "$p")
		if pkg_ok "$p"; then
			echo "  ok    $p ${ver##* }"
		elif [[ -z "$ver" ]]; then
			echo "  miss  $p"
		else
			echo "  bad   $p ${ver}"
		fi
	done
	for p in "${BUILD_PACKAGES[@]}" "${JUMP_PACKAGES[@]}"; do
		if dpkg-query -W -f '${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
			echo "  ok    $p"
		else
			echo "  miss  $p"
		fi
	done
	echo "Patches"
	if [[ -f /usr/share/perl5/PVE/QemuServer.pm ]] && grep -q "if=ide,index=1,media=cdrom" /usr/share/perl5/PVE/QemuServer.pm; then
		echo "  ok    qemu-server IDE routing"
	else
		echo "  miss  qemu-server IDE routing"
	fi
	if [[ -x /usr/bin/qemu-system-sparc64 ]]; then
		echo "  $(cmd646_state /usr/bin/qemu-system-sparc64)  CMD646 interrupt and PIO disk in qemu-system-sparc64"
		/usr/bin/qemu-system-sparc64 --version 2>/dev/null | head -1 | sed 's/^/        /' || true
	else
		echo "  miss  qemu-system-sparc64"
	fi
	if [[ -f /var/lib/solaris-host/openbios.stamp ]]; then
		echo "  ok    OpenBIOS stamp $(cat /var/lib/solaris-host/openbios.stamp)"
	else
		echo "  miss  OpenBIOS not built by this script"
	fi
	if serial_proxy_ok; then
		echo "  ok    sparc-serial-proxy"
	elif systemctl is-active --quiet sparc-serial-proxy.service 2>/dev/null; then
		echo "  old   sparc-serial-proxy serves one VM only"
	else
		echo "  miss  sparc-serial-proxy"
	fi
	echo
	missing=$(missing_wsh || true)
	if [[ -n "$missing" ]]; then
		echo "This node is not ready for Solaris."
		echo "Run:"
		echo "  ./solaris.sh patch"
		return 2
	fi
	if ! patches_applied; then
		echo "Packages are installed. Some patches are not applied."
		echo "Run:"
		echo "  ./solaris.sh patch"
		return 2
	fi
	echo "This node can boot sparc64 Solaris."
	echo "Create a guest with:"
	echo "  ./solaris.sh vm --iso /path/to/sol-10-u11-ga-sparc-dvd.iso --vmid ${VMID}"
	return 0
}

deb_installed() {
	dpkg-query -W -f '${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

setup_wsh_repo() {
	local log=$1
	echo "Adding the wsh-pve repository."
	apt-get update >"$log" 2>&1 || fail "apt-get update before adding the wsh repository" \
		"The node could not update its existing Proxmox lists." \
		"Log: $log"
	if ! deb_installed wget || ! deb_installed gpg || ! deb_installed ca-certificates; then
		DEBIAN_FRONTEND=noninteractive apt-get install -y wget gpg ca-certificates >>"$log" 2>&1 \
			|| fail "apt-get install wget gpg ca-certificates" "Log: $log"
	else
		echo "already installed  wget gpg ca-certificates"
	fi
	if ! wget -O - http://debian.wshosting.no/debian/conf/wsh-pve.gpg.key \
		| gpg --dearmor --yes -o /usr/share/keyrings/wsh-pve.gpg >>"$log" 2>&1; then
		fail "download of the wsh signing key" \
			"Could not fetch http://debian.wshosting.no/debian/conf/wsh-pve.gpg.key" \
			"Check DNS and outbound HTTP from this node." \
			"Log: $log"
	fi
	if ! wget -O /etc/apt/sources.list.d/wsh-pve.sources \
		http://debian.wshosting.no/debian/conf/wsh-pve.sources >>"$log" 2>&1; then
		fail "download of wsh-pve.sources" "Log: $log"
	fi
	cat > /etc/apt/preferences.d/wsh-pve << 'EOF'
Package: pve-manager qemu-server pve-qemu-kvm
Pin: origin debian.wshosting.no
Pin-Priority: 1001
EOF
	if ! apt-get update >"$log" 2>&1; then
		fail "apt-get update of the wsh repository" \
			"The signing key or /etc/apt/sources.list.d/wsh-pve.sources was rejected." \
			"Log: $log"
	fi
}

packages_pending() {
	local p
	for p in "${WSH_PACKAGES[@]}"; do
		pkg_ok "$p" || return 0
	done
	for p in "${BUILD_PACKAGES[@]}" "${JUMP_PACKAGES[@]}"; do
		deb_installed "$p" || return 0
	done
	return 1
}

wsh_pending() {
	local p
	for p in "${WSH_PACKAGES[@]}"; do
		pkg_ok "$p" || return 0
	done
	return 1
}

patches_pending() {
	[[ "$REFRESH" == 1 ]] && return 0
	qemuserver_patched || return 0
	[[ -x /usr/bin/qemu-system-sparc64 ]] || return 0
	[[ "$(cmd646_state /usr/bin/qemu-system-sparc64)" == "patched" ]] || return 0
	[[ -f /var/lib/solaris-host/openbios.stamp ]] || return 0
	serial_proxy_ok || return 0
	return 1
}

preflight() {
	local mode=$1
	local -a problems=()
	if ! command -v pveversion >/dev/null 2>&1 || [[ ! -d /etc/pve ]]; then
		problems+=("This is not a Proxmox VE node. pveversion or /etc/pve is missing.")
	elif ! mountpoint -q /etc/pve; then
		problems+=("/etc/pve is not mounted. Start pve-cluster before changing Proxmox packages.")
	fi
	if [[ -e /var/lib/dpkg/lock-frontend ]] && ! flock -n /var/lib/dpkg/lock-frontend -c true 2>/dev/null; then
		problems+=("apt or dpkg is already running. Wait until it finishes, then run this again.")
	fi
	local pending=0
	if packages_pending; then
		pending=1
	fi
	if [[ "$mode" == "patch" ]] && patches_pending; then
		pending=1
	fi
	if [[ ${#problems[@]} -gt 0 ]]; then
		echo "Not continuing. Fix this before any Proxmox package is installed or patched:"
		local item
		for item in "${problems[@]}"; do
			echo "  - $item"
		done
		exit 2
	fi
	if [[ "$pending" == 0 ]]; then
		return 0
	fi
	echo "Before changing this Proxmox node:"
	if wsh_pending; then
		echo "  pve-manager, qemu-server, and pve-qemu-kvm will be installed or replaced"
		echo "  with the wsh builds from debian.wshosting.no. Stock Proxmox has no sparc64."
		echo "  An apt pin at priority 1001 keeps those wsh packages when a newer stock"
		echo "  Proxmox upload appears. Delete /etc/apt/preferences.d/wsh-pve to stop that."
		echo "  A sparc64 guest cannot move to a node that does not have the same packages."
	fi
	if [[ "$mode" == "patch" ]] && patches_pending; then
		echo "  The Solaris patch edits qemu-server, qemu-system-sparc64, and OpenBIOS"
		echo "  on this node. Every sparc64 VM uses those files."
		echo "  A VM that is already running keeps its current QEMU until it is stopped"
		echo "  and started again. pveproxy may restart when the patch finishes."
	fi
	if qm list >/dev/null 2>&1; then
		local running
		running=$(qm list 2>/dev/null | awk 'NR>1 && $3=="running" {print $1}' | paste -sd, -)
		if [[ -n "$running" ]]; then
			echo "  Running VMs: ${running}"
		fi
	fi
	echo
}

ensure_packages() {
	local log=/var/log/solaris-host/install.log
	LOG=$log
	local p
	local -a need=()
	local need_wsh=0
	for p in "${WSH_PACKAGES[@]}"; do
		if pkg_ok "$p"; then
			echo "already installed  $p $(pkg_ver "$p" | awk '{print $NF}')"
		elif deb_installed "$p"; then
			echo "replace            $p $(pkg_ver "$p" | awk '{print $NF}') is not a wsh build"
			need+=("$p")
			need_wsh=1
		else
			echo "missing            $p"
			need+=("$p")
			need_wsh=1
		fi
	done
	for p in "${BUILD_PACKAGES[@]}" "${JUMP_PACKAGES[@]}"; do
		if deb_installed "$p"; then
			echo "already installed  $p"
		else
			echo "missing            $p"
			need+=("$p")
		fi
	done
	if [[ ${#need[@]} -eq 0 ]]; then
		echo "All packages are already installed."
		return 0
	fi
	if [[ "$need_wsh" == 1 ]]; then
		setup_wsh_repo "$log"
	fi
	apt_install "$log" "${need[@]}"
	local missing
	missing=$(missing_wsh || true)
	if [[ -n "$missing" ]]; then
		fail "a wsh package is still not the sparc64 build" \
			"$missing" \
			"Run: apt policy pve-manager qemu-server pve-qemu-kvm" \
			"The pin in /etc/apt/preferences.d/wsh-pve must be 1001."
	fi
	local still
	still=$(missing_debs "${BUILD_PACKAGES[@]}" "${JUMP_PACKAGES[@]}")
	if [[ -n "$still" ]]; then
		fail "packages are still missing after apt-get install" "$still" "Log: $log"
	fi
	echo "Installed: ${need[*]}"
}

apt_install() {
	local log=$1
	shift
	echo "Installing: $*"
	if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >"$log" 2>&1; then
		fail "apt-get install $*" \
			"Log: $log" \
			"Check the node can reach http://debian.wshosting.no and run: apt-get update" \
			"Then: apt policy $1"
	fi
}

ensure_payload() {
	if [[ -n "$PAYLOAD" && -d "$PAYLOAD" ]]; then
		return 0
	fi
	PAYLOAD=$(mktemp -d /tmp/solaris-host.XXXXXX)
	trap 'rm -rf "$PAYLOAD"' EXIT
	extract_payloads "$PAYLOAD"
}

divert_file() {
	local file=$1
	local dist="${file}.wsh-dist"
	if [[ ! -e "$file" && ! -e "$dist" ]]; then
		fail "missing $file" \
			"The package that owns this file is not installed." \
			"Run: ./solaris.sh patch"
	fi
	if ! dpkg-divert --list "$file" | grep -F -q "$dist"; then
		dpkg-divert --local --rename --divert "$dist" --add "$file"
		cp -a "$dist" "$file"
	elif [[ "$REFRESH" == 1 ]]; then
		if [[ ! -e "$dist" ]]; then
			fail "cannot refresh $file" \
				"$dist does not exist, so there is no package copy to patch again."
		fi
		cp -a "$dist" "$file"
	fi
}

qemuserver_patched() {
	local qs=/usr/share/perl5/PVE/QemuServer.pm
	[[ -f "$qs" ]] || return 1
	grep -q "if=ide,index=1,media=cdrom" "$qs" || return 1
	grep -q 'socket .= .\.qemu. if $arch =~ m/\^sparc/' "$qs" || return 1
	grep -q 'vmgenid} && $arch !~ m/\^sparc/' "$qs" || return 1
}

LAN_DIR=/var/lib/solaris-host/lan

install_lan_helper() {
	mkdir -p "$LAN_DIR" /usr/local/sbin /etc/network/if-up.d
	cat > /usr/local/sbin/solaris-lan-apply << 'APPLY'
#!/bin/bash
# Publish saved Solaris guests onto the Proxmox host network.
# One /32 route per guest. Replacing one address leaves the others in place.
set -u
LAN_DIR=/var/lib/solaris-host/lan
mkdir -p "$LAN_DIR"

main_iface() {
	ip -4 route show default | awk 'NR==1 { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
}

drop_one() {
	local vmid=$1 ip=$2 br=$3 main=$4
	local f oip
	shopt -s nullglob
	for f in "$LAN_DIR"/*; do
		[[ "$(basename "$f")" == "$vmid" ]] && continue
		oip=$(awk -F= '$1=="IP" { print $2 }' "$f")
		if [[ "$oip" == "$ip" ]]; then
			return 0
		fi
	done
	ip route del "${ip}/32" dev "$br" 2>/dev/null || true
	if [[ -n "$main" ]]; then
		ip neigh del proxy "$ip" dev "$main" 2>/dev/null || true
	fi
	python3 - "$vmid" "$ip" << 'PY'
import re, subprocess, sys
vmid, ip = sys.argv[1:]
try:
    out = subprocess.check_output(
        ["nft", "-a", "list", "chain", "inet", "filter", "forward"],
        text=True, stderr=subprocess.DEVNULL)
except (subprocess.CalledProcessError, FileNotFoundError):
    raise SystemExit(0)
handles = []
mark = "solaris-vmid-%s" % vmid
for line in out.splitlines():
    if mark in line or ("daddr %s " % ip) in line or ("saddr %s " % ip) in line:
        found = re.search(r"handle (\d+)", line)
        if found:
            handles.append(found.group(1))
for handle in handles:
    subprocess.call(["nft", "delete", "rule", "inet", "filter", "forward", "handle", handle])
PY
}

apply_all() {
	local main cidr
	main=$(main_iface)
	if [[ -z "$main" ]]; then
		echo "LAN route          skipped, this host has no default route yet"
		return 0
	fi
	cidr=$(ip -4 -o addr show dev "$main" | awk 'NR==1 { print $4 }')
	if [[ -z "$cidr" ]]; then
		echo "LAN route          skipped, ${main} has no address yet"
		return 0
	fi
	local -a bridges=()
	local f ip br vmid onlan
	shopt -s nullglob
	for f in "$LAN_DIR"/*; do
		[[ -f "$f" ]] || continue
		br=$(awk -F= '$1=="BRIDGE" { print $2 }' "$f")
		[[ -n "$br" && "$br" != "$main" ]] || continue
		local seen=0 b
		for b in "${bridges[@]:-}"; do
			[[ "$b" == "$br" ]] && seen=1
		done
		[[ "$seen" == 0 ]] && bridges+=("$br")
	done
	sysctl -w net.ipv4.ip_forward=1 >/dev/null
	sysctl -w net.ipv4.conf.all.proxy_arp=1 >/dev/null
	sysctl -w net.ipv4.conf.default.proxy_arp=1 >/dev/null
	sysctl -w "net.ipv4.conf.${main}.proxy_arp=1" >/dev/null || true
	{
		echo "net.ipv4.ip_forward = 1"
		echo "net.ipv4.conf.all.proxy_arp = 1"
		echo "net.ipv4.conf.default.proxy_arp = 1"
		echo "net.ipv4.conf.${main}.proxy_arp = 1"
		for br in "${bridges[@]:-}"; do
			[[ -n "$br" ]] || continue
			echo "net.ipv4.conf.${br}.proxy_arp = 1"
			sysctl -w "net.ipv4.conf.${br}.proxy_arp=1" >/dev/null || true
		done
	} > /etc/sysctl.d/99-solaris-proxyarp.conf
	echo "proxy ARP          ${main}${bridges[*]:+ ${bridges[*]}}"
	for f in "$LAN_DIR"/*; do
		[[ -f "$f" ]] || continue
		vmid=$(basename "$f")
		ip=$(awk -F= '$1=="IP" { print $2 }' "$f")
		br=$(awk -F= '$1=="BRIDGE" { print $2 }' "$f")
		[[ -n "$ip" && -n "$br" ]] || continue
		onlan=$(python3 - "$ip" "$cidr" "$main" "$br" << 'PY'
import ipaddress, sys
guest, cidr, main, bridge = sys.argv[1:]
host = ipaddress.ip_interface(cidr)
addr = ipaddress.ip_address(guest)
if addr == host.ip:
    print("self")
elif bridge == main:
    print("direct")
elif addr in host.network:
    print("publish")
else:
    print("private")
PY
)
		case "$onlan" in
		publish)
			ip route replace "${ip}/32" dev "$br"
			ip neigh replace proxy "$ip" dev "$main"
			python3 - "$vmid" "$ip" "$main" "$br" << 'PY'
import re, subprocess, sys
vmid, ip, uplink, bridge = sys.argv[1:]
try:
    out = subprocess.check_output(
        ["nft", "-a", "list", "chain", "inet", "filter", "forward"],
        text=True, stderr=subprocess.DEVNULL)
except (subprocess.CalledProcessError, FileNotFoundError):
    raise SystemExit(0)
if "policy drop" not in out:
    raise SystemExit(0)
handles = []
mark = "solaris-vmid-%s" % vmid
for line in out.splitlines():
    if mark in line or ("daddr %s " % ip) in line or ("saddr %s " % ip) in line:
        found = re.search(r"handle (\d+)", line)
        if found:
            handles.append(found.group(1))
for handle in handles:
    subprocess.check_call(["nft", "delete", "rule", "inet", "filter", "forward", "handle", handle])
subprocess.check_call([
    "nft", "add", "rule", "inet", "filter", "forward",
    "iifname", uplink, "oifname", bridge, "ip", "daddr", ip, "accept",
    "comment", "solaris-vmid-%s" % vmid,
])
subprocess.check_call([
    "nft", "add", "rule", "inet", "filter", "forward",
    "iifname", bridge, "oifname", uplink, "ip", "saddr", ip, "accept",
    "comment", "solaris-vmid-%s" % vmid,
])
PY
			[[ $? -eq 0 ]] || return 1
			echo "LAN route          ${ip}/32 dev ${br} (VM ${vmid})"
			;;
		*)
			echo "LAN route          VM ${vmid} ${ip} stays on ${br}"
			;;
		esac
	done
}

if [[ "${1:-}" == "--drop" ]]; then
	drop_one "$2" "$3" "$4" "$(main_iface)"
	exit 0
fi
apply_all
APPLY
	chmod 755 /usr/local/sbin/solaris-lan-apply
	cat > /etc/network/if-up.d/solaris-lan << 'UP'
#!/bin/sh
# Re-apply Solaris host routes when an interface comes up. Running twice is safe.
case "${IFACE:-}" in
lo) exit 0 ;;
esac
/usr/local/sbin/solaris-lan-apply || true
exit 0
UP
	chmod 755 /etc/network/if-up.d/solaris-lan
}

point_hook_at_guest_ip() {
	local conf="/etc/pve/qemu-server/${VMID}.conf"
	local spec file
	[[ "$IP_SET" == 1 ]] || return 0
	[[ "$GUEST_IP" =~ ^[0-9.]+$ ]] || return 0
	[[ -f "$conf" ]] || return 0
	spec=$(sed -n 's/^hookscript: //p' "$conf" | head -1)
	[[ -n "$spec" ]] || return 0
	file="/var/lib/vz/snippets/$(basename "$spec")"
	[[ -f "$file" ]] || return 0
	if grep -q "root@${GUEST_IP}[ \"']" "$file"; then
		return 0
	fi
	sed -i -E "s/root@[0-9][0-9.]*/root@${GUEST_IP}/" "$file"
	echo "shutdown hook      ${file} uses ${GUEST_IP}"
}

publish_guest_lan() {
	local state="${LAN_DIR}/${VMID}"
	local old_ip="" old_br=""
	install_lan_helper
	if [[ "$IP_SET" != 1 ]]; then
		/usr/local/sbin/solaris-lan-apply
		if [[ -f "$state" || -f "/etc/pve/qemu-server/${VMID}.conf" ]]; then
			echo "LAN route          VM ${VMID} unchanged (pass --ip to change it)"
		fi
		return 0
	fi
	if [[ -f "$state" ]]; then
		old_ip=$(awk -F= '$1=="IP" { print $2 }' "$state")
		old_br=$(awk -F= '$1=="BRIDGE" { print $2 }' "$state")
	fi
	local mode main cidr
	main=$(ip -4 route show default | awk 'NR==1 { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
	cidr=$(ip -4 -o addr show dev "$main" 2>/dev/null | awk 'NR==1 { print $4 }')
	mode=$(python3 - "$GUEST_IP" "$cidr" "$main" "$BRIDGE" << 'PY'
import ipaddress, sys
guest, cidr, main, bridge = sys.argv[1:]
if not cidr or not main:
    print("private")
    raise SystemExit(0)
host = ipaddress.ip_interface(cidr)
addr = ipaddress.ip_address(guest)
if addr == host.ip:
    print("self")
elif bridge == main:
    print("direct")
elif addr in host.network:
    print("publish")
else:
    print("private")
PY
)
	if [[ "$mode" == "self" ]]; then
		fail "guest address ${GUEST_IP} is this Proxmox host" \
			"Pick another address on ${cidr}."
	fi
	if [[ -n "$old_ip" && ( "$old_ip" != "$GUEST_IP" || "$old_br" != "$BRIDGE" || "$mode" != "publish" ) ]]; then
		/usr/local/sbin/solaris-lan-apply --drop "$VMID" "$old_ip" "$old_br"
	fi
	if [[ "$mode" == "publish" ]]; then
		mkdir -p "$LAN_DIR"
		printf 'IP=%s\nBRIDGE=%s\n' "$GUEST_IP" "$BRIDGE" > "$state"
		if [[ -n "$old_ip" && "$old_ip" != "$GUEST_IP" && -f "/etc/pve/qemu-server/${VMID}.conf" ]]; then
			echo "VM ${VMID} keeps the address installed in Solaris until that guest is changed or reinstalled."
		fi
	else
		rm -f "$state"
		if [[ "$mode" == "direct" ]]; then
			echo "LAN route          ${GUEST_IP} is on ${BRIDGE}, the host network"
		else
			echo "LAN route          ${GUEST_IP} stays on ${BRIDGE}"
		fi
	fi
	/usr/local/sbin/solaris-lan-apply
}

patch_cmd() {
	need_root
	preflight patch
	echo "Packages"
	ensure_packages
	ensure_payload
	LOG=/var/log/solaris-host/patch.log
	: > "$LOG"
	local changed=0

	echo "Patches"
	if [[ "$REFRESH" == 0 ]] && qemuserver_patched; then
		echo "already patched    QemuServer.pm"
	else
		echo "patching           QemuServer.pm"
		divert_file /usr/share/perl5/PVE/QemuServer.pm
		if ! python3 "$PAYLOAD/lib/patch_qemuserver.py" /usr/share/perl5/PVE/QemuServer.pm | tee -a "$LOG"; then
		fail "QemuServer.pm patch" \
			"qemu-server $(pkg_ver qemu-server)" \
			"The patch matches qemu-server 9.2.14+wsh2." \
			"After a newer wsh package, run: ./solaris.sh patch --refresh" \
			"If --refresh fails, that package no longer has the same drive and serial code."
	fi
	if ! perl -c /usr/share/perl5/PVE/QemuServer.pm >>"$LOG" 2>&1; then
		fail "perl -c /usr/share/perl5/PVE/QemuServer.pm" \
			"The patched file is not valid Perl. Restore the package copy:" \
			"  cp -a /usr/share/perl5/PVE/QemuServer.pm.wsh-dist /usr/share/perl5/PVE/QemuServer.pm"
		fi
		changed=1
	fi

	local cstate
	cstate=$(cmd646_state /usr/bin/qemu-system-sparc64)
	if [[ "$REFRESH" == 0 && "$cstate" == "patched" ]]; then
		echo "already patched    CMD646 interrupt and PIO disk"
	else
		echo "patching           CMD646 interrupt and PIO disk"
		divert_file /usr/bin/qemu-system-sparc64
		if ! python3 "$PAYLOAD/lib/patch_cmd646.py" /usr/bin/qemu-system-sparc64 | tee -a "$LOG"; then
		fail "CMD646 interrupt patch" \
			"Installed $(pkg_ver pve-qemu-kvm)" \
			"This byte patch matches pve-qemu-kvm 11.1.3-1+wsh2 only." \
			"Do not replace the binary with a qemu you built yourself; Proxmox rejects that version string." \
			"State of this file: $(cmd646_state /usr/bin/qemu-system-sparc64)"
	fi
		chmod 755 /usr/bin/qemu-system-sparc64
		changed=1
	fi
	local qver
	qver=$(/usr/bin/qemu-system-sparc64 --version | head -1 || true)
	echo "$qver"
	if [[ "$qver" != QEMU*emulator\ version*pve-qemu-kvm* ]]; then
		fail "QEMU version string was rejected" \
			"Got: ${qver:-no output}" \
			"Proxmox only starts a binary whose version line contains pve-qemu-kvm."
	fi

	local commit=e5ac46dd24e6216c36aa80462af25457e7029440
	local src=/var/lib/solaris-host/src/openbios
	local stamp=/var/lib/solaris-host/openbios.stamp
	local blog=/var/log/solaris-host/openbios.log
	mkdir -p /var/lib/solaris-host/src
	if [[ "$REFRESH" == 1 || ! -f "$stamp" || "$(cat "$stamp")" != "$commit" ]]; then
		echo "patching           OpenBIOS"
		if [[ ! -d "$src/.git" ]]; then
			git clone https://github.com/openbios/openbios.git "$src" >"$blog" 2>&1 || fail "git clone openbios" \
				"Could not clone https://github.com/openbios/openbios.git" \
				"Log: $blog"
		fi
		git -C "$src" fetch origin >"$blog" 2>&1 || fail "git fetch openbios" "Log: $blog"
		git -C "$src" checkout "$commit" >>"$blog" 2>&1 || fail "git checkout $commit" \
			"That commit is the OpenBIOS revision these patches apply to." \
			"Log: $blog"
		git -C "$src" checkout -- . >>"$blog" 2>&1
		git -C "$src" clean -fd -e obj-sparc64 >>"$blog" 2>&1
		if ! patch -p1 --forward --batch -d "$src" < "$PAYLOAD/patches/openbios-solaris.patch" >>"$blog" 2>&1; then
			fail "OpenBIOS patch did not apply" \
				"Source is $src at $commit." \
				"Log: $blog"
		fi
		( cd "$src" && ./config/scripts/switch-arch builtin-sparc64 ) >>"$blog" 2>&1 || fail "OpenBIOS configure" \
			"switch-arch builtin-sparc64 failed. gcc-sparc64-linux-gnu must be installed." \
			"Log: $blog"
		make -C "$src/obj-sparc64" -j"$(nproc)" >>"$blog" 2>&1 || fail "OpenBIOS build" \
			"Log: $blog"
		if [[ ! -f "$src/obj-sparc64/openbios-builtin.elf" ]]; then
			fail "OpenBIOS build produced no openbios-builtin.elf" "Log: $blog"
		fi
		divert_file /usr/share/kvm/openbios-sparc64
		cp -f "$src/obj-sparc64/openbios-builtin.elf" /usr/share/kvm/openbios-sparc64
		chmod 644 /usr/share/kvm/openbios-sparc64
		echo "$commit" > "$stamp"
		echo "patched            OpenBIOS ($(wc -c < /usr/share/kvm/openbios-sparc64) bytes)"
		changed=1
	else
		echo "already patched    OpenBIOS $(cat "$stamp")"
	fi

	if [[ "$REFRESH" == 0 ]] && serial_proxy_ok; then
		echo "already patched    serial proxy"
	else
		echo "patching           serial proxy"
		install -m 0755 "$PAYLOAD/files/sparc-serial-proxy.py" /usr/local/sbin/sparc-serial-proxy.py
		install -m 0644 "$PAYLOAD/files/sparc-serial-proxy.service" /etc/systemd/system/sparc-serial-proxy.service
		systemctl daemon-reload
		systemctl enable sparc-serial-proxy.service
		systemctl restart sparc-serial-proxy.service || fail "sparc-serial-proxy did not start" \
			"systemctl status sparc-serial-proxy.service --no-pager"
		changed=1
	fi
	if [[ "$changed" == 1 ]]; then
		systemctl try-restart pvedaemon.service pveproxy.service || true
	fi

	if ! patches_applied; then
		fail "patch finished but status still shows a missing piece" \
			"Run: ./solaris.sh status"
	fi
	echo "LAN"
	install_lan_helper
	/usr/local/sbin/solaris-lan-apply
	echo ""
	if [[ "$changed" == 0 ]]; then
		echo "Already patched. Nothing to do."
	else
		echo "Patch complete."
	fi
	echo "Create a guest with:"
	echo "  ./solaris.sh vm --iso /path/to/sol-10-u11-ga-sparc-dvd.iso --vmid ${VMID} --start"
}

require_patched() {
	local missing
	missing=$(missing_wsh || true)
	if [[ -n "$missing" ]] || ! patches_applied; then
		echo "This node is not patched for Solaris yet."
		if [[ -n "$missing" ]]; then
			echo "$missing"
		fi
		echo "Run:"
		echo "  ./solaris.sh patch"
		exit 2
	fi
}

mark_block() {
	local file=$1
	local body=$2
	touch "$file"
	python3 - "$file" "$body" << 'PY'
import pathlib, sys
path, body = sys.argv[1], sys.argv[2]
text = pathlib.Path(path).read_text() if pathlib.Path(path).exists() else ""
begin, end = "# BEGIN solaris-host\n", "# END solaris-host\n"
block = begin + body.rstrip("\n") + "\n" + end
if begin in text and end in text:
    pre, rest = text.split(begin, 1)
    _, post = rest.split(end, 1)
    text = pre + block + post
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += block
pathlib.Path(path).write_text(text)
PY
}

place_iso() {
	if [[ ! -f "$ISO" ]]; then
		fail "ISO not found: ${ISO}" \
			"Pass the Solaris 10 sparc DVD:" \
			"  ./solaris.sh $CMD --iso /path/to/sol-10-u11-ga-sparc-dvd.iso"
	fi
	local base dest
	base=$(basename "$ISO")
	dest="/var/lib/vz/template/iso/${base}"
	mkdir -p /var/lib/vz/template/iso
	if [[ "$ISO" != "$dest" ]]; then
		cp -f "$ISO" "$dest" || fail "could not copy the ISO into /var/lib/vz/template/iso" \
			"Source: $ISO" \
			"The Proxmox ISO store must be writable."
		ISO=$dest
	fi
}

setup_jumpstart() {
	if [[ -f /etc/ethers ]]; then
		local wire_owner mac_owner
		wire_owner=$(awk 'tolower($1)=="52:54:00:12:34:56" {print $2; exit}' /etc/ethers)
		if [[ -n "$wire_owner" && "$wire_owner" != "$HOSTNAME" ]]; then
			echo "Not creating this guest. Duplicate MAC:"
			echo "  - 52:54:00:12:34:56 is already JumpStart for ${wire_owner}."
			exit 2
		fi
		if [[ -n "$GUEST_MAC" ]]; then
			mac_owner=$(awk -v mac="$GUEST_MAC" 'tolower($1)==tolower(mac) {print $2; exit}' /etc/ethers)
			if [[ -n "$mac_owner" && "$mac_owner" != "$HOSTNAME" ]]; then
				echo "Not creating this guest. Duplicate MAC:"
				echo "  - ${GUEST_MAC} is already JumpStart for ${mac_owner}."
				exit 2
			fi
		fi
	fi
	if [[ ! "$HOSTNAME" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
		fail "--hostname must be a DNS name" "Got: ${HOSTNAME}"
	fi
	local jump_miss
	jump_miss=$(missing_debs "${JUMP_PACKAGES[@]}")
	if [[ -n "$jump_miss" ]]; then
		echo "JumpStart packages are missing:"
		echo "$jump_miss"
		echo "Run: ./solaris.sh patch"
		exit 2
	fi
	place_iso
	if ! grep -q "^iface ${BRIDGE} " /etc/network/interfaces \
		&& ! grep -Rqs "^iface ${BRIDGE} " /etc/network/interfaces.d 2>/dev/null; then
		local prefix main cidr overlap
		prefix=$(python3 - "$NETMASK" << 'PY'
import sys
parts = sys.argv[1].split(".")
if len(parts) != 4:
    raise SystemExit(1)
try:
    nums = [int(p) for p in parts]
except ValueError:
    raise SystemExit(1)
if any(n < 0 or n > 255 for n in nums):
    raise SystemExit(1)
bits = "{:032b}".format((nums[0] << 24) | (nums[1] << 16) | (nums[2] << 8) | nums[3])
if "01" in bits:
    raise SystemExit(1)
print(bits.count("1"))
PY
) || fail "--netmask must be a contiguous dotted mask" "Got: ${NETMASK}"
		main=$(ip -4 route show default | awk 'NR==1 { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
		cidr=""
		if [[ -n "$main" ]]; then
			cidr=$(ip -4 -o addr show dev "$main" | awk 'NR==1 { print $4 }')
		fi
		overlap=$(python3 - "$GATEWAY" "$cidr" << 'PY'
import ipaddress, sys
gateway, cidr = sys.argv[1], sys.argv[2]
if not cidr:
    print("ok")
    raise SystemExit(0)
host = ipaddress.ip_interface(cidr)
gw = ipaddress.ip_address(gateway)
print("overlap" if gw == host.ip or gw in host.network else "ok")
PY
)
		if [[ "$overlap" == "overlap" ]]; then
			fail "--gateway ${GATEWAY} is on this host's network ${cidr}" \
				"That address is already reached through ${main}." \
				"Attach the guest to the bridge on that network, or use a private gateway such as 10.10.10.1."
		fi
		cat >> /etc/network/interfaces << EOF

auto ${BRIDGE}
iface ${BRIDGE} inet static
    address ${GATEWAY}/${prefix}
    bridge-ports none
    bridge-stp off
    bridge-fd 0
EOF
		ifup "$BRIDGE" || fail "could not bring up ${BRIDGE}" \
			"The address ${GATEWAY}/${prefix} was added to /etc/network/interfaces." \
			"ifup ${BRIDGE} failed. Fix the bridge, then rerun this command."
	fi

	if [[ -f /etc/default/rpcbind ]] && grep -q -- '-r' /etc/default/rpcbind; then
		:
	else
		printf '\nOPTIONS="-w -r"\n' >> /etc/default/rpcbind
	fi
	cat > /etc/default/rarpd << EOF
OPTS="-e -v ${BRIDGE}"
EOF
	mkdir -p /etc/systemd/system/bootparamd.service.d
	cat > /etc/systemd/system/bootparamd.service.d/router.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/rpc.bootparamd -s -r ${GATEWAY}
EOF
	systemctl daemon-reload

	mark_block /etc/exports "/export/jumpstart ${EXPORT_NET}(ro,sync,no_subtree_check,no_root_squash,insecure)
/mnt/soliso ${EXPORT_NET}(ro,sync,no_subtree_check,no_root_squash,insecure,fsid=10)"

	if [[ -z "$JUMPSTART" ]]; then
		JUMPSTART=$HOSTNAME
	fi
	if [[ ! "$JUMPSTART" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
		fail "--jumpstart must be a directory name" "Got: ${JUMPSTART}"
	fi
	local jump_dir="/export/jumpstart/${JUMPSTART}"
	local client_dir="${jump_dir}/clients/${HOSTNAME}"
	mkdir -p "$client_dir" /mnt/soliso
	if [[ ! -f "${jump_dir}/profile" && -f /export/jumpstart/profile && "$jump_dir" != "/export/jumpstart" ]] \
		&& [[ -f /export/jumpstart/sysidcfg ]] && grep -q "hostname=${JUMPSTART} " /export/jumpstart/sysidcfg; then
		echo "Copying the existing JumpStart in /export/jumpstart into ${jump_dir}"
		local old
		for old in profile rules rules.ok finishssh mountcd; do
			if [[ -f "/export/jumpstart/${old}" && ! -f "${jump_dir}/${old}" ]]; then
				cp -p "/export/jumpstart/${old}" "${jump_dir}/${old}"
			fi
		done
	fi
	local item swap_mb home_mb home_line disk_mb
	swap_mb=${SWAP_MB:-$MEMORY}
	home_mb=${HOME_MB:-0}
	[[ "$DISK_GB" =~ ^[0-9]+$ ]] || fail "--disk is the whole disk in GB" "Got: ${DISK_GB}"
	[[ "$MEMORY" =~ ^[0-9]+$ ]] || fail "--memory is RAM in MB" "Got: ${MEMORY}"
	[[ "$swap_mb" =~ ^[0-9]+$ ]] || fail "--swap is the swap slice in MB" "Got: ${swap_mb}"
	[[ "$home_mb" =~ ^[0-9]+$ ]] || fail "--home is the /export/home slice in MB" "Got: ${home_mb}"
	disk_mb=$((DISK_GB * 1024))
	if (( disk_mb - swap_mb - home_mb < 4096 )); then
		fail "the disk is too small for these slices" \
			"Disk is ${DISK_GB} GB. Swap is ${swap_mb} MB. Home is ${home_mb} MB." \
			"/ needs at least 4096 MB of what remains."
	fi
	if [[ -f "${jump_dir}/profile" ]]; then
		echo "keeping            ${jump_dir}/profile"
		if [[ -n "$SWAP_MB" || -n "$HOME_MB" ]]; then
			echo "warning: --swap and --home do not change an existing profile."
			echo "Edit ${jump_dir}/profile, or delete it and run this command again."
		fi
	else
		if [[ "$home_mb" == 0 ]]; then
			home_line=""
		else
			home_line="filesys         rootdisk.s7 ${home_mb} /export/home"
		fi
		sed -e "s/@SWAP@/${swap_mb}/g" -e "s|@HOME@|${home_line}|g" \
			"$PAYLOAD/jumpstart/profile.in" > "${jump_dir}/profile"
		echo "created            ${jump_dir}/profile"
		echo "  swap ${swap_mb} MB, / is the rest of the ${DISK_GB} GB disk"
		if [[ "$home_mb" != 0 ]]; then
			echo "  /export/home ${home_mb} MB"
		fi
	fi
	for item in rules finishssh; do
		if [[ -f "${jump_dir}/${item}" ]]; then
			echo "keeping            ${jump_dir}/${item}"
			if [[ "$item" == "finishssh" ]] && ! grep -q 'uata-pio' "${jump_dir}/finishssh"; then
				echo "warning: ${jump_dir}/finishssh does not force PIO or install the shutdown key."
				echo "Delete that file and run this command again to write the current finish script."
			fi
		else
			cp "$PAYLOAD/jumpstart/${item}" "${jump_dir}/${item}"
			echo "created            ${jump_dir}/${item}"
		fi
	done
	if [[ -f "${jump_dir}/mountcd" ]]; then
		echo "keeping            ${jump_dir}/mountcd"
	else
		sed -e "s/@GATEWAY@/${GATEWAY}/g" "$PAYLOAD/jumpstart/mountcd.in" > "${jump_dir}/mountcd"
		echo "created            ${jump_dir}/mountcd"
	fi
	if [[ ! -f "${client_dir}/sysidcfg" && -f /export/jumpstart/sysidcfg ]] && grep -q "hostname=${HOSTNAME} " /export/jumpstart/sysidcfg; then
		cp -p /export/jumpstart/sysidcfg "${client_dir}/sysidcfg"
		echo "copied             /export/jumpstart/sysidcfg"
	fi
	if [[ -f "${client_dir}/sysidcfg" ]]; then
		echo "keeping            ${client_dir}/sysidcfg"
		if ! grep -q "${GUEST_IP}" "${client_dir}/sysidcfg"; then
			echo "warning: ${client_dir}/sysidcfg does not contain ${GUEST_IP}."
			echo "Edit that file, or delete it and run this command again to recreate it."
		fi
	else
		sed -e "s/@HOSTNAME@/${HOSTNAME}/g" \
			-e "s/@GUEST_IP@/${GUEST_IP}/g" \
			-e "s/@NETMASK@/${NETMASK}/g" \
			-e "s/@GATEWAY@/${GATEWAY}/g" \
			"$PAYLOAD/jumpstart/sysidcfg.in" > "${client_dir}/sysidcfg"
		echo "created            ${client_dir}/sysidcfg"
	fi
	chmod 755 "${jump_dir}/mountcd" "${jump_dir}/finishssh"
	chmod 644 "${jump_dir}/profile" "${jump_dir}/rules" "${client_dir}/sysidcfg"
	python3 - "${jump_dir}/rules" "${jump_dir}/rules.ok" << 'PY'
import pathlib, sys
rules = pathlib.Path(sys.argv[1]).read_bytes()
if not rules.endswith(b"\n"):
    rules += b"\n"
checksum = sum(rules)
pathlib.Path(sys.argv[2]).write_bytes(rules + f"# version=2 checksum={checksum}\n".encode())
print(f"rules.ok           checksum={checksum}")
PY
	chmod 644 "${jump_dir}/rules.ok"
	python3 - "$HOSTNAME" "$GUEST_IP" "$GATEWAY" "$IDPROM_MAC" "$GUEST_MAC" "$JUMPSTART" << 'PY'
import pathlib, sys
host, ip, gateway, idprom, sunhme, jump = sys.argv[1:]

def load(path):
    file = pathlib.Path(path)
    text = file.read_text() if file.exists() else ""
    begin, end = "# BEGIN solaris-host\n", "# END solaris-host\n"
    if begin in text and end in text:
        pre, rest = text.split(begin, 1)
        body, post = rest.split(end, 1)
        return pre, [ln for ln in body.splitlines() if ln.strip()], post
    if text and not text.endswith("\n"):
        text += "\n"
    return text, [], ""

def save(path, pre, lines, post):
    body = ("\n".join(lines) + "\n") if lines else ""
    pathlib.Path(path).write_text(pre + "# BEGIN solaris-host\n" + body + "# END solaris-host\n" + post)

pre, lines, post = load("/etc/hosts")
gateway_line = f"{gateway} jumpstart"
kept = [ln for ln in lines if ln != gateway_line and ln.split()[-1:] != [host]]
save("/etc/hosts", pre, [gateway_line, f"{ip} {host}"] + kept, post)

pre, lines, post = load("/etc/ethers")
macs = []
seen = set()
def add_mac(mac):
    if mac and mac.lower() not in seen:
        seen.add(mac.lower())
        macs.append(f"{mac} {host}")
add_mac(sunhme)
add_mac(idprom)
# OpenBIOS RARP uses the QEMU idprom, which stays this address.
add_mac("52:54:00:12:34:56")
if idprom.lower() != "52:54:00:12:34:56":
    print("warning: --idprom does not change the address on the wire. RARP still uses 52:54:00:12:34:56.")
for ln in lines:
    parts = ln.split()
    if len(parts) >= 2 and parts[0].lower() == "52:54:00:12:34:56" and parts[-1] != host:
        print(f"Not creating this guest. Duplicate MAC:")
        print(f"  - 52:54:00:12:34:56 is already JumpStart for {parts[-1]}.")
        raise SystemExit(2)
kept = [ln for ln in lines if ln.split()[-1:] != [host]]
save("/etc/ethers", pre, macs + kept, post)

pre, lines, post = load("/etc/bootparams")
line = f"{host} sysid_config=jumpstart:/export/jumpstart/{jump}/clients/{host} install_config=jumpstart:/export/jumpstart/{jump}"
kept = [ln for ln in lines if ln.split()[:1] != [host]]
save("/etc/bootparams", pre, [line] + kept, post)
names = sorted({ln.split()[0] for ln in ([line] + kept) if ln.split()})
print("jumpstart clients: " + ", ".join(names))
PY

	local fstab_line="${ISO} /mnt/soliso iso9660 loop,ro,nofail 0 0"
	grep -qF "$ISO" /etc/fstab || echo "$fstab_line" >> /etc/fstab
	if ! mountpoint -q /mnt/soliso; then
		mount /mnt/soliso || fail "could not loop-mount the DVD on /mnt/soliso" \
			"Line in /etc/fstab: ${fstab_line}" \
			"Check the ISO is a real DVD image: file ${ISO}"
	fi
	systemctl enable rpcbind rarpd bootparamd nfs-server
	systemctl restart rpcbind || fail "rpcbind did not start" "It must be running with -r or Solaris bootparams are dropped."
	systemctl restart rarpd || fail "rarpd did not start" \
		"rarpd exits when ${BRIDGE} has more than one address." \
		"Check: ip addr show ${BRIDGE}"
	systemctl restart bootparamd || fail "bootparamd did not start" "systemctl status bootparamd --no-pager"
	systemctl restart nfs-server || fail "nfs-server did not start" "exportfs -v"
	ensure_shutdown_key "$jump_dir"
	echo "JumpStart ${JUMPSTART} for ${HOSTNAME} (${GUEST_IP})"
	echo "  ${jump_dir}/profile"
	echo "  ${jump_dir}/rules"
	echo "  ${client_dir}/sysidcfg"
	echo "Another VM can use this JumpStart without replacing those files:"
	echo "  ./solaris.sh vm --iso ${ISO} --vmid <id> --name <name> --hostname <name> --jumpstart ${JUMPSTART} --ip <address> --netmask ${NETMASK} --gateway ${GATEWAY} --bridge ${BRIDGE} --mac <sunhme-mac> --idprom ${IDPROM_MAC} --disk ${DISK_GB} --swap ${SWAP_MB:-$MEMORY} --home ${HOME_MB:-0} --memory ${MEMORY} --storage ${STORAGE} --export-net ${EXPORT_NET} --start"
}

mac_same() {
	local a=${1^^} b=${2^^}
	[[ -n "$a" && "$a" == "$b" ]]
}

refuse_duplicate_mac() {
	local wire=52:54:00:12:34:56
	local -a problems=()
	local f id arch mac name line emac ehost
	shopt -s nullglob
	for f in /etc/pve/qemu-server/*.conf; do
		id=$(basename "$f" .conf)
		[[ "$id" == "$VMID" ]] && continue
		arch=$(sed -n 's/^arch: //p' "$f" | head -1)
		mac=$(sed -n 's/^net0: sunhme=\([^,]*\).*/\1/p' "$f" | head -1)
		name=$(sed -n 's/^name: //p' "$f" | head -1)
		if [[ "$arch" == "sparc64" ]]; then
			problems+=("VM ${id} (${name:-unnamed}) already uses wire MAC ${wire}. Every SPARC guest sends that address.")
		fi
		if mac_same "$GUEST_MAC" "$mac"; then
			problems+=("VM ${id} (${name:-unnamed}) already uses sunhme MAC ${mac}.")
		fi
	done
	shopt -u nullglob
	if [[ -f /etc/ethers ]]; then
		while read -r line; do
			[[ "$line" =~ ^[[:space:]]*# ]] && continue
			emac=${line%% *}
			ehost=${line#* }
			ehost=${ehost%% *}
			[[ -z "$emac" || -z "$ehost" ]] && continue
			if mac_same "$emac" "$wire" && [[ "$ehost" != "$HOSTNAME" ]]; then
				problems+=("${wire} is already JumpStart for ${ehost}.")
			fi
			if mac_same "$emac" "$GUEST_MAC" && [[ "$ehost" != "$HOSTNAME" ]]; then
				problems+=("${GUEST_MAC} is already JumpStart for ${ehost}.")
			fi
		done < /etc/ethers
	fi
	if [[ ${#problems[@]} -eq 0 ]]; then
		return 0
	fi
	echo "Not creating this guest. Duplicate MAC:"
	local item
	for item in "${problems[@]}"; do
		echo "  - $item"
	done
	exit 2
}

other_sparc_running() {
	local f id name
	shopt -s nullglob
	for f in /etc/pve/qemu-server/*.conf; do
		id=$(basename "$f" .conf)
		[[ "$id" == "$VMID" ]] && continue
		grep -q '^arch: sparc64$' "$f" || continue
		if qm status "$id" 2>/dev/null | grep -q running; then
			name=$(sed -n 's/^name: //p' "$f" | head -1)
			echo "Not starting VM ${VMID}. Duplicate MAC:"
			echo "  - VM ${id} (${name:-unnamed}) is running with wire MAC 52:54:00:12:34:56."
			shopt -u nullglob
			return 0
		fi
	done
	shopt -u nullglob
	return 1
}

ensure_shutdown_key() {
	local jump_dir=$1
	mkdir -p /root/.ssh
	chmod 700 /root/.ssh
	if [[ ! -s /root/.ssh/sol-shutdown || ! -s /root/.ssh/sol-shutdown.pub ]]; then
		ssh-keygen -q -t rsa -b 2048 -N '' -f /root/.ssh/sol-shutdown -C sol-shutdown
	fi
	chmod 600 /root/.ssh/sol-shutdown
	chmod 644 /root/.ssh/sol-shutdown.pub
	cp /root/.ssh/sol-shutdown.pub "${jump_dir}/shutdown.pub"
	chmod 644 "${jump_dir}/shutdown.pub"
	echo "shutdown key       ${jump_dir}/shutdown.pub"
}

ensure_snippets() {
	local content
	content=$(awk '
		$1 == "dir:" && $2 == "local" { inlocal = 1; next }
		inlocal && $1 == "content" { print $2; exit }
		inlocal && $0 !~ /^[[:space:]]/ { exit }
	' /etc/pve/storage.cfg)
	[[ -n "$content" ]] || fail "storage local has no content line" "/etc/pve/storage.cfg"
	case ",${content}," in
	*,snippets,*) ;;
	*) pvesm set local --content "${content},snippets" ;;
	esac
	mkdir -p /var/lib/vz/snippets
}

write_shutdown_hook() {
	local dest="/var/lib/vz/snippets/sol-shutdown-${VMID}.sh"
	sed -e "s/__VMID__/${VMID}/g" -e "s/__GUEST_IP__/${GUEST_IP}/g" > "$dest" << 'HOOK'
#!/bin/bash
# Proxmox Shutdown sends a power signal this SPARC guest ignores.
# Ask Solaris to halt, then wait until the guest has powered off.
VMID=__VMID__
PHASE="$2"
LOG=/var/log/sol-shutdown-${VMID}.log
[ "$1" = "$VMID" ] || exit 0
[ "$PHASE" = "pre-stop" ] || exit 0

echo "$(date -u +%H:%M:%S) pre-stop" >> "$LOG"
if ! ssh -i /root/.ssh/sol-shutdown -o BatchMode=yes -o ConnectTimeout=20 \
	-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	-o KexAlgorithms=+diffie-hellman-group14-sha1 \
	-o HostKeyAlgorithms=+ssh-rsa \
	-o PubkeyAcceptedAlgorithms=ssh-rsa \
	root@__GUEST_IP__ "shutdown -y -g0 -i5" >> "$LOG" 2>&1; then
	echo "$(date -u +%H:%M:%S) ssh failed, leaving stop to qemu" >> "$LOG"
	exit 0
fi

python3 - << 'QMP'
import os, socket, json, time, subprocess
vmid = "__VMID__"
log = open("/var/log/sol-shutdown-%s.log" % vmid, "a")
def say(msg):
    log.write(time.strftime("%H:%M:%S ") + msg + "\n")
    log.flush()
def qm_running():
    r = subprocess.run(["qm", "status", vmid], capture_output=True, text=True)
    return "running" in r.stdout
def qmp_status():
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect("/var/run/qemu-server/%s.qmp" % vmid)
    except OSError:
        return "gone"
    def readmsg():
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        return data
    try:
        readmsg()
        s.sendall(b'{"execute":"qmp_capabilities"}\n')
        readmsg()
        s.sendall(b'{"execute":"query-status"}\n')
        msg = json.loads(readmsg().decode())
    except Exception:
        return "unknown"
    finally:
        s.close()
    return msg.get("return", {}).get("status", "unknown")

deadline = time.time() + 180
st = "running"
while time.time() < deadline:
    if not qm_running():
        say("qemu already stopped")
        raise SystemExit(0)
    st = qmp_status()
    if st in ("shutdown", "gone"):
        break
    time.sleep(2)
say("after wait status=%s running=%s" % (st, qm_running()))
if st == "shutdown":
    try:
        pid = int(open("/run/qemu-server/%s.pid" % vmid).read().strip())
    except Exception:
        pid = 0
    if pid:
        say("guest powered off, stopping qemu %s" % pid)
        try:
            os.kill(pid, 15)
        except OSError as exc:
            say("kill failed %s" % exc)
    end = time.time() + 20
    while time.time() < end and qm_running():
        time.sleep(1)
    say("final running=%s" % qm_running())
QMP
exit 0
HOOK
	# The Python block is quoted, so replace the id left inside it.
	sed -i "s/__VMID__/${VMID}/g" "$dest"
	chmod 755 "$dest"
	echo "shutdown hook      ${dest}"
}

ensure_shutdown_hook() {
	local conf="/etc/pve/qemu-server/${VMID}.conf"
	[[ -f "$conf" ]] || return 0
	ensure_snippets
	if grep -q '^hookscript:' "$conf"; then
		echo "keeping            hookscript on VM ${VMID}"
		return 0
	fi
	write_shutdown_hook
	qm set "$VMID" --hookscript "local:snippets/sol-shutdown-${VMID}.sh" \
		|| fail "could not set the shutdown hook on VM ${VMID}" \
			"qm set ${VMID} --hookscript local:snippets/sol-shutdown-${VMID}.sh"
}

create_vm() {
	local conf="/etc/pve/qemu-server/${VMID}.conf"
	local vol="vm-${VMID}-disk-0"
	if [[ ! "$VMID" =~ ^[0-9]+$ ]]; then
		fail "--vmid must be a number" "Got: ${VMID}"
	fi
	if [[ -e "$conf" ]]; then
		echo "VM ${VMID} already exists. Its config was not changed."
		if [[ -z "$GUEST_MAC" ]]; then
			GUEST_MAC=$(sed -n 's/^net0: sunhme=\([^,]*\).*/\1/p' "$conf" | head -1)
		fi
		return 0
	fi
	if [[ -z "$GUEST_MAC" ]]; then
		GUEST_MAC=$(printf 'BC:24:11:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
	fi
	refuse_duplicate_mac
	place_iso
	if ! pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$STORAGE"; then
		fail "storage ${STORAGE} is not on this node" \
			"Run: pvesm status" \
			"Pass the storage that is listed, for example: --storage local-lvm"
	fi
	if ! pvesm list "$STORAGE" | awk '{print $1}' | grep -q "vm-${VMID}-disk-0"; then
		pvesm alloc "$STORAGE" "$VMID" "$vol" "${DISK_GB}G" || fail "could not allocate ${DISK_GB}G on ${STORAGE}" \
			"pvesm alloc ${STORAGE} ${VMID} ${vol} ${DISK_GB}G"
	fi
	local base iso_vol
	base=$(basename "$ISO")
	iso_vol="local:iso/${base}"
	python3 - "$VMID" "$NAME" "$STORAGE" "$vol" "$BRIDGE" "$GUEST_MAC" \
		"$iso_vol" "$MEMORY" "$DISK_GB" << 'PY'
import pathlib, sys
vmid, name, storage, vol, bridge, mac, iso_vol, memory, disk = sys.argv[1:]
lines = [
    "arch: sparc64",
    "args: -prom-env input-device=ttya -prom-env output-device=ttya -prom-env 'boot-command=s\" /pci@1f,0/pci@1,1/ide@3/dad@0,0:a\" open-dev dup if close-dev s\" boot /pci@1f,0/pci@1,1/ide@3/dad@0,0:a\" evaluate else drop s\" boot /pci@1f,0/pci@1,1/ide@3/cdrom@1,0:f - install\" evaluate then'",
    "balloon: 0",
    "bios: openbios-sparc64",
    "boot: order=scsi0;scsi2",
    "cores: 1",
    "kvm: 0",
    f"memory: {memory}",
    f"name: {name}",
    f"net0: sunhme={mac},bridge={bridge},firewall=0",
    "numa: 0",
    "ostype: solaris",
    f"scsi0: {storage}:{vol},size={disk}G",
    f"scsi2: {iso_vol},media=cdrom",
    "serial0: socket",
    "sockets: 1",
    "tablet: 0",
    "vga: serial0",
    "vmgenid: 0",
]
path = pathlib.Path(f"/etc/pve/qemu-server/{vmid}.conf")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(lines) + "\n")
print(path)
PY
	echo "VM ${VMID} (${NAME}) created. Disk ${DISK_GB}G on ${STORAGE}. sunhme MAC ${GUEST_MAC}."
	echo "An empty disk boots the CD and JumpStart runs. After Solaris is installed, this VM boots the disk."
}

vm_cmd() {
	need_root
	require_patched
	ensure_payload
	create_vm
	setup_jumpstart
	ensure_shutdown_hook
	publish_guest_lan
	point_hook_at_guest_ip
	if [[ "$DO_START" == 1 ]]; then
		if qm status "$VMID" 2>/dev/null | grep -q running; then
			echo "VM ${VMID} is already running."
		elif other_sparc_running; then
			exit 2
		else
			qm start "$VMID" || fail "qm start ${VMID}" \
				"qm start ${VMID}" \
				"A running guest keeps the previous QEMU until it is started again."
			echo "VM ${VMID} is starting. The first boot takes several minutes."
			echo "SSH is enabled at boot and answers after the network and filesystems are up."
		fi
	fi
}

jumpstart_cmd() {
	need_root
	require_patched
	ensure_payload
	setup_jumpstart
	publish_guest_lan
	point_hook_at_guest_ip
}

if [[ "${SOLARIS_APPLY_LAN:-0}" == 1 ]]; then
	need_root
	install_lan_helper
	/usr/local/sbin/solaris-lan-apply
	exit 0
fi

case "${CMD}" in
"")
	status_cmd
	;;
status)
	status_cmd
	;;
patch)
	patch_cmd
	;;
vm)
	vm_cmd
	;;
jumpstart)
	jumpstart_cmd
	;;
*)
	echo "Unknown command: ${CMD}"
	usage
	exit 1
	;;
esac
