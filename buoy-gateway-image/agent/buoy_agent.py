"""
Buoy Gateway Agent
Lightweight fleet management daemon that replaces Balena's supervisor.
Connects to the Phoenix server via MQTT for remote monitoring and control.

Capabilities:
  - Heartbeat: publishes device status every 60 seconds
  - Log streaming: tails container logs and publishes to MQTT
  - Command execution: restart containers, update config, reboot
  - Config sync: apply new docker-compose env or multiplexer config
"""

import json
import os
import platform
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

import docker
import paho.mqtt.client as mqtt
import psutil

# --- Configuration ---
MQTT_BROKER = os.environ.get("MQTT_BROKER", "mqtt.buoy.fish")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USER = os.environ.get("MQTT_USER", "gateway")
MQTT_PASS = os.environ.get("MQTT_PASS", "buoy")
DEVICE_ID = os.environ.get("DEVICE_ID", "unprovisioned")
SITE_NAME = os.environ.get("SITE_NAME", "unknown")
HEARTBEAT_INTERVAL = int(os.environ.get("HEARTBEAT_INTERVAL", "60"))

# MQTT topic prefixes
TOPIC_STATUS = f"buoy/fleet/{DEVICE_ID}/status"
TOPIC_LOGS = f"buoy/fleet/{DEVICE_ID}/logs"
TOPIC_COMMANDS = f"buoy/fleet/{DEVICE_ID}/commands"
TOPIC_COMMANDS_ACK = f"buoy/fleet/{DEVICE_ID}/commands/ack"
TOPIC_CONFIG = f"buoy/fleet/{DEVICE_ID}/config"

# --- Docker client ---
try:
    docker_client = docker.from_env()
except Exception as e:
    print(f"[agent] WARNING: Docker not available: {e}")
    docker_client = None

