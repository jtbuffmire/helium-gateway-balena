FROM tailscale/tailscale:stable

# docker-cli lets a `tailscale ssh` session drive the balena engine
# (socket mounted via io.balena.features.balena-socket) to view logs
# and restart the other services on the device.
RUN apk add --no-cache docker-cli
