// The shoggoth's eyes as its shaders draw them, from the textures scripts/draw_shoggoth_eyes.py
// draws: the eyes on its body and tentacles (material `shoggoth eye`) and the eight-eyed flower
// under its mask (`shoggoth eyeface`). Each texture is two panels side by side: the open eye
// without its iris (ink, white, fold), and the iris with its slit pupil and glint. Every frame
// the shader puts the iris on the white where the shoggoth is looking, scaled by `uIris`, then
// closes lids over the white, all in whole texels, so the eyes stay pixel art.
//
// An eye is an almond: at s along it (-1 .. 1, tip to tip) its white reaches almond(s) either side
// of its middle line, t in units of its half-height. Lids come down and up over the white to meet
// on a seam (`lidEdges`): how far they have come (closed), how much of the way the upper one comes
// (split), the seam's curve (bent like ^ when happy, like a smile when asleep) and how flat the
// upper lid's edge is (a heavy, drowsy lid). The numbers below are the drawing script's; the
// tests decode the textures and fail if they disagree.
//
// The flower then takes the shade of its Blender graph (docs/shoggoth-shader-nodes.png): texels
// whose HSL lightness lies strictly between LIGHTNESS[0] and LIGHTNESS[1] (its irises) are
// multiplied by the tint; an RGB curve through (0, 0) and (CURVE_KNEE, 1), flat after, brightens
// everything; alpha over ALPHA_CUT is opaque and the rest is cut, as is anything outside the
// texture (Blender's Clip). One change: only texels from the iris layer take the tint. The drawn
// art keeps the graph's own split (irises inside the band, everything else outside it), but
// the mip levels a small flower is drawn from blend ink and white into the band. Blender's curve
// is a smooth spline through those points; here it is the straight line min(1, x / CURVE_KNEE).
// The art is greyscale, so Display P3 and sRGB read it alike. The body's eyes take no tint, as in
// the owner's model.

export const LIGHTNESS = [0.15, 0.37];
export const CURVE_KNEE = 0.25;
export const ALPHA_CUT = 0.5;
export const DEFAULT_TINT = '#ff0000';

export const ALMOND_POWER = 0.75;
// `size` texels a panel; lengths are shares of a panel. `look` is how far an iris moves, along
// and across its eye, looking hard one way.
export const BODY_EYE = { size: 64, halfLength: 0.44, halfHeight: 0.26, look: [0.1, 0.045] };
export const FLOWER = { size: 128, eyes: 8, radius: 0.3, halfLength: 0.165, halfHeight: 0.085, look: [0.04, 0.016] };
// Open lids rest this far (in half-heights) outside the white, so they cover none of it.
const LID_CLEAR = 0.02;
// Linear colours of a lid: its skin, the crease just above its edge, and the lash along it.
const LID = [0.24, 0.23, 0.26], CREASE = [0.1, 0.095, 0.11], LASH = [0.012, 0.012, 0.014];

/// `#rrggbb` (any case) as given, lower-cased; anything else is the default red.
export function parseTint(value) {
  return typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value.trim()) ? value.trim().toLowerCase() : DEFAULT_TINT;
}

export function almond(s) {
  return Math.abs(s) < 1 ? (1 - s * s) ** ALMOND_POWER : 0;
}

/// Lids `{ closed, split, curve, flat }`: where the upper and lower lids' edges cross an eye at s,
/// in half-heights from its middle line. A texel at t is under the upper lid at or above `upper`,
/// under the lower one below `lower`; closed, they meet on the seam, so every texel is under one.
export function lidEdges(s, { closed, split, curve, flat }) {
  const h = almond(s);
  const seam = 1 - 2 * split + 0.35 * curve * h;
  return {
    upper: (1 - closed) * (h + (1 - h) * flat + LID_CLEAR) + closed * seam,
    lower: -(1 - closed) * (h + LID_CLEAR) + closed * seam,
  };
}

/// The texel of a panel holding `uv` ([u, v], 0 .. 1), in its eye's frame: { s, t } (t toward the
/// top of the image on the body's eye, turning with the spoke on the flower).
export function eyeAt(eye, [u, v]) {
  const qu = (Math.floor(Math.min(u, 0.99999) * eye.size) + 0.5) / eye.size;
  const qv = (Math.floor(Math.min(v, 0.99999) * eye.size) + 0.5) / eye.size;
  let dir = [1, 0], centre = [0.5, 0.5];
  if (eye.eyes) {
    const step = (2 * Math.PI) / eye.eyes;
    const spoke = Math.floor(Math.atan2(qv - 0.5, qu - 0.5) / step + 0.5) * step;
    dir = [Math.cos(spoke), Math.sin(spoke)];
    centre = [0.5 + eye.radius * dir[0], 0.5 + eye.radius * dir[1]];
  }
  const du = qu - centre[0], dv = qv - centre[1];
  return { s: (du * dir[0] + dv * dir[1]) / eye.halfLength, t: (du * dir[1] - dv * dir[0]) / eye.halfHeight };
}

