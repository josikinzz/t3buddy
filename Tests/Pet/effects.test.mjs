import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../../Resources/Pet/vendor/three/build/three.module.js';
import { createEffects } from '../../Resources/Pet/effects.js';
import { installFakeDom } from './fake-dom.mjs';

installFakeDom();

function makeEffects() {
  const scene = new THREE.Scene();
  const effects = createEffects({ THREE, scene, pxPerUnit: () => 100, pageToWorld: (x, y, z = 0) => new THREE.Vector3(x / 100, -y / 100, z) });
  return { scene, effects, step: (t) => effects.step(t, 1 / 60, {}) };
}

/// Flies one glint toward a target that exists while `present()` says so; returns what it reported.
function flyGlint(present) {
  const { effects, step } = makeEffects();
  const ends = [];
  effects.glint({ at: (u) => (present() ? new THREE.Vector3(u, 0, 0) : null), color: 0xfff1d0, size: 0.1, duration: 0.5, done: (arrived) => ends.push(arrived) });
  let t = 0;
  for (; t <= 1 && effects.glints > 0; t += 1 / 60) step(t);
  return { ends, effects };
}

test('a glint that reaches its orb reports one arrival', () => {
  const { ends, effects } = flyGlint(() => true);
  assert.deepEqual(ends, [true]);
  assert.equal(effects.glints, 0, 'the glint is gone once it lands');
});

test('a glint whose orb vanished mid-flight reports its end once, and no arrival', () => {
  let present = true;
  const { effects, step } = makeEffects();
  const ends = [];
  effects.glint({ at: (u) => (present ? new THREE.Vector3(u, 0, 0) : null), color: 0xfff1d0, size: 0.1, duration: 0.5, done: (arrived) => ends.push(arrived) });
  step(0);
  step(0.1);
  assert.deepEqual(ends, [], 'still in flight');
  present = false;
  step(0.2);
  assert.deepEqual(ends, [false]);
  assert.equal(effects.glints, 0, 'the cancelled glint is cleared from the scene');
  for (let t = 0.3; t < 1; t += 0.1) step(t);
  assert.deepEqual(ends, [false], 'it reports once');
});

test('a glint whose orb is gone before it first moves still reports its end', () => {
  const { ends } = flyGlint(() => false);
  assert.deepEqual(ends, [false]);
});

function materialsAndGeometriesOf(object) {
  const materials = new Set(), geometries = new Set();
  object.traverse((o) => { if (o.material) materials.add(o.material); if (o.geometry) geometries.add(o.geometry); });
  return { materials: [...materials], geometries: [...geometries] };
}

test('a removed scheduled seed disposes every material it owned and keeps the shared geometry', () => {
  const { scene, effects } = makeEffects();
  const halo = { centre: new THREE.Vector3(0, 1.4, 0), radius: 0.5, size: 0.2, t: 0, reduced: false, forehead: null };
  const before = new Set(scene.children);
  effects.setSeeds([{ id: 'seed:docs-site', color: 0x0a84ff, ripe: 0.5, failed: true }, { id: 'seed:demo-app', color: 0xd97757, ripe: 0.2, failed: false }], halo);
  const [docsSite] = scene.children.filter((o) => !before.has(o));
  const { materials, geometries } = materialsAndGeometriesOf(docsSite);
  assert.ok(materials.length >= 2, 'the seed has its glass and its crack');
  const disposed = new Set();
  for (const m of materials) m.addEventListener('dispose', () => disposed.add(m));
  for (const g of geometries) g.addEventListener('dispose', () => disposed.add(g));

  effects.setSeeds([{ id: 'seed:demo-app', color: 0xd97757, ripe: 0.2, failed: false }], halo);

  assert.ok(!scene.children.includes(docsSite), 'the seed left the scene');
  assert.deepEqual(materials.filter((m) => !disposed.has(m)), [], 'no material of the removed seed is left undisposed');
  assert.deepEqual(geometries.filter((g) => disposed.has(g)), [], 'the shared seed and crack geometry stay for the others');
  assert.deepEqual(effects.seeds.map((s) => s.id), ['seed:demo-app']);
});
