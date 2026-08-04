#!/bin/bash

# ==============================================================================
# PHASE 3: Jetson Nano — AI Environment Setup (Jetson-Side)
# Waveshare JETSON-NANO-DEV-KIT One-Click Setup
#
# Runs on: Jetson Nano (after booting from TF card in Phase 2)
# Objective: Remove bloatware, install CUDA/PyTorch/Torchvision,
#            jstest-gtk, jetson-stats, clone jetson-containers@5645241
#
# Software Stack (JetPack 4.6.6 / L4T 32.7.6):
#   - CUDA 10.2, cuDNN 8
#   - PyTorch 1.10.0 (pre-built aarch64 wheel)
#   - Torchvision 0.11.1 (built from source)
#   - jetson-stats (jtop utility)
#   - jstest-gtk (joystick tester)
#   - jetson-containers @ commit 5645241
#
# Prerequisites:
#   - Phase 2 completed (Jetson boots from TF card)
#   - Internet access for package downloads
#   - ~4 GB free disk space on TF card
#
# Usage:
#   sudo ~/phase3_ai_environment.sh
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
echo "  PHASE 3: AI Environment Setup (Jetson-Side)"
echo "  Waveshare Jetson Nano Dev Kit"
echo "  JetPack 4.6.6 (L4T 32.7.6) | CUDA 10.2 | PyTorch 1.10.0"
echo "================================================================"
echo ""
echo "This script will:"
echo "  Step 1 — Purge desktop bloatware"
echo "  Step 2 — Install CUDA toolkit, cuDNN, build tools, jstest-gtk"
echo "  Step 3 — Setup CUDA environment variables in .bashrc"
echo "  Step 4 — Install PyTorch 1.10.0 (pre-built wheel)"
echo "  Step 5 — Build & install Torchvision 0.11.1 from source"
echo "  Step 6 — Install jetson-stats (jtop)"
echo "  Step 7 — Clone jetson-containers @ commit 5645241 & run install.sh"
echo "  Step 8 — (Optional) Configure SPI1 & PWM"
echo "  Step 9 — Final cleanup"
echo ""

# ==============================================================================
# Step 1: Purge Bloatware
# ==============================================================================
echo -e "\n================================================================"
echo "Step 1: Purge Desktop Bloatware"
echo "================================================================"

# --- 1a: Patch NVIDIA APT repository SOC placeholder ---
# NOTE: Commented out — not typically needed on JetPack 4.6.6 rootfs.
#       Uncomment if your APT source list contains the '<SOC>' placeholder.
# NVIDIA_L4T_SOURCE="/etc/apt/sources.list.d/nvidia-l4t-apt-source.list"
# if [ -f "$NVIDIA_L4T_SOURCE" ] && grep -q '<SOC>' "$NVIDIA_L4T_SOURCE"; then
#     echo "---> Patching <SOC> placeholder -> t210 in NVIDIA APT source..."
#     sed -i 's|<SOC>|t210|g' "$NVIDIA_L4T_SOURCE"
# else
#     echo "---> NVIDIA APT source already patched or not present."
# fi

confirm "Proceed with bloatware removal?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping bloatware removal."
else
    echo -e "\n---> Purging desktop bloatware..."

    BLOATWARE=(
        gnome-mahjongg
        gnome-mines
        gnome-sudoku
        leafpad
        libreoffice
        libreoffice-calc
        libreoffice-draw
        libreoffice-impress
        libreoffice-math
        libreoffice-writer
        lxmusic
        rhythmbox
        shotwell
        thunderbird
        transmission
        todo
        smplayer
        simple-scan
    )

    for pkg in "${BLOATWARE[@]}"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            echo "  Removing $pkg..."
            apt-get purge -y "$pkg" || true
        fi
    done
    apt-get autoremove --purge -y || true
    echo "---> Bloatware removal complete."
fi

# ==============================================================================
# Step 2: Install CUDA, cuDNN, Build Tools, jstest-gtk
# ==============================================================================
echo -e "\n================================================================"
echo "Step 2: Install CUDA Toolkit, cuDNN, Tools & jstest-gtk"
echo "================================================================"

