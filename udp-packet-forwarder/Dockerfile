FROM rakwireless/udp-packet-forwarder:latest

# Copy configuration files
COPY global_conf.json /opt/packet-forwarder/
COPY local_conf.json /opt/packet-forwarder/

# Ensure proper permissions
RUN chmod 644 /opt/packet-forwarder/global_conf.json /opt/packet-forwarder/local_conf.json
