// The pets the page can show, by kind. The host picks one (window.__t3boiiConfig.pet, or ?pet= on
// the page); anything else gets T3boii.
//
// A body module's default export is its descriptor:
//   kind, name   its key here and its name in the menu
//   ball         { x, y, r } in model metres: the round middle the orbit rings hug, from the front
//   top          the height of its top in model metres, which the rings' top tucks behind
//   soles        how far below the ball's centre, in ball radii, its underside rests (eggs sit there)
//   anchors      { forehead, mouth }: { x, y[, z] } in model metres, rest pose, from the front
//   frame        its height on screen, as a share of the height T3boii is framed at
//   load(ctx)    adds the model to ctx.rig; resolves to the body pet.js drives each frame
// and the body: restPose(), pose(state) (returns how much it still swings after a shake),
// light(state), anchor('forehead' | 'mouth', out), droolCorner(swell), tears, tear(i, rig), internals,
// and optionally setTint(hex). `tear(i, rig)` gives { points, carry, tint }: world points now and the
// matrix carrying them with the face, or `points` as a function giving this frame's points.

import t3boii from './t3boii.js';
import shoggoth from './shoggoth.js';

export const BODIES = { t3boii, shoggoth };
export const DEFAULT_BODY = 't3boii';

export function bodyFor(kind) {
  return Object.hasOwn(BODIES, kind) ? BODIES[kind] : BODIES[DEFAULT_BODY];
}
