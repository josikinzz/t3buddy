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
//   - a thread waiting on you: he holds its orb out to you, bouncing, glancing from you to it;
//   - a thread that fails: he flinches and frowns at its cracked red orb until you look at it;
//   - what each thread is doing trails behind its orb as faint glowing text (orbit.js); he looks
//     at the orb you hover, and now and then at one on his own; the busier he is, the more his
//     eyes dart and the lower he floats.
//
// Bridge (Swift -> page), all on window.t3boii:
//   update(snapshot)        OrbitSnapshot JSON: spawn new orb ids, swallow gone ones (orbit.js)
//   setPaused(bool)         stop or resume rendering (screen sleep, occlusion)
//   setReducedMotion(bool)  macOS Reduce Motion: fades for flights, still rings, damped idle motion
//   setMuted(bool)          silence his sound effects (sounds.js); the Sounds menu toggle
//   setPosition(x, y)       move his stage centre to page CSS px (clamped)
//   demo(payload | false)   play the scripted demo (demo.js) with the owner's real projects; false stops it
//   hover(x, y)             the mouse is at page CSS px over him (Swift forwards it; null clears)
//   pointer(x, y)           the mouse moved to page CSS px anywhere on the layer (for his gaze)
//   foreheadAnchor()        { page: {x, y}, world: {x, y, z} } of the T3 logo
//   hitRegions()            current hit rects in page CSS px
//   setHitRegions(key, r)   let other layers (orbs) add hit rects; null clears
//
// Bridge (page -> Swift), one message handler `t3boii`, body.type is one of:
//   "ready"      { ok: true, position: {x, y} } or { ok: false, error }
//   "hitRegions" { rects: [{x, y, width, height}], viewport: {width, height} }
//   "position"   { x, y }   stage centre in page CSS px, after a drag ends
//   "openLink"   { url }    an orb was clicked
//   "error"      { message }

import * as THREE from 'three';
import { GLTFLoader } from './vendor/three/examples/jsm/loaders/GLTFLoader.js';
import { createOrbit, fakeSnapshot } from './orbit.js';
import { smoothSkinning, bindLidsToFace } from './skinning.js';
import { createEffects } from './effects.js';
import { createSounds } from './sounds.js';
import { demo, demoPlaying } from './demo.js';

// Non-verbal sound effects for when you play with him (sounds.js); Swift can mute them.
const sounds = createSounds({ muted: !!window.__t3boiiConfig?.muted || new URLSearchParams(location.search).has('mute') });

// The canvas is larger than the box kept on screen, so swelling, floating and flailing
// limbs have room; his size on screen is the same as in a 760 px stage.
const STAGE = { width: 900, height: 980 };
const KEEP = { width: 640, height: 760 };     // kept on screen; PetLayerGeometry.stageSize
const FRAME_HEIGHT = 760;                     // he is framed as in a stage this tall (~580 px)
const FPS_IDLE = 30;                          // resting: breathing and blinking only
const FPS_ACTIVE = 60;                        // flights, petting, dragging: smooth and responsive
const BAND_PX = 14;                           // silhouette hit-band height
const HIT_PAD = 6;                            // px around the silhouette
// Spots on his skin, in model metres (rest pose, seen from the front), measured against a
// render: the middle of the T3 logo, the middle of his mouth, and his cheeks.
const FOREHEAD_RAY = { x: -0.03, y: 1.355 };
const MOUTH_RAY = { x: 0.022, y: 0.797 };
const CHEEK_RAYS = [{ x: 0.36, y: 0.86 }, { x: -0.36, y: 0.86 }];
// His ball body: centre and radius in model metres (the egg is within a few percent of a sphere).
const BALL = { x: 0.015, y: 1.07, r: 0.66 };
const HEAD_BONE = 'Bone_011';   // the bone his face skin follows (the eyes ride it too; see start)
const LID_SHUT = 1;     // share of the blink morph that reads as shut (see installEyeMask)
const SLEEP_AFTER_S = 75;     // idle (no agents, nobody near) this long and he nods off
const DROWSE_S = 9;          // ... over this long
const DANCE_S = 3.8;         // his all-done dance
const DANCE_DELAY_S = 1.2;   // ... starts this long after the last gulp
const DROOL_AFTER_S = 12;    // sound asleep this long and he starts to drool
const ODD_SMILE_S = 2.2;     // the lopsided grin after a gulp
const POINTER_GAZE_S = 1.4;  // his eyes stay on the mouse this long after it stops
const EYE_ROLL = 0.45;   // rad the eyes roll up behind closed lids
const HEART_AFTER_S = 1; // stroke him this long before hearts start
const SPIN_S = 0.95;     // shaken hard enough, he spins right round in this long
const DIZZY_S = 2.4;     // ... and is dizzy for this long after
const HOLD_BOB_S = 0.9;  // the hop while he holds out a waiting orb
const CHATTER_S = [24, 42];   // he glances at one of his threads this often, on his own
// His arms holding a waiting orb out: world-euler deltas for his left shoulder and elbow (the
// right arm mirrors them).
const HOLD_POSE = { shoulder: [-0.75, -1.1, -0.1], elbow: [-0.3, -0.6, 0] };

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

// ---------------------------------------------------------------- placement

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
const bones = {};
const rest = {};
const morphs = {};
let bodyMeshes = [];          // the skinned body (face, eyes, mouth), for the glow shader
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

function loadModel() {
  return new Promise((resolve, reject) => {
    new GLTFLoader().load(new URL('./T3-rigged.glb', import.meta.url).href, resolve, undefined, reject);
  });
}

// Rotate a bone by a world-space euler on top of its rest pose, as the dance
// page does, so small angles read the same whatever the bone's local axes are.
function delta(name, x = 0, y = 0, z = 0) {
  const b = bones[name], r = rest[name];
  if (!b) return;
  const world = q4().setFromEuler(new THREE.Euler(x, y, z, 'XYZ'));
  const local = r.wq.clone().invert().multiply(world).multiply(r.wq);
  b.quaternion.copy(r.q).multiply(local);
}

function setShape(name, value) {
  const c = morphs[name];
  if (c) for (const mesh of c.meshes) mesh.morphTargetInfluences[c.index] = clamp01(value);
}

// The lids are morph meshes with four in-between shapes (25/50/75/100 %).
// They are hidden while open (or barely drooped, which shows nothing but their rim) so they
// never z-fight with the eye.
// A fully shut lid pushes through his cheek, so "shut" stops at LID_SHUT of the morph.
function blinkEye(side, value) {
  value = clamp01(value) * LID_SHUT;
  const lid = morphs['Blink_' + side];
  if (lid) for (const mesh of lid.meshes) mesh.visible = value > 0.05;
  ['_25', '_50', '_75', ''].forEach((suffix, i) => {
    setShape('Blink_' + side + suffix, Math.max(0, 1 - Math.abs(value * 4 - (i + 1))));
  });
}

