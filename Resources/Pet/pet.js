// T3boii: a rigged T3 doll that floats on the desktop with no box around him.
//
// The page fills a transparent, full-screen layer. Only the #stage element holds a
// WebGL canvas; dragging him moves #stage with a CSS transform, so a move never
// re-renders the scene. Swift owns the layer window and makes it click-through
// everywhere except the hit regions this page reports.
//
// He shows what the agents are doing without a word of UI:
//   - idle, he stares blankly into the middle distance; left alone long enough, he nods off
//     and Zs float up until something wakes him; sound asleep a while, he drools;
//   - a new agent glows out of the T3 on his forehead and floats out to orbit him;
//   - a finished agent is sucked in through pursed lips on a rush of wind and he gulps, then
//     grins a lopsided grin; when the last one is gone, he does a little dance;
//   - the more agents orbit, the more he powers up: eyes and mouth glow white, he floats
//     higher and swells;
//   - his eyes follow the mouse while it moves, and otherwise his orbiting agents;
//   - pet him (stroke or click) and he leans in, squints and blushes; keep stroking and hearts
//     pop out; grab him and shake, and his limbs flop about; shake hard and he spins right round;
//   - a thread waiting on you: its orb floats beside his head as the dot of a lit 3D "?" ("!" for
//     an approval); he glances at each new one, and fretful, back at the oldest now and then;
//   - a thread that fails: he flinches and frowns at its cracked red orb until you look at it;
//   - a provider hits its rate or usage limit: he cries (tears run down his cheeks, he sobs and
//     slumps) and the threads it refused die, each orb dissolving under the provider's big logo;
//     he stays glum a while, and it is all over within about a minute (SAD_S), limit or no;
//   - what each thread is doing trails behind its orb as faint glowing text (orbit.js); he looks
//     at the orb you hover, and now and then at one on his own; the busier he is, the more his
//     eyes dart and the lower he floats.
//
// Bridge (Swift -> page), all on window.t3boii:
//   feed({events, state})   the t3boii-feed sidecar, relayed by Swift (feed.js): state.orbs is the
//                           orbit; an orb leaves by swallow only after a `finished` event, else it fades
//   update(snapshot)        { orbs, limits, fade?, source? }: spawn new orb ids, swallow gone ones
//                           (orbit.js); a new entry in `limits` makes him cry, limited orbs dissolve
//   setPaused(bool)         stop or resume rendering (screen sleep, occlusion)
//   setReducedMotion(bool)  macOS Reduce Motion: fades for flights, still rings, damped idle motion
//   setMuted(bool)          silence his sound effects (sounds.js); the Sounds menu toggle
//   setTint('#rrggbb')      the shoggoth's eye tint (bodies/shoggoth.js), live; other pets ignore it
//   setPosition(x, y)       move his stage centre to page CSS px (clamped)
//   demo(payload | false)   play the scripted demo (demo.js) with the owner's real projects; false stops it
//   hover(x, y)             the mouse is at page CSS px over him (Swift forwards it; null clears)
//   pointer(x, y)           the mouse moved to page CSS px anywhere on the layer (for his gaze)
//   foreheadAnchor()        { page: {x, y}, world: {x, y, z} } of the T3 logo
//   hitRegions()            current hit rects in page CSS px
//   setHitRegions(key, r)   let other layers (orbs) add hit rects; null clears
//
// window.__t3boiiConfig, set by Swift before this runs: { position, reducedMotion, muted, pet, tint }.
// `pet` picks the body (bodies/index.js; ?pet= in a browser), and a new pet reloads the page.
//
// Bridge (page -> Swift), one message handler `t3boii`, body.type is one of:
//   "ready"      { ok: true, position: {x, y} } or { ok: false, error }
//   "hitRegions" { rects: [{x, y, width, height}], viewport: {width, height} }
//   "position"   { x, y }   stage centre in page CSS px, after a drag ends
//   "openLink"   { url }    an orb was clicked
//   "error"      { message }

import './still.js';
import * as THREE from 'three';
import { createOrbit, fakeSnapshot, PROVIDER_FLASH } from './orbit.js';
import { createFeed } from './feed.js';
import { createMood } from './mood.js';
import { createEffects } from './effects.js';
import { createSounds } from './sounds.js';
import { demo, demoPlaying, limitShow } from './demo.js';
import { tremble, spring } from './motion.js';
import { bodyFor } from './bodies/index.js';

// Non-verbal sound effects for when you play with him (sounds.js); Swift can mute them.
const sounds = createSounds({ muted: !!window.__t3boiiConfig?.muted || new URLSearchParams(location.search).has('mute') });

// The canvas is larger than the box kept on screen, so swelling, floating and flailing
// limbs, and question marks beside a second ring of orbs, have room; his size on screen is
// the same as in a 760 px stage.
const STAGE = { width: 1200, height: 980 };
const KEEP = { width: 640, height: 760 };     // kept on screen; PetLayerGeometry.stageSize
const FRAME_HEIGHT = 760;                     // he is framed as in a stage this tall (~580 px)
const FPS_IDLE = 30;                          // resting: breathing and blinking only
const FPS_ACTIVE = 60;                        // flights, petting, dragging: smooth and responsive
const BAND_PX = 14;                           // silhouette hit-band height
const HIT_PAD = 6;                            // px around the silhouette
// Which pet this page shows (bodies/index.js): its model, anchors and how it moves. The rest of
// this file is the shared brain every body runs on.
const KIND = bodyFor(window.__t3boiiConfig?.pet ?? new URLSearchParams(location.search).get('pet'));
const BALL = KIND.ball;       // its round middle, in model metres
const SLEEP_AFTER_S = 75;     // idle (no agents, nobody near) this long and he nods off
const DROWSE_S = 9;          // ... over this long
const DANCE_S = 3.8;         // his all-done dance
const DANCE_DELAY_S = 1.2;   // ... starts this long after the last gulp
const DROOL_AFTER_S = 12;    // sound asleep this long and he starts to drool
const ODD_SMILE_S = 2.2;     // the lopsided grin after a gulp
const POINTER_GAZE_S = 1.4;  // his eyes stay on the mouse this long after it stops
const HEART_AFTER_S = 1; // stroke him this long before hearts start
const SPIN_S = 0.95;     // shaken hard enough, he spins right round in this long
const DIZZY_S = 2.4;     // ... and is dizzy for this long after
const CRY_S = 4.6;       // a fit of crying when a provider hits its limit; glum after, while it lasts (up to SAD_S)
const SAD_LINGER = 0.55; // how glum he stays while any limit lasts
// The whole sad spell a limit brings on (tears, sobs, glum slump and pout) is over this long after
// the limit that set him off, even if it still lasts; only a new limit (another provider, or a fresh one
// after it cleared) starts another. The glum lifts over SAD_FADE_S, settled 4 s before the end.
const SAD_S = 60;
const SAD_FADE_S = 8;
const TEAR_EVERY_S = [0.55, 1.1];   // tears while he cries, by turns from each eye
const LINGER_TEAR_S = [5, 8];       // ... and now and then while he stays glum
const CHATTER_S = [24, 42];   // he glances at one of his threads this often, on his own
const ASK_GLANCE_S = [4, 7];   // fretful, he glances at the oldest question this often
const ASK_NOD_S = 0.7;         // his nod toward a new question
// A message comes as a glint from behind him to its orb (see sendGlint).
const GLINT_S = 0.85, GLINT_BEAD = 0.22, GLINT_BULGE = 0.3;   // flight; bead and bulge in orb sizes
const GLINT_MAX = 3, GLINT_GAP_S = 0.6, GLINT_FOLD = 1.25;    // in flight at once; per orb; a folded one grows
const GLINT_COLOR = { user: 0xfff1d0, agent: 0x7fdbff };       // its owner, or anything else

const stage = document.getElementById('stage');
const canvas = document.getElementById('t3boii-canvas');
const orbitLayer = document.getElementById('orbits');
const orbitBack = document.getElementById('orbits-back');
const bridge = window.webkit?.messageHandlers?.t3boii;
const post = (body) => { try { bridge?.postMessage(body); } catch (_) { /* no host */ } };
const fail = (message) => { post({ type: 'error', message: String(message) }); console.error(message); };
window.addEventListener('error', (e) => fail(e.message));
window.addEventListener('unhandledrejection', (e) => fail(e.reason?.message ?? e.reason));

const TAU = Math.PI * 2;
const clamp = THREE.MathUtils.clamp;
const clamp01 = (v) => clamp(v, 0, 1);
const smooth = (a, b, v) => { const t = clamp01((v - a) / (b - a)); return t * t * (3 - 2 * t); };
/// Moves `value` toward `target` at `rate` per second, frame-rate independent.
const approach = (value, target, rate, dt) => value + (target - value) * (1 - Math.exp(-rate * dt));

const viewport = () => ({ width: window.innerWidth, height: window.innerHeight });

function clampPosition(p) {
  const { width, height } = viewport();
  const hw = KEEP.width / 2, hh = KEEP.height / 2;
  return {
    x: Math.round(Math.min(Math.max(p.x, hw), Math.max(hw, width - hw))),
    y: Math.round(Math.min(Math.max(p.y, hh), Math.max(hh, height - hh))),
  };
}

const initial = window.__t3boiiConfig?.position;
let position = clampPosition(initial ?? { x: viewport().width * 0.3, y: viewport().height * 0.72 });

function placeStage() {
  stage.style.width = STAGE.width + 'px';
  stage.style.height = STAGE.height + 'px';
  stage.style.transform = `translate(${position.x - STAGE.width / 2}px, ${position.y - STAGE.height / 2}px)`;
}
placeStage();

const stageLeft = () => position.x - STAGE.width / 2;
const stageTop = () => position.y - STAGE.height / 2;

// --------------------------------------------------------------- renderer

const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true, stencil: true, premultipliedAlpha: true, powerPreference: 'low-power' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(STAGE.width, STAGE.height, false);
renderer.setClearColor(0x000000, 0);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.08;

const scene = new THREE.Scene();
scene.background = null;

