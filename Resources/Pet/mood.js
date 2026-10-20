// His mood: what the work around him says about how he feels, as a blend of five faces and
// bodies. pet.js adds the blend to the pose it already makes, so Neutral is today's look and the
// others are offsets from it.
//
//   Dozy       nothing to do for DOZE_AFTER_S: heavy lids, slow breath, head down (sleep comes later, as before)
//   Focused    3+ threads, or 1+ working hard: lids up, a small concentration frown, leaning in
//   Satisfied  just swallowed one: a contented squint and smile, a settle-bounce, a slow exhale
//   Fretful    a failure you have not looked at, or a question waiting 20 s: frown, quick shallow
//              breath, quick blinks, arms in, a faint trembling mouth
//
// Moods hold a minimum time once entered so they never flicker, and their weights ease on
// critically damped springs, so nothing steps.

import { spring } from './motion.js';

export const MOODS = ['dozy', 'neutral', 'focused', 'satisfied', 'fretful'];

// Offsets from Neutral. lid, smile, frown: shares of the morphs; breath: times the breath period;
// breathDepth: times its depth; blink: times the gap between blinks; float: world units;
// lean: head and body forward (rad); arms: in toward his sides (rad).
export const LOOKS = {
  dozy:      { lid: 0.30, smile: -0.07, frown: 0,    breath: 1.38, breathDepth: 1,   blink: 1.6,  float: -0.02,  lean: 0,     head: 0.07, arms: 0 },
  neutral:   { lid: 0,    smile: 0,     frown: 0,    breath: 1,    breathDepth: 1,   blink: 1,    float: 0,      lean: 0,     head: 0,    arms: 0 },
  focused:   { lid: -0.06, smile: -0.04, frown: 0.12, breath: 0.75, breathDepth: 1,  blink: 0.75, float: 0.01,   lean: 0.05,  head: 0,    arms: 0 },
  satisfied: { lid: 0.14, smile: 0.43,  frown: 0,    breath: 1.1,  breathDepth: 1.2, blink: 1.25, float: 0.015, lean: 0,     head: 0,    arms: 0 },
  fretful:   { lid: -0.02, smile: -0.12, frown: 0.45, breath: 0.65, breathDepth: 0.7, blink: 0.5, float: -0.01,  lean: 0,     head: 0,    arms: 0.06 },
};

const DOZE_AFTER_S = 8;
const FOCUS_AT = { active: 3, fleet: 0.15 }, UNFOCUS_FLEET = 0.08, UNFOCUS_S = 10;
const ASK_FRETS_S = 20;
const MEAL_S = 5, MEAL_MORE_S = 2, MEAL_MAX_S = 10;
const DWELL_S = { dozy: 3, focused: 4, fretful: 4, neutral: 0 };
const BLEND_OMEGA = 2.5, MEAL_OMEGA = 6;
const SATISFIED_KEEPS_FRET = 0.3;

export function createMood() {
  const weights = Object.fromEntries(MOODS.map((m) => [m, { x: m === 'neutral' ? 1 : 0, v: 0 }]));
  let base = 'neutral', baseSince = -Infinity;
  let idleSince = null, focused = false, lowSince = null;
  let mealUntil = -Infinity, mealStart = -Infinity;
  let severity = 0;

  /// Call when he finishes a swallow.
  function meal(t) {
    if (t < mealUntil) mealUntil = Math.min(mealStart + MEAL_MAX_S, Math.max(mealUntil, t + MEAL_S) + MEAL_MORE_S);
    else { mealStart = t; mealUntil = t + MEAL_S; }
  }

  /// One frame. `active`: orbs working; `fleet`: how hard the busiest five work (0 .. 1);
  /// `unseenFailures`: count; `oldestAsk`: seconds the longest-waiting question has waited.
  function step(t, dt, { active = 0, fleet = 0, unseenFailures = 0, oldestAsk = 0 }) {
    if (active > 0) idleSince = null; else idleSince ??= t;
    if (active >= FOCUS_AT.active || (fleet >= FOCUS_AT.fleet && active >= 1)) { focused = true; lowSince = null; }
    else if (focused) {
      if (active === 0) focused = false;
      else if (fleet < UNFOCUS_FLEET) { lowSince ??= t; if (t - lowSince >= UNFOCUS_S) focused = false; }
      else lowSince = null;
    }
    const fret = unseenFailures >= 1 || oldestAsk >= ASK_FRETS_S;
    const want = fret ? 'fretful' : focused ? 'focused' : idleSince !== null && t - idleSince >= DOZE_AFTER_S ? 'dozy' : 'neutral';
    if (want !== base && t - baseSince >= DWELL_S[base]) { base = want; baseSince = t; }
    severity = Math.min(1, 0.3 * unseenFailures + oldestAsk / 600);

    const eating = t < mealUntil;
    for (const m of MOODS) {
      let target = m === base ? 1 : 0;
      if (eating) target = m === 'satisfied' ? (base === 'fretful' ? 1 - SATISFIED_KEEPS_FRET : 1) : m === 'fretful' && base === 'fretful' ? SATISFIED_KEEPS_FRET : 0;
      spring(weights[m], target, m === 'satisfied' && eating ? MEAL_OMEGA : BLEND_OMEGA, dt);
    }
    return look();
  }

  /// The blend, as offsets from Neutral (breath, breathDepth and blink as factors).
  function look() {
    const out = { lid: 0, smile: 0, frown: 0, breath: 0, breathDepth: 0, blink: 0, float: 0, lean: 0, head: 0, arms: 0 };
    let total = 0;
    for (const m of MOODS) total += Math.max(0, weights[m].x);
    for (const m of MOODS) {
      const w = Math.max(0, weights[m].x) / (total || 1);
      for (const key of Object.keys(out)) out[key] += w * LOOKS[m][key];
    }
    out.frown += 0.1 * severity * Math.max(0, weights.fretful.x);
    return out;
  }

  return {
    step, meal,
    get mood() { return base; },
    get eating() { return mealUntil; },
    get weights() { return Object.fromEntries(MOODS.map((m) => [m, +Math.max(0, weights[m].x).toFixed(3)])); },
    get fretful() { return Math.max(0, weights.fretful.x); },
    get satisfied() { return Math.max(0, weights.satisfied.x); },
  };
}
