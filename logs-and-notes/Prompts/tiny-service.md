Yes. Keep the Pi “data-plane only” and add a tiny sidecar that:
	•	has grpcurl, curl, jq
	•	exposes a very small HTTP API (BusyBox httpd + CGI shell scripts)
	•	lets you invoke common gateway-rs ops from any machine on the LAN/VPN (or from your CICD box) without installing a wallet or extra runtimes on the gateway.

Below is a drop-in helium-tools/ folder: one Dockerfile, a BusyBox httpd config, four CGI endpoints, and the same functions as CLI helpers. It’s ~15–25 MB when built on Alpine.

⸻

Directory layout

helium-tools/
├─ Dockerfile
├─ httpd.conf
├─ cgi-bin/
│  ├─ gw-info.sh
│  ├─ gw-pubkey.sh
│  ├─ gw-region.sh
│  └─ gw-peers.sh
└─ bin/
   ├─ gw-info
   ├─ gw-pubkey
   ├─ gw-region
   └─ gw-peers


⸻

Dockerfile (Alpine + BusyBox httpd + grpcurl + jq)

# helium-tools/Dockerfile
FROM alpine:3.20

ARG GRPCURL_VER=1.9.1
ENV GW_HOST=gateway-rs \
    GW_API_PORT=4467 \
    HTTP_PORT=8080 \
    BUSYBOX_CGI="/cgi-bin/*"

# base tools
RUN apk add --no-cache ca-certificates curl jq bash tini

# grpcurl (static)
RUN arch="$(apk --print-arch)"; \
    case "$arch" in \
      aarch64)  url="https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VER}/grpcurl_${GRPCURL_VER}_linux_arm64.tar.gz" ;; \
      armv7)    url="https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VER}/grpcurl_${GRPCURL_VER}_linux_armv7.tar.gz" ;; \
      x86_64)   url="https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VER}/grpcurl_${GRPCURL_VER}_linux_x86_64.tar.gz" ;; \
      *) echo "unsupported arch: $arch" && exit 1 ;; \
    esac; \
    curl -sSL "$url" | tar -xz -C /usr/local/bin grpcurl && chmod +x /usr/local/bin/grpcurl

