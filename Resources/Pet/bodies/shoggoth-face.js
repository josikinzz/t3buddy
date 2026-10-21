// The shoggoth's face: what each state does to its eyes and to the two U's of its "UwU" mask, as
// one table. `faceFor(pose)` lays the rows over Idle in order, each by how much its state holds
// now, so a later row wins where both hold and every change is a blend: the pose's weights all ease
// (mood springs, eased sleep, pulses), so the face never steps.
//
// Eyes: `close` is how far its lids come down at least (the brain's own lid, with its blinks, can
// close them further), `split` how much of the way the upper lid comes, `curve` the seam's bend
// (1 a happy ^, -1 a sleepy smile), `flat` how flat the upper lid's edge is (heavy, drowsy), `iris`
// the iris's size. Mask: the glyph each U becomes, `glow` how much it lights, `wobble` how much it
// trembles.
//
// The mask's w is never touched: `createMask` keeps it as its own mesh on the text's own vertex
// arrays and draws each U anew as a lit stroke.

import * as THREE from 'three';
import { tremble } from '../motion.js';

const OPEN = { close: 0, split: 0.62, curve: 0, flat: 0, iris: 1 };

export const FACES = [
  { name: 'idle',      when: () => 1,                                       eyes: OPEN,                                                         mask: { glyph: 'u' } },
  { name: 'dozy',      when: (P) => P.dozy,                                 eyes: { close: 0.42, split: 0.75, curve: 0, flat: 0.8, iris: 1 },   mask: { glyph: 'drowsy' } },
  { name: 'focused',   when: (P) => P.focused,                              eyes: { close: 0.12, split: 0.7, curve: 0, flat: 0.45, iris: 0.92 }, mask: { glyph: 'narrow' } },
  { name: 'power',     when: (P) => P.eyeLight,                             eyes: { close: 0, split: 0.62, curve: 0, flat: 0, iris: 1.12 },     mask: { glyph: 'wide', glow: 1 } },
  { name: 'fretful',   when: (P) => P.fretful,                              eyes: { close: 0, split: 0.62, curve: -0.2, flat: 0, iris: 0.82 },  mask: { glyph: 'worried', wobble: 1 } },
  { name: 'satisfied', when: (P) => Math.max(P.satisfied, P.odd, P.D),      eyes: { close: 0.55, split: 0.3, curve: 1, flat: 0, iris: 1 },      mask: { glyph: 'arc' } },
  { name: 'petted',    when: (P) => P.L,                                    eyes: { close: 0.62, split: 0.3, curve: 1, flat: 0, iris: 1 },      mask: { glyph: 'arc' } },
  { name: 'sleep',     when: (P) => P.S,                                    eyes: { close: 1, split: 0.75, curve: -1, flat: 0.5, iris: 1 },     mask: { glyph: 'shut' } },
  { name: 'crying',    when: (P) => P.sad,                                  eyes: { close: 0.5, split: 0.6, curve: -0.7, flat: 0, iris: 0.9 },  mask: { glyph: 'tears', wobble: 0.4 } },
  { name: 'surprised', when: (P) => Math.max(P.startle, P.flinch, P.psy),   eyes: { close: 0, split: 0.62, curve: 0, flat: 0, iris: 0.72 },     mask: { glyph: 'o' } },
  { name: 'dizzy',     when: (P) => Math.max(P.dizzy, P.spinning),          eyes: { close: 0.15, split: 0.62, curve: 0, flat: 0, iris: 0.85 },  mask: { glyph: 'spiral' } },
];

// ------------------------------------------------------------------ glyphs
//
// A glyph is drawn in units of half the U's height, x right and y up, for the mask's left eye (the
// right one is its mirror), as two strokes: a main one of MAIN points and an extra one (a brow, a
// lid line, a tear) of EXTRA, joined by two points of no width so the pen lifts between them. Each
// point has a width, a share of the U's stroke; a glyph without an extra stroke shrinks it to
// nothing at its main stroke's end. Points lie evenly along each stroke, so any two glyphs blend
// point by point.

const MAIN = 36, EXTRA = 12;
export const GLYPH_POINTS = MAIN + 2 + EXTRA;

const arc = (cx, cy, rx, ry, from, to, n = 24) => Array.from({ length: n + 1 }, (_, i) => {
  const a = from + ((to - from) * i) / n;
  return [cx + rx * Math.cos(a), cy + ry * Math.sin(a)];
});
const line = (a, b) => [a, b];
const join = (...parts) => parts.flat().filter((p, i, all) => i === 0 || p[0] !== all[i - 1][0] || p[1] !== all[i - 1][1]);
const PI = Math.PI;

