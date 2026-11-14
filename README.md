# proxmox-solaris

Solaris 10 SPARC on a Proxmox node.

Proxmox itself has no sparc64 support. That support comes from **[wsh-pve](https://github.com/hwinther/wsh-pve)** (wsh). wsh-pve publishes patched `pve-manager`, `qemu-server`, and `pve-qemu-kvm` at [debian.wshosting.no](https://debian.wshosting.no/). `solaris.sh` installs those packages when they are missing, then finishes the node so a guest can install and keep running.

The guest process is **`qemu-system-sparc64`**. The machine is `sun4u` and KVM is off, so QEMU emulates the SPARC CPU. That machine has one CPU. `2048` MB is the memory this setup runs. OpenBIOS starts at `4096` MB and does not boot at `5120` MB or above, so leave `--memory` at `2048`.

On a patched node the script also provides:

- a QEMU fix so the CMD646 disk stays on PIO (DMA reads never finish)
- an OpenBIOS build that can boot the installed disk
- a serial console on `serial0`
- one JumpStart directory per OS name, with SSH installed and enabled at boot
- a shutdown hook per VM, so Proxmox Shutdown halts Solaris instead of cutting power
- a host route for each guest address that sits on the Proxmox host's own network

Run the script on the node as root. With no command, or with `status`, it only reports what is missing. There is no install command. `./solaris.sh install` tells you to run `patch`.

## Patch the node

```bash
./solaris.sh patch
```

`patch` is the only command the node needs. It installs a missing package and skips one that is already installed. It applies a missing fix and prints `already patched` for one that is already there. Run it again any time. A second run changes nothing and ends with `Already patched. Nothing to do.`

It warns before replacing `pve-manager`, `qemu-server`, or `pve-qemu-kvm`, and it stops first if this is not a Proxmox node, if `/etc/pve` is not mounted, or if apt is already running. A failure names the step, the log under `/var/log/solaris-host/`, and what to check.

Add `--refresh` only when the `qemu-system-sparc64` and OpenBIOS files should be copied and patched again:

```bash
./solaris.sh patch --refresh
```

A guest that is already running keeps its current QEMU until it is stopped and started again.

## Create a guest

`vm` creates one guest and its own JumpStart directory. The first run writes these files. A later run keeps them, including your edits. `rules.ok` is rebuilt from `rules` so the checksum still matches. `--swap` and `--home` are written into `profile` only when that file is created.

```text
/export/jumpstart/<name>/profile
/export/jumpstart/<name>/rules
/export/jumpstart/<name>/rules.ok
/export/jumpstart/<name>/finishssh
/export/jumpstart/<name>/mountcd
/export/jumpstart/<name>/clients/<hostname>/sysidcfg
```

The directory name defaults to the hostname.

`--disk 100` is the whole 100 GB disk. `--swap 2048` is the swap slice in MB. When `--swap` is omitted, the swap slice is `--memory` (2048 MB). `--home 10240` is a 10 GB `/export/home`. The rest of the disk is `/`. Slice 2 is the Solaris overlap of the whole disk and holds no files. Leave `--home` out and there is no separate home slice. `/` needs at least 4096 MB of what remains.

This example lists every `vm` option. The values are the defaults, except `--mac` (generated when omitted), `--home` (omit it for no home slice), and `--start`.

```bash
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
```

An empty disk has no boot block, so the VM boots the CD with `- install` and JumpStart runs. After Solaris is installed, the same VM boots the disk. The root password is `Sol10install`.

`--gateway` is this host's address on the guest network. JumpStart mounts its files from there. If `--bridge` does not exist, it is created at that address with `--netmask`. A bridge is not created on top of the network this host already uses. Use the bridge that already carries that network, or a private gateway such as `10.10.10.1`.

## A second guest

`qemu-system-sparc64` sends `52:54:00:12:34:56` for every guest. `--idprom` is recorded for RARP and does not change the address on the wire. A duplicate wire MAC, or a duplicate sunhme MAC, prints the conflict and creates nothing. `--start` also refuses to boot while another SPARC guest is running. Install and run one SPARC guest at a time.

```bash
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
```

Reusing a JumpStart directory follows the same rule. The profile stays, and the new guest is still refused while another SPARC guest has the wire MAC:

```bash
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
```

## JumpStart without a new VM

`jumpstart` adds or updates one client and does not create a VM. It does not take `--name`, `--storage`, or `--start`. `--vmid` is the existing guest whose shutdown hook and host route follow `--ip`.

```bash
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
```

An existing `finishssh` is kept. If it does not contain `uata-pio`, delete that file and run the command again. The current finish script patches the Solaris 10 Update 11 `uata` driver so the disk stays on PIO, copies the shutdown key into root's `authorized_keys`, and enables SSH at boot. The same key is reused if it already exists. Generating a new key would break an installed guest.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `--iso PATH` | `/var/lib/vz/template/iso/sol-10-u11-ga-sparc-dvd.iso` | Solaris 10 sparc DVD |
| `--vmid N` | `100` | VM id |
| `--name NAME` | `sol` | Proxmox VM name |
| `--hostname NAME` | `sol` | Solaris hostname and default JumpStart name |
| `--jumpstart NAME` | the hostname | Directory under `/export/jumpstart` |
| `--ip ADDR` | `10.10.10.10` | Guest address |
| `--netmask MASK` | `255.0.0.0` | Guest netmask |
| `--gateway ADDR` | `10.10.10.1` | This host's address on the guest network, and the JumpStart server |
| `--bridge NAME` | `vmbr1` | Bridge the guest NIC is attached to |
| `--mac MAC` | generated `BC:24:11:xx:xx:xx` | sunhme MAC shown to Solaris |
| `--idprom MAC` | `52:54:00:12:34:56` | Recorded for RARP. `qemu-system-sparc64` still sends `52:54:00:12:34:56` |
| `--disk GB` | `100` | Whole virtual disk in GB |
| `--swap MB` | `--memory` | Swap slice in MB, written only when `profile` is created |
| `--home MB` | none | Optional `/export/home` slice in MB |
| `--memory MB` | `2048` | RAM in MB. The guest still has 1 CPU |
| `--storage NAME` | `local-lvm` | Proxmox storage for the disk |
| `--export-net CIDR` | `10.10.10.0/24` | NFS clients allowed to mount JumpStart |
| `--start` | off | Boot the VM after `vm` |
| `--refresh` | off | With `patch` only. Re-copy `qemu-system-sparc64` and OpenBIOS and patch them again |

`./solaris.sh help` prints these commands and the same examples.

## Network

The default guest is `10.10.10.10/8` on `vmbr1`, with the host at `10.10.10.1`. That network exists only on the Proxmox node. SSH to it from the node:

```bash
ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    root@10.10.10.10
```

Solaris 10 offers those old algorithms. A current client refuses them until you add them back.

To reach the guest from other machines on the Proxmox host's own LAN, give `--ip` an address on that LAN and attach the guest to a bridge that is not the host's uplink. The host then answers ARP for that address and forwards it. Each guest gets its own `/32` route. A route for `192.168.1.181` does not replace the route for `192.168.1.180`. Changing `--ip` for one VM removes only that VM's old route. Passing `--ip` updates the host route and the shutdown hook. An installed Solaris system keeps its current address until you change it on the guest or reinstall.

A WiFi uplink cannot carry the guest's MAC. The access point accepts one client MAC, so the guest stays on its bridge and the host forwards.

## After the guest is up

JumpStart installs the SSH packages and enables `ssh` on every boot. The console can look ready a few minutes before port 22 answers, because `ssh` waits for the network and the local filesystems. The service starts on its own once those are up.

Use Proxmox **Shutdown**. The hook logs in with the shutdown key and runs `shutdown -y -g0 -i5`, then waits until `qemu-system-sparc64` has exited. **Stop** cuts power while Solaris is still running. The filesystem is left dirty, and the next boot can hang on the disk.

The first new VM gets `/var/lib/vz/snippets/sol-shutdown-<vmid>.sh`, filled in with that VM's number and `--ip`. A VM that already has a hook keeps it. If you change `--ip` later, the address inside that hook is updated.