# --- Tailscale IP detection ---
def get_tailscale_ip():
    """Get this device's Tailscale IP address."""
    try:
        result = subprocess.run(
            ["tailscale", "ip", "-4"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None

# --- Container status ---
def get_container_status():
    """Get status of all running containers."""
    if not docker_client:
        return {}
    try:
        containers = docker_client.containers.list(all=True)
        return {
            c.name: {
                "status": c.status,
                "health": c.attrs.get("State", {}).get("Health", {}).get("Status", "n/a"),
                "image": c.image.tags[0] if c.image.tags else "unknown",
                "uptime": c.attrs.get("State", {}).get("StartedAt", ""),
            }
            for c in containers
        }
    except Exception as e:
        return {"error": str(e)}

# --- System metrics ---
def get_system_metrics():
    """Collect system-level metrics."""
    disk = psutil.disk_usage("/")
    return {
        "cpu_percent": psutil.cpu_percent(interval=1),
        "memory_percent": psutil.virtual_memory().percent,
        "memory_available_mb": round(psutil.virtual_memory().available / 1024 / 1024),
        "disk_percent": disk.percent,
        "disk_free_gb": round(disk.free / 1024 / 1024 / 1024, 1),
        "cpu_temp": get_cpu_temp(),
        "uptime_seconds": int(time.time() - psutil.boot_time()),
        "load_avg": list(os.getloadavg()),
    }

def get_cpu_temp():
    """Read Pi CPU temperature."""
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            return round(int(f.read().strip()) / 1000, 1)
    except Exception:
        return None

# --- Gateway health ---
def _strip_ansi(text):
    """Remove ANSI escape codes from text."""
    return re.sub(r'\x1b\[[0-9;]*m', '', text)


def get_gateway_health():
    """Check gateway-specific health: EUI, Helium connectivity, downlink capability."""
    if not docker_client:
        return {"error": "Docker unavailable"}

    health = {}

    # Check packet forwarder: gateway EUI and downlink stats
    try:
        pf = docker_client.containers.get("buoy-gateway-udp-packet-forwarder-1")

        # EUI is in the startup banner — read from beginning of logs (first 2KB)
        startup_logs = _strip_ansi(
            pf.logs(tail=0, since=0).decode("utf-8", errors="replace")[:4096]
        )
        eui_match = re.search(
            r'(?:Gateway EUI|concentrator EUI):\s*(?:0x)?([0-9a-fA-F]{16})', startup_logs
        )
        if eui_match:
            eui = eui_match.group(1).upper()
            health["gateway_eui"] = eui
            health["gateway_eui_valid"] = eui != "0000000000000000"

        # Downlink stats from recent log lines (dwnb = received, txnb = transmitted)
        recent_logs = _strip_ansi(pf.logs(tail=100).decode("utf-8", errors="replace"))
        stat_matches = re.findall(r'dwnb:\s*(\d+).*?txnb:\s*(\d+)', recent_logs)
        if stat_matches:
            health["downlinks_received"] = int(stat_matches[-1][0])
            health["downlinks_transmitted"] = int(stat_matches[-1][1])
    except docker.errors.NotFound:
        health["packet_forwarder"] = "not found"
    except Exception as e:
        health["packet_forwarder_error"] = str(e)

    # Check gateway-rs: Helium session, DNS errors, downlink MAC
    try:
        gw = docker_client.containers.get("buoy-gateway-gateway-rs-1")
        gw_logs = gw.logs(tail=200).decode("utf-8", errors="replace")
        gw_lines = gw_logs.split("\n")

        health["helium_session_active"] = any("initialized session" in l for l in gw_lines)

        dns_errors = sum(1 for l in gw_lines if "dns error" in l.lower())
        health["dns_errors_recent"] = dns_errors

        # Check downlink MAC from most recent uplink log
        mac_lines = [l for l in gw_lines if "downlink_mac=" in l]
        if mac_lines:
            mac_match = re.search(r'downlink_mac=([0-9a-fA-F:]+)', mac_lines[-1])
            if mac_match:
                mac = mac_match.group(1)
                health["downlink_mac_valid"] = mac != "00:00:00:00:00:00:00:00"
    except docker.errors.NotFound:
        health["gateway_rs"] = "not found"
    except Exception as e:
        health["gateway_rs_error"] = str(e)

    return health


# --- Command handlers ---
ALLOWED_COMMANDS = {
    "restart_container",
    "restart_all",
    "reboot",
    "update_mux_config",
    "reroute_lns",
    "get_status",
    "get_logs",
}

def handle_command(client, payload):
    """Execute a validated command and publish the result."""
    try:
        cmd = json.loads(payload)
    except json.JSONDecodeError:
        return

    action = cmd.get("action")
    request_id = cmd.get("request_id", "unknown")
    params = cmd.get("params", {})

    if action not in ALLOWED_COMMANDS:
        ack(client, request_id, "error", f"Unknown command: {action}")
        return

    print(f"[agent] Executing command: {action} (request_id={request_id})")

    try:
        if action == "restart_container":
            name = params.get("name")
            if not name or not docker_client:
                ack(client, request_id, "error", "Missing container name or Docker unavailable")
                return
            container = docker_client.containers.get(name)
            container.restart(timeout=30)
            ack(client, request_id, "ok", f"Restarted {name}")

        elif action == "restart_all":
            subprocess.run(
                ["docker", "compose", "restart"],
                cwd="/app",
                capture_output=True, timeout=120
            )
            ack(client, request_id, "ok", "All containers restarted")

        elif action == "reboot":
            ack(client, request_id, "ok", "Rebooting in 5 seconds")
            time.sleep(5)
            subprocess.run(["sudo", "reboot"])

        elif action == "reroute_lns":
            # The insurance feature: rewrite multiplexer config to point at a new LNS
            new_server = params.get("server")
            uplink_only = params.get("uplink_only", True)
            if not new_server:
                ack(client, request_id, "error", "Missing 'server' param")
                return
            result = reroute_lns(new_server, uplink_only)
            ack(client, request_id, "ok", result)

        elif action == "update_mux_config":
            config_toml = params.get("config")
            if not config_toml:
                ack(client, request_id, "error", "Missing 'config' param")
                return
            # Write new config and restart the multiplexer
            with open("/app/services/cs-mux/chirpstack-packet-multiplexer.toml", "w") as f:
                f.write(config_toml)
            subprocess.run(
                ["docker", "compose", "restart", "cs-mux"],
                cwd="/app",
                capture_output=True, timeout=60
            )
            ack(client, request_id, "ok", "Multiplexer config updated and restarted")

        elif action == "get_status":
            status = build_heartbeat()
            ack(client, request_id, "ok", json.dumps(status))

        elif action == "get_logs":
            container_name = params.get("name", "")
            lines = params.get("lines", 50)
            if docker_client and container_name:
                container = docker_client.containers.get(container_name)
                logs = container.logs(tail=lines).decode("utf-8", errors="replace")
                ack(client, request_id, "ok", logs[-4096:])  # cap at 4KB
            else:
                ack(client, request_id, "error", "Missing container name or Docker unavailable")

    except Exception as e:
        ack(client, request_id, "error", str(e))

def reroute_lns(new_server, uplink_only=True):
    """Add or update an LNS endpoint in the multiplexer config."""
    config_path = "/app/services/cs-mux/chirpstack-packet-multiplexer.toml"
    try:
        with open(config_path, "r") as f:
            config = f.read()

        # Append a new server block
        new_block = f"""
  # Added by buoy-agent at {datetime.now(timezone.utc).isoformat()}
  [[multiplexer.server]]
    server = "{new_server}"
    uplink_only = {"true" if uplink_only else "false"}
"""
        # Insert before [monitoring] section
        if "[monitoring]" in config:
            config = config.replace("[monitoring]", new_block + "\n[monitoring]")
        else:
            config += new_block

        with open(config_path, "w") as f:
            f.write(config)

        # Restart multiplexer
        subprocess.run(
            ["docker", "compose", "restart", "cs-mux"],
            cwd="/app",
            capture_output=True, timeout=60
        )
        return f"Added LNS endpoint {new_server} and restarted multiplexer"
    except Exception as e:
        return f"Failed to reroute: {e}"

def ack(client, request_id, status, result):
    """Publish a command acknowledgement."""
    client.publish(TOPIC_COMMANDS_ACK, json.dumps({
        "request_id": request_id,
        "status": status,
        "result": result,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }), qos=1)

# --- Heartbeat ---
def build_heartbeat():
    """Build a heartbeat payload."""
    return {
        "device_id": DEVICE_ID,
        "site_name": SITE_NAME,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "tailscale_ip": get_tailscale_ip(),
        "hostname": socket.gethostname(),
        "system": get_system_metrics(),
        "containers": get_container_status(),
        "gateway_health": get_gateway_health(),
        "agent_version": "0.2.0",
    }

def heartbeat_loop(client):
    """Publish heartbeat at regular intervals."""
    while True:
        try:
            payload = build_heartbeat()
            client.publish(TOPIC_STATUS, json.dumps(payload), qos=1)
            print(f"[agent] Heartbeat published ({payload['system']['cpu_percent']}% CPU, "
                  f"{payload['system']['memory_percent']}% RAM, "
                  f"{payload['system']['cpu_temp']}°C)")
        except Exception as e:
            print(f"[agent] Heartbeat error: {e}")
        time.sleep(HEARTBEAT_INTERVAL)

# --- Log streaming ---
def log_stream_loop(client):
    """Stream container logs to MQTT (last 10 lines per container, every 30s)."""
    while True:
        if docker_client:
            try:
                for container in docker_client.containers.list():
                    logs = container.logs(tail=5, since=int(time.time()) - 30)
                    if logs:
                        client.publish(TOPIC_LOGS, json.dumps({
                            "source": container.name,
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                            "lines": logs.decode("utf-8", errors="replace").strip().split("\n")[-5:],
                        }), qos=0)
            except Exception as e:
                print(f"[agent] Log stream error: {e}")
        time.sleep(30)

# --- MQTT callbacks ---
def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"[agent] Connected to MQTT broker (rc={reason_code})")
    client.subscribe(TOPIC_COMMANDS, qos=1)
    client.subscribe(TOPIC_CONFIG, qos=1)
    # Publish an immediate heartbeat on connect
    payload = build_heartbeat()
    client.publish(TOPIC_STATUS, json.dumps(payload), qos=1)

def on_message(client, userdata, msg):
    topic = msg.topic
    payload = msg.payload.decode("utf-8", errors="replace")

    if topic == TOPIC_COMMANDS:
        handle_command(client, payload)
    elif topic == TOPIC_CONFIG:
        print(f"[agent] Config update received: {payload[:200]}...")
        # Future: apply config changes

def on_disconnect(client, userdata, flags, reason_code, properties=None):
    print(f"[agent] Disconnected from MQTT broker (rc={reason_code}), reconnecting...")

# --- Main ---
def main():
    print(f"[agent] Buoy Gateway Agent v0.1.0")
    print(f"[agent] Device ID: {DEVICE_ID}")
    print(f"[agent] Site: {SITE_NAME}")
    print(f"[agent] MQTT Broker: {MQTT_BROKER}:{MQTT_PORT}")
    print(f"[agent] Tailscale IP: {get_tailscale_ip() or 'not available'}")

    # Set up MQTT client
    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"buoy-agent-{DEVICE_ID}",
        clean_session=True,
    )
    client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.on_connect = on_connect
    client.on_message = on_message
    client.on_disconnect = on_disconnect

    # Set a last-will message so the server knows if this device goes offline
    client.will_set(TOPIC_STATUS, json.dumps({
        "device_id": DEVICE_ID,
        "status": "offline",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }), qos=1, retain=True)

    # Connect with retry
    while True:
        try:
            client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            break
        except Exception as e:
            print(f"[agent] MQTT connection failed: {e}, retrying in 10s...")
            time.sleep(10)

    # Start background threads
    heartbeat_thread = threading.Thread(target=heartbeat_loop, args=(client,), daemon=True)
    heartbeat_thread.start()

    log_thread = threading.Thread(target=log_stream_loop, args=(client,), daemon=True)
    log_thread.start()

    # Handle graceful shutdown
    def shutdown(sig, frame):
        print(f"[agent] Shutting down (signal {sig})...")
        client.publish(TOPIC_STATUS, json.dumps({
            "device_id": DEVICE_ID,
            "status": "shutting_down",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }), qos=1)
        client.disconnect()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    # Run MQTT loop (blocking)
    client.loop_forever()

if __name__ == "__main__":
    main()
