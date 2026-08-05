#!/bin/bash

# ==============================================================================
# PHASE 1: Jetson Nano eMMC — Build & Flash (Host-Side)
# Waveshare JETSON-NANO-DEV-KIT One-Click Setup
#
# Target : JetPack 4.6.6 (L4T 32.7.6) on Jetson Nano eMMC (Waveshare)
# Runs on: Host PC (Ubuntu x86_64, requires sudo)
#
# Steps:
#   1. Download & extract JetPack L4T 32.7.6 (BSP + RootFS)
#   2. Patch DTB for TF Card Boot, SPI1, PWM0/PWM2
#   3. Copy Phase 2 & Phase 3 scripts into rootfs, create default user
#   4. Flash eMMC bootloader via Recovery Mode
#
# Prerequisites:
#   - Host PC running Ubuntu 18.04/20.04 (x86_64)
#   - Internet access for NVIDIA L4T downloads (~1.2 GB)
#   - Jetson Nano connected in Force Recovery Mode (for Step 4)
#   - phase2_setup_tf_boot.sh and phase3_ai_environment.sh in same directory
#
# Usage:
#   sudo ./phase1_build_and_flash.sh
# ==============================================================================

set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Global Paths
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACTUAL_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
SDKM_INST="$ACTUAL_HOME/nvidia/nvidia_sdk"
SDKM_DL="$ACTUAL_HOME/Downloads/nvidia/sdkm_downloads"
TARGET_DIR="$SDKM_INST/JetPack_4.6.6_Linux_JETSON_NANO_TARGETS"
L4T_DIR="$TARGET_DIR/Linux_for_Tegra"
ROOTFS_DIR="$L4T_DIR/rootfs"

# Default user credentials for Jetson
DEFAULT_USERNAME="nvidia"
DEFAULT_PASSWORD="nvidia"

# L4T 32.7.6 download URLs
BSP_URL="https://developer.nvidia.com/embedded/l4t/r32_release_v7.6/t210/jetson-210_linux_r32.7.6_aarch64.tbz2"
ROOTFS_URL="https://developer.nvidia.com/embedded/l4t/r32_release_v7.6/t210/tegra_linux_sample-root-filesystem_r32.7.6_aarch64.tbz2"

# No chroot cleanup trap needed — default user creation is delegated to
# the NVIDIA-provided l4t_create_default_user.sh script.

# ------------------------------------------------------------------------------
# Root check
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

# ------------------------------------------------------------------------------
# Simplified confirmation helper — Yes / No (no/skip)
# Sets CONFIRM_CHOICE -> "yes" | "no"
# ------------------------------------------------------------------------------
confirm() {
    local prompt="$1"
    local default="${2:-n}"          # y | n
    local hint

    case "$(echo "$default" | tr '[:upper:]' '[:lower:]')" in
        y|yes)  hint="[Y/n]" ;;
        *)      hint="[y/N]" ;;
    esac

    local ans
    while true; do
        read -r -p "$prompt $hint " ans
        ans=${ans:-$default}
        case "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" in
            y|yes)
                CONFIRM_CHOICE="yes"; return 0 ;;
            n|no|skip)
                CONFIRM_CHOICE="no";  return 0 ;;
            *)
                echo "  Please answer y (yes) or n (no/skip)." >&2 ;;
        esac
    done
}

# Default user creation is handled by the NVIDIA-provided
# l4t_create_default_user.sh script (called in Step 3).

# ==============================================================================
# Banner
# ==============================================================================
clear
echo "================================================================"
echo "  PHASE 1: Jetson Nano eMMC Build & Flash (Host-Side)"
echo "  Target: JetPack 4.6.6 (L4T 32.7.6) | Waveshare Dev Kit"
echo "================================================================"
echo ""
echo "This script will:"
echo "  Step 1 — Download & extract JetPack L4T 32.7.6"
echo "  Step 2 — Patch DTB for TF Card Boot, SPI, PWM"
echo "  Step 3 — Copy Phase 2/3 scripts into rootfs & create default user"
echo "  Step 4 — Flash eMMC bootloader"
echo ""