function frameCamera() {
  // Fit his rest-pose height into a 760 px-tall frame with room for the bob and sway, then
  // widen the view to the real stage without changing his size on screen.
  const box = new THREE.Box3().setFromObject(character);
  const size = box.getSize(v3()), center = box.getCenter(v3());
  const fov = THREE.MathUtils.degToRad(camera.fov);
  const fitHeight = size.y * 1.2 * STAGE.height / FRAME_HEIGHT;
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

// A spot on his skin: cast a ray at his front through (x, y) and remember the skinned vertex
// nearest the hit. Reading that vertex back later gives the exact skinned spot, so an anchor
// rides the breathing, float, swell, drag and morphs.
function findAnchor({ x, y }) {
  scene.updateMatrixWorld(true);
  const ray = new THREE.Raycaster(new THREE.Vector3(x, y, 5), new THREE.Vector3(0, 0, -1));
  const hit = ray.intersectObject(character, true).find((h) => h.object.isSkinnedMesh && !h.object.name.startsWith('Lid'));
  if (!hit) return null;
  const p = v3();
  let best = null;
  for (const index of [hit.face.a, hit.face.b, hit.face.c]) {
    hit.object.getVertexPosition(index, p).applyMatrix4(hit.object.matrixWorld);
    const d = p.distanceToSquared(hit.point);
    if (!best || d < best.d) best = { d, index, offset: hit.point.clone().sub(p) };
  }
  return { mesh: hit.object, index: best.index, offset: best.offset };
}

function anchorWorld(anchor, out) {
  return anchor.mesh.getVertexPosition(anchor.index, out).applyMatrix4(anchor.mesh.matrixWorld).add(anchor.offset);
}

let forehead = null, mouth = null, cheeks = [];
const eyes = [];              // { bone, front: local offset of the eye's front, radius }

async function start() {
  const gltf = await loadModel();
  character = gltf.scene;
  rig.add(character);
  character.updateMatrixWorld(true);
  // The rig hangs his eye sockets off the root bone, so as his head nods and breathes the face skin
  // round each eye slides over the eyeball (the lower lid lifts off it and the eye peeks out below).
  // Hang the sockets off the head bone the skin follows, in the same rest pose.
  const head = character.getObjectByName(HEAD_BONE);
  if (head) for (const name of ['EyeSocket_L', 'EyeSocket_R']) { const socket = character.getObjectByName(name); if (socket) head.attach(socket); }
  character.updateMatrixWorld(true);
  character.traverse((o) => {
    if (o.isBone) {
      bones[o.name] = o;
      rest[o.name] = { p: o.position.clone(), q: o.quaternion.clone(), wq: o.getWorldQuaternion(q4()) };
    }
    if (o.isMesh) {
      o.frustumCulled = false;
      if (o.material?.map) o.material.map.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
      if (o.morphTargetDictionary) {
        for (const [name, index] of Object.entries(o.morphTargetDictionary)) {
          (morphs[name] ||= { index, meshes: [] }).meshes.push(o);
        }
        if (o.morphTargetDictionary.Mouth_Open !== undefined) bodyMeshes.push(o);
      }
    }
  });
  smoothSkinning(character);
  bindLidsToFace(character);
  blinkEye('L', 0); blinkEye('R', 0);
  frameCamera();
  computeSilhouette();
  forehead = findAnchor(FOREHEAD_RAY);
  mouth = findAnchor(MOUTH_RAY);
  cheeks = CHEEK_RAYS.map(findAnchor).filter(Boolean);
  for (const name of ['Eye_L', 'Eye_R']) {
    const bone = bones[name];
    if (!bone) continue;
    const center = bone.getWorldPosition(v3());
    const hit = new THREE.Raycaster(new THREE.Vector3(center.x, center.y, 5), new THREE.Vector3(0, 0, -1))
      .intersectObject(character, true).find((h) => h.object.isSkinnedMesh && !h.object.name.startsWith('Lid'));
    const front = hit ? hit.point : center.clone().add(new THREE.Vector3(0, 0, 0.075));
    eyes.push({ bone, front: bone.worldToLocal(front.clone()), radius: front.distanceTo(center) });
  }
  installGlow();
  installEyeMask();
  setMouthRest();
  installSprites();
  effects = createEffects({ THREE, scene, pxPerUnit: () => pxPerUnit, pageToWorld });
  // His own animations are heard only with the mouse on him, or all through the demo (for recordings).
  sounds.listenWhile(() => pet.over || !!talk.hovered || demoPlaying());
  orbit = createOrbit({
    body: bodyPx,
    ball: ballOnPage,
    foreheadAnchor,
    mouthAnchor: () => { const m = anchorPage(mouth); return m && m.page; },
    setHitRegions: (key, rects) => window.t3boii.setHitRegions(key, rects),
    post,
    events: { spawn: onSpawn, swallow: onSwallow, swallowed: onSwallowed, hover: onOrbHover, failed: onOrbFailed, waiting: onOrbWaiting },
    holdAnchor,
    front: orbitLayer,
    back: orbitBack,
  });
  orbit.setReducedMotion(reducedMotion);
  if (pendingSnapshot) { orbit.update(pendingSnapshot); pendingSnapshot = null; }
  ready = true;
  reportHitRegions(true);
  post({ type: 'ready', ok: true, position });
  window.__t3boiiReady = true;
  requestFrame();
}

// ------------------------------------------------------------------- glow
//
// One small patch to his skin shader lights up parts of him by where they are on his body:
// the dark ink of the T3 logo (psychic), his whole eyeballs and the inside of his mouth
// (power), and a blush on his cheeks (petting). Positions are in the body mesh's own space
// after skinning, so the glow rides every pose.

const glow = {
  uPsy: { value: 0 }, uEyes: { value: 0 }, uMouthGlow: { value: 0 }, uBlush: { value: 0 },
  uForehead: { value: new THREE.Vector3() }, uMouth: { value: new THREE.Vector3() },
  uEyeL: { value: new THREE.Vector3() }, uEyeR: { value: new THREE.Vector3() }, uEyeRadius: { value: 0.07 },
  uCheekL: { value: new THREE.Vector3(9, 9, 9) }, uCheekR: { value: new THREE.Vector3(9, 9, 9) },
  // Lip shapes the rig has no morph for, done in the vertex shader around his mouth in the rest
  // pose: a pucker (lips pursed into a round O) and a smirk (one corner of the mouth hitched up).
  uPucker: { value: 0 }, uSmirk: { value: 0 }, uFrown: { value: 0 }, uMaskDebug: { value: 0 },
  uMouthRest: { value: new THREE.Vector3(9, 9, 9) }, uFaceBasis: { value: new THREE.Matrix3() },
};

function installGlow() {
  const materials = new Set();
  for (const mesh of bodyMeshes) materials.add(mesh.material);
  for (const material of materials) {
    material.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, glow);
      patchVertex(shader);
      shader.fragmentShader = `varying vec3 vT3Pos;
uniform float uPsy, uEyes, uMouthGlow, uBlush, uEyeRadius, uMaskDebug;
uniform vec3 uForehead, uMouth, uEyeL, uEyeR, uCheekL, uCheekR;
uniform mat3 uFaceBasis;
` + shader.fragmentShader.replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
  {
    float lum = dot(diffuseColor.rgb, vec3(0.299, 0.587, 0.114));
    float ink = smoothstep(0.34, 0.08, lum);
    float fm = 1.0 - smoothstep(0.55, 1.0, length((vT3Pos - uForehead) / vec3(0.30, 0.15, 0.4)));
    totalEmissiveRadiance += uPsy * fm * (ink * vec3(0.86, 0.66, 1.0) * 2.6 + vec3(0.62, 0.46, 1.0) * 0.3);
    float eye = max(1.0 - smoothstep(uEyeRadius * 0.82, uEyeRadius * 1.08, distance(vT3Pos, uEyeL)),
                    1.0 - smoothstep(uEyeRadius * 0.82, uEyeRadius * 1.08, distance(vT3Pos, uEyeR)));
    // Lit, the whole eyeball goes white, iris and pupil too, and glows.
    diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0), uEyes * eye);
    totalEmissiveRadiance += uEyes * eye * vec3(1.0, 0.99, 1.04) * 2.2;
    // Only the dark inside of his mouth glows: dark surface set back 5 to 15 cm behind his lip line,
    // where his lips are within 3 cm of it. The darkness test keeps out his pale skin where his face
    // curves away beside and below his mouth.
    vec3 mf = transpose(uFaceBasis) * (vT3Pos - uMouth);
    float inside = smoothstep(0.03, 0.055, -mf.z) * ink * (1.0 - smoothstep(0.7, 1.0, length(mf.xy / vec2(0.24, 0.12))));
    totalEmissiveRadiance += uMouthGlow * inside * vec3(1.0, 0.93, 0.8) * 2.4;
    if (uMaskDebug > 2.5) totalEmissiveRadiance += gl_FrontFacing ? vec3(0.0, 0.0, 4.0) : vec3(4.0, 0.0, 0.0);
    else if (uMaskDebug > 0.5) totalEmissiveRadiance += uMaskDebug < 1.5 ? inside * vec3(3.0, 0.0, 0.0)
      : vec3(step(0.05, -mf.z), step(0.15, -mf.z), step(0.3, -mf.z)) * (1.0 - smoothstep(0.6, 1.0, length(mf.xy / vec2(0.16, 0.08)))) * 2.0;
    float cheek = max(1.0 - smoothstep(0.0, 1.0, length((vT3Pos - uCheekL) / vec3(0.12, 0.07, 0.2))),
                      1.0 - smoothstep(0.0, 1.0, length((vT3Pos - uCheekR) / vec3(0.12, 0.07, 0.2))));
    diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0, 0.52, 0.6), uBlush * cheek * 0.55);
  }`);
    };
    material.needsUpdate = true;
  }
}

/// Lip shapes the rig has no morph for, in the vertex shader around his mouth in the rest pose:
/// a pucker (lips pursed into a round O), a smirk (one corner hitched up) and a frown (both corners
/// down). Also hands the skinned position to the fragment shader. Shared by every material that
/// draws his body, so they all agree to the pixel.
function patchVertex(shader) {
  Object.assign(shader.uniforms, glow);
  shader.vertexShader = `varying vec3 vT3Pos;
