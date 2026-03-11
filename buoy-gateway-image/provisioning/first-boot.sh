#!/bin/bash
# =============================================================================
# Buoy.fish Gateway Companion - First Boot Provisioning
# =============================================================================
# Run this manually after SSHing into a freshly-flashed Pi:
#
#   sudo bash /boot/firmware/buoy-config/first-boot.sh
#
# It installs Docker, Tailscale, enables SPI/I2C, and starts the gateway stack.
# Config is read from /boot/firmware/buoy-config/site.json.
#
# If SPI/I2C need enabling, the script installs itself into /etc/rc.local so
# it can finish automatically after reboot. Uses the .provisioned marker to
# skip completed work on re-run (idempotent).
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/buoy-first-boot.log"
CONFIG_DIR="/boot/firmware/buoy-config"
GATEWAY_DIR="/opt/buoy-gateway"
MARKER="/opt/buoy-gateway/.provisioned"

# Log everything
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================="
echo "Buoy.fish First Boot Provisioning"
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================="

# Skip if already provisioned
if [ -f "$MARKER" ]; then
    echo "[first-boot] Already provisioned. Skipping."
    echo "[first-boot] To re-provision, remove $MARKER and run again."
    exit 0
fi

# --- Read site config ---
if [ ! -f "$CONFIG_DIR/site.json" ]; then
    echo "[first-boot] ERROR: No site.json found in $CONFIG_DIR"
    echo "[first-boot] Run prepare-sd.sh first, then re-flash."
    exit 1
fi

DEVICE_ID=$(jq -r '.device_id // "unprovisioned"' "$CONFIG_DIR/site.json")
SITE_NAME=$(jq -r '.site_name // "unknown"' "$CONFIG_DIR/site.json")
MQTT_BROKER=$(jq -r '.mqtt_broker // "mqtt.buoy.fish"' "$CONFIG_DIR/site.json")
MQTT_USER=$(jq -r '.mqtt_user // "gateway"' "$CONFIG_DIR/site.json")
MQTT_PASS=$(jq -r '.mqtt_pass // "buoy"' "$CONFIG_DIR/site.json")
TAILSCALE_KEY=$(jq -r '.tailscale_auth_key // ""' "$CONFIG_DIR/site.json")
HOSTNAME_CUSTOM=$(jq -r '.hostname // ""' "$CONFIG_DIR/site.json")

echo "[first-boot] Device ID: $DEVICE_ID"
echo "[first-boot] Site: $SITE_NAME"
echo "[first-boot] MQTT: $MQTT_BROKER"

# --- Set hostname ---
if [ -n "$HOSTNAME_CUSTOM" ]; then
    echo "[first-boot] Setting hostname to: $HOSTNAME_CUSTOM"
    hostnamectl set-hostname "$HOSTNAME_CUSTOM"
fi

# --- System updates ---
echo "[first-boot] Updating package lists..."
apt-get update -qq

echo "[first-boot] Installing prerequisites..."
apt-get install -y -qq jq curl git ca-certificates gnupg lsb-release

# --- Enable SPI (required for RAK2287 concentrator) ---
SPI_NEEDS_REBOOT=false

echo "[first-boot] Enabling SPI interface..."
if ! grep -q "^dtparam=spi=on" /boot/firmware/config.txt; then
    echo "dtparam=spi=on" >> /boot/firmware/config.txt
    SPI_NEEDS_REBOOT=true
    echo "[first-boot] SPI enabled (reboot required)."
else
    echo "[first-boot] SPI already enabled."
fi

# --- Enable I2C (used by gateway-rs for ECC key storage) ---
if ! grep -q "^dtparam=i2c_arm=on" /boot/firmware/config.txt; then
    echo "dtparam=i2c_arm=on" >> /boot/firmware/config.txt
    SPI_NEEDS_REBOOT=true
    echo "[first-boot] I2C enabled."
fi

# --- Install Docker ---
echo "[first-boot] Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    # Add the first non-root user to docker group
    REAL_USER=$(ls /home/ | head -1)
    if [ -n "$REAL_USER" ]; then
        usermod -aG docker "$REAL_USER" 2>/dev/null || true
    fi
    systemctl enable docker
    systemctl start docker
    echo "[first-boot] Docker installed."
else
    echo "[first-boot] Docker already installed."
fi