confirm "Proceed with CUDA/toolchain installation?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping CUDA/toolchain installation."
else
    echo -e "\n---> Updating APT package lists..."
    apt-get update

    echo -e "\n---> Installing L4T core, CUDA 10.2, cuDNN 8, build chain & jstest-gtk..."
    apt-get install -y \
        nvidia-l4t-core \
        nvidia-container-runtime \
        cuda-toolkit-10-2 \
        libavcodec-dev \
        libavformat-dev \
        libswscale-dev \
        libcudnn8 \
        libcudnn8-dev \
        libopencv-dev \
        python3-opencv \
        libjpeg-dev \
        zlib1g-dev \
        libpython3-dev \
        libopenblas-dev \
        libopenmpi-dev \
        libomp-dev \
        python3-pip \
        python3-dev \
        git \
        wget \
        curl \
        jstest-gtk \
        nano

    echo "---> CUDA toolkit and dependencies installed."
fi

# ==============================================================================
# Step 3: Setup CUDA Environment Variables
# ==============================================================================
echo -e "\n================================================================"
echo "Step 3: Setup CUDA Environment Variables"
echo "================================================================"
echo ""
echo "This step appends CUDA paths to .bashrc so they are available"
echo "on every login, per the Waveshare setup instructions:"
echo "  export PATH=/usr/local/cuda-10.2/bin:\$PATH"
echo "  export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH"
echo "  export CUDA_HOME=\$CUDA_HOME:/usr/local/cuda-10.2"
echo ""

confirm "Add CUDA environment variables to .bashrc?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping CUDA environment setup. You can add them manually later."
else
    BASHRC="/home/nvidia/.bashrc"

    # Create .bashrc if it doesn't exist
    if [ ! -f "$BASHRC" ]; then
        touch "$BASHRC"
        chown 1000:1000 "$BASHRC" 2>/dev/null || true
    fi

    # Add CUDA environment variables if not already present
    if ! grep -q "cuda-10.2/bin" "$BASHRC"; then
        echo "" >> "$BASHRC"
        echo "# CUDA Environment Variables" >> "$BASHRC"
        echo "export PATH=/usr/local/cuda-10.2/bin:\$PATH" >> "$BASHRC"
        echo "export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH" >> "$BASHRC"
        echo "export CUDA_HOME=\$CUDA_HOME:/usr/local/cuda-10.2" >> "$BASHRC"
        echo "---> CUDA environment variables added to $BASHRC"
    else
        echo "---> CUDA environment variables already present in $BASHRC"
    fi

    # Also set them for the current script session
    export PATH=/usr/local/cuda-10.2/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
    export CUDA_HOME=${CUDA_HOME:-}:/usr/local/cuda-10.2

    echo "---> CUDA environment is active for this session."
fi

# ==============================================================================
# Step 4: Install PyTorch 1.10.0
# ==============================================================================
echo -e "\n================================================================"
echo "Step 4: Install PyTorch 1.10.0 (aarch64 pre-built wheel)"
echo "================================================================"

confirm "Proceed with PyTorch installation?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping PyTorch installation."
else
    # --- 4a: Upgrade pip toolchain ---
    echo -e "\n---> Upgrading pip & build prerequisites..."
    python3 -m pip install --upgrade --force-reinstall pip
    pip3 install --upgrade setuptools
    pip3 install "Cython<3" "numpy<1.20.0"

    # --- 4b: Download & install PyTorch ---
    PYTORCH_WHL="torch-1.10.0-cp36-cp36m-linux_aarch64.whl"
    PYTORCH_URL="https://nvidia.box.com/shared/static/fjtbno0vpo676a25cgvuqc1wty0fkkg6.whl"

    cd /tmp

    if python3 -c "import torch; assert torch.__version__ == '1.10.0'" 2>/dev/null; then
        echo "---> PyTorch 1.10.0 is already installed. Skipping."
    else
        echo -e "\n---> Downloading PyTorch 1.10.0 wheel (~800 MB)..."
        wget -q "$PYTORCH_URL" -O "$PYTORCH_WHL"

        echo "---> Installing PyTorch 1.10.0..."
        pip3 install --force-reinstall "$PYTORCH_WHL"
        rm -f "$PYTORCH_WHL"

        # Sanity check
        echo -e "\n---> Verifying PyTorch installation..."
        python3 -c "import torch; print('PyTorch', torch.__version__, 'loaded successfully!')"
    fi
