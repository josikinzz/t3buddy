// Re-skins the joints where T3boii's limbs meet his ball body, once, at load.
//
// As shipped, the rig skins those joints badly:
//   - The first ~60 % of each upper arm is a mix of the upper-arm bone
//     (Bone_041 / Bone_036, ~0.4), ShoulderBlend_* (~0.35-0.47) and body bones
//     (the clavicle Bone_042 / Bone_037, and on the left even Bone_031 from the
//     side of the head). Only the forearm and hand are 100 % arm, so the upper
//     arm smears instead of swinging.
//   - The upper-arm bone and ShoulderBlend also own a square patch of the ball
//     below each shoulder whose lower edge drops from ~0.8 to 0 between
//     neighbouring vertices. Raising an arm tears that edge into a flap and
//     swinging it back stretches a sheet of skin.
//   - ShoulderBlend was meant to turn half as far as the arm; nothing drives it
//     any more, so its share now pins the arm root to the body.
//   - Each half of the ball is ~40 % weighted to its clavicle, whose head sits
//     in the middle of the ball, so turning a clavicle warps the face.
//   - The legs start at full weight right where they leave the ball.
//
// What this does, on the shared body geometry only (the lids and eyes are not
// touched, and morph targets keep working because only skinIndex/skinWeight
// change):
//   1. Welds vertices by position (glTF splits them at UV seams and between
//      the two primitives) so every copy of a point ends up with the same
//      weights and no seam can open.
//   2. Finds each limb's tube: vertices around the upper arm / thigh bone whose
//      normals point away from the bone, plus everything the limb owned
//      outright. The tube follows the limb chain 100 %, keeping its own mix of
//      upper arm / forearm / hand. The ball's skin that the arm overlaps in the
//      armpit faces the other way, so it stays with the ball.
//   3. Gives the ball around each socket a share of the limb root that falls
//      off smoothly (smootherstep) with distance from the joint, then solves a
//      harmonic blend across a band on both sides of the tube's edge, so a
//      raised arm drags a soft web of skin instead of tearing a flap. Each
//      vertex keeps its own body bone mix for the rest of its weight.
//   4. Folds ShoulderBlend and the clavicles into the upper body (Bone_011), so
//      only the limb chains move skin around a joint.
//   5. Keeps the four strongest influences and renormalises.
// Every weight it moves goes between bones whose rest transforms agree, so the
// rest pose renders exactly as before.

import * as THREE from 'three';

const BODY = 'Bone_011';
const LIMBS = [
  // root/child: the bone whose head is the joint, and the next bone down the chain.
  // inner/outer: straight-line distance from the joint (model metres) over which
  //   the ball's share of the limb root falls from 1 to 0.
  // radius/from: the tube is skin within `radius` of the bone, past `from` along it.
  // seamIn/seamOut: band (along the surface) inside/outside the tube's edge
  //   across which the share is blended.
  { root: 'Bone_041', child: 'Bone_040', inner: 0.07, outer: 0.21, radius: 0.13, from: 0.04, seamIn: 0.03, seamOut: 0.07 },
  { root: 'Bone_036', child: 'Bone_035', inner: 0.07, outer: 0.21, radius: 0.13, from: 0.04, seamIn: 0.03, seamOut: 0.07 },
  { root: 'Bone_010', child: 'Bone_009', inner: 0.05, outer: 0.16, radius: 0.10, from: 0.03, seamIn: 0.03, seamOut: 0.06 },
  { root: 'Bone_006', child: 'Bone_005', inner: 0.05, outer: 0.16, radius: 0.10, from: 0.03, seamIn: 0.03, seamOut: 0.06 },
];
const FOLD = ['ShoulderBlend_L', 'ShoulderBlend_R', 'Bone_042', 'Bone_037'];

