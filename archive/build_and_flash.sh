#!/bin/bash

# ==============================================================================
# JETSON NANO eMMC (Waveshare) - MASTER HOST SETUP SCRIPT
# Prepares Custom L4T 32.7.6 (JetPack 4.6.6), Patches DTB for TF Card Boot, 
# SPI, and PWM. Removes Bloatware, Clones to TF Card, and Flashes eMMC Bootloader.
# ==============================================================================

set -Eeuo pipefail
# ------------------------------------------------------------------------------
# Global Paths
# ------------------------------------------------------------------------------
# Get the absolute path to the directory containing this master bash script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACTUAL_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
SDKM_INST="$ACTUAL_HOME/nvidia/nvidia_sdk"
SDKM_DL="$ACTUAL_HOME/Downloads/nvidia/sdkm_downloads"
TARGET_DIR="$SDKM_INST/JetPack_4.6.6_Linux_JETSON_NANO_TARGETS"
L4T_DIR="$TARGET_DIR/Linux_for_Tegra"
ROOTFS_DIR="$L4T_DIR/rootfs"

# Trap to ensure chroot mounts are cleaned up if script fails
cleanup() {
    echo -e "\n[---> Cleaning up environment...]"
    if [ -d "$ROOTFS_DIR" ]; then
        umount -f "$ROOTFS_DIR/dev/pts" 2>/dev/null || true
        umount -f "$ROOTFS_DIR/dev" 2>/dev/null || true
        umount -f "$ROOTFS_DIR/sys" 2>/dev/null || true
        umount -f "$ROOTFS_DIR/proc" 2>/dev/null || true
        rm -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Ensure script is run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (sudo)."
  exit 1
fi

clear
echo "================================================================"
echo "    JETSON NANO eMMC AUTO-BUILD & FLASH WORKFLOW (HOST-SIDE)    "
echo "      Target: JetPack 4.6.6 (L4T 32.7.6) | ROS2 Ready Image     "
echo "================================================================"

# Define URLs for L4T 32.7.6 (JetPack 4.6.6)
BSP_URL="https://developer.nvidia.com/embedded/l4t/r32_release_v7.6/t210/jetson-210_linux_r32.7.6_aarch64.tbz2"
ROOTFS_URL="https://developer.nvidia.com/embedded/l4t/r32_release_v7.6/t210/tegra_linux_sample-root-filesystem_r32.7.6_aarch64.tbz2"

# ------------------------------------------------------------------------------
# Unified confirmation helper – supports Yes / No / Skip / Abort
# Sets:  CONFIRM_CHOICE  -> "yes" | "no" | "skip"
# Exit:  script terminates only on "abort" (or Ctrl-C)
# ------------------------------------------------------------------------------
confirm() {
    local prompt="$1"
    local default="${2:-n}"          # y | n | s | a
    local hint

    case "$(echo "$default" | tr '[:upper:]' '[:lower:]')" in
        y|yes)   hint="[Y/n/s/a]" ;;
        s|skip)  hint="[y/n/S/a]" ;;
        a|abort) hint="[y/n/s/A]" ;;
        *)       hint="[y/N/s/a]" ;;
    esac

    local ans
    while true; do
        read -r -p "$prompt $hint " ans
        ans=${ans:-$default}
        case "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" in
            y|yes)
                CONFIRM_CHOICE="yes";  return 0 ;;
            n|no)
                CONFIRM_CHOICE="no";   return 0 ;;
            s|skip)
                CONFIRM_CHOICE="skip"; return 0 ;;
            a|abort)
                echo "Aborted by user." >&2
                exit 1 ;;
            *)
                echo "  Invalid input. Please answer: y (yes), n (no), s (skip), or a (abort)." >&2 ;;
        esac
    done
}
# ------------------------------------------------------------------------------
# STEP 1: Secure Source & Build the Base Image
# ------------------------------------------------------------------------------
echo -e "\n---> Installing Host Dependencies..."
apt-get update
# Added libxml2-utils to ensure xmllint is available for flash.sh XML parsing
apt-get install -y qemu-user-static device-tree-compiler curl lbzip2 rsync libxml2-utils

echo -e "\n================================================================"
echo "STEP 1: L4T File Sourcing & Extraction"
echo "================================================================"

BSP_SRC="$SDKM_DL/Jetson-210_Linux_R32.7.6_aarch64.tbz2"
ROOTFS_SRC="$SDKM_DL/Tegra_Linux_Sample-Root-Filesystem_R32.7.6_aarch64.tbz2"

confirm "Use L4T files already downloaded via SDK Manager?" n
use_sdkm="$CONFIRM_CHOICE"

if [ "$use_sdkm" = "yes" ]; then
    echo -e "\n---> Searching in $SDKM_DL..."
    if [ ! -f "$BSP_SRC" ] || [ ! -f "$ROOTFS_SRC" ]; then
        echo "Error: Could not find both L4T 32.7.6 tbz2 files in $SDKM_DL."
        exit 1
    fi