# ==============================================================================
# STEP 1: Download & Extract L4T 32.7.6
# ==============================================================================
echo -e "\n================================================================"
echo "STEP 1: Download & Extract JetPack L4T 32.7.6"
echo "================================================================"

# Install host dependencies
echo -e "\n---> Installing host dependencies..."
apt-get update
apt-get install -y qemu-user-static device-tree-compiler curl libxml2-utils

BSP_SRC="$SDKM_DL/Jetson-210_Linux_R32.7.6_aarch64.tbz2"
ROOTFS_SRC="$SDKM_DL/Tegra_Linux_Sample-Root-Filesystem_R32.7.6_aarch64.tbz2"

# --- Source L4T files ---
confirm "Use L4T files already downloaded via SDK Manager?" n
use_sdkm="$CONFIRM_CHOICE"

if [ "$use_sdkm" = "yes" ]; then
    echo -e "\n---> Searching in $SDKM_DL..."
    if [ ! -f "$BSP_SRC" ] || [ ! -f "$ROOTFS_SRC" ]; then
        echo "ERROR: Could not find both L4T 32.7.6 tbz2 files in $SDKM_DL."
        echo "  Expected: $BSP_SRC"
        echo "  Expected: $ROOTFS_SRC"
        exit 1
    fi
    echo "---> Found existing L4T files."
else
    confirm "Download L4T 32.7.6 (~1.2 GB) from NVIDIA servers?" y
    if [ "$CONFIRM_CHOICE" = "yes" ]; then
        mkdir -p "$SDKM_DL"
        echo -e "\n---> Downloading L4T Board Support Package..."
        curl -fL --retry 3 -o "$BSP_SRC" "$BSP_URL"
        echo -e "\n---> Downloading L4T Sample Root Filesystem..."
        curl -fL --retry 3 -o "$ROOTFS_SRC" "$ROOTFS_URL"
    else
        echo -e "\n---> Skipping download. Ensure L4T files exist or the script will fail later."
    fi
fi

# --- Extract ---
confirm "Proceed with extraction to $TARGET_DIR?" y
if [ "$CONFIRM_CHOICE" = "yes" ]; then
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

    echo -e "\n---> Applying NVIDIA binaries to RootFS..."
    ./apply_binaries.sh
else
    echo -e "\n---> Skipping extraction. Ensure $L4T_DIR exists and is valid."
fi

# ==============================================================================
# STEP 2: Patch DTB for TF Card Boot, SPI, PWM
# ==============================================================================
echo -e "\n================================================================"
echo "STEP 2: Patch DTB (TF Card Boot, SPI1, PWM0/PWM2)"
echo "================================================================"

confirm "Proceed with DTB patching?" y

