# Raspcam-ubuntu24

Headless Raspberry Pi camera stack with OpenCV — one script installs everything from source, one script captures and processes a frame.

**Hardware:** Raspberry Pi 4 · Ubuntu 24.04 · Camera Module v2.1 (imx219)

---

## Quick start

```bash
bash setup.sh
# (reboot when prompted)
python3 demo.py
```

Output: `original.jpg`, `gray.jpg`, `edges.jpg`, `overlay.jpg` in the working directory.

---

## What `setup.sh` does

The Ubuntu 24.04 system `libcamera` does not support Raspberry Pi cameras — it must be replaced with the RPi fork built from source. `setup.sh` handles the full chain:

| Step | Action |
|------|--------|
| 1 | Remove conflicting `libcamera` system packages |
| 2 | Install build dependencies |
| 3 | Clone & build **libcamera** (RPi fork) with Python bindings |
| 4 | Symlink Python bindings into the versioned site-packages path Python 3.x actually searches |
| 5 | Clone & build **rpicam-apps** (headless — no Qt/DRM/EGL) |
| 6 | Append `dtoverlay=imx219` to `/boot/firmware/config.txt` |
| 7 | Install `picamera2` + `opencv-python-headless`; patch picamera2 for headless use |
| 8 | Add user to `video` group; prompt reboot |

All steps are idempotent — safe to re-run.

### Changing the camera model

Edit the `CAMERA_OVERLAY` variable at the top of `setup.sh`:

| Camera | Overlay |
|--------|---------|
| Camera Module v2.1 | `imx219` |
| Camera Module 3 | `imx708` |
| HQ Camera | `imx477` |

### Low-memory build

If the build OOMs, open `setup.sh` and change:
```bash
ninja -C build
```
to:
```bash
ninja -C build -j1
```

---

## What `demo.py` does

Captures one still frame at 1920×1080 and runs it through a simple OpenCV pipeline:

```
camera → original.jpg
       → grayscale → gray.jpg
       → gaussian blur → canny edges → edges.jpg
       → edges overlaid in green → overlay.jpg
```

---

## Known quirks

**`libcamera` Python bindings path**
The RPi libcamera meson build installs Python bindings to `/usr/local/lib/python3/dist-packages/` but Python 3.x only searches `/usr/local/lib/python3.x/dist-packages/`. `setup.sh` creates a symlink to bridge the gap.

**`pykms` missing on headless Ubuntu**
`picamera2` unconditionally imports `pykms` (a KMS/DRM display driver) at module load time, which fails on headless systems. `setup.sh` patches the two affected files in the installed `picamera2` package to make the import optional. This only affects live preview — capture and processing are unaffected.

---

## Dependencies

Managed entirely by `setup.sh`. No `requirements.txt` needed — the only pip packages are `picamera2` and `opencv-python-headless`.
