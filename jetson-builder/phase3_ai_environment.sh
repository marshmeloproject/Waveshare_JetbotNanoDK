#!/bin/bash

# ==============================================================================
# PHASE 3: Jetson Nano — AI Environment Setup (Jetson-Side)
# Waveshare JETSON-NANO-DEV-KIT One-Click Setup
#
# Runs on: Jetson Nano (after booting from TF card in Phase 2)
# Objective: Remove bloatware, install CUDA/jetson-stats/Docker,
#            clone jetson-containers, configure power & swap.
#            PyTorch/Torchvision install is offered last (optional)
#            since jetson-containers handles them via containers.
#
# Software Stack (JetPack 4.6.6 / L4T 32.7.6):
#   - CUDA 10.2, cuDNN 8
#   - Docker with NVIDIA runtime (default)
#   - jetson-stats (jtop utility)
#   - jetson-containers @ commit 5645241
#   - jstest-gtk (joystick tester)
#   - (Optional) PyTorch 1.10.0 + Torchvision 0.11.1
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
# Dynamic home directory — do not hardcode "nvidia"
# ------------------------------------------------------------------------------
JETSON_USER="${SUDO_USER:-$USER}"
JETSON_HOME=$(getent passwd "$JETSON_USER" | cut -d: -f6)
if [ -z "$JETSON_HOME" ] || [ ! -d "$JETSON_HOME" ]; then
    JETSON_HOME="/home/$JETSON_USER"
fi
JETSON_UID=$(getent passwd "$JETSON_USER" | cut -d: -f3 || echo 1000)
JETSON_GID=$(getent passwd "$JETSON_USER" | cut -d: -f4 || echo 1000)

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
echo "  JetPack 4.6.6 (L4T 32.7.6) | CUDA 10.2"
echo "================================================================"
echo ""
echo "  Detected user : $JETSON_USER"
echo "  Home directory: $JETSON_HOME"
echo ""
echo "This script will:"
echo "  Step 1  — Purge desktop bloatware"
echo "  Step 2  — Install CUDA toolkit, cuDNN, build tools, jstest-gtk"
echo "  Step 3  — Setup CUDA environment variables in .bashrc"
echo "  Step 4  — Install jetson-stats (jtop)"
echo "  Step 5  — Setup Docker (NVIDIA default runtime + user group)"
echo "  Step 6  — Clone jetson-containers @ commit 5645241"
echo "  Step 7  — Set power mode (MAXN)"
echo "  Step 8  — Mount swap file"
echo "  Step 9  — (Optional) Configure SPI1 & PWM"
echo "  Step 10 — (Optional) Install PyTorch 1.10.0"
echo "  Step 11 — (Optional) Build Torchvision 0.11.1"
echo "  Step 12 — Final cleanup"
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
    echo "---> Skipping CUDA environment setup."
    echo "    You can add them manually later."
else
    BASHRC="$JETSON_HOME/.bashrc"

    # Create .bashrc if it doesn't exist
    if [ ! -f "$BASHRC" ]; then
        touch "$BASHRC"
        chown "$JETSON_UID:$JETSON_GID" "$BASHRC" 2>/dev/null || true
    fi

    # Add CUDA environment variables if not already present
    if ! grep -q "cuda-10.2/bin" "$BASHRC"; then
        {
            echo ""
            echo "# CUDA Environment Variables"
            echo "export PATH=/usr/local/cuda-10.2/bin:\$PATH"
            echo "export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH"
            echo "export CUDA_HOME=\$CUDA_HOME:/usr/local/cuda-10.2"
        } >> "$BASHRC"
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
# Step 4: Install jetson-stats
# ==============================================================================
echo -e "\n================================================================"
echo "Step 4: Install jetson-stats (jtop utility)"
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
# Step 5: Setup Docker — Default Runtime & User Group
# ==============================================================================
echo -e "\n================================================================"
echo "Step 5: Setup Docker (NVIDIA Default Runtime + User Group)"
echo "================================================================"
echo ""
echo "Per the jetson-containers setup guide, Docker must be configured"
echo "to use the NVIDIA runtime by default. This enables GPU access"
echo "inside containers without specifying --runtime=nvidia each time."
echo ""

