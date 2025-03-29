#!/bin/bash

set -e

echo "Updating system..."
sudo pacman -Syu --noconfirm

echo "Installing Hyprland and core packages..."
sudo pacman -S --noconfirm \
  hyprland xdg-desktop-portal-hyprland \
  kitty dolphin rofi waybar dunst \
  pipewire wireplumber xdg-utils xdg-user-dirs \
  wl-clipboard brightnessctl swaybg jq \
  network-manager-applet polkit-gnome \
  grim slurp swappy ffmpeg xdg-utils \
  ttf-jetbrains-mono-nerd ttf-font-awesome \
  qt5ct qt6ct qt5-graphicaleffects \
  unzip zip git curl wget neovim

echo "Installing Dolphin dependencies..."
sudo pacman -S --noconfirm kio kservice kdeclarative baloo

echo "Installing NVIDIA drivers..."
sudo pacman -S --noconfirm nvidia nvidia-utils nvidia-settings

echo "Setting NVIDIA KMS and Wayland support..."
echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia.conf
sudo mkinitcpio -P

echo "Enabling NetworkManager service..."
sudo systemctl enable NetworkManager

echo "Creating screenshot sound directory..."
mkdir -p ~/.local/share/sounds

echo "Setup complete. Don't forget to copy your dotfiles and run install.sh!"
