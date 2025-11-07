#!/bin/bash
# Helium Gateway SSH Helper
# This script provides SSH access and onboarding commands for Helium gateways

set -e

# Default values
DEVICE_UUID=""
OWNER_ADDRESS=""
PAYER_ADDRESS=""

# Function to show help
show_help() {
    cat << EOF
Helium Gateway SSH Helper

USAGE:
    $0 <device-uuid> [OPTIONS]
    $0 --help

ARGUMENTS:
    <device-uuid>           Required. Balena device UUID

OPTIONS:
    --owner <address>       Solana wallet address (owner)
    --payer <address>       Solana wallet address (payer, defaults to owner)
    --help                  Show this help message

EXAMPLES:
    # SSH access only (no onboarding commands)
    $0 abc123def456

    # SSH access with onboarding commands
    $0 abc123def456 --owner FDFowiVotGxYE3CrXsV4Fh2kgUrihSJkzFbwAmc23waU

    # SSH access with custom payer
    $0 abc123def456 --owner OWNER_ADDR --payer PAYER_ADDR

DESCRIPTION:
    This script helps you SSH into your Helium gateway container and provides
    the exact commands needed for onboarding old miners to your wallet.
    
    If no wallet addresses are provided, placeholder commands will be shown
    that you can customize manually.

    IMPORTANT: The command syntax issue you experienced was due to an extra
    backslash. The correct format is:
    
    helium-wallet -f wallet.key hotspots add iot --commit "TRANSACTION_HASH"
    
    NOT: helium-wallet ... --commit \\ "TRANSACTION_HASH"

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --owner)
            OWNER_ADDRESS="$2"
            shift 2
            ;;
        --payer)
            PAYER_ADDRESS="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [ -z "$DEVICE_UUID" ]; then
                DEVICE_UUID="$1"
            else
                echo "Unexpected argument: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [ -z "$DEVICE_UUID" ]; then
    echo "Error: Device UUID is required"
    echo "Use --help for usage information"
    exit 1
fi

# Set payer to owner if not specified
if [ -n "$OWNER_ADDRESS" ] && [ -z "$PAYER_ADDRESS" ]; then
    PAYER_ADDRESS="$OWNER_ADDRESS"
fi

echo "=== Helium Gateway SSH Helper ==="
echo "Device UUID: $DEVICE_UUID"
if [ -n "$OWNER_ADDRESS" ]; then
    echo "Owner Address: $OWNER_ADDRESS"
    echo "Payer Address: $PAYER_ADDRESS"
else
    echo "Mode: SSH access only (no wallet addresses provided)"
fi
echo ""

echo "Due to Balena CLI limitations with remote command execution on containers,"
echo "you'll need to run these commands manually:"
echo ""

echo "=== STEP 1: SSH into your gateway container ==="
echo "balena device ssh $DEVICE_UUID gateway-rs"
echo ""

echo "=== STEP 2: Once inside the container, run these commands ==="
echo "# Delete old key"
echo "rm -f /etc/helium_gateway/gateway_key.bin"
echo ""
echo "# Kill gateway process (it will restart automatically)"
echo "pkill -f helium_gateway || true"
echo ""
echo "# Wait a moment for restart"
echo "sleep 10"
echo ""
echo "# Check new gateway info"
echo "helium_gateway -c /etc/helium_gateway/settings.toml key info"
echo ""
echo "# Generate add transaction"
if [ -n "$OWNER_ADDRESS" ]; then
    echo "helium_gateway add --owner $OWNER_ADDRESS --payer $PAYER_ADDRESS --mode dataonly"
else
    echo "helium_gateway add --owner <YOUR_WALLET_ADDRESS> --payer <YOUR_WALLET_ADDRESS> --mode dataonly"
fi
echo ""

echo "=== STEP 3: Copy the 'txn' value and sign locally ==="
echo "IMPORTANT: No backslash before the transaction hash!"
echo ""
echo "/Users/jt/buoy-fish-tech/network/helium-wallet-x86-64-macos/helium-wallet \\"
echo "  -f /Users/jt/buoy-fish-tech/network/wallets/novascotia/wallet.key \\"
echo "  hotspots add iot --commit \\"
echo "  \"<TXN_VALUE_FROM_STEP_2>\""
echo ""
echo "Example (correct format):"
echo "helium-wallet -f wallet.key hotspots add iot --commit \"CqsBCiEBlzKEVZu...\""
echo ""

echo "=== STEP 4: Optional - Rename device ==="
echo "After onboarding, you can rename your Balena device to match"
echo "the gateway's animal name (shown in step 2 output)"
echo ""

if [ -z "$OWNER_ADDRESS" ]; then
    echo "=== TIP ==="
    echo "For pre-filled wallet addresses, run:"
    echo "$0 $DEVICE_UUID --owner <YOUR_WALLET_ADDRESS>"
    echo ""
fi

echo "===================================================="