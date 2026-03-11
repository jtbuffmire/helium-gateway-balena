---
allowed-tools: Bash(ssh *), Bash(python3 *)
description: "Helium HPR status for buoy tenant. No flags = quick summary (sync count + balance). --check-routes for detailed route/device diff. --check-balance for detailed DC balance."
---

## Context

- Buoy tenant UUID: `e1d293fb-6dc5-4214-a23a-94696f17f82f`
- Buoy OUI: `2109`
- ChirpStack server: `console.buoy.fish` (SSH as `ubuntu`)
- Helium CLI: `/usr/local/bin/helium-config-service-cli`
- CLI env: `/helium/cli/env.sh`
- 1 DC = 1 packet = $0.00001

## Arguments

User provided: $ARGUMENTS

Parse the arguments:
- No flags → run **Quick Summary** (default)
- `--check-routes` → run **Detailed Routes**
- `--check-balance` → run **Detailed Balance**
- Both flags → run both detailed sections
- One or more DevEUIs (hex strings like `70b3d570500144c4`) → run **EUI Lookup**
- CSV data with columns like `DevEUI, JoinEUI / AppEUI, NwkKey` (from LoRaWAN Provisioning tool) → run **Provisioning Diagnostic**

---

## Data Collection

All modes need some or all of these. Run what you need, parallelizing independent calls.

### A. Get route ID and ChirpStack devices (two separate SSH commands, run in parallel)

**A1. Route ID:**
```
ssh ubuntu@console.buoy.fish "docker exec helium-postgres-1 psql -U chirpstack -d chirpstack -t -A -c \"SELECT route_id FROM helium_tenant_setup WHERE tenantuuid = 'e1d293fb-6dc5-4214-a23a-94696f17f82f'\""
```

**A2. ChirpStack devices** (returns `eui_hex|name` per line):
```
ssh ubuntu@console.buoy.fish "docker exec helium-postgres-1 psql -U chirpstack -d chirpstack -t -A -c \"SELECT encode(d.dev_eui, 'hex') || '|' || d.name FROM device d JOIN device_profile dp ON d.device_profile_id = dp.id WHERE dp.tenant_id = 'e1d293fb-6dc5-4214-a23a-94696f17f82f' ORDER BY d.name\""
```

