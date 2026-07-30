#!/bin/bash
set -Eeuo pipefail

echo "---> [02_ai_environment] Beginning AI stack provisioning..."

# Helper function to scan Python site-packages and resolve missing .so dependencies
auto_fix_missing_libs() {
    echo "---> [AUTO-FIX] Scanning Python site-packages for missing shared libraries..."
    local site_pkg
    site_pkg=$(python3 -c "import site; print(site.getsitepackages()[0])")
    
    local missing_libs
    missing_libs=$(find "$site_pkg" -name "*.so" -exec ldd {} + 2>/dev/null | grep "not found" | awk '{print $1}' | sort -u || true)

    if [ -z "$missing_libs" ]; then
        echo "---> [AUTO-FIX] All dynamic library dependencies are satisfied!"
        return 0
    fi

    for lib in $missing_libs; do
        echo "---> [AUTO-FIX] Missing library detected: $lib"
        local pkg
        pkg=$(apt-file search "$lib" | head -n1 | cut -d: -f1 || true)
        
        if [ -n "$pkg" ]; then
            echo "---> [AUTO-FIX] Installing '$pkg' to resolve $lib..."
            apt-get install -y "$pkg"
        else
            echo "WARNING: Could not automatically locate an APT package for $lib" >&2
        fi
    done
    ldconfig
}

export LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"

# 1. Upgrade Pip Toolchain
echo "---> Upgrading pip, installing jetson-stats & PyTorch 1.10.0..."
python3 -m pip install --upgrade --force-reinstall pip
pip3 install --upgrade setuptools
pip3 install "Cython<3" "numpy<1.20.0"

# 2. Install jetson-stats (jtop utility)
pip3 install -U jetson-stats

# 3. Download and Install PyTorch 1.10.0
cd /tmp
wget -q https://nvidia.box.com/shared/static/fjtbno0vpo676a25cgvuqc1wty0fkkg6.whl -O torch-1.10.0-cp36-cp36m-linux_aarch64.whl
pip3 install --force-reinstall torch-1.10.0-cp36-cp36m-linux_aarch64.whl
rm -f torch-1.10.0-cp36-cp36m-linux_aarch64.whl

# 4. Resolve dynamic library linkages (e.g. OpenBLAS)
auto_fix_missing_libs

# 5. Sanity Check
echo "---> Verifying PyTorch C++ backend..."
python3 -c "import torch; print('PyTorch successfully loaded! Version:', torch.__version__)"

# 6. Setup Desktop Folders, jetson-containers, and build script
echo "---> Setting up Desktop artifacts..."
DESKTOP_PATHS=("/etc/skel/Desktop" "/home/nvidia/Desktop")

for TARGET_DESKTOP in "${DESKTOP_PATHS[@]}"; do
    mkdir -p "$TARGET_DESKTOP"

    # Clone jetson-containers (commit 5645241) and run install.sh
    CONTAINERS_DIR="$TARGET_DESKTOP/jetson-containers"
    if [ ! -d "$CONTAINERS_DIR" ]; then
        echo "---> Cloning jetson-containers into $CONTAINERS_DIR..."
        git clone https://github.com/dusty-nv/jetson-containers.git "$CONTAINERS_DIR"
        cd "$CONTAINERS_DIR"
        echo "---> Checking out commit 5645241..."
        git checkout 5645241
        
        if [ -f "./install.sh" ]; then
            echo "---> Running jetson-containers install.sh..."
            bash ./install.sh || echo "Notice: jetson-containers install.sh finished with non-fatal warnings."
        fi
    fi

    # Copy build_torchvision.sh to user Desktop
    if [ -f "/tmp/provision/desktop/build_torchvision.sh" ]; then
        cp /tmp/provision/desktop/build_torchvision.sh "$TARGET_DESKTOP/build_torchvision.sh"
        chmod +x "$TARGET_DESKTOP/build_torchvision.sh"
    fi
done

# Fix user ownership if pre-existing
if [ -d "/home/nvidia" ]; then
    chown -R 1000:1000 /home/nvidia/Desktop 2>/dev/null || true
fi

# 7. Final Cleanup
echo "---> Performing final system cleanup..."
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*
rm -f /usr/sbin/policy-rc.d
ldconfig

echo "---> [02_ai_environment] AI stack provisioning complete!"