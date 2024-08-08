# rpi-compute-node

A streamlined setup script for transforming a fresh Raspberry Pi OS Lite or Ubuntu Server (64-bit) installation into a lean, Docker-ready compute node.

## Overview

This project provides a bash script that optimises a Raspberry Pi for compute-intensive tasks by:

1. Cleaning up unnecessary packages and services
2. Configuring hardware settings for optimal performance
3. Installing and setting up Docker

## Quick Start

To run the script, execute the following command on your Raspberry Pi:

```bash
curl -sSL https://raw.githubusercontent.com/realies/rpi-compute-node/master/setup.sh | sudo bash
```

**Note:** Always review scripts before running them with root privileges.

## Features

- System update and upgrade
- Dynamic Raspberry Pi configuration optimisation
- Backup and restore of original configuration
- Swap disable
- Unnecessary service disabling and package removal
- Module blacklisting for Bluetooth, Wi-Fi, and audio
- Temporary filesystem mount configuration
- Kernel command line modification for cgroup support
- APT timer disabling
- Docker installation and user setup

## Detailed Changes

### Hardware Configuration

- Creates a backup of the original config.txt file
- Dynamically updates config.txt, preserving non-conflicting settings
- Disables onboard audio, camera, display, Bluetooth, and Wi-Fi
- Enables 64-bit mode and CPU boost
- Configures GPU memory to minimum (16MB)
- Overclocks CPU to 2.2GHz
- Disables various interfaces (I2C, SPI, UART)

### Software Configuration

- Removes unnecessary packages (e.g., Bluetooth, Wi-Fi, audio-related)
- Disables services like avahi-daemon, ModemManager, and others
- Blacklists modules related to Bluetooth, Wi-Fi, and audio
- Configures kernel parameters for optimal container support

### Docker Setup

- Installs Docker from the official repository
- Adds the primary user to the Docker group

## Compatibility

This script is now compatible with both Raspberry Pi OS Lite and Ubuntu Server (64-bit) installations. It dynamically adjusts the configuration based on the existing setup, making it more versatile across different Raspberry Pi operating systems.

## Requirements

- Raspberry Pi 3 or newer
- Fresh installation of Raspberry Pi OS Lite or Ubuntu Server (64-bit)
- Internet connection

## Caution

This script makes significant changes to your Raspberry Pi configuration. It's designed for use cases where a minimal, compute-focused setup is desired. Some functionality (like Wi-Fi and Bluetooth) will be disabled. While the script creates a backup of the original config.txt file, always ensure you have a full backup of your system before running this script. Test in a safe environment before using in production.

## Idempotency

The script has been designed to be idempotent, meaning it can be safely run multiple times without causing errors or unintended changes. Key idempotent features include:

- Backing up the original config.txt file before making changes
- Restoring the original configuration before applying changes on subsequent runs
- Selectively updates config.txt, preserving original settings except for those explicitly managed by the script
- Avoiding duplicate entries in configuration files
- Skipping already completed steps
- Preventing re-installation of already installed packages
- Avoiding re-adding users to groups they're already part of

This allows for safe re-runs of the script, whether for updates or in case of interrupted execution.

## Post-Installation

After running the script, it's recommended to reboot your Raspberry Pi to ensure all changes take effect:

```bash
sudo reboot
```
