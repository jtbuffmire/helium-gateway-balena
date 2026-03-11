#!/bin/bash
# =============================================================================
# Buoy.fish SD Card Preparation Script
# =============================================================================
# Run this on your Mac/Linux AFTER flashing Raspberry Pi OS Lite with rpi-imager.
#
# PREREQUISITES:
#   - Flash Raspberry Pi OS Lite (64-bit, Bookworm) using rpi-imager
#   - In rpi-imager settings (gear icon), configure:
#       * Hostname (e.g., buoy-dev-join-debug)
#       * Username/password (e.g., pi / your-password)
#       * Enable SSH (password auth or key)
#       * WiFi if needed (not required for Ethernet)
#   - Re-insert the SD card after flashing (macOS auto-mounts boot partition)
#
# USAGE:
#   ./prepare-sd.sh <boot-partition-path> <site-config.json>
#
# EXAMPLES:
#   ./prepare-sd.sh /Volumes/bootfs ./dev-join-debug.json      # macOS
#   ./prepare-sd.sh /media/user/bootfs ./dev-join-debug.json   # Linux
#
# AFTER BOOT:
#   SSH into the Pi and run:
#     sudo bash /boot/firmware/buoy-config/first-boot.sh
#
#   That's it. If SPI needs enabling, the script installs itself into
#   /etc/rc.local, reboots, and finishes automatically on next boot.
# =============================================================================

set -euo pipefail

BOOT_PARTITION="${1:-}"
SITE_CONFIG="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "$BOOT_PARTITION" ] || [ -z "$SITE_CONFIG" ]; then
    echo "Usage: $0 <boot-partition-path> <site-config.json>"
    echo ""
    echo "Examples:"
    echo "  $0 /Volumes/bootfs ./dev-join-debug.json       # macOS"
    echo "  $0 /media/user/bootfs ./dev-join-debug.json    # Linux"
    echo ""
    echo "Prerequisites:"
    echo "  1. Flash Raspberry Pi OS Lite (64-bit) with rpi-imager"
    echo "  2. Configure user/SSH/WiFi in rpi-imager settings (gear icon)"
    echo "  3. Re-insert the SD card"
    echo "  4. Run this script"
    exit 1
fi

if [ ! -d "$BOOT_PARTITION" ]; then
    echo "ERROR: Boot partition not found at: $BOOT_PARTITION"
    echo "Make sure the SD card is inserted and mounted."
    exit 1
fi

if [ ! -f "$SITE_CONFIG" ]; then
    echo "ERROR: Site config not found at: $SITE_CONFIG"
    echo "Copy example-site.json, fill in your values, and pass it as the second argument."
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required. Install with: brew install jq"
    exit 1
fi

echo "============================================="
echo "Buoy.fish SD Card Preparation"
echo "============================================="
echo "Boot partition: $BOOT_PARTITION"
echo "Site config: $SITE_CONFIG"
echo ""

# Validate the site config
DEVICE_ID=$(jq -r '.device_id // "unprovisioned"' "$SITE_CONFIG")
SITE_NAME=$(jq -r '.site_name // "unknown"' "$SITE_CONFIG")
HOSTNAME_CUSTOM=$(jq -r '.hostname // ""' "$SITE_CONFIG")
TS_KEY=$(jq -r '.tailscale_auth_key // ""' "$SITE_CONFIG")

echo "Device ID: $DEVICE_ID"
echo "Site name: $SITE_NAME"
echo "Hostname:  ${HOSTNAME_CUSTOM:-buoy-${DEVICE_ID}}"
if [ -n "$TS_KEY" ] && [ "$TS_KEY" != "tskey-auth-REPLACE_ME" ]; then
    echo "Tailscale key: ${TS_KEY:0:20}... (set)"
else
    echo "Tailscale key: NOT SET"
    echo ""
    echo "WARNING: No Tailscale auth key. The Pi won't join your VPN automatically."
    echo "You can set it later by editing /boot/firmware/buoy-config/site.json on the Pi."
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# --- Copy buoy-config ---
echo "[prep] Copying site config..."
mkdir -p "$BOOT_PARTITION/buoy-config"
cp "$SITE_CONFIG" "$BOOT_PARTITION/buoy-config/site.json"

# --- Copy the gateway stack ---
echo "[prep] Copying gateway stack..."
mkdir -p "$BOOT_PARTITION/buoy-config/gateway-stack"
cp "$PROJECT_DIR/docker-compose.yml" "$BOOT_PARTITION/buoy-config/gateway-stack/"
cp -r "$PROJECT_DIR/services" "$BOOT_PARTITION/buoy-config/gateway-stack/"
cp -r "$PROJECT_DIR/agent" "$BOOT_PARTITION/buoy-config/gateway-stack/"

# --- Copy first-boot script ---
echo "[prep] Copying first-boot script..."
cp "$SCRIPT_DIR/first-boot.sh" "$BOOT_PARTITION/buoy-config/"
chmod +x "$BOOT_PARTITION/buoy-config/first-boot.sh"

echo ""
echo "============================================="
echo "[prep] SD card prepared successfully!"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Eject the SD card safely"
echo "  2. Insert into the gateway (RAK Miner V2, etc.)"
echo "  3. Connect Ethernet, power on"
echo "  4. Wait ~1 min for Pi OS to finish its own first-boot"
echo "  5. SSH in:"
echo "       ssh pi@${HOSTNAME_CUSTOM:-raspberrypi}.local"
echo "     (or check your router for the DHCP IP)"
echo "  6. Run:"
echo "       sudo bash /boot/firmware/buoy-config/first-boot.sh"
echo ""
echo "The script handles everything: Docker, Tailscale, SPI, containers."
echo "If SPI needs enabling, it reboots once and finishes automatically."
echo ""
echo "After ~5-10 min:"
echo "  - Tailscale: ssh pi@buoy-${DEVICE_ID}"
echo "  - Logs: sudo cat /var/log/buoy-first-boot.log"
echo "  - Status: cd /opt/buoy-gateway && docker compose ps"
echo "============================================="
