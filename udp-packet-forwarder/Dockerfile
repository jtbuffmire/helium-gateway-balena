# udp-packet-forwarder/Dockerfile
FROM rakwireless/udp-packet-forwarder:latest

# Replace RAK's reset script templates with our custom one that includes
# proper 2000ms power discharge timing for concentrator stability
COPY reset_lgw_custom.sh /app/reset.sh.gpiod
COPY reset_lgw_custom.sh /app/reset.sh.legacy
RUN chmod +x /app/reset.sh.gpiod /app/reset.sh.legacy

# no COPY of rak-config here; config arrives via the mounted volume