// T3boii's demo: a scripted show of his animations, about 44 seconds long, for screen recordings.
//
// window.t3boii.demo(payload) starts it (again from the top if it is already running);
// demo(false) stops it. `payload.projects` is the owner's real projects, [{ title, icon }] with
// icons resolved by Swift exactly as for live threads; `payload.grok` is Grok Bot's orb face.
// Without a payload it borrows project faces from the latest real snapshot.
//
// It only orchestrates what he already does: it feeds the orbit made-up snapshots of those
// projects' threads, puts him to sleep and hurries his drool through the existing debug knobs,
// and wakes him through his own wake path. While it runs, snapshots from Swift are kept aside
// and the mouse is ignored (it would wake or pet him); his idle fidgets are held off. When it
// ends he has the latest real snapshot back, so the orbit returns to the real threads.
//
// The arc: asleep (Zs, drool, a drip) -> woken with a start and a stretch -> threads glow out of
// his forehead, a few, then more, with subagents and activity trails; now and then one is
// swallowed -> one waits on you (held out, amber) -> one fails (flinch, cracked red orb, frown)
// and is retried -> 20+ at once: eyes white, light pouring from his mouth -> Codex hits its usage
// limit: he cries, and its threads die, dissolving under its logo -> the limit clears ->
// swallowed back in waves -> his all-done dance.
//
// limitShow(provider) (window.t3boii.debug.limit, scripts/demo.sh limit) is the limit beat alone,
// on the real orbit: that provider's orbs dissolve and he cries; LIMIT_SHOW_S later the real orbit
// is handed back, and its threads come out again as they are.

const END_S = 44;               // the whole show; real snapshots come back here
const LIMIT_SHOW_S = 9;         // limitShow: the made-up limit lasts this long
const ACTIVITY_EVERY_S = 2.3;   // how often a working thread moves on to something new

const GENERIC_ACTIVITY = [
  'reading README.md', 'running the tests', 'thinking…', 'searching the codebase', 'reviewing the diff',
  'checking git status', 'planning the change', 'writing a test', 'editing the layout', 'reading package.json',
  '“Found it: the cache key was stale.”', '“Tests pass. Tidying up.”', 'running the build', 'thinking…',
];
// Activity that only reads right in this repo.
const OWN_ACTIVITY = { widgets: ['reading pet.js', 'running swift build', 'thinking…', 'editing orbit.js', '“The orbs ride the halo now.”'] };
const GROK_FACE = { kind: 'image', src: './badges/grokBot.png' };

let run = null;
let show = null;                // limitShow, while it runs

/// True while the demo plays (his animation sounds play then, mouse or not, for recordings).
export function demoPlaying() { return run !== null; }

/// Starts the demo (payload: { projects, grok }) or, with `false`, stops it.
export function demo(payload) {
  const T = window.t3boii;
  if (payload === false) { stop(); return false; }
  if (!T?.ready || !T.orbit) return false;
  endShow();
  // Restarted mid-show: the real orbit is still the one from before the first start.
  const real = run ? (run.stash !== undefined ? run.stash : run.real) : T.lastSnapshot;
  if (run) stop({ restore: false });
  start(T, payload || {}, real);
  return true;
}

function start(T, payload, real) {
  const I = T.internals;
  const projects = pickProjects(payload, T.lastSnapshot);
  run = {
    T, I,
    t0: performance.now(),
    fired: 0,
    stash: undefined,             // the latest snapshot Swift sent while the demo ran
    saved: { update: T.update, pointer: T.pointer, hover: T.hover, droolAfter: T.debug.droolAfter, calm: T.debug.calm },
    real,                         // the real orbit when it started (the demo's own updates replace lastSnapshot)
    threads: new Map(),           // id -> orb data, in arrival order
    limits: [],                   // providers at a limit in the show
    projects,
    grok: payload.grok || GROK_FACE,
    activityAt: 0,
    raf: 0,
  };
  // Swift keeps sending the real orbit; hold on to the latest for afterwards. The mouse would
  // wake or pet him mid-show, so it is ignored until the end.
  T.update = (snapshot) => { run.stash = snapshot; return null; };
  T.pointer = () => {};
  T.hover = () => {};
  T.debug.calm = true;
  T.debug.droolAfter = 0.3;
  // Clear the stage at once and put him sound asleep.
  T.orbit.reset();
  I.swallows.clear();
  I.sleep.active = -1e6;
  I.sleep.deep = 0;
  push();
  const tick = () => {
    if (!run) return;
    step((performance.now() - run.t0) / 1000);
    if (run) run.raf = requestAnimationFrame(tick);
  };
  run.raf = requestAnimationFrame(tick);
}

function stop({ restore = true } = {}) {
  if (!run) return;
  const { T, saved, stash, real: before } = run;
  cancelAnimationFrame(run.raf);
  T.update = saved.update;
  T.pointer = saved.pointer;
  T.hover = saved.hover;
  T.debug.droolAfter = saved.droolAfter;
  T.debug.calm = saved.calm;
  const ended = run.fired >= BEATS.length;
  run = null;
  if (!restore) return;
  // Cut short: drop the demo's orbs at once rather than swallow a crowd of them.
  if (!ended) T.orbit.reset();
  const real = stash !== undefined ? stash : before;
  T.update(real || { orbs: [] });
}