// Soft studio light that still reads on a dark desktop: a lilac sky fill, a
// warm key from upper left, a violet rim from behind, and a cool front fill.
scene.add(new THREE.HemisphereLight(0xf3eaff, 0x6e6482, 0.95));
const key = new THREE.DirectionalLight(0xfff5ed, 1.9);
key.position.set(-2.4, 4.4, 3.8);
scene.add(key);
const rim = new THREE.DirectionalLight(0xc391ff, 1.8);
rim.position.set(2.2, 2.8, -2.6);
scene.add(rim);
const rimLeft = new THREE.DirectionalLight(0x9fd0ff, 0.9);
rimLeft.position.set(-2.6, 1.6, -2.2);
scene.add(rimLeft);
const fill = new THREE.DirectionalLight(0xa9d5ff, 0.55);
fill.position.set(3, 1, 3);
scene.add(fill);

const camera = new THREE.PerspectiveCamera(20, STAGE.width / STAGE.height, 0.1, 40);

// `rig` floats, sways and swells; the glTF scene sits inside it untouched.
const rig = new THREE.Group();
scene.add(rig);

// ------------------------------------------------------------------ model

let character = null;
let body = null;              // the loaded body (bodies/*.js)
let silhouette = [];          // hit bands in stage-local CSS px, rest pose
let ready = false;
let orbit = null;             // orbit.js, once the model is in
let effects = null;           // effects.js: hearts, Zs, drool, wind, heaven light
let pendingSnapshot = null;   // a snapshot that arrived before the model
let lastSnapshot = null;      // the latest snapshot from Swift, for the demo to hand back afterwards
let pxPerUnit = 1;            // CSS px per model metre at his depth
let bodyPx = { width: 0, height: 0 };

const v3 = () => new THREE.Vector3();
const q4 = () => new THREE.Quaternion();
const tmpA = v3();

function frameCamera() {
  // Fit his rest-pose height into a 760 px-tall frame with room for the bob and sway, then
  // widen the view to the real stage without changing his size on screen.
  const box = new THREE.Box3().setFromObject(character);
  const size = box.getSize(v3()), center = box.getCenter(v3());
  const fov = THREE.MathUtils.degToRad(camera.fov);
  const fitHeight = size.y * 1.2 * STAGE.height / FRAME_HEIGHT / KIND.frame;
  const distance = fitHeight / (2 * Math.tan(fov / 2)) + size.z / 2;
  camera.position.set(0, center.y + size.y * 0.06, distance);
  camera.lookAt(0, center.y, 0);
  camera.updateProjectionMatrix();
  camera.updateMatrixWorld(true);
  const a = new THREE.Vector3(0, center.y, 0).project(camera), b = new THREE.Vector3(1, center.y, 0).project(camera);
  pxPerUnit = Math.abs(b.x - a.x) / 2 * STAGE.width;
  bodyPx = { width: size.x * pxPerUnit, height: size.y * pxPerUnit };
}

// Project every body vertex once in the rest pose and keep, per horizontal
// band, the leftmost and rightmost pixel. Idle motion stays inside HIT_PAD.
function computeSilhouette() {
  scene.updateMatrixWorld(true);
  const rows = new Map();
  const p = v3();
  const meshes = [];
  character.traverse((o) => { if (o.isMesh && o.visible) meshes.push(o); });
  for (const mesh of meshes) {
    const count = mesh.geometry.attributes.position.count;
    for (let i = 0; i < count; i += 2) {
      mesh.getVertexPosition(i, p);
      p.applyMatrix4(mesh.matrixWorld).project(camera);
      const x = (p.x + 1) / 2 * STAGE.width, y = (1 - p.y) / 2 * STAGE.height;
      const row = Math.floor(y / BAND_PX);
      const r = rows.get(row);
      if (r) { r.min = Math.min(r.min, x); r.max = Math.max(r.max, x); } else rows.set(row, { min: x, max: x });
    }
  }
  silhouette = [...rows.entries()].sort((a, b) => a[0] - b[0]).map(([row, r]) => ({
    x: Math.floor(r.min - HIT_PAD),
    y: row * BAND_PX - HIT_PAD,
    width: Math.ceil(r.max - r.min + HIT_PAD * 2),
    height: BAND_PX + HIT_PAD * 2,
  }));
}

async function start() {
  body = await KIND.load({ renderer, scene, rig, tint: window.__t3boiiConfig?.tint });
  character = body.character;
  frameCamera();
  computeSilhouette();
  effects = createEffects({ THREE, scene, pxPerUnit: () => pxPerUnit, pageToWorld });
  // His own animations are heard only with the mouse on him, or all through the demo (for recordings).
  sounds.listenWhile(() => pet.over || !!talk.hovered || demoPlaying());
  orbit = createOrbit({
    body: bodyPx,
    ball: ballOnPage,
    soles: KIND.soles,
    foreheadAnchor,
    mouthAnchor: () => { const m = anchorPage('mouth'); return m && m.page; },
    setHitRegions: (key, rects) => window.t3boii.setHitRegions(key, rects),
    post,
    events: { spawn: onSpawn, swallow: onSwallow, swallowed: onSwallowed, hover: onOrbHover, failed: onOrbFailed, waiting: onOrbWaiting, dying: onOrbDying, sputter: onOrbSputter, mended: onOrbMended, hatch: onOrbHatch },
    front: orbitLayer,
    back: orbitBack,
  });
  orbit.setReducedMotion(reducedMotion);
  // Messages that came while he loaded are old news: glinting them now would show them late.
  if (pendingSnapshot) { applySnapshot({ ...pendingSnapshot, messages: [] }); pendingSnapshot = null; }
  ready = true;
  reportHitRegions(true);
  post({ type: 'ready', ok: true, position, pet: KIND.kind });
  window.__t3boiiReady = true;
  requestFrame();
}

// ---------------------------------------------------------- reduced motion

// Either macOS Reduce Motion (from Swift, also in the start config) or the page's media query.
const motionQuery = window.matchMedia?.('(prefers-reduced-motion: reduce)');
let reducedFromHost = !!window.__t3boiiConfig?.reducedMotion || new URLSearchParams(location.search).has('reduced');
let reducedMotion = false;
function applyReducedMotion() {
  reducedMotion = reducedFromHost || !!motionQuery?.matches;
  document.documentElement.toggleAttribute('data-reduced-motion', reducedMotion);
  orbit?.setReducedMotion(reducedMotion);
}
motionQuery?.addEventListener?.('change', applyReducedMotion);
applyReducedMotion();

// ------------------------------------------------------------ expressions

const rand = (a, b) => a + Math.random() * (b - a);
const now = () => (performance.now() - clockStart) / 1000;

const blink = { next: rand(2, 4), start: -1, double: false };
const gaze = { x: 0, y: 0, tx: 0, ty: 0, next: 0, follow: null };

/// Psychic pulses (one per spawning agent) and swallows in progress.
const psychic = [];                   // { t0, duration }
// The ripples each spawn sends off the T3: the first strongest, the second as the orb lifts away.
const RIPPLES = [{ delay: 0.05, strength: 1 }, { delay: 0.3, strength: 0.78 }, { delay: 0.56, strength: 0.56 }];
const swallows = new Map();           // orb id -> { t0, duration }
let gulp = -1;                        // when he last gulped
let pat = -1;                         // when he was last patted (clicked)

// Power: the more agents orbit, the brighter, higher and rounder he gets. 0 .. 1.
const power = { value: 0 };
const powerTarget = () => 1 - Math.exp(-(orbit?.activeCount ?? 0) / 8);
// How many threads and subagents are going (each counts the same), eased so the glow doesn't jump.
// His eyes stay normal with a few, light up from EYES_FROM and are white right across at EYES_FULL;
// his mouth stays dark until MOUTH_AT, the most he can hold, then pours out light.
const load = { value: 0 };
const EYES_FROM = 5, EYES_FULL = 15, MOUTH_AT = 20;

// Petting: stroking him with the mouse, or a click, fills `level`; it ebbs when you stop.
const pet = { energy: 0, level: 0, x: 0, y: 0, at: -10, over: false, heartAt: -10, since: -1 };

// Sleep: `level` runs from 0 (awake) to 1 (sound asleep). `active` is the last moment anything
// kept him awake; `startle` when he last woke with a jolt.
const sleep = { level: 0, active: 0, startle: -10, zAt: -10, zBig: false, deep: 0 };
// Drool: a strand that slowly lengthens from the corner of his mouth, drips and starts over.
const drool = { cycle: 0, len: 0 };
// His all-done dance, once the last agent is swallowed: null or { t0 }.
let dance = null;
// The mouse anywhere on the layer, from Swift; his eyes follow it while it moves.
const cursor = { x: 0, y: 0, at: -10 };
// Shaken hard while held, he spins right round, then is dizzy: `meter` fills while he is shaken.
const spin = { meter: 0, t0: -10, dir: 1 };
// The question he is glancing at, and until when: a new one, or (fretful) the oldest.
const askGlance = { id: null, until: 0, next: 0 };
// The newest question: when he began a small nod toward it, its side (1 right, -1 left), read
// once the orbit has given it a place, and his tilt easing toward that side.
const askNod = { t0: -10, id: null, side: 0, tilt: 0 };
const gulpGlance = { id: null, until: 0 };
// Scheduled tasks (flag `seeds`): the halo over his head, from the feed or the debug knob.
const SEED_HALO = { r: 0.55, above: 0.35, size: 0.28, ripen: 300 };   // ball radii; orb sizes; seconds
let seedList = [];
const glints = { flying: new Map(), waiting: new Map(), lastGulp: new Map() };   // orb id -> glint
// A thread just failed: when he flinched, and the orb he frowns at.
const upset = { t0: -10, id: null, glanceAt: -10 };
// A provider hit its limit: when he burst into tears, how glum he is (0 .. 1, eased), the limits
// now (`active`) and every limit he has cried over (`keys`, provider@since), the orb he watches
// die, and when the next tear comes.
const cry = { t0: -100, sad: 0, burst: 0, active: [], keys: new Set(), watch: null, watchUntil: -10, tearAt: Infinity, eye: 0 };
// What he is looking at: the orb under the mouse, and when he next glances at a thread on his own.
const talk = { hovered: null, nextChatter: 0, chatterId: null, chatterUntil: -10 };
// Small things he does on his own: one at a time, { kind, t0, duration } or null.
let act = null;
let nextFidget = 0;
// The time of day: 1 deep in the night, 1 in the morning; refreshed once a minute.
const daylight = { night: 0, morning: 0, at: -100 };

