// The shoggoth: a tentacled, many-eyed blob wearing a yellow smiley mask over its real face, an
// eight-eyed flower. It has no rig; every motion is a deformation in its vertex shader (patched
// into its own lit glTF materials), driven by the pose pet.js works out each frame:
//
//   - its head (the bulb under the mask) turns, nods and swells as one piece, the mask with it;
//   - its mask is a visor hinged at its top edge: it swings up to show the eye-flower whenever its
//     mouth would open (to swallow, yawn, gasp, or a crack when powered up), and orbs go into the
//     flower; a gulp then ripples back from it through the body;
//   - its core breathes; its tentacles wriggle on a phase advanced by dt, spread out with power,
//     a spin or a stretch, curl in when it flinches, sag when it sleeps or is glum, tremble when it
//     frets, swing on springs when it is shaken, and wave round in turn when it dances;
//   - the crown of its head is its forehead: it lights violet when an agent spawns, and its eyes
//     flash with it; its eyes, the flower's too, look where it looks, blink, squint and droop as
//     one, and glow white with power; the U's of its mask's UwU change with its mood
//     (shoggoth-face.js, one table for both);
//   - glum over a limit, it darkens, droops, and its eyes weep dark ooze.

import * as THREE from 'three';
import { GLTFLoader } from '../vendor/three/examples/jsm/loaders/GLTFLoader.js';
import { Phase, tremble } from '../motion.js';
import { BODY_EYE, FLOWER, ALPHA_CUT, EYE_VERTEX_HEAD, EYE_VERTEX, EYE_FRAGMENT_HEAD, eyeMapGlsl, decalAxes, parseTint } from './shoggoth-eyes.js';
import { faceFor, createMask } from './shoggoth-face.js';

const TAU = Math.PI * 2;
const clamp = THREE.MathUtils.clamp;

// Spots on it in model metres (rest pose, the creature stood on the origin by
// scripts/strip_shoggoth_glb.py), measured from its mesh and checked against a render.
const HEAD_PIVOT = [0.09, 1.05, 0.4];   // the head bulb under the mask turns about here
const HEAD_REACH = [0.55, 0.85];        // ... carrying everything this near, fading out to here
const CORE = [0.05, 0.95, -0.1];        // the middle of its body; tentacles start past CORE_REACH[0]
const CORE_REACH = [0.55, 1.4];
const DROOL = [0.12, 0.85, 0.74];       // under the mask's lower edge
const WEEP_FROM = [0.55, 1.35];          // its weeping eyes are on its front between these heights
const WEEPERS = 4;
const OOZE = { color: 0x3a2f4a, emissive: 0x140b22 };   // what it weeps
const MASK_LIFT = 1.9;                  // rad the mask flips up, like a visor, when its mouth is fully open

const SHOGGOTH = {
  kind: 'shoggoth',
  name: 'Shoggoth',
  // Its round middle for the orbit: the rings' top tucks a third of an orb behind TOP and their
  // bottom passes in front of its lower tentacles (Tests/Pet/bodies.test.mjs).
  ball: { x: 0.05, y: 0.92, r: 0.71 },
  top: 1.62,
  soles: 1.3,
  // Its forehead is the top of its head, where orbs come out; its mouth is the middle of the
  // eye-flower under its mask, just in front of it.
  anchors: { forehead: { x: 0.08, y: 1.47, z: 0.56 }, mouth: { x: 0.095, y: 1.15, z: 0.86 } },
  // It is wider than T3boii, so it stands a little shorter on screen.
  frame: 0.75,
  load,
};
export default SHOGGOTH;

async function load({ renderer, scene, rig, tint }) {
  const gltf = await new Promise((resolve, reject) => {
    new GLTFLoader().load(new URL('../shoggoth.glb', import.meta.url).href, resolve, undefined, reject);
  });
  const character = gltf.scene;
  rig.add(character);
  return assemble({ character, renderer, scene, tint });
}