/// The flower's Blender shade in JS: `rgb` linear 0..1, `tint` linear 0..1; returns the linear base colour.
export function eyefaceShade(rgb, tint) {
  const lightness = (Math.max(...rgb) + Math.min(...rgb)) / 2;
  const iris = lightness > LIGHTNESS[0] && lightness < LIGHTNESS[1] ? 1 : 0;
  return rgb.map((c, i) => Math.min(1, (c + (c * tint[i] - c) * iris) / CURVE_KNEE));
}

const f = (x) => x.toFixed(4);
const vec3 = ([r, g, b]) => `vec3(${f(r)}, ${f(g)}, ${f(b)})`;

/// Vertex GLSL for both eye materials: needs attributes shogEyeU and shogEyeV (each decal's
/// texture axes in body space, from `decalAxes`) and `uniform vec3 uGaze` (where it looks, in body
/// space); gives the fragment `vLook`, the look along the texture's u and v.
export const EYE_VERTEX_HEAD = 'attribute vec3 shogEyeU, shogEyeV;\nuniform vec3 uGaze;\nvarying vec2 vLook;\n';
export const EYE_VERTEX = 'vLook = vec2(dot(uGaze, shogEyeU), dot(uGaze, shogEyeV));';
export const EYE_FRAGMENT_HEAD = 'varying vec2 vLook;\nuniform vec4 uLids;\nuniform float uIris;\n';

/// GLSL replacing three's map_fragment for an eye material. Declares `shogLid` (1 under a lid),
/// `shogBare` (1 on bare white or iris) and `shogRing` (0 at the eye's middle, 1 at its tips).
/// Needs uLids (closed, split, curve, flat), uIris, vLook, and for the flower `uniform vec3 uTint`.
export function eyeMapGlsl(eye) {
  const frame = eye.eyes
    ? `vec2 fromMiddle = q - 0.5;
    float spoke = floor(atan(fromMiddle.y, fromMiddle.x) / ${f(2 * Math.PI / eye.eyes)} + 0.5) * ${f(2 * Math.PI / eye.eyes)};
    vec2 dir = vec2(cos(spoke), sin(spoke));
    vec2 centre = 0.5 + ${f(eye.radius)} * dir;`
    : 'vec2 dir = vec2(1.0, 0.0);\n    vec2 centre = vec2(0.5);';
  // The flower's Blender graph, except that only the iris layer's texels can take the tint: blended
  // mip levels of ink and white land in the tint band too, and would speckle its outlines.
  const shade = eye.eyes
    ? `{
      float lightness = 0.5 * (max(max(c.r, c.g), c.b) + min(min(c.r, c.g), c.b));
      float tinted = fromIris * (1.0 - step(lightness, ${f(LIGHTNESS[0])})) * (1.0 - step(${f(LIGHTNESS[1])}, lightness));
      c = mix(c, c * uTint, tinted);
      c = min(vec3(1.0), c / ${f(CURVE_KNEE)});
    }`
    : '';
  return `float shogLid = 0.0, shogBare = 0.0, shogRing = 1.0;
#ifdef USE_MAP
  {
    // Clip, as in Blender (glTF can only say clamp, which smears edge texels across each decal).
    bool inside = all(greaterThanEqual(vMapUv, vec2(0.0))) && all(lessThanEqual(vMapUv, vec2(1.0)));
    // Everything below is worked out on the texel grid of the mip level the sampler would read, so
    // a small, far eye still closes whole.
    vec2 footprint = vMapUv * ${f(eye.size)};
    float lod = clamp(floor(0.5 + 0.5 * log2(max(1.0, max(dot(dFdx(footprint), dFdx(footprint)), dot(dFdy(footprint), dFdy(footprint)))))), 0.0, ${f(Math.log2(eye.size) - 3)});
    float n = ${f(eye.size)} / exp2(lod);
    vec2 uv = clamp(vMapUv, vec2(0.5 / n), vec2(1.0 - 0.5 / n));
    vec2 q = (floor(uv * n) + 0.5) / n;
    ${frame}
    vec2 across = vec2(dir.y, -dir.x);
    vec2 d = q - centre;
    float s = dot(d, dir) / ${f(eye.halfLength)}, t = dot(d, across) / ${f(eye.halfHeight)};
    shogRing = clamp(length(vec2(s, t)), 0.0, 1.0);
    vec4 base = textureLod(map, vec2(q.x * 0.5, q.y), lod);
    bool white = base.a > 0.5 && base.g > 0.4;
    // The iris, moved toward the look in whole texels, as far as its eye lets it.
    vec2 look = clamp(dot(vLook, dir), -1.0, 1.0) * ${f(eye.look[0])} * dir + clamp(dot(vLook, across), -1.0, 1.0) * ${f(eye.look[1])} * across;
    look = floor(look * n + 0.5) / n;
    vec2 irisAt = clamp((floor((centre + (q - look - centre) / uIris) * n) + 0.5) / n, vec2(0.5 / n), vec2(1.0 - 0.5 / n));
    vec4 iris = textureLod(map, vec2(0.5 + irisAt.x * 0.5, irisAt.y), lod);
    float fromIris = white && iris.a > 0.5 ? 1.0 : 0.0;
    vec3 c = mix(base.rgb, iris.rgb, fromIris);
    ${shade}
    if (white) {
      float h = pow(max(0.0, 1.0 - s * s), ${f(ALMOND_POWER)});
      float seam = 1.0 - 2.0 * uLids.y + 0.35 * uLids.z * h;
      float upper = (1.0 - uLids.x) * (h + (1.0 - h) * uLids.w + ${f(LID_CLEAR)}) + uLids.x * seam;
      float lower = -(1.0 - uLids.x) * (h + ${f(LID_CLEAR)}) + uLids.x * seam;
      float under = t >= upper ? t - upper : t < lower ? lower - t : -1.0;
      if (under >= 0.0) {
        shogLid = 1.0;
        float texels = under * ${f(eye.halfHeight)} * n;
        c = texels < 1.0 ? ${vec3(LASH)} : texels < 2.0 ? ${vec3(CREASE)} : ${vec3(LID)};
      } else {
        shogBare = 1.0;
      }
    }
    diffuseColor.rgb *= c;
    diffuseColor.a *= inside ? base.a : 0.0;
  }
#endif`;
}