function wake(t) {
  if (sleep.level > 0.5) sleep.startle = t;
  // Woken from a proper sleep: once the jolt passes, a big stretch.
  if (sleep.level > 0.7 && !reducedMotion) act = { kind: 'stretch', t0: t + 0.75, duration: 2.1 };
  if (sleep.level > 0.7 && !reducedMotion) sounds.ambient('grab', { delay: 0.75, gain: 0.7 });   // the stretch
  if (sleep.level > 0.7 && (t - cursor.at < 0.5 || pet.over)) sounds.play('wake');   // woken by the mouse: a sleepy murmur
  sleep.active = t;
  sleep.yawned = false;
}

function onSpawn() {
  wake(now());
  dance = null;
  psychic.push({ t0: now(), duration: reducedMotion ? 0.9 : 1.35 });
  sounds.ambient('spawn');
  if (reducedMotion || !effects || !body.anchor('forehead', v3())) return;
  for (const r of RIPPLES) effects.ripple(r);
}

/// The T3 on his forehead in world units, and the way his forehead faces there.
function foreheadFrame() {
  const at = body?.anchor('forehead', v3());
  if (!at) return null;
  return { at, normal: at.clone().sub(ballWorld(0, 0, 0)).normalize() };
}

function onSwallow(orb, duration) {
  swallows.set(orb.id, { t0: now(), duration: duration + orb.delay });
  sounds.ambient('suck', { delay: orb.delay || 0 });
}

function onSwallowed(orb) {
  swallows.delete(orb.id);
  gulp = now();
  feeling.meal(gulp);
  sounds.ambient('gulp');
  // That was the last of them: a little dance once the grin has had its moment.
  if (orbit && orbit.activeCount === 0 && orbit.pendingSwallows <= 1) { dance = { t0: gulp + DANCE_DELAY_S }; sounds.ambient('dance', { delay: DANCE_DELAY_S }); }
}

/// The mouse came onto an orb (or left one): he looks at it.
function onOrbHover(orb) {
  const t = now();
  talk.hovered = orb ? orb.id : null;
  if (orb) { wake(t); sounds.play('orb'); }
  requestFrame();
}

/// A thread failed: he flinches, then frowns at its orb.
function onOrbFailed(orb) {
  const t = now();
  wake(t);
  upset.t0 = t; upset.id = orb.id; upset.glanceAt = t;
  sounds.ambient('fail');
  requestFrame();
}

/// A message reached a thread: a glint comes round from behind him to its orb, which gulps it.
/// At most GLINT_MAX fly at once and an orb gulps at most once per GLINT_GAP_S; one more for an orb
/// already sent one rides along with it, which grows a little and leaves two rings.
function sendGlint({ id, from, fromQueue }) {
  const prior = glints.flying.get(id) ?? glints.waiting.get(id);
  if (prior) { prior.folded = true; prior.fromQueue ||= fromQueue; return; }
  glints.waiting.set(id, { id, color: GLINT_COLOR[from] ?? GLINT_COLOR.agent, fromQueue, folded: false });
  requestFrame();
}

/// Launches waiting glints whose orb is settled in place and free to gulp.
function stepGlints(t) {
  for (const [id, at] of glints.lastGulp) if (t - at >= GLINT_GAP_S) glints.lastGulp.delete(id);
  for (const [id, g] of glints.waiting) {
    const orb = orbit?.orbById(id);
    if (!orb) { glints.waiting.delete(id); continue; }
    if (orb.phase !== 'live' || glints.flying.size >= GLINT_MAX || t - (glints.lastGulp.get(id) ?? -1e9) < GLINT_GAP_S) continue;
    glints.waiting.delete(id);
    if (reducedMotion || !effects) { landGlint(g, orb, t); continue; }
    glints.flying.set(id, g);
    launchGlint(g, orb);
  }
}

function launchGlint(g, orb) {
  const ball = ballOnPage();
  const toward = Math.atan2(-(orb.page.y - ball.y), orb.page.x - ball.x) + rand(-25, 25) * Math.PI / 180;
  const [cx, cy] = [Math.cos(toward), Math.sin(toward)];
  const radius = ballWorld(1, 0, 0).distanceTo(ballWorld(0, 0, 0));
  const orbWorld = (o) => pageToWorld(o.page.x, o.page.y, o.layer === orbitBack ? -0.62 : 0.78);
  const px = () => orbit.geometry.orb * orb.scale / pxPerUnit;
  const at = (u) => {
    const live = orbit.orbById(g.id);
    if (!live) return null;
    const e = u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
    // From a disc behind his middle, out past his edge while still behind him...
    const start = ballWorld(0.6 * cx, 0.6 * cy, -0.4), edge = ballWorld(1.08 * cx, 1.08 * cy, -0.25);
    if (e < 0.35) return start.lerp(edge, e / 0.35);
    // ...then round to wherever its orb is now, bulging away from him.
    const end = orbWorld(live);
    if (!end) return null;
    const mid = edge.clone().lerp(end, 0.5), centre = ballWorld(0, 0, 0);
    const out = v3().set(mid.x - centre.x, mid.y - centre.y, 0).normalize();
    const bend = mid.addScaledVector(out, GLINT_BULGE * px() + radius * 0.15);
    const v = (e - 0.35) / 0.65;
    return edge.multiplyScalar((1 - v) ** 2).addScaledVector(bend, 2 * v * (1 - v)).addScaledVector(end, v * v);
  };
  effects.glint({ at, color: g.color, size: GLINT_BEAD * px() * (g.folded ? GLINT_FOLD : 1), duration: GLINT_S, done: (arrived) => (arrived ? landGlint(g, orbit.orbById(g.id), now()) : releaseGlint(g)) });
}

/// A glint's flight is over, landed or not, and its slot is free. Only its own record frees it, so
/// an old flight can't free a newer one to the same orb.
function releaseGlint(g) {
  if (glints.flying.get(g.id) === g) glints.flying.delete(g.id);
}

/// A glint lands: its orb gulps, a ring spreads (two for a folded one), and his eyes flick to it.
function landGlint(g, orb, t) {
  releaseGlint(g);
  if (!orb) return;
  glints.lastGulp.set(g.id, t);
  const ball = ballOnPage();
  const css = `#${g.color.toString(16).padStart(6, '0')}`;
  orbit.gulp(g.id, { angle: Math.atan2(orb.page.y - ball.y, orb.page.x - ball.x), color: css, fromQueue: g.fromQueue });
  if (reducedMotion || !effects) return;
  const at = pageToWorld(orb.page.x, orb.page.y, orb.layer === orbitBack ? -0.62 : 0.78);
  const radius = orbit.geometry.orb * orb.scale * 0.5 / pxPerUnit;
  if (at) for (let i = 0; i < (g.folded ? 2 : 1); i += 1) effects.ring(at, { color: g.color, radius, delay: 0.12 * i });
  gulpGlance.id = g.id; gulpGlance.until = t + 0.15;
  requestFrame();
}

/// A snoozed thread woke: its egg's shell splits in two and falls away.
function onOrbHatch(orb) {
  if (!effects || reducedMotion) return;
  const at = pageToWorld(orb.page.x, orb.page.y, 0.78);
  if (at) effects.shell(at, orbit.geometry.orb * orb.scale * 1.18 / pxPerUnit);
  requestFrame();
}

/// New seeds from the feed. A seed whose task ran since the last list drops into his T3, or, for a
/// task bound to a thread with an orb out, comes as a glint to that orb.
function setSeedList(list) {
  const before = new Map(seedList.map((s) => [s.id, s]));
  seedList = list.filter((s) => s && typeof s.id === 'string');
  for (const seed of seedList) {
    const was = before.get(seed.id);
    if (!was || seed.lastRun == null || seed.lastRun === was.lastRun) continue;
    if (seed.orbId && orbit?.orbById(seed.orbId)) sendGlint({ id: seed.orbId, from: 'agent' });
    else effects?.dropSeed(seed.id, now());
  }
}

function stepSeeds(t) {
  if (!effects) return;
  const head = ballWorld(0, 1 + SEED_HALO.above, 0), radius = ballWorld(SEED_HALO.r, 0, 0).distanceTo(ballWorld(0, 0, 0));
  const wall = Date.now() / 1000;
  effects.setSeeds(seedList.map((s) => ({
    id: s.id,
    color: new THREE.Color(PROVIDER_FLASH[s.provider] || '#8e8e93').getHex(),
    ripe: s.next == null ? 0 : smooth(0, 1, 1 - (s.next - wall) / SEED_HALO.ripen),
    failed: !!s.failed,
  })), { centre: head, radius, size: SEED_HALO.size * (orbit?.geometry.orb ?? 36) / pxPerUnit, t, reduced: reducedMotion, forehead: foreheadFrame() });
}

/// A failed orb sputters: a few ember chips spit off it.
function onOrbSputter(orb) {
  if (!effects || reducedMotion) return;
  const r = orbit.geometry.orb * orb.scale / 2;
  const at = pageToWorld(orb.page.x, orb.page.y, 0.78);
  if (at) effects.crumble(at, r / pxPerUnit, { duration: 0.25, count: 3 + Math.floor(Math.random() * 4), size: 0.6 });
  requestFrame();
}

/// A failed thread runs again: a beam from his T3 to its orb, which seals and goes home.
function onOrbMended(orb) {
  const t = now();
  wake(t);
  if (upset.id === orb.id) upset.id = null;
  const at = pageToWorld(orb.page.x, orb.page.y, 0.78);
  if (at && effects && !reducedMotion) effects.beam(at, { duration: 0.5 });
  requestFrame();
}

/// A thread started waiting on you: its question mark forms, and he glances over at it.
function onOrbWaiting(orb) {
  const t = now();
  wake(t);
  sounds.ambient('hold');
  askGlance.id = orb.id; askGlance.until = t + 1; askGlance.next = t + rand(...ASK_GLANCE_S);
  if (!reducedMotion) {
    // A nod already under way carries on from where his head is, so a newer question never snaps it.
    const u = clamp01((t - askNod.t0) / ASK_NOD_S);
    askNod.t0 = t - Math.min(u, 1 - u) * ASK_NOD_S; askNod.id = orb.id; askNod.side = 0;
    if (u >= 1) askNod.tilt = 0;
  }
  requestFrame();
}