confirm "Proceed with Docker setup?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping Docker setup."
else
    # --- 5a: Install Docker if not present ---
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "\n---> Docker not found. Installing..."
        apt-get install -y docker.io
    else
        echo "---> Docker is already installed."
    fi

    # --- 5b: Set NVIDIA as default runtime ---
    DAEMON_JSON="/etc/docker/daemon.json"

    echo -e "\n---> Configuring NVIDIA as default Docker runtime..."

    if [ -f "$DAEMON_JSON" ]; then
        # Check if nvidia runtime is already configured
        if grep -q '"nvidia"' "$DAEMON_JSON"; then
            echo "---> NVIDIA runtime already present in $DAEMON_JSON"
        else
            echo "WARNING: $DAEMON_JSON exists but does not contain NVIDIA runtime." >&2
            echo "         Please manually add the following to $DAEMON_JSON:" >&2
            echo '  {"runtimes": {"nvidia": {"path": "nvidia-container-runtime", "runtimeArgs": []}}}' >&2
            confirm "Overwrite daemon.json with NVIDIA runtime config?" n
            if [ "$CONFIRM_CHOICE" = "yes" ]; then
                cp "$DAEMON_JSON" "${DAEMON_JSON}.bak"
                cat > "$DAEMON_JSON" <<'EOF'
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    },
    "default-runtime": "nvidia"
}
EOF
                echo "---> $DAEMON_JSON updated (backup: ${DAEMON_JSON}.bak)"
            fi
        fi
    else
        cat > "$DAEMON_JSON" <<'EOF'
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    },
    "default-runtime": "nvidia"
}
EOF
        echo "---> Created $DAEMON_JSON with NVIDIA default runtime."
    fi

    # Restart Docker to apply changes
    echo -e "\n---> Restarting Docker daemon..."
    systemctl restart docker || echo "WARNING: Docker restart failed." >&2
    echo "---> Docker default runtime configured."

    # --- 5c: Add user to docker group ---
    echo -e "\n---> Adding user '$JETSON_USER' to docker group..."
    if ! groups "$JETSON_USER" | grep -q docker; then
        usermod -aG docker "$JETSON_USER"
        echo "---> User '$JETSON_USER' added to docker group."
        echo "    Note: You must log out and back in for group changes"
        echo "    to take effect, or run: newgrp docker"
    else
        echo "---> User '$JETSON_USER' is already in the docker group."
    fi
fi

# ==============================================================================
# Step 6: Clone jetson-containers @ commit 5645241
# ==============================================================================
echo -e "\n================================================================"
echo "Step 6: Clone jetson-containers @ commit 5645241"
echo "================================================================"

confirm "Proceed with jetson-containers clone?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping jetson-containers clone."
else
    JETSON_CONTAINERS_COMMIT="5645241"
    DESKTOP_PATHS=("$JETSON_HOME/Desktop" "/etc/skel/Desktop")

    for TARGET_DESKTOP in "${DESKTOP_PATHS[@]}"; do
        CONTAINERS_DIR="$TARGET_DESKTOP/jetson-containers"

        mkdir -p "$TARGET_DESKTOP"

        if [ -d "$CONTAINERS_DIR" ]; then
            echo "---> $CONTAINERS_DIR already exists. Skipping clone."
            continue
        fi

        echo -e "\n---> Cloning jetson-containers into $CONTAINERS_DIR..."
        git clone https://github.com/dusty-nv/jetson-containers.git \
            "$CONTAINERS_DIR"

        cd "$CONTAINERS_DIR"
        echo "---> Checking out commit $JETSON_CONTAINERS_COMMIT..."
        git checkout "$JETSON_CONTAINERS_COMMIT"

        # Run install.sh if present
        if [ -f "./install.sh" ]; then
            echo -e "\n---> Running jetson-containers install.sh..."
            bash ./install.sh \
                || echo "Notice: install.sh finished with non-fatal warnings."
        else
            echo "---> No install.sh found. Skipping."
        fi
    done

    # Fix ownership for Jetson user
    if [ -d "$JETSON_HOME" ]; then
        chown -R "$JETSON_UID:$JETSON_GID" \
            "$JETSON_HOME/Desktop" 2>/dev/null || true
    fi
fi

# ==============================================================================
# Step 7: Set Power Mode (MAXN)
# ==============================================================================
echo -e "\n================================================================"
echo "Step 7: Set Power Mode"
echo "================================================================"
echo ""
echo "Setting the Jetson to MAXN power mode (mode 0) enables all CPU/GPU"
echo "cores and maximum clock frequencies for best AI inference performance."
echo "This increases power consumption to ~10W and may require active cooling."
echo ""

confirm "Set power mode to MAXN (mode 0)?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping power mode configuration."
    echo "    You can change it later with: sudo nvpmodel -m <mode>"
