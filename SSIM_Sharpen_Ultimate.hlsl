// ==================================================================================
// SSIM-Based Detail Enhancement - v15.6 Experimental
// ==================================================================================
// VERSION: 15.6
// DATE: 2026
// AUTHOR: Samer the Croc 🐊
// BASED ON: Shiandow SSIM / igv implementation
// TARGET: MPC-BE + NVIDIA VSR (Video Super Resolution)
// ==================================================================================

// ==================================================================================
// IMPORTANT NOTES & USAGE GUIDE (Essential Only)
// ==================================================================================

// ★ HALO-RESISTANT DESIGN:
// - Detail formula is `c - neighbors` (NOT `c - blurL`) — hard borders, frame edges,
//   and letterbox bars receive strong SSIM-based protection against halo artifacts
//
// ★ HDR PIPELINE:
// - Auto-detect is designed for scRGB linear. Use FORCE_HDR_MODE=2 only when the
//   renderer supplies a linear scRGB HDR signal that auto-detection cannot identify.
//
// ==================================================================================
// $MinimumShaderProfile: ps_4_0
// ==================================================================================

// ===== TUNING GUIDE =====
// The values currently defined below are the recommended defaults for this release.
// ----------------------------------------------------------------------------------
// ★ HDR PANEL-SPECIFIC TUNING ★
// Set this to your display's measured peak brightness in nits for panel-aware scaling.
// Windows scRGB uses 80 nits as the standard SDR reference level (value 1.0).
// For a 497-nit panel: 497 / 80 = 6.21 max structural scale.
// ----------------------------------------------------------------------------------
#define HDR_PEAK_NITS 497.0
#define SDR_REF_NITS 80.0

// ★ HDR MODE OVERRIDE ★
// 0 = Auto-Detect (local peak + frame corners — works for scRGB linear pipelines)
// 1 = Force SDR (all content treated as sRGB, no HDR scaling)
// 2 = Force HDR (content treated as scRGB linear — use for PQ/HLG if auto-detect fails)
// ⚠️ Only use 1 or 2 if auto-detect produces incorrect results for your content/pipeline.
#define FORCE_HDR_MODE 0

// ★ DOF VARIANCE SCALE FOR UPSCALED CONTENT ★
// Sources upscaled from 720p/1080p to 2K have lower inherent pixel variance.
// Scale >1.0 raises evaluated variance (equivalent to lowering effective thresholds)
// to help prevent over-suppression of soft detail.
// 1.0 is neutral; current tuned value is 1.09. Try 1.1-1.3 for heavily upscaled content.
#define DOF_VARIANCE_SCALE 1.09

// SHARPNESS STRENGTH [0.0 - 2.0]
// Master multiplier for extracted detail. Operates on linear-space detail signal.
// 3-Zone DOF reduces effective strength in blurred areas automatically,
// so you may slightly increase this vs v12.0 if you want more overall "pop" on sharp regions.
//
// 0.25 = Ultra-clean (very low halo risk, subtle)
// 0.30 = Balanced (slightly softer)
// 0.31 = ★ Recommended default
// 0.33 = Enhanced (stronger for high-quality 4K sources)
// 0.40 = Strong (noticeable "bite" — watch UI text halos)
// 0.50 = Very strong (max texture pop, artifact-prone on low-bitrate)
// 0.60+ = Aggressive (not recommended)
#define STRENGTH 0.31

// SENSITIVITY [4.0 - 12.0]
// Controls SSIM weight curve (Exponential Decay). Operates on linear luma.
//
// Lower = STRONGER (less selective, more full-frame detail).
// Higher = WEAKER (more selective, only high-contrast edges).
//
// ★ TUNING FOR FOLIAGE/BRANCHES ★ :
// 5.5-6.0 = Maximum texture extraction (can over-sharpen branches/twigs)
// 6.5-7.0 = Balanced (good detail, calmer organic content)
// 7.2-7.5 = Calmer foliage/branches while keeping hard edges sharp
// 8.0+ = Very selective (only text/UI/corners get sharpened)
//
// ⚠️ In 25-Tap mode, high sensitivity + low noise gate = weak/dead shader.
// If you raise this above 7.5, also raise NOISE_GATE to 0.018+.
//
// TUNING TIP: In 25-Tap mode, lowering this extracts deeper texture than raising STRENGTH.
#define SENSITIVITY 6.4

// DETAIL CLAMP [0.00 - 0.30]
// Limits max detail signal magnitude before application. L∞-magnitude soft compression.
//
// 0.08 = Safe (no halos, best for low-bitrate)
// 0.10 = Standard (balanced fallback)
// 0.12 = Conservative (good pop, lower halo risk)
// 0.14-0.15 = Moderate pop
// 0.16 = ★ Recommended default
// 0.18 = Extended (only if SENSITIVITY ≤ 5.5 — otherwise chokes sharpness)
//
// SOFT CLAMP NOTE: Retains ~71% at knee point. No need to 1.5x compensate like v7.1.
#define DETAIL_CLAMP 0.16

// NOISE GATE (ANTI-FLICKER) [0.00 - 0.10]
// Ignores tiny luma differences from VSR temporal noise. Smoothstep transition.
// Value = center of zone (full rejection below 0.5x, full pass above 1.5x).
//
// Operates on perceptual luma for more consistent behavior across brightness.
// 0.008 = Max grain retention (blocks only banding)
// 0.010 = Classic VSR sweet spot
// 0.013 = Balanced
// 0.016 = ★ Recommended default (calms fine branch/twig detail)
// 0.018-0.020 = Clean (use with SENSITIVITY 7.0+ to avoid dead shader)
//
// ⚠️ PAIRING RULE: High SENSITIVITY + Low NOISE_GATE = invisible shader.
// SENS 7.0+ needs NOISE_GATE 0.015+. SENS 5.5 can use 0.010.
#define NOISE_GATE 0.016

// CHROMA DAMPENING [0.0 - 1.0] - Optimized for clean VSR edges
// Controls how much color information is sharpened vs. Luma only.
// 0.0 = Luma Only (Maximum stability, no color fringing)
// 0.25 = Cleaner color transitions, reduced chroma sharpening
// 0.35 = ★ Recommended default / balanced
// 0.5 = Moderate (50% chroma sharpening)
// 1.0 = Full RGB (Maximum color detail, risk of fringing on VSR edges)
#define CHROMA_DAMPENING 0.35

// SAMPLING MODES [0 or 1]
// USE_25TAP = ★ Recommended default: studio-quality 5x5 grid with stronger noise averaging.
// USE_9TAP = High-quality 3x3 grid; use only if 25-tap mode drops frames.
// ⚠️ Do NOT enable both simultaneously — compile-time guard will catch this.
#define USE_25TAP 1
#define USE_9TAP 0

// Compile-time mutual exclusion guard
#if (USE_25TAP == 1) && (USE_9TAP == 1)
#error Cannot enable both USE_25TAP and USE_9TAP simultaneously. Set one to 0.
#endif

// ===== TAP COMPENSATION =====
// These values are tuned for 720p/1080p → 2K
// upscaling to recover perceived detail pop. Quality is priority #1.
#if USE_25TAP == 1
  #define TAP_COMPENSATION 3.65
#elif USE_9TAP == 1
  #define TAP_COMPENSATION 4.15
#else
  #define TAP_COMPENSATION 4.15
#endif

// ==================================================================================
// ANISOTROPIC, FREQUENCY & CHROMA ENHANCEMENTS
// ==================================================================================

// ANISOTROPIC (DIRECTIONAL) SSIM WEIGHTING [0 or 1]
// Modifies neighbor weights based on local gradients to prevent cross-edge blurring.
// NOTE: By detecting the dominant edge axis (horizontal vs vertical), this applies a stricter
// penalty to pixels across the boundary. Prevents texture bleeding and preserves razor-sharp contours.
#define ANISOTROPIC_WEIGHTING 1

// ANISOTROPIC STRENGTH [0.0 - 1.5]
// How strongly to penalize cross-edge neighbors.
// 0.30 = Subtle (safe for lower-resolution source material, minimal banding risk)
// 0.60 = ★ Recommended default / balanced
// 0.85 = Strong (maximum edge preservation, may introduce slightly "painterly" boundaries)
// 1.20 = Extreme (not recommended for daily use)
#define ANISOTROPIC_STRENGTH 0.60

// FREQUENCY-SEPARATED DETAIL CLAMPING (WAVELET-LITE) [0 or 1]
// Subtly separates high-frequency (HF) from mid-frequency (MF) detail before clamping.
// NOTE: HF represents sharp micro-edges and noise/grain (highly prone to ringing/flicker).
// MF represents broader local contrast and texture (which gives the image 3D "pop").
// This separation allows us to push mid-texture harder without amplifying VSR grain.
#define USE_FREQ_CLAMP 1

// HF CLAMP RATIO [0.50 - 1.00]
// Multiplier for the master DETAIL_CLAMP applied to High Frequencies. (Lower = Stricter)
// 0.70 = Aggressive grain and ringing suppression (good for heavily compressed web video)
// 0.80 = Slightly stricter HF clamp
// 0.82 = ★ Recommended default
// 0.85 = Looser HF clamp (more fine texture)
// 1.00 = Neutral (behaves exactly like legacy v13.0 clamp)
#define FREQ_CLAMP_HF_RATIO 0.82

