// T3boii's sounds: small, deep, soft, non-verbal effects (low hums, thuds, whooshes) for when you
// play with him, and for his own animations while the mouse is over him.
//
// Web Audio only: each clip in ./sfx/ is fetched and decoded once, then played through one
// quiet master gain. Every sound has its own cooldown and level, never overlaps itself, and
// gets a little random pitch (only ever lower, never brighter) and volume so repeats don't
// sound canned. Muting stops new sounds; the AudioContext is resumed on the first sound (the
// host lets media play without a user gesture, since mouse input reaches the page through the
// Swift bridge).
//
// Two kinds of play:
//   play(name)     an interaction (you poked him): always plays, cooldowns permitting.
//   ambient(name)  one of his own animations (an orb spawning, a yawn): plays only while the
//                  mouse is over him or his orbs (setListening), at most AMBIENT_MAX at once, and
//                  fades out quickly when the mouse leaves.
//
// Usage: const sounds = createSounds(); sounds.play('poke'); sounds.setMuted(true);

const MASTER = 0.24;        // everything is quiet by default
const AMBIENT_MAX = 2;      // ambient sounds playing at once
const AMBIENT_GAIN = 0.75;  // ambient sounds sit under the interaction sounds
const FADE_S = 0.35;        // ambient fade when the mouse leaves

// name: { gain, cooldown (s), rate jitter (down only: 1 - rate .. 1), gain jitter (±) }
const CLIPS = {
  // Interactions
  purr:  { gain: 0.7,  cooldown: 6,    rate: 0.12, vol: 0.15 },   // stroking him
  pop:   { gain: 0.45, cooldown: 0.25, rate: 0.12, vol: 0.25 },   // a heart pops out (and a drool drip)
  poke:  { gain: 0.8,  cooldown: 0.3,  rate: 0.12, vol: 0.15 },   // a click / pat
  grab:  { gain: 0.7,  cooldown: 0.8,  rate: 0.12, vol: 0.15 },   // picked up (and his stretch)
  drop:  { gain: 0.75, cooldown: 0.5,  rate: 0.12, vol: 0.15 },   // let go
  shake: { gain: 0.55, cooldown: 0.9,  rate: 0.12, vol: 0.2 },    // shaken about
  spin:  { gain: 0.6,  cooldown: 1.5,  rate: 0.12, vol: 0.1 },    // spun right round
  dizzy: { gain: 0.55, cooldown: 3,    rate: 0.12, vol: 0.1 },    // woozy after the spin
  orb:   { gain: 0.35, cooldown: 0.35, rate: 0.12, vol: 0.2 },    // hovering an orb
  wake:  { gain: 0.6,  cooldown: 20,   rate: 0.12, vol: 0.1 },    // woken from a proper sleep
  // His own animations (ambient)
  spawn: { gain: 0.55, cooldown: 2.5,  rate: 0.12, vol: 0.15 },   // a new orb glows out of his forehead
  suck:  { gain: 0.5,  cooldown: 2.5,  rate: 0.12, vol: 0.15 },   // an orb sucked in on the wind
  gulp:  { gain: 0.6,  cooldown: 2,    rate: 0.12, vol: 0.15 },   // ... and the gulp
  fail:  { gain: 0.6,  cooldown: 4,    rate: 0.1,  vol: 0.1 },    // a thread failed: flinch and crack
  hold:  { gain: 0.5,  cooldown: 8,    rate: 0.1,  vol: 0.1 },    // holding out a waiting orb
  dance: { gain: 0.55, cooldown: 10,   rate: 0.06, vol: 0.1 },    // the all-done dance
  yawn:  { gain: 0.55, cooldown: 20,   rate: 0.1,  vol: 0.1 },    // a yawn before he nods off
  snore: { gain: 0.4,  cooldown: 4.5,  rate: 0.12, vol: 0.2 },    // asleep, with the Zs
};