function step(s) {
  while (run && run.fired < BEATS.length && s >= BEATS[run.fired][0]) {
    const beat = BEATS[run.fired];
    run.fired += 1;
    beat[1]();
  }
  if (!run) return;
  if (s - run.activityAt > ACTIVITY_EVERY_S && run.threads.size) {
    run.activityAt = s;
    moveOn();
  }
  if (s >= END_S) stop();
}

// --------------------------------------------------------------- threads

/// Up to 12 real projects, image faces first so the orbit looks varied, then monograms.
function pickProjects(payload, snapshot) {
  let list = Array.isArray(payload.projects) ? payload.projects.filter((p) => p && p.icon) : [];
  if (!list.length && snapshot?.orbs) {
    const seen = new Set();
    for (const orb of snapshot.orbs) {
      if (orb.source !== 't3' || orb.parentId || !orb.projectIcon) continue;
      const key = JSON.stringify(orb.projectIcon);
      if (seen.has(key)) continue;
      seen.add(key);
      list.push({ title: String(orb.label || '').split(' · ')[0] || 'project', icon: orb.projectIcon });
    }
  }
  if (!list.length) list = [{ title: 'widgets', icon: { kind: 'monogram', text: 'WI', color: '#8b5cf6' } }];
  return list.slice(0, 12);
}

const project = (i) => run.projects[i % run.projects.length];

function activityFor(title, n) {
  const pool = OWN_ACTIVITY[title] || GENERIC_ACTIVITY;
  return pool[n % pool.length];
}

/// A T3 thread in project `p` (an index into the real projects).
function thread(id, p, provider, n = 0) {
  const { title, icon } = project(p);
  return { id: `demo:${id}`, parentId: null, source: 't3', provider, state: 'active', projectIcon: icon, label: `${title} · thread`, activity: activityFor(title, n), n, title };
}

/// A subagent circling thread `parent`.
function sub(id, parent, provider, n = 1) {
  const p = run.threads.get(`demo:${parent}`);
  const title = p?.title || 'project';
  return { id: `demo:${id}`, parentId: `demo:${parent}`, source: 't3', provider, state: 'active', projectIcon: p?.projectIcon, label: `${title} · subagent`, activity: activityFor(title, n + 3), n: n + 3, title };
}

/// Grok Bot's own thread: its app icon, no trail (Grok Bot reports no activity).
function grokThread(id) {
  return { id: `demo:${id}`, parentId: null, source: 'grok', provider: 'grokBot', state: 'active', projectIcon: run.grok, label: 'Grok Bot', n: 0 };
}

function add(...items) { for (const item of items) run.threads.set(item.id, item); push(); }
function drop(...ids) {
  for (const id of ids) {
    const key = `demo:${id}`;
    run.threads.delete(key);
    for (const [k, v] of run.threads) if (v.parentId === key) run.threads.delete(k);
  }
  push();
}
function setState(id, state) { const t = run.threads.get(`demo:${id}`); if (t) t.state = state; push(); }

/// A few working threads move on to their next activity, so the trails read as live work.
function moveOn() {
  const working = [...run.threads.values()].filter((t) => t.state === 'active' && t.activity);
  for (let i = 0; i < Math.min(3, working.length); i += 1) {
    const t = working[(Math.floor(Math.random() * working.length) + i) % working.length];
    t.n += 1;
    t.activity = activityFor(t.title, t.n);
  }
  push();
}

/// Hands the orbit the demo's threads as one snapshot (the real update, bypassing the stash).
function push() {
  const at = Date.now() / 1000;
  const orbs = [...run.threads.values()].map(({ n, title, ...orb }) => ({ ...orb, activeAt: at }));
  run.saved.update.call(run.T, { orbs, limits: run.limits });
}

/// `provider` hits its limit: he cries, and these threads (with their subagents) die of it.
function limit(provider, ...ids) {
  const hit = new Set(ids.map((id) => `demo:${id}`));
  for (const t of run.threads.values()) {
    if (hit.has(t.id) || hit.has(t.parentId)) { t.limited = true; t.limitProvider = provider; t.state = 'failed'; }
  }
  run.limits = [{ provider, since: Math.round(Date.now()) / 1000 }];
  push();
}

/// The limit clears; the threads it killed are long gone.
function unlimit() {
  for (const [id, t] of run.threads) if (t.limited) run.threads.delete(id);
  run.limits = [];
  push();
}

// ------------------------------------------------------------ limitShow

