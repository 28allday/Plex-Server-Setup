#!/usr/bin/env bash
# ==============================================================================
# Plex Media Server Installer with Drive Mount Setup
#
# A two-in-one setup script for building a Plex media server on Ubuntu or
# Linux Mint. It handles the two things you always need to do when setting
# up a new media server:
#
#   Part A: Mount your media drive permanently (via /etc/fstab)
#     - Shows available drives/partitions
#     - Detects UUID for reliable mounting (doesn't break if device order changes)
#     - Adds the mount to /etc/fstab so it survives reboots
#
#   Part B: Install Plex Media Server
#     - Installs from a .deb file you've downloaded to ~/Downloads/
#     - Handles dependencies automatically
#     - Enables the Plex service to start on boot
#     - Opens port 32400 in the firewall (UFW)
#
# Prerequisites:
#   - Ubuntu 20.04+ or Linux Mint 20+
#   - An external or internal drive for media storage
#   - Plex .deb file downloaded to ~/Downloads/
#     (download from https://www.plex.tv/media-server-downloads/)
#   - Run with sudo: sudo ./plexint.sh
# ==============================================================================

set -eo pipefail  # Exit immediately if any command fails; catch pipe failures too

# Root is required because this script modifies /etc/fstab (system mount
# config), installs packages with apt, and manages systemd services.
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run with sudo (root privileges)."
  exit 1
fi

echo "======================================================="
echo "   Combined Setup: Drive Mount + Plex Installation"
echo "======================================================="
echo

# ==================== Part A: Drive Mount Setup ====================
#
# Most media servers need a dedicated drive for storing movies, TV shows,
# music, etc. This section helps mount that drive permanently so it's
# available after every reboot.
#
# We use lsblk to show available drives, then ask the user to pick one.
# The mount is configured via /etc/fstab using the drive's UUID (not the
# device path like /dev/sdb1) because device paths can change if you add
# or remove drives, but UUIDs are permanent identifiers.
echo "-----------------------------"
echo " Part A: Drive Mount Setup"
echo "-----------------------------"
echo
echo "Below are the available drives/partitions on your system:"
echo

# Show drives with their sizes, types, current mount points, and filesystem
# types. The -p flag shows full device paths (e.g. /dev/sdb1 not just sdb1).
lsblk -p -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE

echo
echo "Which device/partition would you like to mount? (e.g. /dev/sdb1)"
read -rp "Device path: " DEVICE_PATH

# Validate the device
if [[ ! -b "$DEVICE_PATH" ]]; then
  echo "ERROR: '$DEVICE_PATH' is not a valid block device."
  echo "Aborting drive-mount portion."
  echo