/// Limits from a snapshot: a new one (a provider and when it began) makes him cry; he stays glum
/// while any lasts, for SAD_S at most. One he has already cried over never makes him cry again.
function onLimits(list) {
  cry.active = Array.isArray(list) ? list.filter((l) => l && typeof l.provider === 'string') : [];
  const fresh = cry.active.filter((l) => !cry.keys.has(`${l.provider}@${l.since}`));
  if (!fresh.length) return;
  for (const l of fresh) cry.keys.add(`${l.provider}@${l.since}`);
  if (cry.keys.size > 200) cry.keys = new Set([...cry.keys].slice(-100));
  const t = now();
  // Asleep, he wakes with a start into tears (no stretch).
  if (sleep.level > 0.5) sleep.startle = t;
  sleep.active = t; sleep.yawned = false;
  act = null; dance = null;
  cry.t0 = t;
  cry.tearAt = t + 0.35;
  sounds.ambient('sob', { delay: 0.15 });
  requestFrame();
}

/// An orb whose provider refused it is dying: he watches it go, and it crumbles into dark chips.
function onOrbDying(orb, d) {
  const t = now();
  cry.watch = orb.id; cry.watchUntil = t + d.duration * 0.8;
  sleep.active = t;
  requestFrame();
  if (d.still || !effects) return;
  // Chips fly in his scene on a plane in front of him, or behind him for an orb on the far side.
  const at = pageToWorld(d.x, d.y, d.back ? -0.62 : 0.78);
  if (at) effects.crumble(at, d.r / pxPerUnit, { delay: d.duration * 0.36, duration: d.duration * 0.56, count: 26 + Math.round(d.r / 3), size: clamp(d.r / 40, 0.6, 1.4) });
}

/// Tears while he cries (and now and then while he stays glum): one eye, then the other.
function stepTears(t) {
  if (!effects || !body.tears) return;
  const crying = t - cry.t0 < CRY_S - 0.8;
  // No new tears once his glum starts to lift, so the last has dried well before SAD_S.
  if (!crying && (cry.sad < 0.3 || t - cry.t0 > SAD_S - 4 - SAD_FADE_S)) { cry.tearAt = Infinity; return; }
  if (cry.tearAt === Infinity) cry.tearAt = t + rand(...LINGER_TEAR_S);
  if (t < cry.tearAt) return;
  cry.tearAt = t + (crying ? rand(...TEAR_EVERY_S) : rand(...LINGER_TEAR_S));
  const tear = body.tear(cry.eye++, rig);
  if (!tear) return;
  effects.tear(tear.points, tear.carry, { size: crying ? rand(0.9, 1.2) : 0.85, still: reducedMotion, tint: tear.tint });
}

/// Where his attention wanders on its own: back, frowning, to a failed orb you have not looked
/// at yet, and every so often over to one of his working threads.
function stepTalk(t) {
  if (!orbit) return;
  if (talk.hovered && !orbit.orbById(talk.hovered)) talk.hovered = null;
  const unseen = orbit.unseenFailures;
  // Fretful, he checks on it more often.
  if (unseen.length && t - upset.glanceAt > (feeling.fretful > 0.5 ? 5.5 : 9) && t - upset.t0 > 4) {
    upset.glanceAt = t; upset.id = unseen[Math.floor(Math.random() * unseen.length)].id;
  }
  // Fretful about a question, he glances back at the oldest one now and then.
  const oldest = orbit.oldestAskOrb;
  if (oldest && feeling.fretful > 0.5 && t >= askGlance.next) { askGlance.id = oldest.id; askGlance.until = t + 1; askGlance.next = t + rand(...ASK_GLANCE_S); }
  if (!talk.nextChatter) talk.nextChatter = t + rand(8, 16);
  if (t >= talk.nextChatter) {
    talk.nextChatter = t + rand(...CHATTER_S);
    const pick = sleep.level < 0.1 && !drag && !reducedMotion ? orbit.pickChatty() : null;
    if (pick) { talk.chatterId = pick.id; talk.chatterUntil = t + 3; }
  }
}


// ---------------------------------------------------------------- floaters
//
// Hearts while he is petted, Zs while he sleeps, drool after a long sleep: 3D objects in his
// scene (effects.js), lit like he is.

/// Hearts once he has been stroked for a moment (more, the happier he is); Zs while he sleeps.
function emitFloaters(t) {
  if (reducedMotion || !effects) return;
  const stroking = pet.over && t - pet.at < 0.3 && !drag;
  if (!stroking) pet.since = -1; else if (pet.since < 0) pet.since = t;
  if (stroking && t - pet.since > HEART_AFTER_S && pet.level > 0.15 && t - pet.heartAt > 0.62 - 0.4 * pet.level) {
    pet.heartAt = t;
    effects.heart({ x: pet.x + rand(-20, 20), y: pet.y - 20 }, rand(0.75, 1.15));
    sounds.play('pop');
  }
  if (sleep.level > 0.85 && t - sleep.zAt > 1.1) {
    sleep.zAt = t;
    sleep.zBig = !sleep.zBig;   // big and small in turn, as in the cartoons
    effects.z(ballWorld(0.45, 0.72, 0.25), sleep.zBig ? 1.1 : 0.75);
    sounds.ambient('snore');
  }
}

/// A point on his ball, in world units: `x`, `y`, `z` in ball radii from its centre.
function ballWorld(x, y, z) {
  rig.updateMatrixWorld(true);
  return v3().set(BALL.x + x * BALL.r, BALL.y + y * BALL.r, z * BALL.r).applyMatrix4(rig.matrixWorld);
}

/// The drool strand, hung from the corner of his mouth (his left, screen right).
function stepDrool(t, dt) {
  sleep.deep = sleep.level > 0.97 ? sleep.deep + dt : 0;
  const on = !reducedMotion && sleep.deep > (debug.droolAfter ?? DROOL_AFTER_S);
  const corner = on || drool.len > 0.5 ? body.droolCorner(swellNow) : null;
  if (on && corner) {
    if (drool.len < 0.5) drool.cycle = t;
    // It sags slowly, swells with each breath, then lets a drop go and starts short again.
    const age = t - drool.cycle;
    drool.len = 4 + 34 * smooth(0, 5, age) + 2 * Math.sin(t * TAU / 6.4);
    if (age > 6) { effects.drip(corner.clone().add(v3().set(0, -(drool.len + 4) / pxPerUnit, 0))); drool.cycle = t; sounds.ambient('pop', { gain: 0.6 }); }
  } else {
    drool.len = approach(drool.len, 0, 10, dt);   // awake: slurped back in
  }
  effects.setDrool(corner, drool.len, t);
}

/// 0 .. 1: how lit the T3 on his forehead is.
function psychicLevel(t) {
  let level = 0;
  for (let i = psychic.length - 1; i >= 0; i -= 1) {
    const u = (t - psychic[i].t0) / psychic[i].duration;
    if (u >= 1) { psychic.splice(i, 1); continue; }
    level = Math.max(level, smooth(0, 0.16, u) * (1 - smooth(0.45, 1, u)));
  }
  return level;
}

/// 0 .. 1: the T3 flashing as each ripple leaves it, a quick rise and a slower fall.
function psychicFlare(t) {
  let flare = 0;
  if (reducedMotion) return flare;
  for (const { t0 } of psychic) {
    for (const { delay, strength } of RIPPLES) {
      const x = t - t0 - delay;
      flare = Math.max(flare, strength * (x < 0 ? Math.exp(-((x / 0.04) ** 2)) : Math.exp(-x / 0.14)));
    }
  }
  return flare;
}

/// 0 .. 1: how far his mouth is open for incoming orbs.
function swallowOpen(t) {
  let open = 0;
  for (const s of swallows.values()) {
    const left = s.t0 + s.duration - t;
    // Opens over the last ~0.9 s of the pull, stays open until the orb is in.
    open = Math.max(open, 1 - smooth(0.25, 0.95, left));
  }
  return open;
}

function blinkAmount(t, busy = 0) {
  if (t >= blink.next && blink.start < 0) { blink.start = t; }
  if (blink.start < 0) return 0;
  const d = t - blink.start, dur = 0.22;
  if (d > dur) {
    if (blink.double) { blink.double = false; blink.start = t + 0.12; blink.next = t + 0.12; return 0; }
    blink.start = -1;
    // A blank stare blinks slowly and rarely; a busy one a little more.
    blink.next = t + (orbit?.activeCount ? rand(2.6, 5) * (1 - 0.55 * busy) : rand(4, 7.5)) * look.blink;
    blink.double = Math.random() < 0.15;
    window.__t3boiiBlinks = (window.__t3boiiBlinks || 0) + 1;
    return 0;
  }
  if (d < 0) return 0;
  return Math.pow(Math.sin(Math.PI * d / dur), 2);
}

// Gaze units: x > 0 looks to screen right, y > 0 looks up; about 1 at a glance's edge.
const GAZE_PX = 240;   // page px from his forehead that a full glance covers

function lookAt(x, y) {
  const a = foreheadAnchor();
  if (!a) return;
  gaze.tx = clamp((x - a.page.x) / GAZE_PX, -1, 1) * 0.9;
  // Not far down: a lowered eye pushes against his lower lid.
  gaze.ty = clamp((a.page.y - y) / GAZE_PX, -0.3, 0.55);
}

