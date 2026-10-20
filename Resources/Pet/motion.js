// Trembles: the one way anything on the page shakes, shivers, shudders or purrs.
//
// Past about 6 Hz a shake stops reading as a tremble and reads as a buzz, and T3boii has
// been sent back for buzzing. tremble() caps the rate, so a new shake can't buzz however it
// is tuned. The checks (Tests/ModelWidgetChecks/PetMotionChecks.swift) fail any raw
// Math.sin(t * N) faster than the cap in these scripts.
//
// Callers still own amplitude and the Reduce Motion gate; this only owns how fast.

export const TREMBLE_MAX_RATE = 40;   // rad/s, about 6.4 Hz

// A sine tremble at `rate` rad/s (capped), in [-1, 1].
export function tremble(t, rate, phase = 0) {
  return Math.sin(t * Math.min(rate, TREMBLE_MAX_RATE) + phase);
}

// Paces: anything that loops at a rate that can change (an orbit lap, a breath) keeps a Phase and
// advances it by dt. Writing it as sin(t * rate) instead jumps the moment the rate changes, and on
// a clock hours old the jump sweeps through dozens of cycles in a frame: a buzz.
export class Phase {
  constructor(value = 0) { this.value = value; }
  advance(dt, rate) { this.value += dt * rate; return this.value; }
}

// Eases s.x (with velocity s.v) toward `target` like a spring: omega is how quick (rad/s), zeta
// the damping (1 = no overshoot). Implicit, so a long frame never makes it overshoot or blow up.
export function spring(s, target, omega, dt, zeta = 1) {
  const f = 1 + 2 * dt * zeta * omega;
  const oo = omega * omega, hoo = dt * oo, hhoo = dt * hoo;
  const inv = 1 / (f + hhoo);
  const x = (f * s.x + dt * s.v + hhoo * target) * inv;
  s.v = (s.v + hoo * (target - s.x)) * inv;
  s.x = x;
  return x;
}