uniform float uPucker, uSmirk, uFrown;
uniform vec3 uMouthRest;
uniform mat3 uFaceBasis;
` + shader.vertexShader.replace('#include <morphtarget_vertex>', `#include <morphtarget_vertex>
  {
    // f: offset from the mouth in face axes (x to his left on screen right, y up, z out of the face).
    vec3 f = transpose(uFaceBasis) * (transformed - uMouthRest);
    float m = 1.0 - smoothstep(0.35, 1.0, length(f / vec3(0.26, 0.14, 0.3)));
    vec3 d = vec3(-f.x * 0.68, -f.y * 0.05, 0.07) * uPucker * m;
    d.y += uSmirk * (0.07 * smoothstep(-0.02, 0.14, f.x) - 0.02 * smoothstep(0.02, -0.14, f.x)) * m;
    d.y -= uFrown * (0.055 * smoothstep(0.02, 0.15, abs(f.x)) - 0.012) * m;
    transformed += uFaceBasis * d;
  }`).replace('#include <skinning_vertex>', '#include <skinning_vertex>\n  vT3Pos = transformed;');
}

// How far the eyelids are pulled toward the camera, in metres (his eyes are ~7 cm in radius).
const lidBias = { value: 0.002 };   // metres the lids are pulled toward the camera, against z-fighting
const LID_CLEARANCE = 1.1;         // lids stay this far out from the eye's centre, in eye radii
// The eye is painted on his face surface, which runs straight on into the skin round it, so
// "bare eye" is anything this near the eye's centre (in eye radii) that no lid covers.
const EYE_MASK_REACH = '1.5';
const lidEyes = [];                // { lid, bone, uniforms }: each lid and the eye it closes over

// The eyes and their lids. The blink's in-between shapes blend linearly, so part way through a
// blink the lid would cut through the inside of the eyeball and the eye would show through it (in a
// squint, a drowsy droop, a grin, the dance...). Each lid's vertex shader pushes any vertex inside
// its eyeball back out onto the surface, so the lid always wraps over the eye. A mask pass also
// marks, in the stencil buffer, the pixels where bare eye shows; the lids clear the mark where they
// land, and the eye glow draws only on marked pixels, so it never shines on a lid or skin.
function installEyeMask() {
  const face = bodyMeshes.find((m) => m.material?.map) || bodyMeshes[0];
  if (!face) return;
  const material = new THREE.MeshBasicMaterial({
    colorWrite: false, depthWrite: false, depthFunc: THREE.LessEqualDepth, side: face.material.side,
    stencilWrite: true, stencilRef: 1, stencilFunc: THREE.AlwaysStencilFunc, stencilZPass: THREE.ReplaceStencilOp,
    polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -2,
  });
  material.onBeforeCompile = (shader) => {
    patchVertex(shader);
    shader.fragmentShader = `varying vec3 vT3Pos;
