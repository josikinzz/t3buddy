import { test } from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { readFileSync } from 'node:fs';
import { inflateSync } from 'node:zlib';
import { installFakeDom } from './fake-dom.mjs';

register('./three-hooks.mjs', import.meta.url);
const dom = installFakeDom({ width: 1600, height: 1200 });
const { BODIES, DEFAULT_BODY, bodyFor } = await import('../../Resources/Pet/bodies/index.js');
const { createOrbit } = await import('../../Resources/Pet/orbit.js');
const { eyefaceShade, parseTint, DEFAULT_TINT, LIGHTNESS, CURVE_KNEE, ALMOND_POWER, BODY_EYE, FLOWER, almond, lidEdges, eyeAt, eyeMapGlsl, decalAxes } = await import('../../Resources/Pet/bodies/shoggoth-eyes.js');
const { FACES, faceFor, GLYPH_SHAPES, createMask } = await import('../../Resources/Pet/bodies/shoggoth-face.js');
const THREE = await import('three');

const finite = (...values) => values.every((v) => typeof v === 'number' && Number.isFinite(v));

test('the pet picker shows the shoggoth for "shoggoth" and T3boii for anything else', () => {
  assert.equal(DEFAULT_BODY, 't3boii');
  assert.equal(bodyFor('shoggoth'), BODIES.shoggoth);
  assert.equal(bodyFor('t3boii'), BODIES.t3boii);
  for (const kind of [undefined, null, '', 'Shoggoth', 'dragon', '__proto__', 'toString', 'constructor', 42, {}]) {
    assert.equal(bodyFor(kind), BODIES.t3boii, `${String(kind)} gets T3boii`);
  }
});

test('every pet declares the ball, top, soles, frame and the forehead and mouth the shared systems place things by', () => {
  assert.ok(Object.keys(BODIES).length >= 2);
  for (const [key, body] of Object.entries(BODIES)) {
    assert.equal(body.kind, key, `${key} is registered under its own kind`);
    assert.ok(typeof body.name === 'string' && body.name, `${key} has a name for the menu`);
    assert.equal(typeof body.load, 'function', `${key} can load`);
    const { ball, top, soles, frame, anchors } = body;
    assert.ok(finite(ball?.x, ball?.y, ball?.r) && ball.r > 0, `${key} has a ball`);
    assert.ok(finite(top) && top > ball.y && top < ball.y + 1.6 * ball.r, `${key}'s top is above its middle, near its ball's`);
    assert.ok(finite(soles) && soles > 0, `${key} has soles below its middle`);
    assert.ok(finite(frame) && frame > 0 && frame <= 1, `${key} is framed no taller than T3boii`);
    const base = ball.y - soles * ball.r;
    for (const name of ['forehead', 'mouth']) {
      const a = anchors?.[name];
      assert.ok(a && finite(a.x, a.y), `${key} has a ${name}`);
      assert.ok(Math.abs(a.x - ball.x) < ball.r && a.y > base && a.y < top, `${key}'s ${name} is on it`);
    }
    assert.ok(anchors.forehead.y > anchors.mouth.y, `${key}'s forehead is above its mouth`);
  }
});

test('the rings tuck about a third of an orb behind each pet\'s top and pass in front of its lower body', () => {
  for (const [key, body] of Object.entries(BODIES)) {
    const { ball, top, soles, frame } = body;
    const ppu = 330 * frame, hub = { x: 800, y: 600, r: ball.r * ppu };
    const topPage = hub.y - (top - ball.y) * ppu, basePage = hub.y + soles * hub.r;
    const orbit = createOrbit({
      body: { height: (top - (ball.y - soles * ball.r)) * ppu },
      ball: () => ({ ...hub }),
      soles,
      foreheadAnchor: () => ({ page: { x: hub.x, y: hub.y - hub.r * 0.6 }, world: { x: 0, y: 1, z: 0.5 } }),
      mouthAnchor: () => ({ x: hub.x, y: hub.y + hub.r * 0.2 }),
      setHitRegions() {},
      post() {},
      front: dom.element(),
      back: dom.element(),
    });
    orbit.update({ orbs: [{ id: 't3:a', parentId: null, source: 't3', projectIcon: { kind: 'monogram', text: 'DA', color: '#5b8def' }, provider: 'codex', state: 'active', label: 'demo-app' }] });
    let t = orbit.clock;
    for (const end = t + 2.5; t < end; t += 1 / 30) orbit.frame(t, 1 / 30);
    let high = null, low = null;
    for (const end = t + 23; t < end; t += 1 / 30) {
      orbit.frame(t, 1 / 30);
      const o = orbit.state()[0];
      if (!high || o.y < high.y) high = o;
      if (!low || o.y > low.y) low = o;
    }
    const size = orbit.geometry.orb * high.scale;
    const tucked = (high.y + size / 2 - topPage) / size;
    assert.ok(high.depth < 0, `${key}: over the top, the orb is behind it`);
    assert.ok(tucked > 0.22 && tucked < 0.48, `${key}: over the top, about a third of the orb is behind it (${tucked.toFixed(2)})`);
    assert.ok(low.depth > 0, `${key}: at the bottom, the orb is in front`);
    assert.ok(low.y < basePage && low.y > hub.y + hub.r * 0.5, `${key}: the ring's bottom crosses its lower body, above its underside`);
  }
});

