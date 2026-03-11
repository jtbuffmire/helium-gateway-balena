#!/bin/sh
# Generate cs-mux TOML config from environment variables.
# Each endpoint can be toggled via env vars in .env.

CONFIG="/tmp/chirpstack-packet-multiplexer.toml"

cat > "$CONFIG" <<TOML
[logging]
  level = "${LOG_LEVEL:-info}"

[multiplexer]
  bind = "0.0.0.0:1700"
TOML

# Helium gateway-rs
if [ -n "$HELIUM_ENDPOINT" ]; then
  cat >> "$CONFIG" <<TOML

  [[multiplexer.server]]
    server = "$HELIUM_ENDPOINT"
    uplink_only = false
TOML
  echo "[cs-mux] Helium endpoint: $HELIUM_ENDPOINT"
fi

# Direct LNS (ChirpStack)
if [ -n "$DIRECT_LNS_ENDPOINT" ]; then
  cat >> "$CONFIG" <<TOML

  [[multiplexer.server]]
    server = "$DIRECT_LNS_ENDPOINT"
    uplink_only = false
TOML
  echo "[cs-mux] Direct LNS endpoint: $DIRECT_LNS_ENDPOINT"
fi

# Packet logger
if [ -n "$PKT_LOGGER_ENDPOINT" ]; then
  cat >> "$CONFIG" <<TOML

  [[multiplexer.server]]
    server = "$PKT_LOGGER_ENDPOINT"
    uplink_only = true
TOML
  echo "[cs-mux] Packet logger endpoint: $PKT_LOGGER_ENDPOINT"
fi

cat >> "$CONFIG" <<TOML

[monitoring]
  bind = "0.0.0.0:9090"
TOML

echo "[cs-mux] Generated config:"
cat "$CONFIG"
echo "---"

exec chirpstack-packet-multiplexer -c "$CONFIG"
