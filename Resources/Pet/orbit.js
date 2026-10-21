// T3boii's orbit: one orb per active agent, circling his round body like a halo.
//
// Orbs are DOM elements (crisp favicons and badges) placed each frame in page CSS px, shaded
// as little spheres. They ride near-circular rings hugging the outer edge of his ball body, so
// every thread is in view at once. The rings lean back a little, as if seen from just below
// their plane: the lower half of a lap is the near side, in the front layer over his legs; the
// upper half is the far side, in the back layer under his canvas, where an orb passing over the
// top of his head tucks a third of the way behind it. Depth also shrinks and dims an orb a touch.
// Each ring carries a glowing energy line, drawn in two halves on canvases in the same two layers. More orbs fill more, wider rings;
// nothing is hidden behind a count.
//
// A thread's orb wears its provider's logo small on its own surface, over the lower part of its
// project icon (which keeps its full size), so it never reads as a subagent. A thread's subagents circle it as satellites: each just a sphere
// wearing its provider's logo, since the project icon would only repeat its parent's.
//
// update(snapshot) diffs orb ids. A new id glows out of the T3 on his forehead and
// floats, psychically, into a ring slot. A removed id is swallowed: his mouth opens,
// the orb is drawn in with a little spiral on a rush of wind lines, and he gulps.
// Ids are threads, stable across their turns (Swift debounces gaps), so a thread that stirs
// again after a lull only glows briefly. A parent stays while any orb in the snapshot circles it.
//
// An orb's state picks its place:
//   active, no parent in orbit  -> a slot on his halo rings, its subagents circling it
//   active, parent in orbit     -> a satellite circling its parent's orb (spawns from
//                                  and is reabsorbed into the parent when it can be)
//   waiting                     -> leaves orbit for the ask arc beside his head, outside his rings,
//                                  and floats there as the dot of a lit 3D "?" when it asks you a
//                                  question (waitingFor "input"), a "!" otherwise. He never holds it.
//   failed                      -> cracks and turns red, and stays put just outside its ring
//                                  until you look at it (hover a moment, or click); then it greys,
//                                  sinks and fades. It stays even after the snapshot drops it,
//                                  for up to FAILED_KEEP_S, until you have seen it.
//   limited (any state)         -> its provider refused it for a rate or usage limit: it dies where
//                                  it is. It darkens to black under a big copy of its provider's
//                                  logo, then dissolves, eaten away from within with a glowing rim
//                                  while dark chips crumble off it (pet.js, effects.js). It stays
//                                  gone while the snapshot still says it is limited; back unlimited,
//                                  it is a new orb.
// A main orb also shows how lively its thread is: it breathes quickly while its thread is busy,
// slowly when quiet, and a thread quiet for minutes drifts out from its ring and dims.
// Moving between places is a short glide. With reduced motion, flights become fades,
// the rings stand still and nothing bobs or sinks.
//
// What a thread is doing trails behind its orb like a comet's tail: faint glowing words laid
// along the path the orb has just flown, clearly legible at the orb and fading out behind it. Hover an
// orb and its words light up (and T3boii looks at it, events.hover); a waiting thread's read
// amber, a failed one's red. Subagents trail theirs too, smaller and fainter; a parent's satellites
// share one small ring, so they take turns, one tail at a time.

import { tremble, Phase, spring } from './motion.js';

// Sizes follow his rendered body, so the orbit scales with the stage.
const ORB_PER_HEIGHT = 0.14;     // face diameter as a share of his on-screen height
const ORB_MIN = 34, ORB_MAX = 96;
const SPAWN_S = 1.6;             // forehead to ring slot
const MATERIALIZE_S = 0.3;       // ... of which the orb kindles in the forehead glow
const SWALLOW_S = 1.3;           // ring slot to mouth
const TUG_S = 0.3;               // ... of which the orb is tugged before it lets go
const SWALLOW_STAGGER_S = 0.22;  // several orbs leaving at once queue for his mouth
const PARENT_LEAVE_S = 0.9;      // a satellite flying back into its parent
const PERIOD0 = 22;              // seconds per lap on the first ring
const EASE_RATE = 2.4;           // how fast an orb settles into a new slot (1/s)
const SAT_SCALE = 0.5;           // a satellite's size against its parent's
const SAT_PERIOD = 6;            // seconds per lap on a parent's first satellite ring
const BLEND_S = 0.9;             // glide between orbit, satellite, waiting and failed places
const FADE_S = 0.6;              // reduced motion: fade in or out in place
// A thread waiting on its owner leaves its ring for the ask arc beside his head and shrinks into
// the dot of a 3D question mark (effects.js grows the hook; "!" for an approval). Slots alternate
// right and left from ASK_TOP_DEG above level, ASK_STEP_DEG lower each pair, oldest ask first,
// each ASK_CLEAR orb sizes (more by ASK_LOW below level) outside the edge of an orb on the
// outermost ring in use; past ASK_PER_ARC (half that when only one side has room) a further arc
// ASK_OUTER_STEP out, with smaller dots. A mark stays at least ASK_MIN_S once formed.
const ASK_CLEAR = 0.22, ASK_LOW = 0.5, ASK_OUTER_STEP = 0.95, ASK_PER_ARC = 6, ASK_TOP_DEG = 26, ASK_STEP_DEG = 24;
const ASK_DOT = 0.62, ASK_OUTER = 0.8;   // the dot's size, and the outer arc's
const ASK_MARK = { input: '?', approval: '!' };   // what a waiting thread wants -> its mark
const ASK_HEADROOM = 2.7;                // dots of page kept clear above a dot, for its hook
const ASK_BOB_S = 2.4, ASK_BOB = 0.06;   // a fixed bob, in orb sizes
const ASK_FORM_S = 0.9, ASK_MIN_S = 1.2, ASK_RETRACT_S = 0.35;
const FAIL_SINK = 0.09;          // a failed orb sinks this many orb sizes per second
// The worry zone: failed orbs wait below and beside him, chipped, sputtering embers now and then.
const WORRY_R = 1.25;                     // his radius out from his middle
const WORRY_DEG = [30, 60], WORRY_PER_ROW = 4, WORRY_ROW = 0.9;   // below horizontal; a row further out is this many orbs
const WORRY_SCALE = 0.85, WORRY_JOLT_S = 0.6;   // it jolts on its ring this long before it goes
const SPUTTER_S = [1.6, 3.2], FLICKER_S = 0.12, FLICKER = 0.35, SHIVER = 0.015;
// A message gulped: squash along the glint's way, overshoot, then a damped spring back; a flash.
const GULP_SQUASH = [0.06, 0.9], GULP_STRETCH = [0.14, 1.08], GULP_W = 14, GULP_Z = 0.55, GULP_FLASH_S = 0.25;
// Queued messages: up to three seeds circling the orb on its first moon ring, in the gaps between
// any moons there, on a lap more open than theirs so they clear the orb (a question's dot keeps the
// moons' flat lap, clear of its mark). Seed sizes are in orb sizes; more than three makes the last bigger.
const SEEDS = 3, SEED = 0.26, SEED_BIG = 0.34, SEED_OPEN = 0.78, SEED_GROW_S = 0.3, SEED_EAT_S = 0.35, SEED_DROP_S = 0.4;
const MEND_S = 1.5;
// A thread moved to another provider: its badge flips over to the new one, and a rim of the new
// provider's colour flashes round the orb. A new model alone only flashes, at half strength.
const FLIP_IN_S = 0.18, FLIP_OUT_S = 0.24, FLIP_FLASH_S = 0.6, MODEL_FLASH_S = 0.4;
export const PROVIDER_FLASH = { claudeAgent: '#d97757', codex: '#0a84ff', kimi: '#40c8e0', antigravity: '#ff6fb1', opencode: '#c9ced6', grok: '#f5f5f7', grokBot: '#f5f5f7' };
// Snoozed: up to six orbs rest as frosted eggs in a row at his feet, soonest to wake in the middle.
const EGG_MAX = 6, EGG_GAP = 0.95, EGG_ARC = 0.06, EGG_SCALE = 0.86;   // in orb sizes
const EGG_BELOW = 0.12;                     // the eggs' middles, in ball radii below his soles
const EGG_BREATH_S = 6, EGG_BREATH = 0.01;
const EGG_ROCK_S = 60, EGG_ROCK_DEG = 6, EGG_HOP_S = 20, EGG_HOP_EVERY = 6, EGG_HOP = 0.06, EGG_HOP_LEN = 0.35;
const HATCH_CRACK_S = 0.3, HATCH_SPLIT_S = 0.6, HATCH_POP_S = 0.35;
const EGG_SLOTS = [0, 1, -1, 2, -2, 3];                       // a retried thread's orb seals in the worry zone this long, then flies home
const GAZE_SPAWN_S = 1.8;        // how long his eyes follow a new orb
const STIR_MS = 700;             // how long an orb already in orbit glows when its thread stirs again
const TRAIL_CHARS = 44;          // longest a comet-trail line gets before it is cut with "…"
const TRAIL_FONT_PX = 12;        // trail text size on a main orb; a satellite's is smaller
const SAT_TURN_S = 4;            // how long each of a parent's satellites has its tail lit
const BLUR_TAPS = [[-1.2, 0], [1.2, 0], [0, -1.2], [0, 1.2]];   // px offsets of a trail letter's glow copies
// Rings lean back only a little: `tilt` squashes each circle very slightly, and `roll` tips
// alternate rings a hair either way so stacked rings read as separate orbits.
const RING_TILT = [0.94, 0.9, 0.93, 0.89];
const RING_ROLL = [0.04, -0.05, 0.03, -0.04];
// The rings' centre sits RING_DROP orb sizes below his, and each ring is that much shorter, so
// its near point stays over his legs while its far point comes down twice that: an orb passing
// over the top tucks about a third of its height behind his head.
const RING_DROP = 0.18;
const DEPTH_SCALE = [0.86, 1.04]; // an orb's size at the far (top) and near (bottom) points of its ring
const FAILED_KEEP_S = 600;       // an unseen failed orb outlives its snapshot this long at most
const SEEN_HOVER_S = 0.6;        // hovering a failed orb this long counts as looking at it
const ACKED_FADE_S = 20;         // a seen failed orb sinks and fades over this long
const BUSY_S = 20, QUIET_S = 180, STALE_S = 600;   // a thread's last activity: busy, quiet, stale
// How hard a thread is working (0 .. 1): the feed's `level` (its timeline's growth), at least
// ACT_FLOOR for its pace. It quickens its ring (up to RING_RUSH, the mean over the ring), lets it
// press ahead of its neighbours within its slot (SURGE, never past them), and quickens and deepens its breath.
const ACT_FLOOR = { busy: 0.3, quiet: 0.05, stale: 0 };
const RING_RUSH = 0.6, MOON_RUSH = 0.5;             // a ring at full activity laps 1.6x, satellites 1.5x
const SURGE = 0.25;                                 // of a slot, at most
const BREATH_S = [3.4, 0.95];                       // an orb's breath, idle to flat out; never quicker
const BREATH_SCALE = [0.012, 0.05];                 // how much it swells at the top of a breath
const CREST = 0.12;                                 // brighter at the crest of a breath, past ACT_CREST
const ACT_CREST = 0.6;
const MOTES = 22;                // drifting specks of light along each ring
const DISSOLVE_S = 2.7;          // a limited orb darkens, shows its provider's logo and dissolves
const DISSOLVE_STILL_S = 2.2;    // ... with reduced motion: fades only
const DOOM_SIZE = 1.75;          // the provider logo over a dying orb, in orb sizes
const BADGES = {
  codex: 'codex.svg', claudeAgent: 'claudeAgent.svg', grok: 'grok.svg', antigravity: 'antigravity.svg',
  cursor: 'cursor.svg', opencode: 'opencode.svg', pi: 'pi.svg', kimi: 'kimi.svg', grokBot: 'grokBot.png',
};

const TAU = Math.PI * 2;
const clamp01 = (v) => Math.min(1, Math.max(0, v));
const easeOut = (t) => 1 - Math.pow(1 - t, 3);
const easeIn = (t) => t * t * t;
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
/// Overshoots a little past 1 and settles: an arrival "pop".
const easeOutBack = (t) => { const c = 1.6; return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2); };
const lerp = (a, b, t) => a + (b - a) * t;
const rand = (a, b) => a + Math.random() * (b - a);
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
/// Leaves d alone up to 3/4 of room, then eases it in so it never passes room.
const softLimit = (d, room) => {
  const knee = room * 0.75;
  return d <= knee ? d : knee + (room - knee) * Math.tanh((d - knee) / (room - knee));
};

/// Orb size and ring spacing in CSS px, for a body `height` px tall whose ball is `ball` px in radius.
/// The first ring sits just outside the ball's edge; each further ring is about one orb out.
export function orbitGeometry(height, ball) {
  const orb = Math.round(Math.min(ORB_MAX, Math.max(ORB_MIN, height * ORB_PER_HEIGHT)));
  return { orb, ball: Math.round(ball), gap0: Math.round(orb * 0.66), ringStep: Math.round(orb * 1.14), spacing: Math.round(orb * 1.16) };
}

/// Halo ring k: how far outside the ball it runs, its tilt and lean, how many orbs fit, and its speed.
function ringSpec(k, geo) {
  const offset = geo.gap0 + geo.ringStep * k;
  return {
    offset,
    tilt: RING_TILT[k % RING_TILT.length],
    roll: RING_ROLL[k % RING_ROLL.length],
    capacity: Math.max(6, Math.floor(TAU * (geo.ball + offset) / geo.spacing)),
    speed: TAU / (PERIOD0 * Math.sqrt(1 + k)) * (k % 2 ? -1 : 1),
  };
}

