// T3boii's 3D effects: everything that pops out of him lives in his scene, lit by the same
// studio lights and drawn with the same glossy, slightly squishy materials as he is.
//
//   hearts    puffy extruded hearts that pop out where he is stroked and bob upward
//   zs        chunky bevelled Zs that rise and rock while he sleeps
//   drool     a glassy strand from the corner of his mouth, and the drops that fall from it
//   vortex    while he sucks an orb in: translucent spiral tubes of air streaming into his lips
//   heaven    god rays and a warm glare pouring out of his mouth at full power
//   rings     glowing tori that roll off the T3 on his forehead when an agent spawns
//   stars     a dizzy halo of little stars after he has been spun round
//   shards    dark glossy chips an orb crumbles into when its provider hits a limit
//   tears     glassy drops that well at his lower lids, run down his cheeks and drip off
//
// Positions are world units (his model metres); `pageToWorld` maps page CSS px onto a plane
// in front of him for effects that start where the mouse is.

import { tremble } from './motion.js';

const TAU = Math.PI * 2;
const clamp01 = (v) => Math.min(1, Math.max(0, v));
const smooth = (a, b, v) => { const t = clamp01((v - a) / (b - a)); return t * t * (3 - 2 * t); };
const rand = (a, b) => a + Math.random() * (b - a);


