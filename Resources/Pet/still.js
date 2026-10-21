// A deterministic still of the pet, for before/after comparisons (scripts/pet_stills.sh).
//
// `index.html?still=<scene>` replaces the page's clock, timers, frames, dates and randomness with
// synthetic ones before anything else runs (pet.js imports this module first). Once the model is
// in, it plays the scene's snapshots on a fixed 60 Hz clock, renders only the frame at the scene's
// end, and sets the title to `still:<scene>:done` (or `still:<scene>:failed`). Randomness is
// reseeded every frame, so a change that adds or drops a random draw in one frame cannot shift
// every later one. Without `?still` this module does nothing.
//
// `&film=<fps>&from=<s>` films the scene instead: it renders the first frame at `from` seconds and,
// each time `window.__stillNext()` is called, the next one 1/fps seconds of scene time later, until
// the scene's end (scripts/pet_stills.py film).

const query = new URLSearchParams(location.search);
const sceneName = query.get('still');

const EPOCH = Date.UTC(2026, 0, 15, 12, 0, 0);   // what Date.now() reads at the synthetic clock's 0
const FRAME_MS = 1000 / 60;
const BACKDROP = '#2b2834';                       // a dark desktop, so the lit pet reads as it does there

const icon = (name, color) => ({ kind: 'monogram', text: name.split('-').map((w) => w[0]).join('').toUpperCase(), color });
const DEMO = icon('demo-app', '#5b8def');
const DOCS = icon('docs-site', '#a855f7');
const thread = (n, extra = {}) => ({
  id: `still:${n}`, parentId: null, source: 't3', projectIcon: n % 2 ? DOCS : DEMO, provider: n % 3 ? 'codex' : 'claudeAgent',
  state: 'active', label: `${n % 2 ? 'docs-site' : 'demo-app'} · thread ${n}`, activity: ['reading README.md', 'running tests', 'thinking…'][n % 3], ...extra,
});
const sub = (parent, n) => thread(parent * 10 + n, { id: `still:${parent}:sub${n}`, parentId: `still:${parent}`, label: `subagent ${n}` });
const seconds = (s) => EPOCH / 1000 + s;

const working = (count) => Array.from({ length: count }, (_, i) => thread(i + 1));
const limited = (orbs, provider) => orbs.map((o) => (o.provider === provider ? { ...o, limited: true, limitProvider: provider, state: 'failed' } : o));

/// A hand that grabs him at `from` seconds, shakes him side to side until `to`, and lets go.
function shake(from, to) {
  let press = null;
  return (t) => {
    const stage = document.getElementById('stage');
    const pointer = (type, x, y, target) => target.dispatchEvent(new PointerEvent(type, { pointerId: 7, button: 0, buttons: type === 'pointerup' ? 0 : 1, clientX: x, clientY: y, bubbles: true }));
    if (t < from) return;
    if (!press) { press = window.t3boii.foreheadAnchor().page; pointer('pointerdown', press.x, press.y, stage); return; }
    if (t < to) pointer('pointermove', press.x + 120 * Math.sin((t - from) * 18.85), press.y, window);
    else if (press.x !== null) { pointer('pointerup', press.x, press.y, stage); press.x = null; }
  };
}

/// The shoggoth's ooze against the GPU: where each weeping eye and the track of ooze below it are
/// now, as the JS that lays the ooze has them and as its vertex shader moves its skin. Lengths in
/// model millimetres; `ok` when they agree to a millimetre and every track starts under its eye.
function oozeOnSkin(t3) {
  const body = t3.internals.body;
  if (!body?.deformOnGpu) return undefined;
  const { THREE, renderer } = t3.internals;
  const mm = (v) => +(v * 1000).toFixed(3);
  const gpu = body.deformOnGpu(renderer, body.oozePaths.flatMap((path) => [path.eye, ...path.points]));
  let at = 0;
  const tracks = body.oozePaths.map((path) => {
    const eye = gpu[at++], start = gpu[at];
    const miss = Math.max(body.deform(path.eye).distanceTo(eye), ...path.points.map((rest) => body.deform(rest).distanceTo(gpu[at++])));
    return {
      jsVsGpuMm: mm(miss),
      eyeMovedMm: mm(path.eye.at.distanceTo(eye)),
      eyeToOozeRestMm: mm(path.eye.at.distanceTo(path.points[0].at)),
      eyeToOozeNowMm: mm(eye.distanceTo(body.deform(path.points[0]))),
      restTrackOffMm: mm(path.points[0].at.distanceTo(start)),
    };
  });
  const turn = new THREE.Quaternion();
  body.shape.uHead.value.decompose(new THREE.Vector3(), turn, new THREE.Vector3());
  return { ok: tracks.every((k) => k.jsVsGpuMm < 1 && k.eyeToOozeRestMm < 90), headTurnDeg: +THREE.MathUtils.radToDeg(2 * Math.acos(Math.min(1, Math.abs(turn.w)))).toFixed(1), tracks };
}

