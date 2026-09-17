# SSIM Sharpen Ultimate 🐊

SSIM-based post-resize sharpening shader for MPC-BE. It is designed to sharpen both edges and fine textures while keeping haloing to a minimum.

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

## Installation

1. Download the latest version of `SSIM_Sharpen_Ultimate_vX.X.hlsl`.

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

## Bug Reports

No known bugs have been found so far in current testing. If you notice a bug, visual artifact, compatibility issue, or other unexpected behavior, feel free to report it through [GitHub Issues](https://github.com/SamerDesgin/SSIM-Sharpen-Ultimate/issues).

---

Created by **Samer the Croc 🐊**
