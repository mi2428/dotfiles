// A faint line-art girls_last_tour_draft1 overlay for Ghostty.
//
// The 160x240 mask is extracted from dark-line intensity rather than alpha,
// keeping the robe hollow. Each row uses six positive 28-bit words so the
// artwork remains self-contained without another texture sampler.

const int MASK_WIDTH = 160;
const int MASK_HEIGHT = 240;
const int MASK_WORD_BITS = 28;
const int MASK_WORDS_PER_ROW = 6;

const int girls_last_tour_draft1Mask[1440] = int[1440](
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 1048576, 0, 0, 0,
    0, 0, 1572864, 0, 0, 0,
    0, 0, 238551040, 3, 0, 0,
    0, 0, 267911168, 31, 0, 0,
    0, 0, 267386880, 6203, 0, 0,
    0, 0, 33030144, 16226, 0, 0,
    0, 0, 16515072, 8188, 0, 0,
    0, 0, 1441792, 159, 0, 0,
    0, 0, 219021312, 415, 0, 0,
    0, 0, 252116992, 408, 0, 0,
    0, 0, 59211776, 792, 0, 0,
    0, 0, 15171584, 792, 0, 0,
    0, 0, 7782400, 784, 0, 0,
    0, 0, 2080768, 32752, 0, 0,
    0, 0, 1032192, 65535, 0, 0,
    0, 0, 253739008, 25467, 0, 0,
    0, 0, 33406976, 428, 0, 0,
    0, 0, 33226752, 412, 0, 0,
    0, 0, 268308480, 255, 0, 0,
    0, 0, 4657152, 127, 0, 0,
    0, 0, 260276224, 115, 0, 0,
    0, 0, 255647744, 127, 0, 0,
    0, 0, 267968512, 79, 0, 0,
    0, 0, 268369920, 15, 0, 0,
    0, 0, 252706816, 12, 0, 0,
    0, 0, 234881024, 396, 0, 0,
    0, 0, 234881024, 903, 0, 0,
    0, 0, 254803968, 899, 0, 0,
    0, 0, 268304384, 15, 0, 0,
    0, 0, 268402688, 31, 0, 0,
    0, 0, 268427264, 255, 0, 0,
    0, 0, 268431360, 511, 0, 0,
    0, 0, 268431360, 2047, 0, 0,
    0, 0, 268433408, 2047, 0, 0,
    0, 0, 268434432, 4095, 0, 0,
    0, 0, 268434944, 4095, 0, 0,
    0, 0, 268435200, 4095, 0, 0,
    0, 0, 260046592, 7167, 0, 0,
    0, 0, 200277888, 6651, 0, 0,
    0, 0, 260046720, 14259, 0, 0,
    0, 0, 56623040, 13235, 0, 0,
    0, 0, 47054784, 13922, 0, 0,
    0, 0, 115343232, 30278, 0, 0,
    0, 0, 115046336, 29894, 0, 0,
    0, 0, 110837504, 31876, 0, 0,
    0, 0, 93959872, 63884, 0, 0,
    0, 0, 228179648, 47372, 0, 0,
    0, 0, 219889600, 45848, 0, 0,
    0, 0, 252919744, 62232, 0, 0,
    0, 0, 187905920, 110592, 0, 0,
    0, 0, 34617216, 167936, 0, 0,
    0, 0, 16256, 55296, 0, 0,
    0, 0, 12160, 317632, 0, 0,
    0, 0, 118656, 112832, 0, 0,
    0, 0, 118656, 109568, 0, 0,
    0, 0, 3584, 11264, 0, 0,
    0, 0, 7168, 9728, 0, 0,
    0, 0, 14592, 3584, 0, 0,
    0, 0, 117467904, 7040, 0, 0,
    0, 0, 117502464, 14272, 0, 0,
    0, 0, 523008, 19704, 0, 0,
    0, 0, 268413952, 104671, 0, 0,
    0, 0, 267834880, 209667, 0, 0,
    0, 0, 264465152, 418567, 0, 0,
    0, 0, 266559744, 541215, 0, 0,
    0, 0, 258015360, 1082943, 0, 0,
    0, 0, 268014144, 99383, 0, 0,
    0, 0, 264864032, 198707, 0, 0,
    0, 0, 234391600, 2081, 0, 0,
    0, 0, 234654720, 12323, 0, 0,
    0, 0, 217892352, 4195, 0, 0,
    0, 0, 217368096, 99, 0, 0,
    0, 0, 208945664, 99, 0, 0,
    0, 0, 208928768, 67, 0, 0,
    0, 0, 208928768, 67, 0, 0,
    0, 0, 204865536, 67, 0, 0,
    0, 0, 204865536, 194, 0, 0,
    0, 0, 205127680, 194, 0, 0,
    0, 0, 205127680, 194, 0, 0,
    0, 0, 205193216, 130, 0, 0,
    0, 0, 205455360, 130, 0, 0,
    0, 0, 205193216, 386, 0, 0,
    0, 0, 202964992, 386, 0, 0,
    0, 0, 1900544, 386, 0, 0,
    0, 0, 1900544, 258, 0, 0,
    0, 0, 1900544, 262, 0, 0,
    0, 0, 1933312, 262, 0, 0,
    0, 0, 1933312, 262, 0, 0,
    0, 0, 1867776, 768, 0, 0,
    0, 0, 819200, 768, 0, 0,
    0, 0, 819200, 768, 0, 0,
    0, 0, 311296, 768, 0, 0,
    0, 0, 442368, 512, 0, 0,
    0, 0, 409600, 512, 0, 0,
    0, 0, 475136, 512, 0, 0,
    0, 0, 475136, 512, 0, 0,
    0, 0, 417792, 512, 0, 0,
    0, 0, 417792, 1536, 0, 0,
    0, 0, 417792, 1536, 0, 0,
    0, 0, 483328, 1536, 0, 0,
    0, 0, 417792, 1536, 0, 0,
    0, 0, 401408, 1536, 0, 0,
    0, 0, 401408, 1536, 0, 0,
    0, 0, 466944, 1536, 0, 0,
    0, 0, 466944, 1536, 0, 0,
    0, 0, 208896, 1536, 0, 0,
    0, 0, 208896, 1024, 0, 0,
    0, 0, 208896, 1024, 0, 0,
    0, 0, 200704, 1024, 0, 0,
    0, 0, 200704, 1024, 0, 0,
    0, 0, 200704, 1024, 0, 0,
    0, 0, 200704, 3072, 0, 0,
    0, 0, 200704, 3072, 0, 0,
    0, 0, 4096, 3072, 0, 0,
    0, 0, 4096, 3072, 0, 0,
    0, 0, 6144, 3072, 0, 0,
    0, 0, 6144, 3072, 0, 0,
    0, 0, 6144, 2048, 0, 0,
    0, 0, 6144, 2048, 0, 0,
    0, 0, 6144, 2048, 0, 0,
    0, 0, 2048, 2048, 0, 0,
    0, 0, 2048, 2048, 0, 0,
    0, 0, 2048, 6144, 0, 0,
    0, 0, 2048, 6144, 0, 0,
    0, 0, 2048, 6144, 0, 0,
    0, 0, 2048, 6144, 0, 0,
    0, 0, 2048, 6144, 0, 0,
    0, 0, 3072, 6144, 0, 0,
    0, 0, 3072, 6144, 0, 0,
    0, 0, 3072, 4096, 0, 0,
    0, 0, 3072, 4096, 0, 0,
    0, 0, 3072, 4096, 0, 0,
    0, 0, 3072, 4096, 0, 0,
    0, 0, 3072, 12288, 0, 0,
    0, 0, 3072, 12288, 0, 0,
    0, 0, 1024, 12288, 0, 0,
    0, 0, 1024, 12288, 0, 0,
    0, 0, 1024, 12288, 0, 0,
    0, 0, 1024, 12288, 0, 0,
    0, 0, 1024, 12288, 0, 0,
    0, 0, 1024, 12288, 0, 0,
    0, 0, 1024, 12288, 0, 0,
    0, 0, 1024, 12288, 0, 0,
    0, 0, 1536, 12288, 0, 0,
    0, 0, 1536, 12288, 0, 0,
    0, 0, 512, 12288, 0, 0,
    0, 0, 512, 8192, 0, 0,
    0, 0, 512, 8192, 0, 0,
    0, 0, 512, 8192, 0, 0,
    0, 0, 512, 8192, 0, 0,
    0, 0, 512, 8192, 0, 0,
    0, 0, 512, 8192, 0, 0,
    0, 0, 768, 24576, 0, 0,
    0, 0, 768, 24576, 0, 0,
    0, 0, 134218496, 24576, 0, 0,
    0, 0, 134217984, 24576, 0, 0,
    0, 0, 134217984, 24576, 0, 0,
    0, 0, 256, 24576, 0, 0,
    0, 0, 256, 24579, 0, 0,
    0, 0, 256, 24579, 0, 0,
    0, 0, 256, 24579, 0, 0,
    0, 0, 1920, 24576, 0, 0,
    0, 0, 1920, 24576, 0, 0,
    0, 0, 896, 24577, 0, 0,
    0, 0, 896, 24579, 0, 0,
    0, 0, 263040, 24578, 0, 0,
    0, 0, 786816, 24579, 0, 0,
    0, 0, 1573248, 24576, 0, 0,
    0, 0, 1442176, 24576, 0, 0,
    0, 0, 786816, 24576, 0, 0,
    0, 0, 1573248, 24578, 0, 0,
    0, 0, 1245568, 24578, 0, 0,
    0, 0, 983488, 24578, 0, 0,
    0, 0, 1572928, 24576, 0, 0,
    0, 0, 786496, 24576, 0, 0,
    0, 0, 852032, 24624, 0, 0,
    0, 0, 983104, 24604, 0, 0,
    0, 0, 524384, 24700, 0, 0,
    0, 0, 393312, 24576, 0, 0,
    0, 0, 135135328, 24591, 0, 0,
    0, 0, 524384, 24607, 0, 0,
    0, 0, 135200800, 24583, 0, 0,
    0, 0, 491552, 24607, 0, 0,
    0, 0, 4161568, 24608, 0, 0,
    0, 0, 4161568, 24638, 0, 0,
    0, 0, 4161568, 24591, 0, 0,
    0, 0, 136232992, 16511, 0, 0,
    0, 0, 4177952, 16895, 0, 0,
    0, 0, 201768992, 16895, 0, 0,
    0, 0, 136306720, 49407, 0, 0,
    0, 0, 1490992, 49344, 0, 0,
    0, 0, 235925552, 49407, 0, 0,
    0, 0, 942128, 49279, 0, 0,
    0, 0, 522288, 49400, 0, 0,
    0, 0, 268394512, 49183, 0, 0,
    0, 0, 202373136, 49404, 0, 0,
    0, 0, 13625360, 49344, 0, 0,
    0, 0, 268433424, 49275, 0, 0,
    0, 0, 138354704, 33279, 0, 0,
    0, 0, 253968, 33791, 0, 0,
    0, 0, 135262224, 99327, 0, 0,
    0, 0, 138309632, 98559, 0, 0,
    0, 0, 205519872, 100350, 0, 0,
    0, 0, 3798040, 100351, 0, 0,
    0, 0, 268434952, 100350, 0, 0,
    0, 0, 268303368, 101631, 0, 0,
    0, 0, 66059784, 67526, 0, 0,
    0, 0, 253754376, 67071, 0, 0,
    0, 0, 255852296, 200703, 0, 0,
    0, 0, 259784460, 200703, 0, 0,
    0, 0, 4193796, 200703, 0, 0,
    0, 0, 268041988, 204799, 0, 0,
    0, 0, 142606084, 204799, 0, 0,
    0, 0, 268434948, 204799, 0, 0,
    0, 0, 264240644, 229375, 0, 0,
    0, 0, 268434948, 200703, 0, 0,
    0, 0, 268435204, 163839, 0, 0,
    0, 0, 268435336, 212991, 0, 0,
    0, 0, 268435376, 131071, 0, 0,
    0, 0, 268435392, 32767, 0, 0,
    0, 0, 268435200, 8191, 0, 0,
    0, 0, 268433408, 127, 0, 0,
    0, 0, 266600448, 7, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0
);