# --- Install Docker Compose plugin ---
echo "[first-boot] Verifying Docker Compose..."
docker compose version || {
    echo "[first-boot] Installing Docker Compose plugin..."
    apt-get install -y -qq docker-compose-plugin
}

# --- Install Tailscale ---
echo "[first-boot] Installing Tailscale..."
if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "[first-boot] Tailscale installed."
else
    echo "[first-boot] Tailscale already installed."
fi

# Join tailnet if auth key provided
if [ -n "$TAILSCALE_KEY" ]; then
    echo "[first-boot] Joining Tailscale network..."
    tailscale up \
        --auth-key="$TAILSCALE_KEY" \
        --hostname="buoy-${DEVICE_ID}" \
        --ssh \
        --accept-routes
    echo "[first-boot] Tailscale connected. IP: $(tailscale ip -4 2>/dev/null || echo 'pending')"
else
    echo "[first-boot] WARNING: No Tailscale auth key. Run 'sudo tailscale up' manually."
fi

# --- Deploy gateway stack ---
echo "[first-boot] Setting up gateway services..."
mkdir -p "$GATEWAY_DIR"

if [ -d "$CONFIG_DIR/gateway-stack" ]; then
    echo "[first-boot] Copying gateway stack from boot partition..."
    cp -r "$CONFIG_DIR/gateway-stack/"* "$GATEWAY_DIR/"
else
    echo "[first-boot] ERROR: No gateway-stack found on boot partition."
    echo "[first-boot] Run prepare-sd.sh to copy the stack to the SD card."
    exit 1
fi

# Write environment file for docker-compose
cat > "$GATEWAY_DIR/.env" << EOF
MQTT_BROKER=$MQTT_BROKER
MQTT_PORT=1883
MQTT_USER=$MQTT_USER
MQTT_PASS=$MQTT_PASS
DEVICE_ID=$DEVICE_ID
SITE_NAME=$SITE_NAME
EOF

# --- Create systemd service for container auto-start on boot ---
cat > /etc/systemd/system/buoy-gateway.service << 'EOF'
[Unit]
Description=Buoy.fish Gateway Companion Stack
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/buoy-gateway
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable buoy-gateway.service

# --- Handle SPI reboot ---
if [ "$SPI_NEEDS_REBOOT" = true ]; then
    echo "[first-boot] SPI/I2C was just enabled — reboot required."
    echo "[first-boot] Installing rc.local hook to finish after reboot..."

    # Create /etc/rc.local if it doesn't exist
    if [ ! -f /etc/rc.local ]; then
        cat > /etc/rc.local << 'RCEOF'
#!/bin/bash
exit 0
RCEOF
        chmod +x /etc/rc.local
    fi

    # Insert our continuation hook before "exit 0"
    # On next boot, rc.local runs first-boot.sh again. The script detects
    # SPI is already enabled, skips the reboot path, builds containers,
    # marks as provisioned, and cleans the rc.local entry.
    sed -i '/^exit 0/i # --- Buoy.fish: finish provisioning after SPI reboot ---\n/bin/bash /boot/firmware/buoy-config/first-boot.sh &' /etc/rc.local

    echo "[first-boot] Rebooting in 5s to activate SPI/I2C..."
    sleep 5
    reboot
else
    # SPI already enabled (either was already on, or this is the post-reboot run)
    echo "[first-boot] Building and starting containers..."
    cd "$GATEWAY_DIR"
    docker compose build
    docker compose up -d
    echo "[first-boot] Containers started:"
    docker compose ps

    # --- Mark as provisioned ---
    touch "$MARKER"
    echo "$DEVICE_ID" > "$MARKER"

    # --- Clean up rc.local hook if present ---
    if [ -f /etc/rc.local ] && grep -q "buoy-config/first-boot.sh" /etc/rc.local; then
        sed -i '/# --- Buoy.fish: finish provisioning/d' /etc/rc.local
        sed -i '/buoy-config\/first-boot.sh/d' /etc/rc.local
        echo "[first-boot] Cleaned up rc.local hook."
    fi

    echo "============================================="
    echo "[first-boot] Provisioning complete!"
    echo "[first-boot] Device ID: $DEVICE_ID"
    echo "[first-boot] Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'not connected')"
    echo "[first-boot] Gateway dir: $GATEWAY_DIR"
    echo "[first-boot] Logs: sudo cat $LOG_FILE"
    echo "============================================="
fi
