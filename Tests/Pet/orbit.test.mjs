import { test } from 'node:test';
import assert from 'node:assert/strict';
import { installFakeDom } from './fake-dom.mjs';
import { createOrbit } from '../../Resources/Pet/orbit.js';

const dom = installFakeDom();

const BALL = { x: 600, y: 420, r: 110 };   // his round body on the page

function makeOrbit() {
  return createOrbit({
    body: { height: 320 },
    ball: () => ({ ...BALL }),
    soles: 1.6,
    foreheadAnchor: () => ({ page: { x: BALL.x, y: BALL.y - 80 }, world: { x: 0, y: 0.8, z: 0.4 } }),
    mouthAnchor: () => ({ x: BALL.x, y: BALL.y + 30 }),
    setHitRegions() {},
    post() {},
    front: dom.element(),
    back: dom.element(),
  });
}

const orb = (id, extra = {}) => ({ id, parentId: null, source: 't3', projectIcon: { kind: 'monogram', text: 'DA', color: '#5b8def' }, provider: 'codex', state: 'active', label: `demo-app ${id}`, ...extra });

function settle(orbit, seconds = 3) {
  for (let t = orbit.clock, end = t + seconds; t < end; t += 1 / 60) orbit.frame(t, 1 / 60);
}

test('a thread waiting for input asks with a ?, one waiting for approval with a !, and an unknown wait with a !', () => {
  const orbit = makeOrbit();
  orbit.update({ orbs: [
    orb('t3:input', { state: 'waiting', waitingFor: 'input' }),
    orb('t3:approval', { state: 'waiting', waitingFor: 'approval' }),
    orb('t3:other', { state: 'waiting', waitingFor: 'something-new' }),
    orb('t3:working'),
  ] });
  settle(orbit);
  const asks = orbit.asks();
  assert.deepEqual(Object.fromEntries(asks.map((a) => [a.id, a.kind])), { 't3:input': '?', 't3:approval': '!', 't3:other': '!' });
  for (const a of asks) assert.ok(Math.hypot(a.x - BALL.x, a.y - BALL.y) > BALL.r, `${a.id}'s dot floats beside him, not on him`);
});

test('a question that becomes an approval changes its mark', () => {
  const orbit = makeOrbit();
  orbit.update({ orbs: [orb('t3:a', { state: 'waiting', waitingFor: 'input' })] });
  settle(orbit);
  assert.deepEqual(orbit.asks().map((a) => a.kind), ['?']);
  orbit.update({ orbs: [orb('t3:a', { state: 'waiting', waitingFor: 'approval' })] });
  settle(orbit, 0.5);
  assert.deepEqual(orbit.asks().map((a) => a.kind), ['!']);
});

test('a working thread has no mark', () => {
  const orbit = makeOrbit();
  orbit.update({ orbs: [orb('t3:a')] });
  settle(orbit);
  assert.deepEqual(orbit.asks(), []);
});
