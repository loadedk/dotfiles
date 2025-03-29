#!/bin/bash
#
# Arch Linux Hyprland Installation Script
# Author: Gemini AI based on user request
# Date: 2025-03-28
#
# WARNING: This script is intended for advanced users. It will
# partition drives and install an operating system automatically.
# *** IT WILL IRREVERSIBLY DESTROY ALL DATA ON THE SPECIFIED DRIVES ***
# Review carefully and use at your own risk.
#

# Exit immediately if a command exits with a non-zero status.
set -e
# Optional: Print commands and their arguments as they are executed.
# set -x

# --- Configuration ---
# !! VERIFY THESE ARE CORRECT FOR YOUR SYSTEM !!
ROOT_DRIVE="/dev/nvme0n1"     # Drive for OS (Btrfs + Snapshots)
HOME_DRIVE="/dev/sda"         # Drive for /home (Ext4)
STORAGE_DRIVE="/dev/sdc"      # Drive for /storage (Ext4)

# Partition variables (derived from drive names)
ROOT_PART1="${ROOT_DRIVE}p1" # EFI
ROOT_PART2="${ROOT_DRIVE}p2" # Btrfs Root
HOME_PART1="${HOME_DRIVE}1"     # Ext4 Home
STORAGE_PART1="${STORAGE_DRIVE}1" # Ext4 Storage

# Mount points
EFI_MOUNT="/mnt/boot/efi"
ROOT_MOUNT="/mnt"
HOME_MOUNT="/mnt/home"
STORAGE_MOUNT="/mnt/storage"

# System settings
HOSTNAME="arch-hyprland" # Change this to your desired hostname
TIMEZONE="America/New_York" # Change this to your timezone (e.g., Europe/London, list: timedatectl list-timezones)
LOCALE="en_US.UTF-8"        # Set your desired locale (ensure it's uncommented in /etc/locale.gen later)

# --- Safety Check ---
clear
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!!                          !!! WARNING !!!                                !!!"
echo "!!! This script will partition and format the following drives:             !!!"
echo "!!!   Root OS Drive: ${ROOT_DRIVE}                                             !!!"
echo "!!!   Home Drive:    ${HOME_DRIVE}                                             !!!"
echo "!!!   Storage Drive: ${STORAGE_DRIVE}                                             !!!"
echo "!!!                                                                         !!!"
echo "!!! >>> ALL EXISTING DATA ON THESE DRIVES WILL BE PERMANENTLY DESTROYED <<< !!!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""
echo "Please double-check these are the correct drives you wish to use."
echo "Verify with 'lsblk' in another terminal if unsure."
echo ""
echo "Type 'YES' in uppercase to confirm and proceed, anything else to abort:"
read -r CONFIRMATION
if [ "$CONFIRMATION" != "YES" ]; then
    echo "Aborting script."
    exit 1
fi

