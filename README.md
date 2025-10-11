# Helium Gateway with RAK2287

A modern Helium Data-Only Gateway implementation using gateway-rs 1.3.0 and RAK2287 LoRa concentrator for Raspberry Pi 4.

## Features

- **Latest Gateway Software**: Uses gateway-rs v1.3.0 with improved stability and performance
- **RAK2287 Support**: Full support for SX1302-based RAK2287 concentrator
- **Balena Ready**: Designed for easy deployment with Balena Cloud
- **Health Monitoring**: Built-in health checks and automatic restarts
- **Multi-Region**: Supports all major LoRaWAN frequency plans

## Quick Start

### Hardware Setup

1. Install RAK2287 concentrator on Raspberry Pi 4 using the Pi HAT
2. Ensure SPI is enabled in Raspberry Pi configuration
3. Connect antenna to RAK2287

### Software Deployment

1. **Deploy to Balena**:
   - Fork this repository or use "Deploy with balena" button
   - Create a new Balena application
   - Push code to your Balena application

2. **Configure Device Variables**:
   ```
   REGION_OVERRIDE = US915  # Set your region (US915, EU868, AU915, AS923, etc.)
   ```

3. **Optional Variables**:
   ```
   GATEWAY_EUI = ""         # Custom EUI (auto-generated if empty)
   GW_KEYPAIR = ""          # Custom keypair path
   
   # Packet Forwarder Configuration
   MODEL = RAK2287              # Concentrator model
   CONCENTRATOR = SX1302        # Concentrator chip type
   SPI_SPEED = 2000000         # SPI communication speed (Hz)

   # Note: GPIO configuration removed - concentrator initializes without GPIO control

   # Hardware Configuration
   CONCENTRATOR_MODEL = RAK2287    # Concentrator model
   CONCENTRATOR_CHIP = SX1302      # Concentrator chip type
   FREQUENCY_BAND = us_902_928     # Frequency band
   
   # GPS Configuration
   GPS_LATITUDE = 38.851137        # GPS latitude
   GPS_LONGITUDE = -121.269953     # GPS longitude
   HAS_GPS = 0                     # Enable GPS (0/1)
   ```

4. **Adding Multiple LoRaWAN Network Servers**:
   
   To connect to additional networks like TTN or ChirpStack, edit the gwmp-mux configuration:
   ```bash
   # In Balena terminal, edit the gwmp-mux config:
   nano /etc/gwmp-mux/config.toml
   ```
   
   Add additional upstream servers:
   ```toml
   [[upstreams]]
   name = "ttn"
   host = "eu1.cloud.thethings.network"
   port = 1700
   enabled = true
   ```

## Gateway Registration

### Onboarding Helper Script (Recommended)

Use the `gw-ssh.sh` helper script to streamline migrating old Helium miners to your wallet:

```bash
# Get help
./gw-ssh.sh --help

# SSH access with pre-filled onboarding commands
./gw-ssh.sh <device-uuid> --owner <your-wallet-address>

# SSH access only (manual commands)
./gw-ssh.sh <device-uuid>
```

The script provides exact commands to run inside the container and handles wallet address substitution automatically.

### Manual Registration

For recycled gateways, you need to generate a fresh identity:

1. **SSH into container**: `balena device ssh <device-uuid> gateway-rs`
2. **Delete old key**: `rm -f /etc/helium_gateway/gateway_key.bin`
3. **Restart service**: `pkill -f helium_gateway` (auto-restarts)
4. **Generate transaction**: `helium_gateway add --owner <WALLET> --payer <WALLET> --mode dataonly`
5. **Sign locally**: `helium-wallet -f wallet.key hotspots add iot --commit "<TXN>"`

### Getting Gateway Information

```bash
# SSH into container
balena device ssh <device-uuid> gateway-rs

# Get gateway info
helium_gateway -c /etc/helium_gateway/settings.toml key info
```

## Architecture

### Services

- **gateway-service**: Runs the Helium gateway-rs daemon
  - Handles blockchain communication
  - Manages gateway identity and keys
  - Receives packets from gwmp-mux

- **gwmp-mux**: GWMP packet multiplexer (NEW)
  - Multiplexes packets from packet forwarder to multiple upstream servers
  - Enables connection to multiple LoRaWAN Network Servers simultaneously
  - Built from [helium/gwmp-mux](https://github.com/helium/gwmp-mux)

- **packet-forwarder**: Manages the RAK2287 concentrator
  - Interfaces with SX1302 radio
  - Forwards LoRa packets to gwmp-mux
  - Handles regional frequency configuration

### Network Flow

```
LoRa Devices → RAK2287 → packet-forwarder → cs-mux → gateway-service + other LNS → Networks
```

### Packet Multiplexing

The gwmp-mux service allows your gateway to simultaneously connect to:
- Helium Network (via gateway-service)
- The Things Network (TTN)
- ChirpStack servers
- Any other LoRaWAN Network Server

This enables maximum utilization of your LoRa gateway hardware.

## Supported Regions

- **US915**: North America (902-928 MHz)
- **EU868**: Europe (863-870 MHz)
- **AU915**: Australia (915-928 MHz)
- **AS923**: Asia (923 MHz)
- **CN470**: China (470-510 MHz)
- **KR920**: South Korea (920-923 MHz)
- **IN865**: India (865-867 MHz)

## Troubleshooting

### Common Issues

1. **Services not starting**: Check device variables are set correctly
2. **No LoRa packets**: Verify antenna connection and SPI interface
3. **Gateway not connecting**: Check internet connection and region settings

### Logs

Check service logs in Balena Cloud:
- `gateway-service`: Gateway daemon logs
- `packet-forwarder`: Concentrator and packet forwarding logs
- `gwmp-mux`: Packet multiplexing logs

### Health Checks

Both services include health checks:
- Gateway service: Validates key access
- Packet forwarder: Checks concentrator process

## Development

### Local Testing

```bash
# Build and test locally
docker-compose build
docker-compose up

# Check services
docker-compose ps
docker-compose logs gateway-service
docker-compose logs packet-forwarder
```

### Customization

- Modify `gateway-service/settings.toml.template` for gateway configuration
- Adjust `packet-forwarder/start-packet-forwarder.sh` for concentrator settings
- Update `docker-compose.yml` for service parameters

## License

This project combines multiple open-source components:
- gateway-rs: Apache 2.0 License
- RAKWireless UDP Packet Forwarder: MIT License

## Support

- [Helium Documentation](https://docs.helium.com/)
- [Gateway-rs Repository](https://github.com/helium/gateway-rs)
- [RAK2287 Documentation](https://docs.rakwireless.com/)
- [Balena Documentation](https://www.balena.io/docs/)

## Quick Reference

```bash
# Use helper script (recommended)
./gw-ssh.sh <device-uuid> --owner <wallet-address>

# Sign transaction (correct format - no backslash before quotes)
helium-wallet -f wallet.key hotspots add iot --commit "TRANSACTION_HASH"
```