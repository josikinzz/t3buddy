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