if [ "$CONFIRM_CHOICE" = "yes" ]; then
    DTB_DIR="$L4T_DIR/kernel/dtb"
    DTB_FILE="tegra210-p3448-0002-p3449-0000-b00.dtb"
    DTB_PATH="$DTB_DIR/$DTB_FILE"

    if [ ! -f "$DTB_PATH" ]; then
        echo "ERROR: DTB file not found at $DTB_PATH"
        exit 1
    fi

    cd "$L4T_DIR"

    # --- TF Card / SD Card Boot (sdhci@700b0400) ---
    echo "  -> Enabling TF Card Boot (sdhci@700b0400)..."
    fdtput -t s "$DTB_PATH" /sdhci@700b0400 status "okay"
    fdtput -t x "$DTB_PATH" /sdhci@700b0400 cd-gpios 0x5b 0xc2 0x0
    fdtput -t x "$DTB_PATH" /sdhci@700b0400 uhs-mask 0xc
    for flag in sd-uhs-sdr104 sd-uhs-sdr50 sd-uhs-sdr25 sd-uhs-sdr12 no-mmc; do
        fdtput "$DTB_PATH" /sdhci@700b0400 "$flag"
    done

    # --- SPI1 ---
    echo "  -> Enabling SPI1..."
    fdtput -t s "$DTB_PATH" /spi@7000d400/spi@0 status "okay"
    fdtput -t s "$DTB_PATH" /spi@7000d400/spi@1 status "okay"
    for pin in spi1_mosi_pc0 spi1_miso_pc1 spi1_sck_pc2 spi1_cs0_pc3 spi1_cs1_pc4; do
        fdtput -t s "$DTB_PATH" /pinmux@700008d4/unused_lowpower/$pin nvidia,function "spi1"
        fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/$pin nvidia,tristate 0x0
        fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/$pin nvidia,enable-input 0x1
    done

    # --- PWM0 & PWM2 ---
    echo "  -> Enabling PWM0 (lcd_bl_pwm_pv0) and PWM2 (pe6)..."
    fdtput -t s "$DTB_PATH" /pinmux@700008d4/unused_lowpower/lcd_bl_pwm_pv0 nvidia,function "pwm0"
    fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/lcd_bl_pwm_pv0 nvidia,tristate 0x0
    fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/lcd_bl_pwm_pv0 nvidia,enable-input 0x1

    fdtput -t s "$DTB_PATH" /pinmux@700008d4/unused_lowpower/pe6 nvidia,function "pwm2"
    fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/pe6 nvidia,tristate 0x0
    fdtput -t x "$DTB_PATH" /pinmux@700008d4/unused_lowpower/pe6 nvidia,enable-input 0x1

    echo -e "\n---> DTB patching complete."
else
    echo -e "\n---> Skipping DTB patching."
fi

# ==============================================================================
# STEP 3: Copy Phase 2/3 Scripts into rootfs & Create Default User
# ==============================================================================
echo -e "\n================================================================"
echo "STEP 3: Copy Phase 2/3 Scripts & Create Default User"
echo "================================================================"

# --- 3a: Copy scripts into rootfs ---
PHASE2_SRC="$SCRIPT_DIR/phase2_setup_tf_boot.sh"
PHASE3_SRC="$SCRIPT_DIR/phase3_ai_environment.sh"
DEST_HOME="$ROOTFS_DIR/home/$DEFAULT_USERNAME"

echo -e "\n---> Ensuring destination directory exists: $DEST_HOME"
mkdir -p "$DEST_HOME"

if [ -f "$PHASE2_SRC" ]; then
    cp "$PHASE2_SRC" "$DEST_HOME/phase2_setup_tf_boot.sh"
    chmod +x "$DEST_HOME/phase2_setup_tf_boot.sh"
    echo "---> Copied phase2_setup_tf_boot.sh -> rootfs"
else
    echo "WARNING: $PHASE2_SRC not found. Phase 2 script will not be available on the Jetson." >&2
fi

if [ -f "$PHASE3_SRC" ]; then
    cp "$PHASE3_SRC" "$DEST_HOME/phase3_ai_environment.sh"
    chmod +x "$DEST_HOME/phase3_ai_environment.sh"
    echo "---> Copied phase3_ai_environment.sh -> rootfs"
else
    echo "WARNING: $PHASE3_SRC not found. Phase 3 script will not be available on the Jetson." >&2
fi

