#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Optional: Print commands and their arguments as they are executed.
# set -x

# --- Configuration ---
ROOT_DRIVE="/dev/nvme0n1"
HOME_DRIVE="/dev/sda"
STORAGE_DRIVE="/dev/sdc"

ROOT_PART1="${ROOT_DRIVE}p1" # EFI
ROOT_PART2="${ROOT_DRIVE}p2" # Btrfs Root

HOME_PART1="${HOME_DRIVE}1"     # Ext4 Home
STORAGE_PART1="${STORAGE_DRIVE}1" # Ext4 Storage

EFI_MOUNT="/mnt/boot/efi"
ROOT_MOUNT="/mnt"
HOME_MOUNT="/mnt/home"
STORAGE_MOUNT="/mnt/storage"

HOSTNAME="arch-hyprland" # Change this to your desired hostname
USERNAME="your_user"     # Change this to your desired username
USER_PASSWORD="your_password" # Change this for your user
ROOT_PASSWORD="your_root_password" # Change this for root

TIMEZONE="America/New_York" # Change this to your timezone (e.g., Europe/London)
LOCALE="en_US.UTF-8"

# List of Flatpaks to install
FLATPAK_APPS=(
    "com.visualstudio.code"
    "one.ablaze.Floorp"
    "org.prismlauncher.PrismLauncher"
    "com.nextcloud.desktopclient"
    "org.qbittorrent.qBittorrent"
    "dev.vencord.Vesktop"
    "org.gnome.World.PikaBackup"
    "com.valvesoftware.Steam"
    "org.videolan.VLC"
)


# --- Safety Check ---
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!! WARNING: This script will ERASE ALL DATA on the following drives:"
echo "!!!   - ${ROOT_DRIVE}"
echo "!!!   - ${HOME_DRIVE}"
echo "!!!   - ${STORAGE_DRIVE}"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "Verify these are the correct drives. Double-check using 'lsblk'."
echo "Type 'YES' in uppercase to continue, anything else to abort:"
read -r CONFIRMATION
if [ "$CONFIRMATION" != "YES" ]; then
    echo "Aborting."
    exit 1
fi

# --- 1. Update System Clock ---
echo "Updating system clock..."
timedatectl set-ntp true

# --- 2. Partition Disks ---
echo "Partitioning disks..."

# Root Drive (NVMe)
parted -s "${ROOT_DRIVE}" mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart primary btrfs 513MiB 100%

# Home Drive (SSD)
parted -s "${HOME_DRIVE}" mklabel gpt \
    mkpart primary ext4 1MiB 100%

# Storage Drive (HDD)
parted -s "${STORAGE_DRIVE}" mklabel gpt \
    mkpart primary ext4 1MiB 100%

# Wait a moment for the kernel to recognize the new partitions
sleep 3

# --- 3. Format Filesystems ---
echo "Formatting filesystems..."

# Root Drive
echo "Formatting EFI partition: ${ROOT_PART1}"
mkfs.fat -F32 "${ROOT_PART1}" -n EFI

echo "Formatting Btrfs root partition: ${ROOT_PART2}"
mkfs.btrfs -f -L ROOT "${ROOT_PART2}"

# Home Drive
echo "Formatting ext4 home partition: ${HOME_PART1}"
mkfs.ext4 -F -L HOME "${HOME_PART1}"

# Storage Drive
echo "Formatting ext4 storage partition: ${STORAGE_PART1}"
mkfs.ext4 -F -L STORAGE "${STORAGE_PART1}"

# --- 4. Create Btrfs Subvolumes ---
echo "Creating Btrfs subvolumes..."
mount "${ROOT_PART2}" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@srv

umount /mnt
echo "Btrfs subvolumes created."

# --- 5. Mount Filesystems ---
echo "Mounting filesystems..."

BTRFS_OPTS="rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol="
mount -o "${BTRFS_OPTS}@" "${ROOT_PART2}" "${ROOT_MOUNT}"

mkdir -p "${ROOT_MOUNT}/.snapshots"
mkdir -p "${ROOT_MOUNT}/var/log"
mkdir -p "${ROOT_MOUNT}/var/cache"
mkdir -p "${ROOT_MOUNT}/tmp"
mkdir -p "${ROOT_MOUNT}/srv"
mkdir -p "${EFI_MOUNT}"
mkdir -p "${HOME_MOUNT}"
mkdir -p "${STORAGE_MOUNT}"