// MF CLAMP RATIO [1.00 - 1.50]
// Multiplier for the master DETAIL_CLAMP applied to Mid Frequencies. (Higher = Looser)
// 1.00 = Neutral (behaves exactly like legacy v13.0 clamp)
// 1.15 = ★ Recommended default (natural depth and pop)
// 1.30 = Strong texture enhancement (excellent for high-bitrate 4K movies/gaming)
#define FREQ_CLAMP_MF_RATIO 1.15

// LUMA-DEPENDENT CHROMA DAMPENING [0 or 1]
// Dynamically reduces chroma sharpening in extreme shadows and highlights
// where color noise is highly visible, preserving vibrant midtones.
#define USE_LUMA_CHROMA_DAMPENING 1
#define CHROMA_EXTREME_LUMA_MULTIPLIER 0.25 // Reduces chroma detail to 25% at extreme lumas

// ==================================================================================

// SOFT DETAIL CLAMP [0 or 1] (Fallback if USE_FREQ_CLAMP == 0)
// 0 = Hard Clamp | 1 = ★ Recommended default: Soft Compression (L∞ norm soft clamp curve)
#define USE_SOFT_CLAMP 1

// TRUE ANTI-RINGING (LOCAL MIN/MAX) [0 or 1]
// WARNING: KEEP THIS AT 0 FOR VSR.
#define USE_ANTI_RINGING 0
#define ANTI_RINGING_OVERSHOOT 0.05

// EDGE-AWARE DAMPENING [White Line / Halo Prevention]
// Range: 0.0-1.0 (higher = MORE suppression on bright hard edges).
// 0.0 = Off | 0.75 = Moderate | 0.80 = ★ Recommended default | 1.0 = Maximum
#define USE_EDGE_DAMPEN 1
#define EDGE_DAMPEN_STRENGTH 0.80

// WHITE LINE THRESHOLD [0.70 - 0.98]
// Defines what PERCEPTUAL brightness triggers white-line halo protection.
// 0.93 = ★ Recommended default (pure whites/speculars only)
#define WHITE_LINE_THRESHOLD 0.93

// DARK AREA PROTECTION
// Reduces sharpening in very dark areas where noise dominates signal.
#define DARK_PROTECT_LOW 0.02
#define DARK_PROTECT_HIGH 0.10

// CENTER PIXEL ANCHOR WEIGHT [0.0 - 3.0]
#define CENTER_ANCHOR_WEIGHT 1.0

// ==================================================================================
// EDGE RAMP & CASCADE CONSTANTS
// ==================================================================================
// Edge ramp reduced for smoother real-world texture response (was 0.35)
#define EDGE_RAMP_CONSTANT 0.20

// Cascade correction now applies to chroma protection as well
#define CASCADE_CORRECTION 0.75

// ==================================================================================
// 3-ZONE ASYMMETRIC EDGE-PRESERVE DOF PARAMETERS
// ==================================================================================
// 3-Zone DOF MASTER SWITCH [0 or 1]
#define USE_3ZONE_DOF 1

// ---- ZONE BOUNDARY THRESHOLDS (Perceptual Luma Variance) ----
#define DOF_ZONE_LOW 0.004
#define DOF_ZONE_MID 0.012
#define DOF_ZONE_HIGH 0.020

// ---- SUPPRESSION STRENGTHS PER ZONE ----
#define DOF_FLAT_SUPPRESSION 0.30
#define DOF_TRANSITION_BASE_SUPPRESSION 0.40

// ---- ASYMMETRIC EDGE DETECTION PARAMETERS ----
#define DOF_EDGE_DETECT_THRESHOLD 0.05
#define DOF_EDGE_PRESERVE_STRENGTH 0.85
#define DOF_MIN_SHARP_PRESERVE 0.05

// ==================================================================================
// LEGACY DOF PARAMETERS
// ==================================================================================
#define USE_LEGACY_DOF_AWARENESS 0 // Set to 1 ONLY if reverting to v12.0
#define DOF_VARIANCE_THRESHOLD 0.014
#define DOF_SUPPRESSION_STRENGTH 0.30
#define DOF_MIN_EDGE_PRESERVE 0.03

// ==================================================================================
// COMPILE-TIME CONFIGURATION VALIDATION
// ==================================================================================
#if (FORCE_HDR_MODE < 0) || (FORCE_HDR_MODE > 2)
#error FORCE_HDR_MODE must be 0 (Auto), 1 (SDR), or 2 (HDR).
#endif

#if ((USE_25TAP != 0) && (USE_25TAP != 1)) || ((USE_9TAP != 0) && (USE_9TAP != 1))
#error USE_25TAP and USE_9TAP must each be 0 or 1.
#endif

#if ((ANISOTROPIC_WEIGHTING != 0) && (ANISOTROPIC_WEIGHTING != 1)) || \
    ((USE_FREQ_CLAMP != 0) && (USE_FREQ_CLAMP != 1)) || \
    ((USE_LUMA_CHROMA_DAMPENING != 0) && (USE_LUMA_CHROMA_DAMPENING != 1))
#error ANISOTROPIC_WEIGHTING, USE_FREQ_CLAMP, and USE_LUMA_CHROMA_DAMPENING must be 0 or 1.
#endif

#if ((USE_SOFT_CLAMP != 0) && (USE_SOFT_CLAMP != 1)) || \
    ((USE_ANTI_RINGING != 0) && (USE_ANTI_RINGING != 1)) || \
    ((USE_EDGE_DAMPEN != 0) && (USE_EDGE_DAMPEN != 1))
#error USE_SOFT_CLAMP, USE_ANTI_RINGING, and USE_EDGE_DAMPEN must be 0 or 1.
#endif

#if ((USE_3ZONE_DOF != 0) && (USE_3ZONE_DOF != 1)) || \
    ((USE_LEGACY_DOF_AWARENESS != 0) && (USE_LEGACY_DOF_AWARENESS != 1))
#error USE_3ZONE_DOF and USE_LEGACY_DOF_AWARENESS must each be 0 or 1.
#endif

#if (USE_3ZONE_DOF == 1) && (USE_LEGACY_DOF_AWARENESS == 1)
#error USE_3ZONE_DOF and USE_LEGACY_DOF_AWARENESS cannot both be enabled.
#endif

// ===== RESOURCES =====
Texture2D tex : register(t0);
SamplerState samp : register(s0);
cbuffer PS_CONSTANTS : register(b0) {
    float px;
    float py;
    float2 wh;
    uint counter;
    float clock;
};

// ===== QUALITY-SAFE INTERNAL CONSTANTS =====
// SSIM spatial and DOF edge weights are intentionally independent.
// User tuning defines above remain unchanged.
static const float SSIM_EXP2_SCALE = 1.44269504089;      // log2(e)
static const float SSIM_SPATIAL_W_DIAGONAL = 0.70710678; // 1/sqrt(2), unchanged
static const float DOF_EDGE_W_CARDINAL = 1.00000000;
static const float DOF_EDGE_W_DIAGONAL = 0.70710678;    // 1/sqrt(2), retained for quality
// Numerical stabilizer for orientation-only anisotropic splitting.
// This is an internal safety constant, not a user tuning control.
static const float ANISO_DIRECTION_EPS = 0.0001;

// ===== HELPER FUNCTIONS =====
// Per-channel sRGB selection uses step()/lerp(); HDR early returns remain.

float3 ToLinear(float3 c, bool isHDR) {
    if (isHDR) return c;
    // Branchless sRGB→linear using step/lerp
    float3 mask = step(float3(0.04045, 0.04045, 0.04045), c);
    float3 lo = c / 12.92;
    float3 hi = pow(max((c + 0.055) / 1.055, 0.0), 2.4);
    return lerp(lo, hi, mask);
}

float3 ToGamma(float3 c, bool isHDR) {
    if (isHDR) return c;
    // Branchless linear→sRGB using step/lerp
    float3 mask = step(float3(0.0031308, 0.0031308, 0.0031308), c);
    float3 lo = c * 12.92;
    float3 hi = 1.055 * pow(max(c, 0.0), 1.0 / 2.4) - 0.055;
    return lerp(lo, hi, mask);
}

float LinearToPerceptualLuma(float Y_linear) {
    // Per-channel gamma approximation using step/lerp.
    // Clamp only the fractional-pow input; the low branch still preserves
    // negative scRGB/out-of-gamut luma without risking NaN propagation from pow().
    float mask = step(0.0031308, Y_linear);
    float lo = Y_linear * 12.92;
    float hi = 1.055 * pow(max(Y_linear, 0.0), 1.0 / 2.4) - 0.055;
    return lerp(lo, hi, mask);
}

static const float3 LUMA_WEIGHTS = float3(0.2126, 0.7152, 0.0722);

// Accepts pre-computed perceptual luma to avoid redundant pow() calls
float GetSSIMWeight(float Y_c_lin, float Y_n_lin, float Y_c_perc, float Y_n_perc, float eff_noise_gate_perceptual, float aniso_mult) {
    float diff = abs(Y_c_lin - Y_n_lin);
    float diff_perceptual = abs(Y_c_perc - Y_n_perc);

    float gate_lo = eff_noise_gate_perceptual * 0.5;
    float gate_hi = max(eff_noise_gate_perceptual * 1.5, gate_lo + 0.0001);
    float gate_mask = smoothstep(gate_lo, gate_hi, diff_perceptual);

    // Apply gate mask and anisotropic directional modifier
    diff *= gate_mask * aniso_mult;
    return exp2(-diff * SENSITIVITY * SSIM_EXP2_SCALE);
}

