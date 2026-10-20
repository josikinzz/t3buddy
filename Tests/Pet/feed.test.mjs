import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createFeed } from '../../Resources/Pet/feed.js';

const orb = (id) => ({ id, state: 'active', provider: 'codex', project: 'demo-app' });
const state = (...ids) => ({ orbs: ids.map(orb) });

function recordingFeed() {
  const applied = [];
  const feed = createFeed((snapshot) => { applied.push(snapshot); return applied.length; });
  return { feed, applied, last: () => applied.at(-1) };
}

test('an orb that leaves without a finished event fades', () => {
  const { feed, last } = recordingFeed();
  feed({ state: state('t3:a', 't3:b') });
  feed({ state: state('t3:b') });
  assert.deepEqual(last().fade, ['t3:a']);
});

test('an orb whose thread T3 said finished does not fade, so the orbit may swallow it', () => {
  const { feed, last } = recordingFeed();
  feed({ state: state('t3:a', 't3:b') });
  feed({ events: [{ kind: 'finished', id: 't3:a' }], state: state() });
  assert.deepEqual(last().fade, ['t3:b']);
});

test('a finished event delivered alone counts for the next state', () => {
  const { feed, applied, last } = recordingFeed();
  feed({ state: state('t3:a') });
  assert.equal(feed({ events: [{ kind: 'finished', id: 't3:a' }] }), null, 'an events-only batch applies nothing');
  assert.equal(applied.length, 1);
  feed({ state: state() });
  assert.deepEqual(last().fade, []);
});

test('finish evidence does not leak into the state after the one it came with', () => {
  const { feed, last } = recordingFeed();
  feed({ state: state('t3:a') });
  feed({ events: [{ kind: 'finished', id: 't3:a' }], state: state('t3:a') });
  feed({ state: state() });
  assert.deepEqual(last().fade, ['t3:a'], 'the old finish is spent; leaving later is unknown, so it fades');
});

test('a finished event for an orb never shown fades nothing and swallows nothing later', () => {
  const { feed, last } = recordingFeed();
  feed({ events: [{ kind: 'finished', id: 't3:a' }], state: state('t3:b') });
  feed({ state: state('t3:a', 't3:b') });
  feed({ state: state('t3:b') });
  assert.deepEqual(last().fade, ['t3:a']);
});

test('a reading where every orb vanished with no events fades them all', () => {
  const { feed, last } = recordingFeed();
  feed({ state: state('t3:a', 't3:b') });
  feed({ state: state() });
  assert.deepEqual(last().fade.sort(), ['t3:a', 't3:b']);
  feed({ state: state('t3:a') });
  assert.deepEqual(last().fade, [], 'coming back after the reset fades nothing');
});

test('a new feed starts with nothing shown, so its first state fades nothing', () => {
  const { feed, last } = recordingFeed();
  feed({ events: [{ kind: 'message', id: 't3:a', from: 'user' }], state: state('t3:a') });
  assert.deepEqual(last().fade, []);
  assert.deepEqual(last().orbs.map((o) => o.id), ['t3:a']);
});

test('a state delivered again fades nothing and replays no events', () => {
  const { feed, last } = recordingFeed();
  feed({ events: [{ kind: 'message', id: 't3:a', from: 'user' }, { kind: 'failure.seen', id: 't3:b' }], state: state('t3:a', 't3:b') });
  assert.equal(last().messages.length, 1);
  assert.deepEqual(last().seen, ['t3:b']);
  feed({ state: state('t3:a', 't3:b') });
  assert.deepEqual(last().fade, []);
  assert.deepEqual(last().messages, []);
  assert.deepEqual(last().seen, []);
});

test('a finished event delivered twice before the state still lets the orb be swallowed', () => {
  const { feed, last } = recordingFeed();
  feed({ state: state('t3:a') });
  feed({ events: [{ kind: 'finished', id: 't3:a' }] });
  feed({ events: [{ kind: 'finished', id: 't3:a' }], state: state() });
  assert.deepEqual(last().fade, []);
});

test('messages reach the next state in order, with their sender and queue origin', () => {
  const { feed, last } = recordingFeed();
  feed({ state: state('t3:a', 't3:b') });
  feed({ events: [{ kind: 'message', id: 't3:b', from: 'user', fromQueue: true }] });
  feed({ events: [{ kind: 'message', id: 't3:a', from: 'agent' }, { kind: 'message', id: 't3:a', from: 'someone' }], state: state('t3:a', 't3:b') });
  assert.deepEqual(last().messages, [
    { id: 't3:b', from: 'user', fromQueue: true },
    { id: 't3:a', from: 'agent', fromQueue: false },
    { id: 't3:a', from: 'agent', fromQueue: false },
  ]);
});

test('the state passes through with its limits, seeds and source', () => {
  const { feed, last } = recordingFeed();
  const seeds = [{ id: 'seed:docs-site', provider: 'codex' }];
  const limits = [{ provider: 'codex', since: 1 }];
  assert.equal(feed({ state: { ...state('t3:a'), seeds, limits, source: 'stale' } }), 1, 'feed returns what apply returned');
  assert.deepEqual(last().seeds, seeds);
  assert.deepEqual(last().limits, limits);
  assert.equal(last().source, 'stale');
  feed({ state: state('t3:a') });
  assert.equal(last().source, 'live');
  assert.deepEqual(last().limits, []);
});

test('malformed batches apply nothing and break nothing', () => {
  const { feed, applied, last } = recordingFeed();
  assert.equal(feed(undefined), null);
  assert.equal(feed({ events: 'nope', state: { orbs: 'nope' } }), null);
  feed({ events: [null, { kind: 'finished' }, { kind: 'finished', id: 7 }], state: { orbs: [orb('t3:a'), null, { id: 3 }] } });
  assert.equal(applied.length, 1);
  feed({ state: state() });
  assert.deepEqual(last().fade, ['t3:a']);
});
