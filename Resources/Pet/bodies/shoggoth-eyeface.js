// The shoggoth's eye-flower face (material `shoggoth eyeface`), ported from its Blender graph
// (docs/shoggoth-shader-nodes.png): the pixel-art texture sampled nearest; texels whose HSL
// lightness lies strictly between LIGHTNESS[0] and LIGHTNESS[1] (its irises) are multiplied by the
// tint; an RGB curve through (0, 0) and (CURVE_KNEE, 1), flat after, brightens everything; alpha
// over ALPHA_CUT is opaque and the rest is cut, as is anything outside the texture (Blender's Clip). The GLSL below is built from these numbers, and
// `eyefaceShade` is the same sum in JS, for the tests.
//
// Blender's curve is a smooth spline through those points; here it is the straight line
// min(1, x / CURVE_KNEE). The texture is greyscale, so Blender's Display P3 and three's sRGB read
// it alike.

export const LIGHTNESS = [0.15, 0.37];
export const CURVE_KNEE = 0.25;
export const ALPHA_CUT = 0.5;
export const DEFAULT_TINT = '#ff0000';

// Its eyes lie on FLOWER_EYES spokes from the texture's middle, the first along +u, and reach
// FLOWER_EYE_REACH across their spoke at their widest, outline included (measured from the
// texture). Lids close across each eye toward its spoke.
export const FLOWER_EYES = 8;
export const FLOWER_EYE_REACH = 0.135;

/// `#rrggbb` (any case) as given, lower-cased; anything else is the default red.
export function parseTint(value) {
  return typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value.trim()) ? value.trim().toLowerCase() : DEFAULT_TINT;
}

const f = (x) => x.toFixed(4);

/// GLSL replacing three's map_fragment for the eye-flower: needs `uniform vec3 uTint` (linear).
export const EYEFACE_MAP_GLSL = `#ifdef USE_MAP
  {
    vec4 eyeTexel = texture2D(map, vMapUv);
    vec3 c = eyeTexel.rgb;
    float lightness = 0.5 * (max(max(c.r, c.g), c.b) + min(min(c.r, c.g), c.b));
    float iris = (1.0 - step(lightness, ${f(LIGHTNESS[0])})) * (1.0 - step(${f(LIGHTNESS[1])}, lightness));
    c = mix(c, c * uTint, iris);
    c = min(vec3(1.0), c / ${f(CURVE_KNEE)});
    diffuseColor.rgb *= c;
    // Clip, as in Blender (glTF exports it as clamp): nothing outside the texture.
    bool inside = all(greaterThanEqual(vMapUv, vec2(0.0))) && all(lessThanEqual(vMapUv, vec2(1.0)));
    diffuseColor.a *= inside ? eyeTexel.a : 0.0;
  }
#endif`;

/// The same shade in JS: `rgb` linear 0..1, `tint` linear 0..1; returns the linear base colour.
export function eyefaceShade(rgb, tint) {
  const lightness = (Math.max(...rgb) + Math.min(...rgb)) / 2;
  const iris = lightness > LIGHTNESS[0] && lightness < LIGHTNESS[1] ? 1 : 0;
  return rgb.map((c, i) => Math.min(1, (c + (c * tint[i] - c) * iris) / CURVE_KNEE));
}

/// GLSL declaring `float across`: how far vMapUv lies across from the spoke of the eye it is on.
export const EYEFACE_ACROSS_GLSL = `float across;
  {
    vec2 fromMiddle = vMapUv - 0.5;
    float spoke = floor(atan(fromMiddle.y, fromMiddle.x) / ${f(2 * Math.PI / FLOWER_EYES)} + 0.5) * ${f(2 * Math.PI / FLOWER_EYES)};
    across = abs(dot(fromMiddle, vec2(-sin(spoke), cos(spoke))));
  }`;

/// The same in JS, for the tests: `uv` [u, v].
export function acrossSpoke([u, v]) {
  const x = u - 0.5, y = v - 0.5, step = 2 * Math.PI / FLOWER_EYES;
  const spoke = Math.round(Math.atan2(y, x) / step) * step;
  return Math.abs(-x * Math.sin(spoke) + y * Math.cos(spoke));
}