/// Each scene: snapshots applied at synthetic seconds, the second its still is taken, and
/// optionally debug knobs (pet.js `debug`), a `drive(t)` run before every frame, and `evidence(t3)`,
/// what the pixels can't show, saved beside the still (a false `ok` in it fails the capture).
export const STILL_SCENES = {
  idle: { end: 6, at: [] },
  busy: {
    end: 9.05,
    at: [
      [0, { orbs: [...working(7), sub(2, 1), sub(2, 2), sub(5, 1), thread(8, { queue: 2 })] }],
      [8.7, { orbs: [...working(7), sub(2, 1), sub(2, 2), sub(5, 1), thread(8, { queue: 2 })], messages: [{ id: 'still:3', from: 'user' }, { id: 'still:6', from: 'agent' }] }],
    ],
  },
  swallow: {
    end: 7.1,
    at: [
      [0, { orbs: working(5) }],
      [6, { orbs: working(4) }],
    ],
  },
  fretful: {
    end: 24,
    at: [[0, { orbs: [...working(3), thread(4, { state: 'waiting', waitingFor: 'input' }), thread(5, { state: 'waiting', waitingFor: 'approval' }), thread(6, { state: 'failed' })] }]],
  },
  eggs: {
    end: 9,
    at: [[0, {
      orbs: [...working(4), thread(5, { snoozedUntil: seconds(600) }), thread(6, { snoozedUntil: seconds(900) }), thread(7, { snoozedUntil: seconds(1500) })],
      seeds: [
        { id: 'still-seed-1', provider: 'claudeAgent', next: seconds(120), lastRun: 1 },
        { id: 'still-seed-2', provider: 'codex', next: seconds(3600), lastRun: 1, failed: true },
        { id: 'still-seed-3', provider: 'kimi', next: seconds(240), lastRun: 1 },
      ],
    }]],
  },
  cry: {
    end: 5,
    at: [
      [0, { orbs: working(4) }],
      [3, { orbs: limited(working(4), 'codex'), limits: [{ provider: 'codex', since: seconds(3) }] }],
    ],
  },
  // Crying, then looking hard to one side while its tears run.
  weep: {
    end: 5.6,
    at: [
      [0, { orbs: working(4) }],
      [3, { orbs: limited(working(4), 'codex'), limits: [{ provider: 'codex', since: seconds(3) }] }],
    ],
    drive: (t) => { window.t3boii.debug.gaze = t >= 4.2 ? { x: 0.9, y: -0.2 } : null; },
    evidence: oozeOnSkin,
  },
  // Its mouth held open and its eyes shut: the shoggoth's mask up over its eye-flower, every eye closed.
  blink: { end: 6, debug: { mouth: 1, lid: 1 }, at: [] },
  sleep: { end: 16, debug: { sleepAfter: 3, droolAfter: 1 }, at: [] },
  dance: {
    end: 8.2,
    at: [
      [0, { orbs: working(2) }],
      [4, { orbs: [] }],
    ],
  },
  shake: { end: 3.4, at: [], drive: shake(1, 3) },
  spawn: {
    end: 5.4,
    at: [
      [0, { orbs: working(3) }],
      [5, { orbs: working(4) }],
    ],
  },
  power: { end: 12, at: [[0, { orbs: working(21) }]] },
  // Moods the shoggoth's face shows (shoggoth-face.js): dozy with nothing to do, focused on several
  // threads, satisfied just after a meal, and its eyes looking hard to one side with the lids half down.
  dozy: { end: 14, at: [] },
  focused: { end: 9, at: [[0, { orbs: working(4) }]] },
  satisfied: { end: 8.4, at: [[0, { orbs: working(3) }], [6, { orbs: working(2) }]] },
  look: { end: 6, debug: { lid: 0.45, gaze: { x: 0.9, y: 0.4 } }, at: [] },
  // Bright: 16 threads, its eyes white and its mask's U's lit, before the mask lifts at 20.
  bright: { end: 12, at: [[0, { orbs: working(16) }]] },
  // Its faces in turn, for a film: idle, new agents (surprised), focused, a meal (satisfied), a
  // failure (a flinch, then fretful), a limit (crying), a crowd (power), all done (the dance),
  // dozy, asleep.
  faces: {
    end: 54,
    debug: { sleepAfter: 5 },
    at: [
      [0, { orbs: [] }],
      [2.5, { orbs: working(4) }],
      [9, { orbs: working(3) }],
      [16, { orbs: [...working(3), thread(9, { state: 'failed' })] }],
      [22, { orbs: working(4) }],
      [23, { orbs: limited(working(4), 'codex'), limits: [{ provider: 'codex', since: seconds(23) }] }],
      [29, { orbs: working(16), limits: [] }],
      [35, { orbs: [] }],
    ],
  },
};

