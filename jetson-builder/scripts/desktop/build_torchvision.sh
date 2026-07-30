#!/bin/bash
set -e

echo "================================================================="
echo "   JETSON NANO: Native Torchvision 0.11.1 Compilation Script    "
echo "================================================================="

# Target Maxwell GPU Architecture (Compute 5.3 for Jetson Nano)
export FORCE_CUDA=1
export TORCH_CUDA_ARCH_LIST="5.3"
export BUILD_VERSION=0.11.1
export MAX_JOBS=2

echo "---> Checking PyTorch state..."
python3 -c "import torch; print('PyTorch Version:', torch.__version__)"

BUILD_DIR="$HOME/torchvision_build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "---> Cloning Torchvision 0.11.1 source..."
git clone --branch v0.11.1 https://github.com/pytorch/vision.git "$BUILD_DIR"
cd "$BUILD_DIR"

echo "---> Compiling and installing Torchvision (MAX_JOBS=2)..."
python3 setup.py install --user

echo "---> Cleaning up build directory..."
cd "$HOME"
rm -rf "$BUILD_DIR"

echo "================================================================="
echo " SUCCESS! Torchvision 0.11.1 build & installation complete."
echo "================================================================="