# --- User and Password Input ---
echo ""
echo "--- User Account Setup ---"
while true; do
    read -p "Enter the desired username (e.g., 'john'): " script_username
    # Basic validation for username format
    if [[ -n "$script_username" ]] && [[ "$script_username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        break
    else
        echo "Invalid username. Please use lowercase letters, numbers, underscores, hyphens. Must start with a letter or underscore."
    fi
done

while true; do
    # Prompt for user password silently
    read -s -p "Enter password for user '$script_username': " script_user_password
    echo # Add a newline after silent input
    # Prompt for confirmation
    read -s -p "Confirm password for user '$script_username': " script_user_password_confirm
    echo # Add a newline
    # Check if passwords match and are not empty
    if [[ "$script_user_password" == "$script_user_password_confirm" ]] && [[ -n "$script_user_password" ]]; then
        break # Exit loop if passwords match and are not empty
    else
        echo "Passwords do not match or are empty. Please try again."
    fi
done

while true; do
    # Prompt for root password silently
    read -s -p "Enter password for the 'root' user: " script_root_password
    echo
    # Prompt for confirmation
    read -s -p "Confirm password for 'root': " script_root_password_confirm
    echo
    # Check if passwords match and are not empty
    if [[ "$script_root_password" == "$script_root_password_confirm" ]] && [[ -n "$script_root_password" ]]; then
        break # Exit loop if passwords match and are not empty
    else
        echo "Passwords do not match or are empty. Please try again."
    fi
done
echo "Username and passwords captured."
echo ""
# --- End User and Password Input ---


# --- 1. Preparation ---
echo "---> Setting up Network Time Protocol..."
timedatectl set-ntp true
echo "NTP service status:"
timedatectl status

# --- 2. Partitioning Disks ---
echo "---> Partitioning drives (${ROOT_DRIVE}, ${HOME_DRIVE}, ${STORAGE_DRIVE})..."

# Root Drive (NVMe/SSD) - GPT, EFI partition, Btrfs root partition
parted -s "${ROOT_DRIVE}" mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart primary btrfs 513MiB 100%
echo "Partitioned ${ROOT_DRIVE}."

# Home Drive (SSD/HDD) - GPT, single Ext4 partition
parted -s "${HOME_DRIVE}" mklabel gpt \
    mkpart primary ext4 1MiB 100%
echo "Partitioned ${HOME_DRIVE}."

# Storage Drive (HDD/SSD) - GPT, single Ext4 partition
parted -s "${STORAGE_DRIVE}" mklabel gpt \
    mkpart primary ext4 1MiB 100%
echo "Partitioned ${STORAGE_DRIVE}."

# Short pause for the kernel to recognize new partitions
sleep 3
echo "Disk partitioning complete."

# --- 3. Formatting Filesystems ---
echo "---> Formatting filesystems..."

# Format EFI partition
echo "Formatting EFI partition: ${ROOT_PART1}"
mkfs.fat -F32 "${ROOT_PART1}" -n EFI

# Format Btrfs root partition
echo "Formatting Btrfs root partition: ${ROOT_PART2}"
mkfs.btrfs -f -L ROOT "${ROOT_PART2}" # -f to force overwrite if needed

# Format Home partition
echo "Formatting ext4 home partition: ${HOME_PART1}"
mkfs.ext4 -F -L HOME "${HOME_PART1}" # -F to force (avoids prompt)

# Format Storage partition
echo "Formatting ext4 storage partition: ${STORAGE_PART1}"
mkfs.ext4 -F -L STORAGE "${STORAGE_PART1}" # -F to force

echo "Filesystem formatting complete."

# --- 4. Create Btrfs Subvolumes ---
echo "---> Creating Btrfs subvolumes on ${ROOT_PART2}..."
# Mount the top-level Btrfs volume temporarily
mount "${ROOT_PART2}" /mnt

# Create subvolumes for Snapper layout + extras
# See: https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout
btrfs subvolume create /mnt/@          # /
btrfs subvolume create /mnt/@home      # /home (even if unused on this drive, common practice)
btrfs subvolume create /mnt/@snapshots # /.snapshots
btrfs subvolume create /mnt/@log       # /var/log
btrfs subvolume create /mnt/@cache     # /var/cache
btrfs subvolume create /mnt/@tmp       # /tmp
btrfs subvolume create /mnt/@srv       # /srv

# Unmount the temporary top-level mount
umount /mnt
echo "Btrfs subvolumes created."

# --- 5. Mount Target Filesystems ---
echo "---> Mounting filesystems for Arch installation..."

# Define common Btrfs mount options for SSDs
BTRFS_OPTS="rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol="
# Define common Ext4 mount options
EXT4_OPTS="rw,noatime,defaults"

# Mount root subvolume (@) to /mnt
mount -o "${BTRFS_OPTS}@" "${ROOT_PART2}" "${ROOT_MOUNT}"

# Create mount points within /mnt for other filesystems/subvolumes
mkdir -p "${ROOT_MOUNT}/.snapshots"
mkdir -p "${ROOT_MOUNT}/var/log"
mkdir -p "${ROOT_MOUNT}/var/cache"
mkdir -p "${ROOT_MOUNT}/tmp"
mkdir -p "${ROOT_MOUNT}/srv"
mkdir -p "${EFI_MOUNT}"
mkdir -p "${HOME_MOUNT}"
mkdir -p "${STORAGE_MOUNT}"

# Mount other Btrfs subvolumes
mount -o "${BTRFS_OPTS}@snapshots" "${ROOT_PART2}" "${ROOT_MOUNT}/.snapshots"
mount -o "${BTRFS_OPTS}@log"       "${ROOT_PART2}" "${ROOT_MOUNT}/var/log"
mount -o "${BTRFS_OPTS}@cache"     "${ROOT_PART2}" "${ROOT_MOUNT}/var/cache"
mount -o "${BTRFS_OPTS}@tmp"       "${ROOT_PART2}" "${ROOT_MOUNT}/tmp"
mount -o "${BTRFS_OPTS}@srv"       "${ROOT_PART2}" "${ROOT_MOUNT}/srv"

# Mount EFI partition
mount "${ROOT_PART1}" "${EFI_MOUNT}"

# Mount Home partition
mount -o "${EXT4_OPTS}" "${HOME_PART1}" "${HOME_MOUNT}"

# Mount Storage partition
mount -o "${EXT4_OPTS}" "${STORAGE_PART1}" "${STORAGE_MOUNT}"

echo "Target filesystems mounted. Current layout:"
lsblk "${ROOT_DRIVE}" "${HOME_DRIVE}" "${STORAGE_DRIVE}"
echo ""

# --- 6. Install Base System and Packages ---
echo "---> Installing Arch Linux base system and essential packages (pacstrap)..."
# Define list of packages to install
PACKAGES=(
    base linux linux-firmware     # Base system, kernel, firmware
    btrfs-progs                   # Btrfs utilities
    grub efibootmgr               # Bootloader
    snapper grub-btrfs            # Snapshot management and GRUB integration
    networkmanager                # Network management
    sudo vim git base-devel       # Basic utilities, build tools
    hyprland xdg-desktop-portal-hyprland # Hyprland compositor and portal
    waybar kitty wofi mako        # Status bar, terminal, launcher, notifications
    swaylock swaybg grim slurp    # Lock screen, wallpaper, screenshots
    polkit-kde-agent              # Polkit agent for permissions in graphical session
    qt5-wayland qt6-wayland       # Qt Wayland support
    pipewire wireplumber pipewire-audio pipewire-alsa pipewire-pulse pipewire-jack # Audio system
    noto-fonts ttf-jetbrains-mono ttf-font-awesome # Fonts
    rsync                         # File synchronization (for backups)
    sddm                          # Display Manager (Login screen)
    jdk-openjdk                   # Java Development Kit (current default)
    # Add amd-ucode or intel-ucode here if desired
)
# Run pacstrap
pacstrap "${ROOT_MOUNT}" "${PACKAGES[@]}"

echo "Base system and packages installation complete."

# --- 7. Generate fstab ---
echo "---> Generating fstab..."
# Generate fstab file using UUIDs for block devices (-U)
genfstab -U "${ROOT_MOUNT}" >> "${ROOT_MOUNT}/etc/fstab"

echo "--------------------------------------------------------------------------"
echo "!!! IMPORTANT: Review the generated /mnt/etc/fstab file now!           !!!"
echo "!!! Verify mount options (e.g., 'noatime', 'compress=zstd', 'ssd').    !!!"
echo "!!! It's crucial for performance and correctness, especially for Btrfs.!!!"
echo "--------------------------------------------------------------------------"
echo "You can check it with: cat /mnt/etc/fstab"
echo "Or edit it with: nano /mnt/etc/fstab"
echo ""
echo "Press Enter to continue AFTER reviewing, or Ctrl+C to abort and edit."
read -r DUMMY_VAR
echo "--------------------------------------------------------------------------"


# --- 8. Chroot into New System and Configure ---
echo "---> Chrooting into the new system to perform configurations..."

# Create a configuration script that will run inside the chroot environment
# Variables like $script_username, $script_root_password etc. are expanded
# by the shell running *this* script *before* the content is written.
cat > "${ROOT_MOUNT}/configure_system.sh" <<EOF
#!/bin/bash
# This script runs inside the chroot environment
set -e # Exit on error

echo "--- Running Configuration Inside Chroot ---"

# Set Timezone
echo "Setting timezone to ${TIMEZONE}..."
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
# Sync hardware clock to system time
hwclock --systohc
echo "Timezone set."

# Set Locale
echo "Configuring locale (${LOCALE})..."
# Uncomment the desired locale in /etc/locale.gen
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
# Generate the locales
locale-gen
# Set the system locale
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "Locale configured."

# Set Hostname
echo "Setting hostname to ${HOSTNAME}..."
echo "${HOSTNAME}" > /etc/hostname
# Configure /etc/hosts
echo "127.0.0.1   localhost" >> /etc/hosts
echo "::1         localhost" >> /etc/hosts
echo "127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}" >> /etc/hosts
echo "Hostname set."

# Set Root Password (using password provided earlier)
echo "Setting root password..."
echo "root:${script_root_password}" | chpasswd
echo "Root password set."

# Create User and Set Password (using details provided earlier)
echo "Creating user '${script_username}'..."
# Create user with home directory (-m), add to wheel group (-G) for sudo
useradd -m -G wheel -s /bin/bash "${script_username}"
# Set user password
echo "${script_username}:${script_user_password}" | chpasswd
echo "User '${script_username}' created and password set."

# Configure sudo (allow users in 'wheel' group to use sudo)
echo "Configuring sudo permissions for 'wheel' group..."
# Create a sudoers drop-in file (safer than editing /etc/sudoers directly)
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel # Set secure permissions
echo "Sudo configured."

# Install GRUB Bootloader
echo "Installing GRUB bootloader to EFI partition..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
echo "GRUB installed."

# Configure GRUB for Btrfs Snapshots
echo "Configuring GRUB for Btrfs snapshots..."
# Add the directory where Snapper stores snapshots to GRUB's config
echo "GRUB_BTRFS_SUBVOLUME_DIR=/.snapshots" >> /etc/default/grub
# Optional: Adjust GRUB timeout, theme etc. in /etc/default/grub if needed

# Generate main GRUB configuration file
echo "Generating GRUB configuration (grub.cfg)..."
grub-mkconfig -o /boot/grub/grub.cfg
echo "GRUB configuration generated."

# Configure Snapper
echo "Configuring Snapper for root filesystem snapshots..."
# Create a Snapper configuration for the root filesystem ('/')
snapper -c root create-config /
# Optional: Adjust snapshot limits in /etc/snapper/configs/root
# Example: snapper -c root set-config "TIMELINE_LIMIT_HOURLY=6 TIMELINE_LIMIT_DAILY=7 ..."

# Enable Snapper's automatic snapshot and cleanup timers
echo "Enabling Snapper systemd timers..."
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer
echo "Snapper configured and timers enabled."

# Enable Essential System Services
echo "Enabling NetworkManager service..."
systemctl enable NetworkManager

echo "Enabling SDDM (Login Manager) service..."
systemctl enable sddm

echo "--- System Configuration Inside Chroot Finished ---"
EOF

# Make the configuration script executable
chmod +x "${ROOT_MOUNT}/configure_system.sh"

# Execute the configuration script within the chroot environment
echo "---> Running configuration script inside chroot..."
arch-chroot "${ROOT_MOUNT}" /bin/bash /configure_system.sh

# Clean up the configuration script
rm "${ROOT_MOUNT}/configure_system.sh"
echo "---> Chroot configuration script finished and removed."

# --- 9. Final Steps ---
echo ""
echo "--------------------------------------------------------------------------"
echo "            >>> Base Installation and Configuration Complete <<<           "
echo "--------------------------------------------------------------------------"
echo ""
echo "The script has finished. The next steps are manual:"
echo ""
echo "1. Unmount all partitions: run 'umount -R /mnt'"
echo "2. Reboot the system: run 'reboot'"
echo "3. Remove the Arch Linux installation medium."
echo ""
echo "--- Post-Reboot Checklist ---"
echo " After rebooting and logging in via SDDM as user '${script_username}':"
echo "  a. **Network:** Configure your network connection (e.g., using 'nmtui' in terminal, or a GUI applet if installed later)."
echo "  b. **AUR Helper (paru):** Install an AUR helper like 'paru' for easily accessing user repositories:"
echo "     sudo pacman -S --needed base-devel git"
echo "     git clone https://aur.archlinux.org/paru.git ~/paru"
echo "     cd ~/paru && makepkg -si && cd ~ && rm -rf ~/paru"
echo "  c. **AppImageLauncher:** Install using paru:"
echo "     paru -S appimagelauncher"
echo "  d. **Hyprland Config:** Create/copy a Hyprland config (e.g., from /usr/share/hyprland/ to ~/.config/hypr/hyprland.conf)."
echo "     Add the Polkit agent for permissions: 'exec-once = /usr/lib/polkit-kde-authentication-agent-1'"
echo "  e. **Dotfiles:** Configure Waybar, Wofi, Kitty, etc. by creating/copying config files to ~/.config/"
echo "  f. **Backup Script:** Set up the 'backup_home.sh' rsync script (provided separately) in your home directory."
echo "  g. **Snapper Check:** Verify Snapper is working: 'sudo snapper list-configs', 'sudo snapper list'."
echo "  h. **GRUB Check:** Reboot again to ensure 'Arch Linux Snapshots' appears in the GRUB menu."
echo "  i. **Java Check:** Verify Java installation: 'java -version'."
echo "  j. **(Optional) Flatpak:** Install Flatpak and apps manually if needed:"
echo "     sudo pacman -S flatpak"
echo "     flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
echo "     flatpak install flathub <app-id-1> <app-id-2> ..."
echo ""

# --- Unmount Reminder ---
# It's safer to unmount manually after the script finishes.
# echo "--> Attempting to unmount filesystems..."
# sync
# umount -R "${ROOT_MOUNT}" || echo "Warning: Unmounting failed. Please unmount manually with 'umount -R /mnt'."

echo "--------------------------------------------------------------------------"
echo "      >>> Ready to unmount and reboot. Run 'umount -R /mnt' then 'reboot' <<<"
echo "--------------------------------------------------------------------------"

exit 0