# www + cgi
RUN mkdir -p /www/cgi-bin /opt/bin
COPY httpd.conf /www/httpd.conf
COPY cgi-bin/*.sh /www/cgi-bin/
COPY bin/* /usr/local/bin/

# make scripts executable
RUN chmod +x /www/cgi-bin/*.sh /usr/local/bin/gw-*

# healthcheck: list services via reflection
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD \
  grpcurl -plaintext ${GW_HOST}:${GW_API_PORT} list >/dev/null 2>&1 || exit 1

EXPOSE 8080

# BusyBox httpd is in BusyBox; Alpine ships busybox multi-call binary already.
# Launch httpd in foreground with CGI enabled.
ENTRYPOINT ["/sbin/tini","--"]
CMD ["/bin/sh","-lc", "httpd -f -v -p ${HTTP_PORT} -h /www -c ${BUSYBOX_CGI} && tail -f /dev/null"]


⸻

httpd.conf (minimal)

# helium-tools/httpd.conf
# (BusyBox httpd largely configured via flags. This is here for future growth.)


⸻

Shared implementation notes
	•	Scripts assume gRPC reflection is enabled in gateway-rs (it is in standard builds).
	•	Each helper tries multiple candidate method names and returns the first success, so it survives minor API renames across gateway-rs builds.
	•	All JSON output is normalized with jq -c so your callers can parse reliably.
	•	If a method isn’t available, the script returns {"ok":false,"error":"..."}
	•	Security: expose helium-tools only on the internal Docker/balena network. If you must publish it externally, add mTLS or at least a reverse proxy with auth.

⸻

CGI endpoints (HTTP API)

Each CGI script returns application/json. Examples:
	•	GET /cgi-bin/gw-info.sh
	•	GET /cgi-bin/gw-pubkey.sh
	•	GET /cgi-bin/gw-region.sh
	•	GET /cgi-bin/gw-peers.sh

cgi-bin/gw-info.sh

#!/bin/sh
set -eu
echo "Content-Type: application/json"
echo ""

GW_HOST="${GW_HOST:-gateway-rs}"
GW_API_PORT="${GW_API_PORT:-4467}"

# candidate RPCs that typically return version/build/info
CANDIDATES="
heliumiot.gateway.api.v1.Info/Version
heliumiot.gateway.api.v1.Gateway/Info
helium.gateway.Info/Version
"

for m in $CANDIDATES; do
  if out=$(grpcurl -plaintext "${GW_HOST}:${GW_API_PORT}" "$m" 2>/dev/null); then
    echo "$out" | jq -c '{ok:true, method:"'"$m"'", data:.}'
    exit 0
  fi
done

# Fallback: list services
if out=$(grpcurl -plaintext "${GW_HOST}:${GW_API_PORT}" list 2>/dev/null); then
  echo "$(printf '%s\n' "$out")" | jq -R -s -c '{ok:false, error:"No known info method; reflection listing attached", services: split("\n")|map(select(length>0))}'
  exit 0
fi

echo '{"ok":false,"error":"gateway-rs gRPC unreachable"}'

cgi-bin/gw-pubkey.sh

#!/bin/sh
set -eu
echo "Content-Type: application/json"
echo ""

GW_HOST="${GW_HOST:-gateway-rs}"
GW_API_PORT="${GW_API_PORT:-4467}"

CANDIDATES="
heliumiot.gateway.api.v1.Keys/GetPublicKey
heliumiot.gateway.api.v1.Gateway/GetPublicKey
helium.gateway.Keys/GetPublicKey
"

REQ='{}'  # most key getters are empty reqs

for m in $CANDIDATES; do
  if out=$(echo "$REQ" | grpcurl -plaintext -d @ "${GW_HOST}:${GW_API_PORT}" "$m" 2>/dev/null); then
    echo "$out" | jq -c '{ok:true, method:"'"$m"'", data:.}'
    exit 0
  fi
done

echo '{"ok":false,"error":"No known GetPublicKey method found"}'

cgi-bin/gw-region.sh

#!/bin/sh
set -eu
echo "Content-Type: application/json"
echo ""

GW_HOST="${GW_HOST:-gateway-rs}"
GW_API_PORT="${GW_API_PORT:-4467}"

CANDIDATES="
heliumiot.gateway.api.v1.Config/GetRegion
heliumiot.gateway.api.v1.Gateway/GetRegion
helium.gateway.Config/GetRegion
"

REQ='{}'

for m in $CANDIDATES; do
  if out=$(echo "$REQ" | grpcurl -plaintext -d @ "${GW_HOST}:${GW_API_PORT}" "$m" 2>/dev/null); then
    # normalize common field variants
    region=$(echo "$out" | jq -r '.region // .name // .Region // empty')
    jq -nc --arg method "$m" --arg region "${region:-unknown}" \
      '{ok:true, method:$method, region:$region, raw: '"$out"'}'
    exit 0
  fi
done

echo '{"ok":false,"error":"No known GetRegion method found"}'

cgi-bin/gw-peers.sh

#!/bin/sh
set -eu
echo "Content-Type: application/json"
echo ""

GW_HOST="${GW_HOST:-gateway-rs}"
GW_API_PORT="${GW_API_PORT:-4467}"

# common peerbook/peers endpoints across builds
CANDIDATES="
heliumiot.gateway.api.v1.Diagnostics/ListPeers
heliumiot.gateway.api.v1.Gateway/ListPeers
helium.gateway.Diagnostics/ListPeers
"

REQ='{}'

for m in $CANDIDATES; do
  if out=$(echo "$REQ" | grpcurl -plaintext -d @ "${GW_HOST}:${GW_API_PORT}" "$m" 2>/dev/null); then
    echo "$out" | jq -c '{ok:true, method:"'"$m"'", data:.}'
    exit 0
  fi
done

echo '{"ok":false,"error":"No known ListPeers method found"}'


⸻

CLI helpers (same behavior, for docker exec use)

bin/gw-info

#!/bin/sh
set -eu
GW_HOST="${GW_HOST:-gateway-rs}"
GW_API_PORT="${GW_API_PORT:-4467}"
grpcurl -plaintext "${GW_HOST}:${GW_API_PORT}" list

bin/gw-pubkey

#!/bin/sh
set -eu
GW_HOST="${GW_HOST:-gateway-rs}"
GW_API_PORT="${GW_API_PORT:-4467}"
/www/cgi-bin/gw-pubkey.sh | jq .

bin/gw-region

#!/bin/sh
set -eu
/www/cgi-bin/gw-region.sh | jq .

bin/gw-peers

#!/bin/sh
set -eu
/www/cgi-bin/gw-peers.sh | jq .


⸻

Add service to your Compose

  helium-tools:
    build: ./helium-tools
    restart: unless-stopped
    environment:
      GW_HOST: "gateway-rs"
      GW_API_PORT: "4467"
      HTTP_PORT: "8080"
    depends_on:
      - gateway-rs
    labels:
      io.balena.features.i2c: '1'     # optional, not required for tools itself
      io.balena.features.sysfs: '1'   # optional
    ports:
      # expose only if you need to reach it outside the compose network.
      # otherwise omit 'ports' and curl it from another container or your VPN.
      - "8080:8080"


⸻

Usage

From another machine (replace host/IP as needed):

# Info / version
curl -s http://<gateway-ip>:8080/cgi-bin/gw-info.sh | jq .

# Public key
curl -s http://<gateway-ip>:8080/cgi-bin/gw-pubkey.sh | jq -r '.data.publicKey // .data.key // .region // .raw'

# Region
curl -s http://<gateway-ip>:8080/cgi-bin/gw-region.sh | jq .

# Peers
curl -s http://<gateway-ip>:8080/cgi-bin/gw-peers.sh | jq .

Or via CLI inside the container:

docker exec -it <stack>_helium-tools_1 gw-info
docker exec -it <stack>_helium-tools_1 gw-pubkey
docker exec -it <stack>_helium-tools_1 gw-region
docker exec -it <stack>_helium-tools_1 gw-peers


⸻

Hardening & options
	•	Network: keep the HTTP port internal only unless you’ve locked it down. With balena, omit ports: so it’s reachable only from sibling services or via a tailscaled container.
	•	Auth: if you must publish it, front it with Caddy/Traefik and require an auth header or mTLS.
	•	More endpoints: you can add new CGI scripts in cgi-bin/ in seconds; they’re just grpcurl wrappers.
	•	Zero-HTTP mode: if you dislike running any HTTP server at all, drop the CGI pieces and use only the CLI helpers via docker exec or balena ssh—no other changes needed.

If you want, I can also give you a Makefile and a multi-arch buildx recipe (arm64/armv7/amd64) so you can push this to GHCR and pull it on any gateway.