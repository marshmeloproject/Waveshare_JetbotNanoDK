#!/bin/bash
set -Eeuo pipefail

echo "---> [01_system_prep] Beginning base system setup..."

# 1. Install policy-rc.d to block services inside chroot
if [ -f /tmp/provision/config/policy-rc.d ]; then
    cp /tmp/provision/config/policy-rc.d /usr/sbin/policy-rc.d
    chmod +x /usr/sbin/policy-rc.d
fi

# 2. Patch NVIDIA APT repository SOC placeholder (<SOC> -> t210)
NVIDIA_L4T_SOURCE="/etc/apt/sources.list.d/nvidia-l4t-apt-source.list"
if [ -f "$NVIDIA_L4T_SOURCE" ] && grep -q '<SOC>' "$NVIDIA_L4T_SOURCE"; then
    echo "---> Patching <SOC> placeholder -> t210..."
    sed -i 's|<SOC>|t210|g' "$NVIDIA_L4T_SOURCE"
fi

# 3. Export library paths
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"

# 4. Purge desktop bloatware
echo "---> Purging desktop bloatware..."
for pkg in \
    gnome-mahjongg gnome-mines gnome-sudoku leafpad libreoffice libreoffice-calc \
    libreoffice-draw libreoffice-impress libreoffice-math libreoffice-writer \
    lxmusic rhythmbox shotwell thunderbird transmission todo smplayer simple-scan
do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        apt-get purge -y "$pkg" || true
    fi
done
apt-get autoremove --purge -y || true

# 5. Consolidated APT Installation (Includes jstest-gtk and PyTorch C++ prerequisites)
echo "---> Installing L4T Core, CUDA, cuDNN, toolchains, and jstest-gtk..."
apt-get update

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
    apt-file \
    jstest-gtk

echo "---> Updating apt-file database..."
apt-file update

echo "---> [01_system_prep] Base system setup complete!"