else
    # If user chose 'no' or 'skip', we proceed to download
    confirm "Download L4T 32.7.6 (~1.2GB) from NVIDIA servers?" y
    if [ "$CONFIRM_CHOICE" = "yes" ]; then
        mkdir -p "$SDKM_DL"
        echo -e "\n---> Downloading L4T Board Support Package & RootFS..."
        curl -fL --retry 3 -o "$BSP_SRC"   "$BSP_URL"
        curl -fL --retry 3 -o "$ROOTFS_SRC" "$ROOTFS_URL"
    else
        echo -e "\n---> Skipping download step. (Ensure files exist or script may fail later)."
    fi
fi

# TARGET_DIR="$SDKM_INST/JetPack_4.6.6_Linux_JETSON_NANO_TARGETS"

# Prompt user whether to extract or skip
confirm "Proceed with extraction to $TARGET_DIR?" y
do_extract="$CONFIRM_CHOICE"

if [ "$do_extract" = "yes" ]; then
    if [ -d "$TARGET_DIR/Linux_for_Tegra" ]; then
        echo -e "\n---> Removing existing extracted files..."
        rm -rf "$TARGET_DIR/Linux_for_Tegra"
    fi
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"

    echo -e "\n---> Extracting BSP..."
    tar -xjf "$BSP_SRC"

    echo -e "\n---> Extracting RootFS..."
    cd Linux_for_Tegra/rootfs/
    tar -xjf "$ROOTFS_SRC"
    cd ..

    echo -e "\n---> Applying NVIDIA Binaries to RootFS..."
    ./apply_binaries.sh
else
    # This catches both "no" and "skip"
    echo -e "\n---> Skipping extraction step. Proceeding to next phase..."
fi

# ------------------------------------------------------------------------------
# STEP 2: Direct Hardware & Boot Configuration
# ------------------------------------------------------------------------------
echo -e "\n================================================================"
echo "STEP 2: Hardware & Boot Configuration (Waveshare Method)"
echo "================================================================"

confirm "Proceed with patching DTB for TF Card Boot, SPI, and PWM?" y

if [ "$CONFIRM_CHOICE" = "yes" ]; then
    echo -e "\n---> Patching DTB directly using fdtput (Lossless method)..."

    # Define explicit absolute paths
    DTB_DIR="$L4T_DIR/kernel/dtb"
    DTB_FILE="tegra210-p3448-0002-p3449-0000-b00.dtb"
    DTB_PATH="$DTB_DIR/$DTB_FILE"

    if [ ! -f "$DTB_PATH" ]; then
        echo "Error: DTB file $DTB_FILE not found at:"
        echo "  $DTB_PATH"
        exit 1
    fi

    # Ensure the script operates from inside the Linux_for_Tegra directory
    cd "$L4T_DIR"

    echo -e "\n---> Patching DTB directly using fdtput (Lossless method)..."

    # 1. TF Card / SD Card Boot Enablement (sdhci@700b0400)
    echo "  -> Configuring sdhci@700b0400 for TF Card Boot..."
    fdtput -t s "$DTB_PATH" /sdhci@700b0400 status "okay"
    fdtput -t x "$DTB_PATH" /sdhci@700b0400 cd-gpios 0x5b 0xc2 0x0
    fdtput -t x "$DTB_PATH" /sdhci@700b0400 uhs-mask 0xc

    for flag in sd-uhs-sdr104 sd-uhs-sdr50 sd-uhs-sdr25 sd-uhs-sdr12 no-mmc; do
        fdtput "$DTB_PATH" /sdhci@700b0400 "$flag"
    done
    # 2. SPI1 Enablement
    echo "  -> Configuring SPI1..."
    fdtput -t s "$DTB_PATH" /spi@7000d400/spi@0 status "okay"
    fdtput -t s "$DTB_PATH" /spi@7000d400/spi@1 status "okay"

    # Pinmux for SPI1
    for pin in spi1_mosi_pc0 spi1_miso_pc1 spi1_sck_pc2 spi1_cs0_pc3 spi1_cs1_pc4; do
        fdtput -t s "$DTB_PATH" /pinmux@700008d4/unused_lowpower/$pin nvidia,function "spi1"
        fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/$pin nvidia,tristate 0x0
        fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/$pin nvidia,enable-input 0x1
    done

    # 3. PWM Enablement (PWM0 and PWM2)
    echo "  -> Configuring PWM0 and PWM2..."
    fdtput -t s "$DTB_PATH" /pinmux@700008d4/unused_lowpower/lcd_bl_pwm_pv0 nvidia,function "pwm0"
    fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/lcd_bl_pwm_pv0 nvidia,tristate 0x0
    fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/lcd_bl_pwm_pv0 nvidia,enable-input 0x1

    fdtput -t s "$DTB_PATH" /pinmux@700008d4/unused_lowpower/pe6 nvidia,function "pwm2"
    fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/pe6 nvidia,tristate 0x0
    fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/pe6 nvidia,enable-input 0x1