/// A made-up rate limit for `provider` on the real orbit (default: the provider with the most
/// orbs, else Codex): its threads and their subagents dissolve and he cries. Real snapshots are
/// kept aside meanwhile; then the latest is handed back. Not during the demo.
export function limitShow(provider) {
  const T = window.t3boii;
  if (!T?.ready || !T.orbit || run) return null;
  const real = show ? (show.stash !== undefined ? show.stash : show.real) : (T.lastSnapshot || { orbs: [] });
  endShow({ restore: false });
  const orbs = Array.isArray(real?.orbs) ? real.orbs : [];
  if (typeof provider !== 'string' || !provider) {
    const counts = new Map();
    for (const o of orbs) if (!o.parentId) counts.set(o.provider, (counts.get(o.provider) || 0) + 1);
    provider = [...counts].sort((a, b) => b[1] - a[1])[0]?.[0] || 'codex';
  }
  const hit = new Set(orbs.filter((o) => o.provider === provider && !o.parentId).map((o) => o.id));
  const marked = orbs.map((o) => (hit.has(o.id) || hit.has(o.parentId) || (o.parentId && o.provider === provider) ? { ...o, limited: true, limitProvider: provider } : o));
  const limits = [...(Array.isArray(real?.limits) ? real.limits : []), { provider, since: Math.round(Date.now()) / 1000 }];
  show = { T, real, stash: undefined, update: T.update, t0: performance.now(), raf: 0 };
  T.update = (snapshot) => { show.stash = snapshot; return null; };
  show.update.call(T, { orbs: marked, limits });
  const tick = () => {
    if (!show) return;
    if (performance.now() - show.t0 >= LIMIT_SHOW_S * 1000) { endShow(); return; }
    show.raf = requestAnimationFrame(tick);
  };
  show.raf = requestAnimationFrame(tick);
  return provider;
}

/// Ends limitShow, handing back the latest real snapshot unless `restore` is false.
function endShow({ restore = true } = {}) {
  if (!show) return;
  const { T, update, stash, real } = show;
  cancelAnimationFrame(show.raf);
  T.update = update;
  show = null;
  if (restore) T.update(stash !== undefined ? stash : real || { orbs: [] });
}

/// Every main thread and satellite id currently in the show.
const mainIds = () => [...run.threads.values()].filter((t) => !t.parentId).map((t) => t.id.slice(5));

// ------------------------------------------------------------------- beats
//
// [seconds from the start, what happens]. He starts asleep (Zs rise; drool sags from ~0.3 s and
// drips at ~6.3 s).

const BEATS = [
  // Woken with a start, then a big stretch (his own wake path).
  [7.0, () => run.I.wake()],
  // The first threads glow out of the T3 on his forehead, one at a time.
  [9.3, () => add(thread('a', 0, 'claudeAgent'))],
  [10.4, () => add(thread('b', 1, 'codex', 1))],
  [11.4, () => add(grokThread('g'))],
  [12.3, () => add(sub('a1', 'a', 'claudeAgent'), sub('a2', 'a', 'codex', 2))],
  [13.1, () => add(thread('c', 2, 'opencode', 2), thread('d', 3, 'grokBot', 3))],
  // One finishes: sucked in, a gulp, a lopsided grin.
  [14.3, () => drop('b')],
  [15.7, () => add(thread('e', 4, 'codex', 4), thread('f', 5, 'claudeAgent', 5))],
  [16.3, () => add(sub('e1', 'e', 'opencode', 1))],
  // One waits on you: he holds it out, amber, "needs you"; then it is answered.
  [16.9, () => setState('c', 'waiting')],
  [19.2, () => setState('c', 'active')],
  // One fails: he flinches, its orb cracks red, he frowns at it; then it is retried.
  [19.6, () => setState('e', 'failed')],
  [20.6, () => add(thread('h', 6, 'codex', 6), thread('i', 7, 'opencode', 7))],
  [22.1, () => setState('e', 'active')],
  // Build to full power: 20+ threads and subagents, eyes white, light from his mouth.
  [22.6, () => add(thread('j', 8, 'claudeAgent', 8), sub('j1', 'j', 'claudeAgent'), sub('j2', 'j', 'grokBot', 2), thread('k', 9, 'codex', 9))],
  [23.3, () => add(thread('l', 10, 'grokBot', 10), sub('l1', 'l', 'codex'), thread('m', 11, 'claudeAgent', 11))],
  [24.0, () => add(thread('n', 1, 'opencode', 12), sub('n1', 'n', 'claudeAgent'), sub('n2', 'n', 'codex', 3))],
  [24.6, () => add(sub('h1', 'h', 'claudeAgent'), thread('o', 3, 'codex', 13))],
  [25.3, () => drop('i')],
  [26.0, () => add(thread('p', 5, 'claudeAgent', 2), sub('d1', 'd', 'opencode'))],
  // Codex hits its usage limit: he bursts into tears, and three of its threads (one with its
  // subagent) and another's Codex subagent die, darkening under the Codex logo and crumbling away;
  // under 20 again, the light in his mouth goes out. Then it clears.
  [27.2, () => limit('codex', 'k', 'o', 'h', 'n2')],
  [31.4, () => unlimit()],
  // Swallowed back in waves until the last is gone, then his all-done dance (~39 s to ~43 s).
  [31.6, () => drop('a', 'g', 'm')],
  [33.4, () => drop('d', 'f', 'j', 'l', 'p')],
  [35.2, () => drop(...mainIds())],
];