function assemble({ character, renderer, scene, tint }) {
  character.updateMatrixWorld(true);
  // GLTFLoader drops the dots from node names ('mask.001' is 'mask001').
  const node = (name) => character.getObjectByName(THREE.PropertyBinding.sanitizeNodeName(name));
  const root = node('shoggoth_unanimated') ?? character.children[0];
  // Body space: the root's own, where its meshes' vertices live.
  const toBody = (p) => root.worldToLocal(Array.isArray(p) ? new THREE.Vector3(...p) : new THREE.Vector3(p.x, p.y, p.z));
  const CROWN = SHOGGOTH.anchors.forehead, MOUTH = SHOGGOTH.anchors.mouth;

  const materials = {};
  character.traverse((o) => {
    if (!o.isMesh) return;
    o.frustumCulled = false;
    materials[o.material.name] = o.material;
    if (o.material.map) o.material.map.anisotropy = o.material.map.magFilter === THREE.NearestFilter ? 1 : Math.min(8, renderer.capabilities.getMaxAnisotropy());
  });

  // The head carries the mask's string; the visor, hinged at the mask's top edge, carries the mask
  // and its text.
  const head = new THREE.Object3D();
  head.name = 'ShoggothHead';
  head.matrixAutoUpdate = false;
  root.add(head);
  const disc = node('mask.001'), text = node('mask text.001'), string = node('mask string.001');
  const visor = new THREE.Object3D();
  visor.name = 'ShoggothVisor';
  let hingeAxis = new THREE.Vector3(1, 0, 0);
  if (disc) {
    const centre = disc.position.clone();
    let normal = new THREE.Vector3(0, 1, 0).applyQuaternion(disc.quaternion).normalize();
    if (normal.z < 0) normal.negate();
    const up = new THREE.Vector3(0, 1, 0).addScaledVector(normal, -normal.y).normalize();
    const radius = new THREE.Box3().setFromObject(disc).getSize(new THREE.Vector3()).x / 2;
    visor.position.copy(centre).addScaledVector(up, radius);
    hingeAxis = normal.clone().cross(up).normalize();
  }
  head.add(visor);
  character.updateMatrixWorld(true);
  if (string) head.attach(string);
  if (disc) visor.attach(disc);
  if (text) visor.attach(text);
  const visorRest = visor.quaternion.clone();

  // ------------------------------------------------------------------ shader
  //
  // One set of uniforms deforms every material of its body (skin, belly, eyes, eye-flower) alike,
  // in body space, from where each vertex rests.

  const shape = {
    uHead: { value: new THREE.Matrix4() }, uHeadPivot: { value: toBody(HEAD_PIVOT) }, uHeadReach: { value: new THREE.Vector2(...HEAD_REACH) },
    uCore: { value: toBody(CORE) }, uCoreReach: { value: new THREE.Vector2(...CORE_REACH) },
    uBreath: { value: 0 }, uWriggle: { value: new THREE.Vector2() }, uSpread: { value: 0 }, uLift: { value: 0 },
    uJiggle: { value: new THREE.Vector3() }, uTremble: { value: new THREE.Vector3() }, uWave: { value: new THREE.Vector2() },
    uMouth: { value: toBody(MOUTH) }, uGulp: { value: new THREE.Vector2() }, uSuck: { value: 0 },
    uCrown: { value: toBody(CROWN) }, uPsy: { value: 0 }, uPsyFlare: { value: 0 }, uTime: { value: 0 },
    uEyes: { value: 0 }, uMouthGlow: { value: 0 }, uBlush: { value: 0 }, uSad: { value: 0 },
    uLids: { value: new THREE.Vector4(0, 0.62, 0, 0) }, uIris: { value: 1 }, uGaze: { value: new THREE.Vector3() },
    uTint: { value: new THREE.Color(parseTint(tint)) },
  };

  const vertexHead = `uniform mat4 uHead;
uniform vec3 uHeadPivot, uCore, uMouth, uJiggle, uTremble;
uniform vec2 uHeadReach, uCoreReach, uWriggle, uWave, uGulp;
uniform float uBreath, uSpread, uLift, uSuck;
varying vec3 vRest;
`;
  const bend = `#include <beginnormal_vertex>
  float shogHead = 1.0 - smoothstep(uHeadReach.x, uHeadReach.y, distance(position, uHeadPivot));
  objectNormal = normalize(mix(objectNormal, mat3(uHead) * objectNormal, shogHead));`;
  const move = `#include <begin_vertex>
  {
    vRest = position;
    vec3 p = transformed;
    // Its mouth sucks in while it eats; then a gulp ripples back from it.
    float dm = distance(position, uMouth);
    p -= normal * uSuck * 0.07 * (1.0 - smoothstep(0.0, 0.3, dm));
    p += normal * uGulp.y * 0.06 * exp(-pow((dm - uGulp.x) / 0.16, 2.0));
    p = mix(p, (uHead * vec4(p, 1.0)).xyz, shogHead);
    vec3 c = position - uCore;
    float reach = smoothstep(uCoreReach.x, uCoreReach.y, length(c)) * (1.0 - shogHead);
    float r2 = reach * reach;
    vec2 outward = length(c.xz) > 1e-4 ? normalize(c.xz) : vec2(0.0);
    p += c * uBreath * (1.0 - reach) * (1.0 - shogHead);
    p.xz += outward * uSpread * r2;
    p.y += uLift * r2;
    float d = length(c);
    p += r2 * uWriggle.y * vec3(sin(uWriggle.x + 2.3 * d + position.z * 1.7), 0.6 * sin(uWriggle.x * 0.8 + 2.9 * d + position.x * 1.3), cos(uWriggle.x + 2.1 * d + position.x * 1.9));
    p += r2 * uJiggle;
    p += r2 * uTremble.z * vec3(mix(uTremble.x, uTremble.y, fract(position.x * 7.3)), 0.5 * mix(uTremble.y, uTremble.x, fract(position.z * 5.1)), mix(uTremble.x, -uTremble.y, fract(position.y * 3.7)));
    p.y += r2 * uWave.y * sin(uWave.x - 2.0 * atan(c.z, c.x));
    transformed = p;
  }`;
  const fragmentHead = `varying vec3 vRest;
uniform vec3 uCrown, uHeadPivot, uTint;
uniform float uPsy, uPsyFlare, uTime, uEyes, uMouthGlow, uBlush, uSad;
`;
  // Its crown lights violet as an agent leaves it, a ripple running out from the middle; petted, its
  // head flushes pink; glum, it darkens.
  const skinLight = `#include <emissivemap_fragment>
  {
    float crown = 1.0 - smoothstep(0.0, 1.0, length((vRest - uCrown) / vec3(0.36, 0.26, 0.36)));
    if (uPsy > 0.001 && crown > 0.0) {
      float run = 0.8 + 0.2 * sin(length(vRest - uCrown) * 28.0 - uTime * 4.0);
      diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(0.6, 0.42, 1.0), uPsy * crown);
      totalEmissiveRadiance += uPsy * crown * run * vec3(0.45, 0.16, 1.0) * (0.7 + 0.9 * uPsyFlare);
    }
    float cheek = 1.0 - smoothstep(0.0, 1.0, length((vRest - uHeadPivot - vec3(0.0, 0.05, 0.25)) / vec3(0.48, 0.32, 0.42)));
    diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0, 0.5, 0.62), uBlush * cheek * 0.5);
    diffuseColor.rgb *= 1.0 - 0.32 * uSad;
  }`;
  // Every eye (shoggoth-eyes.js): its iris where it looks, lids over the white; power whitens and
  // lights only bare eye, its pupil and iris showing through until it is white right across, and
  // it is brightest in the middle; it flashes violet with the crown, more the nearer it is.
  const eyeLight = `#include <emissivemap_fragment>
  {
    float ink = 1.0 - smoothstep(0.05, 0.6, dot(diffuseColor.rgb, vec3(0.2126, 0.7152, 0.0722)));
    float glow = uEyes * shogBare * (1.0 - 0.95 * ink * (1.0 - smoothstep(0.6, 1.0, uEyes)));
    diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0), glow);
    totalEmissiveRadiance += glow * (0.55 + 0.45 * (1.0 - shogRing)) * vec3(1.0, 0.99, 1.04) * 1.3;
    float near = 1.0 - smoothstep(0.2, 1.4, distance(vRest, uCrown));
    totalEmissiveRadiance += shogBare * uPsy * (0.3 + 0.7 * near) * (0.5 + 1.2 * uPsyFlare) * vec3(0.55, 0.25, 1.0);
  }`;
  // The eye-flower: its own shade, the same power whitening of its open eyes, and the warm light
  // that pours from it at full power.
  const flowerLight = `#include <emissivemap_fragment>
  {
    diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0), uEyes * 0.7 * shogBare);
    totalEmissiveRadiance += uEyes * shogBare * vec3(1.0, 0.99, 1.04) * 1.2 + uMouthGlow * vec3(1.0, 0.93, 0.8) * 2.6;
    totalEmissiveRadiance += shogBare * uPsy * (0.5 + 1.2 * uPsyFlare) * vec3(0.55, 0.25, 1.0);
  }`;

  const patch = (material, fragment, eye = false) => {
    if (!material) return;
    material.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, shape);
      let vertex = shader.vertexShader.replace('#include <beginnormal_vertex>', bend).replace('#include <begin_vertex>', move);
      if (eye) vertex = EYE_VERTEX_HEAD + vertex.replace('#include <uv_vertex>', `#include <uv_vertex>\n  ${EYE_VERTEX}`);
      shader.vertexShader = vertexHead + vertex;
      shader.fragmentShader = fragmentHead + (eye ? EYE_FRAGMENT_HEAD : '') + fragment(shader.fragmentShader);
    };
    material.needsUpdate = true;
  };
  patch(materials['shoggoth skin'], (f) => f.replace('#include <emissivemap_fragment>', skinLight));
  patch(materials['shoggoth belly'], (f) => f.replace('#include <emissivemap_fragment>', skinLight));
  patch(materials['shoggoth eye'], (f) => f.replace('#include <map_fragment>', eyeMapGlsl(BODY_EYE)).replace('#include <emissivemap_fragment>', eyeLight), true);
  const flower = materials['shoggoth eyeface'];
  if (flower) {
    // As in Blender: alpha over the cut is solid, the rest is not drawn.
    Object.assign(flower, { transparent: false, depthWrite: true, alphaTest: ALPHA_CUT });
    patch(flower, (f) => f.replace('#include <map_fragment>', eyeMapGlsl(FLOWER)).replace('#include <emissivemap_fragment>', flowerLight), true);
  }
  // Each eye decal's texture axes, so its iris can turn toward what it looks at.
  character.traverse((o) => {
    if (!o.isMesh || (o.material.name !== 'shoggoth eye' && o.material.name !== 'shoggoth eyeface')) return;
    const g = o.geometry;
    const { eyeU, eyeV } = decalAxes(g.attributes.position.array, g.attributes.uv.array, g.index.array);
    g.setAttribute('shogEyeU', new THREE.BufferAttribute(eyeU, 3));
    g.setAttribute('shogEyeV', new THREE.BufferAttribute(eyeV, 3));
  });
  const mask = createMask(text);

  // ----------------------------------------------------------------- anchors

  const crown = toBody(CROWN), mouth = toBody(MOUTH), drool = toBody(DROOL);
  // Weeping eyes: its front eyes nearest its face, each with a track down the skin below it, found by
  // casting rays at it in the rest pose and kept in body space with the skin's normal at each point
  // (the shader moves skin along it). Its tears are dark ooze.
  const skinMeshes = [], eyeMeshes = [];
  character.traverse((o) => {
    if (!o.isMesh) return;
    if (o.material.name === 'shoggoth skin' || o.material.name === 'shoggoth belly') skinMeshes.push(o);
    if (o.material.name === 'shoggoth eye') eyeMeshes.push(o);
  });
  scene.updateMatrixWorld(true);
  const ray = new THREE.Raycaster(), back = new THREE.Vector3(0, 0, -1);
  const castAt = (x, y, meshes) => { ray.set(new THREE.Vector3(x, y, 5), back); return ray.intersectObjects(meshes, false)[0] ?? null; };
  const maskCentre = disc ? disc.getWorldPosition(new THREE.Vector3()) : null;
  const pivotWorld = root.localToWorld(toBody(HEAD_PIVOT));
  const weepers = [];
  for (let y = WEEP_FROM[1]; y >= WEEP_FROM[0]; y -= 0.04) {
    for (let x = -0.8; x <= 0.9; x += 0.04) {
      if (maskCentre && Math.hypot(x - maskCentre.x, y - maskCentre.y) < 0.36) continue;
      const hit = castAt(x, y, [...eyeMeshes, ...skinMeshes]);
      if (!hit || !eyeMeshes.includes(hit.object) || !hit.uv || Math.abs(hit.uv.x - 0.5) > 0.15 || Math.abs(hit.uv.y - 0.5) > 0.15) continue;
      if (weepers.some((w) => w.point.distanceTo(hit.point) < 0.22)) continue;
      weepers.push(hit);
    }
  }
  weepers.sort((a, b) => a.point.distanceTo(pivotWorld) - b.point.distanceTo(pivotWorld));
  // The meshes sit untransformed in the root, so a hit's normal is already in body space.
  const restOf = (hit, lift = 0) => ({ at: root.worldToLocal(hit.point.clone().add(new THREE.Vector3(0, 0, lift))), normal: hit.normal.clone().normalize() });
  // A track starts on the skin just under its eye; one whose first ray passes the eye's own surface
  // and lands on something behind is no track for that eye.
  const oozePaths = weepers.map((eye) => {
    const points = [];
    for (let k = 0; k <= 9; k += 1) {
      const hit = castAt(eye.point.x, eye.point.y - 0.05 - 0.035 * k, [...skinMeshes, ...eyeMeshes]);
      if (!hit || (points.length ? hit.point.z < points.at(-1).z - 0.12 : hit.point.distanceTo(eye.point) > 0.09)) break;
      points.push(hit);
    }
    return points.length >= 4 ? { eye: restOf(eye), points: points.map((hit) => restOf(hit, 0.015)) } : null;
  }).filter(Boolean).slice(0, WEEPERS);

  // The vertex shader's `move` (above) in JS, for what rides its skin: where a body-space point at
  // rest, its skin facing `normal`, is this frame. The `weep` still checks it against the GPU's.
  const smoothstep = (a, b, x) => { const u = clamp((x - a) / (b - a), 0, 1); return u * u * (3 - 2 * u); };
  const fract = (x) => x - Math.floor(x);
  const mix = (a, b, u) => a + (b - a) * u;
  const headed = new THREE.Vector3(), fromCore = new THREE.Vector3();
  function deform({ at: rest, normal }, out = new THREE.Vector3()) {
    const { uHead, uHeadPivot, uHeadReach, uCore, uCoreReach, uMouth, uSuck, uGulp, uBreath, uSpread, uLift, uWriggle, uJiggle, uTremble, uWave } = shape;
    const shogHead = 1 - smoothstep(uHeadReach.value.x, uHeadReach.value.y, rest.distanceTo(uHeadPivot.value));
    const p = out.copy(rest);
    const dm = rest.distanceTo(uMouth.value);
    p.addScaledVector(normal, -uSuck.value * 0.07 * (1 - smoothstep(0, 0.3, dm)));
    p.addScaledVector(normal, uGulp.value.y * 0.06 * Math.exp(-(((dm - uGulp.value.x) / 0.16) ** 2)));
    p.lerp(headed.copy(p).applyMatrix4(uHead.value), shogHead);
    const c = fromCore.subVectors(rest, uCore.value), d = c.length();
    const reach = smoothstep(uCoreReach.value.x, uCoreReach.value.y, d) * (1 - shogHead);
    const r2 = reach * reach;
    const flat = Math.hypot(c.x, c.z);
    p.addScaledVector(c, uBreath.value * (1 - reach) * (1 - shogHead));
    if (flat > 1e-4) { p.x += (c.x / flat) * uSpread.value * r2; p.z += (c.z / flat) * uSpread.value * r2; }
    p.y += uLift.value * r2;
    const [phase, size] = [uWriggle.value.x, uWriggle.value.y];
    p.x += r2 * size * Math.sin(phase + 2.3 * d + rest.z * 1.7);
    p.y += r2 * size * 0.6 * Math.sin(phase * 0.8 + 2.9 * d + rest.x * 1.3);
    p.z += r2 * size * Math.cos(phase + 2.1 * d + rest.x * 1.9);
    p.addScaledVector(uJiggle.value, r2);
    const { x: ta, y: tb, z: shiver } = uTremble.value;
    p.x += r2 * shiver * mix(ta, tb, fract(rest.x * 7.3));
    p.y += r2 * shiver * 0.5 * mix(tb, ta, fract(rest.z * 5.1));
    p.z += r2 * shiver * mix(ta, -tb, fract(rest.y * 3.7));
    p.y += r2 * uWave.value.y * Math.sin(uWave.value.x - 2 * Math.atan2(c.z, c.x));
    return p;
  }

  /// The vertex shader's own answer for where body-space rest points are this frame, read back from
  /// the GPU: what `deform` has to agree with.
  function deformOnGpu(renderer, rests) {
    const n = rests.length;
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute(rests.flatMap((r) => r.at.toArray()), 3));
    geometry.setAttribute('normal', new THREE.Float32BufferAttribute(rests.flatMap((r) => r.normal.toArray()), 3));
    geometry.setAttribute('slot', new THREE.Float32BufferAttribute(rests.map((_, i) => i), 1));
    const material = new THREE.ShaderMaterial({
      uniforms: shape,
      vertexShader: `${vertexHead}attribute float slot;
varying vec3 vMoved;
void main() {
  vec3 objectNormal = normal;
  ${bend.replace('#include <beginnormal_vertex>', '')}
  vec3 transformed = position;
  ${move.replace('#include <begin_vertex>', '')}
  vMoved = transformed;
  gl_Position = vec4((2.0 * slot + 1.0) / ${n.toFixed(1)} - 1.0, 0.0, 0.0, 1.0);
  gl_PointSize = 1.0;
}`,
      fragmentShader: 'varying vec3 vMoved;\nvoid main() { gl_FragColor = vec4(vMoved, 1.0); }',
    });
    const probe = new THREE.Points(geometry, material);
    probe.frustumCulled = false;
    const stage = new THREE.Scene().add(probe);
    const target = new THREE.WebGLRenderTarget(n, 1, { type: THREE.FloatType, depthBuffer: false, minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter });
    const before = renderer.getRenderTarget();
    renderer.setRenderTarget(target);
    renderer.render(stage, new THREE.Camera());
    const read = new Float32Array(4 * n);
    renderer.readRenderTargetPixels(target, 0, 0, n, 1, read);
    renderer.setRenderTarget(before);
    target.dispose(); material.dispose(); geometry.dispose();
    return rests.map((_, i) => new THREE.Vector3(read[4 * i], read[4 * i + 1], read[4 * i + 2]));
  }

  // ------------------------------------------------------------------- pose

  const wriggle = new Phase();
  const jiggle = { x: 0, y: 0, vx: 0, vy: 0 };
  const pivot = shape.uHeadPivot.value;
  const turn = new THREE.Euler(0, 0, 0, 'YXZ');
  const mTurn = new THREE.Matrix4(), mScale = new THREE.Matrix4(), mTo = new THREE.Matrix4(), mFrom = new THREE.Matrix4();
  const lift = new THREE.Quaternion();
  let shown = null;   // the face it showed last frame, for the stills' evidence

  /// Tentacles on springs: a shake swings them against the hand; let go, they settle.
  function stepJiggle({ dt, held, ax, ay }) {
    const k = held ? 18 : 40, c = held ? 3 : 7;
    const tx = clamp(-ax * 4e-6, -0.35, 0.35), ty = clamp(ay * 4e-6, -0.35, 0.35);
    jiggle.vx += ((tx - jiggle.x) * k - c * jiggle.vx) * dt;
    jiggle.vy += ((ty - jiggle.y) * k - c * jiggle.vy) * dt;
    jiggle.x += jiggle.vx * dt;
    jiggle.y += jiggle.vy * dt;
    return Math.abs(jiggle.x) + Math.abs(jiggle.y) + 0.1 * (Math.abs(jiggle.vx) + Math.abs(jiggle.vy));
  }

  return {
    character,
    restPose() {},

    pose(P) {
      const { t, dt, amp, p, S, sad, face, gaze } = P;
      // Its head: nods with its breath, sleep and glum (headDip), follows its gaze, tips toward a new
      // question, hangs lopsided in its grin, and puffs with a gulp.
      turn.set(
        P.headDip - gaze.y * 0.12 + 0.12 * face.frown - 0.06 * face.smile,
        gaze.x * 0.22,
        0.16 * face.smirk - 0.14 * P.nodSide * P.nod,
      );
      const puff = 1 + 0.035 * P.gulpPulse + 0.012 * P.breath;
      mTo.makeTranslation(pivot.x, pivot.y, pivot.z);
      mFrom.makeTranslation(-pivot.x, -pivot.y, -pivot.z);
      mTurn.makeRotationFromEuler(turn);
      mScale.makeScale(puff, puff, puff);
      head.matrix.copy(mTo).multiply(mTurn).multiply(mScale).multiply(mFrom);
      head.matrixWorldNeedsUpdate = true;
      shape.uHead.value.copy(head.matrix);
      // Its mask flips up to show its mouth whenever its mouth would open; half open is enough to
      // clear the eye-flower, so the light at full power gets out.
      visor.quaternion.copy(visorRest).multiply(lift.setFromAxisAngle(hingeAxis, MASK_LIFT * clamp(1.6 * face.open, 0, 1)));

      // Its core breathes; its tentacles wriggle, quicker with power and work, slow asleep or glum.
      shape.uBreath.value = 0.02 * P.breath;
      const pace = TAU / ((3.4 - 1.1 * p - 0.6 * P.busy + 2.6 * S + 1.4 * sad) * P.look.breath);
      shape.uWriggle.value.set(wriggle.advance(dt, pace) % (TAU * 64), amp * (0.03 + 0.025 * p + 0.012 * P.drift) * (1 - 0.6 * S) * (1 - 0.5 * sad) + 0.06 * P.D);
      shape.uSpread.value = 0.1 * p + 0.22 * P.spinning + 0.14 * P.stretch + 0.12 * P.startle - 0.1 * P.flinch - 0.05 * S - amp * P.look.arms
        - 0.04 * sad + 0.04 * P.D * Math.sin(P.beat);
      shape.uLift.value = 0.08 * p + 0.16 * P.stretch - 0.16 * S - 0.2 * sad + (P.held ? -0.1 : 0) + 0.03 * P.sob;
      const energy = stepJiggle(P);
      shape.uJiggle.value.set(jiggle.x, jiggle.y, 0);
      // Fretful, its tentacle tips tremble; sobbing, they shudder.
      const shiver = P.reduced ? 0 : 0.012 * P.fretful + 0.02 * P.shudder;
      shape.uTremble.value.set(tremble(t, 26), tremble(t, 31, 1.7), shiver);
      shape.uWave.value.set(P.beat, 0.12 * P.D);

      // Its mouth: sucks in as it eats; a gulp ripples back through it.
      shape.uSuck.value = face.pucker;
      const since = P.sinceGulp;
      shape.uGulp.value.set(since * 1.6, since < 0.8 ? 1 - since / 0.8 : 0);

      // Its face (shoggoth-face.js): the lids' shape and the iris from its state, closing at least
      // as far as the brain's own lid; its eyes turn less the lower its lids.
      const now = faceFor(P);
      const closed = clamp(Math.max(P.lid, now.eyes.close), 0, 1);
      shape.uLids.value.set(closed, now.eyes.split, now.eyes.curve, now.eyes.flat);
      shape.uIris.value = now.eyes.iris;
      shape.uGaze.value.set(clamp(gaze.x, -1, 1), clamp(gaze.y, -1, 1), 0).multiplyScalar(1 - 0.7 * closed);
      mask?.step(now, t, P.reduced);
      shown = now;
      shape.uPsy.value = P.glow.psy;
      shape.uPsyFlare.value = P.glow.flare;
      shape.uTime.value = t;
      shape.uEyes.value = P.glow.eyes;
      shape.uMouthGlow.value = P.glow.mouth;
      shape.uBlush.value = P.glow.blush;
      shape.uSad.value = sad;
      return energy;
    },

    light() {},

    anchor(name, out) {
      const at = name === 'forehead' ? crown : name === 'mouth' ? mouth : null;
      return at ? head.localToWorld(out.copy(at)) : null;
    },

    droolCorner() {
      return head.localToWorld(drool.clone());
    },

    // Its skin bends with its head and body, which no one matrix carries, so the ooze is laid along
    // the skin as it is each frame.
    tears: oozePaths.length,
    tear(i, rig) {
      const path = oozePaths[i % oozePaths.length];
      if (!path) return null;
      rig.updateMatrixWorld(true);
      return { points: () => path.points.map((rest) => root.localToWorld(deform(rest))), tint: OOZE };
    },

    setTint(hex) {
      shape.uTint.value.set(parseTint(hex));
      return parseTint(hex);
    },

    internals: { shape, head, visor, materials, root, deform, deformOnGpu, mask, get face() { return shown; }, get oozePaths() { return oozePaths; } },
  };
}