float maskPixel(ivec2 pixel) {
    if (pixel.x < 0 || pixel.x >= MASK_WIDTH ||
        pixel.y < 0 || pixel.y >= MASK_HEIGHT) {
        return 0.0;
    }

    int wordIndex = pixel.y * MASK_WORDS_PER_ROW + pixel.x / MASK_WORD_BITS;
    int bitIndex = pixel.x - (pixel.x / MASK_WORD_BITS) * MASK_WORD_BITS;
    return (girls_last_tour_draft1Mask[wordIndex] & (1 << bitIndex)) != 0 ? 1.0 : 0.0;
}

float sampleMask(vec2 position) {
    ivec2 base = ivec2(floor(position));
    vec2 weight = fract(position);

    float top = mix(maskPixel(base), maskPixel(base + ivec2(1, 0)), weight.x);
    float bottom = mix(
        maskPixel(base + ivec2(0, 1)),
        maskPixel(base + ivec2(1, 1)),
        weight.x
    );
    return mix(top, bottom, weight.y);
}

vec2 inverseRotate(vec2 point, float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return vec2(
        cosine * point.x + sine * point.y,
        -sine * point.x + cosine * point.y
    );
}

float ellipseRing(vec2 point, vec2 radius) {
    float distanceFromRing = abs(length(point / radius) - 1.0);
    return 1.0 - smoothstep(0.035, 0.085, distanceFromRing);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 terminal = texture(iChannel0, uv);

    // Anchor the figure near the lower-right and keep it at 69% screen height.
    vec2 screenAnchor = vec2(0.82, 0.97) * iResolution.xy;
    vec2 maskAnchor = vec2(80.0, 232.0);
    float pixelScale = (0.69 * iResolution.y) / float(MASK_HEIGHT);

    // Inverse-map the output pixel into the artwork. The lower body stays
    // planted while the head drifts by roughly one to two degrees.
    float focusMotion = iFocus > 0 ? 1.0 : 0.14;
    float angle = focusMotion * (
        0.027 * sin(iTime * 0.5711987) +
        0.004 * sin(iTime * 1.1423973 + 1.2)
    );
    vec2 local = inverseRotate((fragCoord - screenAnchor) / pixelScale, angle);
    vec2 maskPosition = local + maskAnchor;

    float upperBody = clamp(
        (maskAnchor.y - maskPosition.y) / maskAnchor.y,
        0.0,
        1.0
    );
    maskPosition.x -= focusMotion * 1.4 *
        sin(iTime * 0.6981317 + 0.8) * upperBody * upperBody;

    // The actual ink occupies only this narrow area of the source canvas.
    // Avoid all packed-mask reads for the rest of the terminal.
    if (maskPosition.x < 52.0 || maskPosition.x > 110.0 ||
        maskPosition.y < 5.0 || maskPosition.y > 238.0) {
        fragColor = terminal;
        return;
    }

    float ink = sampleMask(maskPosition);

    // A single independently tilting orbit and node keep the head mechanism
    // alive without loops or additional texture reads.
    vec2 haloPoint = maskPosition - vec2(81.0, 23.0);
    float haloAngle = focusMotion * 0.075 * sin(iTime * 0.3695991 + 0.4);
    haloPoint = inverseRotate(haloPoint, haloAngle);
    float orbit = ellipseRing(haloPoint, vec2(24.0, 8.0));

    float orbitPhase = iFocus > 0 ? iTime * 0.4487989 : 0.5;
    vec2 nodePosition = vec2(cos(orbitPhase) * 24.0, sin(orbitPhase) * 8.0);
    float node = 1.0 - smoothstep(
        0.8,
        1.8,
        length(haloPoint - nodePosition)
    );
    float halo = max(orbit * 0.55, node);

    // Detect terminal foreground pixels and let glyphs dominate the overlay.
    float foregroundDistance = length(terminal.rgb - iBackgroundColor);
    float bareBackground = 1.0 - smoothstep(0.055, 0.20, foregroundDistance);
    float readability = mix(0.08, 1.0, bareBackground);

    vec3 lineColor = mix(iPalette[8], iForegroundColor, 0.22);
    float overlay = clamp(ink * 0.072 + halo * 0.028, 0.0, 0.10);
    overlay *= readability;

    fragColor = vec4(mix(terminal.rgb, lineColor, overlay), terminal.a);
}