fi

# ==============================================================================
# Step 5: Build & Install Torchvision 0.11.1
# ==============================================================================
echo -e "\n================================================================"
echo "Step 5: Build & Install Torchvision 0.11.1 (from source)"
echo "================================================================"

confirm "Proceed with Torchvision build?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping Torchvision build."
    echo "    You can build it manually later:"
    echo "      git clone --branch v0.11.1 https://github.com/pytorch/vision torchvision"
    echo "      cd torchvision && export BUILD_VERSION=0.11.1 && sudo python3 setup.py install"
    echo "      sudo pip3 uninstall -y pillow && sudo pip3 install pillow"
else
    if python3 -c "import torchvision; assert torchvision.__version__ == '0.11.1'" 2>/dev/null; then
        echo "---> Torchvision 0.11.1 is already installed. Skipping."
    else
        echo -e "\n---> This step compiles Torchvision from source and may take 15-30 minutes."

        cd /tmp

        if [ -d "torchvision" ]; then
            rm -rf torchvision
        fi

        echo "---> Cloning Torchvision v0.11.1..."
        git clone --branch v0.11.1 --depth 1 https://github.com/pytorch/vision torchvision
        cd torchvision

        echo "---> Building Torchvision 0.11.1..."
        export BUILD_VERSION=0.11.1
        python3 setup.py install

        # Cleanup build artifacts
        cd /tmp
        rm -rf torchvision

        # Reinstall Pillow to fix compatibility (per Waveshare instructions)
        echo -e "\n---> Reinstalling Pillow for Torchvision compatibility..."
        pip3 uninstall -y pillow || true
        pip3 install pillow

        # Verify
        echo -e "\n---> Verifying Torchvision installation..."
        python3 -c "import torchvision; print('Torchvision', torchvision.__version__, 'loaded successfully!')"
    fi
fi

# ==============================================================================
# Step 6: Install jetson-stats
# ==============================================================================
echo -e "\n================================================================"
echo "Step 6: Install jetson-stats (jtop utility)"
echo "================================================================"

confirm "Proceed with jetson-stats installation?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping jetson-stats installation."
else
    if command -v jtop >/dev/null 2>&1; then
        echo "---> jetson-stats is already installed. Updating..."
        pip3 install -U jetson-stats
    else
        echo -e "\n---> Installing jetson-stats..."
        pip3 install -U jetson-stats
    fi

    echo "---> jetson-stats installed. Run 'jtop' to monitor the Jetson."
fi

# ==============================================================================
# Step 7: Clone jetson-containers @ commit 5645241
# ==============================================================================
echo -e "\n================================================================"
echo "Step 7: Clone jetson-containers @ commit 5645241"
echo "================================================================"

