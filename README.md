# SSIM Sharpen Ultimate 🐊

SSIM-based post-resize sharpening shader for MPC-BE. It is designed to sharpen both edges and fine textures while keeping haloing to a minimum.

**[Download the latest release](https://github.com/SamerDesgin/SSIM-Sharpen-Ultimate/releases/latest)**

## Features

- **Edge + Texture Sharpening**  
  Unlike basic sharpen filters that mainly emphasize edges, this shader also enhances fine surface texture and local detail.

- **Minimal Haloing**  
  Designed to keep bright and dark edge halos extremely low while retaining noticeable sharpening.

- **Adaptive Sharpening**  
  Applies more sharpening where useful detail exists and backs off in areas that are already smooth or naturally soft.

- **Noise-Aware Detail Protection**  
  Helps avoid turning compression noise, grain, or unstable detail into harsh artifacts.

- **Depth-Aware Processing**  
  Reduces sharpening in naturally blurred or out-of-focus regions.

- **SDR & HDR Aware**  
  Built to behave consistently across SDR and HDR/scRGB playback.

- **Ready-to-Use Defaults**  
  The included settings are the recommended configuration. Manual tuning is optional.

## Compatibility

- MPC-BE with the DirectX 11 shader path (`Shaders11`)
- Minimum shader profile: `ps_4_0`
- Designed as a **Post-Resize Pixel Shader**
- Tuned primarily for upscaled video and NVIDIA VSR workflows
- Supports SDR and HDR/scRGB-aware processing

## Installation

1. Download the latest version of `SSIM_Sharpen_Ultimate_vX.X.hlsl` from the [Releases](https://github.com/SamerDesgin/SSIM-Sharpen-Ultimate/releases/latest) page.

2. Copy it into your MPC-BE `Shaders11` folder.

   Common locations:

   ```text
   %APPDATA%\MPC-BE\Shaders11
   ```

   or:

   ```text
   C:\Program Files\MPC-BE\Shaders11
   ```

   Portable installations may have `Shaders11` inside the MPC-BE folder.

3. Restart MPC-BE if it is already running.

4. Open:

   **Play → Shaders → Select Shaders...**

5. Add **SSIM Sharpen Ultimate** to the **Post-Resize Pixel Shaders** list.

6. Make sure:

   **Play → Shaders → Enable Post-Resize Pixel Shaders**

   is enabled.

## Before / After Comparison

Press:

**Ctrl + Alt + P**

to quickly toggle **Post-Resize Pixel Shaders** on/off and compare the sharpened image with the original.

The included default settings are the recommended settings. No tuning is required for normal use.

## Changelog

See [CHANGELOG.txt](https://github.com/SamerDesgin/SSIM-Sharpen-Ultimate/blob/main/CHANGELOG.txt) for meaningful changes between versions.

## Credits

Based on the SSIM / SSimSuperRes work by **Shiandow** and the **igv implementation**. The upstream SSimSuperRes source is distributed under the **GNU Lesser General Public License v3.0 or later**.

This project preserves the original attribution and keeps the added shader work under compatible LGPL-3.0-or-later terms. See [LICENSE.md](https://github.com/SamerDesgin/SSIM-Sharpen-Ultimate/blob/main/LICENSE.md).

## Bug Reports

No known bugs have been found in testing so far. If you notice a bug, visual artifact, compatibility issue, or other unexpected behavior, feel free to report it through [GitHub Issues](https://github.com/SamerDesgin/SSIM-Sharpen-Ultimate/issues).

When reporting an issue, include your MPC-BE version, GPU, renderer setup, SDR/HDR state, NVIDIA VSR state, and a screenshot when possible.

---

Created by **Samer the Croc 🐊**