/// Each eye decal's texture axes in body space, for the look: the eye meshes are patches of quads,
/// one patch per eye, whose positions follow their uv about linearly; this fits position = o + u A
/// + v B to each patch, weighted to the eye in its middle, and gives every vertex its patch's unit
/// A and B. `position` and `uv` are flat arrays (3 and 2 a vertex), `index` the triangles.
export function decalAxes(position, uv, index) {
  const count = position.length / 3;
  const ids = new Map(), at = new Int32Array(count);
  for (let i = 0; i < count; i += 1) {
    const key = `${position[3 * i].toFixed(5)},${position[3 * i + 1].toFixed(5)},${position[3 * i + 2].toFixed(5)}`;
    if (!ids.has(key)) ids.set(key, ids.size);
    at[i] = ids.get(key);
  }
  const parent = Int32Array.from({ length: ids.size }, (_, i) => i);
  const root = (x) => { while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; };
  for (let k = 0; k < index.length; k += 3) {
    const a = root(at[index[k]]), b = root(at[index[k + 1]]), c = root(at[index[k + 2]]);
    parent[a] = b; parent[root(c)] = root(b);
  }
  const patches = new Map();
  for (let i = 0; i < count; i += 1) {
    const r = root(at[i]);
    if (!patches.has(r)) patches.set(r, []);
    patches.get(r).push(i);
  }
  const eyeU = new Float32Array(3 * count), eyeV = new Float32Array(3 * count);
  for (const members of patches.values()) {
    // Weighted least squares on [1, u, v]: the normal equations, one right-hand side per axis.
    const m = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], rhs = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
    for (const i of members) {
      const u = uv[2 * i], v = uv[2 * i + 1];
      const w = Math.exp(-(((u - 0.5) ** 2 + (v - 0.5) ** 2) / 0.5));
      const x = [1, u, v];
      for (let r = 0; r < 3; r += 1) {
        for (let c = 0; c < 3; c += 1) m[r][c] += w * x[r] * x[c];
        for (let k = 0; k < 3; k += 1) rhs[k][r] += w * x[r] * position[3 * i + k];
      }
    }
    const solved = rhs.map((b) => solve3(m, b));
    const axis = (j) => { const a = [solved[0][j], solved[1][j], solved[2][j]]; const l = Math.hypot(...a) || 1; return a.map((x) => x / l); };
    const A = axis(1), B = axis(2);
    for (const i of members) { eyeU.set(A, 3 * i); eyeV.set(B, 3 * i); }
  }
  return { eyeU, eyeV, patches: patches.size };
}

function solve3(m, b) {
  const a = m.map((row, r) => [...row, b[r]]);
  for (let c = 0; c < 3; c += 1) {
    let pivot = c;
    for (let r = c + 1; r < 3; r += 1) if (Math.abs(a[r][c]) > Math.abs(a[pivot][c])) pivot = r;
    [a[c], a[pivot]] = [a[pivot], a[c]];
    if (Math.abs(a[c][c]) < 1e-12) return [0, 0, 0];
    for (let r = 0; r < 3; r += 1) {
      if (r === c) continue;
      const k = a[r][c] / a[c][c];
      for (let j = c; j < 4; j += 1) a[r][j] -= k * a[c][j];
    }
  }
  return [a[0][3] / a[0][0], a[1][3] / a[1][1], a[2][3] / a[2][2]];
}