else
    if command -v nvpmodel >/dev/null 2>&1; then
        nvpmodel -m 0
        echo "---> Power mode set to MAXN (mode 0)."
    else
        echo "WARNING: nvpmodel not found. Cannot set power mode." >&2
        echo "         Install jetson-stats and retry: pip3 install jetson-stats" >&2
    fi
fi

# ==============================================================================
# Step 8: Mount Swap File
# ==============================================================================
echo -e "\n================================================================"
echo "Step 8: Mount Swap File"
echo "================================================================"
echo ""
echo "The Jetson Nano has 4 GB RAM. Adding swap prevents out-of-memory"
echo "errors during container builds and large model inference."
echo ""

# Show current disk space for user reference
ROOT_FS="/"
AVAILABLE_GB=$(df -BG "$ROOT_FS" | awk 'NR==2 {print $4}' | tr -d 'G')
echo "  Current root filesystem free space: ${AVAILABLE_GB} GB"
echo ""

confirm "Create and mount a swap file?" y
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping swap setup."
else
    echo "Select swap size:"
    echo "  1) 4 GB  (minimum recommended)"
    echo "  2) 8 GB  (recommended for container builds)"
    echo "  3) 16 GB (for heavy workloads)"
    echo ""
    echo "  Your TF card has ${AVAILABLE_GB} GB free."
    echo ""

    # Validate swap choice against available space
    while true; do
        read -r -p "Enter choice [1/2/3]: " swap_choice
        case "$swap_choice" in
            1) SWAP_SIZE_GB=4; break ;;
            2) SWAP_SIZE_GB=8; break ;;
            3) SWAP_SIZE_GB=16; break ;;
            *)
                echo "  Invalid choice. Enter 1, 2, or 3." >&2 ;;
        esac
    done

    # Warn if swap exceeds half of available space
    if [ "$SWAP_SIZE_GB" -gt "$((AVAILABLE_GB / 2))" ]; then
        echo ""
        echo "WARNING: Swap size (${SWAP_SIZE_GB} GB) is more than half of" >&2
        echo "         available space (${AVAILABLE_GB} GB). This may fill your disk." >&2
        confirm "Continue anyway?" n
        if [ "$CONFIRM_CHOICE" = "no" ]; then
            echo "---> Skipping swap setup."
            SWAP_SIZE_GB=0
        fi
    fi

    if [ "$SWAP_SIZE_GB" -gt 0 ]; then
        SWAP_FILE="/swapfile"

        # Disable existing swap if present
        if swapon --show | grep -q "$SWAP_FILE"; then
            echo -e "\n---> Disabling existing swap at $SWAP_FILE..."
            swapoff "$SWAP_FILE"
        fi

        echo -e "\n---> Creating ${SWAP_SIZE_GB} GB swap file at $SWAP_FILE..."
        dd if=/dev/zero of="$SWAP_FILE" bs=1G count="$SWAP_SIZE_GB" \
            status=progress
        chmod 600 "$SWAP_FILE"
        mkswap "$SWAP_FILE"
        swapon "$SWAP_FILE"

        # Make swap persistent across reboots
        if ! grep -q "$SWAP_FILE" /etc/fstab; then
            echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
            echo "---> Swap entry added to /etc/fstab."
        else
            echo "---> Swap entry already in /etc/fstab."
        fi

        echo "---> ${SWAP_SIZE_GB} GB swap mounted successfully."
    fi
fi

# ==============================================================================
# Step 9: (Optional) SPI1 & PWM Configuration
# ==============================================================================
echo -e "\n================================================================"
echo "Step 9: SPI1 & PWM Configuration (Optional)"
echo "================================================================"

# --- SPI1 ---
confirm "Configure SPI1 (install minicom, pyserial, spidev)?" n
if [ "$CONFIRM_CHOICE" = "yes" ]; then
    echo -e "\n---> Installing SPI1 tools..."
    apt-get install -y minicom nano
    pip3 install pyserial spidev==3.1

    echo "---> SPI1 tools installed."
    echo "    To test SPI: short pins 19 & 21 on the 40-pin header,"
    echo "    then run:"
    echo "      sudo modprobe spidev"
    echo "      git clone https://github.com/rm-hull/spidev-test"
    echo "      cd spidev-test && gcc spidev_test.c -o spidev_test"
    echo "      ./spidev_test"
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
        cat /sys/kernel/debug/pwm 2>/dev/null \
            || echo "    (debug info not available)"
    else
        echo "WARNING: /sys/class/pwm/pwmchip0 not found." >&2
        echo "         PWM may not be available." >&2
    fi