function updateGaze(t, dt, psy, toViewer, mood = {}) {
  const focus = orbit?.attention(t);
  const hovered = talk.hovered && orbit?.orbById(talk.hovered);
  const chatter = t < talk.chatterUntil && talk.chatterId && orbit?.orbById(talk.chatterId);
  const failed = mood.frownAt && upset.id && orbit?.orbById(upset.id);
  const asked = t < askGlance.until && !reducedMotion && askGlance.id && orbit?.orbById(askGlance.id);
  const gulped = t < gulpGlance.until && !reducedMotion && gulpGlance.id && orbit?.orbById(gulpGlance.id);
  const dying = t < cry.watchUntil ? orbit?.dying : null;
  const watching = dying && (dying.id === cry.watch || !orbit.orbById(cry.watch)) ? dying : null;
  if (mood.dizzy > 0.05) {
    // Dizzy: his eyes go round and round.
    gaze.tx = 0.55 * Math.cos(t * 7.5) * mood.dizzy; gaze.ty = 0.12 + 0.35 * Math.sin(t * 7.5) * mood.dizzy;
  } else if (drag) {
    // Held up: eyes dart about.
    if (t >= gaze.next) { gaze.tx = rand(-0.5, 0.5); gaze.ty = rand(-0.3, 0.3); gaze.next = t + rand(0.15, 0.4); }
  } else if (psy > 0.4) {
    // Concentrating: eyes roll up toward the T3.
    gaze.tx = 0; gaze.ty = 0.5;
  } else if (watching) {
    // An orb dying of a limit: he watches it go.
    lookAt(watching.page.x, watching.page.y);
  } else if (mood.crying > 0.3) {
    // Crying: eyes down, wandering a little.
    gaze.tx = 0.12 * Math.sin(t * 0.7); gaze.ty = -0.3;
  } else if (failed) {
    // Frowning at the orb that failed.
    lookAt(failed.page.x, failed.page.y);
  } else if (asked) {
    // A question mark: a glance over at it.
    lookAt(asked.page.x, asked.page.y);
  } else if (gulped) {
    // An orb gulping a message: a flick of the eyes to it.
    lookAt(gulped.page.x, gulped.page.y);
  } else if (toViewer || focus?.kind === 'viewer') {
    // Grinning or dancing: he looks straight out at you.
    gaze.tx = 0; gaze.ty = 0.04;
  } else if (focus?.kind === 'point') {
    lookAt(focus.x, focus.y);
  } else if (hovered) {
    // The orb under your mouse, while he tells you about it.
    lookAt(hovered.page.x, hovered.page.y);
  } else if (pet.over && t - pet.at < 1.5) {
    lookAt(pet.x, pet.y);
  } else if (t - cursor.at < POINTER_GAZE_S) {
    // The mouse is moving: he watches it.
    lookAt(cursor.x, cursor.y);
  } else if (chatter) {
    lookAt(chatter.page.x, chatter.page.y);
  } else if (mood.actKind === 'look') {
    // Looking around: one way, then the other.
    gaze.tx = (mood.actU < 0.5 ? -0.75 : 0.75); gaze.ty = 0.1;
  } else if (orbit?.activeCount) {
    // Otherwise he follows one of his agents round its orbit, now and then picking another;
    // the busier he is, the more often his eyes dart to the next one.
    const live = orbit.state().filter((o) => o.phase === 'live' && o.mode !== 'failed');
    let pick = live.find((o) => o.id === gaze.follow);
    if (!pick || t >= gaze.next) {
      pick = live[Math.floor(Math.random() * live.length)];
      gaze.follow = pick?.id ?? null;
      gaze.next = t + rand(2.5, 5) * (1 - 0.7 * (mood.busy ?? 0));
    }
    if (pick) lookAt(pick.x, pick.y); else { gaze.tx = 0; gaze.ty = 0; }
  } else {
    // Idle: the blank stare. Straight ahead, with the faintest drift.
    gaze.tx = 0.03 * Math.sin(t * 0.21); gaze.ty = -0.02 + 0.02 * Math.sin(t * 0.13 + 1);
  }
  // Glum, his eyes stay low whatever they are on.
  if (mood.sad > 0.05 && !watching) gaze.ty = Math.max(-0.3, gaze.ty - 0.3 * mood.sad);
  if (debug.gaze) { gaze.tx = debug.gaze.x; gaze.ty = debug.gaze.y; }
  const k = 1 - Math.exp(-dt * 14);   // quick saccade, then hold or pursue
  gaze.x += (gaze.tx - gaze.x) * k;
  gaze.y += (gaze.ty - gaze.y) * k;
}

/// Starts a little fidget when he has been left alone a while (a look round, a stretch, a hop),
/// and a big yawn just before he nods off.
function scheduleAct(t, S, L) {
  if (act || reducedMotion || debug.calm) return;
  const alone = !(orbit?.activeCount) && !drag && L < 0.05 && !dance && S < 0.02 && swallows.size === 0 && cry.sad < 0.05;
  if (!alone) { nextFidget = Math.max(nextFidget, t + rand(8, 14)); return; }
  const after = debug.sleepAfter ?? SLEEP_AFTER_S * (1 - 0.5 * daylight.night);
  const idleFor = t - sleep.active;
  if (!sleep.yawned && idleFor > after - 5 && idleFor < after - 0.5) {
    sleep.yawned = true;
    act = { kind: 'yawn', t0: t, duration: 2.6 };
    sounds.ambient('yawn');
    return;
  }
  if (!nextFidget) nextFidget = t + rand(12, 22);
  if (t >= nextFidget && idleFor < after - 8) {
    nextFidget = t + rand(14, 28);
    const kind = ['look', 'stretch', 'hop', 'look'][Math.floor(Math.random() * 4)];
    act = { kind, t0: t, duration: { look: 2.6, stretch: 2.1, hop: 0.7 }[kind] };
    if (kind === 'stretch') sounds.ambient('grab', { gain: 0.7 });
  }
}

/// Night and morning, from the local clock: sleepier, dimmer and slower at night, brighter in the morning.
function stepDaylight(t) {
  if (t - daylight.at < 60 && debug.hour == null) return;
  daylight.at = t;
  const d = new Date();
  const h = debug.hour ?? d.getHours() + d.getMinutes() / 60;
  daylight.night = Math.max(smooth(21.5, 23.5, h), 1 - smooth(5, 7, h));
  daylight.morning = smooth(6, 7.5, h) * (1 - smooth(10, 11.5, h));
  renderer.toneMappingExposure = 1.08 * (1 + 0.07 * daylight.morning - 0.12 * daylight.night);
}

// ------------------------------------------------------------------ sway
//
// Held, his whole body swings under the hand; let go, it rights itself. (His limbs swing in his
// body module.)

const motion = { vx: 0, vy: 0, ax: 0, ay: 0, last: null, tilt: 0, tiltV: 0, shake: 0 };

/// Tracks how fast his stage moves and accelerates (page px/s and px/s²), smoothed.
function trackMotion(dt) {
  const p = { x: position.x, y: position.y };
  if (!motion.last) motion.last = p;
  const vx = (p.x - motion.last.x) / dt, vy = (p.y - motion.last.y) / dt;
  motion.last = p;
  const kv = 1 - Math.exp(-dt / 0.035);
  const nvx = motion.vx + (vx - motion.vx) * kv, nvy = motion.vy + (vy - motion.vy) * kv;
  const ka = 1 - Math.exp(-dt / 0.05);
  motion.ax += ((nvx - motion.vx) / dt - motion.ax) * ka;
  motion.ay += ((nvy - motion.vy) / dt - motion.ay) * ka;
  motion.vx = nvx; motion.vy = nvy;
  motion.shake = approach(motion.shake, clamp01(Math.hypot(motion.ax, motion.ay) / 9000), drag ? 6 : 2, dt);
  // Shaken about enough while held, he spins right round.
  const t = now();
  const spinning = t - spin.t0 < SPIN_S + 0.4;
  spin.meter = drag && motion.shake > 0.4 && !spinning ? spin.meter + dt * (0.6 + motion.shake) : Math.max(0, spin.meter - dt * 0.8);
  if (drag && motion.shake > 0.45 && !spinning) sounds.play('shake', { gain: Math.min(1, motion.shake) });
  if (spin.meter > 1.4 && !reducedMotion) {
    spin.meter = 0; spin.t0 = t; spin.dir = motion.vx >= 0 ? 1 : -1;
    sounds.play('spin'); sounds.play('dizzy', { delay: SPIN_S });
  }
}

function stepTilt(dt) {
  const held = !!drag && !reducedMotion;
  const tiltGoal = held ? clamp(-motion.vx * 0.00035, -0.4, 0.4) : 0;
  const ta = (tiltGoal - motion.tilt) * 30 - motion.tiltV * (held ? 4 : 8);
  motion.tiltV += ta * dt;
  motion.tilt += motion.tiltV * dt;
}

// ------------------------------------------------------------------- pose

let ragdollEnergy = 0;
const debug = { lid: null, sleepAfter: null, pucker: null, smirk: null, frown: null, mouth: null, droolAfter: null, hour: null, calm: null, gaze: null };   // checks can hold a face or a look ({ x, y }), or hurry his sleep
// A made-up rate limit for `provider` (default: the one with the most orbs) on the real orbit: he
// cries and its orbs dissolve; the real orbit comes back after (demo.js, scripts/demo.sh limit).
debug.limit = (provider) => limitShow(provider);
// Sample seeds on the halo for a look at the prototype (flag `seeds`): one ripening, one whose last
// run failed, one that fires every eight seconds. debug.seeds(false) clears them.
debug.seeds = (on = true) => {
  clearInterval(debug.seedTimer);
  if (!on) { setSeedList([]); return; }
  const wall = Date.now() / 1000;
  const sample = (lastRun) => [
    { id: 'demo-seed-1', provider: 'claudeAgent', next: wall + 60, lastRun: 1 },
    { id: 'demo-seed-2', provider: 'codex', next: wall + 3600, lastRun: 1, failed: true },
    { id: 'demo-seed-3', provider: 'kimi', next: wall + 240, lastRun },
  ];
  let runs = 1;
  setSeedList(sample(runs));
  debug.seedTimer = setInterval(() => { runs += 1; setSeedList(sample(runs)); requestFrame(); }, 8000);
  requestFrame();
};
let floatPx = 0, swellNow = 1;
// Phases advance by dt, so a change of pace (power, sleep, sadness) speeds or slows the sway instead of sweeping it.
const sway = { bob: 0, breath: 0 };
// His mood (mood.js), stepped once a frame in pose(); `look` is its blend, offsets from Neutral.
const feeling = createMood();
let look = feeling.step(0, 0, {});
const settle = { x: 0, v: 0 };   // the little bounce as he settles, satisfied, after a meal
let wasSatisfied = 0;