const GLYPHS = {
  // The font's U: straight sides into a round bottom.
  u: { main: join(line([-0.7, 0.85], [-0.7, -0.15]), arc(0, -0.15, 0.7, 0.7, PI, 2 * PI), line([0.7, -0.15], [0.7, 0.85])) },
  // Half shut: the lower half of the eye under a flat lid line.
  drowsy: { main: arc(0, 0.02, 0.7, 0.5, PI, 2 * PI), extra: { points: line([-0.82, 0.02], [0.82, 0.02]) } },
  // Shut: a shallow smile of a closed eye.
  shut: { main: arc(0, 0.25, 0.75, 0.5, PI * 1.12, PI * 1.88) },
  // Narrowed under a brow sloping down toward the middle of the mask.
  narrow: { main: arc(0, 0.2, 0.68, 0.72, PI, 2 * PI), extra: { points: line([-0.85, 0.6], [0.8, 0.18]) } },
  // Happy: ^, an upturned arc.
  arc: { main: join(line([-0.7, -0.45], [-0.7, -0.05]), arc(0, -0.05, 0.7, 0.75, PI, 0), line([0.7, -0.05], [0.7, -0.45])) },
  // Worried: a small round eye under a brow raised toward the middle.
  worried: { main: arc(0, -0.15, 0.5, 0.55, PI, 3 * PI), extra: { points: line([-0.8, 0.5], [0.7, 1.02]) } },
  // Crying: a shut eye with a stream running down from it, a drop at its end.
  tears: { main: arc(0, 0.75, 0.8, 0.28, PI, 2 * PI), extra: { points: line([0.05, 0.42], [0.05, -0.95]), width: (u) => 0.55 + 0.9 * u ** 4 } },
  // Wide and round, lit at full power.
  wide: { main: arc(0, 0, 0.82, 0.85, PI, 3 * PI) },
  // A small o.
  o: { main: arc(0, 0.05, 0.48, 0.52, PI, 3 * PI) },
  // Dizzy: a spiral, two turns in.
  spiral: { main: Array.from({ length: 97 }, (_, i) => { const u = i / 96, a = PI + 4 * PI * u, r = 0.85 * (1 - 0.82 * u); return [r * Math.cos(a), r * Math.sin(a)]; }) },
};

/// `points` resampled to n points evenly along its length.
function resample(points, n) {
  const lengths = [0];
  for (let i = 1; i < points.length; i += 1) lengths.push(lengths[i - 1] + Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]));
  const total = lengths.at(-1), out = [];
  for (let k = 0, j = 0; k < n; k += 1) {
    const at = (total * k) / (n - 1);
    while (j < points.length - 2 && lengths[j + 1] < at) j += 1;
    const u = (at - lengths[j]) / (lengths[j + 1] - lengths[j] || 1);
    out.push([points[j][0] + u * (points[j + 1][0] - points[j][0]), points[j][1] + u * (points[j + 1][1] - points[j][1])]);
  }
  return out;
}

/// A glyph as GLYPH_POINTS [x, y, width] points.
function glyphPoints({ main, extra }) {
  const stroke = resample(main, MAIN).map(([x, y]) => [x, y, 1]);
  const end = stroke.at(-1);
  const more = extra ? resample(extra.points, EXTRA).map(([x, y], i) => [x, y, extra.width ? extra.width(i / (EXTRA - 1)) : 1]) : Array.from({ length: EXTRA }, () => [end[0], end[1], 0]);
  return [...stroke, [end[0], end[1], 0], [more[0][0], more[0][1], 0], ...more];
}

export const GLYPH_SHAPES = Object.fromEntries(Object.entries(GLYPHS).map(([name, g]) => [name, glyphPoints(g)]));

// ------------------------------------------------------------------- blend

const mix = (a, b, u) => a + (b - a) * u;
const clamp01 = (x) => Math.min(1, Math.max(0, x));

/// The face for a pose: { eyes, mask: { points, glow, wobble }, weights, name } with `name` the
/// row that shows most.
export function faceFor(P) {
  const eyes = { ...OPEN };
  const points = GLYPH_SHAPES.u.map((p) => [...p]);
  let glow = 0, wobble = 0;
  const weights = {};
  let name = 'idle', best = 0;
  let left = 1;
  for (let i = FACES.length - 1; i >= 0; i -= 1) {
    const row = FACES[i];
    const w = clamp01(row.when(P) || 0);
    weights[row.name] = w * left;
    left *= 1 - w;
  }
  for (const row of FACES) {
    const w = row.name === 'idle' ? 1 : clamp01(row.when(P) || 0);
    if (weights[row.name] > best) { best = weights[row.name]; name = row.name; }
    if (row.name === 'idle' || w <= 0) continue;
    for (const key of Object.keys(eyes)) eyes[key] = mix(eyes[key], row.eyes[key], w);
    const shape = GLYPH_SHAPES[row.mask.glyph];
    for (let k = 0; k < points.length; k += 1) for (let c = 0; c < 3; c += 1) points[k][c] = mix(points[k][c], shape[k][c], w);
    glow = mix(glow, row.mask.glow ?? 0, w);
    wobble = mix(wobble, row.mask.wobble ?? 0, w);
  }
  return { eyes, mask: { points, glow, wobble }, weights, name };
}

// -------------------------------------------------------------------- mask

const WARM = new THREE.Color(1, 0.86, 0.45);

