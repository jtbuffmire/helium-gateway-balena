"""
Packet Logger for Semtech UDP (GWMP) protocol.
Listens on UDP 1702, decodes PHYPayloads, highlights target DevEUI.
"""

import base64
import json
import socket
import struct
import sys

TARGET_DEVEUI = "70b3d570500144c4"

MTYPE_NAMES = {
    0: "JoinRequest",
    1: "JoinAccept",
    2: "UnconfirmedDataUp",
    3: "UnconfirmedDataDown",
    4: "ConfirmedDataUp",
    5: "ConfirmedDataDown",
    6: "RejoinRequest",
    7: "Proprietary",
}


def decode_phypayload(b64_data):
    """Decode a base64 PHYPayload and return summary info."""
    try:
        raw = base64.b64decode(b64_data)
    except Exception:
        return None

    if len(raw) < 1:
        return None

    mhdr = raw[0]
    mtype = (mhdr >> 5) & 0x07
    mtype_name = MTYPE_NAMES.get(mtype, f"Unknown({mtype})")

    result = {
        "mtype": mtype_name,
        "size": len(raw),
        "raw_hex": raw[:20].hex(),
    }

    # JoinRequest: MHDR(1) + AppEUI(8) + DevEUI(8) + DevNonce(2) + MIC(4) = 23 bytes
    if mtype == 0 and len(raw) >= 23:
        app_eui = raw[1:9][::-1].hex()  # little-endian
        dev_eui = raw[9:17][::-1].hex()  # little-endian
        dev_nonce = struct.unpack("<H", raw[17:19])[0]
        result["app_eui"] = app_eui
        result["dev_eui"] = dev_eui
        result["dev_nonce"] = dev_nonce

    return result


def handle_push_data(data):
    """Parse a PUSH_DATA packet and decode each rxpk."""
    # PUSH_DATA: proto(1) + token(2) + id(1) + gw_mac(8) + json
    if len(data) < 12:
        return

    json_bytes = data[12:]
    try:
        payload = json.loads(json_bytes)
    except json.JSONDecodeError:
        return

    rxpk_list = payload.get("rxpk", [])
    if not rxpk_list:
        return

    for rxpk in rxpk_list:
        b64_data = rxpk.get("data")
        if not b64_data:
            continue

        freq = rxpk.get("freq", "?")
        rssi = rxpk.get("rssi", "?")
        snr = rxpk.get("lsnr", "?")
        datr = rxpk.get("datr", "?")

        info = decode_phypayload(b64_data)
        if not info:
            print(f"  [pkt] freq={freq} rssi={rssi} (decode failed)", flush=True)
            continue

        mtype = info["mtype"]
        size = info["size"]

        if mtype == "JoinRequest":
            dev_eui = info.get("dev_eui", "unknown")
            app_eui = info.get("app_eui", "unknown")
            nonce = info.get("dev_nonce", "?")
            marker = ""
            if dev_eui.lower() == TARGET_DEVEUI.lower():
                marker = " <<< TARGET DEVICE"
            print(
                f">>> JOIN REQUEST DevEUI={dev_eui.upper()} "
                f"AppEUI={app_eui.upper()} Nonce={nonce} "
                f"freq={freq} rssi={rssi} snr={snr}{marker}",
                flush=True,
            )
        else:
            print(
                f"  [{mtype}] {size}B freq={freq} rssi={rssi} "
                f"snr={snr} datr={datr}",
                flush=True,
            )


def main():
    port = 1702
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", port))
    print(f"[pkt-logger] Listening on UDP :{port}", flush=True)
    print(f"[pkt-logger] Target DevEUI: {TARGET_DEVEUI.upper()}", flush=True)

    while True:
        data, addr = sock.recvfrom(65535)
        if len(data) < 4:
            continue

        pkt_type = data[3]

        # PUSH_DATA = 0x00
        if pkt_type == 0x00:
            # Send PUSH_ACK back: proto(1) + token(2) + type(1)
            ack = bytes([data[0], data[1], data[2], 0x01])
            sock.sendto(ack, addr)
            handle_push_data(data)

        # PULL_DATA = 0x02
        elif pkt_type == 0x02:
            # Send PULL_ACK
            ack = bytes([data[0], data[1], data[2], 0x04])
            sock.sendto(ack, addr)


if __name__ == "__main__":
    main()
