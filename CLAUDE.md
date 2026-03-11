# Helium Gateway - Buoy.fish

## What This Is

LoRaWAN gateway image for Raspberry Pi 4 with RAK2287 concentrator (SX1302 chipset). Deployed on fishing boats and shore stations for Buoy.fish gillnet monitoring network. **Currently deployed via Balena** for the next pilot.

## Current Status

The Balena-based deployment (root-level `docker-compose.yml`) is what we're running for the next pilot. A Docker Compose on bare Raspberry Pi OS migration was explored in `buoy-gateway-image/` but caused problems and is **on hold**. Long-term goal: fully in-house gateway image on a Tailscale network, but out of scope for the next deployment.

## Repository Layout

- `docker-compose.yml` — **Active Balena deployment** (what gets pushed to the fleet)
- `udp-packet-forwarder/` — Forked packet forwarder with custom reset script
- `cs-mux/` — ChirpStack Packet Multiplexer config (Balena service)
- `rak-config-seed/` — RAK concentrator config seed
- `buoy-gateway-image/` — **On hold** — Docker Compose migration for bare Pi OS (not deployed)
- `logs-and-notes/` — Debug logs from extensive SX1302 troubleshooting
- `background/` — Reference materials (sx1302_hal source)

## Packet Flow

```
LoRa Device → RAK2287 → udp-packet-forwarder → cs-mux:1700
                                                   ├→ gateway-rs:1680 (Helium network)
                                                   └→ console.buoy.fish:1701 (direct LNS)
```

## Hardware Targets

| Device | GPIO Reset | Concentrator | Notes |
|--------|-----------|--------------|-------|
| RAK Miner V2 | GPIO 25 | RAK2287 (SX1302) | Pi 4 inside |
| SenseCap M1 | GPIO 17 | SX1302 variant | Different reset pin |

The `RESET_GPIO: "25,17"` env var tries both pins to support both hardware types from a single image.

## Key Services (Balena deployment)

- **cs-mux**: ChirpStack Packet Multiplexer — fans UDP packets to multiple LNS endpoints
- **udp-packet-forwarder**: Semtech UDP packet forwarder, talks to concentrator via SPI
- **gateway-rs**: Helium light gateway (team-helium/miner:gateway-latest)
- **rak-config-seed**: One-shot init container that seeds concentrator config

## Branch Info

- `main` — stable, deployed to Balena fleet
- `buoy/gateway-image` — was used for Docker Compose migration work (on hold, currently identical to main)

## Common Pitfalls

- **SX1302 boot loop**: The concentrator needs a proper GPIO reset pulse on startup. If the reset pin is wrong, the packet forwarder will crash-loop. Fixed by trying both GPIO 25 and 17.
- **Gateway EUI**: Auto-derived from the concentrator chip. Needed to register in ChirpStack before packets will be accepted.

## Future Direction

Long-term plan is to move off Balena to a fully in-house gateway image running on bare Raspberry Pi OS with Tailscale for remote management. The `buoy-gateway-image/` directory contains early work toward this (provisioning scripts, buoy-agent, etc.) but it's not ready for production use.

## LNS Endpoints

- `console.buoy.fish:1701` — Buoy.fish ChirpStack (US915 region port)
- Helium Packet Router — accessed via gateway-rs (requires onboarding)