else
    echo -e "\n---> Skipping DTB patching step. Proceeding to next phase..."
fi

# # ------------------------------------------------------------------------------
# # STEP 4: TF Card Preparation & Cloning
# # ------------------------------------------------------------------------------
# echo -e "\n================================================================"
# echo "STEP 4: TF Card Preparation & Cloning"
# echo "================================================================"

# echo -e "\n*** ACTION REQUIRED ***"
# echo "Please ensure your TF card (min 32GB) is inserted into the host PC."
# confirm "Proceed with TF Card preparation and cloning?" n

# if [ "$CONFIRM_CHOICE" != "yes" ]; then
#     echo -e "\n---> Skipping TF Card preparation and cloning step."
#     echo "    You can clone the rootfs to a TF card manually later with:"
#     echo "      mkfs.ext4 -F /dev/<tfcard>1 && mount /dev/<tfcard>1 /mnt"
#     echo "      rsync -axHAWX --numeric-ids $ROOTFS_DIR/ /mnt/"
#     echo "      sync && umount /mnt"
# else
#     echo -e "\n================================================================"
#     lsblk -e 7
#     echo "================================================================"
#     read -p "Look at the list above. Enter the identifier of your TF Card (e.g., sdb, sdc): " TFCARD

#     if [ -z "$TFCARD" ] || [ ! -b "/dev/$TFCARD" ]; then
#         echo "Invalid drive selected. Skipping TF Card cloning to protect host system."
#     else
#         SIZE=$(blockdev --getsize64 /dev/$TFCARD)
#         if [ "$SIZE" -lt 30000000000 ]; then
#             echo "Error: Selected drive is smaller than 32GB. Skipping TF Card cloning."
#         else
#             confirm "WARNING: /dev/$TFCARD will be WIPED and reformatted as ext4. Proceed?" a

#             if [ "$CONFIRM_CHOICE" = "yes" ]; then
#                 echo -e "\n---> Formatting /dev/$TFCARD as ext4..."
#                 umount /dev/${TFCARD}* 2>/dev/null || true
#                 parted -s /dev/$TFCARD mklabel gpt
#                 parted -s /dev/$TFCARD mkpart primary ext4 0% 100%
#                 mkfs.ext4 -F /dev/${TFCARD}1

#                 echo -e "\n---> Cloning RootFS to TF Card (This will take a few minutes)..."
#                 mount /dev/${TFCARD}1 /mnt
#                 rsync -axHAWX --numeric-ids --info=progress2 rootfs/ /mnt/
#                 sync
#                 umount /mnt
#                 echo "TF Card clone complete. You may leave the card in the host or insert it into the Jetson."
#             else
#                 # Reached only via explicit 'n' or 's' (abort exits inside confirm()).
#                 echo -e "\n---> Skipped or declined formatting. Skipping cloning as well."
#             fi
#         fi
#     fi
# fi

# ------------------------------------------------------------------------------
# STEP 5: Flash eMMC Bootloader
# ------------------------------------------------------------------------------

# Ensure the script operates from inside the Linux_for_Tegra directory
cd "$L4T_DIR"

echo -e "\n================================================================"
echo "STEP 5: Flash eMMC Bootloader"
echo "================================================================"

echo -e "\n*** ACTION REQUIRED ***"
echo "1. Ensure the TF card is inserted into the Jetson Nano."
echo "2. Put the Jetson Nano into Force Recovery Mode (Jumper J40, connect USB)."
read -n 1 -s -r -p "Press any key when the Jetson is connected in Recovery Mode..."

echo -e "\n\n---> Verifying Recovery Mode connection..."
if ! lsusb | grep -q '0955:7f21'; then
    echo "Error: NVIDIA Corp APX device (0955:7f21) not found in lsusb."
    echo "Ensure the device is powered on and in Recovery Mode."
    exit 1
fi

confirm "Flash the bootloader to the Jetson eMMC now?" a

if [ "$CONFIRM_CHOICE" = "yes" ]; then
    echo -e "\n---> Flashing Bootloader to eMMC..."
    ./flash.sh jetson-nano-emmc mmcblk1p1
    echo -e "\n================================================================"
    echo "SUCCESS! Flash complete."
    echo "The Jetson will now boot the OS from the TF Card."
    echo "SPI and PWM are enabled in the DTB. ROS2 environment is ready."
    echo "================================================================"
else
    echo -e "\n---> Skipped flashing the bootloader."
    echo "You can flash manually later by running:"
    echo "cd $L4T_DIR && ./flash.sh jetson-nano-emmc mmcblk1p1"
    exit 0
fi
