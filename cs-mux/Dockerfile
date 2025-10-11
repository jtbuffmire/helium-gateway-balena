FROM chirpstack/chirpstack-packet-multiplexer:4.0.0-test.2

# Copy the configuration file
COPY chirpstack-packet-multiplexer.toml /etc/chirpstack-packet-multiplexer/chirpstack-packet-multiplexer.toml

# Expose the port where packet forwarder connects
EXPOSE 1700/udp

# Use the default entrypoint with our config
CMD ["-c", "/etc/chirpstack-packet-multiplexer/chirpstack-packet-multiplexer.toml"]