test('the shoggoth\'s eye-flower turns its mid-grey irises the tint and leaves outlines and whites alone', () => {
  const red = [1, 0, 0], green = [0, 1, 0];
  assert.deepEqual(eyefaceShade([0.25, 0.25, 0.25], red), [1, 0, 0]);
  assert.deepEqual(eyefaceShade([0.25, 0.25, 0.25], green), [0, 1, 0]);
  assert.deepEqual(eyefaceShade([0.05, 0.05, 0.05], red).map((c) => +c.toFixed(6)), [0.2, 0.2, 0.2]);
  assert.deepEqual(eyefaceShade([0.8, 0.8, 0.8], red), [1, 1, 1]);
  for (const edge of LIGHTNESS) {
    const shade = eyefaceShade([edge, edge, edge], red);
    assert.ok(shade[1] > 0 && shade[1] === shade[0], `lightness ${edge} is not an iris`);
  }
  // The shader is built from the same numbers, so this sum is the shader's.
  for (const n of [...LIGHTNESS, CURVE_KNEE]) assert.ok(eyeMapGlsl(FLOWER).includes(n.toFixed(4)), `the GLSL uses ${n}`);
  assert.ok(!eyeMapGlsl(BODY_EYE).includes('uTint'), 'the body\'s eyes take no tint');
});

test('a tint is #rrggbb, lower-cased, or the default red', () => {
  assert.equal(DEFAULT_TINT, '#ff0000');
  assert.equal(parseTint('#00FF88'), '#00ff88');
  assert.equal(parseTint(' #a970ff '), '#a970ff');
  for (const bad of ['', 'red', '#fff', '#gg0000', 'ff0000', '#ff00001', null, undefined, 42]) {
    assert.equal(parseTint(bad), DEFAULT_TINT, `${String(bad)} is not a tint`);
  }
});

// ------------------------------------------------------------ shoggoth.glb

const GLB = readFileSync(new URL('../../Resources/Pet/shoggoth.glb', import.meta.url));
const GLTF = JSON.parse(GLB.subarray(20, 20 + GLB.readUInt32LE(12)).toString());
const BIN = GLB.subarray(20 + GLB.readUInt32LE(12) + 8);
const bytesOf = (view) => BIN.subarray(view.byteOffset ?? 0, (view.byteOffset ?? 0) + view.byteLength);

/// An accessor of shoggoth.glb as a flat typed array.
function accessor(index) {
  const a = GLTF.accessors[index], view = GLTF.bufferViews[a.bufferView];
  const Type = { 5126: Float32Array, 5125: Uint32Array, 5123: Uint16Array }[a.componentType];
  const width = { SCALAR: 1, VEC2: 2, VEC3: 3 }[a.type];
  const bytes = bytesOf(view).subarray(a.byteOffset ?? 0);
  return Type.from({ length: a.count * width }, (_, i) => bytes[`read${Type === Float32Array ? 'FloatLE' : Type === Uint32Array ? 'UInt32LE' : 'UInt16LE'}`](i * Type.BYTES_PER_ELEMENT));
}

/// The primitive of shoggoth.glb drawn with `material`, as flat arrays.
function primitive(material) {
  const m = GLTF.materials.findIndex((x) => x.name === material);
  const p = GLTF.meshes.flatMap((mesh) => mesh.primitives).find((x) => x.material === m);
  return { position: accessor(p.attributes.POSITION), normal: accessor(p.attributes.NORMAL), uv: accessor(p.attributes.TEXCOORD_0), index: accessor(p.indices) };
}

