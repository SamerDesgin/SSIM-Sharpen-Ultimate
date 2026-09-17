# SSIM Sharpen Ultimate 🐊

SSIM-based post-resize sharpening shader for MPC-BE. It is designed to sharpen both edges and fine textures while keeping haloing to a minimum.

**[Download the latest release](https://github.com/SamerDesgin/SSIM-Sharpen-Ultimate/releases/latest)**

## Development

This shader was developed with **AI assistance**, but not by simply generating a finished filter. It went through repeated hands-on testing of sharpening strength, edge response, texture recovery, haloing, noise behavior, and overall image balance on real video.

My background in **graphic design and visual work** guided the decisions about what looked natural, which artifacts were distracting, and which features were worth adding. AI was used as a coding and research assistant, while the visual evaluation, tuning direction, testing, feature choices, and final decisions were driven by repeated comparison and practical use.

## How the Sharpening Works

The shader compares each pixel with its surrounding pixels to estimate useful local detail, then adds that detail back in a controlled way. Strong edges and real texture are enhanced, while flat, soft, noisy, very dark, or halo-prone areas are reduced automatically.

This is what lets it sharpen both **contours and surface texture** without relying on a simple global edge boost.

## How It Differs from Other Sharpeners

Different sharpening shaders are built around different goals. This project is not simply an edge-sharpen filter with a stronger setting.

| Approach | Main focus | Simple description |
| --- | --- | --- |
| **Edge Sharpen** | Strong edges and outlines | Detects edges and increases local contrast around them. This can make contours look crisp, but surface texture is not usually the main target. MPC-HC's Edge Sharpen, for example, uses Prewitt-style edge detection. |
| **Adaptive Sharpen** | Blurry or medium-strength edges | Changes the sharpening amount depending on how strong an edge already is. [bacondither's Adaptive-sharpen](https://github.com/bacondither/Adaptive-sharpen) is designed to sharpen somewhat blurry edges more while reducing sharpening on already-sharp edges and flat areas, helping reduce ringing, noise, and banding. |
| **SSIM Sharpen Ultimate** | Edges **and** texture | Uses SSIM-inspired local weighting to estimate useful detail from nearby pixels, then enhances both contours and fine surface texture. It also separates high- and mid-frequency detail and adds protections for noise, dark areas, depth-of-field, bright-edge halos, chroma, and HDR. |

The practical difference is that **Edge Sharpen** is mainly about making outlines stronger, while **Adaptive Sharpen** mainly varies sharpening based on edge condition. **SSIM Sharpen Ultimate** is aimed at recovering a broader range of local detail while keeping the result controlled and natural-looking.

Reference: [MPC-HC Edge Sharpen example](https://gist.github.com/butterw/928aa8961c06e8df827e3546c07f57c5) · [Adaptive-sharpen](https://github.com/bacondither/Adaptive-sharpen)

## Features

- **Edge + Texture Sharpening**  
  Unlike basic sharpen filters that mainly emphasize edges, this shader also enhances fine surface texture and local detail.

- **Minimal Haloing**  
  Designed to keep bright and dark edge halos extremely low while retaining noticeable sharpening.

- **Adaptive Sharpening**  
  Applies more sharpening where useful detail exists and backs off in areas that are already smooth or naturally soft.

- **Resolution-Aware Sampling**  
  Uses the current post-resize pixel size when sampling neighboring pixels, so the sharpening footprint follows the actual output resolution instead of relying on fixed texture-coordinate offsets.

- **Upscale-Aware Tuning**  
  Tuned around lower-resolution video being upscaled through [MPC Video Renderer](https://github.com/Aleksoid1978/VideoRenderer)'s **Super Resolution** path, including the NVIDIA VSR workflow I use on supported GeForce hardware. The defaults were tested especially around 720p/1080p → 2K playback, helping preserve useful detail without over-sharpening naturally soft areas.

- **Noise-Aware Detail Protection**  
  Helps avoid turning compression noise, grain, or unstable detail into harsh artifacts.

- **Depth-Aware Processing**  
  Reduces sharpening in naturally blurred or out-of-focus regions.

- **SDR & HDR Aware**  
  Built to behave consistently across SDR and HDR/scRGB playback.

- **Ready-to-Use Defaults**  
  The included settings are the recommended configuration. Manual tuning is optional.

## Sharpening Strength

The recommended default is:

```hlsl
#define STRENGTH 0.31
```

`0.31` is intentionally **subtle but clearly useful**. It improves edge definition and texture without pushing the image into an obviously sharpened look, and the difference is easy to check with **Ctrl + Alt + P**.

If you want a stronger result while still staying away from an aggressive look, `0.33` is the recommended stronger option.

With the default **25-tap mode**, the final sharpened detail is applied as:

```hlsl
final = c + final_detail * STRENGTH * 3.65;
```

That gives these effective detail multipliers:

- `0.31` → `1.1315×` — recommended default
- `0.32` → `1.1680×` — small step up
- `0.33` → `1.2045×` — stronger, still controlled

Because `STRENGTH` is a direct multiplier, even a `0.01` change can be visible. Relative to `0.31`, `0.32` increases the sharpen-detail contribution by about **3.2%**, while `0.33` increases it by about **6.45%**.

These percentages describe the **sharpening contribution itself**, not a literal percentage increase in perceived image sharpness. The shader still adapts to local detail, edges, noise, dark areas, depth-of-field, and halo protection, so the visible difference will vary from scene to scene.

## Compatibility

- MPC-BE with the DirectX 11 shader path (`Shaders11`)
- Minimum shader profile: `ps_4_0`
- Designed as a **Post-Resize Pixel Shader**
- Tested and tuned with [MPC Video Renderer](https://github.com/Aleksoid1978/VideoRenderer) and its **Super Resolution** resizing path; this is the VSR workflow used during development
- NVIDIA VSR / Super Resolution is **not required** — the shader can still be used as a normal MPC-BE post-resize shader
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