// ==================================================================================
// LEGACY: DOF / Blur Region Detection
// ==================================================================================
float CalculateDOFSuppression(
    float Y_c_g,
    float Y_n1_g, float Y_n2_g, float Y_n3_g, float Y_n4_g,
    float Y_n5_g, float Y_n6_g, float Y_n7_g, float Y_n8_g
) {
    #if USE_LEGACY_DOF_AWARENESS == 0
    return 1.0;
    #endif

    float sum = Y_c_g + Y_n1_g + Y_n2_g + Y_n3_g + Y_n4_g;
    int count = 5;

    #if USE_9TAP == 1 || USE_25TAP == 1
    sum += Y_n5_g + Y_n6_g + Y_n7_g + Y_n8_g;
    count += 4;
    #endif

    float mean = sum / count;
    float sq_diff_sum = 0.0;
    sq_diff_sum += (Y_c_g - mean) * (Y_c_g - mean);
    sq_diff_sum += (Y_n1_g - mean) * (Y_n1_g - mean);
    sq_diff_sum += (Y_n2_g - mean) * (Y_n2_g - mean);
    sq_diff_sum += (Y_n3_g - mean) * (Y_n3_g - mean);
    sq_diff_sum += (Y_n4_g - mean) * (Y_n4_g - mean);

    #if USE_9TAP == 1 || USE_25TAP == 1
    sq_diff_sum += (Y_n5_g - mean) * (Y_n5_g - mean);
    sq_diff_sum += (Y_n6_g - mean) * (Y_n6_g - mean);
    sq_diff_sum += (Y_n7_g - mean) * (Y_n7_g - mean);
    sq_diff_sum += (Y_n8_g - mean) * (Y_n8_g - mean);
    #endif

    float variance = sq_diff_sum / count;

    float dof_lo = DOF_VARIANCE_THRESHOLD * 0.5;
    float dof_hi = max(DOF_VARIANCE_THRESHOLD * 1.5, dof_lo + 0.0001);
    float sharpness_factor = smoothstep(dof_lo, dof_hi, variance);

    float final_factor = lerp(
        1.0 - DOF_SUPPRESSION_STRENGTH,
        1.0,
        sharpness_factor
    );
    return max(final_factor, DOF_MIN_EDGE_PRESERVE);
}

