# udp-packet-forwarder/Dockerfile
FROM rakwireless/udp-packet-forwarder:latest

# Copy power cycle script
COPY power_cycle_lgw.sh /usr/local/bin/power_cycle_lgw.sh
RUN chmod +x /usr/local/bin/power_cycle_lgw.sh

# Find and patch RAK's startup script to run power cycle first
# This discovers whatever entrypoint RAK uses and wraps it
RUN ORIGINAL_ENTRYPOINT=$(find / -name "start.sh" -o -name "entrypoint.sh" 2>/dev/null | head -1) && \
    if [ -n "$ORIGINAL_ENTRYPOINT" ]; then \
        mv "$ORIGINAL_ENTRYPOINT" "${ORIGINAL_ENTRYPOINT}.original" && \
        echo '#!/bin/bash' > "$ORIGINAL_ENTRYPOINT" && \
        echo '/usr/local/bin/power_cycle_lgw.sh' >> "$ORIGINAL_ENTRYPOINT" && \
        echo "exec ${ORIGINAL_ENTRYPOINT}.original \"\$@\"" >> "$ORIGINAL_ENTRYPOINT" && \
        chmod +x "$ORIGINAL_ENTRYPOINT"; \
    fi

# no COPY of rak-config here; config arrives via the mounted volume