mount -o "${BTRFS_OPTS}@snapshots" "${ROOT_PART2}" "${ROOT_MOUNT}/.snapshots"
mount -o "${BTRFS_OPTS}@log"       "${ROOT_PART2}" "${ROOT_MOUNT}/var/log"
mount -o "${BTRFS_OPTS}@cache"     "${ROOT_PART2}" "${ROOT_MOUNT}/var/cache"
mount -o "${BTRFS_OPTS}@tmp"       "${ROOT_PART2}" "${ROOT_MOUNT}/tmp"
mount -o "${BTRFS_OPTS}@srv"       "${ROOT_PART2}" "${ROOT_MOUNT}/srv"

mount "${ROOT_PART1}" "${EFI_MOUNT}"

EXT4_OPTS="rw,noatime,defaults"
mount -o "${EXT4_OPTS}" "${HOME_PART1}" "${HOME_MOUNT}"
mount -o "${EXT4_OPTS}" "${STORAGE_PART1}" "${STORAGE_MOUNT}"

echo "Filesystems mounted."
lsblk

# --- 6. Install Essential Packages ---
echo "Installing base system and essential packages (pacstrap)..."
# Added jdk-openjdk (current Java)
pacstrap "${ROOT_MOUNT}" base linux linux-firmware \
    btrfs-progs grub efibootmgr snapper grub-btrfs \
    networkmanager sudo vim git base-devel \
    hyprland xdg-desktop-portal-hyprland waybar kitty wofi mako \
    swaylock swaybg grim slurp polkit-kde-agent qt5-wayland qt6-wayland \
    pipewire wireplumber pipewire-audio pipewire-alsa pipewire-pulse pipewire-jack \
    noto-fonts ttf-jetbrains-mono ttf-font-awesome \
    rsync sddm flatpak jdk-openjdk # Added jdk-openjdk

# Add intel-ucode or amd-ucode if you know your CPU type
# pacstrap /mnt intel-ucode
# pacstrap /mnt amd-ucode

echo "Base installation complete."

# --- 7. Generate fstab ---
echo "Generating fstab..."
genfstab -U "${ROOT_MOUNT}" >> "${ROOT_MOUNT}/etc/fstab"

echo "---------------------------------------------------------------------"
echo "!!! IMPORTANT: Review the generated /mnt/etc/fstab file now!"
echo "!!! Verify mount options (e.g., noatime, compress, ssd, discard)."
echo "Press Enter to continue after reviewing, or Ctrl+C to abort and edit."
read -r DUMMY_VAR
echo "---------------------------------------------------------------------"

# --- 8. Chroot into the New System and Configure ---
echo "Chrooting into the new system to perform configuration..."

# Create a configuration script that will run inside chroot
cat > "${ROOT_MOUNT}/configure_system.sh" <<EOF
#!/bin/bash
set -e
# set -x

# Define Flatpak apps here directly for simplicity within chroot script
FLATPAK_APPS=(
    "com.visualstudio.code"
    "one.ablaze.Floorp"
    "org.prismlauncher.PrismLauncher"
    "com.nextcloud.desktopclient"
    "org.qbittorrent.qBittorrent"
    "dev.vencord.Vesktop"
    "org.gnome.World.PikaBackup"
    "com.valvesoftware.Steam"
    "org.videolan.VLC"
)

echo "--- Running Configuration Inside Chroot ---"

# Timezone
echo "Setting timezone to ${TIMEZONE}..."
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

# Locale
echo "Configuring locale (${LOCALE})..."
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

# Hostname
echo "Setting hostname to ${HOSTNAME}..."
echo "${HOSTNAME}" > /etc/hostname
{
    echo "127.0.0.1   localhost"
    echo "::1         localhost"
    echo "127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}"
} >> /etc/hosts


# Root password
echo "Setting root password..."
echo "root:${ROOT_PASSWORD}" | chpasswd

# Create user and set password
echo "Creating user ${USERNAME}..."
useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
echo "User ${USERNAME} created."

# Configure sudo (allow users in wheel group)
echo "Configuring sudo..."
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Install GRUB
echo "Installing GRUB bootloader..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck

# Configure GRUB for Btrfs snapshots
echo "Configuring GRUB for Btrfs snapshots..."
# Ensure rootflags=subvol=@ is present if needed (check fstab first)
# sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& rootflags=subvol=@/' /etc/default/grub
echo "GRUB_BTRFS_SUBVOLUME_DIR=/.snapshots" >> /etc/default/grub

# Regenerate GRUB config
echo "Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg

# Configure Snapper
echo "Configuring Snapper..."
snapper -c root create-config /
# Optional: Adjust snapper config limits in /etc/snapper/configs/root
echo "Enabling Snapper timer units..."
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# Enable NetworkManager
echo "Enabling NetworkManager..."
systemctl enable NetworkManager

# Enable SDDM (Login Manager)
echo "Enabling SDDM..."
systemctl enable sddm

# Install Flatpak applications
echo "Installing Flatpak applications..."
echo "Adding Flathub remote..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Loop through the app list and install
echo "Installing ${#FLATPAK_APPS[@]} Flatpak apps..."
# Using --system to install system-wide (default when run as root)
# Using --noninteractive to avoid prompts
for app_id in "\${FLATPAK_APPS[@]}"; do
    echo "Installing \$app_id..."
    if flatpak install --system --noninteractive flathub "\$app_id"; then
        echo "Successfully installed \$app_id."
    else
        echo "WARNING: Failed to install \$app_id. Check the ID and network connection."
    fi
done
echo "Flatpak application installation finished."


echo "--- Configuration Inside Chroot Finished ---"
EOF

chmod +x "${ROOT_MOUNT}/configure_system.sh"

# Run the configuration script within chroot
arch-chroot "${ROOT_MOUNT}" /bin/bash /configure_system.sh

# Remove the configuration script
rm "${ROOT_MOUNT}/configure_system.sh"

# --- 9. Post-Installation ---
echo "Installation and basic configuration complete."
echo "You can now unmount the partitions and reboot."
echo "Run: 'umount -R /mnt' then 'reboot'."
echo ""
echo "--- Post-Reboot Steps ---"
echo "1. You should be greeted by the SDDM login manager."
echo "2. Select 'Hyprland' from the session menu (usually a small icon)."
echo "3. Login as user '${USERNAME}'."
echo "4. Configure your network using 'nmtui' or NetworkManager applet if needed."
echo "5. **Install paru (AUR Helper):**"
echo "   Open a terminal and run:"
echo "   sudo pacman -S --needed base-devel git"
echo "   git clone https://aur.archlinux.org/paru.git ~/paru"
echo "   cd ~/paru"
echo "   makepkg -si"
echo "   cd ~ && rm -rf ~/paru"
echo "   (Confirm prompts during makepkg unless you add --noconfirm)"
echo ""
echo "6. **Install AppImageLauncher using paru:**"
echo "   Open a terminal and run:"
echo "   paru -S appimagelauncher"
echo "   (Confirm prompts during installation unless you add --noconfirm)"
echo ""
echo "7. **Configure Hyprland and Polkit:**"
echo "   Edit your Hyprland config (~/.config/hypr/hyprland.conf)."
echo "   Add this line to autostart the Polkit agent for permissions:"
echo "   exec-once = /usr/lib/polkit-kde-authentication-agent-1"
echo "   (You'll need to create/copy a base Hyprland config first if it doesn't exist)."
echo ""
echo "8. Copy/create essential dotfiles (Waybar, Wofi, Kitty configs)."
echo "9. Set up the rsync backup script (backup_home.sh provided separately)."
echo "10. Check snapper status: 'sudo snapper list-configs', 'sudo snapper list'."
echo "11. Verify snapshots appear in GRUB menu on next boot."
echo "12. Flatpak apps are installed system-wide. You may need to log out/in for them to appear in menus."
echo "13. Java is installed ('java -version'). Manage versions with 'archlinux-java' if needed."


# --- Unmount and Reboot ---
echo "Unmounting filesystems..."
# sync # Write cached data
# umount -R "${ROOT_MOUNT}" || echo "Unmounting failed, proceed with reboot manually."

echo "---------------------------------------------------------------------"
echo "Setup script finished. Please run 'umount -R /mnt' and 'reboot'."
echo "---------------------------------------------------------------------"

exit 0