// ==================================================================================
// ★ v13.0 NEW: 3-Zone Asymmetric Edge-Preserve DOF Calculation
// v14 FIX: Zone1 factor corrected — asymmetric edge detection now active
// v14.2 FIX: Restored conservative asymmetric logic, removed [unroll]
// v14.4 FIX: Manually unrolled code to resolve fxc array compilation issues
// v14.5 FIX: Added HDR scaling and full 25-tap variance
// v15 FIX: Asymmetric edge detection now uses ALL available neighbors (not just inner 8)
// v15.4 NOTE: Per-neighbor edge thresholds use step(); zone-level branches remain
// intentionally to skip unnecessary asymmetric evidence work.
// ==================================================================================
float Calculate3ZoneAsymmetricDOF(
    float Y_c_g,
    float Y_n1_g, float Y_n2_g, float Y_n3_g, float Y_n4_g,
    float Y_n5_g, float Y_n6_g, float Y_n7_g, float Y_n8_g,
    float maxLumaCapPerceptual
#if USE_25TAP == 1
   , float Y_n9_g, float Y_n10_g, float Y_n11_g, float Y_n12_g,
    float Y_n13_g, float Y_n14_g, float Y_n15_g, float Y_n16_g,
    float Y_n17_g, float Y_n18_g, float Y_n19_g, float Y_n20_g,
    float Y_n21_g, float Y_n22_g, float Y_n23_g, float Y_n24_g
#endif
) {
    #if USE_3ZONE_DOF == 0
    return 1.0;
    #endif

    // v15.2: Apply DOF_VARIANCE_SCALE for upscaled content
    float varianceScale = DOF_VARIANCE_SCALE;

    // v15.3: One-pass E[x²] - E[x]² variance. Same model, lower live register pressure.
    float sum = Y_c_g + Y_n1_g + Y_n2_g + Y_n3_g + Y_n4_g;
    float sumSq = Y_c_g * Y_c_g +
                  Y_n1_g * Y_n1_g + Y_n2_g * Y_n2_g +
                  Y_n3_g * Y_n3_g + Y_n4_g * Y_n4_g;
    float count = 5.0;

    #if USE_9TAP == 1 || USE_25TAP == 1
    sum += Y_n5_g + Y_n6_g + Y_n7_g + Y_n8_g;
    sumSq += Y_n5_g * Y_n5_g + Y_n6_g * Y_n6_g +
             Y_n7_g * Y_n7_g + Y_n8_g * Y_n8_g;
    count += 4.0;
    #endif

#if USE_25TAP == 1
    sum += Y_n9_g + Y_n10_g + Y_n11_g + Y_n12_g;
    sum += Y_n13_g + Y_n14_g + Y_n15_g + Y_n16_g;
    sum += Y_n17_g + Y_n18_g + Y_n19_g + Y_n20_g;
    sum += Y_n21_g + Y_n22_g + Y_n23_g + Y_n24_g;

    sumSq += Y_n9_g * Y_n9_g + Y_n10_g * Y_n10_g +
             Y_n11_g * Y_n11_g + Y_n12_g * Y_n12_g;
    sumSq += Y_n13_g * Y_n13_g + Y_n14_g * Y_n14_g +
             Y_n15_g * Y_n15_g + Y_n16_g * Y_n16_g;
    sumSq += Y_n17_g * Y_n17_g + Y_n18_g * Y_n18_g +
             Y_n19_g * Y_n19_g + Y_n20_g * Y_n20_g;
    sumSq += Y_n21_g * Y_n21_g + Y_n22_g * Y_n22_g +
             Y_n23_g * Y_n23_g + Y_n24_g * Y_n24_g;
    count += 16.0;
#endif

    float mean = sum / count;
    float variance = max((sumSq / count) - (mean * mean), 0.0) * varianceScale;

    // v14.5 FIX: Scale DOF thresholds to perceptual HDR range
    float zoneScale = maxLumaCapPerceptual * maxLumaCapPerceptual;
    float zLow = DOF_ZONE_LOW * zoneScale;
    float zMid = DOF_ZONE_MID * zoneScale;
    float zHigh = DOF_ZONE_HIGH * zoneScale;
    float edgeThresh = DOF_EDGE_DETECT_THRESHOLD * maxLumaCapPerceptual;

    // v14 FIX: zone1_factor must be HIGH at LOW variance (flat/blur zone).
    float zone1_factor = 1.0 - smoothstep(zLow * 0.5, zLow, variance);
    float zone3_factor = smoothstep(zMid, zHigh, variance);
    float zone2_factor = (1.0 - zone1_factor) * (1.0 - zone3_factor);

    // v15.2: Branchless zone3 check using step()
    float zone3_active = step(0.95, zone3_factor);
    // v15.3: Unused `dof_return` temporary removed; final lerp below preserves zone3 behavior.

    // If zone3 not active, compute asymmetric edge detection
    float flat_suppression = DOF_FLAT_SUPPRESSION;
    float transition_suppression = DOF_TRANSITION_BASE_SUPPRESSION;

    // v15.4: Only Zone 2 pixels whose final result is not forced to Zone 3
    // evaluate the expensive asymmetric edge-evidence block.
    float zone2_active = step(0.01, zone2_factor);
    zone2_active *= (1.0 - zone3_active);
    
    if (zone2_active > 0.5) {
        float sharp_side_evidence = 0.0;
        float blur_side_evidence = 0.0;

        // === Cardinal neighbors (1px) — manually unrolled ===
        // v15.2: Branchless edge detection using step()
        float d0 = Y_c_g - Y_n1_g;
        float a0 = abs(d0);
        float edge0 = step(edgeThresh, a0);
        sharp_side_evidence += edge0 * step(0.0, d0) * a0 * DOF_EDGE_W_CARDINAL;
        blur_side_evidence += edge0 * step(0.0, -d0) * a0 * DOF_EDGE_W_CARDINAL;

        float d1 = Y_c_g - Y_n2_g;
        float a1 = abs(d1);
        float edge1 = step(edgeThresh, a1);
        sharp_side_evidence += edge1 * step(0.0, d1) * a1 * DOF_EDGE_W_CARDINAL;
        blur_side_evidence += edge1 * step(0.0, -d1) * a1 * DOF_EDGE_W_CARDINAL;

        float d2 = Y_c_g - Y_n3_g;
        float a2 = abs(d2);
        float edge2 = step(edgeThresh, a2);
        sharp_side_evidence += edge2 * step(0.0, d2) * a2 * DOF_EDGE_W_CARDINAL;
        blur_side_evidence += edge2 * step(0.0, -d2) * a2 * DOF_EDGE_W_CARDINAL;

        float d3 = Y_c_g - Y_n4_g;
        float a3 = abs(d3);
        float edge3 = step(edgeThresh, a3);
        sharp_side_evidence += edge3 * step(0.0, d3) * a3 * DOF_EDGE_W_CARDINAL;
        blur_side_evidence += edge3 * step(0.0, -d3) * a3 * DOF_EDGE_W_CARDINAL;

        #if USE_9TAP == 1 || USE_25TAP == 1
        // === Diagonal neighbors (1px, inverse-distance weight 0.70710678) ===
        float dd0 = Y_c_g - Y_n5_g;
        float da0 = abs(dd0);
        float edge5 = step(edgeThresh, da0);
        sharp_side_evidence += edge5 * step(0.0, dd0) * da0 * DOF_EDGE_W_DIAGONAL;
        blur_side_evidence += edge5 * step(0.0, -dd0) * da0 * DOF_EDGE_W_DIAGONAL;

        float dd1 = Y_c_g - Y_n6_g;
        float da1 = abs(dd1);
        float edge6 = step(edgeThresh, da1);
        sharp_side_evidence += edge6 * step(0.0, dd1) * da1 * DOF_EDGE_W_DIAGONAL;
        blur_side_evidence += edge6 * step(0.0, -dd1) * da1 * DOF_EDGE_W_DIAGONAL;

        float dd2 = Y_c_g - Y_n7_g;
        float da2 = abs(dd2);
        float edge7 = step(edgeThresh, da2);
        sharp_side_evidence += edge7 * step(0.0, dd2) * da2 * DOF_EDGE_W_DIAGONAL;
        blur_side_evidence += edge7 * step(0.0, -dd2) * da2 * DOF_EDGE_W_DIAGONAL;

        float dd3 = Y_c_g - Y_n8_g;
        float da3 = abs(dd3);
        float edge8 = step(edgeThresh, da3);
        sharp_side_evidence += edge8 * step(0.0, dd3) * da3 * DOF_EDGE_W_DIAGONAL;
        blur_side_evidence += edge8 * step(0.0, -dd3) * da3 * DOF_EDGE_W_DIAGONAL;
        #endif

        // v15 FIX + v15.2: Extended asymmetric edge detection to outer ring neighbors.
        // v15.3 FIX: DOF edge evidence documents the retained inverse-distance style.
        // Inner diagonals keep 1/sqrt(2) weighting; outer-ring code remains unchanged
        // to avoid quality/tuning shifts from v15.2 behavior.
        #if USE_25TAP == 1
        // === 2-pixel cardinal neighbors (retained v15.2 weight 1.0; quality-preserving) ===
        float dc0 = Y_c_g - Y_n9_g;
        float adc0 = abs(dc0);
        float edge9 = step(edgeThresh, adc0);
        sharp_side_evidence += edge9 * step(0.0, dc0) * adc0;
        blur_side_evidence += edge9 * step(0.0, -dc0) * adc0;

        float dc1 = Y_c_g - Y_n10_g;
        float adc1 = abs(dc1);
        float edge10 = step(edgeThresh, adc1);
        sharp_side_evidence += edge10 * step(0.0, dc1) * adc1;
        blur_side_evidence += edge10 * step(0.0, -dc1) * adc1;

        float dc2 = Y_c_g - Y_n11_g;
        float adc2 = abs(dc2);
        float edge11 = step(edgeThresh, adc2);
        sharp_side_evidence += edge11 * step(0.0, dc2) * adc2;
        blur_side_evidence += edge11 * step(0.0, -dc2) * adc2;

        float dc3 = Y_c_g - Y_n12_g;
        float adc3 = abs(dc3);
        float edge12 = step(edgeThresh, adc3);
        sharp_side_evidence += edge12 * step(0.0, dc3) * adc3;
        blur_side_evidence += edge12 * step(0.0, -dc3) * adc3;

        // === 2-pixel diagonal neighbors (retained v15.2 weight 1.0; quality-preserving) ===
        float ddc0 = Y_c_g - Y_n13_g;
        float addc0 = abs(ddc0);
        float edge13 = step(edgeThresh, addc0);
        sharp_side_evidence += edge13 * step(0.0, ddc0) * addc0;
        blur_side_evidence += edge13 * step(0.0, -ddc0) * addc0;

        float ddc1 = Y_c_g - Y_n14_g;
        float addc1 = abs(ddc1);
        float edge14 = step(edgeThresh, addc1);
        sharp_side_evidence += edge14 * step(0.0, ddc1) * addc1;
        blur_side_evidence += edge14 * step(0.0, -ddc1) * addc1;

        float ddc2 = Y_c_g - Y_n15_g;
        float addc2 = abs(ddc2);
        float edge15 = step(edgeThresh, addc2);
        sharp_side_evidence += edge15 * step(0.0, ddc2) * addc2;
        blur_side_evidence += edge15 * step(0.0, -ddc2) * addc2;

        float ddc3 = Y_c_g - Y_n16_g;
        float addc3 = abs(ddc3);
        float edge16 = step(edgeThresh, addc3);
        sharp_side_evidence += edge16 * step(0.0, ddc3) * addc3;
        blur_side_evidence += edge16 * step(0.0, -ddc3) * addc3;

        // === Knight's move neighbors (retained v15.2 weight 1.0; quality-preserving) ===
        float dk0 = Y_c_g - Y_n17_g;
        float adk0 = abs(dk0);
        float edge17 = step(edgeThresh, adk0);
        sharp_side_evidence += edge17 * step(0.0, dk0) * adk0;
        blur_side_evidence += edge17 * step(0.0, -dk0) * adk0;

        float dk1 = Y_c_g - Y_n18_g;
        float adk1 = abs(dk1);
        float edge18 = step(edgeThresh, adk1);
        sharp_side_evidence += edge18 * step(0.0, dk1) * adk1;
        blur_side_evidence += edge18 * step(0.0, -dk1) * adk1;

        float dk2 = Y_c_g - Y_n19_g;
        float adk2 = abs(dk2);
        float edge19 = step(edgeThresh, adk2);
        sharp_side_evidence += edge19 * step(0.0, dk2) * adk2;
        blur_side_evidence += edge19 * step(0.0, -dk2) * adk2;

        float dk3 = Y_c_g - Y_n20_g;
        float adk3 = abs(dk3);
        float edge20 = step(edgeThresh, adk3);
        sharp_side_evidence += edge20 * step(0.0, dk3) * adk3;
        blur_side_evidence += edge20 * step(0.0, -dk3) * adk3;

        float dk4 = Y_c_g - Y_n21_g;
        float adk4 = abs(dk4);
        float edge21 = step(edgeThresh, adk4);
        sharp_side_evidence += edge21 * step(0.0, dk4) * adk4;
        blur_side_evidence += edge21 * step(0.0, -dk4) * adk4;

        float dk5 = Y_c_g - Y_n22_g;
        float adk5 = abs(dk5);
        float edge22 = step(edgeThresh, adk5);
        sharp_side_evidence += edge22 * step(0.0, dk5) * adk5;
        blur_side_evidence += edge22 * step(0.0, -dk5) * adk5;

        float dk6 = Y_c_g - Y_n23_g;
        float adk6 = abs(dk6);
        float edge23 = step(edgeThresh, adk6);
        sharp_side_evidence += edge23 * step(0.0, dk6) * adk6;
        blur_side_evidence += edge23 * step(0.0, -dk6) * adk6;

        float dk7 = Y_c_g - Y_n24_g;
        float adk7 = abs(dk7);
        float edge24 = step(edgeThresh, adk7);
        sharp_side_evidence += edge24 * step(0.0, dk7) * adk7;
        blur_side_evidence += edge24 * step(0.0, -dk7) * adk7;
        #endif // USE_25TAP

        float total_evidence = sharp_side_evidence + blur_side_evidence;
        // v15.4: A detected edge always contributes positive evidence because
        // edgeThresh is positive, so total_evidence exactly replaces edge_count.
        if (total_evidence > 0.0) {
            // v14.2 FIX: Guard against divide-by-zero
            float sharp_ratio = sharp_side_evidence / max(total_evidence, 0.0001);
            // v14.2 FIX: Restored v14 conservative logic — factor stays in [0, 1]
            float asymmetric_modifier = 1.0 - (sharp_ratio * DOF_EDGE_PRESERVE_STRENGTH);
            transition_suppression *= asymmetric_modifier;
        }
    }

    float raw_suppression = (flat_suppression * zone1_factor) +
                            (transition_suppression * zone2_factor);
    float doffactor = 1.0 - raw_suppression;
    doffactor = max(doffactor, DOF_MIN_SHARP_PRESERVE);

    // v15.2: Branchless return selection
    return lerp(doffactor, 1.0, zone3_active);
}