export function smoothSkinning(character, options = {}) {
  const t0 = performance.now();
  const rest = {};
  character.traverse((o) => {
    if (o.isBone) rest[o.name] = { q: o.quaternion.toArray(), p: o.position.toArray(), wq: o.getWorldQuaternion(o.quaternion.clone()).toArray() };
  });
  character.userData.skinRest = rest;   // rest pose, for test harnesses
  if (options.disabled ?? new URLSearchParams(location.search).has('noskinfix')) return null;

  const meshes = [];
  character.traverse((o) => { if (o.isSkinnedMesh && o.name.startsWith('T3_Body_Face')) meshes.push(o); });
  const stats = [];
  const done = new Set();
  for (const mesh of meshes) {
    const weights = mesh.geometry.attributes.skinWeight;
    if (done.has(weights)) continue;
    done.add(weights);
    const siblings = meshes.filter((m) => m.geometry.attributes.skinWeight === weights);
    stats.push(reskin(siblings.map((m) => m.geometry), mesh.skeleton));
  }
  const ms = performance.now() - t0;
  console.info(`[skinning] re-skinned limb joints in ${ms.toFixed(0)} ms`, JSON.stringify(stats));
  return { ms, stats };
}

function reskin(geometries, skeleton) {
  const g = geometries[0];
  const P = g.attributes.position, Nrm = g.attributes.normal, J = g.attributes.skinIndex, W = g.attributes.skinWeight;
  const n = P.count;
  const bones = skeleton.bones;
  const boneIndex = new Map(bones.map((b, i) => [b.name, i]));
  const idx = (name) => boneIndex.get(name) ?? -1;
  // Joint positions in the mesh's bind space.
  const head = (i) => { const e = skeleton.boneInverses[i].clone().invert().elements; return [e[12], e[13], e[14]]; };

  // ---- 1. weld by position
  const nodeOf = new Int32Array(n);
  const keyToNode = new Map();
  let N = 0;
  for (let i = 0; i < n; i++) {
    const k = `${Math.round(P.getX(i) * 1e5)},${Math.round(P.getY(i) * 1e5)},${Math.round(P.getZ(i) * 1e5)}`;
    let node = keyToNode.get(k);
    if (node === undefined) { node = N++; keyToNode.set(k, node); }
    nodeOf[i] = node;
  }
  const pos = new Float32Array(N * 3), nrm = new Float32Array(N * 3);
  const weights = Array.from({ length: N }, () => new Map());
  for (let i = 0; i < n; i++) {
    const a = nodeOf[i];
    pos[a * 3] = P.getX(i); pos[a * 3 + 1] = P.getY(i); pos[a * 3 + 2] = P.getZ(i);
    if (Nrm) { nrm[a * 3] += Nrm.getX(i); nrm[a * 3 + 1] += Nrm.getY(i); nrm[a * 3 + 2] += Nrm.getZ(i); }
    const m = weights[a];
    for (let k = 0; k < 4; k++) {
      const w = W.getComponent(i, k);
      if (w > 0) add(m, J.getComponent(i, k), w);
    }
  }
  for (let a = 0; a < N; a++) {
    normalize(weights[a]);
    const l = Math.hypot(nrm[a * 3], nrm[a * 3 + 1], nrm[a * 3 + 2]) || 1;
    nrm[a * 3] /= l; nrm[a * 3 + 1] /= l; nrm[a * 3 + 2] /= l;
  }

  // ---- adjacency (CSR) over every primitive's triangles
  const edges = new Set();
  for (const geo of geometries) {
    const I = geo.index.array;
    for (let t = 0; t < I.length; t += 3) {
      const a = nodeOf[I[t]], b = nodeOf[I[t + 1]], c = nodeOf[I[t + 2]];
      for (const [u, v] of [[a, b], [b, c], [c, a]]) if (u !== v) edges.add(u < v ? u * N + v : v * N + u);
    }
  }
  const start = new Int32Array(N + 1);
  for (const k of edges) { start[Math.floor(k / N) + 1]++; start[(k % N) + 1]++; }
  for (let a = 0; a < N; a++) start[a + 1] += start[a];
  const nbr = new Int32Array(start[N]), len = new Float32Array(start[N]);
  const fill = start.slice(0, N);
  for (const k of edges) {
    const u = Math.floor(k / N), v = k % N;
    const d = Math.hypot(pos[u * 3] - pos[v * 3], pos[u * 3 + 1] - pos[v * 3 + 1], pos[u * 3 + 2] - pos[v * 3 + 2]) || 1e-6;
    nbr[fill[u]] = v; len[fill[u]++] = d;
    nbr[fill[v]] = u; len[fill[v]++] = d;
  }
  const graph = { N, start, nbr, len };

  // ---- 4 (first, so limb mixes below never see them). Fold helpers into the body.
  const body = idx(BODY);
  const fold = FOLD.map(idx).filter((b) => b >= 0);
  if (body >= 0) {
    for (const m of weights) for (const b of fold) { const w = m.get(b); if (w) { m.delete(b); add(m, body, w); } }
  }

  // ---- 2-3. limbs
  const parentIdx = bones.map((b) => (b.parent?.isBone ? idx(b.parent.name) : -1));
  const out = { verts: n, nodes: N, limbs: {} };
  for (const limb of LIMBS) {
    const root = idx(limb.root), child = idx(limb.child);
    if (root < 0 || child < 0) continue;
    const family = new Set();
    for (let b = 0; b < bones.length; b++) { let p = b; while (p >= 0 && p !== root) p = parentIdx[p]; if (p === root) family.add(b); }
    out.limbs[limb.root] = reskinLimb(limb, root, family, head(root), head(child), weights, pos, nrm, graph);
  }

  // ---- 5. top four, normalise, write back to every welded copy
  const topJ = new Uint16Array(N * 4), topW = new Float32Array(N * 4);
  for (let a = 0; a < N; a++) {
    const sorted = [...weights[a].entries()].filter((e) => e[1] > 1e-4).sort((x, y) => y[1] - x[1]).slice(0, 4);
    const s = sorted.reduce((acc, e) => acc + e[1], 0) || 1;
    sorted.forEach(([b, w], k) => { topJ[a * 4 + k] = b; topW[a * 4 + k] = w / s; });
  }
  for (let i = 0; i < n; i++) {
    const a = nodeOf[i];
    for (let k = 0; k < 4; k++) { J.setComponent(i, k, topJ[a * 4 + k]); W.setComponent(i, k, topW[a * 4 + k]); }
  }
  J.needsUpdate = true;
  W.needsUpdate = true;
  return out;
}

