// The page's end of the feed. Swift's FeedClient relays the t3boii-feed sidecar as
// window.t3boii.feed({ events?, state? }); this turns that into orbit snapshots.
//
// State is truth: the orbit follows state.orbs. Events only choose how a change looks. An orb
// whose thread T3 said finished is swallowed; one that left any other way (deleted, archived,
// out of view) fades where it is. A missed event costs a plain fade, never a wrong scene.

export function createFeed(apply) {
  let shown = new Set();          // orb ids in the last state applied
  const finished = new Set();     // ids T3 said finished since then
  const seen = new Set();         // failed ids the owner has settled in T3 since then
  let messages = [];              // messages that reached a thread since then, in order

  return function feed(message) {
    for (const event of Array.isArray(message?.events) ? message.events : []) {
      if (event?.kind === 'finished' && typeof event.id === 'string') finished.add(event.id);
      if (event?.kind === 'failure.seen' && typeof event.id === 'string') seen.add(event.id);
      if (event?.kind === 'message' && typeof event.id === 'string') messages.push({ id: event.id, from: event.from === 'user' ? 'user' : 'agent', fromQueue: !!event.fromQueue });
    }
    const state = message?.state;
    if (!state || !Array.isArray(state.orbs)) return null;
    const ids = new Set(state.orbs.map((o) => o?.id).filter((id) => typeof id === 'string'));
    const fade = [...shown].filter((id) => !ids.has(id) && !finished.has(id));
    shown = ids;
    finished.clear();
    const settled = [...seen], arrived = messages;
    seen.clear();
    messages = [];
    return apply({ orbs: state.orbs, limits: state.limits || [], fade, seen: settled, messages: arrived, seeds: state.seeds, source: state.source || 'live' });
  };
}