/// An image of shoggoth.glb, decoded: { width, height, at(x, y) -> [r, g, b, a] (0..255) }.
function image(name) {
  const png = bytesOf(GLTF.bufferViews[GLTF.images.find((i) => i.name === name).bufferView]);
  let width, height, depth, colour, idat = [];
  for (let at = 8; at < png.length;) {
    const length = png.readUInt32BE(at), kind = png.toString('latin1', at + 4, at + 8), body = png.subarray(at + 8, at + 8 + length);
    if (kind === 'IHDR') [width, height, depth, colour] = [body.readUInt32BE(0), body.readUInt32BE(4), body[8], body[9]];
    if (kind === 'IDAT') idat.push(body);
    at += 12 + length;
  }
  assert.ok(depth === 8 && colour === 6, `${name} is 8-bit RGBA`);
  const raw = inflateSync(Buffer.concat(idat)), stride = width * 4, pixels = new Uint8Array(width * height * 4);
  let previous = new Uint8Array(stride);
  for (let y = 0; y < height; y += 1) {
    const filter = raw[y * (stride + 1)], line = Uint8Array.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let x = 0; x < stride; x += 1) {
      const a = x >= 4 ? line[x - 4] : 0, b = previous[x], c = x >= 4 ? previous[x - 4] : 0;
      const p = a + b - c, [pa, pb, pc] = [Math.abs(p - a), Math.abs(p - b), Math.abs(p - c)];
      line[x] = (line[x] + [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][filter]) & 255;
    }
    pixels.set(line, y * stride);
    previous = line;
  }
  return { width, height, at: (x, y) => [...pixels.subarray((y * width + x) * 4, (y * width + x) * 4 + 4)] };
}

const linear = (c) => { const x = c / 255; return x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4; };
const lightness = ([r, g, b]) => { const l = [r, g, b].map(linear); return (Math.max(...l) + Math.min(...l)) / 2; };
const inBand = (rgba) => { const l = lightness(rgba); return l > LIGHTNESS[0] && l < LIGHTNESS[1]; };

/// A drawn eye texture split into its panels: the eye's base layer and its iris layer, each a list
/// of { uv, rgba } for its drawn texels (alpha over half).
function panels(name, eye) {
  const img = image(name);
  assert.equal(img.width, 2 * eye.size, `${name} is two panels wide`);
  assert.equal(img.height, eye.size, `${name} is one panel high`);
  const layer = (from) => {
    const out = [];
    for (let y = 0; y < eye.size; y += 1) for (let x = 0; x < eye.size; x += 1) {
      const rgba = img.at(from + x, y);
      if (rgba[3] >= 128) out.push({ uv: [(x + 0.5) / eye.size, (y + 0.5) / eye.size], rgba });
    }
    return out;
  };
  return { base: layer(0), iris: layer(eye.size) };
}

const EYES = [['eye', BODY_EYE], ['eyeface', FLOWER]];
const isWhite = ({ rgba }) => linear(rgba[1]) > 0.4;

test('the shoggoth\'s drawn irises take the tint and nothing else of its eyes would', () => {
  for (const [name, eye] of EYES) {
    const { base, iris } = panels(name, eye);
    const tinted = iris.filter(({ rgba }) => inBand(rgba)).length / iris.length;
    assert.ok(tinted > 0.5, `${name}: most of its iris is in the tint band (${tinted.toFixed(2)})`);
    assert.deepEqual(iris.filter(({ rgba }) => !inBand(rgba) && lightness(rgba) > LIGHTNESS[0] && lightness(rgba) < 0.9), [], `${name}: the rest of its iris is pupil, rim or glint`);
    assert.deepEqual(base.filter(({ rgba }) => inBand(rgba)), [], `${name}: no ink, white or fold is in the tint band`);
    assert.ok(iris.some(({ rgba }) => lightness(rgba) < LIGHTNESS[0]), `${name}: its pupil stays dark`);
  }
});

