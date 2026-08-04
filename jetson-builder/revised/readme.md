# Waveshare Jetson Nano Dev Kit — One-Click Setup

Automated 3-phase bash scripts to provision a **Waveshare JETSON-NANO-DEV-KIT** (eMMC variant) with JetPack 4.6.6 / L4T 32.7.6, TF card boot, and a full AI software stack.

## Software Stack

| Component | Version |
|-----------|---------|
| L4T / JetPack | 32.7.6 / 4.6.6 |
| CUDA | 10.2 |
| cuDNN | 8 |
| PyTorch | 1.10.0 |
| Torchvision | 0.11.1 |
| jetson-stats | latest (pip) |
| jetson-containers | commit `5645241` |

## Workflow Overview

```
┌─────────────────────────────────────────────────┐
│  PHASE 1 — Host PC (sudo)                       │
│  1. Download & extract L4T 32.7.6               │
│  2. Patch DTB (TF card boot, SPI, PWM)          │
│  3. Copy Phase 2/3 scripts + create user        │
│  4. Flash eMMC bootloader                       │
└──────────────────────┬──────────────────────────┘
                       │ Boot Jetson from eMMC
                       ▼
┌─────────────────────────────────────────────────┐
│  PHASE 2 — Jetson (sudo, booted from eMMC)      │
│  1. Detect & format TF card                     │
│  2. Patch extlinux.conf → TF card boot          │
│  3. Clone rootfs to TF card                     │
│  4. Reboot                                      │
└──────────────────────┬──────────────────────────┘
                       │ Boot Jetson from TF card
                       ▼
┌─────────────────────────────────────────────────┐
│  PHASE 3 — Jetson (sudo, booted from TF card)   │
│  1. Purge bloatware                             │
│  2. Install CUDA, cuDNN, tools, jstest-gtk      │
│  3. Setup CUDA env vars in .bashrc              │
│  4. Install PyTorch 1.10.0                      │
│  5. Build Torchvision 0.11.1 from source        │
│  6. Install jetson-stats                        │
│  7. Clone jetson-containers @ 5645241           │
│  8. (Optional) SPI1 & PWM config                │
│  9. Final cleanup                               │
└─────────────────────────────────────────────────┘
```

## Prerequisites

- **Host PC**: Ubuntu 18.04 or 20.04 (x86_64) with `sudo` access
- **Jetson**: Waveshare JETSON-NANO-DEV-KIT (eMMC variant, B01 revision)
- **TF Card**: MicroSD, minimum 32 GB, class 10 / UHS-I recommended
- **Cables**: Micro-USB data cable for Recovery Mode flash
- **Internet**: Required on both host and Jetson for downloads

## Quick Start

```bash
# On Host PC — all 3 scripts must be in the same directory
sudo ./phase1_build_and_flash.sh

# After Jetson boots from eMMC (login: nvidia / nvidia)
sudo ~/phase2_setup_tf_boot.sh

# After Jetson boots from TF card
sudo ~/phase3_ai_environment.sh
```

Every step has a **[Y/n]** or **[y/N]** confirmation prompt. You can skip any step or re-run the script — it detects already-installed components and skips them.

---

## Variables You Should Review

### Phase 1 — `phase1_build_and_flash.sh`

| Variable | Default | When to Change |
|----------|---------|----------------|
| `SDKM_INST` | `$HOME/nvidia/nvidia_sdk` | If you installed SDK Manager to a non-default path |
| `SDKM_DL` | `$HOME/Downloads/nvidia/sdkm_downloads` | If SDK Manager downloads are stored elsewhere |
| `TARGET_DIR` | `$SDKM_INST/JetPack_4.6.6_Linux_JETSON_NANO_TARGETS` | If targeting a different JetPack version |
| `BSP_URL` / `ROOTFS_URL` | L4T 32.7.6 URLs | If targeting a different L4T version (also update `DTB_FILE` below) |
| `DEFAULT_USERNAME` | `nvidia` | If you want a different default username |
| `DEFAULT_PASSWORD` | `nvidia` | If you want a different default password |
| `DTB_FILE` (Step 2) | `tegra210-p3448-0002-p3449-0000-b00.dtb` | If using a different board revision (e.g. A02 vs B01) — verify the correct DTB filename in `Linux_for_Tegra/kernel/dtb/` |

### Phase 2 — `phase2_setup_tf_boot.sh`

| Variable | Default | When to Change |
|----------|---------|----------------|
| `TF_CARD` (Step 1) | `/dev/mmcblk1` | Only if your TF card appears on a different block device — **never set to `mmcblk0`** (that is the eMMC) |
| `EXTLINUX` (Step 3) | `/boot/extlinux/extlinux.conf` | Only if your boot config resides at a non-standard path |

### Phase 3 — `phase3_ai_environment.sh`

| Variable | Default | When to Change |
|----------|---------|----------------|
| `BLOATWARE[]` (Step 1) | 18 desktop packages | Add/remove packages you want to keep or purge |
| `BASHRC` (Step 3) | `/home/nvidia/.bashrc` | If your username is not `nvidia` |
| `PYTORCH_URL` (Step 4) | NVIDIA Box PyTorch 1.10.0 wheel | If you want a different PyTorch version — must be a pre-built aarch64 wheel |
| `BUILD_VERSION` (Step 5) | `0.11.1` | Must match the git tag and be compatible with your PyTorch version |
| `JETSON_CONTAINERS_COMMIT` (Step 7) | `5645241` | If you want a different commit/branch of jetson-containers |
| `DESKTOP_PATHS[]` (Step 7) | `/home/nvidia/Desktop`, `/etc/skel/Desktop` | If your username differs or you want the repo elsewhere |

### Commented-Out Code to Check

| Location | What | When to Uncomment |
|----------|------|-------------------|
| Phase 3, Step 1 | NVIDIA APT `<SOC>` placeholder patch | If `apt-get update` fails with a `<SOC>` error in `nvidia-l4t-apt-source.list` |

---

## Recovery Mode (Phase 1, Step 4)

1. Place a jumper across **J40** header pins (FC REC) on the Jetson
2. Connect micro-USB from Jetson to host PC
3. Power on the Jetson
4. Verify with `lsusb` — you should see `NVIDIA Corp. APX` (ID `0955:7f21`)
5. Remove the jumper after flashing is complete

## Safeguards (Phase 2)

- **Root device check**: Script verifies the system is booted from eMMC (`/dev/mmcblk0`) and warns if booted from TF card
- **Hardcoded TF card target**: Only operates on `/dev/mmcblk1` — never touches `/dev/mmcblk0`
- **32 GB minimum**: Warns if TF card is below minimum size
- **Double confirmation**: Formatting requires two explicit confirmations
- **No premature exits**: All error conditions allow retry or skip to the next step

## References

- [Waveshare JETSON-NANO-DEV-KIT Wiki](https://www.waveshare.com/wiki/JETSON-NANO-DEV-KIT)
- [NVIDIA JetPack Install Setup](https://docs.nvidia.com/jetson/jetpack/install-setup/index.html#install-jetpack-components-on-jetson-linux)
- [NVIDIA L4T Archive](https://developer.nvidia.com/embedded/l4t-archive)

## License

These scripts are provided as-is for development purposes. NVIDIA L4T and JetPack components are subject to NVIDIA's software license agreement.