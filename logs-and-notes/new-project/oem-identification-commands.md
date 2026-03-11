# Commands to Identify Gateway OEM from Host OS

## Method 1: Check Which GPIO is Actually Used (Most Reliable)

The configuration tries GPIO 25 (RAK2004/Helium) first, then GPIO 17 (SenseCAP M1). Check container logs to see which GPIO successfully initialized:

```bash
# SSH into the Balena device
balena device ssh <device-uuid>

# Check udp-packet-forwarder container logs for GPIO usage
balena logs udp-packet-forwarder | grep -i "gpio\|reset"

# Or check which GPIO successfully reset the concentrator
balena logs udp-packet-forwarder | grep -i "reset\|initialized"
```

**Interpretation**:
- If GPIO 25 works → Likely RAK2004/Helium unit
- If GPIO 17 works → Likely SenseCAP M1 unit

## Method 2: Check GPIO Chip Information

```bash
# On host OS
gpiodetect

# This will show GPIO chips and their labels
# Example output:
# gpiochip0 [pinctrl-bcm2711] (58 lines)
```

## Method 3: Check I2C Devices (Some Manufacturers Have Specific Addresses)

```bash
# List I2C buses
ls /dev/i2c-*

# Scan I2C bus 1 for devices (common for Raspberry Pi)
i2cdetect -y 1

# Check for manufacturer-specific I2C addresses
# SenseCAP M1 may have specific I2C devices
```

## Method 4: Check USB Devices (If Connected via USB)

```bash
# List USB devices
lsusb

# Get detailed USB device information
lsusb -v | grep -i "manufacturer\|product"

# Check for SenseCAP or RAK identifiers
lsusb | grep -i "sensecap\|rak"
```

## Method 5: Check Device Tree Information

```bash
# Check device tree for hardware identifiers
cat /proc/device-tree/model

# Check for GPIO information in device tree
cat /proc/device-tree/soc/gpio@*/status 2>/dev/null

# Check compatible strings
find /proc/device-tree -name "compatible" -exec cat {} \; | grep -i "sensecap\|rak"
```

## Method 6: Check Kernel Messages (dmesg)

```bash
# Check kernel messages for hardware detection
dmesg | grep -i "gpio\|i2c\|sensecap\|rak\|concentrator"

# Check recent hardware-related messages
dmesg | tail -100 | grep -i "gpio\|i2c"
```

## Method 7: Check Container Environment Variables

```bash
# SSH into device
balena device ssh <device-uuid>

# Check environment variables in udp-packet-forwarder container
balena exec udp-packet-forwarder env | grep -i "gpio\|model\|reset"

# Check which GPIO is configured
balena exec udp-packet-forwarder printenv | grep RESET_GPIO
```

## Method 8: Check Which GPIO Successfully Resets Concentrator

The most reliable method - check which GPIO pin actually works:

```bash
# SSH into device
balena device ssh <device-uuid>

# Enter the udp-packet-forwarder container
balena exec -it udp-packet-forwarder sh

# Check the reset script that was generated
cat /app/config/reset_lgw.sh

# This will show which GPIO is actually being used
# Look for the RESET_GPIO value in the script
```

## Method 9: Test GPIO Pins Directly (Requires Container Access)

```bash
# SSH into device
balena device ssh <device-uuid>

# Enter the udp-packet-forwarder container
balena exec -it udp-packet-forwarder sh

# Check available GPIO chips
gpiodetect

# Check GPIO info for specific chip
gpioinfo gpiochip0

# Test GPIO 25 (RAK)
gpioset gpiochip0 25=0 && sleep 0.1 && gpioset gpiochip0 25=1

# Test GPIO 17 (SenseCAP)
gpioset gpiochip0 17=0 && sleep 0.1 && gpioset gpiochip0 17=1
```

## Quick One-Liner to Check Active GPIO

```bash
# Check which GPIO is configured in the running container
balena device ssh <device-uuid> "balena exec udp-packet-forwarder cat /app/config/reset_lgw.sh | grep -o 'RESET_GPIO=[0-9]*' | head -1"
```

## Recommended Approach

**Best method**: Check the container logs or the generated reset script to see which GPIO successfully initialized the concentrator:

```bash
# 1. Check logs for successful initialization
balena device ssh <device-uuid>
balena logs udp-packet-forwarder | grep -A 5 -B 5 "reset\|initialized\|gpio"

# 2. Check the actual reset script
balena exec udp-packet-forwarder cat /app/config/reset_lgw.sh

# 3. Look for RESET_GPIO value - if it shows GPIO 25, it's RAK; if GPIO 17, it's SenseCAP
```

## GPIO Reference

Based on `docker-compose.yml` configuration:
- **GPIO 25**: RAK2004/Helium units
- **GPIO 17**: RAK2245/SenseCAP M1 units

The configuration tries GPIO 25 first, then falls back to GPIO 17 if 25 doesn't work.