// ===== MAIN SHADER =====
float4 main(float4 pos : SV_POSITION, float2 coord : TEXCOORD) : SV_Target {
    // -------------------------------------------------------------------------
    // 1. SAMPLE PIXELS (RAW)
    // -------------------------------------------------------------------------
    float3 c = tex.Sample(samp, coord).rgb;
    float3 n1 = tex.Sample(samp, coord + float2( 0.0, -py)).rgb;
    float3 n2 = tex.Sample(samp, coord + float2(-px, 0.0)).rgb;
    float3 n3 = tex.Sample(samp, coord + float2( px, 0.0)).rgb;
    float3 n4 = tex.Sample(samp, coord + float2( 0.0, py)).rgb;

    #if USE_9TAP == 1 || USE_25TAP == 1
    float3 n5 = tex.Sample(samp, coord + float2(-px, -py)).rgb;
    float3 n6 = tex.Sample(samp, coord + float2( px, -py)).rgb;
    float3 n7 = tex.Sample(samp, coord + float2(-px, py)).rgb;
    float3 n8 = tex.Sample(samp, coord + float2( px, py)).rgb;
    #endif

    // -------------------------------------------------------------------------
    // 2. OUTER RING (2 Pixel Radius - v4.0 25-Tap Expansion)
    // -------------------------------------------------------------------------
    #if USE_25TAP == 1
    float3 n9 = tex.Sample(samp, coord + float2( 0.0, -py * 2.0)).rgb;
    float3 n10 = tex.Sample(samp, coord + float2(-px * 2.0, 0.0 )).rgb;
    float3 n11 = tex.Sample(samp, coord + float2( px * 2.0, 0.0 )).rgb;
    float3 n12 = tex.Sample(samp, coord + float2( 0.0, py * 2.0)).rgb;
    float3 n13 = tex.Sample(samp, coord + float2(-px * 2.0, -py * 2.0)).rgb;
    float3 n14 = tex.Sample(samp, coord + float2( px * 2.0, -py * 2.0)).rgb;
    float3 n15 = tex.Sample(samp, coord + float2(-px * 2.0, py * 2.0)).rgb;
    float3 n16 = tex.Sample(samp, coord + float2( px * 2.0, py * 2.0)).rgb;
    float3 n17 = tex.Sample(samp, coord + float2(-px * 1.0, -py * 2.0)).rgb;
    float3 n18 = tex.Sample(samp, coord + float2( px * 1.0, -py * 2.0)).rgb;
    float3 n19 = tex.Sample(samp, coord + float2(-px * 2.0, -py * 1.0)).rgb;
    float3 n20 = tex.Sample(samp, coord + float2( px * 2.0, -py * 1.0)).rgb;
    float3 n21 = tex.Sample(samp, coord + float2(-px * 2.0, py * 1.0)).rgb;
    float3 n22 = tex.Sample(samp, coord + float2( px * 2.0, py * 1.0)).rgb;
    float3 n23 = tex.Sample(samp, coord + float2(-px * 1.0, py * 2.0)).rgb;
    float3 n24 = tex.Sample(samp, coord + float2( px * 1.0, py * 2.0)).rgb;
    #endif

    // -------------------------------------------------------------------------
    // 2.5. HDR/SDR AUTO-DETECTION & DYNAMIC PANEL CLAMP
    // -------------------------------------------------------------------------
    // v14.2: No max3() — inline max() used instead
    float localPeak = max(c.r, max(c.g, c.b));
    localPeak = max(localPeak, max(max(n1.r, max(n1.g, n1.b)), max(n2.r, max(n2.g, n2.b))));
    localPeak = max(localPeak, max(max(n3.r, max(n3.g, n3.b)), max(n4.r, max(n4.g, n4.b))));

    #if USE_9TAP == 1 || USE_25TAP == 1
    localPeak = max(localPeak, max(max(n5.r, max(n5.g, n5.b)), max(n6.r, max(n6.g, n6.b))));
    localPeak = max(localPeak, max(max(n7.r, max(n7.g, n7.b)), max(n8.r, max(n8.g, n8.b))));
    #endif

    #if USE_25TAP == 1
    localPeak = max(localPeak, max(max(n9.r, max(n9.g, n9.b)), max(n10.r, max(n10.g, n10.b))));
    localPeak = max(localPeak, max(max(n11.r, max(n11.g, n11.b)), max(n12.r, max(n12.g, n12.b))));
    localPeak = max(localPeak, max(max(n13.r, max(n13.g, n13.b)), max(n14.r, max(n14.g, n14.b))));
    localPeak = max(localPeak, max(max(n15.r, max(n15.g, n15.b)), max(n16.r, max(n16.g, n16.b))));
    localPeak = max(localPeak, max(max(n17.r, max(n17.g, n17.b)), max(n18.r, max(n18.g, n18.b))));
    localPeak = max(localPeak, max(max(n19.r, max(n19.g, n19.b)), max(n20.r, max(n20.g, n20.b))));
    localPeak = max(localPeak, max(max(n21.r, max(n21.g, n21.b)), max(n22.r, max(n22.g, n22.b))));
    localPeak = max(localPeak, max(max(n23.r, max(n23.g, n23.b)), max(n24.r, max(n24.g, n24.b))));
    #endif

    float max_hdr_scale = HDR_PEAK_NITS / SDR_REF_NITS;

    // v15.4 CLARIFICATION: Auto mode remains pixel-local, supplemented by two fixed
    // frame-corner samples. This improves stability but is not a true frame-wide reduction.
    // FORCE_HDR_MODE remains available if dark HDR content cannot be identified reliably.
    #if FORCE_HDR_MODE == 2
        bool isHDR = true;
        float hdrScale = max_hdr_scale;
    #elif FORCE_HDR_MODE == 1
        bool isHDR = false;
        float hdrScale = 1.0;
    #else
        // Auto-detect: check frame corners for HDR signal (2 extra texture fetches).
        // v15.3: Kept for quality/stability; compile-time FORCE_HDR_MODE 1/2 skips this path.
        float3 cornerA = tex.Sample(samp, float2(0.02, 0.02)).rgb;
        float3 cornerB = tex.Sample(samp, float2(0.98, 0.98)).rgb;
        float cornerPeak = max(max(cornerA.r, max(cornerA.g, cornerA.b)),
                               max(cornerB.r, max(cornerB.g, cornerB.b)));
        float detectPeak = max(localPeak, cornerPeak);
        float hdrScale = min(max(1.0, detectPeak), max_hdr_scale);
        bool isHDR = hdrScale > 1.05;
    #endif

    // v14 FIX: Perceptual thresholds properly capped for HDR vs SDR
    float maxLumaCapPerceptual = isHDR? LinearToPerceptualLuma(hdrScale) : 1.0;

    // v14.4 FIX: Noise gate scaled in perceptual space (NOISE_GATE is perceptual)
    float eff_noise_gate_perceptual = NOISE_GATE * maxLumaCapPerceptual;

    // v15 FIX: eff_detail_clamp moved after linear conversion — now uses Y_c
    // (Was DETAIL_CLAMP * hdrScale here, which over-clamped dark pixels near HDR highlights)

    // v14 FIX: Thresholds now correctly bound to perceptual luma space
    float eff_white_threshold = WHITE_LINE_THRESHOLD * maxLumaCapPerceptual;
    float eff_dark_low = DARK_PROTECT_LOW * maxLumaCapPerceptual;
    float eff_dark_high = DARK_PROTECT_HIGH * maxLumaCapPerceptual;

    // -------------------------------------------------------------------------
    // 2.6. LINEAR LIGHT CONVERSION & DUAL-LUMA CACHE
    // -------------------------------------------------------------------------
    c = ToLinear(c, isHDR);
    n1 = ToLinear(n1, isHDR); n2 = ToLinear(n2, isHDR);
    n3 = ToLinear(n3, isHDR); n4 = ToLinear(n4, isHDR);

    float Y_c = dot(c, LUMA_WEIGHTS);
    float Y_n1 = dot(n1, LUMA_WEIGHTS);
    float Y_n2 = dot(n2, LUMA_WEIGHTS);
    float Y_n3 = dot(n3, LUMA_WEIGHTS);
    float Y_n4 = dot(n4, LUMA_WEIGHTS);

    #if USE_9TAP == 1 || USE_25TAP == 1
    n5 = ToLinear(n5, isHDR); n6 = ToLinear(n6, isHDR);
    n7 = ToLinear(n7, isHDR); n8 = ToLinear(n8, isHDR);
    float Y_n5 = dot(n5, LUMA_WEIGHTS);
    float Y_n6 = dot(n6, LUMA_WEIGHTS);
    float Y_n7 = dot(n7, LUMA_WEIGHTS);
    float Y_n8 = dot(n8, LUMA_WEIGHTS);
    #endif

    #if USE_25TAP == 1
    n9 = ToLinear(n9, isHDR); n10 = ToLinear(n10, isHDR);
    n11 = ToLinear(n11, isHDR); n12 = ToLinear(n12, isHDR);
    n13 = ToLinear(n13, isHDR); n14 = ToLinear(n14, isHDR);
    n15 = ToLinear(n15, isHDR); n16 = ToLinear(n16, isHDR);
    n17 = ToLinear(n17, isHDR); n18 = ToLinear(n18, isHDR);
    n19 = ToLinear(n19, isHDR); n20 = ToLinear(n20, isHDR);
    n21 = ToLinear(n21, isHDR); n22 = ToLinear(n22, isHDR);
    n23 = ToLinear(n23, isHDR); n24 = ToLinear(n24, isHDR);

    float Y_n9 = dot(n9, LUMA_WEIGHTS); float Y_n10 = dot(n10, LUMA_WEIGHTS);
    float Y_n11 = dot(n11, LUMA_WEIGHTS); float Y_n12 = dot(n12, LUMA_WEIGHTS);
    float Y_n13 = dot(n13, LUMA_WEIGHTS); float Y_n14 = dot(n14, LUMA_WEIGHTS);
    float Y_n15 = dot(n15, LUMA_WEIGHTS); float Y_n16 = dot(n16, LUMA_WEIGHTS);
    float Y_n17 = dot(n17, LUMA_WEIGHTS); float Y_n18 = dot(n18, LUMA_WEIGHTS);
    float Y_n19 = dot(n19, LUMA_WEIGHTS); float Y_n20 = dot(n20, LUMA_WEIGHTS);
    float Y_n21 = dot(n21, LUMA_WEIGHTS); float Y_n22 = dot(n22, LUMA_WEIGHTS);
    float Y_n23 = dot(n23, LUMA_WEIGHTS); float Y_n24 = dot(n24, LUMA_WEIGHTS);
    #endif

    float Y_c_g = LinearToPerceptualLuma(Y_c);
    float Y_n1_g = LinearToPerceptualLuma(Y_n1);
    float Y_n2_g = LinearToPerceptualLuma(Y_n2);
    float Y_n3_g = LinearToPerceptualLuma(Y_n3);
    float Y_n4_g = LinearToPerceptualLuma(Y_n4);

    #if USE_9TAP == 1 || USE_25TAP == 1
    float Y_n5_g = LinearToPerceptualLuma(Y_n5);
    float Y_n6_g = LinearToPerceptualLuma(Y_n6);
    float Y_n7_g = LinearToPerceptualLuma(Y_n7);
    float Y_n8_g = LinearToPerceptualLuma(Y_n8);
    #else
    float Y_n5_g = 0.0, Y_n6_g = 0.0, Y_n7_g = 0.0, Y_n8_g = 0.0;
    #endif

    // v14.4 CRITICAL FIX: Declare perceptual luma for all 25-tap outer-ring samples.
    #if USE_25TAP == 1
    float Y_n9_g = LinearToPerceptualLuma(Y_n9);
    float Y_n10_g = LinearToPerceptualLuma(Y_n10);
    float Y_n11_g = LinearToPerceptualLuma(Y_n11);
    float Y_n12_g = LinearToPerceptualLuma(Y_n12);
    float Y_n13_g = LinearToPerceptualLuma(Y_n13);
    float Y_n14_g = LinearToPerceptualLuma(Y_n14);
    float Y_n15_g = LinearToPerceptualLuma(Y_n15);
    float Y_n16_g = LinearToPerceptualLuma(Y_n16);
    float Y_n17_g = LinearToPerceptualLuma(Y_n17);
    float Y_n18_g = LinearToPerceptualLuma(Y_n18);
    float Y_n19_g = LinearToPerceptualLuma(Y_n19);
    float Y_n20_g = LinearToPerceptualLuma(Y_n20);
    float Y_n21_g = LinearToPerceptualLuma(Y_n21);
    float Y_n22_g = LinearToPerceptualLuma(Y_n22);
    float Y_n23_g = LinearToPerceptualLuma(Y_n23);
    float Y_n24_g = LinearToPerceptualLuma(Y_n24);
    #endif

    // =========================================================================
    // 2.7. v15.5: EARLY EDGE AND DOF PROTECTION EVALUATION
    // =========================================================================
    // v15.5 QUALITY-NEUTRAL OPT: These factors use only the completed perceptual-
    // luma cache and fixed thresholds, so evaluating them here preserves the exact
    // equations and decisions while allowing outer perceptual lumas to expire after
    // their SSIM weights are consumed.

    // --- 7. EDGE DAMPENING FACTOR ---
    float edge_suppression_factor = 1.0;
    #if USE_EDGE_DAMPEN == 1
    {
        float d1 = abs(Y_c_g - Y_n1_g);
        float d2 = abs(Y_c_g - Y_n2_g);
        float d3 = abs(Y_c_g - Y_n3_g);
        float d4 = abs(Y_c_g - Y_n4_g);
        float max_raw_diff = max(d1, max(d2, max(d3, d4)));

        #if USE_9TAP == 1 || USE_25TAP == 1
        float d5 = abs(Y_c_g - Y_n5_g);
        float d6 = abs(Y_c_g - Y_n6_g);
        float d7 = abs(Y_c_g - Y_n7_g);
        float d8 = abs(Y_c_g - Y_n8_g);
        max_raw_diff = max(max_raw_diff, max(d5, max(d6, max(d7, d8))));
        #endif

        // v15.2 FIX: Edge ramp constant reduced from 0.35 to 0.20 for smoother detection
        float edge_ramp_max = EDGE_RAMP_CONSTANT * maxLumaCapPerceptual;
        float edge_strength = smoothstep(0.0, edge_ramp_max, max_raw_diff);

        float max_luma_g = Y_c_g;
        max_luma_g = max(max_luma_g, max(Y_n1_g, max(Y_n2_g, max(Y_n3_g, Y_n4_g))));
        #if USE_9TAP == 1 || USE_25TAP == 1
        max_luma_g = max(max_luma_g, max(max(Y_n5_g, Y_n6_g), max(Y_n7_g, Y_n8_g)));
        #endif
        // v15 FIX: Include 25-tap outer ring in white-line peak detection.
        #if USE_25TAP == 1
        max_luma_g = max(max_luma_g, max(max(Y_n9_g, Y_n10_g), max(Y_n11_g, Y_n12_g)));
        max_luma_g = max(max_luma_g, max(max(Y_n13_g, Y_n14_g), max(Y_n15_g, Y_n16_g)));
        max_luma_g = max(max_luma_g, max(max(Y_n17_g, Y_n18_g), max(Y_n19_g, Y_n20_g)));
        max_luma_g = max(max_luma_g, max(max(Y_n21_g, Y_n22_g), max(Y_n23_g, Y_n24_g)));
        #endif

        float whiteness = saturate((max_luma_g - eff_white_threshold) / max(maxLumaCapPerceptual - eff_white_threshold, 0.001));
        edge_suppression_factor = max(1.0 - (edge_strength * whiteness * EDGE_DAMPEN_STRENGTH), 0.0);
    }
    #endif

    // --- 10. DOF SUPPRESSION FACTOR ---
    float dof_factor = 1.0;
    #if USE_3ZONE_DOF == 1
    dof_factor = Calculate3ZoneAsymmetricDOF(
        Y_c_g,
        Y_n1_g, Y_n2_g, Y_n3_g, Y_n4_g,
        Y_n5_g, Y_n6_g, Y_n7_g, Y_n8_g,
        maxLumaCapPerceptual
#if USE_25TAP == 1
       , Y_n9_g, Y_n10_g, Y_n11_g, Y_n12_g,
        Y_n13_g, Y_n14_g, Y_n15_g, Y_n16_g,
        Y_n17_g, Y_n18_g, Y_n19_g, Y_n20_g,
        Y_n21_g, Y_n22_g, Y_n23_g, Y_n24_g
#endif
    );
    #elif USE_LEGACY_DOF_AWARENESS == 1
    dof_factor = CalculateDOFSuppression(
        Y_c_g,
        Y_n1_g, Y_n2_g, Y_n3_g, Y_n4_g,
        Y_n5_g, Y_n6_g, Y_n7_g, Y_n8_g
    );
    #endif

    // -------------------------------------------------------------------------
    // 2.8. ★ v13.5: ANISOTROPIC GRADIENT ANALYSIS
    // -------------------------------------------------------------------------
    #if ANISOTROPIC_WEIGHTING == 1
    // v15.6 experimental: retain the signed central gradients so opposite diagonal
    // orientations can be distinguished; absolute magnitudes preserve v15.5's
    // cardinal anisotropic factors exactly.
    float gradX_signed = Y_n3_g - Y_n2_g;
    float gradY_signed = Y_n4_g - Y_n1_g;
    float gradX = abs(gradX_signed);
    float gradY = abs(gradY_signed);
    float gradSum = gradX + gradY + 0.0001;

    float anisoX = 1.0 + (ANISOTROPIC_STRENGTH * (gradX / gradSum));
    float anisoY = 1.0 + (ANISOTROPIC_STRENGTH * (gradY / gradSum));

    // v14 FIX: Inherit gradient awareness properly for diagonals and knights
    float anisoDiag = 0.5 * (anisoX + anisoY);
    float anisoVertKn = lerp(anisoX, anisoY, 2.0 / 3.0);
    float anisoHorzKn = lerp(anisoX, anisoY, 1.0 / 3.0);

    // v15.6 experimental: divide each v15.5 pair's extra penalty between its two
    // orientations. The pair-average penalty remains aligned with the v15.5 base;
    // the epsilon gives an equal 50/50 split when directional evidence is flat.
    float diagSameEvidence = abs(gradX_signed + gradY_signed);
    float diagOppEvidence = abs(gradX_signed - gradY_signed);
    float diagDenom = diagSameEvidence + diagOppEvidence + (2.0 * ANISO_DIRECTION_EPS);
    float diagPenaltyBudget = 2.0 * (anisoDiag - 1.0);
    float anisoDiagSame = 1.0 + diagPenaltyBudget *
                          ((diagSameEvidence + ANISO_DIRECTION_EPS) / diagDenom);
    float anisoDiagOpp = 1.0 + diagPenaltyBudget *
                         ((diagOppEvidence + ANISO_DIRECTION_EPS) / diagDenom);

    float vertSameEvidence = abs(gradX_signed + (2.0 * gradY_signed));
    float vertOppEvidence = abs(gradX_signed - (2.0 * gradY_signed));
    float vertDenom = vertSameEvidence + vertOppEvidence + (2.0 * ANISO_DIRECTION_EPS);
    float vertPenaltyBudget = 2.0 * (anisoVertKn - 1.0);
    float anisoVertKnSame = 1.0 + vertPenaltyBudget *
                            ((vertSameEvidence + ANISO_DIRECTION_EPS) / vertDenom);
    float anisoVertKnOpp = 1.0 + vertPenaltyBudget *
                           ((vertOppEvidence + ANISO_DIRECTION_EPS) / vertDenom);

    float horzSameEvidence = abs((2.0 * gradX_signed) + gradY_signed);
    float horzOppEvidence = abs((2.0 * gradX_signed) - gradY_signed);
    float horzDenom = horzSameEvidence + horzOppEvidence + (2.0 * ANISO_DIRECTION_EPS);
    float horzPenaltyBudget = 2.0 * (anisoHorzKn - 1.0);
    float anisoHorzKnSame = 1.0 + horzPenaltyBudget *
                            ((horzSameEvidence + ANISO_DIRECTION_EPS) / horzDenom);
    float anisoHorzKnOpp = 1.0 + horzPenaltyBudget *
                           ((horzOppEvidence + ANISO_DIRECTION_EPS) / horzDenom);
    #else
    float anisoX = 1.0; float anisoY = 1.0;
    float anisoDiagSame = 1.0; float anisoDiagOpp = 1.0;
    float anisoVertKnSame = 1.0; float anisoVertKnOpp = 1.0;
    float anisoHorzKnSame = 1.0; float anisoHorzKnOpp = 1.0;
    #endif

    // -------------------------------------------------------------------------
    // 3. CALCULATE SPATIALLY CORRECTED WEIGHTS
    // -------------------------------------------------------------------------
    // v14 FIX: Using pre-computed perceptual luma to save 48 pow() calls
    float w1 = GetSSIMWeight(Y_c, Y_n1, Y_c_g, Y_n1_g, eff_noise_gate_perceptual, anisoY);
    float w2 = GetSSIMWeight(Y_c, Y_n2, Y_c_g, Y_n2_g, eff_noise_gate_perceptual, anisoX);
    float w3 = GetSSIMWeight(Y_c, Y_n3, Y_c_g, Y_n3_g, eff_noise_gate_perceptual, anisoX);
    float w4 = GetSSIMWeight(Y_c, Y_n4, Y_c_g, Y_n4_g, eff_noise_gate_perceptual, anisoY);

    #if USE_9TAP == 1 || USE_25TAP == 1
    // v15.6 experimental orientation map: n5/n8 share an x/y sign; n6/n7 oppose.
    float w5 = GetSSIMWeight(Y_c, Y_n5, Y_c_g, Y_n5_g, eff_noise_gate_perceptual, anisoDiagSame) * SSIM_SPATIAL_W_DIAGONAL;
    float w6 = GetSSIMWeight(Y_c, Y_n6, Y_c_g, Y_n6_g, eff_noise_gate_perceptual, anisoDiagOpp) * SSIM_SPATIAL_W_DIAGONAL;
    float w7 = GetSSIMWeight(Y_c, Y_n7, Y_c_g, Y_n7_g, eff_noise_gate_perceptual, anisoDiagOpp) * SSIM_SPATIAL_W_DIAGONAL;
    float w8 = GetSSIMWeight(Y_c, Y_n8, Y_c_g, Y_n8_g, eff_noise_gate_perceptual, anisoDiagSame) * SSIM_SPATIAL_W_DIAGONAL;
    #endif

    #if USE_25TAP == 1
    float w9 = GetSSIMWeight(Y_c, Y_n9, Y_c_g, Y_n9_g, eff_noise_gate_perceptual, anisoY) * 0.500;
    float w10 = GetSSIMWeight(Y_c, Y_n10, Y_c_g, Y_n10_g, eff_noise_gate_perceptual, anisoX) * 0.500;
    float w11 = GetSSIMWeight(Y_c, Y_n11, Y_c_g, Y_n11_g, eff_noise_gate_perceptual, anisoX) * 0.500;
    float w12 = GetSSIMWeight(Y_c, Y_n12, Y_c_g, Y_n12_g, eff_noise_gate_perceptual, anisoY) * 0.500;
    float w13 = GetSSIMWeight(Y_c, Y_n13, Y_c_g, Y_n13_g, eff_noise_gate_perceptual, anisoDiagSame) * 0.353;
    float w14 = GetSSIMWeight(Y_c, Y_n14, Y_c_g, Y_n14_g, eff_noise_gate_perceptual, anisoDiagOpp) * 0.353;
    float w15 = GetSSIMWeight(Y_c, Y_n15, Y_c_g, Y_n15_g, eff_noise_gate_perceptual, anisoDiagOpp) * 0.353;
    float w16 = GetSSIMWeight(Y_c, Y_n16, Y_c_g, Y_n16_g, eff_noise_gate_perceptual, anisoDiagSame) * 0.353;

    // v14 FIX: Applied direction-blended weights for knights
    // v15.6 experimental orientation map: n17/n24 and n19/n22 share x/y signs;
    // n18/n23 and n20/n21 use opposing x/y signs.
    float w17 = GetSSIMWeight(Y_c, Y_n17, Y_c_g, Y_n17_g, eff_noise_gate_perceptual, anisoVertKnSame) * 0.447;
    float w18 = GetSSIMWeight(Y_c, Y_n18, Y_c_g, Y_n18_g, eff_noise_gate_perceptual, anisoVertKnOpp) * 0.447;
    float w19 = GetSSIMWeight(Y_c, Y_n19, Y_c_g, Y_n19_g, eff_noise_gate_perceptual, anisoHorzKnSame) * 0.447;
    float w20 = GetSSIMWeight(Y_c, Y_n20, Y_c_g, Y_n20_g, eff_noise_gate_perceptual, anisoHorzKnOpp) * 0.447;
    float w21 = GetSSIMWeight(Y_c, Y_n21, Y_c_g, Y_n21_g, eff_noise_gate_perceptual, anisoHorzKnOpp) * 0.447;
    float w22 = GetSSIMWeight(Y_c, Y_n22, Y_c_g, Y_n22_g, eff_noise_gate_perceptual, anisoHorzKnSame) * 0.447;
    float w23 = GetSSIMWeight(Y_c, Y_n23, Y_c_g, Y_n23_g, eff_noise_gate_perceptual, anisoVertKnOpp) * 0.447;
    float w24 = GetSSIMWeight(Y_c, Y_n24, Y_c_g, Y_n24_g, eff_noise_gate_perceptual, anisoVertKnSame) * 0.447;
    #endif

    // -------------------------------------------------------------------------
    // 4. WEIGHTED AVERAGE
    // -------------------------------------------------------------------------
    #if USE_25TAP == 1
    float total_w = CENTER_ANCHOR_WEIGHT + w1+w2+w3+w4 + w5+w6+w7+w8 + w9+w10+w11+w12 + w13+w14+w15+w16 + w17+w18+w19+w20+w21+w22+w23+w24;
    total_w = max(total_w, 0.001);
    float3 neighbors = (c * CENTER_ANCHOR_WEIGHT +
    n1*w1 + n2*w2 + n3*w3 + n4*w4 +
    n5*w5 + n6*w6 + n7*w7 + n8*w8 +
    n9*w9 + n10*w10 + n11*w11 + n12*w12 +
    n13*w13 + n14*w14 + n15*w15 + n16*w16 +
    n17*w17 + n18*w18 + n19*w19 + n20*w20 +
    n21*w21 + n22*w22 + n23*w23 + n24*w24) / total_w;
    #elif USE_9TAP == 1
    float total_w = CENTER_ANCHOR_WEIGHT + w1+w2+w3+w4 + w5+w6+w7+w8;
    total_w = max(total_w, 0.001);
    float3 neighbors = (c * CENTER_ANCHOR_WEIGHT +
     n1*w1 + n2*w2 + n3*w3 + n4*w4 +
    n5*w5 + n6*w6 + n7*w7 + n8*w8) / total_w;
    #else
    float total_w = CENTER_ANCHOR_WEIGHT + w1+w2+w3+w4;
    total_w = max(total_w, 0.001);
    float3 neighbors = (c * CENTER_ANCHOR_WEIGHT +
    n1*w1 + n2*w2 + n3*w3 + n4*w4) / total_w;
    #endif

    // -------------------------------------------------------------------------
    // 5. ★ v13.5 / v14 / v15.2: ENHANCE & CLAMP DETAIL (Wavelet-Lite Frequency Separation)
    // -------------------------------------------------------------------------
    // v15.4: Detail signal remains c - neighbors (NOT c - blurL) for strong halo resistance
    float3 detail = c - neighbors;

    // v15.2 FIX: Detail clamp now scales with perceptual luma max(Y_c_g, 1.0)
    // instead of linear luma. Prevents exploding clamp limits on bright HDR pixels.
    // v15.5 QUALITY-NEUTRAL OPT: Evaluate it at first use to shorten its live range.
    float eff_detail_clamp = DETAIL_CLAMP * max(Y_c_g, 1.0);

#if USE_FREQ_CLAMP == 1
    // v15.2 FIX: HF local_mean strictly excludes center pixel — true high-pass
    #if USE_9TAP == 1 || USE_25TAP == 1
    // 8-neighbor average (excludes center) for true HF extraction
    float3 local_mean_hf = (n1 + n2 + n3 + n4 + n5 + n6 + n7 + n8) * (1.0 / 8.0);
    #else
    float3 local_mean_hf = (n1 + n2 + n3 + n4) * 0.25;
    #endif

    float3 hf_detail = c - local_mean_hf; // True high-pass: HF = c - inner local mean

    #if USE_25TAP == 1
        // v15.1: blurL = uniform 5x5 average for MF clamp reference only
        float3 blurL = (c + n1 + n2 + n3 + n4 + n5 + n6 + n7 + n8 +
                        n9 + n10 + n11 + n12 + n13 + n14 + n15 + n16 +
                        n17 + n18 + n19 + n20 + n21 + n22 + n23 + n24) * (1.0 / 25.0);
        float3 mf_for_clamp = local_mean_hf - blurL;   // linear reference, clamp only
        float3 mf_detail = local_mean_hf - neighbors;  // real signal, stays edge-aware
    #else
        float3 mf_for_clamp = local_mean_hf - neighbors;
        float3 mf_detail = mf_for_clamp;
    #endif

    // HF clamp
    float hf_max = max(abs(hf_detail.r), max(abs(hf_detail.g), abs(hf_detail.b)));
    float hf_clamp = eff_detail_clamp * FREQ_CLAMP_HF_RATIO;
    float hf_scale = hf_clamp * rsqrt(hf_max * hf_max + hf_clamp * hf_clamp + 1e-10);
    hf_detail *= hf_scale;

    // MF clamp now uses linear reference
    float mf_max = max(abs(mf_for_clamp.r), max(abs(mf_for_clamp.g), abs(mf_for_clamp.b)));
    float mf_clamp = eff_detail_clamp * FREQ_CLAMP_MF_RATIO;
    float mf_scale = mf_clamp * rsqrt(mf_max * mf_max + mf_clamp * mf_clamp + 1e-10);
    mf_detail *= mf_scale;

    // Recombine independently clamped HF/MF bands; pre-clamp decomposition preserves
    // HF + MF = c - neighbors.
    detail = hf_detail + mf_detail;

    // v15.2 FIX: Safety clamp post-recombination dynamically scales
    float combined_max = max(abs(detail.r), max(abs(detail.g), abs(detail.b)));
    float safety_limit = eff_detail_clamp * (FREQ_CLAMP_HF_RATIO + FREQ_CLAMP_MF_RATIO);
    float safety_scale = min(1.0, safety_limit / max(combined_max, 0.0001));
    detail *= safety_scale;
#else
    // Legacy Soft/Hard Clamp
    float detail_max = max(abs(detail.r), max(abs(detail.g), abs(detail.b)));
    #if USE_SOFT_CLAMP == 1
    float scale = eff_detail_clamp * rsqrt(detail_max * detail_max + eff_detail_clamp * eff_detail_clamp + 1e-10);
    detail *= scale;
    #else
    if (detail_max > eff_detail_clamp) {
        detail *= eff_detail_clamp / detail_max;
    }
    #endif
#endif

    // -------------------------------------------------------------------------
    // 6. CHROMA SEPARATION
    // -------------------------------------------------------------------------
    float detail_luma = dot(detail, LUMA_WEIGHTS);
    float3 luma_vec = float3(detail_luma, detail_luma, detail_luma);
    float3 detail_chroma = detail - luma_vec;

    // =========================================================================
    // 7-10. PROTECTIVE SUPPRESSION FACTORS (v15: Computed first, then combined)
    // =========================================================================
    // v15 RESTRUCTURE: Instead of applying edge dampen → chroma dampen → dark protect
    // → DOF sequentially (cascading multiplication), we compute all protective factors
    // first and combine them with CASCADE_CORRECTION to prevent over-dampening.

    // --- 7. EDGE DAMPENING FACTOR ---
    // v15.5: edge_suppression_factor was evaluated early from the same luma cache.

    // --- 8. CHROMA DAMPENING (applied to chroma channel only, not a protective factor) ---
    #if USE_LUMA_CHROMA_DAMPENING == 1
    // v15 FIX: Thresholds now scale with maxLumaCapPerceptual — previously hardcoded
    // to SDR [0,1], causing highlight_mask to trigger at perceptual 0.75 in HDR where
    // the range extends to ~2.29, annihilating color sharpening for most bright content.
    float shadow_mask = 1.0 - smoothstep(0.0, 0.25 * maxLumaCapPerceptual, Y_c_g);
    float highlight_mask = smoothstep(0.75 * maxLumaCapPerceptual, maxLumaCapPerceptual, Y_c_g);
    float chroma_luma_mask = saturate(shadow_mask + highlight_mask);

    float dynamic_chroma_damp = lerp(CHROMA_DAMPENING, CHROMA_DAMPENING * CHROMA_EXTREME_LUMA_MULTIPLIER, chroma_luma_mask);
    #else
    float dynamic_chroma_damp = CHROMA_DAMPENING;
    #endif

    // --- 9. DARK AREA PROTECTION FACTOR ---
    float dark_protect_factor = smoothstep(eff_dark_low, eff_dark_high, Y_c_g);

    // --- 10. DOF SUPPRESSION FACTOR ---
    // v15.5: dof_factor was evaluated early from the same luma cache.

    // =========================================================================
    // 11. v15.2: COMBINE PROTECTIVE FACTORS WITH CASCADING CORRECTION
    // =========================================================================
    // PROBLEM: Naive multiplication of N independent suppression factors causes
    // exponential over-dampening. Three 0.5 factors → 0.125 (87.5% suppression)
    // when each factor only intended 50% suppression individually.
    //
    // SOLUTION: Apply pow(product, CASCADE_CORRECTION) where exponent < 1 flattens
    // the cascade. Three 0.5 factors with 0.75 exponent → 0.21 (79% suppression).
    // Each factor still contributes, but the compound effect is less extreme.
    //
    // v15.2 FIX: CASCADE_CORRECTION now applies to chroma spatial protection too.
    // Luma path: edge_suppression × dark_protect × dof_factor (3 factors)
    // Chroma path: dark_protect × dof_factor (2 factors — edge dampen is luma-only,
    //   and chroma_damp is intentional chroma reduction, not spatial protection)

    float luma_combined_protection = edge_suppression_factor * dark_protect_factor * dof_factor;
    luma_combined_protection = pow(max(luma_combined_protection, 0.0), CASCADE_CORRECTION);

    float chroma_spatial_protection = dark_protect_factor * dof_factor;
    // v15.2: Apply CASCADE_CORRECTION to chroma spatial protection as well
    chroma_spatial_protection = pow(max(chroma_spatial_protection, 0.0), CASCADE_CORRECTION);

    // Apply combined factors
    luma_vec *= luma_combined_protection;
    float3 final_detail = luma_vec + (detail_chroma * dynamic_chroma_damp * chroma_spatial_protection);

    // -------------------------------------------------------------------------
    // 12. APPLY SHARPENING
    // -------------------------------------------------------------------------
    float3 final = c + final_detail * STRENGTH * TAP_COMPENSATION;

    // -------------------------------------------------------------------------
    // 13. ANTI-RINGING
    // -------------------------------------------------------------------------
    #if USE_ANTI_RINGING == 1
    float Y_min = min(Y_n1, min(Y_n2, min(Y_n3, Y_n4)));
    float Y_max = max(Y_n1, max(Y_n2, max(Y_n3, Y_n4)));
    #if USE_9TAP == 1 || USE_25TAP == 1
        Y_min = min(Y_min, min(Y_n5, min(Y_n6, min(Y_n7, Y_n8))));
        Y_max = max(Y_max, max(Y_n5, max(Y_n6, max(Y_n7, Y_n8))));
    #endif
    Y_min = min(Y_min, Y_c);
    Y_max = max(Y_max, Y_c);

    float bounds_padding = (Y_max - Y_min) * ANTI_RINGING_OVERSHOOT;
    Y_min -= bounds_padding;
    Y_max += bounds_padding;

    float Y_final = dot(final, LUMA_WEIGHTS);
    float Y_clamped = clamp(Y_final, Y_min, Y_max);

    if (Y_final > 0.0001) {
        final *= (Y_clamped / Y_final);
    }
    #endif

    // -------------------------------------------------------------------------
    // 14. OUTPUT
    // -------------------------------------------------------------------------
    // v15 FIX: Added upper clamp to prevent HDR overshoot on FP16 swap chains.
    final = clamp(final, 0.0, hdrScale);
    final = ToGamma(final, isHDR);

    return float4(final, 1.0);
}


// Original SSIM Concept: Shiandow (SSIM Downscaling)
// ==================================================================================
// END OF SHADER v15.6 Experimental
// ==================================================================================