function reskinLimb(limb, root, family, a, b, weights, pos, nrm, graph) {
  const { N, start, nbr, len } = graph;
  const dx = b[0] - a[0], dy = b[1] - a[1], dz = b[2] - a[2];
  const L = Math.hypot(dx, dy, dz);
  const ux = dx / L, uy = dy / L, uz = dz / L;
  const share = new Float32Array(N);
  for (let v = 0; v < N; v++) { let s = 0; for (const [bone, w] of weights[v]) if (family.has(bone)) s += w; share[v] = s; }

  // The tube: everything the chain owned outright, plus the upper limb found
  // by shape (near the bone, past the socket, facing away from the bone).
  // The ball's own skin that the arm overlaps in the armpit faces the other
  // way, so it stays ball and is simply uncovered when the arm lifts.
  const core = new Uint8Array(N);
  let tube = 0;
  for (let v = 0; v < N; v++) {
    const px = pos[v * 3] - a[0], py = pos[v * 3 + 1] - a[1], pz = pos[v * 3 + 2] - a[2];
    const t = px * ux + py * uy + pz * uz;
    if (t < limb.from) continue;
    if (share[v] > 0.995) { core[v] = 1; tube++; continue; }
    if (t > L * 1.25 || share[v] < 0.05) continue;
    const rx = px - t * ux, ry = py - t * uy, rz = pz - t * uz;
    const r = Math.hypot(rx, ry, rz);
    if (r > limb.radius || r < 1e-6) continue;
    if ((rx * nrm[v * 3] + ry * nrm[v * 3 + 1] + rz * nrm[v * 3 + 2]) / r > 0.45) { core[v] = 1; tube++; }
  }
  if (!tube) return { tube: 0 };

  // Around the socket the ball follows the limb root by a share that falls
  // off with straight-line distance from the joint.
  const target = new Float32Array(N);
  for (let v = 0; v < N; v++) {
    const d = Math.hypot(pos[v * 3] - a[0], pos[v * 3 + 1] - a[1], pos[v * 3 + 2] - a[2]);
    const x = Math.min(1, Math.max(0, (d - limb.inner) / (limb.outer - limb.inner)));
    target[v] = core[v] ? 1 : 1 - x * x * x * (x * (x * 6 - 15) + 10);
  }
  // Where the tube's skin runs into the ball's, spread the change over a band
  // on both sides (measured along the surface) by solving for a harmonic
  // blend: the limb is pinned to 1 deep in the tube and the ball to its
  // socket falloff away from the seam.
  const intoTube = dijkstra(graph, (v) => !core[v], limb.seamIn);
  const outOfTube = dijkstra(graph, (v) => core[v] === 1, limb.seamOut);
  const s = Float32Array.from(target);
  const band = [];
  for (let v = 0; v < N; v++) if (core[v] ? intoTube[v] < limb.seamIn : outOfTube[v] < limb.seamOut) band.push(v);
  let iters = 0;
  for (let change = 1; iters < 400 && change > 1e-4; iters++) {
    change = 0;
    for (const v of band) {
      let sw = 0, sx = 0;
      for (let e = start[v]; e < start[v + 1]; e++) { const w = 1 / len[e]; sw += w; sx += w * s[nbr[e]]; }
      const next = s[v] + 1.6 * (sx / sw - s[v]);
      const clamped = next < 0 ? 0 : next > 1 ? 1 : next;
      change = Math.max(change, Math.abs(clamped - s[v]));
      s[v] = clamped;
    }
  }

  // Bone mixes for vertices that gain a share they never had.
  const bodyDonor = nearestSource(graph, (v) => share[v] < 0.5);
  let moved = 0;
  for (let v = 0; v < N; v++) {
    const target = s[v];
    if (Math.abs(target - share[v]) < 1e-4) continue;
    const m = weights[v];
    const limbMix = new Map(), bodyMix = new Map();
    for (const [bone, w] of m) (family.has(bone) ? limbMix : bodyMix).set(bone, w);
    // Only the tube keeps its forearm/hand mix; skin dragged off the ball
    // follows the limb root alone.
    if (!core[v] || sum(limbMix) < 0.05) { limbMix.clear(); limbMix.set(root, 1); }
    if (sum(bodyMix) < 0.05) {
      bodyMix.clear();
      const d = bodyDonor[v];
      if (d >= 0) for (const [bone, w] of weights[d]) if (!family.has(bone)) bodyMix.set(bone, w);
    }
    normalize(limbMix); normalize(bodyMix);
    if (!bodyMix.size && target < 1) continue;
    m.clear();
    for (const [bone, w] of limbMix) add(m, bone, w * target);
    for (const [bone, w] of bodyMix) add(m, bone, w * (1 - target));
    moved++;
  }
  return { tube, band: band.length, iters, moved };
}