/// Works out this frame's pose from what is going on around him, moves his rig (float, sway, swell)
/// and hands the rest to his body, which turns it into bones, lids, lips and glow (bodies/*.js).
function pose(t, dt) {
  body.restPose();
  const amp = reducedMotion ? 0.25 : 1;

  // Mood: from the work around him (mood.js).
  look = feeling.step(t, dt, { active: orbit?.activeCount ?? 0, fleet: orbit?.fleet ?? 0, unseenFailures: orbit?.unseenFailures.length ?? 0, oldestAsk: orbit?.oldestAsk ?? 0 });
  if (feeling.satisfied > 0.25 && wasSatisfied <= 0.25) settle.x = 0.04;
  wasSatisfied = feeling.satisfied;
  spring(settle, 0, 9, dt, 0.55);

  // Power: count of agents -> glow, lift and swell, eased in and out.
  power.value = approach(power.value, powerTarget(), 0.9, dt);
  load.value = approach(load.value, orbit?.activeCount ?? 0, 1.4, dt);
  const p = power.value;
  const psy = psychicLevel(t);
  const open = swallowOpen(t);
  const sinceGulp = gulp < 0 ? 99 : t - gulp;
  const gulpPulse = sinceGulp < 0.7 ? Math.sin(Math.PI * clamp01(sinceGulp / 0.7)) * (1 - sinceGulp / 0.7) : 0;
  const sincePat = pat < 0 ? 99 : t - pat;
  const patPulse = sincePat < 0.6 ? Math.sin(TAU * sincePat / 0.6 * 1.5) * Math.exp(-sincePat * 6) : 0;

  // Petting ebbs once the hand stops.
  pet.energy = Math.max(0, pet.energy - dt * (t - pet.at < 0.4 ? 0.15 : 0.7));
  pet.level = approach(pet.level, clamp01(pet.energy), 5, dt);
  const L = pet.level;

  // Sleep: anything going on keeps him awake; alone long enough, he drifts off.
  if ((orbit?.activeCount ?? 0) > 0 || drag || L > 0.05 || swallows.size || psychic.length || dance) wake(t);
  stepDaylight(t);
  // Late at night he nods off sooner.
  const after = debug.sleepAfter ?? SLEEP_AFTER_S * (1 - 0.5 * daylight.night);
  const sleepGoal = smooth(after, after + DROWSE_S, t - sleep.active);
  sleep.level = sleepGoal >= sleep.level ? sleepGoal : approach(sleep.level, sleepGoal, 7, dt);
  const S = sleep.level;
  const sinceStartle = t - sleep.startle;
  const startle = sinceStartle < 0.7 ? Math.sin(Math.PI * sinceStartle / 0.7) : 0;

  // The grin: lopsided and a bit too wide, for a while after each gulp.
  const odd = smooth(0.12, 0.4, sinceGulp) * (1 - smooth(ODD_SMILE_S - 0.6, ODD_SMILE_S, sinceGulp));

  // Workload: with many threads going he concentrates, his eyes dart, and he sags a little under them.
  const busy = smooth(2.5, 9, orbit?.activeCount ?? 0);

  // Spun round by a hard shake, then dizzy for a while.
  const sinceSpin = t - spin.t0;
  const spinU = clamp01(sinceSpin / SPIN_S);
  const spinning = sinceSpin < SPIN_S ? Math.sin(Math.PI * spinU) : 0;
  const dizzy = sinceSpin >= SPIN_S && sinceSpin < SPIN_S + DIZZY_S ? 1 - smooth(DIZZY_S * 0.55, DIZZY_S, sinceSpin - SPIN_S) : 0;
  if (sinceSpin >= SPIN_S && !spin.starred) { spin.starred = true; effects?.dizzyStars(t, DIZZY_S); }
  if (sinceSpin < SPIN_S) spin.starred = false;


  // A thread failed: a flinch, then a frown that fades; he frowns again whenever he glances back at it.
  const sinceUpset = t - upset.t0;
  const flinch = sinceUpset < 0.6 ? Math.sin(Math.PI * sinceUpset / 0.6) : 0;
  // A new question: a small nod toward it.
  const sinceAsk = t - askNod.t0;
  if (sinceAsk < ASK_NOD_S && !askNod.side) askNod.side = orbit?.askSide(askNod.id) ?? 0;
  askNod.tilt = approach(askNod.tilt, askNod.side, 8, dt);
  const nod = sinceAsk < ASK_NOD_S ? Math.sin(Math.PI * sinceAsk / ASK_NOD_S) : 0;
  const glance = t - upset.glanceAt < 1.6 ? Math.sin(Math.PI * clamp01((t - upset.glanceAt) / 1.6)) : 0;
  const frown = Math.max(smooth(0.1, 0.45, sinceUpset) * (1 - smooth(3, 4.2, sinceUpset)), 0.6 * glance);

  // A provider hit its limit: a fit of crying (sobs that shake him, eyes screwed up, mouth turned
  // down and trembling), then glum while any limit lasts; it lifts when the last one clears, or
  // anyway by SAD_S after the limit came.
  const sinceCry = t - cry.t0;
  const burst = sinceCry < CRY_S ? smooth(0, 0.4, sinceCry) * (1 - smooth(CRY_S - 1.2, CRY_S, sinceCry)) : 0;
  const glum = cry.active.length ? SAD_LINGER * (1 - smooth(SAD_S - 4 - SAD_FADE_S, SAD_S - 4, sinceCry)) : 0;
  cry.sad = sinceCry < SAD_S ? approach(cry.sad, Math.max(burst, glum), burst > cry.sad ? 5 : 0.9, dt) : 0;
  const sad = cry.sad;
  cry.burst = burst;
  // Each sob: a quick catch of breath, then a shudder.
  const sobPhase = (sinceCry * 1.15) % 1;
  const sob = reducedMotion ? 0 : burst * Math.pow(Math.sin(Math.PI * Math.min(1, sobPhase / 0.4)), 2) * (sobPhase < 0.4 ? 1 : 0);
  const shudder = reducedMotion ? 0 : burst * tremble(t, 28) * Math.exp(-((sobPhase - 0.42) ** 2) / 0.005);

  if (burst > 0) sleep.active = t;   // crying keeps him up (without the stretch a wake brings)

  // Little things he does on his own while nothing else is going on.
  scheduleAct(t, S, L);
  let A = 0, actKind = null, actU = 0;
  if (act && t >= act.t0) {
    actU = (t - act.t0) / act.duration;
    if (actU >= 1) act = null;
    else { actKind = act.kind; A = smooth(0, 0.22, actU) * (1 - smooth(0.72, 1, actU)) * (reducedMotion ? 0.3 : 1); }
  }
  const stretch = actKind === 'stretch' || actKind === 'yawn' ? A : 0;
  const yawn = actKind === 'yawn' ? A : 0;
  const hop = actKind === 'hop' ? Math.sin(Math.PI * actU) * (reducedMotion ? 0.3 : 1) : 0;

  // The dance: hops on the beat, sways, waves his arms, kicks, and spins once in the middle.
  let D = 0, beat = 0, danceSpin = 0;
  if (dance && t >= dance.t0) {
    const d = (t - dance.t0) / DANCE_S;
    if (d >= 1) dance = null;
    else {
      D = smooth(0, 0.1, d) * (1 - smooth(0.86, 1, d)) * (reducedMotion ? 0.3 : 1);
      beat = (t - dance.t0) * TAU * 2.1;
      danceSpin = reducedMotion ? 0 : TAU * smooth(0.38, 0.64, d);
    }
  }

  // Float: a slow bob with a little sway, as if hanging in water. Powered up, he rises and bobs more.
  sway.bob += dt * TAU / (3.8 - 0.8 * p + 2 * S + 0.8 * daylight.night + 1.4 * sad);
  const bob = amp * (0.035 + 0.03 * p) * (1 - 0.6 * S) * (1 - 0.45 * sad) * Math.sin(sway.bob);
  rig.position.y = bob + 0.12 * p - 0.045 * busy - 0.04 * S + 0.06 * startle * amp + 0.08 * D * Math.abs(Math.sin(beat / 2)) + look.float + amp * settle.x
    + 0.1 * hop + 0.03 * flinch + 0.05 * spinning - 0.07 * sad + 0.022 * sob;
  const lean = pet.over && L > 0.02 ? clamp((pet.x - ballOnPage().x) / 220, -1, 1) * -0.08 * L : 0;
  const purr = reducedMotion ? 0 : 0.009 * L * tremble(t, 16);
  rig.rotation.z = amp * 0.025 * Math.sin(t * TAU / 6.1 + 0.6) + lean + purr + motion.tilt + 0.07 * odd + 0.16 * D * Math.sin(beat / 2)
    + 0.12 * dizzy * Math.sin(t * 5.2) * amp + 0.011 * shudder - 0.07 * askNod.tilt * nod;
  const spinTurn = sinceSpin < SPIN_S ? spin.dir * TAU * (spinU < 0.5 ? 4 * spinU ** 3 : 1 - Math.pow(-2 * spinU + 2, 3) / 2) : 0;
  rig.rotation.y = amp * 0.07 * Math.sin(t * TAU / 9.3) * (1 - D) + danceSpin + spinTurn;
  rig.rotation.x = -0.05 * open + 0.04 * gulpPulse - 0.13 * flinch + 0.07 * sad - 0.03 * sob + 0.08 * nod + amp * look.lean;
  // Swell: power rounds him out with an energetic throb; a gulp puffs him, a pat squishes him.
  const throb = reducedMotion ? 0 : 0.012 * p * Math.sin(t * 7.3);
  const swell = 1 + 0.12 * p + throb + 0.035 * gulpPulse + 0.03 * startle + 0.025 * flinch - 0.03 * sad;
  const squash = 0.07 * patPulse - 0.05 * stretch + 0.06 * hop * Math.cos(Math.PI * actU) - 0.035 * sob;
  rig.scale.set(swell * (1 + 0.7 * squash), swell * (1 - squash), swell);
  swellNow = swell;
  floatPx = (rig.position.y - bob) * pxPerUnit;

  // Breathing: chest lifts and the head nods back a touch. Concentrating, he tips his head back.
  // Asleep, he breathes slow and deep and his head droops.
  sway.breath += dt * TAU / ((4.2 - 1.2 * p - 0.8 * busy + 2.2 * S) * look.breath);
  const breath = amp * (1 + 0.9 * S) * look.breathDepth * Math.sin(sway.breath);
  const headDip = 0.010 * breath - 0.06 * psy + 0.05 * gulpPulse + 0.15 * S - 0.16 * stretch - 0.06 * flinch + 0.13 * sad + 0.05 * sob + amp * look.head;
  // Arms (or whatever the body has) drift with the float.
  const drift = amp * (1 - 0.7 * S) * Math.sin(t * TAU / 3.8 + 1.1);
  stepTilt(dt);

  // Eyes glance; the lids blink, squint when happy, droop a touch in the blank stare.
  updateGaze(t, dt, psy, odd > 0.3 || D > 0.1, { busy, dizzy: Math.max(dizzy, spinning), actKind, actU, frownAt: sinceUpset < 3.5 || glance > 0, crying: burst, sad });

  const idle = !orbit?.activeCount && L < 0.05 && !drag;
  const rested = (idle ? 0.13 : 0.03) + 0.1 * daylight.night + 0.05 * busy;
  let lid = Math.max(blinkAmount(t, busy), rested + 0.5 * L + 0.18 * psy + 0.42 * odd + 0.38 * D + 0.25 * dizzy + 0.45 * stretch + 0.3 * yawn
    + 0.12 * frown + 0.66 * Math.min(sad, SAD_LINGER) + 0.2 * Math.max(0, sad - SAD_LINGER) + 0.1 * burst + 0.12 * sob - (drag ? 0.03 : 0) + look.lid);
  // Nodding off: the lids sink, now and then struggle half open, then shut.
  const drowsy = clamp01(S * 1.05 - (S > 0.15 && S < 0.9 ? 0.4 * Math.pow(Math.max(0, Math.sin(t * 0.9)), 10) : 0));
  lid = lerp(lid, drowsy, smooth(0, 0.25, S));
  if (startle > 0) lid *= 1 - startle;   // woken with a jolt: eyes wide
  if (flinch > 0) lid *= 1 - flinch;     // ... or startled by a failure
  if (debug.lid != null) lid = debug.lid;
  // Mouth: blank and closed when idle; a smile while petted or after a gulp; open to swallow;
  // powered up, it hangs open a crack with light inside. Shaken hard, a little "o".
  const smile = Math.max(0, (idle ? 0.04 : 0.14) + 0.62 * L + 0.9 * odd + 0.8 * D + look.smile) * (1 - frown) * (1 - yawn) * (1 - sad);
  // Sucking an orb in, his lips purse into a round O.
  const sucking = open * (sinceGulp < 0.15 ? 0 : 1);
  const mouthOpen = Math.max(0.85 * sucking, 0.14 * p, 0.35 * motion.shake * (drag ? 1 : 0), 0.05 * odd, 0.2 * D, S * (0.05 + 0.03 * breath),
    0.5 * mouthLight() * (1 - burst), 0.95 * yawn, 0.3 * stretch, 0.25 * dizzy, 0.4 * spinning, 0.3 * flinch, 0.1 * burst + 0.22 * sob);
  // Crying, his mouth turns right down and trembles.
  // Fretful, it stays turned down and trembles faintly.
  const fret = look.frown + (reducedMotion ? 0 : 0.025 * feeling.fretful * tremble(t, 14));

  const state = {
    t, dt, amp, reduced: reducedMotion, look, p, psy, open: mouthOpen, sinceGulp, gulpPulse, patPulse, L, S, startle, odd, busy,
    spinning, dizzy, flinch, nod, nodSide: askNod.tilt, frown, burst, sad, sob, shudder, stretch, yawn, hop, actU, D, beat,
    breath, headDip, drift, swell: swellNow, held: !!drag && !reducedMotion, ax: reducedMotion ? 0 : motion.ax, ay: reducedMotion ? 0 : motion.ay,
    gaze, lid, dozy: feeling.dozy, focused: feeling.focused, fretful: feeling.fretful, satisfied: feeling.satisfied, settle: settle.x,
    face: {
      smile,
      open: debug.mouth ?? mouthOpen,
      pucker: debug.pucker ?? Math.max(sucking, 0.35 * yawn, 0.5 * flinch, 0.2 * sad),   // glum: a pout
      smirk: debug.smirk ?? odd,
      frown: debug.frown ?? Math.max(frown, fret, 0.95 * sad + (reducedMotion ? 0 : 0.05 * burst * tremble(t, 14))),
    },
    // Glow levels for the body's shader and sprites.
    glow: { psy, flare: psychicFlare(t), eyes: eyeLight() * (1 - lid * 0.85) * (1 - 0.3 * daylight.night), mouth: mouthLight() * (1 - burst), blush: L },
    eyeLight: eyeLight(), mouthLight: mouthLight(),
  };
  ragdollEnergy = body.pose(state) + Math.abs(motion.tilt) + Math.abs(motion.tiltV) * 0.1;
  return state;
}

