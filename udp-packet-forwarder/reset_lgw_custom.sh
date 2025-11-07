#!/usr/bin/env bash
set -e

# Custom reset script for RAK2287 with proper power cycling
# This script REPLACES the default RAK reset script to ensure
# adequate power discharge time (2000ms) for concentrator stability

echo "[CUSTOM RESET] Starting RAK2287 power cycle with 2000ms discharge"

# Read environment variables (set by RAK container)
GPIO_CHIP="${GPIO_CHIP:-gpiochip0}"
RESET_GPIO="${RESET_GPIO:-17}"
POWER_EN_GPIO="${POWER_EN_GPIO:-18}"
POWER_EN_LOGIC="${POWER_EN_LOGIC:-1}"

echo "[CUSTOM RESET] GPIO Chip: ${GPIO_CHIP}"
echo "[CUSTOM RESET] Reset GPIO: ${RESET_GPIO}"
echo "[CUSTOM RESET] Power Enable GPIO: ${POWER_EN_GPIO}"
echo "[CUSTOM RESET] Power Enable Logic: ${POWER_EN_LOGIC}"

# Use gpioset from libgpiod
GPIOSET="gpioset -m time -u 100000 ${GPIO_CHIP}"

# Calculate power off/on values based on logic
if [[ ${POWER_EN_LOGIC} -eq 1 ]]; then
    POWER_OFF_VALUE=0
    POWER_ON_VALUE=1
else
    POWER_OFF_VALUE=1
    POWER_ON_VALUE=0
fi

# Step 1: Power OFF the concentrator
if [[ ${POWER_EN_GPIO} -ne 0 ]]; then
    echo "[CUSTOM RESET] Powering OFF concentrator (GPIO ${POWER_EN_GPIO} = ${POWER_OFF_VALUE})"
    gpioset -m exit "/dev/${GPIO_CHIP}" "${POWER_EN_GPIO}=${POWER_OFF_VALUE}" 2>/dev/null || true
    
    # Step 2: Wait 2000ms (2 seconds) for COMPLETE capacitor discharge
    echo "[CUSTOM RESET] Waiting 2000ms for complete power discharge..."
    sleep 2
    
    # Step 3: Power ON the concentrator
    echo "[CUSTOM RESET] Powering ON concentrator (GPIO ${POWER_EN_GPIO} = ${POWER_ON_VALUE})"
    gpioset -m exit "/dev/${GPIO_CHIP}" "${POWER_EN_GPIO}=${POWER_ON_VALUE}" 2>/dev/null || true
    
    # Step 4: Wait 100ms for power stabilization
    echo "[CUSTOM RESET] Waiting 100ms for power stabilization..."
    sleep 0.1
fi

# Step 5: Execute reset sequence on all configured reset GPIOs
for GPIO in ${RESET_GPIO//,/ }; do
    if [[ ${GPIO} -ne 0 ]]; then
        echo "[CUSTOM RESET] Concentrator reset through ${GPIO_CHIP}:${GPIO} (using libgpiod)"
        ${GPIOSET} "${GPIO}"=0 2>/dev/null || true
        ${GPIOSET} "${GPIO}"=1 2>/dev/null || true
        ${GPIOSET} "${GPIO}"=0 2>/dev/null || true
    fi
done

echo "[CUSTOM RESET] Power cycle and reset sequence completed successfully"
exit 0