// Multi-source geodesic distance over the edge graph, cut off at `limit`.
function dijkstra({ N, start, nbr, len }, isSource, limit = Infinity) {
  const dist = new Float32Array(N).fill(Infinity);
  const heap = new MinHeap();
  for (let v = 0; v < N; v++) if (isSource(v)) { dist[v] = 0; heap.push(0, v); }
  while (heap.size) {
    const [d, v] = heap.pop();
    if (d > dist[v]) continue;
    for (let e = start[v]; e < start[v + 1]; e++) {
      const u = nbr[e], nd = d + len[e];
      if (nd < dist[u] && nd < limit) { dist[u] = nd; heap.push(nd, u); }
    }
  }
  return dist;
}

// Nearest source vertex for every vertex, by geodesic distance.
function nearestSource({ N, start, nbr, len }, isSource) {
  const dist = new Float32Array(N).fill(Infinity);
  const src = new Int32Array(N).fill(-1);
  const heap = new MinHeap();
  for (let v = 0; v < N; v++) if (isSource(v)) { dist[v] = 0; src[v] = v; }
  // Seed only the frontier: sources next to a non-source.
  for (let v = 0; v < N; v++) {
    if (src[v] !== v) continue;
    for (let e = start[v]; e < start[v + 1]; e++) if (src[nbr[e]] !== nbr[e]) { heap.push(0, v); break; }
  }
  while (heap.size) {
    const [d, v] = heap.pop();
    if (d > dist[v]) continue;
    for (let e = start[v]; e < start[v + 1]; e++) {
      const u = nbr[e], nd = d + len[e];
      if (nd < dist[u]) { dist[u] = nd; src[u] = src[v]; heap.push(nd, u); }
    }
  }
  return src;
}