function eyeLight() { return smooth(EYES_FROM, EYES_FULL, load.value); }
function mouthLight() { return smooth(MOUTH_AT - 0.6, MOUTH_AT, load.value); }

function lerp(a, b, t) { return a + (b - a) * t;
}

// ---------------------------------------------------------- frame pacing

let paused = document.hidden;
let rafId = 0;
let lastFrame = 0;
let lastPose = 0;
let lastHitPose = 0;
const clockStart = performance.now();

function requestFrame() {
  if (!rafId && !paused && ready) rafId = requestAnimationFrame(tick);
}

/// 60 fps while something is moving that you would see stutter; 30 fps at rest.
function lively(t) {
  return !!drag || pet.level > 0.02 || orbit?.busy || psychic.length > 0 || swallows.size > 0
    || (gulp >= 0 && t - gulp < ODD_SMILE_S) || (pat >= 0 && t - pat < 1) || ragdollEnergy > 0.02
    || effects?.busy || !!dance || (orbit?.wind ?? 0) > 0.01 || t - cursor.at < POINTER_GAZE_S + 0.3
    || t - spin.t0 < SPIN_S + DIZZY_S || spin.meter > 0 || !!act || t < askGlance.until || t - askNod.t0 < ASK_NOD_S || t - upset.t0 < 4.5 || t - upset.glanceAt < 1.8
    || t - sleep.startle < 1 || (sleep.level > 0.01 && sleep.level < 0.99) || t - cry.t0 < CRY_S + 0.5;
}

function tick(nowMs) {
  rafId = 0;
  if (paused) return;
  const t = (nowMs - clockStart) / 1000;
  const fps = lively(t) && !reducedMotion ? FPS_ACTIVE : FPS_IDLE;
  if (nowMs - lastFrame >= 1000 / fps - 2) {
    lastFrame = nowMs;
    const dt = lastPose ? Math.min(0.1, t - lastPose) : 1 / fps;
    lastPose = t;
    trackMotion(dt);
    const state = pose(t, dt);
    rig.updateMatrixWorld(true);
    body.light(state);
    orbit?.frame(t, dt);
    emitFloaters(t);
    stepDrool(t, dt);
    stepTalk(t);
    stepTears(t);
    stepGlints(t);
    if (effects) {
      effects.setVortex(body.anchor('mouth', v3()), rig.getWorldQuaternion(q4()), orbit?.wind ?? 0, t);
      // No heavenly light while he cries.
      effects.setRadiance(body.anchor('mouth', v3()), rig.getWorldQuaternion(q4()), mouthLight() * (1 - (orbit?.wind ?? 0)) * (1 - cry.burst), clamp01(state.open * 2), t, reducedMotion);
      effects.setAsks(orbit?.asks() ?? [], t, reducedMotion);
      effects.setQueueSeeds(orbit?.queueSeeds() ?? []);
      effects.setPrRings(orbit?.prRings() ?? [], t, dt, reducedMotion);
      stepSeeds(t);
      effects.step(t, dt, { head: ballWorld(0, 1.02, 0), forehead: foreheadFrame() });
    }
    renderer.render(scene, camera);
    if (t - lastHitPose > 0.25) { lastHitPose = t; reportHitRegions(); }
    window.__t3boiiFrames = (window.__t3boiiFrames || 0) + 1;
  }
  requestFrame();
}

function setPaused(value) {
  paused = !!value;
  if (paused) { if (rafId) cancelAnimationFrame(rafId); rafId = 0; lastPose = 0; motion.last = null; }
  else requestFrame();
}
let externalPause = false;   // set by Swift: screen asleep, session inactive, occluded
document.addEventListener('visibilitychange', () => setPaused(document.hidden || externalPause));

// ------------------------------------------------------------ hit regions

const extraRegions = new Map();
let lastReported = '';
let reportTimer = 0;

/// His silhouette bands on the page this frame: the rest bands, scaled by his swell about
/// his feet and lifted by his float.
function bands() {
  const ox = stageLeft(), oy = stageTop();
  const foot = projectPage(tmpA.set(0, 0, 0));
  const s = swellNow;
  return silhouette.map((r) => {
    const x = foot.x + (r.x + ox - foot.x) * s, y = foot.y + (r.y + oy - foot.y) * s - floatPx;
    return { x: Math.round(x), y: Math.round(y), width: Math.round(r.width * s), height: Math.round(r.height * s) };
  });
}

function hitRegions() {
  const rects = bands();
  for (const list of extraRegions.values()) rects.push(...list);
  return rects;
}

function reportHitRegions(immediate = false) {
  const send = () => {
    reportTimer = 0;
    const body = { type: 'hitRegions', rects: hitRegions(), viewport: viewport() };
    const json = JSON.stringify(body);
    if (json === lastReported) return;
    lastReported = json;
    post(body);
  };
  if (immediate) { clearTimeout(reportTimer); send(); }
  else if (!reportTimer) reportTimer = setTimeout(send, 50);
}

// Only his own silhouette starts a drag or a pet; orbs handle their own presses.
function pointOnHim(x, y) {
  return bands().some((r) => x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height);
}

// ------------------------------------------------------ petting and drag
//
// Stroke him (move the mouse over him) to pet him. Click him for a pat. Press and drag
// to carry him; shake while carrying and his limbs flop.

