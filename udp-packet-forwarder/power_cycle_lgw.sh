#!/bin/bash

# ------------------------------------------------------------
# SX1302 Power Cycle & Reset Script
# Implements proper power sequencing per Semtech sx1302_hal
# ------------------------------------------------------------

set -e

# -------- CONFIGURATION --------
RESET_GPIO="${RESET_GPIO:-17}"
POWER_EN_GPIO="${POWER_EN_GPIO:-18}"
POWER_EN_LOGIC="${POWER_EN_LOGIC:-1}"  # 1=active-high (default), 0=active-low

# -------- BOARD DETECTION --------
MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "Unknown")
echo "[INFO] Detected board: $MODEL"

# -------- GPIO & CHIP CONFIG --------
if echo "$MODEL" | grep -q "Raspberry Pi 5"; then
    GPIO_CHIP="${GPIO_CHIP:-gpiochip4}"  # RP1 GPIO typically gpiochip4
    echo "[INFO] Pi 5 detected: Using $GPIO_CHIP"
else
    GPIO_CHIP="${GPIO_CHIP:-gpiochip0}"  # Default for Pi4 and earlier
    echo "[INFO] Pi 4 or earlier detected: Using $GPIO_CHIP"
fi

echo "[INFO] Reset GPIO: $RESET_GPIO"
echo "[INFO] Power Enable GPIO: $POWER_EN_GPIO"
echo "[INFO] Power Enable Logic: $POWER_EN_LOGIC (1=active-high, 0=active-low)"

# -------- POWER CYCLE SEQUENCE --------
if command -v gpioset &> /dev/null; then
    echo "[INFO] Using GPIOD (gpioset) for power cycling"
    
    # Step 1: Power OFF - complete power cycle to clear any bad state
    if [ "$POWER_EN_LOGIC" = "1" ]; then
        # Active-high: LOW = power off
        echo "[INFO] Powering OFF concentrator (GPIO $POWER_EN_GPIO = LOW)"
        gpioset ${GPIO_CHIP} ${POWER_EN_GPIO}=0
    else
        # Active-low: HIGH = power off
        echo "[INFO] Powering OFF concentrator (GPIO $POWER_EN_GPIO = HIGH, active-low)"
        gpioset ${GPIO_CHIP} ${POWER_EN_GPIO}=1
    fi
    
    # Step 2: Wait for complete capacitor discharge
    echo "[INFO] Waiting 500ms for complete power discharge..."
    sleep 0.5
    
    # Step 3: Power ON
    if [ "$POWER_EN_LOGIC" = "1" ]; then
        # Active-high: HIGH = power on
        echo "[INFO] Powering ON concentrator (GPIO $POWER_EN_GPIO = HIGH)"
        gpioset ${GPIO_CHIP} ${POWER_EN_GPIO}=1
    else
        # Active-low: LOW = power on
        echo "[INFO] Powering ON concentrator (GPIO $POWER_EN_GPIO = LOW, active-low)"
        gpioset ${GPIO_CHIP} ${POWER_EN_GPIO}=0
    fi
    
    # Step 4: Wait for power stabilization
    echo "[INFO] Waiting 100ms for power stabilization..."
    sleep 0.1
    
    # Step 5: Reset sequence (LOW -> HIGH -> LOW)
    echo "[INFO] Starting reset sequence on GPIO $RESET_GPIO"
    gpioset ${GPIO_CHIP} ${RESET_GPIO}=0
    sleep 0.1
    gpioset ${GPIO_CHIP} ${RESET_GPIO}=1
    sleep 0.1
    gpioset ${GPIO_CHIP} ${RESET_GPIO}=0
    sleep 0.1

else
    echo "[INFO] Using Sysfs GPIO for power cycling"
    
    POWER_GPIO_PATH="/sys/class/gpio/gpio${POWER_EN_GPIO}"
    RESET_GPIO_PATH="/sys/class/gpio/gpio${RESET_GPIO}"
    
    # Export GPIOs if not already exported
    if [ ! -d "$POWER_GPIO_PATH" ]; then
        echo $POWER_EN_GPIO > /sys/class/gpio/export
        sleep 0.1
    fi
    if [ ! -d "$RESET_GPIO_PATH" ]; then
        echo $RESET_GPIO > /sys/class/gpio/export
        sleep 0.1
    fi
    
    # Set directions
    echo "out" > ${POWER_GPIO_PATH}/direction
    echo "out" > ${RESET_GPIO_PATH}/direction
    
    # Step 1: Power OFF
    if [ "$POWER_EN_LOGIC" = "1" ]; then
        echo "[INFO] Powering OFF concentrator (sysfs)"
        echo 0 > ${POWER_GPIO_PATH}/value
    else
        echo "[INFO] Powering OFF concentrator (sysfs, active-low)"
        echo 1 > ${POWER_GPIO_PATH}/value
    fi
    
    # Step 2: Wait for discharge
    echo "[INFO] Waiting 500ms for power discharge..."
    sleep 0.5
    
    # Step 3: Power ON
    if [ "$POWER_EN_LOGIC" = "1" ]; then
        echo "[INFO] Powering ON concentrator (sysfs)"
        echo 1 > ${POWER_GPIO_PATH}/value
    else
        echo "[INFO] Powering ON concentrator (sysfs, active-low)"
        echo 0 > ${POWER_GPIO_PATH}/value
    fi
    
    # Step 4: Wait for stabilization
    echo "[INFO] Waiting 100ms for power stabilization..."
    sleep 0.1
    
    # Step 5: Reset sequence
    echo "[INFO] Starting reset sequence (sysfs)"
    echo 0 > ${RESET_GPIO_PATH}/value
    sleep 0.1
    echo 1 > ${RESET_GPIO_PATH}/value
    sleep 0.1
    echo 0 > ${RESET_GPIO_PATH}/value
    sleep 0.1
    
    # Optional: unexport to release GPIOs
    echo $POWER_EN_GPIO > /sys/class/gpio/unexport 2>/dev/null || true
    echo $RESET_GPIO > /sys/class/gpio/unexport 2>/dev/null || true
fi

echo "[INFO] Power cycle and reset sequence completed successfully."
exit 0

