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

test('a tear whose path is given each frame wells and runs on that path as it is now', () => {
  const { scene, effects, step } = makeEffects();
  const shift = new THREE.Vector3();
  const path = () => [0, 1, 2, 3, 4].map((k) => new THREE.Vector3(0, -0.1 * k, 0).add(shift));
  const before = new Set(scene.children);
  effects.tear(path);
  const [holder] = scene.children.filter((o) => !before.has(o));
  const streak = holder.children.find((o) => o.geometry.type === 'TubeGeometry');
  const drop = holder.children.find((o) => o !== streak);
  const offPath = (p) => Math.min(...path().map((q) => Math.hypot(p.x - q.x, p.z - q.z)));

  step(0);
  shift.set(0.3, 0.05, -0.2);
  step(0.4);
  holder.updateMatrixWorld(true);
  assert.ok(drop.getWorldPosition(new THREE.Vector3()).distanceTo(path()[0]) < 1e-6, 'it wells where its path starts now');

  shift.set(-0.25, -0.1, 0.1);
  step(1.3);
  holder.updateMatrixWorld(true);
  const at = drop.getWorldPosition(new THREE.Vector3());
  assert.ok(offPath(at) < 1e-6 && at.y < path()[0].y && at.y > path().at(-1).y, 'it runs down its path as it is now');
  streak.geometry.computeBoundingBox();
  const middle = streak.geometry.boundingBox.getCenter(new THREE.Vector3()).applyMatrix4(holder.matrixWorld);
  assert.ok(Math.abs(middle.x - shift.x) < 0.01 && Math.abs(middle.z - shift.z) < 0.01, 'its streak lies along the path as it is now');
});