test('the shoggoth\'s eyes are the almonds its lids close over', () => {
  for (const [name, eye] of EYES) {
    const { base } = panels(name, eye);
    const whites = base.filter(isWhite);
    assert.ok(whites.length > (eye.eyes ? 2000 : 1000), `${name}: the white is drawn`);
    for (const { uv } of whites) {
      const { s, t } = eyeAt(eye, uv);
      assert.ok(Math.abs(t) < almond(s), `${name}: white at ${uv} lies inside its almond`);
    }
    // ... and the almond is all white, bar its outline.
    const white = new Set(whites.map(({ uv }) => uv.join()));
    for (let y = 0; y < eye.size; y += 1) for (let x = 0; x < eye.size; x += 1) {
      const uv = [(x + 0.5) / eye.size, (y + 0.5) / eye.size], { s, t } = eyeAt(eye, uv);
      if (Math.abs(t) < 0.85 * almond(s) && Math.abs(s) < 0.9) assert.ok(white.has(uv.join()), `${name}: inside its almond at ${uv} is white`);
    }
  }
  assert.ok(eyeMapGlsl(BODY_EYE).includes(ALMOND_POWER.toFixed(4)), 'the shader draws the same almond');
});

test('open lids cover none of any eye, shut ones all of it, and half shut about half, in every face', () => {
  for (const [name, eye] of EYES) {
    const whites = panels(name, eye).base.filter(isWhite).map(({ uv }) => eyeAt(eye, uv));
    const covered = (lids) => whites.filter(({ s, t }) => { const { upper, lower } = lidEdges(s, lids); return t >= upper || t < lower; }).length / whites.length;
    for (const { name: face, eyes } of FACES) {
      assert.equal(covered({ ...eyes, closed: 0 }), 0, `${name}, ${face}: open lids cover no white or iris`);
      assert.equal(covered({ ...eyes, closed: 1 }), 1, `${name}, ${face}: shut lids cover all of it`);
      const half = covered({ ...eyes, closed: 0.5 });
      assert.ok(half > 0.2 && half < 0.85, `${name}, ${face}: half-shut lids cover part of it (${half.toFixed(2)})`);
    }
  }
});

test('each eye of the shoggoth knows which way its texture runs over its body, so it can look', () => {
  for (const material of ['shoggoth eye', 'shoggoth eyeface']) {
    const { position, uv, index } = primitive(material);
    const { eyeU, eyeV, patches } = decalAxes(position, uv, index);
    assert.ok(patches > 0 && eyeU.every(Number.isFinite) && eyeV.every(Number.isFinite), `${material}: every vertex has axes`);
    for (let i = 0; i < position.length / 3; i += 1) {
      const u = eyeU.subarray(3 * i, 3 * i + 3), v = eyeV.subarray(3 * i, 3 * i + 3);
      assert.ok(Math.abs(Math.hypot(...u) - 1) < 1e-3 && Math.abs(u[0] * v[0] + u[1] * v[1] + u[2] * v[2]) < 0.5, `${material}: vertex ${i}'s axes are unit and roughly square`);
    }
  }
  // The flower faces out of its face, upright: across is right, its texture's v down.
  const flower = primitive('shoggoth eyeface');
  const { eyeU, eyeV } = decalAxes(flower.position, flower.uv, flower.index);
  assert.ok(eyeU[0] > 0.9, `the flower's u runs right (${eyeU[0].toFixed(2)})`);
  assert.ok(eyeV[1] < -0.8, `the flower's v runs down (${eyeV[1].toFixed(2)})`);
});

// --------------------------------------------------------------- the face

/// A pose with nothing going on; `extra` sets what is.
const calm = (extra = {}) => ({
  t: 0, S: 0, dozy: 0, focused: 0, fretful: 0, satisfied: 0, odd: 0, D: 0, L: 0, sad: 0, eyeLight: 0,
  startle: 0, flinch: 0, psy: 0, dizzy: 0, spinning: 0, ...extra,
});

// DESIGN.md, Desk Pet (Shoggoth), "Face": each state and what its mask's U's become.
const MASK_FOR = {
  idle: [{}, 'u'],
  dozy: [{ dozy: 1 }, 'drowsy'],
  focused: [{ focused: 1 }, 'narrow'],
  power: [{ eyeLight: 1 }, 'wide'],
  fretful: [{ fretful: 1 }, 'worried'],
  satisfied: [{ satisfied: 1 }, 'arc'],
  petted: [{ L: 1 }, 'arc'],
  sleep: [{ S: 1 }, 'shut'],
  crying: [{ sad: 1 }, 'tears'],
  surprised: [{ startle: 1 }, 'o'],
  dizzy: [{ dizzy: 1 }, 'spiral'],
};