/// The mask's text split into its glyphs: triangles grouped by the vertices they share, left to
/// right. Gives the w's index and each U's box in the text's own plane (x across, z down).
export function splitText(geometry) {
  const index = geometry.index.array, position = geometry.attributes.position;
  const parent = Int32Array.from({ length: position.count }, (_, i) => i);
  const root = (x) => { while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; };
  for (let k = 0; k < index.length; k += 3) { parent[root(index[k])] = root(index[k + 1]); parent[root(index[k + 1])] = root(index[k + 2]); }
  const glyphs = new Map();
  for (let k = 0; k < index.length; k += 3) {
    const r = root(index[k]);
    if (!glyphs.has(r)) glyphs.set(r, { triangles: [], box: new THREE.Box3() });
    const g = glyphs.get(r);
    g.triangles.push(index[k], index[k + 1], index[k + 2]);
    for (let j = 0; j < 3; j += 1) g.box.expandByPoint(new THREE.Vector3().fromBufferAttribute(position, index[k + j]));
  }
  const ordered = [...glyphs.values()].sort((a, b) => a.box.min.x - b.box.min.x);
  if (ordered.length !== 3) return null;
  return { w: ordered[1].triangles, eyes: [ordered[0].box, ordered[2].box] };
}

/// Splits the mask text mesh: the w stays in `text`, on its own vertex arrays, and each U becomes
/// a stroke whose shape `step` sets each frame. Returns null (and leaves the text alone) if the
/// text is not three glyphs.
export function createMask(text) {
  const split = text?.geometry?.index ? splitText(text.geometry) : null;
  if (!split) return null;
  const rest = text.geometry;
  const w = new THREE.BufferGeometry();
  for (const [key, attribute] of Object.entries(rest.attributes)) w.setAttribute(key, attribute);
  w.setIndex(split.w);
  text.geometry = w;

  const material = text.material.clone();
  material.emissive = new THREE.Color(0, 0, 0);
  const rows = 3;   // across a stroke: one edge, its raised middle, the other edge
  const strokes = split.eyes.map((box, side) => {
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute(new Float32Array(GLYPH_POINTS * rows * 3), 3));
    geometry.setAttribute('normal', new THREE.Float32BufferAttribute(new Float32Array(GLYPH_POINTS * rows * 3), 3));
    const index = [];
    for (let i = 0; i < GLYPH_POINTS - 1; i += 1) {
      for (let r = 0; r < rows - 1; r += 1) {
        const a = i * rows + r, b = a + 1, c = a + rows, d = c + 1;
        index.push(a, c, b, b, c, d);
      }
    }
    geometry.setIndex(index);
    const mesh = new THREE.Mesh(geometry, material);
    mesh.name = side ? 'ShoggothMaskRightEye' : 'ShoggothMaskLeftEye';
    mesh.frustumCulled = false;
    text.add(mesh);
    const size = box.getSize(new THREE.Vector3()), centre = box.getCenter(new THREE.Vector3());
    return { geometry, mesh, centre, unit: size.z / 2, mirror: side ? -1 : 1 };
  });
  // The font's stroke is about 0.3 half-heights wide.
  const STROKE = 0.3;

  /// Draws the face's mask glyphs at `t`; `reduced` (Reduce Motion) holds them still.
  function step(face, t, reduced = false) {
    const { points, glow, wobble } = face.mask;
    material.emissive.copy(WARM).multiplyScalar(1.6 * glow);
    for (const [side, s] of strokes.entries()) {
      const shake = reduced ? 0 : wobble * 0.09 * tremble(t, 17, side * 2.1);
      const cos = Math.cos(shake), sin = Math.sin(shake);
      const pos = s.geometry.attributes.position, nor = s.geometry.attributes.normal;
      const at = (k) => { const [x, y] = points[k]; return [s.mirror * (x * cos - y * sin), x * sin + y * cos]; };
      for (let k = 0; k < GLYPH_POINTS; k += 1) {
        const [x, y] = at(k);
        const [ax, ay] = at(Math.max(0, k - 1)), [bx, by] = at(Math.min(GLYPH_POINTS - 1, k + 1));
        let tx = bx - ax, ty = by - ay;
        const tl = Math.hypot(tx, ty) || 1;
        tx /= tl; ty /= tl;
        const half = 0.5 * STROKE * points[k][2];
        // Glyph y is up the mask; in the text's plane that is -z, and +y faces out of the mask.
        const px = s.centre.x + s.unit * x, pz = s.centre.z - s.unit * y;
        const nx = -ty, nz = -tx;
        const lift = 0.45 * half * s.unit;
        for (let r = 0; r < rows; r += 1) {
          const across = r - 1;
          pos.setXYZ(k * rows + r, px + across * nx * half * s.unit, across ? 0 : lift, pz + across * nz * half * s.unit);
          const l = Math.hypot(0.8 * across, 1);
          nor.setXYZ(k * rows + r, (across * nx * 0.8) / l, 1 / l, (across * nz * 0.8) / l);
        }
      }
      pos.needsUpdate = true;
      nor.needsUpdate = true;
    }
  }

  return { step, strokes: strokes.map((s) => s.mesh) };
}
