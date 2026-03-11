# I found this reset script that is showing up in the logs in four places in the repo:
# 1. https://github.com/RAKWireless/udp-packet-forwarder/blob/28d17446cc2159750cdbe349238a39b07b2b7e79/runner/gateway_eui#L67

```
# Create reset file
if [[ ${USE_LIBGPIOD:-0} -eq 0 ]]; then
    cp reset.sh.legacy reset_lgw.sh
else
    cp reset.sh.gpiod reset_lgw.sh
fi
```
# 2 https://github.com/RAKWireless/udp-packet-forwarder/blob/28d17446cc2159750cdbe349238a39b07b2b7e79/runner/start#L67
```
    chmod +x "${RESET_FILE}"
    ln -s "${RESET_FILE}" /app/config/reset_lgw.sh 2>/dev/null
/app/config/reset_lgw.sh
```

# 3. https://github.com/RAKWireless/udp-packet-forwarder/blob/28d17446cc2159750cdbe349238a39b07b2b7e79/runner/find_concentrator#L116
```
# Create reset file
if [[ ${USE_LIBGPIOD:-0} -eq 0 ]]; then
    cp reset.sh.legacy reset_lgw.sh
else
    cp reset.sh.gpiod reset_lgw.sh
fi
```
# 4. https://github.com/RAKWireless/udp-packet-forwarder/blob/28d17446cc2159750cdbe349238a39b07b2b7e79/builder/patches/sx1302_hal.V2.1.0.patch#L3328
```
+
+    if (com_type == LGW_COM_SPI) {
+        /* Board reset */
+        if (system("./reset_lgw.sh start") != 0) {
+            printf("ERROR: failed to reset SX1302, check your reset_lgw.sh script\n");
+            exit(EXIT_FAILURE);
+        }
```

# And in terms of the actual reset script (lora/rak2287/reset_lgw.sh), I found it in the common-for-gateway repo:
# https://github.com/RAKWireless/rak_common_for_gateway/blob/ec6464c35565133b6045eecfbce4daa8c7002d6f/lora/rak2287/reset_lgw.sh#L4

#!/bin/bash

# ------------------------------------------------------------
# Universal reset_lgw.sh - Auto-detects Pi2/4/5, GPIOD + Sysfs
# ------------------------------------------------------------

# -------- BOARD DETECTION --------
MODEL=$(tr -d '\0' < /proc/device-tree/model)
echo "[INFO] Detected board: $MODEL"

# -------- GPIO & CHIP CONFIG --------
if echo "$MODEL" | grep -q "Raspberry Pi 5"; then
    RESET_GPIO=17  # Example for Pi5 (adjust to match concentrator reset pin)
    GPIO_CHIP="gpiochip4"  # RP1 GPIO typically gpiochip4
    echo "[INFO] Pi 5 detected: Using GPIO $RESET_GPIO on $GPIO_CHIP"
else
    RESET_GPIO=17  # Default for Pi4 and earlier
    GPIO_CHIP="gpiochip0"
    echo "[INFO] Pi 4 or earlier detected: Using GPIO $RESET_GPIO on $GPIO_CHIP"
fi

# -------- RESET SEQUENCE --------
if command -v gpioset &> /dev/null; then
    echo "[INFO] Using GPIOD (gpioset) for reset"

    # Pull reset low -> high -> low (with delays)
    gpioset ${GPIO_CHIP} ${RESET_GPIO}=0
    sleep 0.1
    gpioset ${GPIO_CHIP} ${RESET_GPIO}=1
    sleep 0.1
    gpioset ${GPIO_CHIP} ${RESET_GPIO}=0
    sleep 0.1

else
    echo "[INFO] Using Sysfs GPIO for reset"

    GPIO_PATH="/sys/class/gpio/gpio${RESET_GPIO}"

    # Export GPIO if not already exported
    if [ ! -d "$GPIO_PATH" ]; then
        echo $RESET_GPIO > /sys/class/gpio/export
        sleep 0.1
    fi

    # Set direction and perform reset
    echo "out" > ${GPIO_PATH}/direction
    echo 0 > ${GPIO_PATH}/value
    sleep 0.1
    echo 1 > ${GPIO_PATH}/value
    sleep 0.1
    echo 0 > ${GPIO_PATH}/value
    sleep 0.1

    # Optional: unexport to release GPIO
    echo $RESET_GPIO > /sys/class/gpio/unexport
fi

echo "[INFO] Reset sequence completed."
exit 0