else
  # Try to get the drive's UUID using blkid. UUID is preferred over device
  # paths in /etc/fstab because /dev/sdX names can change between reboots
  # (e.g. if you plug in a USB drive before the media drive). UUIDs are
  # unique identifiers burned into the filesystem and never change.
  UUID_FOUND=$(blkid -s UUID -o value "${DEVICE_PATH}" 2>/dev/null || true)
  if [[ -z "$UUID_FOUND" ]]; then
    echo "WARNING: Could not detect a UUID for '${DEVICE_PATH}'."
    echo "We will use the device path directly in /etc/fstab (less reliable)."
    DEVICE_IDENTIFIER="${DEVICE_PATH}"
  else
    echo "Found UUID for ${DEVICE_PATH}: ${UUID_FOUND}"
    DEVICE_IDENTIFIER="UUID=${UUID_FOUND}"
  fi

  echo
  read -rp "Enter the mount point (e.g. /mnt/data): " MOUNT_POINT
  if [[ -z "$MOUNT_POINT" || "$MOUNT_POINT" != /* ]]; then
    echo "ERROR: Mount point must be an absolute path (e.g. /mnt/data)."
    exit 1
  fi
  if [[ ! -d "$MOUNT_POINT" ]]; then
    echo "Creating mount point directory: ${MOUNT_POINT}"
    mkdir -p "$MOUNT_POINT"
  fi

  echo
  read -rp "Enter the file system type (e.g., ext4, ntfs, xfs, exfat): " FS_TYPE
  if [[ -z "$FS_TYPE" || "$FS_TYPE" =~ [[:space:]] ]]; then
    echo "ERROR: Invalid filesystem type."
    exit 1
  fi

  # If exfat is chosen, assume the system has exFAT support already (e.g., Ubuntu 20.04+).
  if [[ "$FS_TYPE" == "exfat" ]]; then
    echo "User selected exFAT. Assuming native exFAT support on this Ubuntu-based system."
    echo "No additional exFAT packages will be installed."
  fi

  # Build the fstab entry. "defaults" enables standard mount options
  # (read/write, auto-mount, etc.). The "0 2" at the end means:
  #   0 = don't include in dump backups
  #   2 = fsck checks this drive second (after the root filesystem)
  MOUNT_OPTS="defaults"
  FSTAB_LINE="${DEVICE_IDENTIFIER}  ${MOUNT_POINT}  ${FS_TYPE}  ${MOUNT_OPTS}  0  2"

  echo
  echo "The following line will be added to /etc/fstab:"
  echo "----------------------------------------------"
  echo "${FSTAB_LINE}"
  echo "----------------------------------------------"

  read -rp "Proceed with adding to /etc/fstab? (y/n): " CONFIRM_MOUNT
  if [[ "$CONFIRM_MOUNT" =~ ^[Yy]$ ]]; then
    # Check if this device/UUID is already in fstab to prevent duplicates
    if grep -qF "$DEVICE_IDENTIFIER" /etc/fstab; then
      echo "WARNING: An entry for ${DEVICE_IDENTIFIER} already exists in /etc/fstab. Skipping."
    else
      echo "Adding line to /etc/fstab..."
      echo "${FSTAB_LINE}" >> /etc/fstab
    fi
    echo "Attempting to mount all file systems now (mount -a)..."
    if ! mount -a; then
      echo "WARNING: mount -a failed. Check the fstab entry. Continuing to Part B..."
    else
      echo "Drive mount process complete."
    fi
  else
    echo "Skipping drive mount configuration."
  fi
fi

# ==================== Part B: Plex Media Server Installation ====================
#
# Plex Media Server is a media streaming server that organises your movies,
# TV shows, music, and photos and streams them to any device on your network
# (or remotely over the internet).
#
# Plex distributes Linux packages as .deb files (for Debian/Ubuntu/Mint).
# The user must download it manually from plex.tv because it requires
# accepting their terms of service. We look for it in ~/Downloads/.
echo
echo "-----------------------------"
echo " Part B: Plex Installation"
echo "-----------------------------"
echo

read -rp "Would you like to install Plex Media Server now? (y/n): " INSTALL_PLEX
if [[ "$INSTALL_PLEX" =~ ^[Yy]$ ]]; then

  # Figure out the real user's home directory. When running with sudo,
  # $USER is "root" but $SUDO_USER is the person who typed "sudo".
  # We need their Downloads folder, not root's.
  if [[ -n "$SUDO_USER" ]]; then
    ORIGINAL_USER="$SUDO_USER"
  else
    ORIGINAL_USER="$USER"
  fi
  DOWNLOADS_DIR="$(getent passwd "${ORIGINAL_USER}" | cut -d: -f6)/Downloads"

  # Update the package database and install prerequisites:
  #   curl:                For downloading files (used by Plex internally)
  #   apt-transport-https: Allows apt to fetch packages over HTTPS
  #   gnupg:               GPG key handling for package verification
  echo "Updating package list..."
  apt-get update -y

  echo "Installing curl, apt-transport-https, gnupg..."
  apt-get install -y curl apt-transport-https gnupg

  # Look for the Plex .deb in the user's Downloads folder. The filename
  # typically looks like "plexmediaserver_1.40.0.1234-abcdef_amd64.deb".
  # We use a glob array instead of parsing ls output, which is safer for
  # filenames with spaces and gives us control over multiple matches.
  shopt -s nullglob
  plex_debs=("${DOWNLOADS_DIR}"/plexmediaserver*.deb)
  shopt -u nullglob

  if [[ ${#plex_debs[@]} -eq 0 ]]; then
    echo "ERROR: No 'plexmediaserver*.deb' file found in ${DOWNLOADS_DIR}."
    echo "Please place the downloaded Plex .deb file there and rerun if needed."
  else
    if [[ ${#plex_debs[@]} -gt 1 ]]; then
      echo "Multiple .deb files found. Using the newest one:"
      PLEX_DEB="$(ls -1t "${plex_debs[@]}" | head -n1)"
    else
      PLEX_DEB="${plex_debs[0]}"
    fi
    echo "Installing: ${PLEX_DEB}"

    # Install the .deb package. dpkg -i may fail if dependencies are missing
    # (it doesn't resolve them automatically). That's OK — apt-get -f install
    # runs right after and pulls in any missing dependencies, then retries
    # the failed package installation.
    dpkg -i "$PLEX_DEB" || true
    apt-get -f install -y

    # Enable the Plex service so it starts automatically on every boot,
    # and start it now so the user can access it immediately.
    echo "Enabling Plex Media Server on boot..."
    systemctl enable plexmediaserver.service

    echo "Starting Plex Media Server..."
    systemctl start plexmediaserver.service

    # Open port 32400 in the firewall. This is Plex's default web interface
    # port — without this, other devices on the network can't access the
    # server. UFW (Uncomplicated Firewall) is the standard firewall on
    # Ubuntu/Mint.
    echo "Installing ufw (if not installed) and allowing port 32400/tcp..."
    apt-get install -y ufw
    ufw allow 32400/tcp || true

    # Note: UFW is not enabled by default. Uncomment the line below if you
    # want to activate the firewall. Be careful — this will block all ports
    # except those explicitly allowed (like 32400 above and SSH port 22).
    # ufw enable

    echo
    echo "==========================================================="
    echo "Plex Media Server installation complete."
    echo "You can access Plex at: http://<server-ip>:32400/web"
    echo "==========================================================="
  fi
else
  echo "Skipping Plex installation."
fi

echo
echo "-----------------------------------------------------------"
echo " All steps completed. Have a great day!"
echo "-----------------------------------------------------------"