test('each state of the shoggoth shows its own face, the mask\'s U\'s its documented emote', () => {
  assert.deepEqual(FACES.map((f) => f.name).sort(), Object.keys(MASK_FOR).sort(), 'every face is documented');
  for (const [state, [pose, glyph]] of Object.entries(MASK_FOR)) {
    const face = faceFor(calm(pose));
    assert.equal(face.name, state, `${JSON.stringify(pose)} shows ${state}`);
    const off = Math.max(...face.mask.points.flatMap((p, k) => p.map((x, c) => Math.abs(x - GLYPH_SHAPES[glyph][k][c]))));
    assert.ok(off < 1e-9, `${state}: its U's are ${glyph}`);
  }
  assert.equal(faceFor(calm({ satisfied: 1, fretful: 1 })).name, 'satisfied', 'a meal shows over a worry, as the mood blends them');
  assert.equal(faceFor(calm({ S: 1, dozy: 1 })).name, 'sleep', 'asleep is more than dozy');
  assert.ok(faceFor(calm({ eyeLight: 1 })).mask.glow > 0.99, 'powered up, its U\'s glow');
  assert.ok(faceFor(calm({ fretful: 1 })).mask.wobble > 0.99, 'fretful, they tremble');
});

test('the shoggoth\'s face blends from one state to the next without a step', () => {
  const flat = (face) => [...face.mask.points.flat(), face.mask.glow, face.mask.wobble, ...Object.values(face.eyes)];
  const states = Object.values(MASK_FOR).map(([pose]) => pose);
  for (const from of states) {
    for (const to of states) {
      let last = flat(faceFor(calm(from)));
      for (let k = 1; k <= 50; k += 1) {
        const u = k / 50, pose = calm();
        for (const [key, value] of Object.entries(from)) pose[key] += value * (1 - u);
        for (const [key, value] of Object.entries(to)) pose[key] += value * u;
        const now = flat(faceFor(pose));
        const jump = Math.max(...now.map((x, i) => Math.abs(x - last[i])));
        assert.ok(jump < 0.15, `${JSON.stringify(from)} to ${JSON.stringify(to)}: no step at ${u} (${jump.toFixed(3)})`);
        last = now;
      }
    }
  }
});

test('the mask\'s w never moves, whatever its U\'s do', () => {
  const { position, normal, uv, index } = primitive('Material.009');
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(position.slice(), 3));
  geometry.setAttribute('normal', new THREE.BufferAttribute(normal.slice(), 3));
  geometry.setAttribute('uv', new THREE.BufferAttribute(uv.slice(), 2));
  geometry.setIndex(new THREE.BufferAttribute(index.slice(), 1));
  const text = new THREE.Mesh(geometry, new THREE.MeshStandardMaterial({ color: 0x000000 }));
  const mask = createMask(text);
  assert.ok(mask, 'the text splits into U, w and U');
  const w = text.geometry, kept = w.index.array.slice();
  const xs = [...kept].map((i) => position[3 * i]);
  const [lo, hi] = [Math.min(...xs), Math.max(...xs)];
  for (let k = 0; k < index.length; k += 3) {
    const x = (position[3 * index[k]] + position[3 * index[k + 1]] + position[3 * index[k + 2]]) / 3;
    if (x > lo && x < hi) assert.ok(kept.includes(index[k]), 'every triangle of the w is still drawn');
  }
  for (const [state, [pose]] of Object.entries(MASK_FOR)) {
    for (const t of [0, 0.37, 5.1]) {
      mask.step(faceFor(calm(pose)), t);
      assert.deepEqual(w.attributes.position.array, position, `${state} at ${t}: its positions are as they were`);
      assert.deepEqual(w.attributes.normal.array, normal, `${state} at ${t}: its normals are as they were`);
      assert.deepEqual(w.index.array, kept, `${state} at ${t}: it is the same triangles`);
      for (const stroke of mask.strokes) {
        const box = new THREE.Box3().setFromBufferAttribute(stroke.geometry.attributes.position);
        assert.ok(box.max.x <= lo + 0.02 || box.min.x >= hi - 0.02, `${state}: neither U is drawn over the w`);
      }
    }
  }
});
