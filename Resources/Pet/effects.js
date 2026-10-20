// T3boii's 3D effects: everything that pops out of him lives in his scene, lit by the same
// studio lights and drawn with the same glossy, slightly squishy materials as he is.
//
//   hearts    puffy extruded hearts that pop out where he is stroked and bob upward
//   zs        chunky bevelled Zs that rise and rock while he sleeps
//   drool     a glassy strand from the corner of his mouth, and the drops that fall from it
//   vortex    while he sucks an orb in: translucent spiral tubes of air streaming into his lips
//   heaven    god rays and a warm glare pouring out of his mouth at full power
//   ripples   rings of psychic light that lift off the T3 on his forehead when an agent spawns
//   stars     a dizzy halo of little stars after he has been spun round
//   shards    dark glossy chips an orb crumbles into when its provider hits a limit
//   tears     glassy drops that well at his lower lids, run down his cheeks and drip off
//   glints    a message: a bright bead with a tail of motes that comes round from behind him to an
//             orb, and the faint ring it leaves as the orb gulps it
//   queue     messages queued behind a thread's turn, small glass seeds circling its orb
//   pr rings  a thin lit band round an orb whose thread has a pull request: silver with a light
//             running round it while its checks run, green when they pass, red and broken when not
//   seeds     scheduled tasks as glossy teardrops on a small halo over his head, ripening as their
//             run nears and dropping into his T3 when it fires
//   shells    the two halves of a snoozed orb's egg, falling away tumbling as it hatches
//   beams     a thin psychic beam from his T3 to an orb he is mending
//   asks      chunky amber glass strokes that grow up out of a waiting orb, making it the dot of a
//             "?" (a "!" bar for an approval); they bob with their dot, sway and glow, and pull
//             back down into it when the question is answered
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
    ask: gloss(0xffc65a, 0xffb340, { emissiveIntensity: 0.35, roughness: 0.18, clearcoatRoughness: 0.06, sheen: 0.3 }),
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

  // ---------------------------------------------------------- ripples

  // Each ripple is a ring of light drawn on a plane parallel to his forehead and lifting off it, so
  // however wide it grows it never cuts into his head. It leaves the T3 as a crisp bright crest and
  // spreads, slowing, into a soft nebulous band: out of round and wavering, its light gathered into
  // drifting wisps, a faint violet wake inside the crest and a rosy fringe outside it. It tints what
  // it passes over as well as lighting it, so it stays violet on his pale skin instead of bleaching
  // to white, and glows on a dark desktop.
  const RIPPLE_S = 1.3;
  const rippleGeometry = new THREE.PlaneGeometry(2, 2);
  const rippleShader = {
    transparent: true, depthWrite: false, premultipliedAlpha: true, side: THREE.DoubleSide, toneMapped: false,
    vertexShader: `
      varying vec2 vPos;
      void main() { vPos = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `
      uniform float uTime, uRadius, uWidth, uAlpha, uHot, uSeed;
      varying vec2 vPos;
      void main() {
        float r = length(vPos), a = atan(vPos.y, vPos.x);
        float bend = 1.0 + 0.045 * sin(3.0 * a + uSeed + uTime * 1.3) + 0.025 * sin(5.0 * a - 2.0 * uSeed - uTime * 1.9);
        float d = (r - uRadius * bend) / uWidth;
        float crest = exp(-d * d);
        float wake = (1.0 - smoothstep(-1.5, 0.0, d)) * exp(d * 0.45) * 0.22;
        float fringe = exp(-(d - 1.3) * (d - 1.3) * 1.6) * 0.3;
        float wisps = 0.5 + 0.3 * sin(7.0 * a + 3.0 * uSeed - uTime * 1.6) + 0.2 * sin(12.0 * a - 5.0 * uSeed + uTime * 2.4);
        float k = uAlpha * (0.4 + 0.6 * wisps) * (1.0 - smoothstep(0.9, 1.0, r));
        vec3 violet = vec3(0.5, 0.32, 1.0), lilac = vec3(0.74, 0.58, 1.0), hot = vec3(0.95, 0.88, 1.0), rose = vec3(1.0, 0.5, 0.9);
        float i = crest + wake + fringe;
        vec3 c = violet * wake + mix(lilac, hot, uHot) * crest + rose * fringe;
        gl_FragColor = vec4(c * k, min(1.0, i * k * 0.62));
      }`,
  };
  // A finished ripple is kept, hidden, for the next one: disposing the last of them would free their
  // shader, and the next spawn would stall compiling it again.
  const ripples = [], spareRipples = [];
  const outward = new THREE.Vector3(0, 0, 1);

  /// A ripple leaves the T3 `delay` s from now; `strength` 0 .. 1 sets how bright and wide it goes.
  function ripple({ delay = 0, strength = 1 } = {}) {
    let mesh = spareRipples.pop();
    if (!mesh) {
      mesh = new THREE.Mesh(rippleGeometry, new THREE.ShaderMaterial({
        ...rippleShader,
        uniforms: { uTime: { value: 0 }, uRadius: { value: 0 }, uWidth: { value: 1 }, uAlpha: { value: 0 }, uHot: { value: 1 }, uSeed: { value: 0 } },
      }));
      mesh.renderOrder = 7;
      scene.add(mesh);
    }
    mesh.visible = false;
    mesh.material.uniforms.uSeed.value = rand(0, TAU);
    ripples.push({ mesh, t0: null, delay, strength, size: 0.8 + 0.2 * strength });
  }

  /// `forehead` is { at, normal }: the T3 in world units and the way his forehead faces there.
  function stepRipples(t, forehead) {
    for (let i = ripples.length - 1; i >= 0; i -= 1) {
      const r = ripples[i];
      if (r.t0 === null) r.t0 = t + r.delay;
      const u = (t - r.t0) / RIPPLE_S;
      if (u >= 1 || !forehead) { r.mesh.visible = false; spareRipples.push(r.mesh); ripples.splice(i, 1); continue; }
      r.mesh.visible = u >= 0;
      if (u < 0) continue;
      const e = 1 - Math.pow(1 - u, 3);
      const radius = unit(14 + 128 * e) * r.size, width = unit(2.5 + 13 * u) * r.size;
      const half = radius + width * 4;
      r.mesh.position.copy(forehead.at).addScaledVector(forehead.normal, unit(5 + 50 * e));
      r.mesh.quaternion.setFromUnitVectors(outward, forehead.normal);
      r.mesh.scale.setScalar(half);
      const uniforms = r.mesh.material.uniforms;
      uniforms.uTime.value = t;
      uniforms.uRadius.value = radius / half;
      uniforms.uWidth.value = width / half;
      uniforms.uHot.value = 1 - smooth(0, 0.45, u);
      uniforms.uAlpha.value = r.strength * smooth(0, 0.05, u) * (1 - smooth(0.3, 1, u));
    }
  }

  // ----------------------------------------------------------- glints

  const GLINT_MOTES = 8;
  const ringGeometry = new THREE.TorusGeometry(1, 0.05, 6, 40);
  const glints = [], rings = [];
  const glow = (color, extra = {}) => gloss(color, color, { emissiveIntensity: 2, roughness: 0.1, clearcoatRoughness: 0.05, sheen: 0, depthWrite: false, ...extra });

  /// A glint: `at(u)` gives its world point at u (0 .. 1) of its flight, re-read every frame so it
  /// can chase a moving orb; `size` is its bead's diameter in world units. Hidden behind him by
  /// his own body while its path runs there. `done(arrived)` runs once when it ends: `true` when it
  /// lands, `false` when `at` lost its orb first.
  function glint({ at, color, size, duration, done }) {
    const material = glow(color);
    const bead = new THREE.Mesh(geometry.drop, material);
    bead.scale.setScalar(size);
    bead.renderOrder = 6;
    const motes = Array.from({ length: GLINT_MOTES }, (_, i) => {
      const m = new THREE.Mesh(geometry.drop, glow(color, { opacity: 0.8 * (1 - i / GLINT_MOTES) }));
      m.scale.setScalar(size * 0.45 * (1 - 0.7 * i / GLINT_MOTES));
      m.renderOrder = 6;
      m.visible = false;
      return m;
    });
    scene.add(bead, ...motes);
    glints.push({ at, bead, motes, material, size, duration, done, t0: null, path: [] });
  }

  /// A faint ring spreading from an orb as it gulps a glint; `delay` staggers a second one.
  function ring(at, { color, radius, duration = 0.4, delay = 0 }) {
    const mesh = new THREE.Mesh(ringGeometry, glow(color, { emissiveIntensity: 0.9 }));
    mesh.position.copy(at);
    mesh.renderOrder = 6;
    mesh.visible = false;
    scene.add(mesh);
    rings.push({ mesh, radius, duration, t0: null, delay });
  }

  function stepGlints(t) {
    for (let i = glints.length - 1; i >= 0; i -= 1) {
      const g = glints[i];
      if (g.t0 === null) g.t0 = t;
      const u = Math.min(1, (t - g.t0) / g.duration);
      const p = g.at(u);
      if (!p || u >= 1) {
        g.done?.(!!p);
        scene.remove(g.bead, ...g.motes);
        g.material.dispose();
        for (const m of g.motes) m.material.dispose();
        glints.splice(i, 1);
        continue;
      }
      g.bead.position.copy(p);
      // The tail: earlier points of its own path, one mote per tenth of a bead width back.
      g.path.unshift(p.clone());
      g.path.length = Math.min(g.path.length, 60);
      let k = 0, gone = 0;
      for (let j = 1; j < g.path.length && k < GLINT_MOTES; j += 1) {
        gone += g.path[j].distanceTo(g.path[j - 1]);
        if (gone < (k + 1) * g.size * 0.47) continue;
        g.motes[k].position.copy(g.path[j]);
        g.motes[k].visible = true;
        k += 1;
      }
    }
    for (let i = rings.length - 1; i >= 0; i -= 1) {
      const r = rings[i];
      if (r.t0 === null) r.t0 = t + r.delay;
      const u = (t - r.t0) / r.duration;
      if (u >= 1) { scene.remove(r.mesh); r.mesh.material.dispose(); rings.splice(i, 1); continue; }
      r.mesh.visible = u >= 0;
      if (u < 0) continue;
      r.mesh.scale.setScalar(r.radius * (0.55 + 0.75 * (1 - Math.pow(1 - u, 2))));
      r.mesh.material.opacity = 0.5 * (1 - u);
    }
  }

  // --------------------------------------------------------- pr rings

  const PR_COLOR = { pending: 0xc7ccd6, pass: 0x30d158, fail: 0xff453a };
  const PR_TUBE = 0.046, PR_GAP = 20 * Math.PI / 180, PR_TILT = 1.2;
  const prGeometry = { whole: new THREE.TorusGeometry(1, PR_TUBE, 6, 56), broken: new THREE.TorusGeometry(1, PR_TUBE, 6, 56, TAU - PR_GAP), glint: new THREE.TorusGeometry(1, PR_TUBE * 1.6, 6, 10, 0.5) };
  const prRings = new Map();   // orb id -> { group, band, glint, material, shown, opacity }

  /// This frame's pull request rings (orbit.prRings()): each a band 1.2 orbs across round its orb,
  /// tilted like his rings. A changed state crossfades over half a second; one that goes fades out.
  function setPrRings(list, t, dt, reduced) {
    const live = new Set();
    for (const r of list) {
      live.add(r.id);
      let ring = prRings.get(r.id);
      if (!ring) {
        const material = gloss(PR_COLOR[r.state], PR_COLOR[r.state], { emissiveIntensity: 0.5, roughness: 0.2, opacity: 0 });
        const band = new THREE.Mesh(prGeometry.whole, material);
        const glint = new THREE.Mesh(prGeometry.glint, gloss(0xffffff, 0xffffff, { emissiveIntensity: 1.2, opacity: 0, depthWrite: false }));
        const group = new THREE.Group();
        group.add(band, glint);
        band.renderOrder = glint.renderOrder = 5;
        scene.add(group);
        ring = { group, band, glint, material, color: new THREE.Color(PR_COLOR[r.state]), opacity: 0 };
        prRings.set(r.id, ring);
      }
      ring.target = r;
    }
    for (const [id, ring] of prRings) {
      const r = ring.target, here = live.has(id);
      const ease = 1 - Math.exp(-dt / (here ? 0.5 : 0.6) * 4);
      ring.opacity += ((here ? (r.state === 'pending' ? 0.4 : 1) * (r.opacity ?? 1) : 0) - ring.opacity) * ease;
      if (!here && ring.opacity < 0.01) { scene.remove(ring.group); ring.material.dispose(); ring.glint.material.dispose(); prRings.delete(id); continue; }
      ring.color.lerp(new THREE.Color(PR_COLOR[r.state]), ease);
      ring.material.color.copy(ring.color); ring.material.emissive.copy(ring.color);
      ring.band.geometry = r.state === 'fail' ? prGeometry.broken : prGeometry.whole;
      // A failing ring glows a little on a slow fixed beat; a pending one has a light running round.
      ring.material.emissiveIntensity = r.state === 'fail' && !reduced ? 0.5 + 0.25 * (0.5 + 0.5 * Math.sin(t * TAU / 0.8)) : 0.5;
      ring.material.opacity = ring.opacity;
      ring.glint.visible = r.state === 'pending' && !reduced;
      ring.glint.rotation.z = (t * TAU / 2.4) % TAU;
      ring.glint.material.opacity = ring.opacity * 1.5;
      const at = here ? pageToWorld(r.x, r.y, r.back ? -0.62 : 0.78) : null;
      if (at) ring.group.position.copy(at);
      ring.group.scale.setScalar(unit(r.size * 0.6));
      ring.group.rotation.set(PR_TILT, 0, r.roll ?? 0);
    }
  }

  // ------------------------------------------------------------ seeds

  // A teardrop one unit long, round end down, point up.
  const seedGeometry = new THREE.LatheGeometry(
    Array.from({ length: 15 }, (_, i) => { const a = Math.PI * i / 14; return new THREE.Vector2(0.32 * Math.sin(a) * Math.pow((1 + Math.cos(a)) / 2, 0.6), -0.5 * Math.cos(a)); }),
    16);
  const seedCrack = new THREE.CylinderGeometry(0.018, 0.018, 0.62, 4);
  const SEED_LAP_S = 40, SEED_TILT = 0.2, SEED_DROP_S = 0.6, SEED_REGROW_S = 1.2;
  const seeds = new Map();   // id -> { group, mesh, crack, material, drop, regrow }

  /// This frame's seeds: [{ id, color, ripe 0 .. 1, failed }] round a halo of `radius` (world)
  /// centred at `centre`, each `size` long, turning on a fixed lap. Ripeness is glow; with reduced
  /// motion the halo stands still.
  function setSeeds(list, { centre, radius, size, t, reduced, forehead }) {
    const live = new Set(list.map((s) => s.id));
    for (const [id, s] of seeds) if (!live.has(id)) { scene.remove(s.group); s.material.dispose(); s.crack.material.dispose(); seeds.delete(id); }
    const lap = reduced ? 0 : t * TAU / SEED_LAP_S;
    list.forEach((seed, i) => {
      let s = seeds.get(seed.id);
      if (!s) {
        const material = gloss(seed.color, seed.color, { emissiveIntensity: 0.2, roughness: 0.15 });
        const mesh = new THREE.Mesh(seedGeometry, material);
        const crack = new THREE.Mesh(seedCrack, new THREE.MeshBasicMaterial({ color: 0x1a1020 }));
        crack.position.z = 0.27; crack.rotation.z = 0.5;
        const group = new THREE.Group();
        group.add(mesh, crack);
        group.renderOrder = 5;
        scene.add(group);
        s = { group, mesh, crack, material, drop: null, regrow: null };
        seeds.set(seed.id, s);
      }
      s.material.color.set(seed.color); s.material.emissive.set(seed.color);
      s.material.emissiveIntensity = 0.15 + 0.85 * seed.ripe;
      s.crack.visible = !!seed.failed;
      const a = lap + TAU * i / list.length;
      const home = centre.clone().add(new THREE.Vector3(Math.cos(a) * radius, Math.sin(a) * radius * Math.sin(SEED_TILT), Math.sin(a) * radius * Math.cos(SEED_TILT)));
      let at = home, scale = size;
      if (s.drop !== null && forehead) {
        const u = (t - s.drop) / SEED_DROP_S;
        if (u >= 1) { s.drop = null; s.regrow = t; ripple({ strength: 0.7 }); }
        else at = home.clone().lerp(forehead.at, u * u * u);
      }
      if (s.regrow !== null) {
        const u = (t - s.regrow) / SEED_REGROW_S;
        if (u >= 1) s.regrow = null; else scale = size * smooth(0, 1, u);
      }
      s.group.position.copy(at);
      s.group.scale.setScalar(Math.max(scale, 1e-4));
    });
  }

  /// A seed's task ran: it drops into his T3, which flares, and it grows back on the halo.
  function dropSeed(id, t) {
    const s = seeds.get(id);
    if (s && s.drop === null) s.drop = t;
  }

  // ------------------------------------------------------- queue seeds

  const queueSeeds = new Map();   // `${orb id}:${i}` -> mesh

  /// This frame's queue seeds (orbit.queueSeeds()): page points with a length in px, the page
  /// direction their point faces and a plane (front or behind him), drawn as small lit glass
  /// teardrops in the queue's colour.
  function setQueueSeeds(list) {
    const live = new Set();
    for (const string of list) {
      string.points.forEach((p, i) => {
        const key = `${string.id}:${i}`;
        const at = pageToWorld(p.x, p.y, p.back ? -0.62 : 0.78);
        if (!at) return;
        live.add(key);
        let mesh = queueSeeds.get(key);
        if (!mesh) {
          mesh = new THREE.Mesh(seedGeometry, gloss(string.color, string.color, { emissiveIntensity: 0.22, roughness: 0.08, clearcoatRoughness: 0.04 }));
          mesh.renderOrder = 5;
          scene.add(mesh);
          queueSeeds.set(key, mesh);
        }
        mesh.position.copy(at);
        mesh.scale.setScalar(Math.max(unit(p.size), 1e-4));
        // The teardrop's point is +y; page y runs down.
        mesh.rotation.set(0.35, 0, -p.turn - Math.PI / 2);
        mesh.material.opacity = p.opacity ?? 1;
      });
    }
    for (const [key, mesh] of queueSeeds) if (!live.has(key)) { scene.remove(mesh); mesh.material.dispose(); queueSeeds.delete(key); }
  }

  // ----------------------------------------------------------- shells

  // Half an egg shell, its pointed end up (a lathe swept half way round), one unit tall.
  const shellGeometry = new THREE.LatheGeometry(
    Array.from({ length: 13 }, (_, i) => { const a = Math.PI * i / 12; return new THREE.Vector2(Math.sin(a) * (0.42 - 0.04 * Math.cos(a)), -0.5 * Math.cos(a) * (1 - 0.08 * Math.cos(a))); }),
    18, 0, Math.PI);
  const shells = [];

  /// An egg hatching at `at`: its shell, `height` world units tall, splits and the halves fall away.
  function shell(at, height, { duration = 0.6 } = {}) {
    for (const side of [-1, 1]) {
      const mesh = new THREE.Mesh(shellGeometry, gloss(0xf2f4ff, 0x8f9bc4, { emissiveIntensity: 0.25, roughness: 0.35, side: THREE.DoubleSide, opacity: 0.92 }));
      mesh.position.copy(at);
      mesh.rotation.y = side > 0 ? Math.PI / 2 : -Math.PI / 2;
      mesh.scale.setScalar(height);
      mesh.renderOrder = 6;
      scene.add(mesh);
      shells.push({ mesh, side, at: at.clone(), height, duration, t0: null });
    }
  }

  function stepShells(t) {
    for (let i = shells.length - 1; i >= 0; i -= 1) {
      const s = shells[i];
      if (s.t0 === null) s.t0 = t;
      const u = (t - s.t0) / s.duration;
      if (u >= 1) { scene.remove(s.mesh); s.mesh.material.dispose(); shells.splice(i, 1); continue; }
      s.mesh.position.set(s.at.x + s.side * s.height * 0.35 * u, s.at.y - s.height * 0.4 * u * u, s.at.z);
      s.mesh.rotation.z = s.side * 1.4 * u;
      s.mesh.material.opacity = 0.92 * (1 - smooth(0.5, 1, u));
    }
  }

  // ------------------------------------------------------------ beams

  const beamGeometry = new THREE.CylinderGeometry(1, 1, 1, 10, 1, true);
  const beams = [];
  const up = new THREE.Vector3(0, 1, 0);

  /// A beam from the T3 on his forehead to `to` (world units), lit for `duration` s.
  function beam(to, { duration = 0.5 } = {}) {
    const mesh = new THREE.Mesh(beamGeometry, materials.ember.clone());
    mesh.material.depthWrite = false;
    mesh.renderOrder = 7;
    mesh.visible = false;
    scene.add(mesh);
    beams.push({ mesh, to: to.clone(), t0: null, duration });
  }

  function stepBeams(t, forehead) {
    for (let i = beams.length - 1; i >= 0; i -= 1) {
      const b = beams[i];
      if (b.t0 === null) b.t0 = t;
      const u = (t - b.t0) / b.duration;
      if (u >= 1 || !forehead) { scene.remove(b.mesh); b.mesh.material.dispose(); beams.splice(i, 1); continue; }
      const span = b.to.clone().sub(forehead.at);
      // It shoots out from the T3 in the first fifth, then holds and fades.
      const reach = smooth(0, 0.2, u);
      b.mesh.visible = true;
      b.mesh.position.copy(forehead.at).addScaledVector(span, reach / 2);
      b.mesh.quaternion.setFromUnitVectors(up, span.clone().normalize());
      b.mesh.scale.set(unit(3.2), span.length() * reach, unit(3.2));
      b.mesh.material.opacity = 0.85 * (1 - smooth(0.55, 1, u));
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

  // ------------------------------------------------------------- asks

  // In orb sizes, from the dot's centre (y up), each stroke drawn up from its foot, a clear gap
  // above the dot: the hook of a "?" and the bar of a "!", which widens toward its top. Each is
  // swept as a thick rounded-square section, half `width` across the stroke (foot, end) and half
  // ASK_DEPTH deep, with rounded ends.
  const ASK_TUBE = 48, ASK_RADIAL = 16, ASK_DEPTH = 0.14, ASK_Z = 0.78;
  const askStrokes = {
    '?': { curve: new THREE.CatmullRomCurve3([[0, 0.84], [0, 1], [0.06, 1.17], [0.28, 1.31], [0.4, 1.54], [0.31, 1.79], [0.05, 1.9], [-0.22, 1.83], [-0.35, 1.66]].map(([x, y]) => new THREE.Vector3(x, y, 0))), width: [0.14, 0.18] },
    '!': { curve: new THREE.LineCurve3(new THREE.Vector3(0, 0.84), new THREE.Vector3(0, 1.82)), width: [0.14, 0.24] },
  };
  const strokeWidth = (stroke, u) => stroke.width[0] + (stroke.width[1] - stroke.width[0]) * u;

  /// A stroke as rings of ASK_RADIAL points, ASK_TUBE + 1 of them from foot to end, so drawing the
  /// first n segments' triangles draws it n / ASK_TUBE of the way up.
  function strokeGeometry(stroke) {
    const position = [], index = [];
    for (let i = 0; i <= ASK_TUBE; i += 1) {
      const u = i / ASK_TUBE, at = stroke.curve.getPointAt(u), along = stroke.curve.getTangentAt(u), w = strokeWidth(stroke, u);
      for (let j = 0; j < ASK_RADIAL; j += 1) {
        const c = Math.cos(TAU * j / ASK_RADIAL), s = Math.sin(TAU * j / ASK_RADIAL);
        const across = Math.sign(c) * Math.sqrt(Math.abs(c)) * w, deep = Math.sign(s) * Math.sqrt(Math.abs(s)) * ASK_DEPTH;
        position.push(at.x - along.y * across, at.y + along.x * across, deep);
      }
    }
    for (let i = 0; i < ASK_TUBE; i += 1) {
      for (let j = 0; j < ASK_RADIAL; j += 1) {
        const a = i * ASK_RADIAL + j, b = i * ASK_RADIAL + (j + 1) % ASK_RADIAL;
        index.push(a, b, a + ASK_RADIAL, b, b + ASK_RADIAL, a + ASK_RADIAL);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(position, 3));
    g.setIndex(index);
    g.computeVertexNormals();
    return g;
  }
  const askGeometry = Object.fromEntries(Object.entries(askStrokes).map(([k, stroke]) => [k, strokeGeometry(stroke)]));
  const marks = new Map();   // orb id -> { group, tube, tip, base, kind }

  function makeMark(kind) {
    const group = new THREE.Group();
    const material = materials.ask.clone();
    const tube = new THREE.Mesh(askGeometry[kind].clone(), material);
    const tip = new THREE.Mesh(geometry.drop, material);
    const base = new THREE.Mesh(geometry.drop, material);
    const stroke = askStrokes[kind];
    base.scale.set(strokeWidth(stroke, 0) * 2, strokeWidth(stroke, 0) * 2, ASK_DEPTH * 2);
    base.position.copy(stroke.curve.getPointAt(0));
    tube.renderOrder = tip.renderOrder = base.renderOrder = 6;
    group.add(tube, tip, base);
    scene.add(group);
    return { group, tube, tip, base, kind, material };
  }

  function disposeMark(mark) {
    scene.remove(mark.group);
    mark.tube.geometry.dispose();
    mark.material.dispose();
  }

  /// This frame's question marks (orbit.asks()): each hook stands on its dot's page position, so
  /// the two line up whatever either does. A hook grows from 0.3 to 0.9 of its dot forming and
  /// pulls back in as it is answered; with Reduce Motion it fades in whole and only its glow moves.
  function setAsks(list, t, reduced) {
    const live = new Set();
    for (const ask of list) {
      if (ask.gone) continue;
      live.add(ask.id);
      let mark = marks.get(ask.id);
      if (mark && mark.kind !== ask.kind) { disposeMark(mark); mark = null; }
      if (!mark) { mark = makeMark(ask.kind); marks.set(ask.id, mark); }
      const at = pageToWorld(ask.x, ask.y, ASK_Z);
      if (!at) { mark.group.visible = false; continue; }
      mark.group.visible = true;
      mark.group.position.copy(at);
      mark.group.scale.setScalar(unit(ask.size));
      mark.group.rotation.z = reduced ? 0 : (4 * Math.PI / 180) * Math.sin(t * TAU / 3.1 + ask.seed);
      const grown = reduced ? 1 : 1 - Math.pow(1 - clamp01((ask.formed * 0.9 - 0.3) / 0.6), 2);
      const u = grown * (1 - Math.pow(ask.retract, 2));
      const segments = Math.floor(u * ASK_TUBE);
      mark.tube.geometry.setDrawRange(0, ASK_RADIAL * 6 * segments);
      mark.tip.visible = mark.base.visible = u > 0.02;
      if (u > 0.02) {
        const stroke = askStrokes[mark.kind], w = strokeWidth(stroke, segments / ASK_TUBE) * 2;
        mark.tip.position.copy(stroke.curve.getPointAt(segments / ASK_TUBE));
        mark.tip.scale.set(w, w, ASK_DEPTH * 2);
      }
      // A slow amber glow, wider once it has waited a minute; never quicker.
      const urgent = smooth(60, 70, ask.waited);
      const [lo, hi] = [0.25 - 0.05 * urgent, 0.45 + 0.15 * urgent];
      mark.material.emissiveIntensity = lo + (hi - lo) * (0.5 + 0.5 * Math.sin(t * TAU / 2 + ask.seed * 3));
      mark.material.opacity = (ask.opacity ?? 1) * (reduced ? smooth(0, 0.55, ask.formed) : 1) * (1 - ask.retract);
    }
    for (const [id, mark] of marks) if (!live.has(id)) { disposeMark(mark); marks.delete(id); }
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
    ripple,
    dizzyStars,
    setDrool,
    setVortex,
    setRadiance,
    setAsks,
    beam,
    glint,
    ring,
    shell,
    setPrRings,
    setSeeds,
    dropSeed,
    get seeds() { return [...seeds.entries()].map(([id, s]) => ({ id, glow: +s.material.emissiveIntensity.toFixed(2), cracked: s.crack.visible, dropping: s.drop !== null, at: s.group.position.clone() })); },
    get prRings() { return [...prRings.entries()].map(([id, r]) => ({ id, opacity: +r.opacity.toFixed(2), color: r.color.getHexString(), broken: r.band.geometry === prGeometry.broken, glint: r.glint.visible })); },
    setQueueSeeds,
    get glints() { return glints.length; },
    get queueSeedCount() { return queueSeeds.size; },
    get marks() { return [...marks.entries()].map(([id, m]) => ({ id, kind: m.kind, visible: m.group.visible, drawn: m.tube.geometry.drawRange.count, at: m.group.position.clone() })); },
    step(t, dt, { head, forehead }) {
      stepFloaters(t);
      stepTears(t);
      stepRipples(t, forehead);
      stepBeams(t, forehead);
      stepGlints(t);
      stepShells(t);
      stepStars(t, head);
    },
    get busy() { return floaters.some((f) => f.kind !== 'star') || tears.length > 0 || ripples.length > 0 || beams.length > 0 || glints.length > 0 || rings.length > 0 || shells.length > 0 || !!dizzy || vortex.visible || radiance.visible; },
    get count() { return floaters.filter((f) => f.kind !== 'star').length; },
    get tears() { return tears.length; },
  };
}
