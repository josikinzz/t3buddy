// T3boii's body: the rigged T3 doll, his bones, lids, lip shapes and the light in his face.
//
// pet.js owns what is happening (moods, power, swallows, sleep, petting, the frame loop) and boils
// it down each frame to a pose (see `pose` in pet.js); this module turns that pose into his bones,
// morphs and glow, and tells the shared systems where his ball, forehead and mouth are.

import * as THREE from 'three';
import { GLTFLoader } from '../vendor/three/examples/jsm/loaders/GLTFLoader.js';
import { smoothSkinning, bindLidsToFace } from '../skinning.js';

// Spots on his skin, in model metres (rest pose, seen from the front), measured against a
// render: his cheeks (his forehead and mouth are in T3BOII.anchors).
const CHEEK_RAYS = [{ x: 0.36, y: 0.86 }, { x: -0.36, y: 0.86 }];
const HEAD_BONE = 'Bone_011';   // the bone his face skin follows (the eyes ride it too; see load)
const LID_SHUT = 1;     // share of the blink morph that reads as shut (see installEyeMask)
const EYE_ROLL = 0.45;   // rad the eyes roll up behind closed lids

const clamp = THREE.MathUtils.clamp;
const clamp01 = (v) => clamp(v, 0, 1);
const smooth = (a, b, v) => { const t = clamp01((v - a) / (b - a)); return t * t * (3 - 2 * t); };
const v3 = () => new THREE.Vector3();
const q4 = () => new THREE.Quaternion();

const T3BOII = {
  kind: 't3boii',
  name: 'T3boii',
  // His ball body (centre and radius in model metres; the egg is within a few percent of a
  // sphere), and his soles, in ball radii below its centre. The rings hug the ball.
  ball: { x: 0.015, y: 1.07, r: 0.66 },
  top: 1.73,
  soles: 1.62,
  // The middle of the T3 logo and of his mouth, seen from the front and measured against a
  // render; load() finds the skin under each and rides it.
  anchors: { forehead: { x: -0.03, y: 1.355 }, mouth: { x: 0.022, y: 0.797 } },
  // His height on screen, as a share of the frame his rest pose is fitted to.
  frame: 1,
  load,
};
export default T3BOII;

/// Loads him into `rig` and readies his bones, morphs, anchors, glow shader, eye mask and light
/// sprites. Resolves to the body pet.js drives.
async function load({ renderer, scene, rig }) {
  const gltf = await new Promise((resolve, reject) => {
    new GLTFLoader().load(new URL('../T3-rigged.glb', import.meta.url).href, resolve, undefined, reject);
  });
  const character = gltf.scene;
  rig.add(character);
  return assemble({ character, renderer, scene });
}

