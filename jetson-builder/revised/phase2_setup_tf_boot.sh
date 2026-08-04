#!/bin/bash

# ==============================================================================
# PHASE 2: Jetson Nano — TF Card Boot Setup (Jetson-Side)
# Waveshare JETSON-NANO-DEV-KIT One-Click Setup
#
# Runs on: Jetson Nano (after booting from eMMC in Phase 1)
# Objective: Patch extlinux.conf to boot from TF card, then clone rootfs
#            to the inserted TF card so the system can boot from it.
#
# Prerequisites:
#   - Phase 1 completed (Jetson boots from eMMC with patched DTB)
#   - TF card (min 32 GB) inserted into the Jetson Nano TF card slot
#   - TF card must NOT be mounted (unmount manually if auto-mounted)
#
# Safeguards:
#   - Refuses to touch /dev/mmcblk0 (eMMC / system root)
#   - Verifies root is currently on eMMC before proceeding
#   - Minimum 32 GB TF card size check
#   - Double confirmation before formatting
#
# Usage:
#   sudo ~/phase2_setup_tf_boot.sh
# ==============================================================================

set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Simplified confirmation helper — Yes / No (no/skip)
# Sets CONFIRM_CHOICE -> "yes" | "no"
# ------------------------------------------------------------------------------
confirm() {
    local prompt="$1"
    local default="${2:-n}"
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

# ------------------------------------------------------------------------------
# Root check
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

# ==============================================================================
# Banner
# ==============================================================================
clear
echo "================================================================"
echo "  PHASE 2: TF Card Boot Setup (Jetson-Side)"
echo "  Waveshare Jetson Nano Dev Kit"
echo "================================================================"
echo ""
echo "This script will:"
echo "  Step 0 — Optionally restore eMMC boot (if currently on TF card)"
echo "  Step 1 — Detect & mount the TF card at /dev/mmcblk1"
echo "  Step 2 — Format the TF card as ext4"
echo "  Step 3 — Patch extlinux.conf to boot from TF card"
echo "  Step 4 — Clone rootfs to the TF card"
echo "  Step 5 — Reboot into TF card boot"
echo ""

# ==============================================================================
# SAFEGUARD: Verify we are currently booted from eMMC
# ==============================================================================
ROOT_DEVICE=$(findmnt -n -o SOURCE / 2>/dev/null || true)

echo -e "\n---> Current root device: $ROOT_DEVICE"

if echo "$ROOT_DEVICE" | grep -q "mmcblk0"; then
    echo "---> Confirmed: System is booted from eMMC (/dev/mmcblk0)."
elif echo "$ROOT_DEVICE" | grep -q "mmcblk1"; then
    echo "WARNING: System appears to be booted from TF card (/dev/mmcblk1)." >&2
    echo "         Phase 2 is normally run while booted from eMMC." >&2
    echo "         If you are already booted from TF card, you may skip this phase." >&2
    confirm "Proceed anyway?" n
    if [ "$CONFIRM_CHOICE" = "no" ]; then
        echo "---> Skipping Phase 2."
    fi
else
    echo "WARNING: Could not confirm root is on eMMC. Root device: $ROOT_DEVICE" >&2
    confirm "Proceed anyway?" n
    if [ "$CONFIRM_CHOICE" = "no" ]; then
        echo "---> Skipping Phase 2."
    fi
fi

# ==============================================================================
# Step 0: Optionally restore eMMC boot configuration
# ==============================================================================
echo -e "\n================================================================"
echo "Step 0: Restore eMMC Boot (optional)"
echo "================================================================"
echo ""
echo "This step is ONLY applicable if you are currently running this"
echo "script while the Jetson is booted from the TF card and you wish"
echo "to revert back to eMMC boot. If you are booted from eMMC (the"
echo "normal Phase 2 entry point), you should skip this step."
echo ""

confirm "Restore extlinux.conf from backup (revert to eMMC boot)?" n
if [ "$CONFIRM_CHOICE" = "yes" ]; then
    if [ -f "/boot/extlinux/extlinux.conf.bak" ]; then
        cp /boot/extlinux/extlinux.conf.bak /boot/extlinux/extlinux.conf
        echo "---> extlinux.conf restored from backup."
        echo "    The system will boot from eMMC on next reboot."
        confirm "Reboot now?" y
        if [ "$CONFIRM_CHOICE" = "yes" ]; then
            reboot
        fi
    else
        echo "WARNING: /boot/extlinux/extlinux.conf.bak not found. Cannot restore." >&2
        echo "         Continuing without restoration."
    fi
else
    echo "---> Skipping eMMC boot restore."
fi

# ==============================================================================
# Step 1: Detect & Mount TF Card
# ==============================================================================
echo -e "\n================================================================"
echo "Step 1: Detect & Mount TF Card"
echo "================================================================"
echo ""
echo "On the Jetson Nano, the TF card slot appears as /dev/mmcblk1"
echo "with its first partition as /dev/mmcblk1p1."
echo ""

confirm "Proceed with TF card detection?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping TF card detection. Ensure TF card is ready manually."
else
    TF_CARD="/dev/mmcblk1"

    # Loop to allow retry if TF card not found
    while true; do
        if [ -b "$TF_CARD" ]; then
            break
        fi

        echo "WARNING: TF card not found at $TF_CARD" >&2
        echo "         Please insert a TF card (min 32 GB) into the Jetson Nano."
        echo ""
        echo "Available block devices:"
        lsblk -e 7
        echo ""
        confirm "Retry TF card detection?" y
        if [ "$CONFIRM_CHOICE" = "no" ]; then
            echo "---> Skipping TF card detection."
            TF_CARD=""
            break
        fi
    done

    if [ -n "$TF_CARD" ] && [ -b "$TF_CARD" ]; then
        # Size check (minimum 32 GB = ~32,000,000,000 bytes)
        TF_SIZE=$(blockdev --getsize64 "$TF_CARD" 2>/dev/null || echo 0)
        TF_SIZE_GB=$(( TF_SIZE / 1000000000 ))

        echo "---> TF card detected: $TF_CARD (${TF_SIZE_GB} GB)"

        if [ "$TF_SIZE" -lt 30000000000 ]; then
            echo "WARNING: TF card is only ${TF_SIZE_GB} GB. Minimum recommended: 32 GB." >&2
            confirm "Continue anyway?" n
            if [ "$CONFIRM_CHOICE" = "no" ]; then
                TF_CARD=""
            fi
        fi

        # If mmcblk1 is already mounted, unmount it so we can remount later
        if [ -n "$TF_CARD" ] && mount | grep -q "mmcblk1"; then
            echo "---> /dev/mmcblk1 is currently mounted. Unmounting..."
            umount /dev/mmcblk1* 2>/dev/null || true
            echo "---> Unmounted."
        fi
    fi
fi

# ==============================================================================
# Step 2: Format TF Card
# ==============================================================================
echo -e "\n================================================================"
echo "Step 2: Format TF Card as ext4"
echo "================================================================"

if [ -z "$TF_CARD" ] || [ ! -b "$TF_CARD" ]; then
    echo "WARNING: No TF card detected. Skipping format step." >&2
    echo "         You can format manually and return to this script." >&2
else
    echo ""
    echo "*** WARNING ***"
    echo "This will ERASE ALL DATA on $TF_CARD."
    echo ""

    confirm "Format $TF_CARD as ext4?" n
    if [ "$CONFIRM_CHOICE" = "yes" ]; then
        # Double confirmation for destructive operation
        confirm "Are you absolutely sure? This cannot be undone." n
        if [ "$CONFIRM_CHOICE" = "no" ]; then
            echo "---> Formatting cancelled. Assuming ${TF_CARD}1 already has a valid ext4 filesystem."
        else
            echo -e "\n---> Partitioning $TF_CARD (GPT)..."
            parted -s "$TF_CARD" mklabel gpt
            parted -s "$TF_CARD" mkpart primary ext4 0% 100%

            echo "---> Formatting ${TF_CARD}1 as ext4..."
            mkfs.ext4 -F "${TF_CARD}1"
            echo "---> Format complete."
        fi
    else
        echo -e "\n---> Skipping format. Assuming ${TF_CARD}1 already has a valid ext4 filesystem."
    fi
fi

# ==============================================================================
# Step 3: Patch extlinux.conf for TF Card Boot
# ==============================================================================
echo -e "\n================================================================"
echo "Step 3: Patch extlinux.conf for TF Card Boot"
echo "================================================================"

EXTLINUX="/boot/extlinux/extlinux.conf"
EXTLINUX_BAK="/boot/extlinux/extlinux.conf.bak"

confirm "Proceed with extlinux.conf patching?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping extlinux.conf patching. You must configure boot manually."
else
    if [ ! -f "$EXTLINUX" ]; then
        echo "WARNING: $EXTLINUX not found. Cannot patch." >&2
        echo "         You may need to configure boot manually." >&2
    else
        # Backup current extlinux.conf (if not already backed up)
        if [ ! -f "$EXTLINUX_BAK" ]; then
            cp "$EXTLINUX" "$EXTLINUX_BAK"
            echo "---> Backed up extlinux.conf -> extlinux.conf.bak"
        else
            echo "---> Backup already exists (extlinux.conf.bak). Preserving original backup."
        fi

        # Show current root= line
        echo ""
        echo "Current boot config:"
        grep "root=" "$EXTLINUX" || echo "  (no root= line found)"

        # Replace mmcblk0p1 (eMMC) with mmcblk1 (TF card) in the root= parameter
        sed -i 's/mmcblk0p1/mmcblk1/g' "$EXTLINUX"

        echo ""
        echo "Updated boot config:"
        grep "root=" "$EXTLINUX"

        echo ""
        echo "---> extlinux.conf patched: root device changed from mmcblk0p1 (eMMC) to mmcblk1 (TF card)."
    fi
fi

# ==============================================================================
# Step 4: Clone rootfs to TF Card
# ==============================================================================
echo -e "\n================================================================"
echo "Step 4: Clone RootFS to TF Card"
echo "================================================================"

if [ -z "$TF_CARD" ] || [ ! -b "${TF_CARD}1" ]; then
    echo "WARNING: TF card not available. Skipping rootfs clone." >&2
    echo "         You can clone manually later:" >&2
    echo "           mount /dev/mmcblk1p1 /mnt/tfcard" >&2
    echo "           rsync -axHAWX --numeric-ids --info=progress2 / /mnt/tfcard/" >&2
    echo "           umount /mnt/tfcard" >&2
else
    confirm "Proceed with cloning rootfs to TF card?" y
    if [ "$CONFIRM_CHOICE" = "no" ]; then
        echo "---> Skipping rootfs clone. You can clone manually later."
    else
        MOUNT_POINT="/mnt/tfcard"

        echo -e "\n---> Mounting ${TF_CARD}1..."
        mkdir -p "$MOUNT_POINT"

        # Unmount if already mounted (e.g. from a previous attempt)
        if mountpoint -q "$MOUNT_POINT"; then
            umount "$MOUNT_POINT" 2>/dev/null || true
        fi

        mount "${TF_CARD}1" "$MOUNT_POINT"

        echo -e "\n---> Cloning rootfs to TF card (this will take several minutes)..."
        echo "    Progress will be shown below."
        rsync -axHAWX --numeric-ids --info=progress2 / "$MOUNT_POINT"/

        echo -e "\n---> Syncing filesystem..."
        sync

        echo -e "\n---> Unmounting TF card..."
        umount "$MOUNT_POINT"
        rmdir "$MOUNT_POINT" 2>/dev/null || true

        echo "---> RootFS clone complete."
    fi
fi

# ==============================================================================
# Step 5: Reboot
# ==============================================================================
echo -e "\n================================================================"
echo "  PHASE 2 COMPLETE!"
echo ""
echo "  The system is now configured to boot from the TF card."
echo "  After reboot:"
echo "    - The Jetson will boot from /dev/mmcblk1 (TF card)"
echo "    - Login as nvidia / nvidia"
echo "    - Run:  sudo ~/phase3_ai_environment.sh"
echo "================================================================"
echo ""

confirm "Reboot now?" y
if [ "$CONFIRM_CHOICE" = "yes" ]; then
    reboot
else
    echo "---> Reboot manually when ready: sudo reboot"
fi