Run A1 and A2 in parallel (they're independent). Do NOT combine into a single psql `-c` flag — psql swallows the first result.

### B. Get HPR DevEUIs (needs route ID from step A — extract just EUIs with jq)

```
ssh ubuntu@console.buoy.fish "cd /helium/cli && source env.sh && helium-config-service-cli route euis list -r <ROUTE_ID> | jq -r '.[].dev_eui'"
```

This outputs one uppercase DevEUI per line (no JSON bloat).

### C. Compute the diff

Pass the CS and HPR outputs to a local python3 script via stdin. Example:

```python
import sys
# Parse CS devices: lines starting with "CS:" → {eui_lower: name}
# Parse HPR EUIs: one per line, lowercase
# Compute: missing = CS - HPR, orphaned = HPR - CS, synced = CS ∩ HPR
# Print results
```

This avoids dumping huge lists into the conversation and doing manual comparison.

---

## Quick Summary (default, no flags)

1. Run step A.
2. Run step B (using route ID from A).
3. Compute the diff with python3 (step C).
4. Output a compact summary exactly like this:

```
Helium HPR — Buoy
Routes: 208/209 synced
  Missing: Boat Hauling Orca (0016c001f016ca38)
```

Rules:
- **Routes line**: `<synced count>/<total ChirpStack devices> synced`
- **Missing line**: only show if some ChirpStack devices are NOT in HPR. List name + DevEUI.
- **Orphaned line**: only show if HPR has DevEUIs NOT in ChirpStack. List the DevEUIs.
- If everything is synced, the output is just one line. Keep it tight.

NOTE: The helium-config-service-cli does NOT have a DC balance command. Do NOT attempt to query balance — it will just error. Skip balance reporting entirely.

---

## Detailed Routes (--check-routes)

Run steps A–C, then produce a full table showing ONLY mismatches:

| DevEUI | Name | Status |
|--------|------|--------|
| 0016c001f016ca38 | Boat Hauling Orca | MISSING |

- Only list MISSING and ORPHANED devices (don't list all 200+ synced devices)
- Show totals: "208/209 synced, 1 missing, 0 orphaned"
- **MISSING** = in ChirpStack but not in HPR → Helium won't route packets for this device
- **ORPHANED** = in HPR but not in ChirpStack → stale entry, wastes nothing but is messy
- If fully synced, just say "All N devices synced" with no table

---

## EUI Lookup (one or more DevEUIs provided)

When the user provides DevEUI(s) as arguments (e.g. `/helium 70b3d570500144c4 0016c001f016ca38`):

### 1. Gather data (run all three in parallel where possible)

**HPR route check** — run A1 first to get route ID, then:
```
ssh ubuntu@console.buoy.fish "cd /helium/cli && source env.sh && helium-config-service-cli route euis list -r <ROUTE_ID> | jq -r '.[].dev_eui'"
```

**Join status** — query ChirpStack DB for session info on the provided EUIs.
Build a WHERE clause with all the EUIs and run a single query:
```
ssh ubuntu@console.buoy.fish "docker exec helium-postgres-1 psql -U chirpstack -d chirpstack -t -A -c \"
SELECT encode(dev_eui, 'hex') || '|' || name || '|' || COALESCE(encode(dev_addr, 'hex'), '') || '|' || COALESCE(last_seen_at::text, '') || '|' || CASE WHEN device_session IS NOT NULL THEN 'joined' ELSE 'not_joined' END
FROM device
WHERE dev_eui IN (decode('<EUI1>', 'hex'), decode('<EUI2>', 'hex'), ...)
\""
```

This returns per device: `eui|name|dev_addr|last_seen_at|joined_status`

### 2. Output a compact per-EUI report

```
Helium HPR — EUI Lookup (3 devices)
  70b3d570500144c4  Test (44c4)              route: ✓  join: ✓ (addr: 78000191)
  70b3d5705001453f  ISN: Panga 1 (453F)      route: ✓  join: ✓ (addr: 78000193)
  0016c001f016ca38  Boat Hauling Orca (0003) route: ✗  join: ✗
```

### Rules
- Normalize all EUIs to lowercase for comparison (HPR returns uppercase)
- If a DevEUI is not found in ChirpStack, show `(unknown device)` for the name
- **route** = ✓ if DevEUI found in HPR EUI list, ✗ if not
- **join** = ✓ if `device_session IS NOT NULL` (show dev_addr), ✗ if no active session
- If `last_seen_at` is set, include it: `join: ✓ (addr: 78000191, seen: 2026-03-07 14:22)`
- Keep it to one line per EUI

---

## Provisioning Diagnostic (CSV data pasted)

When the user pastes CSV data from the LoRaWAN Provisioning tool (Digital Matter OEM tool or similar), run a full join-failure diagnostic checklist.

### Detecting this mode

The input will contain comma-separated rows with columns like:
`Synced, Device Type, DevEUI, Firmware, JoinEUI / AppEUI, NwkKey (1.1) / AppKey (1.0), AppKey (1.1), ...`

Parse the CSV. For duplicate DevEUIs (e.g. one "Unsynced" and one "Synced" row), use the **last "Synced" row**. Extract per device:
- `dev_eui` (column 3)
- `join_eui` (column 5, = JoinEUI / AppEUI)
- `nwk_key` (column 6, = "NwkKey (1.1) / AppKey (1.0)" — this is the LoRaWAN 1.0 AppKey)
- `app_key_11` (column 7, = "AppKey (1.1)")

### Data to gather

Run these in parallel:

**1. Route ID** (step A1)

**2. HPR DevEUIs** (step B, needs route ID)

**3. Keys + join status from ChirpStack** — single query for all DevEUIs:
```
ssh ubuntu@console.buoy.fish "docker exec helium-postgres-1 psql -U chirpstack -d chirpstack -t -A -c \"
SELECT encode(dk.dev_eui, 'hex') || '|' || encode(dk.nwk_key, 'hex') || '|' || encode(dk.app_key, 'hex') || '|' || encode(d.join_eui, 'hex') || '|' || d.name || '|' || CASE WHEN d.device_session IS NOT NULL THEN 'joined' ELSE 'not_joined' END || '|' || CASE WHEN d.is_disabled THEN 'disabled' ELSE 'enabled' END
FROM device_keys dk
JOIN device d ON dk.dev_eui = d.dev_eui
WHERE dk.dev_eui IN (decode('<EUI1>', 'hex'), decode('<EUI2>', 'hex'), ...)
\""
```

Returns per device: `eui|nwk_key|app_key|join_eui|name|join_status|enabled_status`

**Column mapping** (critical — names differ between provisioning tool and ChirpStack):
| Provisioning Tool Column | ChirpStack DB Column | What it is |
|---|---|---|
| NwkKey (1.1) / AppKey (1.0) | `device_keys.nwk_key` | The key used for LoRaWAN 1.0 OTAA join |
| AppKey (1.1) | `device_keys.app_key` | LoRaWAN 1.1 key (often all-zeros in CS for 1.0 devices) |
| JoinEUI / AppEUI | `device.join_eui` | Must match for join to succeed |

### Checklist per device

For each DevEUI, run through this diagnostic checklist:

1. **In ChirpStack?** — Is the DevEUI registered? If not → `NOT IN LNS`
2. **On HPR route?** — Is the DevEUI in the Helium HPR EUI list? If not → `NOT ON ROUTE` (Helium won't forward JoinRequests)
3. **Device enabled?** — Is `is_disabled = false`? If disabled → `DISABLED`
4. **JoinEUI match?** — Does provisioning tool JoinEUI match ChirpStack `join_eui`? Mismatch → `JOINEUI MISMATCH`
5. **NwkKey match?** — Does provisioning tool NwkKey match ChirpStack `nwk_key`? Mismatch → `APPKEY MISMATCH` (this is the key that matters for 1.0 OTAA)
6. **AppKey(1.1) match?** — Only check if ChirpStack `app_key` is NOT all-zeros (zeros = LoRaWAN 1.0 mode, 1.1 key unused). If non-zero and mismatched → `APPKEY_11 MISMATCH`
7. **Joined?** — Does the device have an active session? If not → `NOT JOINED`

### Output format

```
Helium HPR — Provisioning Diagnostic (15 devices)

✓ All keys match LNS (15/15)
✓ All on HPR route (15/15)
✗ 3 devices not joined: ISN: Panga 2 (436B), ISN: Panga 3 (44CC), PEG: Panga 8 (44B5)

Unjoined devices have correct keys and are on the route.
Likely cause: devices not powered on, out of gateway range, or sub-band mismatch.
```

If there ARE key/route mismatches, show them prominently:
```
Helium HPR — Provisioning Diagnostic (15 devices)

ISSUES FOUND:
  70b3d5705001436b  ISN: Panga 2 (436B)   APPKEY MISMATCH
    device: 6118effb4f716ce6...  LNS: aa82a32943adf236...
  70b3d570500144b5  PEG: Panga 8 (44B5)   NOT ON ROUTE

Summary: 13/15 keys OK, 14/15 on route, 12/15 joined
```

### Rules
- Normalize all hex to lowercase for comparison
- ChirpStack `app_key` of all-zeros (`00000000...`) means LoRaWAN 1.0 mode — skip the 1.1 key comparison
- If all checks pass but device still hasn't joined, suggest: RF/coverage issue, device not powered, sub-band mismatch (US915 SB2 expected)
- Keep output actionable — tell the user what to fix

---

## Detailed Balance (--check-balance)

The helium-config-service-cli does NOT have a DC balance subcommand.

Instead, report the OUI payer wallet address and tell the user to check it manually:
- Payer wallet: `14et5dVer2WvW7xUZUTSvK2ViXz9Y47mU2HMJi5KkYATmtzNbr4`
- Check via: Helium Explorer or Solana explorer for the mapped Solana address