/// Splits n orbs over the fewest rings that hold them, in proportion to ring size.
export function ringCounts(n, geo) {
  if (n <= 0) return [];
  const specs = [];
  let capacity = 0;
  while (capacity < n) { const s = ringSpec(specs.length, geo); specs.push(s); capacity += s.capacity; }
  const counts = specs.map((s) => Math.floor(n * s.capacity / capacity));
  let left = n - counts.reduce((a, b) => a + b, 0);
  for (let k = specs.length - 1; left > 0; k = (k - 1 + specs.length) % specs.length) { counts[k] += 1; left -= 1; }
  return counts;
}

/// `ball()` is his ball body on the page this frame ({x, y, r}, following float, swell and drag), and
/// `soles` how far below its centre his underside rests, in ball radii (bodies/index.js);
/// `foreheadAnchor()` and `mouthAnchor()` give page points; `events` hears spawns and swallows.
export function createOrbit({ body, ball, soles, foreheadAnchor, mouthAnchor, setHitRegions, post, events = {}, front, back }) {
  const orbs = new Map();        // id -> orb record
  let order = [];                // ids in arrival order (slot order)
  let frameOrder = [];           // orbs, parents before their satellites
  let reduced = false;           // reduced motion
  let lastSpawn = null;          // { id, at } of the newest orb, for his gaze
  const rest = ball();
  const geo = orbitGeometry(body.height, rest.r);
  const ORB = geo.orb;
  front.style.setProperty('--orb', `${ORB}px`);
  back.style.setProperty('--orb', `${ORB}px`);
  // `labels` sits over every orb and mark: an asking orb's words go there, so nothing hides them.
  const lines = { front: makeCanvas(front), back: makeCanvas(back), labels: makeCanvas(front, 'orbit-labels'), dirty: { front: null, back: null } };
  const ringGlow = [];           // per ring, 0 .. 1: how lit its energy line is
  let ringsInUse = 0;
  const askReach = { x: null, v: 0 };   // the outermost ring's offset the ask arc keeps clear of, eased as rings come and go
  let wind = 0;                  // 0 .. 1: how hard air rushes into his mouth
  const dead = new Set();        // ids dissolved for a limit, kept out while the snapshot still says limited

  const glowDot = makeGlowDot();
  let pointer = null;            // { x, y, at }
  let hovered = null;
  let hoverSince = 0;
  let lastHitReport = 0;
  let clock = 0;
  // Each ring's and each parent's satellite ring's angle, advanced by dt at its own rate, so a rate
  // that changes never sweeps the slots around (see Phase in motion.js).
  const ringPhase = [];
  const ringAct = [];             // each ring's mean activity, for its pace and its orbs' surge
  const moonPhase = new Map();
  let feedStale = false;

  function faceKey(icon) { return JSON.stringify([icon?.kind, icon?.src, icon?.text, icon?.color]); }

  /// A subagent orbiting its thread wears its provider's logo; everything else its project icon.
  function faceIcon(orb) {
    if (orb.mode === 'sat') return { kind: 'provider', src: `./badges/${BADGES[orb.data.provider] || 'generic.svg'}` };
    return orb.data.projectIcon;
  }

  function refreshFace(orb) {
    const icon = faceIcon(orb);
    const key = faceKey(icon);
    if (key !== orb.faceKey) {
      orb.faceKey = key;
      buildFace(orb.face, icon);
      // A thread's provider logo is printed small on the lower part of its sphere, over the project icon.
      if (orb.mode !== 'sat' && orb.badge) { orb.face.appendChild(orb.badge); orb.face.classList.add('badged'); }
    }
  }

  function buildFace(face, icon) {
    face.textContent = '';
    face.className = 'orb-face';
    face.style.removeProperty('--ring');
    face.style.removeProperty('--c');
    if (icon?.kind === 'provider') {
      face.classList.add('provider');
      // A logo with no transparency (Grok Bot's) fills the sphere instead of sitting on it.
      if (/grokBot\.png$/.test(icon.src)) face.classList.add('photo-logo');
      const img = document.createElement('img');
      img.className = 'orb-icon'; img.alt = ''; img.draggable = false; img.src = icon.src;
      face.appendChild(img);
    } else if (icon?.kind === 'image' && icon.src) {
      const img = document.createElement('img');
      img.className = 'orb-icon';   // the badge is an img in the face too: icon rules must not reach it
      img.alt = '';
      img.draggable = false;
      img.src = icon.src;
      if (icon.color) {             // a photo avatar ringed in its colour (Grok Bot)
        face.classList.add('ringed');
        face.style.setProperty('--ring', icon.color);
      } else if (/^data:/.test(icon.src)) {
        face.classList.add('favicon');
        img.addEventListener('load', () => {
          if (img.parentNode === face && isOpaqueSquare(img)) face.classList.add('squircle');
        }, { once: true });
      } else {                      // a bundled full-bleed icon (Grok Bot's own)
        face.classList.add('photo');
      }
      img.addEventListener('error', () => buildFace(face, { kind: 'monogram', text: '?', color: '#52525b' }), { once: true });
      face.appendChild(img);
    } else {
      face.classList.add('monogram');
      face.style.setProperty('--c', icon?.color || '#52525b');
      const span = document.createElement('span');
      span.textContent = icon?.text || '?';
      if ([...(icon?.text || '')].length === 1) span.classList.add('single');
      face.appendChild(span);
    }
  }

  function isOpaqueSquare(img) {
    const w = img.naturalWidth, h = img.naturalHeight;
    if (!w || !h || Math.abs(w / h - 1) > 0.02) return false;
    const size = Math.min(w, 256);
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = size;
    const g = canvas.getContext('2d');
    g.drawImage(img, 0, 0, size, size);
    try {
      const px = g.getImageData(0, 0, size, size).data;
      const last = size - 1;
      return [[0, 0], [last, 0], [0, last], [last, last]].every(([x, y]) => px[(y * size + x) * 4 + 3] >= 250);
    } catch {                       // WebKit may taint a canvas with an SVG; that icon keeps its shape
      return false;
    }
  }

  function makeOrb(data) {
    const el = document.createElement('div');
    el.className = 'orb';
    const face = document.createElement('div');
    const badge = document.createElement('img');
    badge.className = 'orb-badge';
    badge.alt = '';
    badge.draggable = false;
    const crack = document.createElement('div');
    crack.className = 'orb-crack';
    crack.innerHTML = CRACK_SVG;
    el.append(face, crack);
    // Where a failure chips it, the same for the orb's whole life.
    const chip = (hashOf(data.id) % 360) * Math.PI / 180;
    el.style.setProperty('--chip-x', `${50 + 54 * Math.cos(chip)}%`);
    el.style.setProperty('--chip-y', `${50 + 54 * Math.sin(chip)}%`);
    const orb = {
      id: data.id, el, face, badge, data: null, faceKey: '', badgeKey: '', children: 0,
      seed: hashOf(data.id) % 6283 / 1000,
      phase: 'spawning', t0: null, from: null, leaveTo: 'mouth', delay: 0, announced: false,
      mode: null, blend: null, fadeIn: null, failAt: null, failFrom: null,
      angle: null, ring: null, target: null, sat: null, satAngle: null, wait: null, swirl: null, psy: 1, haze: 0,
      layer: null, z: null, page: { x: 0, y: 0 }, scale: 0, opacity: 0, stretch: null, depth: 1, lit: -1,
      seenAt: null, kept: false, gulp: null, queued: { seeds: [], gone: [], lap: new Phase(), eating: 0 }, eggRank: null, hatchAt: null, rotate: 0, flip: null, pace: '', stale: 0, act: { x: 0, v: 0 }, lead: { x: 0, v: 0 }, breath: new Phase(hashOf(data.id) % 7), breathDepth: { x: 0, v: 0 }, crest: { x: 1, v: 0 }, breathShown: 1, crestShown: 1, trail: [], trailFlip: false, trailText: '', trailGlow: 0, trailTurn: false,
    };
    applyData(orb, data);
    return orb;
  }

  function applyData(orb, data) {
    const before = orb.data;
    orb.data = data;
    refreshFace(orb);
    const provider = BADGES[data.provider] ? data.provider : 'generic';
    const color = PROVIDER_FLASH[data.provider] || '#8e8e93';
    if (before && before.provider !== data.provider) {
      orb.flip = { t0: clock, to: provider, color, strength: 1, flash: FLIP_FLASH_S, turn: !reduced };
      if (orb.flip.turn) return finishData(orb, data);
    } else if (before?.model && data.model && before.model !== data.model) {
      orb.flip = { t0: clock, to: null, color, strength: 0.5, flash: MODEL_FLASH_S, turn: false };
    }
    if (provider !== orb.badgeKey) setBadge(orb, provider);
    finishData(orb, data);
  }

  function setBadge(orb, provider) {
    orb.badgeKey = provider;
    orb.badge.src = `./badges/${BADGES[provider] || 'generic.svg'}`;
    orb.badge.classList.toggle('round', provider === 'grokBot');   // no transparency: cut to a circle
  }

  /// One frame of a provider flip: the badge turns edge-on (easeIn), swaps, and turns back
  /// (easeOutBack), while a rim of the new provider's colour flashes round the orb from the swap.
  function flipFrame(orb, t) {
    const f = orb.flip, since = t - f.t0;
    const flashFrom = f.turn ? FLIP_IN_S : 0;
    const u = (since - flashFrom) / f.flash;
    const flash = u >= 0 && u < 1 ? f.strength * (reduced ? 0.4 : 0.9) * Math.sin(Math.PI * (1 - Math.pow(1 - u, 3))) : 0;
    orb.el.dataset.flip = '1';
    orb.el.style.setProperty('--gulp-color', f.color);
    orb.el.style.setProperty('--gulp', flash.toFixed(3));
    if (f.turn) {
      let deg = 0;
      if (since < FLIP_IN_S) deg = 90 * easeIn(since / FLIP_IN_S);
      else {
        if (f.to && orb.badgeKey !== f.to) setBadge(orb, f.to);
        deg = since < FLIP_IN_S + FLIP_OUT_S ? 90 * (1 - easeOutBack((since - FLIP_IN_S) / FLIP_OUT_S)) : 0;
      }
      orb.badge.style.transform = deg ? `translate(-50%, -50%) rotateY(${deg.toFixed(1)}deg)` : '';
    } else if (f.to && orb.badgeKey !== f.to) {
      setBadge(orb, f.to);
    }
    if (since > flashFrom + f.flash && (!f.turn || since > FLIP_IN_S + FLIP_OUT_S)) {
      orb.flip = null; delete orb.el.dataset.flip; orb.el.style.removeProperty('--gulp'); orb.badge.style.transform = '';
    }
  }

  function finishData(orb, data) {
    if (data.state === 'waiting' && orb.el.dataset.state !== 'waiting') orb.waitSince = clock;
    if (data.state !== 'waiting') orb.waitSince = null;
    orb.el.dataset.state = data.state || 'active';
    orb.el.dataset.provider = data.provider || '';
  }

  // --------------------------------------------------------------- update

  function update(snapshot) {
    const all = Array.isArray(snapshot?.orbs) ? snapshot.orbs.filter((o) => o && typeof o.id === 'string') : [];
    // Orbs whose thread left without T3 saying it finished (feed.js): they fade, never swallowed.
    const fade = new Set(Array.isArray(snapshot?.fade) ? snapshot.fade : []);
    // Failures the owner has settled in T3 count as looked at.
    for (const id of Array.isArray(snapshot?.seen) ? snapshot.seen : []) {
      const orb = orbs.get(id);
      if (orb?.mode === 'failed' && orb.seenAt === null) seen(orb, clock);
    }
    // An orb its provider refused for a limit dies where it is, once; it stays out of the scene while
    // the snapshot still says limited. One that arrives already limited never shows.
    const reported = new Set(all.map((o) => o.id));
    for (const id of dead) if (!reported.has(id)) dead.delete(id);
    const list = [], dying = [];
    for (const data of all) {
      if (!data.limited) { dead.delete(data.id); list.push(data); continue; }
      if (dead.has(data.id)) continue;
      dead.add(data.id);
      const orb = orbs.get(data.id);
      if (orb && orb.phase !== 'leaving') { dissolve(orb, data.limitProvider || data.provider); dying.push(data.id); }
    }
    const incoming = new Map(list.map((o) => [o.id, o]));
    const added = [], removed = [];
    for (const data of list) {
      let orb = orbs.get(data.id);
      // Back from a limit while it was still dissolving: that one goes, and it comes out anew.
      if (orb && orb.phase === 'leaving' && orb.leaveTo === 'dissolve') { remove(orb); orb = null; }
      if (!orb) {
        orbs.set(data.id, makeOrb(data));
        added.push(data.id);
      } else {
        const wasAt = orb.data.activeAt;
        applyData(orb, data);
        // The same thread doing something new after a lull (a message sent to it, a new turn): the
        // orb it already has glows for a moment, never a new orb.
        if (orb.phase === 'live' && (orb.pace === 'quiet' || orb.pace === 'stale') && typeof data.activeAt === 'number' && typeof wasAt === 'number' && data.activeAt > wasAt) stir(orb);
        if (orb.phase === 'leaving') {   // came back before it landed: fly out again from where it is
          orb.phase = 'spawning'; orb.t0 = null; orb.delay = 0; orb.stretch = null;
          orb.from = { ...orb.page, scale: orb.scale };
          added.push(data.id);
        }
      }
    }
    // A message taken off a queue keeps its seed until the glint bringing it lands (gulp).
    for (const m of Array.isArray(snapshot?.messages) ? snapshot.messages : []) {
      const orb = m?.fromQueue ? orbs.get(m.id) : null;
      if (orb) orb.queued.eating += 1;
    }
    // A parent stays while anything in the snapshot circles it, even when the snapshot drops it,
    // so its satellites never fall out onto the halo.
    const parents = new Set();
    for (let queue = list.map((o) => o.parentId).filter(Boolean); queue.length;) {
      const pid = queue.pop();
      if (parents.has(pid)) continue;
      parents.add(pid);
      const held = orbs.get(pid);
      if (held?.data.parentId) queue.push(held.data.parentId);
    }
    let queued = 0;
    for (const [id, orb] of orbs) {
      orb.kept = false;
      if (!incoming.has(id) && parents.has(id) && orb.phase !== 'leaving') {
        orb.kept = true;
        continue;
      }
      // A failed orb you have not looked at yet stays, even though its thread has gone.
      if (!incoming.has(id) && orb.mode === 'failed' && orb.phase === 'live' && orb.seenAt === null && clock - (orb.failAt ?? clock) < FAILED_KEEP_S) {
        orb.kept = true;
        continue;
      }
      if (!incoming.has(id) && orb.phase !== 'leaving') {
        // A failed orb fades where it is; a satellite goes back into its parent if the parent stays;
        // everything else is swallowed, one after another.
        const parent = orb.data.parentId ? orbs.get(orb.data.parentId) : null;
        orb.leaveTo = reduced || orb.mode === 'failed' || fade.has(id) ? 'fade'
          : orb.mode === 'sat' && parent && incoming.has(parent.id) ? 'parent' : 'mouth';
        orb.delay = orb.leaveTo === 'mouth' ? queued++ * SWALLOW_STAGGER_S : 0;
        // An egg whose thread finished hatches before it is swallowed.
        if (orb.mode === 'egg' && orb.leaveTo === 'mouth' && !reduced) { hatch(orb); orb.delay += HATCH_CRACK_S + HATCH_SPLIT_S + 1; }
        orb.phase = 'leaving'; orb.t0 = null; orb.announced = false;
        orb.from = { ...orb.page, scale: orb.scale, opacity: orb.opacity };
        removed.push(id);
      }
    }
    order = order.filter((id) => incoming.has(id) || orbs.get(id)?.kept).concat(list.map((o) => o.id).filter((id) => !order.includes(id)));
    assignLayout();
    return { added, removed, dying };
  }

  /// Starts a limited orb's death where it is: it stops, darkens under a big copy of its provider's
  /// logo, and dissolves (see dissolveFrame).
  function dissolve(orb, provider) {
    const key = BADGES[provider] ? provider : 'generic';
    const logo = document.createElement('img');
    logo.className = 'orb-doom';
    logo.alt = '';
    logo.draggable = false;
    logo.src = `./badges/${BADGES[key] || 'generic.svg'}`;
    logo.classList.toggle('round', key === 'grokBot');
    orb.el.appendChild(logo);
    orb.doom = { logo, provider: key, filters: reduced ? null : [dissolveFilter(orb.seed, 0.075), dissolveFilter(orb.seed + 3.1, 0.05)] };
    orb.phase = 'leaving'; orb.leaveTo = 'dissolve'; orb.t0 = null; orb.delay = 0; orb.announced = false; orb.blend = null;
    orb.from = { ...orb.page, scale: orb.scale || 1, opacity: orb.opacity || 1 };
    orb.el.dataset.dying = '1';
    orb.el.classList.remove('psychic', 'emerging', 'hover', 'cracking');
  }

  /// The orb's parent when it can orbit it: present, not leaving, and no loop in the chain.
  function parentOf(orb) {
    let parent = orb.data.parentId ? orbs.get(orb.data.parentId) : null;
    if (!parent || parent.phase === 'leaving') return null;
    for (let p = parent, n = 0; p; p = p.data.parentId ? orbs.get(p.data.parentId) : null, n += 1) {
      if (p === orb || n > 64) return null;
    }
    return parent;
  }

  function modeOf(orb) {
    if (orb.eggRank != null) return 'egg';
    if (orb.data.state === 'waiting') return 'waiting';
    // Answered within moments of asking: the mark still shows long enough to read.
    if (orb.mode === 'waiting' && orb.data.state !== 'failed' && clock - orb.askedAt < ASK_FORM_S + ASK_MIN_S) {
      orb.askHeldUntil = orb.askedAt + ASK_FORM_S + ASK_MIN_S;
      return 'waiting';
    }
    if (orb.data.state === 'failed') return 'failed';
    return parentOf(orb) ? 'sat' : 'main';
  }

  /// Places every orb: main orbs get halo slots in arrival order, satellites slots on their
  /// parent's small rings, waiting orbs a spot in front of him. A changed place starts a glide.
  function assignLayout() {
    const live = order.map((id) => orbs.get(id)).filter((o) => o && o.phase !== 'leaving');
    // Snoozed threads rest as eggs, the six waking soonest; any more stay where they are.
    const snoozed = live.filter((o) => o.data.snoozedUntil != null && !o.data.parentId).sort((a, b) => a.data.snoozedUntil - b.data.snoozedUntil);
    for (const orb of live) orb.eggRank = null;
    snoozed.slice(0, EGG_MAX).forEach((orb, rank) => { orb.eggRank = rank; });
    for (const orb of live) {
      const mode = modeOf(orb);
      if (mode !== orb.mode) {
        if (orb.mode !== null && orb.phase !== 'spawning') {
          if (reduced) orb.fadeIn = null; else orb.blend = { from: { ...orb.page, scale: orb.scale }, t0: null };
        }
        if (mode === 'failed') { orb.failAt = null; orb.failFrom = null; orb.seenAt = null; orb.failedAt = clock; crackOpen(orb); }
        // A failed thread that runs again mends where it waited, then flies home (see goalOf).
        if (orb.mode === 'failed' && mode !== 'failed' && orb.worrySpot && orb.seenAt === null) {
          orb.mendAt = clock; orb.mendFrom = orb.worrySpot; orb.blend = null; orb.el.dataset.mending = '1';
          events.mended?.(orb);
        }
        const was = orb.mode;
        orb.mode = mode;
        refreshFace(orb);
        if (mode === 'failed' && was !== 'failed') events.failed?.(orb);
        if (mode === 'waiting' && was !== 'waiting') { orb.askedAt = clock; orb.answeredAt = null; events.waiting?.(orb); }
        if (was === 'waiting' && mode !== 'waiting') orb.answeredAt = clock;
        if (mode === 'egg') { orb.el.dataset.egg = '1'; orb.hatchAt = null; }
        if (was === 'egg' && mode !== 'egg') hatch(orb);
      }
      orb.target = null; orb.sat = null; orb.wait = null;
    }

    const main = live.filter((o) => o.mode === 'main');
    let i = 0;
    const counts = ringCounts(main.length, geo);
    ringsInUse = counts.length;
    counts.forEach((count, k) => {
      const spec = ringSpec(k, geo);
      for (let j = 0; j < count; j += 1, i += 1) {
        const orb = main[i];
        // Slot 0 starts at the top of the halo, above his head.
        orb.target = { ring: k, spec, slot: -Math.PI / 2 + TAU * j / count + k * 0.5, spacing: TAU / count };
        if (!orb.ring) orb.ring = { offset: spec.offset, tilt: spec.tilt, roll: spec.roll };
      }
    });

    // Every subagent counts towards its parent's number (for its tooltip), wherever it is in the scene.
    const children = new Map();
    for (const orb of live) {
      const key = orb.data.parentId;
      if (key) children.set(key, (children.get(key) || 0) + 1);
    }
    for (const orb of live) orb.children = children.get(orb.id) || 0;
    orbs.forEach((orb) => { orb.el.dataset.mode = orb.mode || ''; });

    const sats = new Map();
    for (const orb of live.filter((o) => o.mode === 'sat')) {
      const key = orb.data.parentId;
      if (!sats.has(key)) sats.set(key, []);
      sats.get(key).push(orb);
    }
    for (const group of sats.values()) {
      // Rings of satellites around the parent: each further ring holds more.
      let k = 0, start = 0;
      while (start < group.length) {
        const capacity = 5 + 3 * k;
        const ring = group.slice(start, start + capacity);
        ring.forEach((orb, j) => { orb.sat = { ring: k, slot: TAU * j / ring.length + k * 0.9 }; });
        start += capacity; k += 1;
      }
    }

    const failed = live.filter((o) => o.mode === 'failed').sort((a, b) => a.failedAt - b.failedAt);
    failed.forEach((orb, index) => { orb.worry = index; });

    const waiting = live.filter((o) => o.mode === 'waiting').sort((a, b) => (a.waitSince ?? a.askedAt) - (b.waitSince ?? b.askedAt));
    waiting.forEach((orb, index) => { orb.wait = { index, count: waiting.length }; });

    // Parents first, so a satellite reads its parent's position from the same frame.
    const depthOf = (orb) => { let d = 0; for (let p = parentOf(orb); p && d < 64; p = parentOf(p)) d += 1; return d; };
    frameOrder = [...orbs.values()].map((o) => [o, o.mode === 'sat' ? depthOf(o) : 0]).sort((a, b) => a[1] - b[1]).map(([o]) => o);
  }

  // ---------------------------------------------------------------- frame

  /// His ball on the page this frame, and how much room the screen leaves around it.
  let hub = null;
  function measureHub() {
    const b = ball();
    hub = {
      x: b.x, y: b.y, r: b.r,
      roomX: Math.max(ORB, Math.min(b.x, window.innerWidth - b.x) - ORB * 0.6),
      roomUp: Math.max(ORB, b.y - ORB * 0.6),
      roomDown: Math.max(ORB, window.innerHeight - b.y - ORB * 0.6),
    };
  }

  /// Page position and depth of a point on a halo ring. `depth` runs from -1 at the far point
  /// (the top, behind his head) to 1 at the near point (the bottom, in front of his legs). A ring wider than the screen allows beside him is
  /// narrowed and opened up vertically, so no orb leaves the screen.
  function project(ring, angle) {
    const radius = hub.r + ring.offset;
    const drop = ring.tilt === undefined ? 0 : ORB * RING_DROP;
    const ex = Math.cos(angle) * radius, ey = Math.sin(angle) * (radius * (ring.tilt ?? 1) - drop);
    const cr = Math.cos(ring.roll ?? 0), sr = Math.sin(ring.roll ?? 0);
    let dx = ex * cr - ey * sr, dy = ex * sr + ey * cr + drop;
    const fit = Math.min(1, hub.roomX / radius);
    if (fit < 1) { dx *= fit; dy *= 1 + (1 - fit) * 0.8; }
    dy = Math.sign(dy) * softLimit(Math.abs(dy), dy < 0 ? hub.roomUp : hub.roomDown);
    return { x: hub.x + dx, y: hub.y + dy, depth: ring.tilt === undefined ? 1 : Math.sin(angle) };
  }

  const depthScale = (d) => lerp(DEPTH_SCALE[0], DEPTH_SCALE[1], (d + 1) / 2);

  /// How far a parent of scale `ps` keeps its moons on satellite ring `ring`, centre to centre.
  const moonRadius = (ps, ring) => ORB * ps * (0.5 + SAT_SCALE * (0.5 + 1.25 * ring)) + ORB * 0.1;

  /// Which side of him a waiting orb's place is on: 1 right, -1 left. Questions alternate sides,
  /// unless only one side has room for them (askRoom).
  const askSide = (orb) => askRoom || (orb.wait.index % 2 ? -1 : 1);
  let askRoom = 0;

  /// A dot on the ask arc, before it is kept on the page: out along its bearing from where the
  /// outermost ring crosses it, however that ring is squeezed to fit the screen.
  function askPlace(side, angle, arc) {
    const size = ORB * ASK_DOT * (arc ? ASK_OUTER : 1);
    const edge = project({ ...ringSpec(Math.max(0, ringsInUse - 1), geo), offset: askReach.x ?? 0 }, Math.atan2(-Math.sin(angle), side * Math.cos(angle)));
    const dx = edge.x - hub.x, dy = edge.y - hub.y, d = Math.hypot(dx, dy) || 1;
    // Below level its hook rises back toward the ring, so it stands further out.
    const out = ORB * depthScale(edge.depth) / 2 + ORB * (ASK_CLEAR + ASK_LOW * Math.max(0, -Math.sin(angle)) + arc * ASK_OUTER_STEP) + size / 2;
    return { x: edge.x + dx / d * out, y: edge.y + dy / d * out, size };
  }

  /// When the screen's edge would pull the ask arc's widest dot on one side back over his rings,
  /// the side that pulls it least takes every question; 0 while both sides have room.
  function measureAskRoom() {
    const short = (side) => { const p = askPlace(side, 0, 0); return Math.max(0, p.size * 0.7 - p.x, p.x + p.size * 0.7 - window.innerWidth); };
    const right = short(1), left = short(-1);
    askRoom = Math.max(right, left) <= ORB * 0.25 ? 0 : right <= left ? 1 : -1;
  }

  /// A waiting orb's place on the ask arc, as the dot of its question mark.
  function askSlot(orb, t, motion) {
    const perArc = askRoom ? ASK_PER_ARC / 2 : ASK_PER_ARC;
    const arc = Math.floor(orb.wait.index / perArc), i = orb.wait.index % perArc;
    // A further arc's slots fall between the nearer arc's, so their hooks miss its dots.
    const angle = (ASK_TOP_DEG - ASK_STEP_DEG * ((askRoom ? i : Math.floor(i / 2)) + (arc % 2) / 2)) * Math.PI / 180;
    const bob = motion * Math.sin(t * TAU / ASK_BOB_S + orb.seed) * ORB * ASK_BOB;
    const scale = ASK_DOT * (arc ? ASK_OUTER : 1);
    const p = askPlace(askSide(orb), angle, arc);
    // Kept on the page with room above for its hook (effects.js draws it 2.1 dots tall, nearer the camera than the dot).
    const x = Math.min(window.innerWidth - p.size * 0.7, Math.max(p.size * 0.7, p.x));
    const y = Math.max(p.size * ASK_HEADROOM, p.y + bob);
    return { x, y, scale, z: 1600 + orb.wait.index };
  }

  /// One frame of an orb gulping a message: it squashes along the glint's way, overshoots and
  /// springs back, flashing the glint's colour. With reduced motion, a 3% pulse and the flash.
  function gulpFrame(orb, t) {
    const since = t - orb.gulp.t0;
    const flash = since < GULP_FLASH_S ? 0.8 * Math.sin(Math.PI * since / GULP_FLASH_S) : 0;
    orb.el.style.setProperty('--gulp', flash.toFixed(3));
    if (reduced) {
      if (since < 0.3) orb.scale *= 1 + 0.03 * Math.sin(Math.PI * since / 0.3);
      else { orb.gulp = null; orb.el.style.removeProperty('--gulp'); }
      return;
    }
    const [s1, a1] = GULP_SQUASH, [s2, a2] = GULP_STRETCH;
    let amount;
    if (since < s1) amount = 1 - (1 - a1) * easeOut(since / s1);
    else if (since < s1 + s2) amount = a1 + (a2 - a1) * (since - s1) / s2;
    else {
      const after = since - s1 - s2;
      amount = 1 + (a2 - 1) * Math.exp(-GULP_Z * GULP_W * after) * Math.cos(after * GULP_W * Math.sqrt(1 - GULP_Z * GULP_Z));
      if (after > 0.8) { orb.gulp = null; orb.el.style.removeProperty('--gulp'); return; }
    }
    orb.stretch = { angle: orb.gulp.angle, amount };
  }

  /// The queue's seeds for one orb this frame: one per queued message, up to SEEDS, front first,
  /// evenly round their own lap, or shared out between the gaps of its first moon ring and riding
  /// that ring's phase. A message taken off the queue keeps its seed until the orb gulps it.
  function stepSeeds(orb, dt) {
    const q = orb.queued;
    const want = orb.phase === 'live' && (orb.mode === 'main' || orb.mode === 'waiting') ? Math.min(SEEDS, (orb.data.queue || 0) + q.eating) : 0;
    while (q.seeds.length > want) {
      const s = q.seeds.pop();
      q.gone.push({ x: s.x, y: s.y, size: s.size, turn: s.turn, t0: clock, eaten: false });
    }
    while (q.seeds.length < want) q.seeds.push({ angle: null, grown: 0, x: orb.page.x, y: orb.page.y, size: 0, turn: 0 });
    q.gone = q.gone.filter((g) => clock - g.t0 < (g.eaten ? SEED_EAT_S : SEED_DROP_S));
    const motion = reduced ? 0 : 1;
    const speed = TAU / SAT_PERIOD;
    q.lap.advance(dt, speed * motion);
    if (!q.seeds.length) return;
    let moons = 0;
    for (const o of orbs.values()) if (o.mode === 'sat' && o.sat?.ring === 0 && o.phase !== 'leaving' && o.data.parentId === orb.id) moons += 1;
    const lap = moons ? moonPhase.get(`${orb.id}|0`)?.value ?? 0 : q.lap.value;
    const m = q.seeds.length;
    const ps = Math.max(0.2, orb.scale);
    const r = moonRadius(ps, 0), open = orb.mode === 'waiting' ? 0.38 : SEED_OPEN;
    const k = 1 - Math.exp(-dt * EASE_RATE);
    q.seeds.forEach((s, i) => {
      const g = moons ? i % moons : 0;
      const slot = moons ? TAU * (g + (Math.floor(i / moons) + 1) / (Math.floor((m - 1 - g) / moons) + 2)) / moons : TAU * i / m;
      const goal = lap + slot;
      if (s.angle === null) s.angle = goal;
      s.angle += speed * dt * motion;
      s.angle += wrap(goal - s.angle) * k;
      s.grown = reduced ? 1 : Math.min(1, s.grown + dt / SEED_GROW_S);
      const near = Math.sin(s.angle);
      s.x = orb.page.x + Math.cos(s.angle) * r;
      s.y = orb.page.y + near * r * open;
      // Its point trails behind it along the lap.
      s.turn = Math.atan2(-Math.cos(s.angle) * open, Math.sin(s.angle));
      s.size = ORB * ps * (i === SEEDS - 1 && (orb.data.queue || 0) > SEEDS ? SEED_BIG : SEED) * easeOut(s.grown) * (0.86 + 0.14 * (near + 1) / 2);
    });
  }

  /// An egg's place: a shallow arc at his feet, soonest to wake in the middle, then out to the
  /// sides in turn.
  function eggSlot(orb) {
    const k = EGG_SLOTS[orb.eggRank];
    return {
      x: hub.x + k * ORB * EGG_GAP,
      y: Math.min(window.innerHeight - ORB * 0.7, hub.y + hub.r * (soles + EGG_BELOW) - ORB * EGG_ARC * k * k),
    };
  }

  /// Its thread woke: the egg cracks where it rests, then its shell splits away (pet.js drops two
  /// 3D half-shells) and the orb pops out. With reduced motion it crossfades.
  function hatch(orb) {
    orb.hatchAt = clock;
    orb.hatchFrom = { x: orb.page.x, y: orb.page.y };
    orb.el.dataset.hatching = '1';
    if (reduced) { delete orb.el.dataset.egg; delete orb.el.dataset.hatching; orb.hatchAt = null; orb.fadeIn = null; }
  }

  /// A hatching orb's scale and rock this frame, or null once it is out and free to fly.
  function hatchPose(orb, t) {
    const p = t - orb.hatchAt;
    if (p >= HATCH_CRACK_S && orb.el.dataset.egg) {
      delete orb.el.dataset.egg; delete orb.el.dataset.hatching;
      events.hatch?.(orb);
    }
    if (p < HATCH_CRACK_S) return { scale: EGG_SCALE, rotate: 7 * tremble(t, 30, orb.seed) * (1 - p / HATCH_CRACK_S) };
    if (p < HATCH_CRACK_S + HATCH_SPLIT_S) return { scale: lerp(0.8, 1, easeOutBack(clamp01((p - HATCH_CRACK_S) / HATCH_POP_S))), rotate: 0 };
    return null;
  }

  /// A failed orb's place in the worry zone: alternating sides, 30 to 60 degrees below his middle,
  /// four to a row, each further row a little lower and further out.
  function worrySlot(orb) {
    const row = Math.floor(orb.worry / WORRY_PER_ROW), i = orb.worry % WORRY_PER_ROW;
    const side = i % 2 ? -1 : 1;
    const angle = (WORRY_DEG[0] + (WORRY_DEG[1] - WORRY_DEG[0]) * Math.floor(i / 2) + 15 * row) * Math.PI / 180;
    const r = hub.r * WORRY_R + row * ORB * WORRY_ROW, size = ORB * WORRY_SCALE;
    return {
      x: Math.min(window.innerWidth - size * 0.6, Math.max(size * 0.6, hub.x + side * Math.cos(angle) * r)),
      y: Math.min(window.innerHeight - size * 0.6, hub.y + Math.sin(angle) * r),
    };
  }

  /// Where an orb belongs this frame, by its place.
  function goalOf(orb, t, dt, k) {
    const motion = reduced ? 0 : 1;
    if (orb.hatchAt != null && orb.phase !== 'leaving') {
      const pose = hatchPose(orb, t);
      if (pose) return { ...orb.hatchFrom, ...pose, z: 900 };
      orb.hatchAt = null;
      orb.blend = { from: { ...orb.page, scale: orb.scale }, t0: null };
    }
    if (orb.mode === 'egg') {
      // Resting: a very slow breath. Its last minute it rocks, more and more; its last twenty
      // seconds it hops every six. With reduced motion it only glows amber at its rim.
      const spot = eggSlot(orb);
      const left = orb.data.snoozedUntil - Date.now() / 1000;
      const near = clamp01(1 - left / EGG_ROCK_S);
      if (reduced) {
        orb.el.style.setProperty('--wake', near.toFixed(3));
        return { ...spot, scale: EGG_SCALE, z: 850 };
      }
      const since = EGG_HOP_S - left, hop = since > 0 ? since % EGG_HOP_EVERY : -1;
      const lift = hop >= 0 && hop < EGG_HOP_LEN ? ORB * EGG_HOP * Math.sin(Math.PI * hop / EGG_HOP_LEN) : 0;
      return {
        x: spot.x, y: spot.y - lift,
        scale: EGG_SCALE * (1 + EGG_BREATH * Math.sin(t * TAU / EGG_BREATH_S + orb.seed)),
        rotate: EGG_ROCK_DEG * near * tremble(t, 5, orb.seed),
        z: 850,
      };
    }
    if (orb.mendAt != null) {
      // Mending: sealed where it waited, the red draining out; then it glides home.
      const p = (t - orb.mendAt) / MEND_S;
      if (p < 1) return { ...orb.mendFrom, scale: lerp(WORRY_SCALE, 1, smoothstep(0.7, 1, p)), z: 900 };
      orb.mendAt = null; delete orb.el.dataset.mending;
      if (!reduced) orb.blend = { from: { ...orb.page, scale: orb.scale }, t0: null };
    }
    if (orb.mode === 'waiting' && orb.wait) return askSlot(orb, t, motion);
    if (orb.mode === 'failed') {
      // A failed orb jolts on its ring, then goes down to the worry zone beside him and waits there,
      // shivering, sputtering embers now and then, until you look at it; then it sinks and fades.
      if (orb.failAt === null) {
        orb.failAt = t;
        orb.failFrom = { ...orb.page, scale: orb.phase === 'spawning' ? WORRY_SCALE : orb.scale || 1 };
        orb.sputterAt = t + WORRY_JOLT_S + rand(...SPUTTER_S) * 0.5;
      }
      const jolting = !reduced && orb.phase !== 'spawning' && t - orb.failAt < WORRY_JOLT_S;
      if (jolting) return { x: orb.failFrom.x, y: orb.failFrom.y, scale: orb.failFrom.scale, z: 900 };
      if (orb.joltDone !== orb.failAt) {
        orb.joltDone = orb.failAt;
        if (!reduced && orb.phase !== 'spawning') orb.blend = { from: { ...orb.page, scale: orb.scale }, t0: null };
      }
      const spot = worrySlot(orb);
      orb.worrySpot = spot;
      if (orb.seenAt === null) {
        if (t >= orb.sputterAt) {
          orb.sputterAt = t + rand(...SPUTTER_S);
          orb.flickerAt = t;
          if (!reduced && orb.phase === 'live' && !orb.blend) events.sputter?.(orb);
        }
        const f = (t - (orb.flickerAt ?? -1)) / FLICKER_S;
        const opacity = reduced
          ? 0.8 + 0.2 * Math.sin(t * TAU / 3 + orb.seed)
          : f >= 0 && f < 1 ? 1 - FLICKER * Math.sin(Math.PI * f) : 1;
        return { x: spot.x + motion * tremble(t, 34, orb.seed) * ORB * SHIVER, y: spot.y, scale: WORRY_SCALE, z: 900, opacity };
      }
      const age = Math.min(t - orb.seenAt, ACKED_FADE_S);
      const y = Math.min(spot.y + motion * age * FAIL_SINK * ORB * 2, window.innerHeight - ORB * 0.6);
      const x = spot.x + motion * Math.sin(age * 0.8) * ORB * 0.12;
      return { x, y, scale: WORRY_SCALE * (1 - 0.18 * clamp01(age / ACKED_FADE_S)), z: 300, opacity: 1 - 0.7 * clamp01(age / ACKED_FADE_S) };
    }
    if (orb.mode === 'sat' && orb.sat) {
      const parent = parentOf(orb);
      if (parent) {
        const ps = Math.max(0.2, parent.scale);
        const r = moonRadius(ps, orb.sat.ring);
        const speed = TAU / (SAT_PERIOD * Math.sqrt(1 + orb.sat.ring)) * (orb.sat.ring % 2 ? -1 : 1);
        const goal = moonPhaseOf(orb.data.parentId, orb.sat.ring).value + orb.sat.slot;
        if (orb.satAngle === null) orb.satAngle = goal;
        orb.satAngle += speed * dt * motion;
        orb.satAngle += wrap(goal - orb.satAngle) * k;
        const near = Math.sin(orb.satAngle);
        return {
          x: parent.page.x + Math.cos(orb.satAngle) * r,
          y: parent.page.y + near * r * 0.38,
          scale: ps * SAT_SCALE * (0.82 + 0.26 * (near + 1) / 2),
          z: (parent.z ?? 800) + (near >= 0 ? 1 : -1),
          depth: parent.depth * 0.7 + near * 0.3,
          layer: parent.layer || front,
        };
      }
    }
    // A halo slot. Orbit motion runs for every orb that has one, so a spawning orb aims at a moving target.
    if (orb.target) {
      const spec = orb.target.spec;
      const ahead = reduced ? 0 : Math.max(-SURGE, Math.min(SURGE, SURGE * (orb.act.x - (ringAct[orb.target.ring] ?? 0))));
      spring(orb.lead, ahead * orb.target.spacing * Math.sign(spec.speed || 1), 0.8, dt);
      const goal = (ringPhase[orb.target.ring]?.value ?? 0) + orb.target.slot + orb.lead.x;
      if (orb.angle === null) orb.angle = goal;
      orb.angle += spec.speed * dt * motion;
      orb.angle += wrap(goal - orb.angle) * k;
      // A thread quiet for minutes drifts out from its ring.
      orb.ring.offset += (spec.offset + orb.stale * ORB * 0.5 - orb.ring.offset) * k;
      orb.ring.tilt += (spec.tilt - orb.ring.tilt) * k;
      orb.ring.roll += (spec.roll - orb.ring.roll) * k;
    }
    if (orb.ring && orb.angle !== null) {
      const slot = project(orb.ring, orb.angle);
      return { ...slot, scale: depthScale(slot.depth), z: 800 + Math.round(slot.depth * 60) - (orb.target?.ring ?? 0), layer: slot.depth < 0 ? back : front };
    }
    return { ...orb.page, scale: orb.scale || 1 };
  }

  function frame(t, dt) {
    clock = t;
    const reach = ringSpec(Math.max(0, ringsInUse - 1), geo).offset;
    if (askReach.x === null || reduced) askReach.x = reach; else spring(askReach, reach, 3, dt);
    // A question answered too quickly to read is let go on the pet's own clock.
    let released = false;
    for (const orb of orbs.values()) if (orb.askHeldUntil != null && t >= orb.askHeldUntil) { orb.askHeldUntil = null; released = true; }
    if (released) assignLayout();
    const anchor = foreheadAnchor();
    const home = anchor ? anchor.page : { x: hub?.x ?? 0, y: (hub?.y ?? 0) - (hub?.r ?? 0) * 0.5 };
    const k = 1 - Math.exp(-dt * EASE_RATE);
    measureHub();
    measureAskRoom();
    let mouth = null;
    advancePhases(dt);

    for (const orb of frameOrder) {
      if (!orbs.has(orb.id)) continue;
      if (orb.t0 === null) {         // a phase change takes effect from the first frame that shows it
        orb.t0 = t + orb.delay;
        if (orb.phase === 'spawning' && !orb.from) {
          lastSpawn = { id: orb.id, at: t };
          if (!parentOf(orb)) events.spawn?.(orb, reduced ? FADE_S : SPAWN_S);
        }
      }
      if (orb.kept && orb.seenAt !== null && orb.phase === 'live') {
        // A failed orb whose thread had already gone, now seen: it can go.
        orb.kept = false; orb.leaveTo = 'fade'; orb.phase = 'leaving'; orb.t0 = t; orb.delay = 0;
        orb.from = { ...orb.page, scale: orb.scale, opacity: orb.opacity };
        order = order.filter((id) => id !== orb.id);
      }
      paceOf(orb);
      breathe(orb, dt);
      const goal = goalOf(orb, t, dt, k);
      orb.z = goal.z ?? null;
      orb.stretch = null;
      // Flights and anything off the rings happen in front of him; a ring orb takes its ring's layer.
      let layer = goal.layer || front;
      let depth = goal.depth ?? 1;
      const parent = orb.mode === 'sat' || orb.leaveTo === 'parent' ? parentOf(orb) : null;

      if (orb.phase === 'spawning') {
        const duration = reduced ? FADE_S : parent ? PARENT_LEAVE_S : SPAWN_S;
        const p = clamp01((t - orb.t0) / duration);
        if (reduced) {
          orb.page = { x: goal.x, y: goal.y };
          orb.scale = goal.scale;
          orb.opacity = easeInOut(p) * (goal.opacity ?? 1);
        } else if (parent || orb.from) {
          // Satellites leave their parent's orb; an orb that turned back flies from where it is.
          const e = easeOut(p);
          const start = orb.from || { x: parent.page.x, y: parent.page.y, scale: 0.1 };
          const lift = { x: (start.x + goal.x) / 2, y: Math.min(start.y, goal.y) - ORB * 0.7 };
          orb.page = bezier(start, lift, goal, e);
          orb.scale = start.scale + (goal.scale - start.scale) * e;
          orb.opacity = clamp01(p * 4) * (goal.opacity ?? 1);
        } else {
          // Psychic: it kindles in the glowing T3 as a ball of light, condenses into itself as it
          // lifts out of his head, then spirals out round him into its slot, the way the orbit
          // flows when the slot is across from the T3, swinging wide enough to clear him.
          const a0 = Math.atan2(home.y - hub.y, home.x - hub.x), r0 = Math.hypot(home.x - hub.x, home.y - hub.y);
          const a1 = Math.atan2(goal.y - hub.y, goal.x - hub.x), r1 = Math.hypot(goal.x - hub.x, goal.y - hub.y);
          let turn = wrap(a1 - a0);
          if (orb.swirl === null) orb.swirl = Math.abs(turn) > Math.PI * 0.8 ? Math.sign(orb.target?.spec.speed || 1) : Math.sign(turn) || 1;
          // Keeps the way round it chose, however its slot moves meanwhile.
          if (Math.sign(turn) !== orb.swirl && Math.abs(turn) > 0.3) turn += orb.swirl * TAU;
          const swing = ORB * (0.35 + 0.55 * Math.abs(turn) / Math.PI) * Math.sin(Math.PI * smoothstep(0.12, 1, p));
          const a = a0 + turn * smoothstep(0.2, 0.96, p), r = lerp(r0, r1, smoothstep(0.06, 0.6, p)) + swing;
          // Near an edge of the screen the swing bends along it, as the rings do (see project); what
          // that moves the T3 and the slot themselves is taken back, so it leaves one and lands on the other.
          const fit = (x, y) => ({
            x: hub.x + Math.sign(x - hub.x) * softLimit(Math.abs(x - hub.x), hub.roomX),
            y: hub.y + Math.sign(y - hub.y) * softLimit(Math.abs(y - hub.y), y < hub.y ? hub.roomUp : hub.roomDown),
          });
          const at = fit(hub.x + Math.cos(a) * r, hub.y + Math.sin(a) * r), from = fit(home.x, home.y), to = fit(goal.x, goal.y);
          const w = smoothstep(0, 1, p);
          orb.page = { x: at.x + (1 - w) * (home.x - from.x) + w * (goal.x - to.x), y: at.y + (1 - w) * (home.y - from.y) + w * (goal.y - to.y) };
          const m = MATERIALIZE_S / SPAWN_S;
          const c = easeOut(clamp01(p / m));
          orb.scale = p < m ? 0.08 + 0.3 * c : lerp(0.38, goal.scale, easeOutBack((p - m) / (1 - m)));
          orb.opacity = c * (goal.opacity ?? 1);
        }
        if (p < 0.85) { layer = front; depth = lerp(1, depth, clamp01(p / 0.85)); }
        // Light at first, it solidifies by the time it is clear of his head; its aura fades as it settles.
        const psychic = !reduced && !parent && !orb.from && p < 1;
        orb.el.classList.toggle('psychic', psychic);
        orb.el.classList.toggle('emerging', psychic);
        if (psychic) setGlow(orb, 1 - smoothstep(0.45, 1, p), 1 - smoothstep(0.08, 0.42, p));
        if (p >= 1) { orb.phase = 'live'; orb.from = null; orb.blend = null; orb.el.classList.remove('psychic', 'emerging'); setGlow(orb, 1, 0); }
      } else if (orb.phase === 'leaving') {
        const start = orb.from;
        layer = orb.layer || front; depth = orb.depth;
        if (t < orb.t0) {
          // Queued for his mouth: it keeps its place until its turn (an egg hatches meanwhile).
          const pose = orb.hatchAt != null ? hatchPose(orb, t) : null;
          if (orb.hatchAt != null && !pose) start.scale = 1;
          orb.page = { x: start.x, y: start.y }; orb.scale = pose?.scale ?? start.scale; orb.opacity = start.opacity ?? 1;
          orb.rotate = pose?.rotate ?? 0;
        } else if (orb.leaveTo === 'dissolve') {
          if (dissolveFrame(orb, t)) { remove(orb); continue; }
        } else if (orb.leaveTo === 'fade') {
          const p = clamp01((t - orb.t0) / (orb.mode === 'failed' ? 1 : FADE_S));
          orb.page = { x: start.x, y: start.y };
          orb.scale = start.scale;
          orb.opacity = (start.opacity ?? 1) * (1 - easeInOut(p));
          if (p >= 1) { remove(orb); continue; }
        } else if (orb.leaveTo === 'parent' && parent) {
          const p = clamp01((t - orb.t0) / PARENT_LEAVE_S);
          const e = easeIn(p);
          const lift = { x: (start.x + parent.page.x) / 2, y: Math.min(start.y, parent.page.y) - ORB * 0.6 };
          orb.page = bezier(start, lift, parent.page, e);
          orb.scale = start.scale + (0.08 - start.scale) * e;
          orb.opacity = 1 - clamp01((p - 0.55) / 0.45);
          if (p >= 1) { remove(orb); continue; }
        } else {
          // Swallowed, Kirby style but polite: a tug toward his mouth, then a short spiral in.
          mouth = mouth || mouthAnchor() || home;
          if (!orb.announced) { orb.announced = true; events.swallow?.(orb, SWALLOW_S); }
          const p = clamp01((t - orb.t0) / SWALLOW_S);
          const tug = TUG_S / SWALLOW_S;
          const vx = start.x - mouth.x, vy = start.y - mouth.y;
          const r0 = Math.hypot(vx, vy) || 1, a0 = Math.atan2(vy, vx);
          if (p < tug) {
            const q = p / tug;
            const pull = Math.sin(q * Math.PI * 0.5) * ORB * 0.18 + Math.sin(q * Math.PI * 6) * ORB * 0.04 * (1 - q);
            orb.page = { x: start.x - vx / r0 * pull, y: start.y - vy / r0 * pull };
            orb.scale = start.scale;
            orb.stretch = { angle: a0, amount: 1 + 0.06 * q };
          } else {
            const u = (p - tug) / (1 - tug);
            const e = easeIn(u);
            layer = front; depth = lerp(depth, 1, clamp01(u * 3));
            const spin = (vx >= 0 ? 1 : -1) * 0.55 * e;
            const r = (r0 - ORB * 0.18) * (1 - e);
            orb.page = { x: mouth.x + Math.cos(a0 + spin) * r, y: mouth.y + Math.sin(a0 + spin) * r };
            orb.scale = start.scale * lerp(1, 0.12, easeIn(u));
            orb.stretch = { angle: a0 + spin, amount: 1.06 + 0.22 * Math.sin(u * Math.PI) };
          }
          orb.opacity = (start.opacity ?? 1) * (1 - clamp01((p - 0.86) / 0.14));
          if (p >= 1) { events.swallowed?.(orb); remove(orb); continue; }
        }
      } else {
        let page = { x: goal.x, y: goal.y }, scale = goal.scale;
        if (orb.blend) {
          if (orb.blend.t0 === null) orb.blend.t0 = t;
          const e = easeInOut(clamp01((t - orb.blend.t0) / BLEND_S));
          page = { x: lerp(orb.blend.from.x, goal.x, e), y: lerp(orb.blend.from.y, goal.y, e) };
          scale = lerp(orb.blend.from.scale, goal.scale, e);
          if (e < 0.6) layer = front;
          if (e >= 1) orb.blend = null;
        }
        // Reduced motion: a changed place shows as a short fade-in at the new spot.
        if (orb.fadeIn === null && reduced) orb.fadeIn = t;
        const fadeIn = reduced && orb.fadeIn !== null ? clamp01((t - orb.fadeIn) / FADE_S) : 1;
        orb.page = page;
        orb.scale = scale;
        orb.opacity = (goal.opacity ?? 1) * fadeIn;
        orb.rotate = goal.rotate ?? 0;
        if (orb.flip) flipFrame(orb, t);
        if (orb.gulp) gulpFrame(orb, t);
      }
      orb.depth = depth;
      place(orb, layer, t);
    }
    drawLines(t, dt);
    updateHover(t);
    if (t - lastHitReport > 0.1) { lastHitReport = t; reportHits(); }
  }

  // ---------------------------------------------------------- energy lines

  /// Draws each ring in use as a thin veil of light: two faint strands that weave about each
  /// other, specks of light drifting along them, and soft sparks that run round ahead of the
  /// orbs. The far half goes under his canvas, the near half over it, and the far side is
  /// dimmer and finer. (The wind he sucks orbs in on is 3D, in his scene: see effects.js.)
  function drawLines(t, dt) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    for (const c of [lines.front, lines.back, lines.labels]) {
      const w = Math.round(window.innerWidth * dpr), h = Math.round(window.innerHeight * dpr);
      if (c.width !== w || c.height !== h) { c.width = w; c.height = h; c.box = null; }
      const ctx = c.getContext('2d');
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      if (c.box) ctx.clearRect(c.box.x0 - 4, c.box.y0 - 4, c.box.x1 - c.box.x0 + 8, c.box.y1 - c.box.y0 + 8);
      c.box = null;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.globalCompositeOperation = 'lighter';
      ctx.lineCap = 'round';
    }
    const grow = (c, x, y) => {
      const b = c.box || (c.box = { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity });
      b.x0 = Math.min(b.x0, x * dpr - 30); b.y0 = Math.min(b.y0, y * dpr - 30);
      b.x1 = Math.max(b.x1, x * dpr + 30); b.y1 = Math.max(b.y1, y * dpr + 30);
    };
    const dot = (at, size, alpha) => {
      const c = at.depth < 0 ? lines.back : lines.front;
      const ctx = c.getContext('2d');
      ctx.globalAlpha = Math.min(1, alpha);
      ctx.drawImage(glowDot, at.x - size / 2, at.y - size / 2, size, size);
      ctx.globalAlpha = 1;
      grow(c, at.x, at.y);
    };
    const kk = 1 - Math.exp(-dt * 2.5);
    const motion = reduced ? 0 : 1;
    const rings = Math.max(ringsInUse, ringGlow.length);
    for (let k = 0; k < rings; k += 1) {
      ringGlow[k] = (ringGlow[k] ?? 0) + ((k < ringsInUse ? 1 : 0) - (ringGlow[k] ?? 0)) * kk;
      const glow = ringGlow[k];
      if (glow < 0.01) continue;
      const spec = ringSpec(k, geo);
      const N = 120, CH = 4;
      for (const strand of [0, 1]) {
        // Each strand wanders a few px in and out of the ring, out of step with the other.
        const pts = [];
        for (let i = 0; i <= N; i += 1) {
          const a = TAU * i / N;
          const wobble = Math.sin(a * 5 + t * 0.9 * motion + strand * 2.6 + k) * ORB * 0.035 + Math.sin(a * 3 - t * 0.6 * motion + strand) * ORB * 0.02;
          pts.push(project({ ...spec, offset: spec.offset + wobble }, a));
        }
        for (let i = 0; i < N; i += CH) {
          const mid = pts[Math.min(N, i + CH / 2)];
          const c = mid.depth < 0 ? lines.back : lines.front;
          const ctx = c.getContext('2d');
          const lit = (mid.depth + 1) / 2;
          // A slow shimmer runs along the veil.
          const shimmer = 0.55 + 0.45 * Math.sin(TAU * i / N * 4 - t * 1.3 * motion + strand * 1.7 + k);
          const hue = 258 - 40 * (0.5 + 0.5 * Math.sin(TAU * i / N + t * 0.4 + k + strand));
          for (const [width, alpha, light] of [[16, 0.022, 72], [6, 0.05, 80], [1.4, 0.14, 92]]) {
            ctx.strokeStyle = `hsla(${hue.toFixed(0)}, 90%, ${light}%, ${(alpha * glow * shimmer * (0.25 + 0.75 * lit)).toFixed(3)})`;
            ctx.lineWidth = width * (0.55 + 0.6 * lit);
            ctx.beginPath();
            ctx.moveTo(pts[i].x, pts[i].y);
            for (let j = i + 1; j <= Math.min(N, i + CH); j += 1) ctx.lineTo(pts[j].x, pts[j].y);
            ctx.stroke();
          }
          for (let j = i; j <= Math.min(N, i + CH); j += j === i ? CH : 1) grow(c, pts[j].x, pts[j].y);
        }
      }
      // Motes: specks of light drifting along the ring, twinkling, larger on the near side.
      for (let n = 0; n < MOTES; n += 1) {
        const seed = (n * 0.618 + k * 0.31) % 1;
        const a = TAU * n / MOTES + seed * 0.8 + (ringPhase[k]?.value ?? 0) * 0.7 + Math.sin(t * 0.5 + n) * 0.05 * motion;
        const at = project({ ...spec, offset: spec.offset + (seed - 0.5) * ORB * 0.22 }, a);
        const lit = (at.depth + 1) / 2;
        const twinkle = 0.5 + 0.5 * Math.sin(t * (1.5 + seed * 2) * motion + n * 2.1);
        dot(at, (5 + 7 * seed) * (0.6 + 0.6 * lit), 0.32 * glow * twinkle * (0.3 + 0.7 * lit));
      }
      // Sparks: soft points of light with a fading tail, running round ahead of the orbs.
      const comets = reduced ? 0 : 3;
      for (let n = 0; n < comets; n += 1) {
        const head = (ringPhase[k]?.value ?? 0) * 2.2 + TAU * n / comets + k;
        const dir = Math.sign(spec.speed) || 1;
        for (let s = 0; s <= 10; s += 1) {
          const at = project(spec, head - dir * s * 0.04);
          const fade = 1 - s / 11, lit = (at.depth + 1) / 2;
          dot(at, (s === 0 ? 20 : 12 * fade + 3) * (0.6 + 0.6 * lit), (s === 0 ? 0.7 : 0.32 * fade) * glow * (0.3 + 0.7 * lit));
        }
      }
    }
    for (let k = ringGlow.length - 1; k >= ringsInUse && ringGlow[k] < 0.01; k -= 1) ringGlow.pop();
    // Satellites' tails would run over the satellites behind them: one per parent is lit at a time.
    const turns = new Map();
    for (const orb of orbs.values()) {
      if (orb.mode !== 'sat' || orb.phase === 'leaving' || !trailWords(orb)) continue;
      if (!turns.has(orb.data.parentId)) turns.set(orb.data.parentId, []);
      turns.get(orb.data.parentId).push(orb);
    }
    for (const group of turns.values()) {
      group.sort((a, b) => (a.id < b.id ? -1 : 1));
      const lit = group[Math.floor(t / SAT_TURN_S) % group.length];
      for (const orb of group) orb.trailTurn = orb === lit;
    }
    for (const orb of orbs.values()) { drawTrail(orb, dt, grow); stepSeeds(orb, dt); }

    // How hard air rushes into his mouth: pet.js draws it as 3D wind.
    let sucking = false;
    for (const orb of orbs.values()) if (orb.phase === 'leaving' && orb.leaveTo === 'mouth' && clock >= orb.t0) sucking = true;
    wind += ((sucking && !reduced ? 1 : 0) - wind) * (1 - Math.exp(-dt * (sucking ? 6 : 3)));
  }

  /// What a thread is doing, for its comet trail: its latest activity, or that it needs you or
  /// failed. Nothing for a thread that has said nothing yet.
  function trailWords(orb) {
    const d = orb.data;
    const words = d.state === 'waiting' ? 'needs you' : d.state === 'failed' ? 'failed' : (d.activity || '');
    const most = orb.mode === 'sat' ? Math.round(TRAIL_CHARS * 0.6) : TRAIL_CHARS;
    if (words.length <= most) return words;
    // Cut at a word boundary when there is one past halfway.
    const cut = words.slice(0, most - 1);
    const space = cut.lastIndexOf(' ');
    return (space > most / 2 ? cut.slice(0, space) : cut).replace(/[\s,;:-]+$/, '') + '…';
  }

  /// Lays an orb's words along the path it has just flown, a letter at a time, each turned to
  /// the path and fading out toward the tail; a soft halo of the same letters under them makes
  /// them glow. The path is kept as page points spaced ~2px apart; where it runs out (an orb
  /// sitting still) the words carry on straight. Words read left to right whichever way the orb
  /// is going: heading right, they end at the orb instead of starting there.
  function drawTrail(orb, dt, grow) {
    const words = trailWords(orb);
    const live = orb.phase !== 'leaving' && orb.opacity > 0.05 && words;
    const want = !live ? 0 : (orb === hovered ? 1 : orb.mode === 'waiting' ? 0.75 : orb.mode === 'failed' ? (orb.seenAt === null ? 0.7 : 0.25) : (orb.mode === 'sat' ? (orb.trailTurn ? 0.5 : 0) : 0.78) * (1 - 0.6 * orb.stale));
    orb.trailGlow += (want - orb.trailGlow) * (1 - Math.exp(-dt * 5));
    if (live) orb.trailText = words;
    // Remember the path, newest first.
    const head = { x: orb.page.x, y: orb.page.y, depth: orb.depth };
    const last = orb.trail[0];
    if (!last || Math.hypot(head.x - last.x, head.y - last.y) > 2) orb.trail.unshift(head);
    else orb.trail[0] = { ...head, x: last.x, y: last.y };
    if (orb.trailGlow < 0.01 || !orb.trailText) { if (orb.trail.length > 400) orb.trail.length = 400; return; }

    const sat = orb.mode === 'sat';
    const size = TRAIL_FONT_PX * (sat ? 0.85 : 1) * (0.85 + 0.15 * orb.scale);
    const font = `600 ${size.toFixed(1)}px ui-rounded, "SF Pro Rounded", -apple-system, system-ui, sans-serif`;
    const measure = lines.front.getContext('2d');
    measure.font = font;
    const chars = [...orb.trailText];
    const widths = chars.map((c) => measure.measureText(c).width);
    const total = widths.reduce((a, b) => a + b, 0);
    // An asking orb's words stand level beside its mark, clear of its "?" (0.6 of a dot to either
    // side) and of any moons or seeds round its dot, not along the way it flew in, which runs up
    // under its hook: on the side away from him, or toward him when the screen's edge leaves no room.
    const asking = orb.mode === 'waiting' && orb.wait;
    const gap = !asking ? ORB * orb.scale / 2 + 5 : (orb.children || orb.queued.seeds.length ? moonRadius(orb.scale, 0) + ORB * orb.scale * SAT_SCALE / 2 : ORB * orb.scale * 0.6) + 6;
    const need = gap + total + 4;

    // The path as arc-length samples from the orb backward, extended straight if it runs short.
    const path = [asking ? { ...head, depth: 1 } : head];
    let length = 0;
    if (asking) {
      const out = askSide(orb);
      const side = (out > 0 ? head.x + need <= window.innerWidth - 4 : head.x - need >= 4) ? out : -out;
      path.push({ x: head.x + side * need, y: head.y, depth: 1 });
      length = need;
    }
    for (let i = 1; !asking && i < orb.trail.length && length < need; i += 1) {
      const a = path[path.length - 1], b = orb.trail[i];
      length += Math.hypot(b.x - a.x, b.y - a.y);
      path.push(b);
    }
    orb.trail.length = Math.min(orb.trail.length, path.length + 8);
    if (length < need) {
      const a = path[Math.max(0, path.length - 2)], b = path[path.length - 1];
      let dx = b.x - a.x, dy = b.y - a.y;
      const d = Math.hypot(dx, dy);
      if (d < 0.5) { dx = 1; dy = 0; } else { dx /= d; dy /= d; }
      path.push({ x: b.x + dx * (need - length), y: b.y + dy * (need - length), depth: b.depth });
    }
    const at = (s) => {
      let walked = 0;
      for (let i = 1; i < path.length; i += 1) {
        const a = path[i - 1], b = path[i];
        const d = Math.hypot(b.x - a.x, b.y - a.y);
        if (walked + d >= s || i === path.length - 1) {
          const u = d ? clamp01((s - walked) / d) : 0;
          return { x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u, depth: a.depth + (b.depth - a.depth) * u, angle: Math.atan2(b.y - a.y, b.x - a.x) };
        }
        walked += d;
      }
      return { ...path[0], angle: 0 };
    };
    // Which way the tail points decides the reading direction (with a little hysteresis).
    const tail = at(need);
    const run = tail.x - head.x;
    if (orb.trailFlip ? run > 6 : run < -6) orb.trailFlip = !orb.trailFlip;

    const tint = orb.mode === 'waiting' ? [255, 196, 92] : orb.mode === 'failed' ? (orb.seenAt === null ? [255, 112, 118] : [190, 186, 200]) : [226, 214, 255];
    let s = gap;
    for (let i = 0; i < chars.length; i += 1) {
      // Laid out from the orb backward; flipped, the last letter sits nearest the orb.
      const k = orb.trailFlip ? chars.length - 1 - i : i;
      const w = widths[k];
      const p = at(s + w / 2);
      s += w;
      const fade = 1 - 0.8 * clamp01((s - gap) / (total + 1));
      const lit = (p.depth + 1) / 2;
      const alpha = orb.trailGlow * fade * orb.opacity * (0.55 + 0.45 * lit);
      if (alpha < 0.01 || chars[k] === ' ') continue;
      const c = asking ? lines.labels : p.depth < 0 ? lines.back : lines.front;
      const ctx = c.getContext('2d');
      ctx.save();
      ctx.translate(p.x, p.y);
      // Letters stand upright along the path: tail direction, or its reverse when flipped.
      ctx.rotate(orb.trailFlip ? p.angle + Math.PI : p.angle);
      ctx.font = font;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const [r, g, b] = tint;
      // The glow: a soft light behind the letter, then the letter blurred out in its tint (a few
      // offset copies, far cheaper than a canvas shadow), then a pale core.
      const halo = size * 2.4;
      ctx.globalAlpha = Math.min(1, alpha * 0.36);
      ctx.drawImage(glowDot, -halo / 2, -halo / 2, halo, halo);
      ctx.globalAlpha = 1;
      ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${Math.min(1, alpha * 0.26).toFixed(3)})`;
      for (const [ox, oy] of BLUR_TAPS) ctx.fillText(chars[k], ox, oy);
      ctx.fillStyle = `rgba(${Math.round((r + 255) / 2)}, ${Math.round((g + 255) / 2)}, ${Math.round((b + 255) / 2)}, ${Math.min(1, alpha).toFixed(3)})`;
      ctx.fillText(chars[k], 0, 0);
      ctx.restore();
      grow(c, p.x, p.y);
    }
  }

  /// How lively an orb's thread is, from when it last did anything: breathing fast while busy,
  /// slowly when quiet, still and dim once it has been quiet for minutes (`stale`, 0 .. 1).
  function paceOf(orb) {
    const at = orb.data.activeAt;
    const age = typeof at === 'number' ? Math.max(0, Date.now() / 1000 - at) : 0;
    const pace = orb.mode !== 'main' && orb.mode !== 'sat' ? '' : age < BUSY_S ? 'busy' : age < QUIET_S ? 'quiet' : 'stale';
    if (pace !== orb.pace) { orb.pace = pace; orb.el.dataset.pace = pace; }
    const stale = orb.mode === 'main' ? clamp01((age - QUIET_S) / (STALE_S - QUIET_S)) : 0;
    if (Math.abs(stale - orb.stale) > 0.02) { orb.stale = stale; orb.el.style.setProperty('--stale', stale.toFixed(2)); }
  }

  /// Moves every ring's angle on by this frame's dt, and every satellite ring's, each quicker the
  /// harder its orbs are working (the mean, so the orbs on a ring keep their order).
  function advancePhases(dt) {
    const motion = reduced ? 0 : 1;
    const rings = Math.max(ringsInUse, ringPhase.length);
    const sums = new Map();
    for (const orb of orbs.values()) {
      const key = orb.mode === 'sat' && orb.sat ? `${orb.data.parentId}|${orb.sat.ring}` : orb.mode === 'main' && orb.target && orb.phase === 'live' ? orb.target.ring : null;
      if (key === null) continue;
      const sum = sums.get(key) ?? [0, 0];
      sums.set(key, [sum[0] + orb.act.x, sum[1] + 1]);
    }
    const mean = (key) => { const sum = sums.get(key); return sum ? sum[0] / sum[1] : 0; };
    for (let ring = 0; ring < rings; ring += 1) {
      ringPhase[ring] ??= new Phase();
      ringAct[ring] = mean(ring);
      ringPhase[ring].advance(dt, ringSpec(ring, geo).speed * Math.min(1 + RING_RUSH, 1 + RING_RUSH * ringAct[ring]) * motion);
    }
    for (const key of sums.keys()) {
      if (typeof key !== 'string') continue;
      const ring = Number(key.slice(key.lastIndexOf('|') + 1));
      const parentId = key.slice(0, key.lastIndexOf('|'));
      moonPhaseOf(parentId, ring).advance(dt, TAU / (SAT_PERIOD * Math.sqrt(1 + ring)) * (ring % 2 ? -1 : 1) * Math.min(1 + MOON_RUSH, 1 + MOON_RUSH * mean(key)) * motion);
    }
    for (const key of moonPhase.keys()) if (!sums.has(key)) moonPhase.delete(key);
  }

  function moonPhaseOf(parentId, ring) {
    const key = `${parentId}|${ring}`;
    if (!moonPhase.has(key)) moonPhase.set(key, new Phase());
    return moonPhase.get(key);
  }

  /// An orb's breath (`--pulse`, its face's scale, and `--crest`, its brightness): quicker and
  /// deeper the harder its thread works, still once stale or while the feed cannot see T3. Activity
  /// eases in over a few seconds, so a burst quickens the breath it is in rather than snapping.
  /// With Reduce Motion it does not swell: it steps brighter with activity instead.
  function breathe(orb, dt) {
    const level = typeof orb.data.level === 'number' ? orb.data.level : 0;
    const breathing = orb.pace in ACT_FLOOR && orb.pace !== 'stale' && !feedStale;
    spring(orb.act, breathing ? Math.max(level, ACT_FLOOR[orb.pace]) : 0, 1.2, dt);
    const a = clamp01(orb.act.x);
    spring(orb.breathDepth, breathing && !reduced ? lerp(BREATH_SCALE[0], BREATH_SCALE[1], a) : 0, 1.5, dt);
    orb.breath.advance(dt, TAU / lerp(BREATH_S[0], BREATH_S[1], a));
    const swell = 0.5 - 0.5 * Math.cos(orb.breath.value);
    const scale = 1 + clamp01(orb.breathDepth.x / BREATH_SCALE[1]) * BREATH_SCALE[1] * swell;
    if (Math.abs(scale - orb.breathShown) >= 0.002) { orb.breathShown = scale; orb.face.style.setProperty('--pulse', scale.toFixed(4)); }
    const lit = reduced ? (breathing ? [1, 1 + CREST / 2, 1 + CREST][Math.min(2, Math.floor(a * 3))] : 1)
      : 1 + CREST * smoothstep(ACT_CREST, 1, a) * swell;
    spring(orb.crest, lit, reduced ? 4 : 20, dt);
    const crest = Math.round(orb.crest.x * 200) / 200;
    if (crest !== orb.crestShown) {
      orb.crestShown = crest;
      if (crest > 1.001) { orb.el.dataset.crest = ''; orb.face.style.setProperty('--crest', crest.toFixed(3)); } else delete orb.el.dataset.crest;
    }
  }

  /// How strong an orb's psychic aura is (`--psy`, 0 .. 1) and how much of it is still unformed light
  /// (`--haze`, 0 .. 1), written only when they change.
  function setGlow(orb, psy, haze) {
    psy = Math.round(psy * 50) / 50; haze = Math.round(haze * 50) / 50;
    if (psy !== orb.psy) { orb.psy = psy; orb.el.style.setProperty('--psy', String(psy)); }
    if (haze !== orb.haze) { orb.haze = haze; orb.el.style.setProperty('--haze', String(haze)); }
  }

  /// A brief glow, the one he gives an orb coming out of his forehead, on an orb already in orbit.
  function stir(orb) {
    clearTimeout(orb.stirTimer);
    orb.el.classList.add('psychic');
    orb.stirTimer = setTimeout(() => { if (orb.phase === 'live') orb.el.classList.remove('psychic'); }, STIR_MS);
  }

  /// The crack opens with a jolt.
  function crackOpen(orb) {
    orb.el.classList.remove('cracking');
    void orb.el.offsetWidth;
    orb.el.classList.add('cracking');
    setTimeout(() => orb.el.classList.remove('cracking'), 700);
  }

  /// One frame of a limited orb's death; true once it is gone. It jolts, then darkens to near black as
  /// its provider's logo grows in over it; then the sphere is eaten away from within, a glowing rim
  /// running ahead of the hole, and last the logo goes the same way. It sinks a touch as it crumbles.
  /// With reduced motion it only darkens and fades, the logo with it.
  function dissolveFrame(orb, t) {
    const still = reduced || !orb.doom.filters;
    const duration = still ? DISSOLVE_STILL_S : DISSOLVE_S;
    const u = clamp01((t - orb.t0) / duration);
    const start = orb.from;
    if (!orb.announced) {
      orb.announced = true;
      events.dying?.(orb, { x: start.x, y: start.y, r: ORB * start.scale / 2, back: orb.layer === back, duration, provider: orb.doom.provider, still });
    }
    const dark = smoothstep(0.03, 0.42, u);
    const jolt = still ? 0 : u < 0.12 ? Math.sin(u / 0.12 * Math.PI) : 0;
    const shiver = still ? 0 : tremble(t, 40, orb.seed) * ORB * 0.018 * (1 - smoothstep(0.08, 0.45, u));
    orb.page = { x: start.x + shiver, y: start.y + (still ? 0 : smoothstep(0.4, 1, u) * ORB * 0.18) };
    orb.scale = start.scale * (1 + 0.14 * jolt);
    orb.opacity = (start.opacity ?? 1) * (still ? 1 - smoothstep(0.62, 1, u) : 1);
    const [sphere, mark] = orb.doom.filters || [];
    const eat = still ? 0 : smoothstep(0.38, 0.9, u), eatLogo = still ? 0 : smoothstep(0.64, 1, u);
    if (sphere) setDissolve(sphere, eat);
    if (mark) setDissolve(mark, eatLogo);
    orb.face.style.filter = `${eat > 0 ? `url(#${sphere.id}) ` : ''}brightness(${(1 - 0.7 * dark).toFixed(3)}) saturate(${(1 - 0.8 * dark).toFixed(3)})`;
    // A cold violet rim and aura keep the darkened glass ball readable on a dark desktop; they burn
    // away with it.
    orb.el.style.setProperty('--aura', (dark * Math.pow(1 - eat, 1.5)).toFixed(3));
    // The logo swells in with a little overshoot and rises a touch, glowing so it reads on the dark.
    const grow = easeOutBack(clamp01((u - 0.05) / 0.32));
    const logo = orb.doom.logo;
    logo.style.width = logo.style.height = `${(DOOM_SIZE * 100).toFixed(0)}%`;
    logo.style.opacity = (smoothstep(0.05, 0.22, u)).toFixed(3);
    logo.style.transform = `translate(-50%, -50%) translateY(${(-(still ? 0 : smoothstep(0.1, 1, u)) * ORB * 0.25).toFixed(1)}px) scale(${(still ? 1 : 0.3 + 0.7 * grow).toFixed(3)})`;
    logo.style.filter = `${eatLogo > 0 ? `url(#${mark.id}) ` : ''}drop-shadow(0 0 ${(ORB * 0.05).toFixed(1)}px rgba(255, 255, 255, .75)) drop-shadow(0 0 ${(ORB * 0.2).toFixed(1)}px rgba(150, 110, 255, .7))`;
    if (u < 1) return false;
    for (const f of orb.doom.filters || []) f.el.remove();
    return true;
  }

  function remove(orb) {
    orb.el.remove();
    orbs.delete(orb.id);
    if (hovered === orb) hovered = null;
  }

  function bezier(a, c, b, t) {
    const u = 1 - t;
    return { x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y };
  }

  function place(orb, layer, t) {
    if (orb.layer !== layer) { layer.appendChild(orb.el); orb.layer = layer; }
    // The far side of the ring is in his shadow.
    const lit = Math.round((orb.depth + 1) * 10) / 20;
    if (lit !== orb.lit) { orb.lit = lit; orb.el.style.setProperty('--lit', String(lit)); }
    const translate = `translate3d(${(orb.page.x - ORB / 2).toFixed(1)}px, ${(orb.page.y - ORB / 2).toFixed(1)}px, 0)`;
    const s = orb.scale;
    if (orb.stretch) {
      // Stretched along the pull: rotate into the pull, scale, rotate back.
      const deg = (orb.stretch.angle * 180 / Math.PI).toFixed(1), a = orb.stretch.amount;
      orb.el.style.transform = `${translate} rotate(${deg}deg) scale(${(s * a).toFixed(3)}, ${(s / a).toFixed(3)}) rotate(${-deg}deg)`;
    } else if (orb.rotate) {
      orb.el.style.transform = `${translate} rotate(${orb.rotate.toFixed(2)}deg) scale(${s.toFixed(3)})`;
    } else {
      orb.el.style.transform = `${translate} scale(${s.toFixed(3)})`;
    }
    orb.el.style.opacity = orb.opacity.toFixed(3);
    orb.el.style.zIndex = String(orb.z ?? 800);
  }

  // ----------------------------------------------------- hover and clicks

  function rectOf(orb) {
    const r = ORB * orb.scale / 2 + 2;
    return { x: orb.page.x - r, y: orb.page.y - r, width: r * 2, height: r * 2 };
  }

  /// Orbs the mouse can reach: everything in view, nearest first.
  function hittable() {
    const hidden = (o) => o.layer === back && hub && Math.hypot(o.page.x - hub.x, o.page.y - hub.y) < hub.r * 0.95;
    return [...orbs.values()].filter((o) => o.phase !== 'leaving' && o.opacity > 0.5 && !hidden(o))
      .sort((a, b) => (b.z ?? 800) - (a.z ?? 800));
  }

  function orbAt(x, y) {
    return hittable().find((o) => { const r = rectOf(o); return x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height; }) || null;
  }

  function reportHits() {
    const rects = hittable().map((o) => {
      const r = rectOf(o);
      return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
    });
    setHitRegions('orbs', rects.length ? rects : null);
  }

  /// The orb under the mouse: T3boii hears about it (to look at it and say what it is doing),
  /// and a failed orb hovered a moment counts as seen.
  function updateHover(t) {
    const live = pointer && t - pointer.at < 3 ? orbAt(pointer.x, pointer.y) : null;
    if (live !== hovered) {
      hovered?.el.classList.remove('hover');
      hovered = live;
      hoverSince = t;
      hovered?.el.classList.add('hover');
      events.hover?.(hovered);
    }
    if (hovered?.mode === 'failed' && hovered.seenAt === null && t - hoverSince > SEEN_HOVER_S) seen(hovered, t);
  }

  function seen(orb, t) {
    orb.seenAt = t;
    orb.el.dataset.seen = '1';
  }

  window.addEventListener('pointermove', (e) => { pointer = { x: e.clientX, y: e.clientY, at: clock }; }, { passive: true });
  window.addEventListener('pointerleave', () => { pointer = null; });
  // Capture phase, so a press on an orb never starts dragging T3boii.
  window.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    const orb = orbAt(e.clientX, e.clientY);
    if (!orb) return;
    e.stopPropagation();
    e.preventDefault();
    if (orb.mode === 'failed' && orb.seenAt === null) seen(orb, clock);
    if (orb.data?.link) post({ type: 'openLink', url: orb.data.link });
  }, true);


  return {
    update,
    frame,
    /// What his eyes should follow: an orb he is swallowing, or the newest orb for a moment.
    attention(t) {
      for (const orb of orbs.values()) {
        if (orb.phase === 'leaving' && orb.leaveTo === 'mouth' && t >= orb.t0) return { kind: 'point', x: orb.page.x, y: orb.page.y };
      }
      const spawn = lastSpawn && orbs.get(lastSpawn.id);
      if (spawn && t - lastSpawn.at < GAZE_SPAWN_S && spawn.phase !== 'leaving') return { kind: 'point', x: spawn.page.x, y: spawn.page.y };
      return null;
    },
    /// An orb by id, while it is on screen.
    /// A message landed on this orb (pet.js's glint): it gulps, squashing along `angle` (radians,
    /// page), flashing `color` (CSS). If it came off the queue, its front seed is drawn in, one for
    /// each message taken off the queue since the last gulp.
    gulp(id, { angle = 0, color = '#fff1d0', fromQueue = false } = {}) {
      const orb = orbs.get(id);
      if (!orb || orb.phase === 'leaving') return;
      orb.gulp = { t0: clock, angle };
      orb.el.style.setProperty('--gulp-color', color);
      const q = orb.queued;
      if (fromQueue) {
        for (let i = 0; i < Math.max(1, q.eating) && q.seeds.length; i += 1) {
          const s = q.seeds.shift();
          q.gone.push({ x: s.x, y: s.y, size: s.size, turn: s.turn, t0: clock + 0.12 * i, eaten: true });
        }
        q.eating = 0;
      }
    },
    /// Pull request rings to draw (effects.js): each orb whose thread has one, where it is.
    prRings() {
      const out = [];
      for (const orb of orbs.values()) {
        if (!orb.data.pr || orb.phase === 'leaving' || orb.mode === 'sat' || orb.mode === 'egg') continue;
        out.push({ id: orb.id, state: orb.data.pr, x: orb.page.x, y: orb.page.y, size: ORB * orb.scale, opacity: orb.opacity, back: orb.layer === back, roll: orb.ring?.roll ?? 0 });
      }
      return out;
    },
    /// The queue seeds to draw (effects.js): per orb, page points, length, which way each points
    /// (page radians), fade, and its side.
    queueSeeds() {
      const out = [];
      for (const orb of orbs.values()) {
        const q = orb.queued;
        if (!q.seeds.length && !q.gone.length) continue;
        const behind = orb.layer === back;
        const points = q.seeds.map((s) => ({ x: s.x, y: s.y, size: s.size, turn: s.turn, back: behind }));
        for (const g of q.gone) {
          const u = clamp01((clock - g.t0) / (g.eaten ? SEED_EAT_S : SEED_DROP_S));
          if (g.eaten) {
            const e = reduced ? 0 : easeIn(u);
            points.push({ x: lerp(g.x, orb.page.x, e), y: lerp(g.y, orb.page.y, e), size: g.size * (1 - 0.5 * e), turn: g.turn, opacity: reduced ? 1 - u : 1, back: behind });
          } else {
            points.push({ x: g.x, y: g.y, size: g.size * (1 - u), turn: g.turn, opacity: 1 - u, back: behind });
          }
        }
        // The queue is its owner's: warm white, like a glint from them.
        out.push({ id: orb.id, color: 0xfff1d0, points });
      }
      return out;
    },
    orbById(id) { const orb = orbs.get(id); return orb && orb.phase !== 'leaving' ? orb : null; },
    /// The question that has waited longest, while one does.
    get oldestAskOrb() {
      let oldest = null;
      for (const orb of orbs.values()) if (orb.mode === 'waiting' && orb.phase !== 'leaving' && (!oldest || orb.wait?.index < oldest.wait?.index)) oldest = orb;
      return oldest;
    },
    /// Which side of him a question waits on: 1 right, -1 left, 0 while it has no place.
    askSide(id) { const orb = orbs.get(id); return orb?.mode === 'waiting' && orb.wait ? askSide(orb) : 0; },
    /// The question marks to draw (effects.js): each waiting orb's dot, page px and size, what it
    /// asks, how long it has waited, and, once answered, how far its hook has gone back in.
    asks() {
      const out = [];
      for (const orb of orbs.values()) {
        const answered = orb.answeredAt != null ? (clock - orb.answeredAt) / ASK_RETRACT_S : null;
        if (orb.mode !== 'waiting' && !(answered !== null && answered < 1)) continue;
        if (orb.phase === 'spawning' && orb.mode !== 'waiting') continue;
        out.push({
          id: orb.id, x: orb.page.x, y: orb.page.y, size: ORB * orb.scale, opacity: orb.opacity,
          kind: ASK_MARK[orb.data.waitingFor] ?? '!', seed: orb.seed,
          formed: clamp01((clock - (orb.askedAt ?? clock)) / ASK_FORM_S), waited: clock - (orb.waitSince ?? orb.askedAt ?? clock),
          retract: orb.mode === 'waiting' ? 0 : clamp01(answered), gone: orb.phase === 'leaving',
        });
      }
      return out;
    },
    get waitingCount() { let n = 0; for (const orb of orbs.values()) if (orb.mode === 'waiting' && orb.phase !== 'leaving') n += 1; return n; },
    /// A settled, working orb with something to say, for him to mention unprompted.
    pickChatty() {
      const live = [...orbs.values()].filter((o) => o.phase === 'live' && (o.mode === 'main' || o.mode === 'sat') && o.data.activity && o.opacity > 0.5);
      return live.length ? live[Math.floor(Math.random() * live.length)] : null;
    },
    /// How hard the busiest five orbs are working, 0 .. 1 (their mean activity).
    get fleet() {
      const acts = [...orbs.values()].filter((o) => o.phase === 'live' && (o.mode === 'main' || o.mode === 'sat')).map((o) => o.act.x).sort((a, b) => b - a).slice(0, 5);
      return acts.length ? acts.reduce((s, a) => s + a, 0) / acts.length : 0;
    },
    /// Seconds the longest-waiting question or approval has waited.
    get oldestAsk() {
      let oldest = 0;
      for (const orb of orbs.values()) if (orb.waitSince != null && orb.phase !== 'leaving') oldest = Math.max(oldest, clock - orb.waitSince);
      return oldest;
    },
    /// Failed orbs nobody has looked at yet.
    get unseenFailures() { return [...orbs.values()].filter((o) => o.mode === 'failed' && o.seenAt === null && o.phase !== 'leaving'); },
    /// Orbs doing work right now (not leaving, not failed): what powers him up.
    get activeCount() {
      let n = 0;
      for (const orb of orbs.values()) if (orb.phase !== 'leaving' && orb.mode !== 'failed') n += 1;
      return n;
    },
    /// The first orb dying of a limit, while it does: he watches it go.
    get dying() {
      for (const orb of orbs.values()) if (orb.phase === 'leaving' && orb.leaveTo === 'dissolve') return orb;
      return null;
    },
    /// Orbs on their way into his mouth, including any queued for it.
    get pendingSwallows() {
      let n = 0;
      for (const orb of orbs.values()) if (orb.phase === 'leaving' && orb.leaveTo === 'mouth') n += 1;
      return n;
    },
    /// 0 .. 1: how hard he is sucking an orb in right now.
    get wind() { return wind; },
    /// True while any orb is in flight, so the scene can render smoothly.
    get busy() {
      for (const orb of orbs.values()) if (orb.phase !== 'live' || orb.blend) return true;
      return false;
    },
    setReducedMotion(value) { reduced = !!value; },
    /// Each ring's angle (rad), mean activity and base speed (rad/s), for checks.
    rings() { return ringPhase.map((p, k) => ({ phase: p.value, act: ringAct[k] ?? 0, base: ringSpec(k, geo).speed })); },
    /// The feed cannot see T3 right now: orbs hold their breath until it can.
    setStale(value) { feedStale = !!value; },
    /// Drops every orb at once, with no flight or swallow: the demo (demo.js) clears the stage with it.
    reset() {
      for (const orb of [...orbs.values()]) { for (const f of orb.doom?.filters || []) f.el.remove(); remove(orb); }
      order = []; lastSpawn = null; wind = 0; dead.clear();
      assignLayout();
    },
    get reducedMotion() { return reduced; },
    get count() { return orbs.size; },
    get clock() { return clock; },
    geometry: { ...geo, bodyHeight: Math.round(body.height) },
    state() {
      return [...orbs.values()].map((o) => ({
        id: o.id, phase: o.phase, mode: o.mode, parent: o.mode === 'sat' ? o.data.parentId : null, children: o.children,
        x: Math.round(o.page.x), y: Math.round(o.page.y), scale: +o.scale.toFixed(2), opacity: +o.opacity.toFixed(2), depth: +o.depth.toFixed(2),
        ring: o.target?.ring ?? o.sat?.ring ?? null, pace: o.pace, stale: +o.stale.toFixed(2), seen: o.seenAt !== null, kept: o.kept, mending: o.mendAt != null,
        dying: o.leaveTo === 'dissolve' && o.phase === 'leaving', leaving: o.phase === 'leaving' ? o.leaveTo : null, pulse: +o.breathShown.toFixed(4),
        egg: o.eggRank, hatching: o.hatchAt != null, rotate: +o.rotate.toFixed(2),
      }));
    },
  };
}

const smoothstep = (a, b, v) => { const t = clamp01((v - a) / (b - a)); return t * t * (3 - 2 * t); };

// A dissolve, as an SVG filter on the orb's face (and one on its logo): fractal noise thresholded
// into a mask that eats the element away as the threshold rises, with a band just inside the edge
// of what is left lit in his violet, like embers at the rim of a burning hole.
const SVG_NS = 'http://www.w3.org/2000/svg';
let filterDefs = null, filterSeq = 0;
const DISSOLVE_SLOPE = 14, EMBER_BAND = 0.07;
function dissolveFilter(seed, frequency) {
  if (!filterDefs) {
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('width', '0'); svg.setAttribute('height', '0');
    svg.setAttribute('aria-hidden', 'true');
    svg.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
    filterDefs = document.createElementNS(SVG_NS, 'defs');
    svg.appendChild(filterDefs);
    document.body.appendChild(svg);
  }
  const node = (name, attrs, parent) => {
    const n = document.createElementNS(SVG_NS, name);
    for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, String(v));
    parent.appendChild(n);
    return n;
  };
  const id = `t3-dissolve-${++filterSeq}`;
  const el = node('filter', { id, x: '-15%', y: '-15%', width: '130%', height: '130%', 'color-interpolation-filters': 'sRGB' }, filterDefs);
  node('feTurbulence', { type: 'fractalNoise', baseFrequency: frequency, numOctaves: 3, seed: Math.round(seed * 1000) % 997, result: 'noise' }, el);
  node('feColorMatrix', { in: 'noise', type: 'matrix', values: '0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  1 0 0 0 0', result: 'grain' }, el);
  const keep = node('feFuncA', { type: 'linear', slope: DISSOLVE_SLOPE, intercept: 1 }, node('feComponentTransfer', { in: 'grain', result: 'keep' }, el));
  const hot = node('feFuncA', { type: 'linear', slope: DISSOLVE_SLOPE, intercept: 1 }, node('feComponentTransfer', { in: 'grain', result: 'hot' }, el));
  node('feComposite', { in: 'SourceGraphic', in2: 'keep', operator: 'in', result: 'body' }, el);
  node('feFlood', { 'flood-color': '#c9a8ff', result: 'ember' }, el);
  node('feComposite', { in: 'ember', in2: 'keep', operator: 'in', result: 'rim' }, el);
  node('feComposite', { in: 'rim', in2: 'hot', operator: 'out', result: 'rimBand' }, el);
  node('feComposite', { in: 'rimBand', in2: 'SourceAlpha', operator: 'in', result: 'rimLit' }, el);
  const merge = node('feMerge', {}, el);
  node('feMergeNode', { in: 'body' }, merge);
  node('feMergeNode', { in: 'rimLit' }, merge);
  return { id, el, keep, hot };
}

/// 0 .. 1: how much of the element the dissolve has eaten. Grain is fractal noise, mostly 0.25 .. 0.75.
function setDissolve(filter, amount) {
  const threshold = 0.18 + 0.7 * amount;
  filter.keep.setAttribute('intercept', (1 - DISSOLVE_SLOPE * threshold).toFixed(3));
  filter.hot.setAttribute('intercept', (1 - DISSOLVE_SLOPE * (threshold + EMBER_BAND)).toFixed(3));
}

function hashOf(text) {
  let hash = 0;
  for (const ch of text) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  return hash;
}

/// A soft round point of light, drawn once and stamped along the rings.
function makeGlowDot() {
  const size = 64, c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  grad.addColorStop(0, 'rgba(255, 252, 255, 1)');
  grad.addColorStop(0.18, 'rgba(236, 222, 255, 0.85)');
  grad.addColorStop(0.45, 'rgba(176, 140, 255, 0.28)');
  grad.addColorStop(1, 'rgba(140, 100, 255, 0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, size, size);
  return c;
}

/// Cracks across a failed orb: dark fissures with a lit edge, as if the sphere had split.
const CRACK_SVG = `<svg viewBox="0 0 100 100" aria-hidden="true"><g fill="none" stroke-linecap="round" stroke-linejoin="round">
<path d="M18 30 L36 42 L31 55 L49 63 L46 78 L58 90" stroke="rgba(255,226,226,.55)" stroke-width="5.5"/>
<path d="M18 30 L36 42 L31 55 L49 63 L46 78 L58 90" stroke="#3a0612" stroke-width="3"/>
<path d="M49 63 L66 57 L78 66 M36 42 L44 27 L60 22 M66 57 L72 41" stroke="rgba(255,226,226,.5)" stroke-width="4"/>
<path d="M49 63 L66 57 L78 66 M36 42 L44 27 L60 22 M66 57 L72 41" stroke="#3a0612" stroke-width="2"/></g></svg>`;

/// A full-page canvas at the bottom of a layer, for energy lines (or, with `extra`, wherever that class puts it).
function makeCanvas(layer, extra = '') {
  const c = document.createElement('canvas');
  c.className = `orbit-lines ${extra}`.trim();
  layer.prepend(c);
  return c;
}

/// ?fake=N: N made-up orbs across providers and monograms, for checking the scene in a browser.
/// Some have satellites (one has a parent that is not in orbit), some wait on the owner, some failed.
/// ?fake=N&churn: also shift them every few seconds to watch spawn, swallow and state changes.
const SUB_ACTIVITY = ['reading orbit.js', 'running swift build', 'thinking…', 'searching for trailWords', 'running check sounds, effects, and sad usage'];
export function fakeSnapshot(n, seed = 0) {
  const providers = ['codex', 'claudeAgent', 'grok', 'antigravity', 'cursor', 'opencode', 'pi', 'kimi', 'grokBot', 'somethingNew'];
  const names = ['data-pipeline', 'docs-site', 'game-engine', 'widgets', 'demo-app', 'notes', 'api-server', 'portfolio'];
  const colors = ['#3b82f6', '#a855f7', '#10b981', '#f97316', '#ec4899', '#14b8a6', '#eab308', '#6366f1'];
  const orbs = [];
  const icon = (j) => {
    const name = names[j % names.length];
    const initials = name.split('-').map((w) => w[0]).join('').slice(0, 2).toUpperCase();
    return { kind: 'monogram', text: initials.length > 1 ? initials : (name[0] + name.at(-1)).toUpperCase(), color: colors[j % colors.length] };
  };
  for (let i = 0; i < n; i += 1) {
    const j = i + seed;
    const name = names[j % names.length];
    const state = j % 6 === 2 ? 'waiting' : j % 9 === 4 ? 'failed' : 'active';
    const provider = providers[j % providers.length];
    orbs.push({
      id: `fake:${j}`,
      parentId: null,
      source: provider === 'grokBot' ? 'grok' : 't3',
      projectIcon: provider === 'grokBot' ? { kind: 'image', src: './badges/grokBot.png' } : icon(j),
      provider,
      state,
      label: `${name} · thread ${j}`,
    });
    if (j % 5 === 1) {
      for (let s = 0; s < 1 + (j % 3) * 2; s += 1) {
        orbs.push({
          id: `fake:${j}:sub${s}`,
          parentId: `fake:${j}`,
          source: 't3',
          projectIcon: icon(j),
          provider: providers[(j + s) % providers.length],
          state: s === 3 ? 'waiting' : 'active',
          label: `${name} · subagent ${s}`,
          activity: SUB_ACTIVITY[(j + s) % SUB_ACTIVITY.length],
        });
      }
    }
  }
  if (n > 0) {
    // A subagent whose parent is not in orbit circles T3boii directly.
    orbs.push({ id: `fake:orphan:${seed % 4}`, parentId: 'fake:not-in-orbit', source: 't3', projectIcon: icon(seed + 3), provider: 'claudeAgent', state: 'active', label: 'orphan subagent' });
  }
  return { orbs };
}
