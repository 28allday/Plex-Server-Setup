#!/usr/bin/env bash
#
# install_and_mount.sh
#
# This script does two main tasks in one go:
#  1) Helps you select and mount a drive/partition at boot (via /etc/fstab).
#  2) Installs Plex Media Server from a local .deb file in your ~/Downloads folder,
#     and opens port 32400 via UFW.
#
# If the user selects 'exfat' as the file system, we do NOT install exfat-fuse or exfat-utils,
# assuming the Ubuntu-based system already supports exFAT natively (e.g., Ubuntu 20.04+).
#

set -e  # Exit on any error

###############################################################################
# 0. Root Check
###############################################################################
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run with sudo (root privileges)."
  exit 1
fi

echo "======================================================="
echo "   Combined Setup: Drive Mount + Plex Installation"
echo "======================================================="
echo

###############################################################################
# 1. MOUNT DRIVE
###############################################################################
echo "-----------------------------"
echo " Part A: Drive Mount Setup"
echo "-----------------------------"
echo
echo "Below are the available drives/partitions on your system:"
echo

# List block devices
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
  # Attempt to get UUID
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
  if [[ ! -d "$MOUNT_POINT" ]]; then
    echo "Creating mount point directory: ${MOUNT_POINT}"
    mkdir -p "$MOUNT_POINT"
  fi

  echo
  read -rp "Enter the file system type (e.g., ext4, ntfs, xfs, exfat): " FS_TYPE

  # If exfat is chosen, assume the system has exFAT support already (e.g., Ubuntu 20.04+).
  if [[ "$FS_TYPE" == "exfat" ]]; then
    echo "User selected exFAT. Assuming native exFAT support on this Ubuntu-based system."
    echo "No additional exFAT packages will be installed."
  fi

  # We'll keep it simple: use 'defaults' for mount options, pass=2
  MOUNT_OPTS="defaults"
  FSTAB_LINE="${DEVICE_IDENTIFIER}  ${MOUNT_POINT}  ${FS_TYPE}  ${MOUNT_OPTS}  0  2"

  echo
  echo "The following line will be added to /etc/fstab:"
  echo "----------------------------------------------"
  echo "${FSTAB_LINE}"
  echo "----------------------------------------------"

  read -rp "Proceed with adding to /etc/fstab? (y/n): " CONFIRM_MOUNT
  if [[ "$CONFIRM_MOUNT" =~ ^[Yy]$ ]]; then
    echo "Adding line to /etc/fstab..."
    echo "${FSTAB_LINE}" >> /etc/fstab
    echo "Attempting to mount all file systems now (mount -a)..."
    mount -a
    echo "Drive mount process complete."
  else
    echo "Skipping drive mount configuration."
  fi
fi

###############################################################################
# 2. INSTALL PLEX
###############################################################################
echo
echo "-----------------------------"
echo " Part B: Plex Installation"
echo "-----------------------------"
echo

read -rp "Would you like to install Plex Media Server now? (y/n): " INSTALL_PLEX
if [[ "$INSTALL_PLEX" =~ ^[Yy]$ ]]; then

  # 2.1. Identify the original user for the Downloads folder
  # (so we can find the .deb in ~<user>/Downloads)
  if [[ -n "$SUDO_USER" ]]; then
    ORIGINAL_USER="$SUDO_USER"
  else
    ORIGINAL_USER="$USER"
  fi
  DOWNLOADS_DIR="$(eval echo ~${ORIGINAL_USER})/Downloads"

  # 2.2. Update system packages
  echo "Updating package list..."
  apt-get update -y

  # 2.3. Install dependencies
  echo "Installing curl, apt-transport-https, gnupg..."
  apt-get install -y curl apt-transport-https gnupg

  # 2.4. Find the Plex .deb file in ~/Downloads
  PLEX_DEB=$(ls -1 "${DOWNLOADS_DIR}"/plexmediaserver*.deb 2>/dev/null || true)

  if [[ -z "$PLEX_DEB" ]]; then
    echo "ERROR: No 'plexmediaserver*.deb' file found in ${DOWNLOADS_DIR}."
    echo "Please place the downloaded Plex .deb file there and rerun if needed."
  else
    echo "Found Plex .deb file(s):"
    echo "$PLEX_DEB"
    echo "Installing Plex Media Server..."

    # Attempt to install
    dpkg -i "$PLEX_DEB" || true

    # Fix missing dependencies if dpkg complained
    apt-get -f install -y

    # Enable and start Plex
    echo "Enabling Plex Media Server on boot..."
    systemctl enable plexmediaserver.service

    echo "Starting Plex Media Server..."
    systemctl start plexmediaserver.service

    # 2.5. Configure firewall
    echo "Installing ufw (if not installed) and allowing port 32400/tcp..."
    apt-get install -y ufw
    ufw allow 32400/tcp || true

    # Optionally enable ufw (uncomment if desired):
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