confirm "Proceed with jetson-containers clone?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping jetson-containers clone."
else
    JETSON_CONTAINERS_COMMIT="5645241"
    DESKTOP_PATHS=("/home/nvidia/Desktop" "/etc/skel/Desktop")

    for TARGET_DESKTOP in "${DESKTOP_PATHS[@]}"; do
        CONTAINERS_DIR="$TARGET_DESKTOP/jetson-containers"

        mkdir -p "$TARGET_DESKTOP"

        if [ -d "$CONTAINERS_DIR" ]; then
            echo "---> $CONTAINERS_DIR already exists. Skipping clone."
            continue
        fi

        echo -e "\n---> Cloning jetson-containers into $CONTAINERS_DIR..."
        git clone https://github.com/dusty-nv/jetson-containers.git "$CONTAINERS_DIR"

        cd "$CONTAINERS_DIR"
        echo "---> Checking out commit $JETSON_CONTAINERS_COMMIT..."
        git checkout "$JETSON_CONTAINERS_COMMIT"

        # Run install.sh if present
        if [ -f "./install.sh" ]; then
            echo -e "\n---> Running jetson-containers install.sh..."
            bash ./install.sh || echo "Notice: jetson-containers install.sh finished with non-fatal warnings."
        else
            echo "---> No install.sh found in jetson-containers. Skipping."
        fi
    done

    # Fix ownership for nvidia user
    if [ -d "/home/nvidia" ]; then
        chown -R 1000:1000 /home/nvidia/Desktop 2>/dev/null || true
    fi
fi

# ==============================================================================
# Step 8: (Optional) SPI1 & PWM Configuration
# ==============================================================================
echo -e "\n================================================================"
echo "Step 8: SPI1 & PWM Configuration (Optional)"
echo "================================================================"

# --- SPI1 ---
confirm "Configure SPI1 (install minicom, pyserial, spidev)?" n
if [ "$CONFIRM_CHOICE" = "yes" ]; then
    echo -e "\n---> Installing SPI1 tools..."
    apt-get install -y minicom nano
    pip3 install pyserial spidev==3.1

    echo "---> SPI1 tools installed."
    echo "    To test SPI: short pins 19 & 21 on the 40-pin header, then run:"
    echo "      sudo modprobe spidev"
    echo "      git clone https://github.com/rm-hull/spidev-test && cd spidev-test && gcc spidev_test.c -o spidev_test && ./spidev_test"
else
    echo "---> Skipping SPI1 configuration."
fi

# --- PWM ---
confirm "Configure PWM0/PWM2 (export and set default values)?" n
if [ "$CONFIRM_CHOICE" = "yes" ]; then
    echo -e "\n---> Configuring PWM0 on pwmchip0..."

    if [ -d "/sys/class/pwm/pwmchip0" ]; then
        echo 0 > /sys/class/pwm/pwmchip0/export       2>/dev/null || true
        echo 8333333 > /sys/class/pwm/pwmchip0/pwm0/period     2>/dev/null || true
        echo 4166667 > /sys/class/pwm/pwmchip0/pwm0/duty_cycle 2>/dev/null || true
        echo 1 > /sys/class/pwm/pwmchip0/pwm0/enable   2>/dev/null || true
        echo "---> PWM0 configured (period: 8.33ms, duty: 4.17ms)."
        echo "    Kernel PWM debug:"
        cat /sys/kernel/debug/pwm 2>/dev/null || echo "    (debug info not available)"
    else
        echo "WARNING: /sys/class/pwm/pwmchip0 not found. PWM may not be available." >&2
    fi
else
    echo "---> Skipping PWM configuration."
fi

# ==============================================================================
# Step 9: Final Cleanup
# ==============================================================================
echo -e "\n================================================================"
echo "Step 9: Final Cleanup"
echo "================================================================"

confirm "Proceed with final cleanup?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping final cleanup."
else
    echo -e "\n---> Cleaning APT cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

    echo "---> Running ldconfig..."
    ldconfig

    echo "---> Cleanup complete."
fi

# ==============================================================================
# Done
# ==============================================================================
echo -e "\n================================================================"
echo "  PHASE 3 COMPLETE!"
echo ""
echo "  Installed software stack:"
echo "    - CUDA 10.2, cuDNN 8"
echo "    - PyTorch 1.10.0 + Torchvision 0.11.1"
echo "    - jetson-stats (jtop)"
echo "    - jstest-gtk"
echo "    - jetson-containers @ commit 5645241"
echo ""
echo "  Useful commands:"
echo "    jtop              — Monitor Jetson stats"
echo "    jstest-gtk        — Test joystick/gamepad"
echo "    jetson-release    — Show JetPack info"
echo "================================================================"