function sum(m) { let s = 0; for (const w of m.values()) s += w; return s; }
function add(m, b, w) { if (w > 0) m.set(b, (m.get(b) || 0) + w); }
function normalize(m) {
  const s = sum(m);
  if (s) for (const [b, w] of m) m.set(b, w / s);
}

class MinHeap {
  constructor() { this.k = []; this.v = []; }
  get size() { return this.k.length; }
  push(key, val) {
    const k = this.k, v = this.v;
    let i = k.length;
    k.push(key); v.push(val);
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (k[p] <= key) break;
      k[i] = k[p]; v[i] = v[p]; i = p;
    }
    k[i] = key; v[i] = val;
  }
  pop() {
    const k = this.k, v = this.v;
    const topK = k[0], topV = v[0];
    const lastK = k.pop(), lastV = v.pop();
    const n = k.length;
    if (n) {
      let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1;
        let m = i, mk = lastK;
        if (l < n && k[l] < mk) { m = l; mk = k[l]; }
        if (r < n && k[r] < mk) { m = r; mk = k[r]; }
        if (m === i) break;
        k[i] = k[m]; v[i] = v[m]; i = m;
      }
      k[i] = lastK; v[i] = lastV;
    }
    return [topK, topV];
  }
}

/// The eyelids ship skinned to the root bone only, so they stay put while his head nods and
/// breathes, and the eyes slide out from under them. This gives every lid vertex the weights
/// of the nearest face skin (not the eyeball), so the lids ride the face they sit in.
export function bindLidsToFace(character) {
  const lids = [], faces = [];
  character.traverse((o) => {
    if (!o.isSkinnedMesh) return;
    if (o.name.startsWith('Lid')) lids.push(o);
    else if (o.morphTargetDictionary?.Mouth_Open !== undefined) faces.push(o);
  });
  if (!lids.length || !faces.length) return;
  character.updateMatrixWorld(true);
  const p = new THREE.Vector3();
  const box = new THREE.Box3();
  for (const lid of lids) box.expandByObject(lid);
  box.expandByScalar(0.08);

  // Face skin near the eyes, with its weights by bone name; eyeball vertices are skipped.
  const skin = [];
  for (const face of faces) {
    const si = face.geometry.attributes.skinIndex, sw = face.geometry.attributes.skinWeight;
    const names = face.skeleton.bones.map((b) => b.name);
    for (let i = 0; i < si.count; i += 1) {
      face.getVertexPosition(i, p).applyMatrix4(face.matrixWorld);
      if (!box.containsPoint(p)) continue;
      const w = [];
      let eye = 0;
      for (let k = 0; k < 4; k += 1) {
        const weight = sw.getComponent(i, k);
        if (weight <= 0) continue;
        const name = names[si.getComponent(i, k)];
        if (name.startsWith('Eye_')) eye += weight;
        w.push([name, weight]);
      }
      if (eye < 0.05) skin.push({ x: p.x, y: p.y, z: p.z, w });
    }
  }
  if (!skin.length) return;

  for (const lid of lids) {
    const si = lid.geometry.attributes.skinIndex, sw = lid.geometry.attributes.skinWeight;
    const index = new Map(lid.skeleton.bones.map((b, i) => [b.name, i]));
    for (let i = 0; i < si.count; i += 1) {
      lid.getVertexPosition(i, p).applyMatrix4(lid.matrixWorld);
      let best = null, bestD = Infinity;
      for (const s of skin) {
        const d = (s.x - p.x) ** 2 + (s.y - p.y) ** 2 + (s.z - p.z) ** 2;
        if (d < bestD) { bestD = d; best = s; }
      }
      const w = best.w.filter(([name]) => index.has(name));
      const total = w.reduce((a, [, v]) => a + v, 0);
      if (!total) continue;
      for (let k = 0; k < 4; k += 1) {
        si.setComponent(i, k, k < w.length ? index.get(w[k][0]) : 0);
        sw.setComponent(i, k, k < w.length ? w[k][1] / total : 0);
      }
    }
    si.needsUpdate = true;
    sw.needsUpdate = true;
  }
}
