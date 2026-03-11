FROM chirpstack/chirpstack-packet-multiplexer:4.0.0-test.2

USER root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
USER nobody

EXPOSE 1700/udp

ENTRYPOINT ["/entrypoint.sh"]