if (sceneName != null) install(sceneName);

function install(name) {
  const scene = STILL_SCENES[name];
  const real = { setTimeout: window.setTimeout.bind(window) };
  const done = (status) => { document.title = `still:${name}:${status}`; };
  if (!scene) { done('failed'); return; }

  let nowMs = 0;
  let seed = 1;
  Math.random = () => {
    seed = (seed + 0x6d2b79f5) >>> 0;
    let x = seed;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  const reseed = (frame) => { seed = Math.imul(frame + 1, 2654435761) >>> 0; };
  Object.defineProperty(performance, 'now', { value: () => nowMs, configurable: true });
  const RealDate = Date;
  window.Date = class StillDate extends RealDate {
    constructor(...args) { super(...(args.length ? args : [EPOCH + nowMs])); }
    static now() { return EPOCH + nowMs; }
  };

  const timers = new Map();
  let nextTimer = 1;
  const schedule = (fn, ms, args, every) => { const id = nextTimer++; timers.set(id, { at: nowMs + Math.max(0, +ms || 0), fn, args, every }); return id; };
  window.setTimeout = (fn, ms, ...args) => schedule(fn, ms, args, 0);
  window.setInterval = (fn, ms, ...args) => schedule(fn, ms, args, Math.max(1, +ms || 0));
  window.clearTimeout = window.clearInterval = (id) => { timers.delete(id); };
  let frames = [];
  let nextFrame = 1;
  window.requestAnimationFrame = (fn) => { frames.push({ id: nextFrame, fn }); return nextFrame++; };
  window.cancelAnimationFrame = (id) => { frames = frames.filter((f) => f.id !== id); };

  window.__t3boiiConfig = { ...(window.__t3boiiConfig || {}), position: { x: 600, y: 560 }, muted: true };
  const style = document.createElement('style');
  style.textContent = `html { background: ${BACKDROP} !important; } *, *::before, *::after { animation-play-state: paused !important; transition: none !important; }`;
  document.head.appendChild(style);

  const runTimers = () => {
    for (;;) {
      let due = null;
      for (const [id, timer] of timers) if (timer.at <= nowMs && (!due || timer.at < due[1].at)) due = [id, timer];
      if (!due) return;
      const [id, timer] = due;
      if (timer.every) timer.at += timer.every; else timers.delete(id);
      if (typeof timer.fn === 'function') timer.fn(...timer.args);
    }
  };

  const play = () => {
    const t3 = window.t3boii;
    Object.assign(t3.debug, { hour: 14 }, scene.debug);
    const renderer = t3.internals.renderer;
    const render = renderer.render.bind(renderer);
    const endMs = scene.end * 1000;
    const film = Number(query.get('film')) || 0;
    let shotMs = film ? Number(query.get('from') ?? 0) * 1000 : endMs;
    let rendered = false;
    renderer.render = (s, c) => { if (nowMs >= shotMs - 0.5) { render(s, c); rendered = true; } };
    const actions = scene.at.map(([at, snapshot]) => ({ ms: at * 1000, snapshot }));
    let frame = 1;
    const run = () => {
      for (rendered = false; !rendered && frame < 60 * 600; frame += 1) {
        nowMs = frame * FRAME_MS;
        reseed(frame);
        while (actions.length && actions[0].ms <= nowMs) t3.update(structuredClone(actions.shift().snapshot));
        scene.drive?.(nowMs / 1000);
        runTimers();
        const due = frames;
        frames = [];
        for (const f of due) f.fn(nowMs);
      }
    };
    run();
    if (film) window.__stillNext = () => { shotMs += 1000 / film; if (shotMs > endMs) return false; run(); return rendered; };
    if (rendered) window.__stillEvidence = scene.evidence?.(t3);
    done(rendered ? 'done' : 'failed');
  };

  const waitForPet = () => {
    if (window.__t3boiiReady) { try { play(); } catch (e) { console.error(e); done('failed'); } return; }
    if (window.__t3boiiFailed) { done('failed'); return; }
    real.setTimeout(waitForPet, 50);
  };
  real.setTimeout(waitForPet, 50);
}
