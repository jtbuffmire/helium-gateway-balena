# Buoy.fish Gateway Companion Image

Self-managed Raspberry Pi gateway image that replaces Balena. Runs the same
container stack (UDP Packet Forwarder, ChirpStack Multiplexer, Helium gateway-rs)
plus a management agent that phones home to the Phoenix server via MQTT.

## What's in the box

```
buoy-gateway-image/
  docker-compose.yml          # Container orchestration (replaces balena docker-compose)
  services/
    cs-mux/                   # ChirpStack Packet Multiplexer
    udp-packet-forwarder/     # RAK UDP PF with custom reset script
    rak-config-seed/          # Seeds local_conf.json
  agent/
    buoy_agent.py             # Fleet management daemon (replaces Balena supervisor)
  provisioning/
    first-boot.sh             # Runs on first boot: installs Docker, Tailscale, starts stack
    prepare-sd.sh             # Run on your Mac to prep an SD card
    example-site.json         # Template for site-specific config
```

## Quick Start

### 1. Flash Raspberry Pi OS Lite

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or Etcher to flash
**Raspberry Pi OS Lite (64-bit, Bookworm)** to an SD card.

### 2. Prepare the SD card

```bash
# Re-insert the SD card after flashing
cd buoy-gateway-image/provisioning

# Copy the example config and edit it
cp example-site.json my-site.json
# Edit my-site.json: set device_id, site_name, tailscale_auth_key, etc.

# Prep the SD card (macOS example)
./prepare-sd.sh /Volumes/bootfs my-site.json
```

### 3. Boot and provision

```bash
# Insert SD card into Pi, power on, wait ~60 seconds
ssh pi@<pi-ip>            # password: buoyfish

# Run first-boot provisioning
sudo bash /boot/firmware/buoy-config/first-boot.sh
```

The script will install Docker, Tailscale, build the containers, and start everything.
After ~5 minutes, the Pi will be on your Tailscale network and reporting to mqtt.buoy.fish.

### 4. Verify

```bash
# Check Tailscale
tailscale status

# Check containers
cd /opt/buoy-gateway
docker compose ps
docker compose logs buoy-agent
```

## Architecture

```
LoRa Sensors
    |
    | (LoRa radio)
    v
RAK2287 Concentrator (on Pi HAT)
    |
    | (SPI)
    v
udp-packet-forwarder ──(UDP 1700)──> cs-mux ──> gateway-rs (Helium)
                                        |
                                        └──> [future: ChirpStack, TTN, etc.]

buoy-agent ──(MQTT)──> mqtt.buoy.fish ──> Phoenix Server
    |
    └── Tailscale VPN ──> Remote SSH from anywhere
```

## Remote Management

Once provisioned, the Pi is reachable via Tailscale:

```bash
# SSH from anywhere
ssh pi@buoy-baja-1      # Tailscale hostname

# Or via the Phoenix app's MQTT commands:
# Restart a container
mosquitto_pub -h mqtt.buoy.fish -u gateway -P buoy \
  -t "buoy/fleet/baja-companion-1/commands" \
  -m '{"action":"restart_container","params":{"name":"cs-mux"},"request_id":"1"}'

# Reroute LNS (the insurance feature)
mosquitto_pub -h mqtt.buoy.fish -u gateway -P buoy \
  -t "buoy/fleet/baja-companion-1/commands" \
  -m '{"action":"reroute_lns","params":{"server":"newlns.example.com:1700"},"request_id":"2"}'
```

## Generating a Tailscale Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Click "Generate auth key"
3. Enable: Reusable, Pre-approved
4. Add tag: `tag:buoy-gateway`
5. Copy the key into your site.json

## Hardware

- Raspberry Pi 4 (2GB+ RAM)
- RAK2287 LoRa concentrator with Pi HAT
- PoE HAT (recommended for field deployments)
- 32GB+ microSD card
- Ethernet cable to RAK gateway (for companion mode)
