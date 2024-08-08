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

# Function to backup and reconfigure the config file
update_config() {
    local config_file="/boot/firmware/config.txt"
    local backup_file="${config_file}.bak"
    local custom_config_marker="# RPI-COMPUTE-NODE CONFIG"

    # Array of settings
    local settings=(
        "dtparam=audio=off"
        "camera_auto_detect=0"
        "display_auto_detect=0"
        "auto_initramfs=1"
        "disable_fw_kms_setup=1"
        "arm_64bit=1"
        "disable_overscan=1"
        "arm_boost=1"
        "dtoverlay=disable-bt"
        "dtoverlay=disable-wifi"
        "gpu_mem=16"
        "arm_freq=2200"
        "over_voltage=8"
        "max_framebuffers=0"
        "disable_camera_led=1"
        "dtparam=i2c_arm=off"
        "dtparam=spi=off"
        "enable_uart=0"
        "dtparam=sd_poll_once"
        "gpu_freq_min=100"
        "h264_freq_min=100"
        "isp_freq_min=100"
        "v3d_freq_min=100"
        "hevc_freq_min=100"
        "dtparam=pwr_led_trigger=default-on"
        "dtparam=pwr_led_activelow=off"
    )

    # If our custom config is already present, restore from backup
    if grep -q "$custom_config_marker" "$config_file"; then
        if [ -f "$backup_file" ]; then
            log "Restoring original configuration from backup"
            cp "$backup_file" "$config_file"
        else
            log "Error: Backup file not found. Cannot restore original configuration."
            return 1
        fi
    fi

    # Backup original config if not already done
    if [ ! -f "$backup_file" ]; then
        cp "$config_file" "$backup_file"
        log "Backup of original configuration created"
    fi

    log "Updating Raspberry Pi configuration..."

    # Remove existing settings we want to manage
    local temp_file=$(mktemp)
    while IFS= read -r line; do
        local skip=false
        for setting in "${settings[@]}"; do
            if [[ "$line" == "${setting%%=*}"* ]]; then
                skip=true
                break
            fi
        done
        if ! $skip; then
            echo "$line" >> "$temp_file"
        fi
    done < "$config_file"

    # Add custom settings configuration at the end
    echo "" >> "$temp_file"
    echo "[all]" >> "$temp_file"
    echo "$custom_config_marker" >> "$temp_file"
    for setting in "${settings[@]}"; do
        echo "$setting" >> "$temp_file"
    done

    # Replace original file
    mv "$temp_file" "$config_file"

    log "Raspberry Pi configuration updated"
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

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
          https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
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
    update_config
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
