#!/bin/bash
set -e

CAMERA_OVERLAY="imx219"          # Camera Module v2.1; change to imx708 for Camera Module 3
BUILD_DIR="$HOME/rpi-build"
PYTHON_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

echo "==> Setting up Raspberry Pi camera stack (headless, $CAMERA_OVERLAY)"
echo "    Python: $PYTHON_VER | Build dir: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── 1. Remove conflicting system packages ────────────────────────────────────
echo ""
echo "==> [1/8] Removing conflicting system libcamera packages..."
sudo apt remove --purge -y rpicam-apps libcamera-dev libcamera0 2>/dev/null || true

# ── 2. Install build dependencies ───────────────────────────────────────────
echo ""
echo "==> [2/8] Installing build dependencies..."
sudo apt install -y \
    git cmake ninja-build meson \
    python3-pip python3-jinja2 python3-yaml python3-ply \
    libboost-dev libboost-program-options-dev \
    libgnutls28-dev openssl libtiff5-dev pybind11-dev \
    libglib2.0-dev libgstreamer-plugins-base1.0-dev \
    libdrm-dev libexif-dev libjpeg-dev libpng-dev \
    libcap-dev v4l-utils

# ── 3. Build libcamera (Raspberry Pi fork) ───────────────────────────────────
echo ""
echo "==> [3/8] Building libcamera..."
if [ ! -d "$BUILD_DIR/libcamera" ]; then
    git clone https://github.com/raspberrypi/libcamera.git "$BUILD_DIR/libcamera"
fi
cd "$BUILD_DIR/libcamera"
git pull --ff-only

meson setup build --buildtype=release \
    -Dpipelines=rpi/vc4,rpi/pisp \
    -Dipas=rpi/vc4,rpi/pisp \
    -Dv4l2=true \
    -Dgstreamer=enabled \
    -Dtest=false \
    -Dlc-compliance=disabled \
    -Dcam=disabled \
    -Dqcam=disabled \
    -Ddocumentation=disabled \
    -Dpycamera=enabled \
    --reconfigure 2>/dev/null || \
meson setup build --buildtype=release \
    -Dpipelines=rpi/vc4,rpi/pisp \
    -Dipas=rpi/vc4,rpi/pisp \
    -Dv4l2=true \
    -Dgstreamer=enabled \
    -Dtest=false \
    -Dlc-compliance=disabled \
    -Dcam=disabled \
    -Dqcam=disabled \
    -Ddocumentation=disabled \
    -Dpycamera=enabled

ninja -C build
sudo ninja -C build install

# ── 4. Fix Python bindings path ──────────────────────────────────────────────
# meson installs to python3/dist-packages; Python 3.x only searches python3.x/dist-packages
echo ""
echo "==> [4/8] Fixing libcamera Python bindings path..."
LIBCAM_SRC="/usr/local/lib/python3/dist-packages/libcamera"
LIBCAM_DST="/usr/local/lib/python${PYTHON_VER}/dist-packages/libcamera"
if [ -d "$LIBCAM_SRC" ] && [ ! -e "$LIBCAM_DST" ]; then
    sudo ln -s "$LIBCAM_SRC" "$LIBCAM_DST"
    echo "    Linked $LIBCAM_SRC → $LIBCAM_DST"
else
    echo "    Already in place, skipping."
fi

# ── 5. Build rpicam-apps (headless) ──────────────────────────────────────────
echo ""
echo "==> [5/8] Building rpicam-apps..."
if [ ! -d "$BUILD_DIR/rpicam-apps" ]; then
    git clone https://github.com/raspberrypi/rpicam-apps.git "$BUILD_DIR/rpicam-apps"
fi
cd "$BUILD_DIR/rpicam-apps"
git pull --ff-only

meson setup build \
    -Denable_libav=disabled \
    -Denable_drm=disabled \
    -Denable_egl=disabled \
    -Denable_qt=disabled \
    -Denable_opencv=disabled \
    -Denable_tflite=disabled \
    -Denable_hailo=disabled \
    --reconfigure 2>/dev/null || \
meson setup build \
    -Denable_libav=disabled \
    -Denable_drm=disabled \
    -Denable_egl=disabled \
    -Denable_qt=disabled \
    -Denable_opencv=disabled \
    -Denable_tflite=disabled \
    -Denable_hailo=disabled

meson compile -C build
sudo meson install -C build
sudo ldconfig

# ── 6. Enable camera overlay in config.txt ───────────────────────────────────
echo ""
echo "==> [6/8] Enabling camera overlay ($CAMERA_OVERLAY)..."
CONFIG="/boot/firmware/config.txt"
if ! grep -q "dtoverlay=$CAMERA_OVERLAY" "$CONFIG"; then
    echo "dtoverlay=$CAMERA_OVERLAY" | sudo tee -a "$CONFIG" > /dev/null
    echo "    Added dtoverlay=$CAMERA_OVERLAY to $CONFIG"
else
    echo "    Already present, skipping."
fi

# ── 7. Install Python packages and patch picamera2 for headless ──────────────
echo ""
echo "==> [7/8] Installing Python packages..."
pip install opencv-python-headless picamera2 --break-system-packages -q

echo "    Patching picamera2 for headless (no pykms)..."
python3 - <<'EOF'
import importlib.util, pathlib, sys

spec = importlib.util.find_spec("picamera2")
if spec is None:
    print("    picamera2 not found, skipping patch.")
    sys.exit(0)

base = pathlib.Path(spec.origin).parent

drm = base / "previews" / "drm_preview.py"
init = base / "previews" / "__init__.py"

old_drm = (
    "except ImportError:\n"
    "    import pykms\n"
    "    from pykms import PixelFormat\n"
)
new_drm = (
    "except ImportError:\n"
    "    try:\n"
    "        import pykms\n"
    "        from pykms import PixelFormat\n"
    "    except ImportError:\n"
    "        pykms = None\n"
    "        PixelFormat = None\n"
)
text = drm.read_text()
if old_drm in text:
    drm.write_text(text.replace(old_drm, new_drm))
    print(f"    Patched {drm}")
else:
    print(f"    drm_preview.py already patched.")

old_init = "from .drm_preview import DrmPreview\n"
new_init = (
    "try:\n"
    "    from .drm_preview import DrmPreview\n"
    "except (ImportError, Exception):\n"
    "    DrmPreview = None\n"
)
text = init.read_text()
if old_init in text and new_init not in text:
    init.write_text(text.replace(old_init, new_init))
    print(f"    Patched {init}")
else:
    print(f"    previews/__init__.py already patched.")
EOF

# ── 8. Add user to video group ───────────────────────────────────────────────
echo ""
echo "==> [8/8] Adding $USER to video group..."
sudo usermod -aG video "$USER"

echo ""
echo "==> Setup complete."
echo "    A reboot is required to activate the camera overlay."
read -r -p "    Reboot now? [y/N] " response
if [[ "$response" =~ ^[Yy]$ ]]; then
    sudo reboot
fi