function assemble({ character, renderer, scene }) {
  const bones = {};
  const rest = {};
  const morphs = {};
  const bodyMeshes = [];          // the skinned body (face, eyes, mouth), for the glow shader

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

  /// Where his tears run: for each eye, from just under it down his cheek, found by casting rays at
  /// his front in the rest pose (so they follow his skin), and kept in the space of the bone his face
  /// skin follows, so they ride his head.
  function findTearPaths() {
    const head = bones[HEAD_BONE];
    if (!head) return [];
    scene.updateMatrixWorld(true);
    const ray = new THREE.Raycaster();
    return eyes.map((eye) => {
      const centre = eye.bone.getWorldPosition(v3());
      const side = Math.sign(centre.x - BALL.x) || 1;
      const points = [];
      for (let k = 0; k <= 9; k += 1) {
        const u = k / 9;
        const x = centre.x + side * eye.radius * (0.25 + 0.9 * u), y = centre.y - eye.radius * 1.02 - 0.27 * u;
        ray.set(new THREE.Vector3(x, y, 5), new THREE.Vector3(0, 0, -1));
        const hit = ray.intersectObject(character, true).find((h) => h.object.isSkinnedMesh && !h.object.name.startsWith('Lid'));
        if (!hit) continue;
        // Just off his skin, so the drop sits on it rather than in it.
        points.push(head.worldToLocal(hit.point.clone().add(v3().set(0, 0, 0.012))));
      }
      return points.length >= 4 ? points : null;
    }).filter(Boolean);
  }

  /// How near each vertex round the T3 on his forehead lies to its ink, blurred over his skin: the
  /// attribute `aT3Bloom` (0 .. 1), the shape of the light the T3 spills round itself as it glows.
  /// His face's UVs are cut into many small islands, so a blur in texture space would smear across
  /// their seams; this one is measured over his surface instead, once, in the rest pose.
  function bakeT3Bloom() {
    const centre = forehead && anchorWorld(forehead, v3());
    // REGION is the glow shader's ellipse round the T3; SIGMA how far the bloom spreads, in metres.
    const REGION = v3().set(0.34, 0.22, 0.4), SIGMA = 0.036, CELL = SIGMA * 3;
    const inRegion = (p) => centre && p.clone().sub(centre).divide(REGION).length() < 1;
    for (const mesh of bodyMeshes) {
      const g = mesh.geometry, pos = g.attributes.position, uv = g.attributes.uv;
      const bloom = new Float32Array(pos.count);
      g.setAttribute('aT3Bloom', new THREE.BufferAttribute(bloom, 1));
      const map = mesh.material.map;
      if (!centre || !map?.image || !uv || !g.index) continue;
      // The texture, small: enough to find the ink.
      const size = 512, canvas = document.createElement('canvas');
      canvas.width = canvas.height = size;
      const context = canvas.getContext('2d', { willReadFrequently: true });
      context.drawImage(map.image, 0, 0, size, size);
      const pixels = context.getImageData(0, 0, size, size).data;
      const inkAt = (u, v) => {
        const x = Math.min(size - 1, Math.max(0, Math.floor(u * size)));
        const y = Math.min(size - 1, Math.max(0, Math.floor((map.flipY ? 1 - v : v) * size)));
        const k = (y * size + x) * 4;
        return 1 - smooth(0.25, 0.6, (0.299 * pixels[k] + 0.587 * pixels[k + 1] + 0.114 * pixels[k + 2]) / 255);
      };
      // The vertices round the T3 (found roughly in the bind pose first, it is cheaper than skinning
      // every vertex), bucketed by where they are.
      const near = new Map(), cells = new Map(), rough = v3(), at = new Float32Array(pos.count * 3);
      const cellKey = (x, y, z) => ((x + 512) * 1024 + (y + 512)) * 1024 + (z + 512);
      const loose = REGION.clone().multiplyScalar(1.4);
      for (let i = 0; i < pos.count; i += 1) {
        if (rough.fromBufferAttribute(pos, i).applyMatrix4(mesh.matrixWorld).sub(centre).divide(loose).lengthSq() > 1) continue;
        const p = mesh.getVertexPosition(i, v3()).applyMatrix4(mesh.matrixWorld);
        if (!inRegion(p)) continue;
        near.set(i, p);
        at[i * 3] = p.x; at[i * 3 + 1] = p.y; at[i * 3 + 2] = p.z;
        const key = cellKey(Math.floor(p.x / CELL), Math.floor(p.y / CELL), Math.floor(p.z / CELL));
        (cells.get(key) || cells.set(key, []).get(key)).push(i);
      }
      // Dense samples of ink over every triangle there, each spread onto the vertices round it.
      const sum = new Float32Array(pos.count), weight = new Float32Array(pos.count);
      const index = g.index, p = v3(), N = 2, spread = 1 / (2 * SIGMA * SIGMA);
      for (let f = 0; f < index.count; f += 3) {
        const a = index.getX(f), b = index.getX(f + 1), c = index.getX(f + 2);
        const pa = near.get(a), pb = near.get(b), pc = near.get(c);
        if (!pa || !pb || !pc) continue;
        for (let s = 0; s <= N; s += 1) {
          for (let r = 0; r <= N - s; r += 1) {
            const wa = s / N, wb = r / N, wc = 1 - wa - wb;
            p.copy(pa).multiplyScalar(wa).addScaledVector(pb, wb).addScaledVector(pc, wc);
            const ink = inkAt(uv.getX(a) * wa + uv.getX(b) * wb + uv.getX(c) * wc, uv.getY(a) * wa + uv.getY(b) * wb + uv.getY(c) * wc);
            const cx = Math.floor(p.x / CELL), cy = Math.floor(p.y / CELL), cz = Math.floor(p.z / CELL);
            for (let dx = -1; dx <= 1; dx += 1) for (let dy = -1; dy <= 1; dy += 1) for (let dz = -1; dz <= 1; dz += 1) {
              const cell = cells.get(cellKey(cx + dx, cy + dy, cz + dz));
              if (!cell) continue;
              for (const i of cell) {
                const x = at[i * 3] - p.x, y = at[i * 3 + 1] - p.y, z = at[i * 3 + 2] - p.z, d2 = x * x + y * y + z * z;
                if (d2 > CELL * CELL) continue;
                const w = Math.exp(-d2 * spread);
                sum[i] += ink * w;
                weight[i] += w;
              }
            }
          }
        }
      }
      for (const i of near.keys()) bloom[i] = weight[i] > 1e-6 ? sum[i] / weight[i] : 0;
    }
  }

  // ------------------------------------------------------------------- glow
  //
  // One small patch to his skin shader lights up parts of him by where they are on his body:
  // the dark ink of the T3 logo (psychic), his whole eyeballs and the inside of his mouth
  // (power), and a blush on his cheeks (petting). Positions are in the body mesh's own space
  // after skinning, so the glow rides every pose.

  const glow = {
    uPsy: { value: 0 }, uPsyFlare: { value: 0 }, uTime: { value: 0 },
    uEyes: { value: 0 }, uMouthGlow: { value: 0 }, uBlush: { value: 0 },
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
varying float vT3Bloom;
uniform float uPsy, uPsyFlare, uTime, uEyes, uMouthGlow, uBlush, uEyeRadius, uMaskDebug;
uniform vec3 uForehead, uMouth, uEyeL, uEyeR, uCheekL, uCheekR;
uniform mat3 uFaceBasis;
` + shader.fragmentShader.replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
  {
    float lum = dot(diffuseColor.rgb, vec3(0.299, 0.587, 0.114));
    float ink = smoothstep(0.34, 0.08, lum);
    float fm = 1.0 - smoothstep(0.55, 1.0, length((vT3Pos - uForehead) / vec3(0.34, 0.22, 0.4)));
    if (uPsy > 0.001 && fm > 0.0) {
      // The T3 lights up like violet neon: its strokes burn a deep, saturated violet, paler at their
      // core as each ripple leaves it, light running along the letters, and the skin round them
      // takes on their violet light in a bloom shaped to the letters (see bakeT3Bloom). His skin is
      // too pale to show light added to it, so the bloom tints it as well as lighting it.
      float halo = clamp((vT3Bloom - ink) * 2.8, 0.0, 1.0);
      halo *= halo * (3.0 - 2.0 * halo);
      float core = ink * smoothstep(0.4, 0.8, vT3Bloom);
      float run = 0.86 + 0.14 * sin(vT3Pos.x * 32.0 - uTime * 3.2);
      vec3 burn = mix(vec3(0.5, 0.2, 1.0), vec3(0.94, 0.84, 1.0), clamp(core * (0.4 + 0.6 * uPsyFlare), 0.0, 1.0));
      diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(0.55, 0.38, 1.0), uPsy * fm * halo);
      totalEmissiveRadiance += uPsy * fm * (ink * burn * (1.1 + 0.9 * uPsyFlare) * run + vec3(0.4, 0.14, 1.0) * halo * (0.25 + 0.35 * uPsyFlare));
    }
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
  /// down). Also hands the skinned position, and how near the T3's ink it is, to the fragment shader.
  /// Shared by every material that draws his body, so they all agree to the pixel.
  function patchVertex(shader) {
    Object.assign(shader.uniforms, glow);
    shader.vertexShader = `varying vec3 vT3Pos;
attribute float aT3Bloom;
varying float vT3Bloom;
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
  }`).replace('#include <skinning_vertex>', '#include <skinning_vertex>\n  vT3Pos = transformed;\n  vT3Bloom = aT3Bloom;');
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
  // never over a lid, and a soft halo spilling around it), and a few sparks of energy around his
  // mouth.
  const sprites = { eyes: [], eyeHalos: [], sparks: [] };
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
    sprites.sparks = Array.from({ length: 7 }, () => make(0xffffff));
  }

  function showSprite(sprite, position, size, opacity) {
    sprite.visible = opacity > 0.003;
    if (!sprite.visible) return;
    sprite.position.copy(position);
    sprite.scale.set(size, size, 1);
    sprite.material.opacity = Math.min(1, opacity);
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

  /// Steps the limb springs; returns how much they are still moving.
  function stepLimbs({ t, dt, held, ax, ay }) {
    const k = held ? 16 : 46, c = held ? 2.6 : 7.5;
    // Inertia: limbs lag the hand that moves him; dropping fast lifts them, a sharp stop flings them.
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
    return energy;
  }

  // ---------------------------------------------------------------- assemble

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

  const BALL = T3BOII.ball;
  const forehead = findAnchor(T3BOII.anchors.forehead);
  const mouth = findAnchor(T3BOII.anchors.mouth);
  const cheeks = CHEEK_RAYS.map(findAnchor).filter(Boolean);
  const eyes = [];              // { bone, front: local offset of the eye's front, radius }
  for (const name of ['Eye_L', 'Eye_R']) {
    const bone = bones[name];
    if (!bone) continue;
    const center = bone.getWorldPosition(v3());
    const hit = new THREE.Raycaster(new THREE.Vector3(center.x, center.y, 5), new THREE.Vector3(0, 0, -1))
      .intersectObject(character, true).find((h) => h.object.isSkinnedMesh && !h.object.name.startsWith('Lid'));
    const front = hit ? hit.point : center.clone().add(new THREE.Vector3(0, 0, 0.075));
    eyes.push({ bone, front: bone.worldToLocal(front.clone()), radius: front.distanceTo(center) });
  }
  const tearPaths = findTearPaths();   // per eye, points down his cheek from under it, in his face bone's space
  bakeT3Bloom();
  installGlow();
  installEyeMask();
  setMouthRest();
  installSprites();

  return {
    character,
    /// Every bone back to its rest pose, before this frame's pose is worked out.
    restPose() {
      for (const [name, b] of Object.entries(bones)) { b.position.copy(rest[name].p); b.quaternion.copy(rest[name].q); }
    },

    /// This frame's pose onto his bones, lids, lips and glow. Returns how much his limbs still swing.
    pose(P) {
      const { t, amp, look } = P;
      const off = new Map();
      const add = (name, x = 0, y = 0, z = 0) => {
        const o = off.get(name) || [0, 0, 0];
        o[0] += x; o[1] += y; o[2] += z;
        off.set(name, o);
      };
      // Breathing: chest lifts and the head nods back a touch. Concentrating, he tips his head back.
      // Asleep, he breathes slow and deep and his head droops.
      add('Bone_014', -0.012 * P.breath);
      add('Bone_013', -0.018 * P.breath);
      add('Bone_012', P.headDip, 0.02 * Math.sin(t * 0.37));
      // Arms drift with the float; powered up, they lift away from his sides; asleep, they hang.
      // Glum, his arms hang in at his sides; each sob jerks them a little.
      const { drift, sad, sob, p, stretch, spinning, D, beat } = P;
      add('Bone_041', 0, 0, 0.05 + 0.035 * drift * (1 - sad) + 0.22 * p - 0.1 * sad + 0.06 * sob - amp * look.arms);
      add('Bone_036', 0, 0, -0.05 - 0.035 * drift * (1 - sad) - 0.22 * p + 0.1 * sad - 0.06 * sob + amp * look.arms);
      add('Bone_040', 0, 0, 0.08 * p);
      add('Bone_035', 0, 0, -0.08 * p);
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
      const energy = stepLimbs({ t, dt: P.dt, held: P.held, ax: P.ax, ay: P.ay });
      for (const limb of LIMBS) limb.chain.forEach((name, i) => add(name, limb.joints[i].x, 0, limb.joints[i].z));

      // Eyes glance; the lids blink, squint when happy, droop a touch in the blank stare.
      const { gaze, lid } = P;
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

      blinkEye('L', lid); blinkEye('R', lid);
      // Closing lids roll the eyes up a little and hold them steadier, as real eyes do, so the
      // cornea never sweeps out under a half-closed lid. (The lids also wrap the eye; see installEyeMask.)
      const tuck = smooth(0.3, 1, lid), steady = 1 - smooth(0.15, 0.6, lid) * 0.75;
      for (const name of ['Eye_L', 'Eye_R']) {
        if (bones[name]) delta(name, (-gaze.y * 0.15 * (1 - tuck) - EYE_ROLL * tuck) * steady, gaze.x * 0.2 * (1 - tuck) * steady, 0);
      }
      setShape('Smile', P.face.smile);
      setShape('Mouth_Open', P.face.open);
      glow.uPucker.value = P.face.pucker;
      glow.uSmirk.value = P.face.smirk;
      glow.uFrown.value = P.face.frown;

      glow.uPsy.value = P.glow.psy;
      glow.uPsyFlare.value = P.glow.flare;
      glow.uTime.value = t;
      glow.uEyes.value = P.glow.eyes;
      glow.uMouthGlow.value = P.glow.mouth;
      glow.uBlush.value = P.glow.blush;
      return energy;
    },

    /// After the rig has moved: the glow shader's anchors and the light sprites.
    light(P) {
      updateGlowAnchors();
      const { t, lid, swell } = P;
      const eyeGlow = P.eyeLight * (1 - lid * 0.9);
      eyes.forEach((eye, i) => {
        // The bloom only lands on bare eye (stencil), so lids and skin always cover it.
        const pos = eye.bone.localToWorld(tmpB.copy(eye.front));
        const open = 1 - 0.5 * lid;
        // The stencil already keeps the fill off his lids, so it stays solid however far they close.
        showSprite(sprites.eyes[i], pos, eye.radius * 4.8 * swell, P.eyeLight * (0.94 + 0.06 * Math.sin(t * 9 + i)));
        showSprite(sprites.eyeHalos[i], pos, eye.radius * 6 * swell, eyeGlow * open * 0.45);
      });
      const mouthGlow = P.mouthLight * (1 - P.burst);
      if (mouth) {
        const m = anchorWorld(mouth, tmpA);
        // Energy: sparks that skitter around his mouth, more of them the more powered he is.
        const active = P.reduced ? 0 : Math.round(mouthGlow * sprites.sparks.length);
        sprites.sparks.forEach((spark, i) => {
          if (i >= active) { spark.visible = false; return; }
          const cycle = 0.55 + 0.15 * (i % 3);
          const u = ((t + i * 0.37) % cycle) / cycle;
          const a = i * 2.4 + Math.floor((t + i * 0.37) / cycle) * 1.7;
          const r = (0.1 + 0.12 * u) * swell;
          const pos = tmpB.set(m.x + Math.cos(a) * r, m.y + Math.sin(a) * r * 0.6, m.z + 0.04);
          showSprite(spark, pos, 0.035 * (1 - u) + 0.012, (1 - u) * mouthGlow * 0.9 * clamp01(P.open * 4));
        });
      }
    },

    /// The middle of the T3 on his forehead, or of his mouth, in world units (null if not found).
    anchor(name, out) {
      const a = name === 'forehead' ? forehead : name === 'mouth' ? mouth : null;
      return a ? anchorWorld(a, out) : null;
    },

    /// Where the drool hangs from: the corner of his mouth (his left, screen right).
    droolCorner(swell) {
      return mouth ? anchorWorld(mouth, v3()).add(v3().set(0.1 * swell, -0.012, 0.02)) : null;
    },

    /// Tear tracks, one per eye: `tear(i)` gives path `i` in world units now and how to carry it
    /// with his head as it moves.
    tears: tearPaths.length,
    tear(i, rig) {
      const head = bones[HEAD_BONE];
      const path = tearPaths[i % tearPaths.length];
      if (!head || !path) return null;
      rig.updateMatrixWorld(true);
      const from = head.matrixWorld.clone().invert();
      const carry = new THREE.Matrix4();
      return { points: path.map((p) => head.localToWorld(p.clone())), carry: () => carry.multiplyMatrices(head.matrixWorld, from) };
    },

    // For checks and debugging.
    internals: { bones, morphs, glow, sprites, lidBias, get tearPaths() { return tearPaths; } },
  };
}