else
    echo "---> Skipping PWM configuration."
fi

# ==============================================================================
# Step 10: Install PyTorch 1.10.0 (Optional)
# ==============================================================================
echo -e "\n================================================================"
echo "Step 10: Install PyTorch 1.10.0 (Optional)"
echo "================================================================"
echo ""
echo "NOTE: The jetson-containers repo (cloned in Step 6) provides"
echo "PyTorch via pre-built Docker containers, which is the recommended"
echo "approach. Installing PyTorch natively on the host is only needed"
echo "if you plan to run Python scripts outside of containers."
echo ""
echo "If you skip this step, you can still use PyTorch inside"
echo "containers with:  jetson-containers run pytorch"
echo ""

confirm "Install PyTorch 1.10.0 natively on the host?" n
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping native PyTorch installation."
    echo "    Use jetson-containers for containerized PyTorch."
else
    # --- 10a: Upgrade pip toolchain ---
    echo -e "\n---> Upgrading pip & build prerequisites..."
    python3 -m pip install --upgrade --force-reinstall pip
    pip3 install --upgrade setuptools
    pip3 install "Cython<3" "numpy<1.20.0"

    # --- 10b: Download & install PyTorch ---
    PYTORCH_WHL="torch-1.10.0-cp36-cp36m-linux_aarch64.whl"
    PYTORCH_URL="https://nvidia.box.com/shared/static/fjtbno0vpo676a25cgvuqc1wty0fkkg6.whl"

    cd /tmp

    if python3 -c "import torch; assert torch.__version__ == '1.10.0'" \
        2>/dev/null; then
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
# Step 11: Build & Install Torchvision 0.11.1 (Optional)
# ==============================================================================
echo -e "\n================================================================"
echo "Step 11: Build & Install Torchvision 0.11.1 (Optional)"
echo "================================================================"
echo ""
echo "NOTE: Like PyTorch, Torchvision is available via jetson-containers"
echo "Docker images. Building from source takes 15-30 minutes and is"
echo "only needed for native (non-container) usage."
echo ""
echo "If you skip this step, you can still use Torchvision inside"
echo "containers with:  jetson-containers run torchvision"
echo ""

confirm "Build Torchvision 0.11.1 natively on the host?" n
if [ "$CONFIRM_CHOICE" = "no" ]; then
    echo "---> Skipping native Torchvision build."
    echo "    Use jetson-containers for containerized Torchvision."
else
    if python3 -c "import torchvision; \
        assert torchvision.__version__ == '0.11.1'" 2>/dev/null; then
        echo "---> Torchvision 0.11.1 is already installed. Skipping."
    else
        echo -e "\n---> This step compiles Torchvision from source"
        echo "    and may take 15-30 minutes."

        cd /tmp

        if [ -d "torchvision" ]; then
            rm -rf torchvision
        fi

        echo "---> Cloning Torchvision v0.11.1..."
        git clone --branch v0.11.1 --depth 1 \
            https://github.com/pytorch/vision torchvision
        cd torchvision

        echo "---> Building Torchvision 0.11.1..."
        export BUILD_VERSION=0.11.1
        python3 setup.py install

        # Cleanup build artifacts
        cd /tmp
        rm -rf torchvision

        # Reinstall Pillow (per Waveshare instructions)
        echo -e "\n---> Reinstalling Pillow for compatibility..."
        pip3 uninstall -y pillow || true
        pip3 install pillow

        # Verify
        echo -e "\n---> Verifying Torchvision installation..."
        python3 -c "import torchvision; print('Torchvision', torchvision.__version__, 'loaded successfully!')"
    fi
fi

# ==============================================================================
# Step 12: Final Cleanup
# ==============================================================================
echo -e "\n================================================================"
echo "Step 12: Final Cleanup"
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
echo "  Installed / configured:"
echo "    - CUDA 10.2, cuDNN 8 (env vars in $JETSON_HOME/.bashrc)"
echo "    - Docker with NVIDIA default runtime"
echo "    - jetson-stats (jtop)"
echo "    - jstest-gtk"
echo "    - jetson-containers @ commit 5645241"
echo "    - Power mode: MAXN"
echo ""
echo "  Useful commands:"
echo "    jtop                — Monitor Jetson stats"
echo "    jstest-gtk          — Test joystick/gamepad"
echo "    jetson-release      — Show JetPack info"
echo "    docker run hello    — Test Docker + NVIDIA runtime"
echo "================================================================"
