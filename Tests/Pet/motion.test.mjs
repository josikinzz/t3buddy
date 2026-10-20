import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Phase, tremble, TREMBLE_MAX_RATE } from '../../Resources/Pet/motion.js';

const SIX_HOURS = 6 * 3600;
const SLOW = 0.4, FAST = 2.5;   // rad/s: a calm lap, then a busy one

/// Runs a sway frame by frame up to six hours of uptime at SLOW, then FAST, and returns the
/// largest frame-to-frame step of its angle in the second around the pace change.
function largestStepAroundPaceChange(fps, angleAt) {
  const dt = 1 / fps;
  const frames = Math.round(SIX_HOURS * fps);
  let previous = null, largest = 0;
  for (let i = 0; i <= frames + fps; i += 1) {
    const t = i * dt;
    const angle = angleAt(t, dt, i < frames ? SLOW : FAST);
    if (i >= frames - fps && previous !== null) largest = Math.max(largest, Math.abs(angle - previous));
    previous = angle;
  }
  return largest;
}

for (const fps of [30, 60]) {
  test(`a Phase advanced by dt stays continuous when its rate changes six hours in, at ${fps} fps`, () => {
    const phase = new Phase();
    const largest = largestStepAroundPaceChange(fps, (t, dt, rate) => phase.advance(dt, rate));
    assert.ok(largest <= FAST / fps + 1e-9, `one frame moves at most rate * dt (${largest.toFixed(4)} rad)`);
    assert.ok(Math.abs(phase.value - (SIX_HOURS * SLOW + FAST * (fps + 1) / fps)) < 1e-3, 'the angle is the integral of its rate');
  });

  test(`the clock times a rate jumps when the rate changes six hours in, at ${fps} fps (the detector sees a sweep)`, () => {
    const largest = largestStepAroundPaceChange(fps, (t, dt, rate) => t * rate);
    assert.ok(largest > 1000, `a pace change on an old clock jumps ${largest.toFixed(0)} rad in one frame`);
  });
}

test('a Phase starts where it is told and never depends on the clock', () => {
  const a = new Phase(1.5), b = new Phase(1.5);
  for (let i = 0; i < 100; i += 1) a.advance(1 / 60, 3);
  for (let i = 0; i < 50; i += 1) b.advance(1 / 30, 3);
  assert.ok(Math.abs(a.value - b.value) < 1e-9, 'the same span at either frame rate lands on the same angle');
  assert.ok(Math.abs(a.value - (1.5 + 5)) < 1e-9);
});

/// Zero crossings per second of tremble(t, rate), sampled finely over ten seconds.
function crossingsPerSecond(rate) {
  let crossings = 0, previous = tremble(0, rate, 0.3);
  for (let i = 1; i <= 10_000; i += 1) {
    const value = tremble(i / 1000, rate, 0.3);
    assert.ok(value >= -1 && value <= 1, 'a tremble stays in [-1, 1]');
    if (Math.sign(value) !== Math.sign(previous)) crossings += 1;
    previous = value;
  }
  return crossings / 10;
}

test('a tremble asked to go faster than the cap shakes no faster than TREMBLE_MAX_RATE', () => {
  const capped = TREMBLE_MAX_RATE / Math.PI;
  for (const rate of [TREMBLE_MAX_RATE * 1.5, 120, 1000]) {
    assert.ok(crossingsPerSecond(rate) <= capped + 0.2, `${rate} rad/s is held to the cap`);
  }
  assert.ok(Math.abs(crossingsPerSecond(12) - 12 / Math.PI) <= 0.2, 'a rate under the cap is left alone');
});

test('the tremble cap is a tremble, not a buzz (about 6 Hz at most)', () => {
  assert.ok(TREMBLE_MAX_RATE / (2 * Math.PI) <= 6.5, `${(TREMBLE_MAX_RATE / (2 * Math.PI)).toFixed(1)} Hz`);
});
