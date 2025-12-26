#!/bin/bash
ROOTFS_NAME="rootfs-alpine.tar.gz"
DEVICE_NAME="pico-mini-b"
while getopts ":f:d:" opt; do
  case ${opt} in
    f) ROOTFS_NAME="${OPTARG}" ;;
    d) DEVICE_NAME="${OPTARG}" ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 1
      ;;
  esac
done
DEVICE_ID="6"
case $DEVICE_NAME in
  pico-mini-b) DEVICE_ID="6" ;;
  pico-plus) DEVICE_ID="7" ;;
  pico-pro-max) DEVICE_ID="8" ;;
  *)
    echo "Invalid device: ${DEVICE_NAME}."
    exit 1
    ;;
esac
rm -rf sdk/sysdrv/custom_rootfs/
mkdir -p sdk/sysdrv/custom_rootfs/
cp "$ROOTFS_NAME" sdk/sysdrv/custom_rootfs/
pushd sdk || exit
pushd tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/ || exit
source env_install_toolchain.sh
popd || exit
rm -rf .BoardConfig.mk
echo "$DEVICE_ID" | ./build.sh lunch
echo "export RK_CUSTOM_ROOTFS=../sysdrv/custom_rootfs/$ROOTFS_NAME" >> .BoardConfig.mk
echo "export RK_BOOTARGS_CMA_SIZE=\"1M\"" >> .BoardConfig.mk

# ===== ENABLE BLUETOOTH IN KERNEL =====
echo "Configuring kernel for Bluetooth support..."

KERNEL_CONFIG="sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig"

# Add Bluetooth config options
cat >> "$KERNEL_CONFIG" << EOF

# Bluetooth support for ESP-Hosted
CONFIG_CRYPTO_AES=y
CONFIG_CRYPTO_ECDH=y
CONFIG_ECC=y

CONFIG_BT=y
CONFIG_BT_BREDR=y
CONFIG_BT_RFCOMM=m
CONFIG_BT_RFCOMM_TTY=y
CONFIG_BT_BNEP=m
CONFIG_BT_BNEP_MC_FILTER=y
CONFIG_BT_BNEP_PROTO_FILTER=y
CONFIG_BT_HIDP=m
CONFIG_BT_HCIBTUSB=m
CONFIG_BT_HCIUART=m

CONFIG_WIRELESS=y
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_CFG80211_WEXT=y
EOF

echo "Bluetooth configuration added"
# ===== END BLUETOOTH CONFIG =====

# ===== CONFIGURE DEVICE TREE (SPI0) =====
DTS_PATH="sysdrv/source/kernel/arch/arm/boot/dts/rv1103g-luckfox-pico-mini-b.dts"

echo "Patching SPI0 in Device Tree..."

# Define the replacement content exactly as requested
export NEW_SPI_CONTENT=$(cat << 'EOF'
status = "okay";
  pinctrl-0 = <&spi0m0_pins &spi0m0_cs0>;
  spidev@0 {
    status = "disabled";
  };
EOF
)

# Using single quotes for the perl command ensures Bash doesn't touch the regex
# $ENV{...} is the internal Perl way to grab the exported bash variable
perl -i -0777 -pe 's/(&spi0 \{).*?(\n\};)/$1\n$ENV{NEW_SPI_CONTENT}$2/s' "$DTS_PATH"

echo "Device Tree patched."


# build sysdrv - rootfs
./build.sh uboot
./build.sh kernel
./build.sh driver
./build.sh env
#./build.sh app

# ===== BUILD ESP-HOSTED DRIVER =====
echo "Building ESP-Hosted driver..."

# Clone esp-hosted if not present
if [ ! -d "esp-hosted" ]; then
  git clone --depth 1 https://github.com/5t0x2fH1z/esp-hosted.git ../esp-hosted
fi

# Store current directory (we're in sdk/)
SDK_ROOT="$(pwd)"

# Kernel source path (relative to sdk/)
# Find kernel source path
if [ -d "$SDK_ROOT/sysdrv/source/kernel" ]; then
  KERNEL_SRC="$SDK_ROOT/sysdrv/source/kernel"
elif [ -d "$SDK_ROOT/kernel" ]; then
  KERNEL_SRC="$SDK_ROOT/kernel"
else
  echo "ERROR: Cannot find kernel source directory"
  ls -la "$SDK_ROOT/sysdrv/source/"
  exit 1
fi

echo "Using kernel at: $KERNEL_SRC"

# Toolchain path (absolute)
TOOLCHAIN_PATH="$SDK_ROOT/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf-"

# Get toolchain info from environment (already sourced above)
export ARCH=arm
export CROSS_COMPILE=arm-rockchip830-linux-uclibcgnueabihf-

# Build esp-hosted module
pushd ../esp-hosted/esp_hosted_ng/host || exit
make -j8 target=spi \
  CROSS_COMPILE="$TOOLCHAIN_PATH" \
  KERNEL="$KERNEL_SRC" \
  ARCH=arm

popd || exit

# Return explicitly to SDK root
cd "$SDK_ROOT" || exit

echo "ESP-Hosted driver build complete"
# ===== END ESP-HOSTED BUILD =====

# package firmware
./build.sh firmware
./build.sh save
popd || exit
rm -rf output
mkdir -p output
cp sdk/output/image/* "output/"

# Debug: check if module is in the firmware
echo "=== Checking for esp32_spi.ko in firmware ==="
find output/ -name "esp32_spi.ko"

# Copy ESP-Hosted module to output and lib/modules
if [ -f "esp-hosted/esp_hosted_ng/host/esp32_spi.ko" ]; then
  cp esp-hosted/esp_hosted_ng/host/esp32_spi.ko output/
  echo "ESP-Hosted module copied to output/"
  if [ -f "./overlay/lib/modules/esp32_spi.ko" ]; then
    echo "esp32_spi.ko already exists"
  else
    mkdir "./overlay/lib/modules"
    cp esp-hosted/esp_hosted_ng/host/esp32_spi.ko ./overlay/lib/modules
    echo "esp32_spi.ko module copied to /lib/modues/"
  fi
fi