# --- 3b: Create default user via l4t_create_default_user.sh ---
# NOTE: l4t_create_default_user.sh determines its rootfs path relative
#       to its own location (dirname $0). It MUST be executed from inside
#       the Linux_for_Tegra directory for the path to resolve correctly.
confirm "Create default user '$DEFAULT_USERNAME' with password '$DEFAULT_PASSWORD'?" y
if [ "$CONFIRM_CHOICE" = "yes" ]; then
    if [ ! -d "$L4T_DIR" ]; then
        echo "WARNING: $L4T_DIR does not exist. Cannot create default user." >&2
        echo "         Ensure Step 1 (extraction) completed successfully." >&2
    elif [ ! -d "$ROOTFS_DIR" ]; then
        echo "WARNING: $ROOTFS_DIR does not exist. Cannot create default user." >&2
        echo "         Ensure RootFS was extracted in Step 1." >&2
    else
        # Copy l4t_create_default_user.sh from $SCRIPT_DIR to $L4T_DIR if available
        L4T_USER_SCRIPT_SRC="$SCRIPT_DIR/l4t_create_default_user.sh"
        if [ -f "$L4T_USER_SCRIPT_SRC" ]; then
            echo "---> Copying l4t_create_default_user.sh to $L4T_DIR..."
            cp "$L4T_USER_SCRIPT_SRC" "$L4T_DIR/l4t_create_default_user.sh"
            chmod +x "$L4T_DIR/l4t_create_default_user.sh"
        fi

        if [ ! -f "$L4T_DIR/l4t_create_default_user.sh" ]; then
            echo "WARNING: l4t_create_default_user.sh not found in $L4T_DIR." >&2
            echo "         You will be prompted to create a user on first boot." >&2
        else
            echo -e "\n---> Running l4t_create_default_user.sh -u $DEFAULT_USERNAME -p $DEFAULT_PASSWORD..."
            echo "    (must run from inside $L4T_DIR for rootfs path resolution)"
            cd "$L4T_DIR"
            bash ./l4t_create_default_user.sh -u "$DEFAULT_USERNAME" -p "$DEFAULT_PASSWORD"
            echo "---> Default user '$DEFAULT_USERNAME' created successfully."
        fi
    fi
else
    echo -e "\n---> Skipping default user creation. You will be prompted on first boot."
fi

# ==============================================================================
# STEP 4: Flash eMMC Bootloader
# ==============================================================================
echo -e "\n================================================================"
echo "STEP 4: Flash eMMC Bootloader"
echo "================================================================"

cd "$L4T_DIR"

echo ""
echo "*** ACTION REQUIRED ***"
echo "1. Ensure the TF card is inserted into the Jetson Nano."
echo "2. Put the Jetson Nano into Force Recovery Mode:"
echo "   - Place jumper on J40 header pins (FC REC)"
echo "   - Connect micro-USB cable from Jetson to this host PC"
echo "   - Power on the Jetson Nano"
echo ""
read -n 1 -s -r -p "Press any key when the Jetson is connected in Recovery Mode..."

echo -e "\n\n---> Verifying Recovery Mode connection..."
if ! lsusb | grep -q '0955:7f21'; then
    echo "ERROR: NVIDIA APX device (0955:7f21) not found via lsusb."
    echo "Ensure the Jetson is powered on and in Force Recovery Mode."
    exit 1
fi
echo "---> Recovery Mode detected (NVIDIA APX device found)."

confirm "Flash the bootloader to the Jetson eMMC now?" y

if [ "$CONFIRM_CHOICE" = "yes" ]; then
    echo -e "\n---> Flashing Bootloader to eMMC (this may take several minutes)..."
    ./flash.sh jetson-nano-emmc mmcblk0p1

    echo -e "\n================================================================"
    echo "  PHASE 1 COMPLETE!"
    echo ""
    echo "  The Jetson will boot from eMMC with the patched DTB."
    echo "  Next steps:"
    echo "    1. Remove the Recovery Mode jumper (J40)"
    echo "    2. Boot the Jetson Nano (it will boot from eMMC)"
    echo "    3. Login as $DEFAULT_USERNAME / $DEFAULT_PASSWORD"
    echo "    4. Run:  sudo ~/phase2_setup_tf_boot.sh"
    echo "================================================================"
else
    echo -e "\n---> Skipping eMMC flash."
    echo "You can flash manually later:"
    echo "  cd $L4T_DIR && sudo ./flash.sh jetson-nano-emmc mmcblk0p1"
fi
