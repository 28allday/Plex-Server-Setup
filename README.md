# Plex Server Setup

## Video Guide

<p align="center">
  <a href="https://youtu.be/7k0ehGUqF9E">
    <img src="https://img.youtube.com/vi/7k0ehGUqF9E/0.jpg" width="700">
  </a>
</p>

One-script setup for a Plex Media Server on Ubuntu or Linux Mint. Handles drive mounting and Plex installation in a single run.

## Requirements

- **OS**: Ubuntu 20.04+ or Linux Mint 20+
- **Plex .deb file**: Downloaded from [plex.tv](https://www.plex.tv/media-server-downloads/) to `~/Downloads/`
- **A media drive**: Internal or external drive for storing your media

## Quick Start

1. **Download the Plex .deb** from [plex.tv/media-server-downloads](https://www.plex.tv/media-server-downloads/)
   - Choose **Linux**
   - Select **Ubuntu (16.04+) / Debian (8+)** → `.deb` package
   - Save to `~/Downloads/`

2. **Run the installer**:
```bash
git clone https://github.com/28allday/Plex-Server-Setup.git
cd Plex-Server-Setup
chmod +x plexint.sh
sudo ./plexint.sh
```

3. **Access Plex** at `http://<your-server-ip>:32400/web`

## What It Does

### Part A: Drive Mount Setup

Mounts your media drive permanently so it survives reboots.

1. Shows all available drives and partitions (`lsblk`)
2. Asks you to select a device (e.g. `/dev/sdb1`)
3. Detects the drive's UUID (unique identifier that won't change)
4. Asks for a mount point (e.g. `/mnt/media`)
5. Asks for the filesystem type (ext4, ntfs, xfs, exfat)
6. Adds the mount to `/etc/fstab` and mounts it immediately

**Why UUID?** Device paths like `/dev/sdb1` can change if you add or remove drives. UUIDs are permanent identifiers tied to the filesystem itself.

**Supported filesystems:** ext4, ntfs, xfs, exfat, btrfs, and any other type supported by your kernel.

### Part B: Plex Installation

1. Installs prerequisites (`curl`, `apt-transport-https`, `gnupg`)
2. Finds the Plex `.deb` file in `~/Downloads/`
3. Installs it with `dpkg` and resolves any missing dependencies
4. Enables Plex to start on boot (`systemctl enable`)
5. Starts Plex immediately
6. Opens port 32400 in UFW firewall

## After Installation

### Initial Plex Setup

1. Open `http://<server-ip>:32400/web` in a browser
2. Sign in with your Plex account (or create one)
3. Name your server
4. Add your media library — point it to the mount point you chose (e.g. `/mnt/media`)
5. Let Plex scan and organize your media

### Organise Your Media

For best results, organise your media like this:

```
/mnt/media/
├── Movies/
│   ├── Movie Name (2024)/
│   │   └── Movie Name (2024).mkv
│   └── ...
├── TV Shows/
│   ├── Show Name/
│   │   ├── Season 01/
│   │   │   ├── Show Name - S01E01.mkv
│   │   │   └── ...
│   │   └── ...
│   └── ...
└── Music/
    ├── Artist Name/
    │   ├── Album Name/
    │   │   ├── 01 - Track Name.flac
    │   │   └── ...
    │   └── ...
    └── ...
```

## Files Modified

| Path | Purpose |
|------|---------|
| `/etc/fstab` | Drive mount entry added (one line) |

## Services

| Service | Port | Purpose |
|---------|------|---------|
| `plexmediaserver.service` | 32400 | Plex Media Server web interface and streaming |

## Troubleshooting

### Can't access Plex web interface

- Check Plex is running: `sudo systemctl status plexmediaserver`
- Check firewall: `sudo ufw status` — port 32400 should be ALLOW
- Try `http://localhost:32400/web` on the server itself first

### Drive not mounting after reboot

- Check fstab syntax: `cat /etc/fstab`
- Test it: `sudo mount -a` (mounts all fstab entries)
- Check the UUID is correct: `sudo blkid`

### Plex can't see files on the media drive

- Check permissions: `ls -la /mnt/media`
- Plex runs as the `plex` user — it needs read access to your media:
  ```bash
  sudo chmod -R 755 /mnt/media
  sudo chown -R plex:plex /mnt/media
  ```
  Or add the plex user to your group:
  ```bash
  sudo usermod -aG your-username plex
  sudo systemctl restart plexmediaserver
  ```

### "No .deb file found" error

- Make sure the file is in `~/Downloads/` (not a subdirectory)
- The filename must start with `plexmediaserver` (e.g. `plexmediaserver_1.40.0.1234_amd64.deb`)

## Updating Plex

Download the new .deb from plex.tv and install it:

```bash
sudo dpkg -i ~/Downloads/plexmediaserver*.deb
sudo systemctl restart plexmediaserver
```

## Uninstalling

```bash
# Stop and remove Plex
sudo systemctl stop plexmediaserver
sudo systemctl disable plexmediaserver
sudo apt remove --purge plexmediaserver

# Remove firewall rule
sudo ufw delete allow 32400/tcp

# Remove the fstab entry (edit manually)
sudo nano /etc/fstab
# Delete the line this script added, then:
sudo umount /mnt/media

# Remove Plex data (WARNING: deletes all library metadata)
sudo rm -rf /var/lib/plexmediaserver
```

## Credits

- [Plex](https://www.plex.tv/) - Media server software

## License

This project is provided as-is.
