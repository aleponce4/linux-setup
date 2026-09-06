# If everything is gone, read this first

Written 2026-09-06 for a version of you who does not remember any of this. It assumes
nothing. Nothing in this file is secret; it only says *where* things are.

## What this machine was

`strix` — a Kubuntu workstation. Three separate disks, which is the whole reason recovery
is possible:

| Disk | What was on it |
|---|---|
| Samsung 990 PRO 1 TB NVMe | The operating system and home directory. **Assume this is the one that died.** |
| Samsung 860 EVO 500 GB SATA | `/data` — LIBS spectroscopy data, Onteko work, seed classification |
| **HGST 8 TB** | `/backup` — **the encrypted restic backups**, plus a 2 TB NTFS partition labelled `WINRESCUE` holding the original Windows-era files |

**The 8 TB HGST drive is the one that matters.** If you have that drive, you have your data.

## The one thing you need: the restic password

The backups are encrypted. Without the password they are permanently unreadable — there is
no reset, no recovery, no support line. It is 45 characters of random base64.

It was stored in two places:

1. **Bitwarden** — a password manager. It is an app and a website (bitwarden.com) that holds
   passwords behind one master password. Look for an entry named "restic backup password
   (strix)". If you no longer have the app, sign in at https://vault.bitwarden.com with the
   email and master password you used in 2026.
2. **`secrets.7z`** on the rescue drive, at `WINRESCUE/secrets.7z`. It is an encrypted 7-Zip
   archive. Its passphrase was also kept in Bitwarden, and originally in a plain file beside
   it called `secrets-passphrase.txt`.

If both are gone, the backups cannot be recovered. The data on `/data` and `WINRESCUE` is
*not* encrypted, so that is still readable directly.

## Getting the data back

Plug the 8 TB drive into any Linux machine.

```bash
sudo apt install restic
lsblk -f                                  # find the partition labelled "backup"
sudo mkdir -p /mnt/backup
sudo mount /dev/sdXN /mnt/backup          # the "backup" partition, NOT "WINRESCUE"

# what is in there
sudo restic -r /mnt/backup/restic snapshots        # prompts for the password

# restore the newest snapshot somewhere with room
sudo restic -r /mnt/backup/restic restore latest --target /mnt/somewhere-big

# or just one path
sudo restic -r /mnt/backup/restic restore latest --target /tmp/out --include /data/libs
```

The backups covered `/data`, `/home/alexponce` and `/etc`, taken daily at 02:30.

**Not encrypted, readable with no password at all:** the `WINRESCUE` NTFS partition on the
same drive, and everything on the 500 GB SATA SSD. Mount and copy.

## Rebuilding the machine

The full provisioning lives at https://github.com/aleponce4/linux-setup — install Kubuntu,
clone it, run `./bootstrap.sh`. `HANDOFF.md` there walks through it.

**Before anything else, if the screen goes black after the boot logo:** this hardware needs
two BIOS settings, and without them a Wayland desktop cannot start.

| Setting | Value |
|---|---|
| `Advanced > PCI Subsystem Settings > Above 4G Decoding` | Enabled |
| `Advanced > PCI Subsystem Settings > Re-Size BAR Support` | Enabled |
| `Boot > CSM > Launch CSM` | Disabled |

That cost a full night once. `docs/boot-and-graphics.md` has the diagnosis.

## What "Bitwarden" is, since you asked

A password manager: one app holding every password, protected by a single master password
you memorise. Installed here as a Flatpak (`com.bitwarden.desktop`) and usable from any
browser at bitwarden.com. If the master password is lost, Bitwarden cannot recover it either
— that is the point of it, and the reason the restic password was also written into
`secrets.7z` as a second copy.

## The short version

1. Find the 8 TB HGST drive.
2. Get the restic password out of Bitwarden, or out of `secrets.7z`.
3. `restic -r <mount>/restic restore latest --target <somewhere>`.
4. If in doubt, `/data` and `WINRESCUE` are plain unencrypted files — just copy them.
