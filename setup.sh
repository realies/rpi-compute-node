#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log "This script must be run as root" 1>&2
        exit 1
    fi
}

# Function to update and upgrade the system
update_system() {
    log "Updating and upgrading the system..."
    apt update && apt upgrade -y
}

# Function to configure Raspberry Pi
configure_rpi() {
    log "Configuring Raspberry Pi..."
    if ! grep -q "# RPI-COMPUTE-NODE CONFIG" /boot/firmware/config.txt; then
        cp /boot/firmware/config.txt /boot/firmware/config.txt.bak
        cat << EOF > /boot/firmware/config.txt
# RPI-COMPUTE-NODE CONFIG
# Disable onboard audio
dtparam=audio=off

# Disable automatic detection of camera and display
camera_auto_detect=0
display_auto_detect=0

# Enable automatic generation of initramfs
auto_initramfs=1

# Disable firmware KMS setup
disable_fw_kms_setup=1

# Enable 64-bit mode
arm_64bit=1

# Disable overscan (black border around the screen)
disable_overscan=1

# Enable CPU boost mode
arm_boost=1

[all]
# Disable Bluetooth
dtoverlay=disable-bt

# Disable Wi-Fi
dtoverlay=disable-wifi

# Set GPU memory to minimum (16MB)
gpu_mem=16

# Overclock CPU to 2.2GHz
arm_freq=2200

# Increase CPU/GPU core voltage
over_voltage=8

# Disable framebuffer allocation
max_framebuffers=0

# Disable camera LED
disable_camera_led=1

# Disable I2C interface
dtparam=i2c_arm=off

# Disable SPI interface
dtparam=spi=off

# Disable UART
enable_uart=0

# Enable SD card polling once at boot
dtparam=sd_poll_once

# Set minimum frequencies for various components
gpu_freq_min=100
h264_freq_min=100
isp_freq_min=100
v3d_freq_min=100
hevc_freq_min=100

# Configure power LED
dtparam=pwr_led_trigger=default-on
dtparam=pwr_led_activelow=off
EOF
        log "Raspberry Pi configuration updated"
    else
        log "Raspberry Pi configuration already updated, skipping"
    fi
}

# Function to disable swap
disable_swap() {
    log "Disabling swap..."
    if [ -f /etc/dphys-swapfile ]; then
        dphys-swapfile swapoff
        dphys-swapfile uninstall
        update-rc.d dphys-swapfile remove
        apt purge dphys-swapfile -y
        log "Swap disabled"
    else
        log "Swap already disabled, skipping"
    fi
}

# Function to disable unnecessary services and remove packages
disable_services_and_remove_packages() {
    log "Disabling unnecessary services and removing packages..."
    services_to_disable=(
        "avahi-daemon.service"
        "bluetooth.service"
        "hciuart.service"
        "rpi-display-backlight.service"
        "triggerhappy.service"
        "ModemManager.service"
        "wpa_supplicant.service"
        "dphys-swapfile.service"
        "pigpiod.service"
        "rsync.service"
        "nfs-common.service"
        "rpcbind.service"
        "systemd-networkd.service"
        "systemd-networkd-wait-online.service"
        "udisks2.service"
    )

    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null; then
            systemctl disable "$service"
            systemctl stop "$service"
            log "Disabled and stopped $service"
        else
            log "$service is already disabled or not found"
        fi
    done

    packages_to_remove=(
        "avahi-daemon"
        "bluez"
        "triggerhappy"
        "modemmanager"
        "wpasupplicant"
        "dphys-swapfile"
        "pigpio"
        "nfs-common"
        "rpcbind"
        "udisks2"
    )

    apt purge "${packages_to_remove[@]}" -y || true
    apt autoremove --purge -y
}

# Function to blacklist modules
blacklist_modules() {
    log "Blacklisting unnecessary modules..."
    if [ ! -f /etc/modprobe.d/raspi-blacklist.conf ]; then
        cat << EOF > /etc/modprobe.d/raspi-blacklist.conf
# Disable Bluetooth modules
blacklist bluetooth
blacklist btbcm
blacklist hci_uart

# Disable Wi-Fi module
blacklist brcmfmac
blacklist brcmutil

# Disable audio modules
blacklist snd_bcm2835
blacklist snd_pcm
blacklist snd_timer
blacklist snd
EOF
        log "Modules blacklisted"
    else
        log "Modules already blacklisted, skipping"
    fi
}

# Function to configure tmp mount
configure_tmp_mount() {
    log "Configuring tmp mount..."
    if [ ! -f /etc/systemd/system/tmp.mount ]; then
        cp /usr/share/systemd/tmp.mount /etc/systemd/system/tmp.mount
        systemctl enable tmp.mount
        systemctl start tmp.mount
        log "Tmp mount configured"
    else
        log "Tmp mount already configured, skipping"
    fi
}

# Function to modify cmdline.txt
modify_cmdline() {
    log "Modifying cmdline.txt..."
    if ! grep -q "cgroup_enable=cpuset" /boot/firmware/cmdline.txt; then
        sed -i '$ s/$/ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 cma=0/' /boot/firmware/cmdline.txt
        log "cmdline.txt modified"
    else
        log "cmdline.txt already modified, skipping"
    fi
}

# Function to disable apt timers
disable_apt_timers() {
    log "Disabling apt timers..."
    systemctl disable apt-daily.timer
    systemctl disable apt-daily-upgrade.timer
}

# Function to install Docker
install_docker() {
    log "Installing Docker..."
    if ! command -v docker &> /dev/null; then
        apt-get install ca-certificates curl -y
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt update
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
        log "Docker installed"
    else
        log "Docker already installed, skipping"
    fi
}

# Function to add user to Docker group
add_user_to_docker_group() {
    log "Adding user to Docker group..."
    user=$(ls /home | head -n1)
    if ! groups "$user" | grep -q docker; then
        usermod -aG docker "$user"
        log "User added to Docker group"
    else
        log "User already in Docker group, skipping"
    fi
}

# Main function
main() {
    check_root
    update_system
    configure_rpi
    disable_swap
    disable_services_and_remove_packages
    blacklist_modules
    configure_tmp_mount
    modify_cmdline
    disable_apt_timers
    install_docker
    add_user_to_docker_group
    log "Script completed successfully!"
}

# Run the main function
main
