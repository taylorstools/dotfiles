#version 440
// One pass of a true Gaussian blur, run once across and once down by
// Widgets/BlurredWallpaper.qml, which also darkens on the second pass (dim:
// the factor the colour is multiplied by, 1 = none). Taps reach 4 sigma, and
// the texture clamps at its edges, so the edge pixels repeat beyond the
// picture as with ImageMagick's -blur.
//
// Qt loads the compiled gaussian.frag.qsb next to this. After editing, run:
//   nix shell nixpkgs#qt6.qtshadertools -c qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o gaussian.frag.qsb gaussian.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // One texel along the blur's direction.
    vec2 texel;
    // In texels.
    float sigma;
    float dim;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    float reach = ceil(sigma * 4.0);
    vec4 sum = texture(source, qt_TexCoord0);
    float total = 1.0;
    // A constant bound with a break: GLSL ES 1.00 allows no other loop.
    for (int i = 1; i <= 128; ++i) {
        float x = float(i);
        if (x > reach)
            break;
        float w = exp(-x * x / (2.0 * sigma * sigma));
        sum += w * (texture(source, qt_TexCoord0 + texel * x) + texture(source, qt_TexCoord0 - texel * x));
        total += 2.0 * w;
    }
    fragColor = vec4(sum.rgb / total * dim, 1.0) * qt_Opacity;
}