function stroke(x, y) {
  const t = now();
  wake(t);
  if (pet.over && t - pet.at < 0.3) {
    const d = Math.hypot(x - pet.x, y - pet.y);
    pet.energy = Math.min(1.3, pet.energy + d / 260);
    if (pet.energy > 0.35) sounds.play('purr');   // rate-limited in sounds.js
  }
  pet.x = x; pet.y = y; pet.at = t; pet.over = true;
  requestFrame();
}

function hover(x, y) {
  if (x == null || y == null || !ready || drag) { pet.over = false; return; }
  if (pointOnHim(x, y)) stroke(x, y); else pet.over = false;
}

let drag = null;
const DRAG_SLOP = 5;   // px a press may wander and still count as a pat
stage.addEventListener('pointerdown', (e) => {
  if (e.button !== 0 || !pointOnHim(e.clientX, e.clientY)) return;
  drag = { id: e.pointerId, dx: e.clientX - position.x, dy: e.clientY - position.y, x0: e.clientX, y0: e.clientY, moved: false };
  try { stage.setPointerCapture(e.pointerId); } catch (_) { /* a synthetic pointer */ }
  e.preventDefault();
  requestFrame();
});
window.addEventListener('pointermove', (e) => {
  if (drag && e.pointerId === drag.id) {
    if (!drag.moved && Math.hypot(e.clientX - drag.x0, e.clientY - drag.y0) < DRAG_SLOP) return;
    if (!drag.moved) { drag.moved = true; stage.classList.add('dragging'); pet.over = false; sounds.play('grab'); }
    const next = clampPosition({ x: e.clientX - drag.dx, y: e.clientY - drag.dy });
    if (next.x === position.x && next.y === position.y) return;
    position = next;
    placeStage();
    reportHitRegions();
    return;
  }
  if (e.buttons === 0) hover(e.clientX, e.clientY);
}, { passive: true });
function endDrag(e) {
  if (!drag || e.pointerId !== drag.id) return;
  const moved = drag.moved;
  drag = null;
  stage.classList.remove('dragging');
  reportHitRegions(true);
  if (moved) { post({ type: 'position', x: position.x, y: position.y }); sounds.play('drop'); }
  else {
    pat = now(); wake(pat); sounds.play('poke');
    pet.energy = Math.min(1.3, pet.energy + 0.55); pet.at = pat; pet.over = true; pet.x = e.clientX; pet.y = e.clientY;
  }
  requestFrame();
}
stage.addEventListener('pointerup', endDrag);
stage.addEventListener('pointercancel', endDrag);
window.addEventListener('pointerleave', () => { pet.over = false; });

window.addEventListener('resize', () => {
  position = clampPosition(position);
  placeStage();
  reportHitRegions(true);
});

// -------------------------------------------------------------- anchors

const projected = v3();
/// Page CSS px of a world point.
function projectPage(world) {
  projected.copy(world).project(camera);
  return { x: stageLeft() + (projected.x + 1) / 2 * STAGE.width, y: stageTop() + (1 - projected.y) / 2 * STAGE.height };
}

/// A page point on the plane `z` world units in front of him (z = 0 is his middle).
function pageToWorld(x, y, z = 0.7) {
  const nx = (x - stageLeft()) / STAGE.width * 2 - 1, ny = 1 - (y - stageTop()) / STAGE.height * 2;
  const dir = v3().set(nx, ny, 0.5).unproject(camera).sub(camera.position).normalize();
  if (Math.abs(dir.z) < 1e-4) return null;
  return camera.position.clone().addScaledVector(dir, (z - camera.position.z) / dir.z);
}

/// A body anchor ('forehead' or 'mouth') in world units and on the page, or null.
function anchorPage(name) {
  if (!ready) return null;
  rig.updateMatrixWorld(true);
  const world = body.anchor(name, v3());
  if (!world) return null;
  return { world: { x: world.x, y: world.y, z: world.z }, page: projectPage(world) };
}

function foreheadAnchor() {
  return anchorPage('forehead');
}

/// His ball body on the page: centre and radius in CSS px, following float, swell and drag.
const ballPoint = v3();
function ballOnPage() {
  rig.updateMatrixWorld(true);
  ballPoint.set(BALL.x, BALL.y, 0).applyMatrix4(rig.matrixWorld);
  const c = projectPage(ballPoint);
  return { x: c.x, y: c.y, r: BALL.r * pxPerUnit * rig.scale.x };
}

// ----------------------------------------------------------------- bridge

/// A feed snapshot onto the scene: staleness, orbs, seeds, message glints and limits. The one that
/// arrives before the model is held and goes through here once the orbit exists.
function applySnapshot(snapshot) {
  const stale = snapshot?.source === 'stale';
  document.documentElement.dataset.feed = stale ? 'stale' : 'live';
  orbit.setStale(stale);
  const result = orbit.update(snapshot);
  if (Array.isArray(snapshot?.seeds)) setSeedList(snapshot.seeds);
  for (const m of Array.isArray(snapshot?.messages) ? snapshot.messages : []) if (typeof m?.id === 'string') sendGlint(m);
  onLimits(snapshot?.limits);
  requestFrame();
  return result;
}

window.t3boii = {
  get ready() { return ready; },
  // Through window.t3boii.update, so the demo's stand-in update holds feed snapshots too.
  feed: createFeed((snapshot) => window.t3boii.update(snapshot)),
  update(snapshot) {
    lastSnapshot = snapshot;
    if (!orbit) { pendingSnapshot = snapshot; return null; }
    return applySnapshot(snapshot);
  },
  get orbit() { return orbit; },
  setPaused(value) { externalPause = !!value; setPaused(externalPause || document.hidden); },
  setReducedMotion(value) { reducedFromHost = !!value; applyReducedMotion(); return reducedMotion; },
  get reducedMotion() { return reducedMotion; },
  setMuted(value) { return sounds.setMuted(value); },
  // The colour of a body's tint, if it has one (the shoggoth's eyes): `#rrggbb`, live.
  setTint(hex) { return body?.setTint?.(hex) ?? null; },
  get muted() { return sounds.muted; },
  sounds,
  get paused() { return paused; },
  setPosition(x, y) {
    position = clampPosition({ x: Number(x), y: Number(y) });
    placeStage();
    reportHitRegions(true);
    return position;
  },
  get position() { return { ...position }; },
  hover,
  pointer(x, y) {
    if (x == null || y == null || !ready) return;
    const t = now();
    cursor.x = Number(x); cursor.y = Number(y); cursor.at = t;
    // Watching the mouse go by doesn't keep him up; it has to come close to stir him.
    const b = ballOnPage();
    if (Math.hypot(cursor.x - b.x, cursor.y - b.y) < b.r * 1.6) wake(t);
    requestFrame();
  },
  foreheadAnchor,
  hitRegions,
  setHitRegions(key, rects) {
    if (rects && rects.length) extraRegions.set(key, rects); else extraRegions.delete(key);
    reportHitRegions();
  },
  stageSize: { ...KEEP },
  // Live state, for checks and debugging.
  get mood() {
    return { power: +power.value.toFixed(3), load: +load.value.toFixed(2), pet: +pet.level.toFixed(3), psychic: psychic.length, swallowing: swallows.size, held: !!drag, ragdoll: +ragdollEnergy.toFixed(3),
      sleep: +sleep.level.toFixed(3), dancing: !!dance, floaters: effects?.count ?? 0, drool: +drool.len.toFixed(1),
      spinning: now() - spin.t0 < SPIN_S, dizzy: now() - spin.t0 < SPIN_S + DIZZY_S, asks: orbit?.waitingCount ?? 0, upset: now() - upset.t0 < 4.2,
      act: act?.kind ?? null, night: +daylight.night.toFixed(2), feeling: feeling.mood, feelings: feeling.weights,
      crying: now() - cry.t0 < CRY_S, sad: +cry.sad.toFixed(2), limits: cry.active.length, tears: effects?.tears ?? 0 };
  },
  debug,
  // A scripted ~43 s show of his animations, for screen recordings (demo.js); demo(false) stops it.
  demo,
  get lastSnapshot() { return lastSnapshot; },
  // The scene graph, for debugging and future layers.
  internals: { THREE, scene, camera, renderer, rig, get character() { return character; }, get body() { return body?.internals ?? null; }, get effects() { return effects; }, stage, orbitLayer, spin, upset, talk, sleep, swallows, cry, wake: () => wake(now()) },
};

const query = new URLSearchParams(location.search);
// ?fake=N fills the orbit with N made-up orbs; add &churn to swap a few every 4 s.
if (query.has('fake')) {
  const n = Math.max(0, parseInt(query.get('fake') || '30', 10) || 0);
  let seed = 0;
  window.t3boii.update(fakeSnapshot(n));
  if (query.has('churn')) {
    setInterval(() => { seed += 3; window.t3boii.update(fakeSnapshot(n, seed)); }, 4000);
  }
}

// ?debug draws the hit bands, the ball and the forehead and mouth anchors on a dark backdrop.
if (query.has('debug')) {
  document.documentElement.style.background = '#16141b';
  const overlay = document.createElement('canvas');
  overlay.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:3';
  document.body.appendChild(overlay);
  const ctx = overlay.getContext('2d');
  const drawDebug = () => {
    overlay.width = innerWidth; overlay.height = innerHeight;
    ctx.strokeStyle = 'rgba(120,220,255,.6)';
    for (const r of hitRegions()) ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.width, r.height);
    if (ready) {
      const b = ballOnPage();
      ctx.strokeStyle = 'rgba(255,220,120,.7)';
      ctx.beginPath(); ctx.arc(b.x, b.y, b.r, 0, TAU); ctx.stroke();
    }
    for (const a of [foreheadAnchor(), anchorPage('mouth')]) {
      if (a) { ctx.fillStyle = '#ff3b6b'; ctx.beginPath(); ctx.arc(a.page.x, a.page.y, 4, 0, TAU); ctx.fill(); }
    }
    setTimeout(drawDebug, 200);
  };
  drawDebug();
}

start().catch((e) => {
  window.__t3boiiFailed = true;
  post({ type: 'ready', ok: false, error: String(e?.message ?? e) });
  console.error(e);
});
