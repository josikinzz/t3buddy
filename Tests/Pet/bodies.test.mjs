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
const { eyefaceShade, parseTint, DEFAULT_TINT, LIGHTNESS, CURVE_KNEE, EYEFACE_MAP_GLSL, FLOWER_EYES, FLOWER_EYE_REACH, EYEFACE_ACROSS_GLSL, acrossSpoke } = await import('../../Resources/Pet/bodies/shoggoth-eyeface.js');

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
  for (const n of [...LIGHTNESS, CURVE_KNEE]) assert.ok(EYEFACE_MAP_GLSL.includes(n.toFixed(4)), `the GLSL uses ${n}`);
});

test('a tint is #rrggbb, lower-cased, or the default red', () => {
  assert.equal(DEFAULT_TINT, '#ff0000');
  assert.equal(parseTint('#00FF88'), '#00ff88');
  assert.equal(parseTint(' #a970ff '), '#a970ff');
  for (const bad of ['', 'red', '#fff', '#gg0000', 'ff0000', '#ff00001', null, undefined, 42]) {
    assert.equal(parseTint(bad), DEFAULT_TINT, `${String(bad)} is not a tint`);
  }
});

/// The drawn texels (alpha over half) of an image in shoggoth.glb, as [u, v] texel centres.
function drawnTexels(imageName) {
  const glb = readFileSync(new URL('../../Resources/Pet/shoggoth.glb', import.meta.url));
  const json = JSON.parse(glb.subarray(20, 20 + glb.readUInt32LE(12)).toString());
  const bin = glb.subarray(20 + glb.readUInt32LE(12) + 8);
  const view = json.bufferViews[json.images.find((i) => i.name === imageName).bufferView];
  const png = bin.subarray(view.byteOffset ?? 0, (view.byteOffset ?? 0) + view.byteLength);
  let width, height, depth, colour, idat = [];
  for (let at = 8; at < png.length;) {
    const length = png.readUInt32BE(at), kind = png.toString('latin1', at + 4, at + 8), body = png.subarray(at + 8, at + 8 + length);
    if (kind === 'IHDR') [width, height, depth, colour] = [body.readUInt32BE(0), body.readUInt32BE(4), body[8], body[9]];
    if (kind === 'IDAT') idat.push(body);
    at += 12 + length;
  }
  assert.ok(depth === 8 && colour === 6, `${imageName} is 8-bit RGBA`);
  const raw = inflateSync(Buffer.concat(idat)), stride = width * 4, texels = [];
  let previous = new Uint8Array(stride);
  for (let y = 0; y < height; y += 1) {
    const filter = raw[y * (stride + 1)], line = Uint8Array.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let x = 0; x < stride; x += 1) {
      const a = x >= 4 ? line[x - 4] : 0, b = previous[x], c = x >= 4 ? previous[x - 4] : 0;
      const p = a + b - c, [pa, pb, pc] = [Math.abs(p - a), Math.abs(p - b), Math.abs(p - c)];
      line[x] = (line[x] + [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][filter]) & 255;
    }
    for (let x = 0; x < width; x += 1) if (line[x * 4 + 3] >= 128) texels.push([(x + 0.5) / width, (y + 0.5) / height]);
    previous = line;
  }
  return texels;
}

test('the shoggoth\'s eye-flower lids start outside every eye and close across all eight', () => {
  const texels = drawnTexels('eyeface');
  assert.ok(texels.length > 1000, 'the flower is drawn');
  const outside = texels.filter((uv) => acrossSpoke(uv) > FLOWER_EYE_REACH);
  assert.deepEqual(outside, [], 'open lids cover no drawn texel');
  const step = (2 * Math.PI) / FLOWER_EYES;
  for (let k = 0; k < FLOWER_EYES; k += 1) {
    const eye = texels.filter(([u, v]) => (((Math.round(Math.atan2(v - 0.5, u - 0.5) / step) % FLOWER_EYES) + FLOWER_EYES) % FLOWER_EYES) === k);
    const widest = Math.max(...eye.map(acrossSpoke));
    assert.ok(widest > 0.75 * FLOWER_EYE_REACH, `eye ${k} reaches out to where the lids start (${widest.toFixed(3)})`);
    const half = eye.filter((uv) => acrossSpoke(uv) > 0.5 * FLOWER_EYE_REACH).length / eye.length;
    assert.ok(half > 0.2 && half < 0.8, `half-closed lids cover part of eye ${k}, not all of it (${half.toFixed(2)})`);
  }
  assert.ok(EYEFACE_ACROSS_GLSL.includes(step.toFixed(4)), 'the GLSL spokes are these spokes');
});