export function createSounds({ base = new URL('./sfx/', import.meta.url).href, muted = false } = {}) {
  const AC = window.AudioContext || window.webkitAudioContext;
  const ctx = AC ? new AC() : null;
  const master = ctx ? ctx.createGain() : null;
  if (master) { master.gain.value = MASTER; master.connect(ctx.destination); }

  const buffers = new Map();
  const lastAt = new Map();
  const playing = new Map();   // name -> { source, level, ambient }
  let isMuted = !!muted;
  let listening = false;

  const loaded = !ctx ? Promise.resolve(0) : Promise.all(Object.keys(CLIPS).map(async (name) => {
    try {
      const response = await fetch(base + name + '.mp3');
      if (!response.ok && response.status !== 0) throw new Error(`HTTP ${response.status}`);
      buffers.set(name, await ctx.decodeAudioData(await response.arrayBuffer()));
    } catch (e) {
      console.warn(`T3boii: sound ${name} failed to load: ${e?.message ?? e}`);
    }
  })).then(() => buffers.size);

  const jitter = (amount) => 1 + (Math.random() * 2 - 1) * amount;
  const lower = (amount) => 1 - Math.random() * amount;   // pitch only ever goes down
  const ambientCount = () => { let n = 0; for (const p of playing.values()) if (p.ambient) n += 1; return n; };

  function start(name, { delay = 0, gain = 1, ambient = false } = {}) {
    const clip = CLIPS[name];
    const buffer = buffers.get(name);
    if (!ctx || isMuted || !clip || !buffer || playing.has(name)) return false;
    const now = ctx.currentTime;
    if (now - (lastAt.get(name) ?? -1e9) < clip.cooldown) return false;
    if (ctx.state === 'suspended') ctx.resume().catch(() => {});
    lastAt.set(name, now + delay);
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.playbackRate.value = lower(clip.rate);
    const level = ctx.createGain();
    level.gain.value = clip.gain * gain * jitter(clip.vol) * (ambient ? AMBIENT_GAIN : 1);
    source.connect(level).connect(master);
    const entry = { source, level, ambient };
    source.onended = () => { if (playing.get(name) === entry) playing.delete(name); level.disconnect(); };
    playing.set(name, entry);
    source.start(now + Math.max(0, delay));
    return true;
  }

  /// An interaction sound: plays unless muted, cooling down, still playing, or not loaded yet.
  /// `delay` (s) schedules it later; `gain` scales this one play.
  function play(name, options = {}) {
    return start(name, { ...options, ambient: false });
  }

  /// One of his own animations: as play(), but only while the mouse is over him or his orbs,
  /// and never more than AMBIENT_MAX of them at once.
  function ambient(name, options = {}) {
    if (!listening || ambientCount() >= AMBIENT_MAX) return false;
    return start(name, { ...options, ambient: true });
  }

  /// Whether the mouse is over him (or one of his orbs). Leaving fades ambient sounds out.
  function setListening(value) {
    const next = !!value;
    if (next === listening) return listening;
    listening = next;
    if (!listening && ctx) {
      const now = ctx.currentTime;
      for (const [name, p] of playing) {
        if (!p.ambient) continue;
        p.level.gain.cancelScheduledValues(now);
        p.level.gain.setValueAtTime(p.level.gain.value, now);
        p.level.gain.linearRampToValueAtTime(0, now + FADE_S);
        try { p.source.stop(now + FADE_S + 0.02); } catch (_) { /* already stopped */ }
        playing.delete(name);
      }
    }
    return listening;
  }

  /// Polls `isOver()` (is the mouse on him or his orbs?) and keeps setListening in step, so
  /// leaving him fades ambient sounds out even when nothing else is running.
  let listenTimer = null;
  function listenWhile(isOver) {
    clearInterval(listenTimer);
    listenTimer = setInterval(() => { try { setListening(isOver()); } catch (_) { /* not ready yet */ } }, 100);
  }

  function setMuted(value) {
    isMuted = !!value;
    if (isMuted) {
      for (const p of playing.values()) { try { p.source.stop(); } catch (_) { /* already stopped */ } }
      playing.clear();
    }
    return isMuted;
  }

  return {
    play,
    ambient,
    setListening,
    listenWhile,
    setMuted,
    get muted() { return isMuted; },
    get listening() { return listening; },
    loaded,
    get count() { return buffers.size; },
    get state() { return ctx?.state ?? 'unavailable'; },
    names: Object.keys(CLIPS),
  };
}