export function createEffects({ THREE, scene, pxPerUnit, pageToWorld }) {
  const unit = (px) => px / pxPerUnit();

  // ------------------------------------------------------------ shapes

  function heartShape() {
    const s = new THREE.Shape();
    s.moveTo(0, 0.28);
    s.bezierCurveTo(0, 0.52, -0.42, 0.6, -0.5, 0.24);
    s.bezierCurveTo(-0.57, -0.08, -0.22, -0.33, 0, -0.58);
    s.bezierCurveTo(0.22, -0.33, 0.57, -0.08, 0.5, 0.24);
    s.bezierCurveTo(0.42, 0.6, 0, 0.52, 0, 0.28);
    return s;
  }

  function zShape() {
    const p = [[-0.5, 0.5], [0.5, 0.5], [0.5, 0.3], [-0.12, -0.3], [0.5, -0.3], [0.5, -0.5], [-0.5, -0.5], [-0.5, -0.3], [0.12, 0.3], [-0.5, 0.3]];
    const s = new THREE.Shape();
    p.forEach(([x, y], i) => (i ? s.lineTo(x, y) : s.moveTo(x, y)));
    return s;
  }

  function starShape() {
    const s = new THREE.Shape();
    for (let i = 0; i < 10; i += 1) {
      const r = i % 2 ? 0.22 : 0.5, a = Math.PI / 2 + i * Math.PI / 5;
      i ? s.lineTo(Math.cos(a) * r, Math.sin(a) * r) : s.moveTo(Math.cos(a) * r, Math.sin(a) * r);
    }
    return s;
  }

  const puffy = (shape, depth, bevel) => {
    const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: true, bevelThickness: bevel, bevelSize: bevel * 0.85, bevelSegments: 6, curveSegments: 18 });
    g.center();
    g.computeVertexNormals();
    return g;
  };

  const geometry = {
    heart: puffy(heartShape(), 0.16, 0.13),
    z: puffy(zShape(), 0.14, 0.07),
    star: puffy(starShape(), 0.12, 0.06),
    drop: new THREE.SphereGeometry(0.5, 20, 16),
    // Chips of a crumbling orb: faceted, so each catches the light on a few flat sides.
    shards: [new THREE.IcosahedronGeometry(0.5, 0), new THREE.TetrahedronGeometry(0.62, 0), new THREE.OctahedronGeometry(0.52, 0)],
  };

  const gloss = (color, emissive, extra = {}) => new THREE.MeshPhysicalMaterial({
    color, emissive, emissiveIntensity: 0.5, roughness: 0.3, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.12,
    sheen: 0.6, sheenColor: new THREE.Color(0xffffff), sheenRoughness: 0.5, transparent: true, ...extra,
  });
  const materials = {
    heart: gloss(0xff4f8e, 0x6a0b30),
    z: gloss(0xd9cbff, 0x3a2878, { emissiveIntensity: 0.35 }),
    star: gloss(0xffd45e, 0x8a5200, { emissiveIntensity: 0.6 }),
    drop: gloss(0xd8eeff, 0x26405e, { roughness: 0.06, clearcoatRoughness: 0.02, opacity: 0.8, emissiveIntensity: 0.25, sheen: 0 }),
    // Near-black glass with a faint violet glow in it, and a few chips still lit like embers.
    shard: gloss(0x231b31, 0x1c0d3a, { emissiveIntensity: 0.7, roughness: 0.2, clearcoatRoughness: 0.08, flatShading: true, sheen: 0.25 }),
    ember: gloss(0xd7c2ff, 0x8a55ff, { emissiveIntensity: 1.7, roughness: 0.3, flatShading: true, sheen: 0 }),
    // A tear: clearer and brighter than drool, it has to read on his pale skin.
    tear: gloss(0xeaf6ff, 0x3a6aa0, { roughness: 0.03, clearcoatRoughness: 0.02, opacity: 0.88, emissiveIntensity: 0.32, sheen: 0, depthWrite: false }),
  };

  // -------------------------------------------------------- floaters

  const floaters = [];
  const group = new THREE.Group();
  scene.add(group);

  function spawn(kind, at, extra = {}) {
    const shape = kind === 'drip' ? geometry.drop : kind === 'shard' ? geometry.shards[Math.floor(Math.random() * geometry.shards.length)] : geometry[kind];
    const material = (kind === 'drip' ? (extra.tear ? materials.tear : materials.drop) : kind === 'shard' ? (extra.ember ? materials.ember : materials.shard) : materials[kind]).clone();
    const mesh = new THREE.Mesh(shape, material);
    mesh.renderOrder = 5;
    group.add(mesh);
    const f = { kind, mesh, at: at.clone(), t0: null, delay: extra.delay ?? 0, life: extra.life ?? { heart: 1.6, z: 3, drip: 0.9, star: 0, shard: 1.5 }[kind], sway: rand(-1, 1), size: extra.size ?? 1, spin: rand(-1, 1), ...extra };
    if (f.delay > 0) mesh.visible = false;
    floaters.push(f);
    return f;
  }

  function stepFloaters(t) {
    for (let i = floaters.length - 1; i >= 0; i -= 1) {
      const f = floaters[i];
      if (f.kind === 'star') continue;
      if (f.t0 === null) f.t0 = t + f.delay;
      if (t < f.t0) continue;
      const u = (t - f.t0) / f.life;
      if (u >= 1) { group.remove(f.mesh); f.mesh.material.dispose(); floaters.splice(i, 1); continue; }
      const m = f.mesh;
      let opacity;
      if (f.kind === 'heart') {
        // Pops out where he was touched, swelling past full size, then bobs up rocking in 3D.
        const px = unit(1);
        m.position.set(f.at.x + f.sway * 34 * px * u + Math.sin(u * 9 + f.sway * 3) * 7 * px, f.at.y + 120 * px * (1 - Math.pow(1 - u, 2)), f.at.z + 0.1 * u);
        const pop = u < 0.16 ? 0.25 + 1.0 * smooth(0, 0.16, u) : 1.25 - 0.3 * (u - 0.16);
        m.scale.setScalar(unit(32) * f.size * pop);
        m.rotation.set(0.25 * Math.sin(u * 6 + f.sway), 0.9 * Math.sin(u * 5 + f.spin * 2), Math.sin(u * 7 + f.sway) * 0.2);
        opacity = Math.min(1, u * 8) * (1 - smooth(0.62, 1, u));
      } else if (f.kind === 'z') {
        // Rises up and away from his head, growing and rocking, turning to show its bevel.
        const px = unit(1);
        m.position.set(f.at.x + 60 * px * u + Math.sin(u * 5 + f.sway) * 10 * px, f.at.y + 130 * px * u, f.at.z);
        m.scale.setScalar(unit(46) * f.size * (0.45 + 0.75 * u));
        m.rotation.set(0.2 * Math.sin(u * 3), 0.7 * Math.sin(u * 4 + f.sway), -0.22 + Math.sin(u * 4 + f.sway) * 0.18);
        opacity = smooth(0, 0.15, u) * (1 - smooth(0.6, 1, u));
      } else if (f.kind === 'shard') {
        // A chip breaks off the orb, flies out a little, tumbles and falls, shrinking away; an ember
        // chip floats up instead, glowing out.
        const age = t - f.t0;
        const fall = f.ember ? -0.35 : 1.25;
        m.position.set(f.at.x + f.v.x * age, f.at.y + f.v.y * age - 0.5 * fall * age * age, f.at.z + f.v.z * age);
        m.scale.setScalar(f.scale * (1 - 0.65 * smooth(0.35, 1, u)));
        m.rotation.set(f.spin * 7 * age, f.sway * 5 * age, (f.spin + f.sway) * 3 * age);
        opacity = smooth(0, 0.06, u) * (1 - smooth(0.55, 1, u));
      } else {
        // A drop falls away under gravity, stretching as it goes.
        const age = t - f.t0;
        m.position.set(f.at.x, f.at.y - 0.5 * 9 * age * age, f.at.z);
        const s = unit(f.tear ? 12 : 11);
        m.scale.set(s * (1 - 0.15 * u), s * (1.25 + 0.6 * u), s);
        opacity = (f.tear ? 0.88 : 0.8) * (1 - smooth(0.45, 1, u));
      }
      m.material.opacity = opacity;
      m.visible = opacity > 0.01;
    }
  }

  // ------------------------------------------------------------ drool

  // A strand hanging from the corner of his mouth: a tapered glassy cylinder, a bead at its tip.
  const drool = new THREE.Group();
  const strandGeometry = new THREE.CylinderGeometry(0.5, 0.32, 1, 14, 6, true);
  strandGeometry.translate(0, -0.5, 0);
  const strand = new THREE.Mesh(strandGeometry, materials.drop.clone());
  const bead = new THREE.Mesh(geometry.drop, materials.drop.clone());
  drool.add(strand, bead);
  drool.visible = false;
  drool.renderOrder = 6;
  scene.add(drool);

  function setDrool(corner, lengthPx, t) {
    drool.visible = !!corner && lengthPx > 0.5;
    if (!drool.visible) return;
    const len = unit(lengthPx), w = unit(6);
    drool.position.copy(corner);
    strand.scale.set(w, len, w);
    bead.position.set(0, -len - unit(3), 0);
    bead.scale.set(unit(11), unit(13), unit(11));
    drool.rotation.z = 0.07 * Math.sin(t * 0.9);
  }

  // ----------------------------------------------------------- vortex

  // Spiral tubes of air, soft and fat far out, thinning as they converge into his lips. A shader runs
  // pale streaks down each tube toward his mouth; each tube is densest down its middle and fades to
  // nothing at its edges, like a twist of mist, not a line.
  const VORTEX_TUBES = 12;
  const vortex = new THREE.Group();
  vortex.visible = false;
  scene.add(vortex);
  const vortexUniforms = { uTime: { value: 0 }, uStrength: { value: 0 } };
  const vortexMaterial = new THREE.ShaderMaterial({
    uniforms: vortexUniforms,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, toneMapped: false,
    vertexShader: `
      attribute float aPhase;
      varying float vU; varying float vPhase; varying float vRim;
      void main() {
        vU = uv.x; vPhase = aPhase;
        vec4 mv = modelViewMatrix * vec4(position, 1.0);
        vec3 n = normalize(normalMatrix * normal);
        vRim = 1.0 - abs(dot(n, normalize(-mv.xyz)));
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: `
      uniform float uTime, uStrength;
      varying float vU; varying float vPhase; varying float vRim;
      void main() {
        float f = fract(vU * 2.2 - uTime * 1.6 + vPhase);
        float streak = smoothstep(0.0, 0.18, f) * (1.0 - smoothstep(0.32, 0.78, f));
        float ends = smoothstep(0.0, 0.18, vU) * (1.0 - smoothstep(0.86, 1.0, vU));
        float body = 0.18 + 0.82 * streak;
        float core = pow(1.0 - vRim, 1.6);
        float a = body * ends * uStrength * core * (0.35 + 0.65 * vU) * 0.55;
        vec3 c = mix(vec3(0.70, 0.62, 1.0), vec3(1.0, 0.98, 1.0), streak * vU);
        gl_FragColor = vec4(c * a, a);
      }`,
  });

  function buildVortex() {
    for (let i = 0; i < VORTEX_TUBES; i += 1) {
      const a0 = TAU * i / VORTEX_TUBES + rand(-0.2, 0.2);
      const turns = rand(0.45, 0.7);
      const r0 = rand(0.3, 0.44), z0 = rand(0.14, 0.26);
      const points = [];
      for (let s = 0; s <= 40; s += 1) {
        const u = s / 40;
        const a = a0 + turns * TAU * u;
        const r = r0 * Math.pow(1 - u, 1.25) + 0.015;
        points.push(new THREE.Vector3(Math.cos(a) * r, Math.sin(a) * r * 0.82, z0 * Math.pow(1 - u, 1.7) + 0.01));
      }
      const curve = new THREE.CatmullRomCurve3(points);
      const radius = rand(0.03, 0.05);
      const tube = new THREE.TubeGeometry(curve, 64, radius, 8, false);
      // Taper: thick far out, a thread where it enters his mouth.
      const pos = tube.attributes.position, uv = tube.attributes.uv, c = new THREE.Vector3(), p = new THREE.Vector3();
      for (let k = 0; k < pos.count; k += 1) {
        const u = uv.getX(k);
        curve.getPointAt(Math.min(1, u), c);
        p.fromBufferAttribute(pos, k).sub(c).multiplyScalar(0.15 + 0.85 * (1 - u) * (1 - u) + 0.25 * Math.sin(Math.PI * u));
        pos.setXYZ(k, c.x + p.x, c.y + p.y, c.z + p.z);
      }
      tube.computeVertexNormals();
      tube.setAttribute('aPhase', new THREE.Float32BufferAttribute(new Array(pos.count).fill(Math.random()), 1));
      vortex.add(new THREE.Mesh(tube, vortexMaterial));
    }
  }
  buildVortex();

  /// `mouth` is his mouth in world units, `quaternion` his facing, `strength` 0 .. 1.
  function setVortex(mouth, quaternion, strength, t) {
    vortexUniforms.uStrength.value = strength;
    vortexUniforms.uTime.value = t;
    vortex.visible = strength > 0.01 && !!mouth;
    if (!vortex.visible) return;
    vortex.position.copy(mouth);
    vortex.quaternion.copy(quaternion);
    vortex.rotateZ(-t * 1.9);
    vortex.scale.setScalar(0.85 + 0.15 * strength);
  }

  // ------------------------------------------------------------ heaven light

  // At full power, light pours out of his open mouth: a fan of soft god rays, each a crossed pair
  // of long tapered planes so it reads as a shaft from any angle, hottest at his lips and fading
  // to nothing far out, with motes drifting along them. A warm glare sits over the opening.
  const RAYS = 16;
  const radiance = new THREE.Group();
  radiance.visible = false;
  scene.add(radiance);
  const rayUniforms = { uTime: { value: 0 }, uStrength: { value: 0 } };
  const rayMaterial = new THREE.ShaderMaterial({
    uniforms: rayUniforms,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, toneMapped: false,
    vertexShader: `
      attribute float aPhase;
      varying vec2 vUv; varying float vPhase;
      void main() { vUv = uv; vPhase = aPhase; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `
      uniform float uTime, uStrength;
      varying vec2 vUv; varying float vPhase;
      void main() {
        float along = vUv.y;
        float across = 1.0 - smoothstep(0.0, 1.0, abs(vUv.x - 0.5) * 2.0);
        float fall = pow(1.0 - along, 1.6) * smoothstep(0.0, 0.06, along);
        float shimmer = 0.72 + 0.28 * sin(along * 14.0 - uTime * 3.2 + vPhase * 6.28);
        float breathe = 0.8 + 0.2 * sin(uTime * 1.3 + vPhase * 9.0);
        float a = uStrength * across * across * fall * shimmer * breathe * 0.42;
        vec3 c = mix(vec3(1.0, 0.86, 0.58), vec3(1.0, 0.99, 0.95), 1.0 - along);
        gl_FragColor = vec4(c * a, a);
      }`,
  });
  const rays = [];
  function buildRadiance() {
    for (let i = 0; i < RAYS; i += 1) {
      // Fanned out all round across his face, leaning toward the viewer (+z) so they clear it.
      const a = TAU * i / RAYS + rand(-0.15, 0.15);
      const dir = new THREE.Vector3(Math.cos(a), Math.sin(a) * 0.75 - 0.1, rand(0.45, 0.7)).normalize();
      const length = rand(0.9, 1.7), width = rand(0.08, 0.16);
      const geometry = new THREE.PlaneGeometry(1, 1, 1, 8);
      // Tapered: a sliver at his lips, widening out along the shaft.
      const pos = geometry.attributes.position;
      for (let k = 0; k < pos.count; k += 1) {
        const v = pos.getY(k) + 0.5;
        pos.setXYZ(k, pos.getX(k) * width * (0.25 + 1.6 * v), v * length, 0);
      }
      geometry.setAttribute('aPhase', new THREE.Float32BufferAttribute(new Array(pos.count).fill(Math.random()), 1));
      const ray = new THREE.Group();
      for (let j = 0; j < 2; j += 1) {
        const plane = new THREE.Mesh(geometry, rayMaterial);
        plane.rotation.y = j * Math.PI / 2;
        plane.renderOrder = 9;
        ray.add(plane);
      }
      ray.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);
      ray.userData = { dir, phase: Math.random(), length };
      radiance.add(ray);
      rays.push(ray);
    }
  }
  buildRadiance();
  const glareTexture = (() => {
    const size = 128, c = document.createElement('canvas');
    c.width = c.height = size;
    const g = c.getContext('2d');
    const grad = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
    grad.addColorStop(0, 'rgba(255,255,255,1)');
    grad.addColorStop(0.18, 'rgba(255,246,222,0.8)');
    grad.addColorStop(0.45, 'rgba(255,226,170,0.25)');
    grad.addColorStop(1, 'rgba(255,214,150,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, size, size);
    const texture = new THREE.CanvasTexture(c);
    texture.colorSpace = THREE.SRGBColorSpace;
    return texture;
  })();
  const glare = new THREE.Sprite(new THREE.SpriteMaterial({ map: glareTexture, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, toneMapped: false, opacity: 0 }));
  glare.renderOrder = 9;
  radiance.add(glare);

  /// `mouth` is his mouth in world units, `quaternion` his facing, `strength` 0 .. 1, `open` how wide
  /// his mouth is (the shafts narrow as it closes).
  function setRadiance(mouth, quaternion, strength, open, t, reduced) {
    rayUniforms.uStrength.value = strength * (0.35 + 0.65 * open);
    rayUniforms.uTime.value = reduced ? 0 : t;
    radiance.visible = strength > 0.01 && !!mouth;
    if (!radiance.visible) return;
    radiance.position.copy(mouth);
    radiance.quaternion.copy(quaternion);
    // From the opening between his lips, just below the mouth spot.
    radiance.translateY(-0.045);
    radiance.translateZ(0.03);
    rays.forEach((ray, i) => {
      // Each shaft slowly lengthens and shrinks, so the light seems to well up rather than sit still.
      ray.scale.set(1, 0.55 + 0.45 * strength + (reduced ? 0 : 0.08 * Math.sin(t * 1.1 + i)), 1);
    });
    const g = 0.36 + 0.1 * open + (reduced ? 0 : 0.03 * Math.sin(t * 2.3));
    glare.scale.set(g * 1.5, g * 0.85, 1);   // wide, like the mouth it pours from
    glare.material.opacity = strength * (0.55 + 0.35 * open);
  }

  // ------------------------------------------------------------ rings

  const ringGeometry = new THREE.TorusGeometry(1, 0.045, 14, 72);
  const rings = [];
  function ring(at, delay = 0) {
    const material = new THREE.MeshPhysicalMaterial({ color: 0xd6c4ff, emissive: 0x9f7bff, emissiveIntensity: 1.4, roughness: 0.25, clearcoat: 1, transparent: true, opacity: 0, depthWrite: false });
    const mesh = new THREE.Mesh(ringGeometry, material);
    mesh.position.copy(at);
    mesh.rotation.set(rand(0.3, 0.5), rand(-0.3, 0.3), 0);
    mesh.renderOrder = 7;
    scene.add(mesh);
    rings.push({ mesh, t0: null, delay, at: at.clone() });
  }
  function stepRings(t) {
    for (let i = rings.length - 1; i >= 0; i -= 1) {
      const r = rings[i];
      if (r.t0 === null) r.t0 = t + r.delay;
      const u = (t - r.t0) / 1.1;
      if (u >= 1) { scene.remove(r.mesh); r.mesh.material.dispose(); rings.splice(i, 1); continue; }
      const e = 1 - Math.pow(1 - clamp01(u), 3);
      r.mesh.scale.setScalar(0.05 + 0.55 * e);
      r.mesh.material.opacity = u < 0 ? 0 : 0.95 * (1 - smooth(0.25, 1, u));
      r.mesh.position.set(r.at.x, r.at.y + 0.05 * e, r.at.z + 0.08 * e);
    }
  }

  // ------------------------------------------------------------ shards

  /// An orb crumbling away: `count` chips break off a ball of `radius` (world units) round `at`
  /// over `duration` s from `delay` s on, mostly from the side facing the viewer. `size` scales them.
  function crumble(at, radius, { delay = 0, duration = 1.4, count = 34, size = 1 } = {}) {
    for (let i = 0; i < count; i += 1) {
      const dir = new THREE.Vector3(rand(-1, 1), rand(-1, 1), rand(-0.3, 1)).normalize();
      const ember = Math.random() < 0.22;
      spawn('shard', at.clone().addScaledVector(dir, radius * rand(0.45, 1)), {
        delay: delay + duration * Math.pow(Math.random(), 0.85),
        life: ember ? rand(1.1, 1.7) : rand(1.0, 1.6),
        ember,
        scale: unit(ember ? rand(3, 5.5) : rand(5.5, 12)) * size,
        v: dir.clone().multiplyScalar(rand(0.08, 0.3)).add(new THREE.Vector3(0, rand(0.02, ember ? 0.3 : 0.14), 0)),
      });
    }
  }

  // ------------------------------------------------------------ tears

  // A tear wells up as a bead at his lower lid, then runs down his cheek along `path` (world
  // points down his skin, as it was when the tear began) leaving a wet glassy streak, and drips
  // off the end. `follow()` gives the matrix carrying that moment's pose to this frame's, so the
  // tear rides his face as his head bobs and droops. Still (reduced motion), it only wells and fades.
  const tears = [];
  const WELL_S = 0.75, RUN_S = 1.15, STREAK_FADE_S = 1.4, TEAR_TUBE = 28, TEAR_RADIAL = 6;
  function tear(path, follow, { size = 1, still = false } = {}) {
    const curve = new THREE.CatmullRomCurve3(path);
    const holder = new THREE.Group();
    holder.matrixAutoUpdate = false;
    const drop = new THREE.Mesh(geometry.drop, materials.tear.clone());
    const streak = new THREE.Mesh(new THREE.TubeGeometry(curve, TEAR_TUBE, unit(2.6) * size, TEAR_RADIAL, false), materials.tear.clone());
    streak.geometry.setDrawRange(0, 0);
    drop.renderOrder = 7; streak.renderOrder = 6;
    holder.add(streak, drop);
    scene.add(holder);
    tears.push({ curve, follow, holder, drop, streak, size, still, t0: null, fell: false });
  }

  const tearTangent = new THREE.Vector3(), tearDown = new THREE.Vector3(0, -1, 0);
  function stepTears(t) {
    for (let i = tears.length - 1; i >= 0; i -= 1) {
      const tr = tears[i];
      if (tr.t0 === null) tr.t0 = t;
      const age = t - tr.t0;
      tr.holder.matrix.copy(tr.follow());
      tr.holder.matrixWorldNeedsUpdate = true;
      const bead = unit(14) * tr.size;
      if (tr.still) {
        // Reduced motion: a bead wells at his lid and fades, no running.
        const u = age / 3;
        if (u >= 1) { disposeTear(tr); tears.splice(i, 1); continue; }
        tr.drop.position.copy(tr.curve.getPointAt(0));
        tr.drop.scale.setScalar(bead * smooth(0, 0.25, u));
        tr.drop.material.opacity = 0.88 * (1 - smooth(0.7, 1, u));
        continue;
      }
      if (age < WELL_S) {
        // Welling: the bead swells at his lid, trembling as it fills.
        const w = smooth(0, WELL_S, age);
        tr.drop.position.copy(tr.curve.getPointAt(0));
        tr.drop.scale.set(bead * w * (1 + 0.06 * tremble(age, 31)), bead * w * (1.05 + 0.1 * w), bead * w);
        tr.drop.quaternion.identity();
      } else if (age < WELL_S + RUN_S) {
        // Running: it lets go and slides down his cheek, gathering speed, stretched along the way.
        const u = Math.pow((age - WELL_S) / RUN_S, 1.55);
        tr.drop.position.copy(tr.curve.getPointAt(u));
        tr.curve.getTangentAt(Math.min(0.999, u), tearTangent);
        tr.drop.quaternion.setFromUnitVectors(tearDown, tearTangent);
        tr.drop.scale.set(bead * 0.92, bead * (1.15 + 0.35 * Math.sin(Math.PI * u)), bead * 0.92);
        tr.streak.geometry.setDrawRange(0, TEAR_RADIAL * 6 * Math.floor(u * TEAR_TUBE));
      } else if (!tr.fell) {
        // Off the end of his cheek it drips, falling free in the world.
        tr.fell = true;
        tr.drop.visible = false;
        tr.streak.geometry.setDrawRange(0, Infinity);
        tr.holder.updateMatrixWorld(true);
        const end = tr.curve.getPointAt(1).applyMatrix4(tr.holder.matrixWorld);
        spawn('drip', end, { tear: true });
      }
      // The wet streak dries off after the drop has passed.
      const dry = smooth(WELL_S + RUN_S * 0.6, WELL_S + RUN_S + STREAK_FADE_S, age);
      tr.streak.material.opacity = 0.62 * (1 - dry);
      if (dry >= 1) { disposeTear(tr); tears.splice(i, 1); }
    }
  }

  function disposeTear(tr) {
    scene.remove(tr.holder);
    tr.streak.geometry.dispose();
    tr.streak.material.dispose();
    tr.drop.material.dispose();
  }

  // ------------------------------------------------------------ stars

  const stars = Array.from({ length: 4 }, () => {
    const f = spawn('star', new THREE.Vector3());
    f.mesh.visible = false;
    return f;
  });
  let dizzy = null;   // { t0, duration }
  function dizzyStars(t, duration) { dizzy = { t0: t, duration }; }
  function stepStars(t, head) {
    const on = dizzy && head && t - dizzy.t0 < dizzy.duration;
    if (!on) { dizzy = on ? dizzy : null; stars.forEach((s) => { s.mesh.visible = false; }); return; }
    const u = (t - dizzy.t0) / dizzy.duration;
    const fade = smooth(0, 0.08, u) * (1 - smooth(0.8, 1, u));
    stars.forEach((s, i) => {
      const a = t * 4.2 + i * TAU / stars.length;
      s.mesh.visible = true;
      s.mesh.position.set(head.x + Math.cos(a) * 0.42, head.y - 0.02 + Math.sin(a * 2) * 0.03, head.z + Math.sin(a) * 0.32);
      s.mesh.scale.setScalar(unit(44) * (0.85 + 0.2 * Math.sin(a)));
      s.mesh.rotation.set(0.3, a * 1.5, 0.2 * Math.sin(a));
      s.mesh.material.opacity = fade;
    });
  }

  return {
    heart(page, size = 1) { const at = pageToWorld(page.x, page.y); if (at) spawn('heart', at, { size }); },
    z(at, size) { spawn('z', at, { size }); },
    drip(at) { spawn('drip', at); },
    crumble,
    tear,
    ring,
    dizzyStars,
    setDrool,
    setVortex,
    setRadiance,
    step(t, dt, { head }) {
      stepFloaters(t);
      stepTears(t);
      stepRings(t);
      stepStars(t, head);
    },
    get busy() { return floaters.some((f) => f.kind !== 'star') || tears.length > 0 || rings.length > 0 || !!dizzy || vortex.visible || radiance.visible; },
    get count() { return floaters.filter((f) => f.kind !== 'star').length; },
    get tears() { return tears.length; },
  };
}
