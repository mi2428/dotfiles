// RunCat Neo's built-in Cat runner, rendered as an ASCII/dot matrix overlay.
//
// Source sprites: https://github.com/runcat-dev/RunCatNeo
//   LocalPackage/Sources/UserInterface/Resources/Media.xcassets/Runners/Cat
// The original 56x36 alpha masks (five frames, Apache-2.0) are encoded below
// as two 28-bit masks per row. This is the source pixel art, not an
// approximation, and needs no texture input beyond Ghostty's iChannel0.

const int spriteMasks[360] = int[360](
    0, 0, 0, 0, 0, 0, 0, 0, 458752, 0, 983040, 0,
    2031616, 0, 4065280, 0, 8272896, 0, 16579584, 0, 33552384, 0, 134213632, 3145728,
    268427264, 8126495, 268419072, 33489407, 268402688, 33540095, 268304384, 33554431, 268173312, 16777215, 267911168, 4194303,
    267386942, 2097151, 268435454, 1048575, 268435448, 4194303, 268435328, 16777215, 252704768, 33554431, 201326592, 67108863,
    0, 67108862, 0, 66715136, 0, 53607424, 0, 53606400, 0, 20969472, 0, 16756736,
    0, 8335360, 0, 7299072, 0, 5103616, 0, 7979008, 0, 7438336, 0, 2097152,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 1835008, 29360128, 3932160, 32505856, 8126464, 33292288, 33030144, 16711680, 66615296, 8355840,
    268433408, 134209536, 268433408, 134217727, 268431360, 67108863, 268419072, 33554431, 268402688, 8388607, 268369920, 4194303,
    268304384, 67108863, 267386880, 134217727, 266338304, 134217727, 264241152, 218103807, 264241152, 216530943, 267386880, 80214527,
    234356736, 132640895, 8257536, 67100678, 4178912, 33472512, 1048560, 33341440, 262080, 58294272, 32256, 63897600,
    0, 63832064, 0, 17563648, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 131072, 0, 491520, 0, 491520, 0, 245760, 29360128, 253952, 29360128, 258048,
    31457280, 16775168, 31457280, 16775168, 31457280, 8386560, 32505856, 2096640, 66060288, 1048560, 133693440, 1048574,
    267911168, 8388607, 267911168, 33554431, 267911168, 67108863, 267911168, 67108863, 267911168, 117440511, 267386880, 73924607,
    267386880, 107216895, 266338304, 65273855, 266338304, 33550591, 264241152, 33546303, 264241152, 58507295, 264241152, 41517071,
    31457280, 64716800, 15728640, 60686336, 7864320, 1835008, 4063232, 0, 2080768, 0, 524032, 0,
    130944, 0, 32256, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 3072, 0, 3584, 0, 3840, 0, 3840, 0, 3983,
    0, 3999, 201326592, 2047, 260046848, 4095, 264241152, 4095, 264241152, 4095, 260046848, 4095,
    264241152, 4095, 266338304, 8191, 267386880, 65535, 267386880, 524287, 267913184, 2097151, 267927544, 2097151,
    268042236, 4194303, 268435454, 3670015, 268431390, 2310143, 268419072, 2301951, 268304384, 3612671, 267911168, 2097151,
    264241152, 1048327, 234881024, 1046017, 0, 650240, 0, 1793024, 0, 1996800, 0, 811008,
    0, 16384, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 50331648, 0, 125829120, 0, 62914560, 0, 31457280, 6, 31457280, 7,
    149946368, 1799, 250609664, 3847, 267386880, 7939, 267386880, 7683, 267386880, 15879, 267386880, 16143,
    267386880, 32767, 267911422, 32767, 267912191, 32767, 267915263, 32767, 267927296, 32767, 268434432, 65535,
    268431360, 262143, 268419072, 1048575, 266600448, 2097151, 264241152, 2097151, 234881024, 4194303, 0, 4169696,
    0, 3350464, 0, 3383168, 0, 1310592, 0, 1047296, 0, 523008, 0, 455168,
    0, 450048, 0, 498688, 0, 497664, 0, 131072, 0, 0, 0, 0
);

float asciiMark(vec2 position) {
    float horizontal = 1.0 - smoothstep(0.040, 0.080, abs(abs(position.y) - 0.16));
    horizontal *= 1.0 - smoothstep(0.36, 0.44, abs(position.x));

    float vertical = 1.0 - smoothstep(0.040, 0.080, abs(abs(position.x) - 0.16));
    vertical *= 1.0 - smoothstep(0.36, 0.44, abs(position.y));

    float dot = 1.0 - smoothstep(0.08, 0.16, length(position));
    return max(max(horizontal, vertical), dot);
}

bool spritePixel(int frame, int x, int y) {
    if (x < 0 || x >= 56 || y < 0 || y >= 36) return false;

    int part = x / 28;
    int mask = spriteMasks[(frame * 36 + y) * 2 + part];
    return (mask & (1 << (x - part * 28))) != 0;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 terminal = texture(iChannel0, uv);

    // Ghostty presents fragCoord with a top-left origin here, while the masks
    // were encoded bottom-to-top from the source PNG. Mirror the Y row below.
    float shortSide = min(iResolution.x, iResolution.y);
    vec2 point = (fragCoord - 0.5 * iResolution.xy) / (0.48 * shortSide);
    vec2 spritePosition = point * 50.0 + vec2(28.0, 18.0);
    ivec2 pixel = ivec2(floor(spritePosition));

    int frame = int(mod(floor(iTime * 8.0), 5.0));
    // The source artwork faces screen-right. Mirror X for a leftward runner,
    // and mirror Y to restore the source artwork's upright orientation.
    float sprite = spritePixel(frame, 55 - pixel.x, 35 - pixel.y) ? 1.0 : 0.0;
    float mark = asciiMark(fract(spritePosition) - 0.5);

    // Catppuccin Mocha's ANSI bright-black and black, blended into a muted
    // charcoal that automatically follows a future palette change.
    vec3 catColor = mix(iPalette[8], iPalette[0], 0.35);
    fragColor = vec4(mix(terminal.rgb, catColor, sprite * mark * 0.38), terminal.a);
}