uniform vec3 uEyeL, uEyeR;
uniform float uEyeRadius;
` + shader.fragmentShader.replace('#include <clipping_planes_fragment>', `#include <clipping_planes_fragment>
  if (min(distance(vT3Pos, uEyeL), distance(vT3Pos, uEyeR)) > uEyeRadius * ${EYE_MASK_REACH}) discard;`);
  };
  const mask = new THREE.SkinnedMesh(face.geometry, material);
  mask.name = 'EyeMask';
  mask.bindMode = face.bindMode;
  mask.bind(face.skeleton, face.bindMatrix);
  mask.morphTargetInfluences = face.morphTargetInfluences;
  mask.morphTargetDictionary = face.morphTargetDictionary;
  mask.position.copy(face.position); mask.quaternion.copy(face.quaternion); mask.scale.copy(face.scale);
  mask.frustumCulled = false;
  mask.renderOrder = 1;
  face.parent.add(mask);
  for (const side of ['L', 'R']) {
    for (const lid of morphs['Blink_' + side]?.meshes ?? []) {
      lid.renderOrder = 2;
      const m = lid.material = lid.material.clone();
      // Wherever a lid lands it clears the bare-eye mark, so the eye glow never shows on it.
      Object.assign(m, { stencilWrite: true, stencilRef: 0, stencilFunc: THREE.AlwaysStencilFunc,
        stencilFail: THREE.KeepStencilOp, stencilZFail: THREE.KeepStencilOp, stencilZPass: THREE.ZeroStencilOp });
      const eye = { centre: { value: new THREE.Vector3(9, 9, 9) }, radius: { value: 0 } };
      lidEyes.push({ lid, bone: bones['Eye_' + side], uniforms: eye });
      m.onBeforeCompile = (shader) => {
        // The blink's in-between shapes blend linearly, so part way through a blink the lid cuts
        // through the inside of the eyeball and the eye shows through it. Any lid vertex inside the
        // eyeball is pushed straight out onto its surface, so the lid always wraps over the eye.
        shader.uniforms.uLidEye = eye.centre;
        shader.uniforms.uLidEyeRadius = eye.radius;
        shader.uniforms.uLidBias = lidBias;
        shader.vertexShader = 'uniform vec3 uLidEye;\nuniform float uLidEyeRadius, uLidBias;\n' + shader.vertexShader
          .replace('#include <skinning_vertex>', `#include <skinning_vertex>
  {
    vec3 d = transformed - uLidEye;
    float r = max(length(d), 1e-5);
    if (uLidEyeRadius > 0.0 && r < uLidEyeRadius) transformed = uLidEye + d * (uLidEyeRadius / r);
  }`)
          .replace('#include <project_vertex>', `#include <project_vertex>
  mvPosition.xyz += normalize(-mvPosition.xyz) * uLidBias;
  gl_Position = projectionMatrix * mvPosition;`);
      };
      m.needsUpdate = true;
    }
  }
}

/// The mouth spot and the world axes, in the body mesh's rest space, for the lip shapes.
function setMouthRest() {
  const mesh = bodyMeshes[0];
  if (!mesh || !mouth) return;
  character.updateMatrixWorld(true);
  const toLocal = mesh.matrixWorld.clone().invert();
  glow.uMouthRest.value.copy(anchorWorld(mouth, v3())).applyMatrix4(toLocal);
  const basis = new THREE.Matrix4().extractRotation(toLocal);
  const axes = [v3().set(1, 0, 0), v3().set(0, 1, 0), v3().set(0, 0, 1)].map((a) => a.applyMatrix4(basis).normalize());
  glow.uFaceBasis.value.set(axes[0].x, axes[1].x, axes[2].x, axes[0].y, axes[1].y, axes[2].y, axes[0].z, axes[1].z, axes[2].z);
}

/// Feeds the glow shader this frame's anchor spots, in the body mesh's space.
const tmpA = v3(), tmpB = v3();
function updateGlowAnchors() {
  const mesh = bodyMeshes[0];
  if (!mesh) return;
  const toLocal = mesh.matrixWorld.clone().invert();
  if (forehead) glow.uForehead.value.copy(anchorWorld(forehead, tmpA)).applyMatrix4(toLocal);
  if (mouth) glow.uMouth.value.copy(anchorWorld(mouth, tmpA)).applyMatrix4(toLocal);
  if (cheeks[0]) glow.uCheekL.value.copy(anchorWorld(cheeks[0], tmpA)).applyMatrix4(toLocal);
  if (cheeks[1]) glow.uCheekR.value.copy(anchorWorld(cheeks[1], tmpA)).applyMatrix4(toLocal);
  for (const { lid, bone, uniforms } of lidEyes) {
    const info = eyes.find((e) => e.bone === bone);
    if (!bone || !info) continue;
    uniforms.centre.value.copy(bone.getWorldPosition(tmpA)).applyMatrix4(lid.matrixWorld.clone().invert());
    uniforms.radius.value = info.radius * LID_CLEARANCE;
  }
  eyes.forEach((eye, i) => {
    const center = eye.bone.getWorldPosition(tmpA).applyMatrix4(toLocal);
    (i === 0 ? glow.uEyeL : glow.uEyeR).value.copy(center);
    const front = eye.bone.localToWorld(tmpB.copy(eye.front)).applyMatrix4(toLocal);
    glow.uEyeRadius.value = center.distanceTo(front);
  });
}

// Light sprites on top of the shader glow: lit eyes (each bare eyeball filled white edge to edge,
// never over a lid, and a soft halo spilling around it), a psychic aura on his forehead, and a
// few sparks of energy around his mouth.
const sprites = { eyes: [], eyeHalos: [], forehead: null, sparks: [] };
function glowTexture(stops = [[0, 1], [0.22, 0.75], [0.5, 0.22], [1, 0]]) {
  const size = 128, c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  for (const [at, a] of stops) grad.addColorStop(at, `rgba(255,255,255,${a})`);
  g.fillStyle = grad;
  g.fillRect(0, 0, size, size);
  const texture = new THREE.CanvasTexture(c);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function installSprites() {
  const texture = glowTexture();
  const make = (color) => {
    const s = new THREE.Sprite(new THREE.SpriteMaterial({
      map: texture, color, blending: THREE.AdditiveBlending, transparent: true, depthTest: false, depthWrite: false, toneMapped: false, opacity: 0,
    }));
    s.renderOrder = 10;
    s.visible = false;
    scene.add(s);
    return s;
  };
  // Flat to well past the eye's edge, so the stencil cuts it to exactly the bare eyeball.
  const fill = glowTexture([[0, 1], [0.7, 1], [1, 0]]);
  sprites.eyes = eyes.map(() => {
    const sprite = make(0xffffff);
    Object.assign(sprite.material, { map: fill, blending: THREE.NormalBlending, stencilWrite: true, stencilRef: 1, stencilFunc: THREE.EqualStencilFunc,
      stencilFail: THREE.KeepStencilOp, stencilZFail: THREE.KeepStencilOp, stencilZPass: THREE.KeepStencilOp });
    return sprite;
  });
  sprites.eyeHalos = eyes.map(() => make(0xf4f0ff));
  sprites.forehead = make(0xb894ff);
  sprites.sparks = Array.from({ length: 7 }, () => make(0xffffff));
}

function showSprite(sprite, position, size, opacity) {
  sprite.visible = opacity > 0.003;
  if (!sprite.visible) return;
  sprite.position.copy(position);
  sprite.scale.set(size, size, 1);
  sprite.material.opacity = Math.min(1, opacity);
}

// ---------------------------------------------------------- reduced motion

// Either macOS Reduce Motion (from Swift, also in the start config) or the page's media query.
const motionQuery = window.matchMedia?.('(prefers-reduced-motion: reduce)');
let reducedFromHost = !!window.__t3boiiConfig?.reducedMotion || new URLSearchParams(location.search).has('reduced');
let reducedMotion = false;
function applyReducedMotion() {
  reducedMotion = reducedFromHost || !!motionQuery?.matches;
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
// Holding out a waiting orb: `amount` 0 .. 1, eased.
const hold = { amount: 0 };
// A thread just failed: when he flinched, and the orb he frowns at.
const upset = { t0: -10, id: null, glanceAt: -10 };
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
  if (reducedMotion || !effects || !forehead) return;
  // Rings of psychic energy roll off the T3.
  rig.updateMatrixWorld(true);
  const at = anchorWorld(forehead, v3()).add(v3().set(0, 0, 0.05));
  for (let i = 0; i < 3; i += 1) effects.ring(at, 0.08 + i * 0.16);
}

function onSwallow(orb, duration) {
  swallows.set(orb.id, { t0: now(), duration: duration + orb.delay });
  sounds.ambient('suck', { delay: orb.delay || 0 });
}

function onSwallowed(orb) {
  swallows.delete(orb.id);
  gulp = now();
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

/// A thread is waiting on you: he holds its orb out to you.
function onOrbWaiting() {
  wake(now());
  sounds.ambient('hold');
  requestFrame();
}

/// Where his attention wanders on its own: back, frowning, to a failed orb you have not looked
/// at yet, and every so often over to one of his working threads.
function stepTalk(t) {
  if (!orbit) return;
  if (talk.hovered && !orbit.orbById(talk.hovered)) talk.hovered = null;
  const unseen = orbit.unseenFailures;
  if (unseen.length && t - upset.glanceAt > 9 && t - upset.t0 > 4) {
    upset.glanceAt = t; upset.id = unseen[Math.floor(Math.random() * unseen.length)].id;
  }
  if (!talk.nextChatter) talk.nextChatter = t + rand(8, 16);
  if (t >= talk.nextChatter) {
    talk.nextChatter = t + rand(...CHATTER_S);
    const pick = sleep.level < 0.1 && !drag && !reducedMotion ? orbit.pickChatty() : null;
    if (pick) { talk.chatterId = pick.id; talk.chatterUntil = t + 3; }
  }
}

/// Where he holds a waiting orb out to you: between his hands, a little in front. Page px.
function holdAnchor() {
  if (!ready || hold.amount < 0.02) return null;
  const left = bones.Bone_034, right = bones.Bone_039;
  if (!left || !right) return null;
  rig.updateMatrixWorld(true);
  const mid = left.getWorldPosition(v3()).add(right.getWorldPosition(v3())).multiplyScalar(0.5);
  mid.z += 0.3 * hold.amount;
  mid.y -= 0.22;
  return { ...projectPage(mid), amount: hold.amount };
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
  let corner = null;
  if ((on || drool.len > 0.5) && mouth) {
    corner = anchorWorld(mouth, v3()).add(v3().set(0.1 * swellNow, -0.012, 0.02));
  }
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
    blink.next = t + (orbit?.activeCount ? rand(2.6, 5) * (1 - 0.55 * busy) : rand(4, 7.5));
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
  if (mood.dizzy > 0.05) {
    // Dizzy: his eyes go round and round.
    gaze.tx = 0.55 * Math.cos(t * 7.5) * mood.dizzy; gaze.ty = 0.12 + 0.35 * Math.sin(t * 7.5) * mood.dizzy;
  } else if (drag) {
    // Held up: eyes dart about.
    if (t >= gaze.next) { gaze.tx = rand(-0.5, 0.5); gaze.ty = rand(-0.3, 0.3); gaze.next = t + rand(0.15, 0.4); }
  } else if (psy > 0.4) {
    // Concentrating: eyes roll up toward the T3.
    gaze.tx = 0; gaze.ty = 0.5;
  } else if (failed) {
    // Frowning at the orb that failed.
    lookAt(failed.page.x, failed.page.y);
  } else if (focus?.kind === 'waiting') {
    // Holding out a waiting orb: from you, to it, back to you.
    if (Math.floor(t / 0.95) % 2) lookAt(focus.x, focus.y); else { gaze.tx = 0; gaze.ty = 0.04; }
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
  const k = 1 - Math.exp(-dt * 14);   // quick saccade, then hold or pursue
  gaze.x += (gaze.tx - gaze.x) * k;
  gaze.y += (gaze.ty - gaze.y) * k;
}

/// Starts a little fidget when he has been left alone a while (a look round, a stretch, a hop),
/// and a big yawn just before he nods off.
function scheduleAct(t, S, L) {
  if (act || reducedMotion || debug.calm) return;
  const alone = !(orbit?.activeCount) && !drag && L < 0.05 && !dance && S < 0.02 && swallows.size === 0;
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

// ----------------------------------------------------------------- ragdoll
//
// Each limb is a chain of damped springs pulled back to its pose. While he is held, the
// springs go soft and the drag's acceleration swings them, so a shake makes him flop.

const LIMBS = [
  { side: -1, gain: 1.0, chain: ['Bone_036', 'Bone_035', 'Bone_034'], limit: [1.25, 1.0, 0.7] },   // his right arm (screen left)
  { side: 1, gain: 1.0, chain: ['Bone_041', 'Bone_040', 'Bone_039'], limit: [1.25, 1.0, 0.7] },
  { side: -1, gain: 0.55, chain: ['Bone_006', 'Bone_005', 'Bone_004'], limit: [0.8, 0.9, 0.5] },   // his right leg
  { side: 1, gain: 0.55, chain: ['Bone_010', 'Bone_009', 'Bone_008'], limit: [0.8, 0.9, 0.5] },
].map((limb, i) => ({ ...limb, phase: i * 1.7, joints: limb.chain.map(() => ({ x: 0, z: 0, vx: 0, vz: 0 })) }));
const SHOULDERS = [['Bone_041', 1], ['Bone_036', -1]];
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

function stepRagdoll(t, dt) {
  const held = !!drag && !reducedMotion;
  const k = held ? 16 : 46, c = held ? 2.6 : 7.5;
  // Inertia: limbs lag the hand that moves him; dropping fast lifts them, a sharp stop flings them.
  const ax = reducedMotion ? 0 : motion.ax, ay = reducedMotion ? 0 : motion.ay;
  let energy = 0;
  for (const limb of LIMBS) {
    let parentAlpha = 0;
    limb.joints.forEach((j, i) => {
      const lever = limb.gain * (i === 0 ? 1 : 0.55);
      let dz = (-ax * 0.0007 + limb.side * ay * 0.0006) * lever;
      let dx = (ay * 0.00045 * (limb.side > 0 ? 1 : -0.8) + ax * 0.0003 * Math.sin(limb.phase)) * lever;
      // Held up, his limbs dangle a little loosely.
      if (held) { dz += limb.side * 0.12 * lever; dx += 0.05 * Math.sin(t * 2.3 + limb.phase) * lever; }
      dz -= parentAlpha * 0.02; dx -= parentAlpha * 0.012;
      const az = dz * k - k * j.z - c * j.vz, axx = dx * k - k * j.x - c * j.vx;
      j.vz += az * dt; j.vx += axx * dt;
      j.z = clamp(j.z + j.vz * dt, -limb.limit[i], limb.limit[i]);
      j.x = clamp(j.x + j.vx * dt, -limb.limit[i], limb.limit[i]);
      parentAlpha = az;
      energy += Math.abs(j.z) + Math.abs(j.x) + Math.abs(j.vz) * 0.1 + Math.abs(j.vx) * 0.1;
    });
  }
  // His whole body swings under the hand.
  const tiltGoal = held ? clamp(-motion.vx * 0.00035, -0.4, 0.4) : 0;
  const ta = (tiltGoal - motion.tilt) * 30 - motion.tiltV * (held ? 4 : 8);
  motion.tiltV += ta * dt;
  motion.tilt += motion.tiltV * dt;
  return energy + Math.abs(motion.tilt) + Math.abs(motion.tiltV) * 0.1;
}

// ------------------------------------------------------------------- pose

let ragdollEnergy = 0;
const debug = { lid: null, sleepAfter: null, pucker: null, smirk: null, frown: null, mouth: null, droolAfter: null, hour: null, calm: null };   // checks can hold a face, or hurry his sleep
let floatPx = 0, swellNow = 1;

function pose(t, dt) {
  for (const [name, b] of Object.entries(bones)) { b.position.copy(rest[name].p); b.quaternion.copy(rest[name].q); }
  const amp = reducedMotion ? 0.25 : 1;
  const off = new Map();
  const add = (name, x = 0, y = 0, z = 0) => {
    const o = off.get(name) || [0, 0, 0];
    o[0] += x; o[1] += y; o[2] += z;
    off.set(name, o);
  };

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

  // Holding a waiting orb out to you.
  hold.amount = approach(hold.amount, (orbit?.waitingCount ?? 0) > 0 && !drag && S < 0.5 && !dance ? 1 : 0, 3, dt);
  const H = hold.amount;

  // A thread failed: a flinch, then a frown that fades; he frowns again whenever he glances back at it.
  const sinceUpset = t - upset.t0;
  const flinch = sinceUpset < 0.6 ? Math.sin(Math.PI * sinceUpset / 0.6) : 0;
  const glance = t - upset.glanceAt < 1.6 ? Math.sin(Math.PI * clamp01((t - upset.glanceAt) / 1.6)) : 0;
  const frown = Math.max(smooth(0.1, 0.45, sinceUpset) * (1 - smooth(3, 4.2, sinceUpset)), 0.6 * glance);

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
  const bob = amp * (0.035 + 0.03 * p) * (1 - 0.6 * S) * Math.sin(t * TAU / (3.8 - 0.8 * p + 2 * S + 0.8 * daylight.night));
  const holdHop = amp * 0.045 * H * Math.abs(Math.sin(t * Math.PI / HOLD_BOB_S));
  rig.position.y = bob + 0.12 * p - 0.045 * busy - 0.04 * S + 0.06 * startle * amp + 0.08 * D * Math.abs(Math.sin(beat / 2))
    + holdHop + 0.1 * hop + 0.03 * flinch + 0.05 * spinning;
  const lean = pet.over && L > 0.02 ? clamp((pet.x - ballOnPage().x) / 220, -1, 1) * -0.08 * L : 0;
  const purr = reducedMotion ? 0 : 0.012 * L * Math.sin(t * 22);
  rig.rotation.z = amp * 0.025 * Math.sin(t * TAU / 6.1 + 0.6) + lean + purr + motion.tilt + 0.07 * odd + 0.16 * D * Math.sin(beat / 2)
    + 0.12 * dizzy * Math.sin(t * 5.2) * amp;
  const spinTurn = sinceSpin < SPIN_S ? spin.dir * TAU * (spinU < 0.5 ? 4 * spinU ** 3 : 1 - Math.pow(-2 * spinU + 2, 3) / 2) : 0;
  rig.rotation.y = amp * 0.07 * Math.sin(t * TAU / 9.3) * (1 - D) + danceSpin + spinTurn;
  rig.rotation.x = -0.05 * open + 0.04 * gulpPulse - 0.13 * flinch + 0.06 * H;
  // Swell: power rounds him out with an energetic throb; a gulp puffs him, a pat squishes him.
  const throb = reducedMotion ? 0 : 0.012 * p * Math.sin(t * 7.3);
  const swell = 1 + 0.12 * p + throb + 0.035 * gulpPulse + 0.03 * startle + 0.025 * flinch;
  const squash = 0.07 * patPulse - 0.05 * stretch + 0.06 * hop * Math.cos(Math.PI * actU);
  rig.scale.set(swell * (1 + 0.7 * squash), swell * (1 - squash), swell);
  swellNow = swell;
  floatPx = (rig.position.y - bob) * pxPerUnit;

  // Breathing: chest lifts and the head nods back a touch. Concentrating, he tips his head back.
  // Asleep, he breathes slow and deep and his head droops.
  const breath = amp * (1 + 0.9 * S) * Math.sin(t * TAU / (4.2 - 1.2 * p - 0.8 * busy + 2.2 * S));
  add('Bone_014', -0.012 * breath);
  add('Bone_013', -0.018 * breath);
  add('Bone_012', 0.010 * breath - 0.06 * psy + 0.05 * gulpPulse + 0.15 * S - 0.16 * stretch - 0.06 * flinch, 0.02 * Math.sin(t * 0.37));
  // Arms drift with the float; powered up, they lift away from his sides; asleep, they hang.
  const drift = amp * (1 - 0.7 * S) * Math.sin(t * TAU / 3.8 + 1.1);
  add('Bone_041', 0, 0, 0.05 + 0.035 * drift + 0.22 * p);
  add('Bone_036', 0, 0, -0.05 - 0.035 * drift - 0.22 * p);
  add('Bone_040', 0, 0, 0.08 * p);
  add('Bone_035', 0, 0, -0.08 * p);
  // Holding a waiting orb: both arms come forward and in, cupping it in front of his belly.
  if (H > 0) {
    add('Bone_041', HOLD_POSE.shoulder[0] * H, HOLD_POSE.shoulder[1] * H, HOLD_POSE.shoulder[2] * H);
    add('Bone_036', HOLD_POSE.shoulder[0] * H, -HOLD_POSE.shoulder[1] * H, -HOLD_POSE.shoulder[2] * H);
    add('Bone_040', HOLD_POSE.elbow[0] * H, HOLD_POSE.elbow[1] * H, HOLD_POSE.elbow[2] * H);
    add('Bone_035', HOLD_POSE.elbow[0] * H, -HOLD_POSE.elbow[1] * H, -HOLD_POSE.elbow[2] * H);
  }
  // A stretch (or a yawn): arms up and out, head back.
  if (stretch > 0) {
    add('Bone_041', -0.15 * stretch, 0, 0.75 * stretch);
    add('Bone_036', -0.15 * stretch, 0, -0.75 * stretch);
    add('Bone_040', 0, 0, 0.35 * stretch);
    add('Bone_035', 0, 0, -0.35 * stretch);
  }
  // Spinning, his arms fly out.
  if (spinning > 0) {
    add('Bone_041', 0, 0, 0.65 * spinning);
    add('Bone_036', 0, 0, -0.65 * spinning);
  }
  if (D > 0) {
    add('Bone_041', 0, 0, D * (0.5 + 0.3 * Math.sin(beat)));
    add('Bone_036', 0, 0, -D * (0.5 + 0.3 * Math.sin(beat + Math.PI)));
    add('Bone_040', 0, 0, D * 0.5 * Math.sin(beat * 2));
    add('Bone_035', 0, 0, -D * 0.5 * Math.sin(beat * 2 + 1));
    add('Bone_006', D * 0.32 * Math.max(0, Math.sin(beat / 2)), 0, 0);
    add('Bone_010', D * 0.32 * Math.max(0, -Math.sin(beat / 2)), 0, 0);
  }

  // Ragdoll on top of everything else.
  ragdollEnergy = stepRagdoll(t, dt);
  for (const limb of LIMBS) limb.chain.forEach((name, i) => add(name, limb.joints[i].x, 0, limb.joints[i].z));

  // Eyes glance; the lids blink, squint when happy, droop a touch in the blank stare.
  updateGaze(t, dt, psy, odd > 0.3 || D > 0.1, { busy, dizzy: Math.max(dizzy, spinning), H, actKind, actU, frownAt: sinceUpset < 3.5 || glance > 0 });
  add('Eye_L', -gaze.y * 0.15, gaze.x * 0.2, 0);
  add('Eye_R', -gaze.y * 0.15, gaze.x * 0.2, 0);
  // Shoulders stay within the range his reskinned armpits deform cleanly in (see skinning.js):
  // a raise past ~0.8 rad away from his side starts to crease the ball under the arm.
  for (const [name, side] of SHOULDERS) {
    const o = off.get(name);
    if (!o) continue;
    o[0] = clamp(o[0], -1.05, 0.85);
    o[2] = side > 0 ? clamp(o[2], -0.35, 0.8) : clamp(o[2], -0.8, 0.35);
  }
  for (const [name, o] of off) delta(name, o[0], o[1], o[2]);

  const idle = !orbit?.activeCount && L < 0.05 && !drag;
  const rested = (idle ? 0.13 : 0.03) + 0.1 * daylight.night + 0.05 * busy;
  let lid = Math.max(blinkAmount(t, busy), rested + 0.5 * L + 0.18 * psy + 0.42 * odd + 0.38 * D + 0.25 * dizzy + 0.45 * stretch + 0.3 * yawn
    + 0.12 * frown - (drag ? 0.03 : 0));
  // Nodding off: the lids sink, now and then struggle half open, then shut.
  const drowsy = clamp01(S * 1.05 - (S > 0.15 && S < 0.9 ? 0.4 * Math.pow(Math.max(0, Math.sin(t * 0.9)), 10) : 0));
  lid = lerp(lid, drowsy, smooth(0, 0.25, S));
  if (startle > 0) lid *= 1 - startle;   // woken with a jolt: eyes wide
  if (flinch > 0) lid *= 1 - flinch;     // ... or startled by a failure
  if (debug.lid != null) lid = debug.lid;
  blinkEye('L', lid); blinkEye('R', lid);
  // Closing lids roll the eyes up a little and hold them steadier, as real eyes do, so the
  // cornea never sweeps out under a half-closed lid. (The lids also wrap the eye; see installEyeMask.)
  const tuck = smooth(0.3, 1, lid), steady = 1 - smooth(0.15, 0.6, lid) * 0.75;
  for (const name of ['Eye_L', 'Eye_R']) {
    if (bones[name]) delta(name, (-gaze.y * 0.15 * (1 - tuck) - EYE_ROLL * tuck) * steady, gaze.x * 0.2 * (1 - tuck) * steady, 0);
  }
  // Mouth: blank and closed when idle; a smile while petted or after a gulp; open to swallow;
  // powered up, it hangs open a crack with light inside. Shaken hard, a little "o".
  setShape('Smile', ((idle ? 0.04 : 0.14) + 0.62 * L + 0.9 * odd + 0.8 * D + 0.35 * H) * (1 - frown) * (1 - yawn));
  // Sucking an orb in, his lips purse into a round O.
  const sucking = open * (sinceGulp < 0.15 ? 0 : 1);
  const mouthOpen = Math.max(0.85 * sucking, 0.14 * p, 0.35 * motion.shake * (drag ? 1 : 0), 0.05 * odd, 0.2 * D, S * (0.05 + 0.03 * breath),
    0.5 * mouthLight(), 0.95 * yawn, 0.3 * stretch, 0.25 * dizzy, 0.4 * spinning, 0.3 * flinch);
  setShape('Mouth_Open', debug.mouth ?? mouthOpen);
  glow.uPucker.value = debug.pucker ?? Math.max(sucking, 0.35 * yawn, 0.5 * flinch);
  glow.uSmirk.value = debug.smirk ?? odd;
  glow.uFrown.value = debug.frown ?? frown;

  // Glow levels for the shader and sprites.
  glow.uPsy.value = psy;
  glow.uEyes.value = eyeLight() * (1 - lid * 0.85) * (1 - 0.3 * daylight.night);
  glow.uMouthGlow.value = mouthLight();
  glow.uBlush.value = L;
  return { p, psy, lid, open: mouthOpen };
}

function eyeLight() { return smooth(EYES_FROM, EYES_FULL, load.value); }
function mouthLight() { return smooth(MOUTH_AT - 0.6, MOUTH_AT, load.value); }

function lerp(a, b, t) { return a + (b - a) * t;
}

function updateSprites(t, state) {
  rig.updateMatrixWorld(true);
  updateGlowAnchors();
  const { p, psy, lid } = state;
  const eyeGlow = eyeLight() * (1 - lid * 0.9);
  eyes.forEach((eye, i) => {
    // The bloom only lands on bare eye (stencil), so lids and skin always cover it.
    const pos = eye.bone.localToWorld(tmpB.copy(eye.front));
    const open = 1 - 0.5 * lid;
    // The stencil already keeps the fill off his lids, so it stays solid however far they close.
    showSprite(sprites.eyes[i], pos, eye.radius * 4.8 * swellNow, eyeLight() * (0.94 + 0.06 * Math.sin(t * 9 + i)));
    showSprite(sprites.eyeHalos[i], pos, eye.radius * 6 * swellNow, eyeGlow * open * 0.45);
  });
  const mouthGlow = mouthLight();
  if (mouth) {
    const m = anchorWorld(mouth, tmpA);
    // Energy: sparks that skitter around his mouth, more of them the more powered he is.
    const active = reducedMotion ? 0 : Math.round(mouthGlow * sprites.sparks.length);
    sprites.sparks.forEach((spark, i) => {
      if (i >= active) { spark.visible = false; return; }
      const cycle = 0.55 + 0.15 * (i % 3);
      const u = ((t + i * 0.37) % cycle) / cycle;
      const a = i * 2.4 + Math.floor((t + i * 0.37) / cycle) * 1.7;
      const r = (0.1 + 0.12 * u) * swellNow;
      const pos = tmpB.set(m.x + Math.cos(a) * r, m.y + Math.sin(a) * r * 0.6, m.z + 0.04);
      showSprite(spark, pos, 0.035 * (1 - u) + 0.012, (1 - u) * mouthGlow * 0.9 * clamp01(state.open * 4));
    });
  }
  if (forehead) showSprite(sprites.forehead, anchorWorld(forehead, tmpA), 0.62 * swellNow, psy * 0.85);
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
    || t - spin.t0 < SPIN_S + DIZZY_S || spin.meter > 0 || !!act || hold.amount > 0.01 || t - upset.t0 < 4.5 || t - upset.glanceAt < 1.8
    || t - sleep.startle < 1 || (sleep.level > 0.01 && sleep.level < 0.99);
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
    updateSprites(t, state);
    orbit?.frame(t, dt);
    emitFloaters(t);
    stepDrool(t, dt);
    stepTalk(t);
    if (effects) {
      effects.setVortex(mouth && anchorWorld(mouth, v3()), rig.getWorldQuaternion(q4()), orbit?.wind ?? 0, t);
      effects.setRadiance(mouth && anchorWorld(mouth, v3()), rig.getWorldQuaternion(q4()), mouthLight() * (1 - (orbit?.wind ?? 0)), clamp01(state.open * 2), t, reducedMotion);
      effects.step(t, dt, { head: ballWorld(0, 1.02, 0) });
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

function anchorPage(anchor) {
  if (!ready || !anchor) return null;
  rig.updateMatrixWorld(true);
  const world = anchorWorld(anchor, v3());
  return { world: { x: world.x, y: world.y, z: world.z }, page: projectPage(world) };
}

function foreheadAnchor() {
  return anchorPage(forehead);
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

window.t3boii = {
  get ready() { return ready; },
  update(snapshot) {
    lastSnapshot = snapshot;
    if (!orbit) { pendingSnapshot = snapshot; return null; }
    const result = orbit.update(snapshot);
    requestFrame();
    return result;
  },
  get orbit() { return orbit; },
  setPaused(value) { externalPause = !!value; setPaused(externalPause || document.hidden); },
  setReducedMotion(value) { reducedFromHost = !!value; applyReducedMotion(); return reducedMotion; },
  get reducedMotion() { return reducedMotion; },
  setMuted(value) { return sounds.setMuted(value); },
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
      spinning: now() - spin.t0 < SPIN_S, dizzy: now() - spin.t0 < SPIN_S + DIZZY_S, holding: +hold.amount.toFixed(2), upset: now() - upset.t0 < 4.2,
      act: act?.kind ?? null, night: +daylight.night.toFixed(2) };
  },
  debug,
  // A scripted ~43 s show of his animations, for screen recordings (demo.js); demo(false) stops it.
  demo,
  get lastSnapshot() { return lastSnapshot; },
  // The scene graph, for debugging and future layers.
  internals: { THREE, scene, camera, renderer, rig, bones, morphs, glow, sprites, get character() { return character; }, get effects() { return effects; }, HOLD_POSE, lidBias, stage, orbitLayer, spin, upset, talk, sleep, swallows, wake: () => wake(now()) },
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
    for (const a of [foreheadAnchor(), anchorPage(mouth)]) {
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
