# Helium Gateway Onboarding

Quick guide for migrating old Helium miners to your Balena fleet and wallet.

## Prerequisites

- **Helium Wallet**: With sufficient SOL for transaction fees
- **Balena CLI**: Installed locally (`npm install -g balena-cli`)
- **SSH Keys**: Configured in Balena Cloud

## Using the Helper Script (Recommended)

The `gw-ssh.sh` script streamlines the onboarding process:

### Basic Usage

```bash
# Get help
./gw-ssh.sh --help

# SSH access with pre-filled wallet addresses
./gw-ssh.sh <device-uuid> --owner <your-wallet-address>

# SSH access only (manual addresses)
./gw-ssh.sh <device-uuid>
```

### Example

```bash
./gw-ssh.sh b579e7ed3d2e63a2dff20e6c5d330f4d --owner BBDEufJuJEauNJHHoJdzJqnm1Z3VsDfR62Bs8enQzcpN
```

The script will output the exact commands to run inside the container and the correct local signing command.

## Manual Process

If you prefer manual steps:

1. **SSH into container**:
   ```bash
   balena device ssh <device-uuid> gateway-rs
   ```

2. **Inside container**:
   ```bash
   # Delete old key
   rm -f /etc/helium_gateway/gateway_key.bin
   
   # Restart service (auto-generates new key)
   pkill -f helium_gateway || true
   sleep 10
   
   # Check new gateway info
   helium_gateway -c /etc/helium_gateway/settings.toml key info
   
   # Generate add transaction
   helium_gateway add --owner <WALLET> --payer <WALLET> --mode dataonly
   ```

3. **Sign locally** (correct format - no backslash before quotes):
   ```bash
   helium-wallet -f wallet.key hotspots add iot --commit "TRANSACTION_HASH"
   ```

## Troubleshooting

**SSH Authentication Issues**:
- Load SSH key: `ssh-add ~/.ssh/id_rsa`
- Verify: `ssh-add -l`

**Command Syntax Error**:
- ❌ Wrong: `--commit \ "hash"`
- ✅ Correct: `--commit "hash"`

**Container Access**:
- Ensure device is online in Balena dashboard
- Try `balena device ssh <uuid>` (host OS) first to test connection

## Security Notes

- Never store wallet private keys in containers or device variables
- Verify transaction details before signing
- Monitor SOL balance for transaction fees