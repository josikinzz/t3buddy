---
name: Local Machine Widgets
description: Private native macOS desktop widgets for local AI workstation control.
colors:
  panel-material: "#F4F4F7CC"
  row-rest: "#FFFFFF14"
  row-active: "#34C75929"
  accent-loaded: "#34C759"
  accent-destructive: "#FF3B30"
  text-primary: "#1D1D1F"
  text-secondary: "#6E6E73"
  separator: "#D1D1D6"
  provider-claude: "#D97757"
typography:
  title:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  body:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "normal"
  label:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "normal"
  token-total:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "44px"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "normal"
    fontVariantNumeric: "tabular-nums"
rounded:
  row: "8px"
  panel: "14px"
  indicator: "999px"
spacing:
  panel-padding: "12px"
  section-gap: "8px"
  row-gap: "6px"
  row-x: "9px"
  row-y: "6px"
components:
  panel:
    backgroundColor: "{colors.panel-material}"
    rounded: "{rounded.panel}"
    padding: "{spacing.panel-padding}"
    width: "332px"
    height: "natural"
  model-row:
    backgroundColor: "{colors.row-rest}"
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
    rounded: "{rounded.row}"
    padding: "6px 9px"
  model-row-active:
    backgroundColor: "{colors.row-active}"
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
    rounded: "{rounded.row}"
    padding: "6px 9px"
  button-standard:
    textColor: "{colors.text-primary}"
    typography: "{typography.label}"
    rounded: "{rounded.row}"
  button-destructive:
    textColor: "{colors.accent-destructive}"
    typography: "{typography.label}"
    rounded: "{rounded.row}"
---

# Design System: Local Machine Widgets

## 1. Overview

**Creative North Star: "The Desktop Instrument"**

The local machine widgets should feel like small instruments that belong on the Mac desktop: present, quiet, glanceable, and useful without asking for attention. The interface is a private utility for this AI-running workstation, so its visual language should stay close to macOS rather than trying to build a public product identity.

The system is compact and state-first. Model names, loaded state, unified memory usage, top memory-consuming apps, and action availability are the design priorities. Ornament, marketing copy, and custom-brand spectacle are prohibited because they would make the widgets feel less trustworthy.

**Key Characteristics:**
- Native SwiftUI controls and platform materials.
- Tight, readable density sized for a desktop panel.
- Semantic accents only for real state: loaded model, warning, destructive action.
- Short labels, direct status text, and no promotional language.
- Familiar macOS behavior before distinctive styling.

## 2. Colors

The palette is primarily SwiftUI semantic color and material, with static swatches documented only so tools can preview the system.

### Primary
- **Loaded Green:** Used for active model state, active row emphasis, and the loaded indicator. It should remain rare and meaningful.
- **Destructive Red:** Reserved for Force Quit and other destructive actions. It should identify danger, not decorate the process list.

### Neutral
- **Panel Material:** The panel background is SwiftUI `.regularMaterial`, not a flat custom color. It should adapt to system appearance and desktop context.
- **Resting Row Wash:** Idle model rows use a very light tonal layer over the material surface.
- **Primary Label:** Primary text follows the system label color and must stay high contrast.
- **Secondary Label:** Metadata, status text, and summaries use the platform secondary label color.
- **Separator Gray:** Use only when a platform divider is genuinely needed; current UI relies mostly on spacing and tonal layers.

### Named Rules

**The System First Rule.** SwiftUI semantic colors and materials are the source of truth. Static hex values are preview swatches, not a reason to hard-code a web palette.

**The One Accent Rule.** Green means loaded or actively relevant model state. Do not use green as decoration.

**The Destructive Clarity Rule.** Red is reserved for actions that terminate something. A red control must name the target action clearly.

### Provider Colours

Cards that draw a provider (subscription usage bars, the token graph and legend) take its colour from one shared map, `ProviderPalette` in `LocalModelWidgetPanel`. No card hard-codes a provider colour.

- **Claude:** `#d97757`, T3's tint for the Claude mark, everywhere.
- **Codex:** system blue.
- **Kimi:** system teal.
- **Other providers:** system gray.

A usage bar at 95% or more turns orange whatever the provider; its percentage text carries the same state.

## 3. Typography

**Display Font:** None. The token total is the one display-size numeral (see Tokens below); it stays SF Pro.
**Body Font:** SF Pro through the system font stack.
**Label/Mono Font:** SF Pro through the system font stack.

**Character:** Native, compact, and utility-forward. The type system should read like macOS chrome, not a website.

### Hierarchy
- **Title** (600, 16px, 1.2): Panel title only.
- **Body** (400 to 600, 12px, 1.3): Model names and primary row content.
- **Secondary** (400 to 500, 11px, 1.25): Active model summary and compact controls.
- **Label** (400 to 500, 10px, 1.25): Memory summary, row metadata, sizes, and footer status.
- **Token Total** (600, 44px, monospaced digits): Today's token total on the Tokens card only.

### Named Rules

**The No Display Type Rule.** This widget never uses hero sizes, display fonts, fluid headings, or marketing typography. One exception, asked for by the owner: a card may show one display-size numeral when the number must read from across the room. Today only the Tokens card does. The numeral is the system font (`.system(size: 44, weight: .semibold)`, no rounded or custom design) with monospaced digits, and it is a number, never words.

## 4. Elevation

Depth comes from one soft shadow per card, `.regularMaterial`, and subtle tonal row backgrounds. Interior components should stay flat. The panel itself may float; rows and controls should not cast decorative shadows.

### Shadow Vocabulary

- **Card Shadow:** One soft drop shadow on each dashboard card (black at 22%, 9pt radius, 3pt down). The transparent dashboard window itself has no shadow.

### Named Rules

**The Panel Shadow Only Rule.** If an element inside the widget needs emphasis, use state, spacing, or tonal background. Do not add shadows inside a card.

## 5. Components

### Panel

Each panel is a card in one transparent desktop-level dashboard window, laid out in a masonry grid of 332px columns (three on the 1080pt-wide portrait screen: 3 × 332 + 2 × 16 gaps = 1028, inside 24pt margins).

- **Shape:** Soft system panel corner (14px).
- **Background:** SwiftUI `.regularMaterial`.
- **Size:** 332px wide at its natural height. No card scrolls: Process Memory lists at most 12 processes, and the dashboard window grows to fit the grid.
- **Internal Padding:** 12px.
- **Behavior:** Drag a card onto another to take its slot; the order persists. A card that grows pushes only the cards below it in its column. At launch the grid repacks until every card has left its placeholder, so a card still loading does not leave the columns lopsided. The dashboard is desktop-pinned by default; the Desktop/Float choice lives once on the dashboard, and every card's menu shows and sets that one mode.

### Header

The header keeps only the panel title, the key loaded/active state where relevant, and a compact utility menu.

- **Title:** 16px semibold system text.
- **Mode Control:** Desktop/Float selection lives in the utility menu.
- **Active Model:** Local Models shows the loaded model in its single card row, not under the title.
- **Spacing:** Keep the control aligned to the title baseline and avoid additional labels.

### Memory Meter

The memory block is compact telemetry for Process Memory. Local Models shows no memory meter.

- **Title:** Use the native memory chip icon visually; keep the full memory title in accessibility.
- **Summary:** 10px medium secondary text with monospaced digits.
- **Meter:** Native linear `ProgressView`; do not replace it with a custom dashboard chart.
- **State:** Memory pressure may later earn semantic color, but the current default should remain native and restrained.
- **Pressure:** Show a compact textual state only when pressure is elevated or high. Use restrained amber for memory pressure so destructive red stays reserved for terminating actions. Normal memory remains neutral.

### Loaded Model Row

Local Models shows one row: the loaded model and its host, or `No model loaded`. It does not list installed models.

- **Shape:** Gently curved row (8px).
- **Background:** A subtle white tonal wash when nothing is loaded; a low-opacity loaded green wash when a model is loaded.
- **Indicator:** Compact SF Symbol: filled green check when loaded, empty circle otherwise.
- **Text:** Model name at 12px semibold with middle truncation for long model IDs; host name at 10px secondary.
- **Action:** A small standard Unload button sits at the trailing edge only while a model is loaded, disabled while work is in progress. Its accessibility label names the model and host, such as "Unload llama3 from Ollama".

### Process Rows

Process rows are the main surface for the memory app widget.

- **Order:** Sort from highest memory usage to lowest.
- **Shape:** Match the loaded model row with the same 8px radius and row padding.
- **Text:** App name at 12px semibold; memory usage and percent at 10px with monospaced digits. PID/path details belong in tooltips, not the main row.
- **Action:** Force Quit is a visible row action, not a hidden gesture. A compact destructive icon may replace text when its tooltip and accessibility label include the app name, such as "Force Quit Xcode".
- **State:** Apps under active termination should show pending state and disable repeat clicks.

### Dashboard Card: Tokens

Token usage over the last 7 days per provider.

- **Total:** Today's fresh input plus output as one large numeral (Token Total style), followed by a 12px secondary `today` label. This is the documented exception to the No Display Type Rule: the owner reads it from across the room.
- **Graph:** Fresh input plus output, stacked by provider in provider colours; cache reads in their own small line chart so a large cache read never flattens the graph.
- **Legend:** Provider dot, name, and today's total at 10px.
- **Menu:** Window mode, Refresh now, and Quit, like every other card.

### Desk Pet (T3boii)

T3boii is the second deliberate exception, asked for by the owner: a pet, not a widget.

- **Frame:** Free-floating anywhere on the screen, with no box, card, material, frame, or window edge. Clicks pass through everywhere except on T3boii and his orbs.
- **Art style:** Everything that comes out of him is 3D and lit like he is: puffy glossy hearts, bevelled Zs, a glassy drool strand, spiral tubes of wind, soft rings of psychic light, and the god rays and warm glare of light pouring from his mouth. Nothing is a flat vector sticker.
- **Orbit:** Each active agent is an orb on a halo of near-circular rings hugging the edge of his round body, so every thread is in view at once. The rings lean back a little: the lower half passes in front of his legs, the upper half behind the top of his head, low enough that an orb passing over the top tucks about a third of its height behind it, and an orb grows and brightens a touch on the near side. Each ring in use is a faint, translucent veil of light: two thin strands weaving about each other, drifting motes, and soft sparks running round.
- **Orbs:** Every orb is shaded as a small sphere. A project favicon keeps its own transparent background inside a clear glass bubble, and one that is an opaque square gets rounded corners there (a round favicon, or one with transparent corners, keeps its shape); a monogram is a solid shaded ball. A thread's provider logo, transparent as in T3 Code (Claude in `#d97757`), sits small on the lower part of its sphere over the project icon, which keeps its full size and place, with a soft shadow so it reads on any icon; a thread never reads as a subagent. A logo with no transparency (Grok Bot's) is cut to a circle, and a Grok Bot agent's photo avatar is ringed in its colour. A thread's subagents circle it as satellites, each a dark glossy sphere wearing only its provider logo; a task delegated through T3 is one satellite, not two. A thread keeps one orb for its whole life: a new turn, a message sent to it, a change of state or a gap of one poll in what T3 reports never swallows and respawns it, and a thread whose own turn has ended keeps its orb while its subagents or delegated tasks work, so they stay its satellites. A thread that stirs again after a lull only glows briefly, as an orb leaving his forehead does. He swallows an orb only when T3 says its thread finished; one that just stops being listed (deleted, archived, out of view) fades where it is, and while T3 cannot be read nothing spawns or is swallowed and the orbit greys slightly until T3 answers again. No orb shows a count. An orb breathes faster and deeper the harder its thread works (how fast its timeline grows): from a slow 3.4 s breath to never quicker than 0.95 s and never more than 5% bigger, brightening a little at the crest when it is flat out; with Reduce Motion it does not swell and steps brighter instead. A ring laps faster with its orbs' mean activity, never more than 1.6 times its base pace (a subagent ring 1.5), and a busier orb presses up to a quarter slot ahead of its neighbours without ever passing them. Activity eases in and out over a few seconds, so nothing snaps; a thread quiet for minutes drifts out from its ring and dims, so a stuck agent stands out.
- **Messages:** A message reaching a thread comes as a glint: a glowing glass bead about a fifth of an orb across with a fading tail of bright motes, warm white from its owner and cool cyan from anything else (an agent, an MCP caller, a bot). It starts behind his body, hidden by it, comes out past his edge and curves round to the orb, chasing it as it moves, in under a second; the orb gulps it, squashing along its way and springing back, a flash of its colour on the glass and a faint 3D ring spreading out, and his eyes flick to it. At most three fly at once and an orb gulps at most once every 0.6 s; a second message for the same orb rides with the first, which grows a little and leaves two rings. With Reduce Motion the orb only flashes and pulses 3%.
- **Queued messages** (on unless the feed runs with flag `-queue`): messages queued behind a thread's turn circle its orb as up to three small warm glass seeds, teardrops a quarter of an orb long with their points trailing, the way its moons circle it but smaller, a different shape, and on a more open lap that keeps them off the orb itself. With moons out, the seeds ride the moons' first ring in the gaps between them, so the two never touch. One seed per message, so one, two or three read at a glance; more than three makes the last one bigger, never a number. A message taken off the queue keeps its seed until the orb gulps the glint bringing it, which draws the front seed in, one per message; one cancelled shrinks and fades where it is. Round a question mark's dot they keep the moons' flat lap, clear of the mark.
- **Needs you:** A thread waiting on its owner leaves the halo and floats beside his head, its orb shrunk to the dot of a 3D question mark: a chunky, rounded-blocky amber glass `?` grows up out of it, its thick stroke squared off in section and standing a clear gap above the dot (for an approval, a `!` of the same stroke, its bar widening toward the top, the orb its separate dot below the gap), lit like him, swaying a few degrees and glowing slowly, the glow widening after a minute but never quickening. Questions take places on an arc beside his head in the order they were asked, alternating sides, each dot a fifth of an orb outside the edge of an orb riding his outermost ring in use (further below level, where its mark's stroke rises back toward the ring), so neither mark nor dot ever sits on a ring; a further arc out past six. When the screen's edge leaves room on only one side, every question goes on that side, three to an arc. A question that waits stays where it is. A question answered at once still shows for over a second so it can be read, then its hook pulls back down into the dot and the orb rejoins the halo. He glances at a new question and gives it one small nod, dipping and tipping toward its side (a newer one takes the nod over), and while fretful glances at the one that has waited longest. Its words, "needs you" in amber, stand level beside its mark rather than along the way it flew in: on the side away from him, or toward him when the screen's edge leaves no room, clear of the mark and of any moons or seeds round its dot, and drawn over every orb and mark so nothing hides them. Clicking the orb opens the thread. With Reduce Motion a mark fades in whole, only its glow changes, and he does not nod.
- **Provider change:** A thread moved to another provider flips its orb's badge: it turns edge-on, swaps to the new logo and turns back with a small overshoot, while a rim of the new provider's colour flashes round the orb (Claude `#d97757`, Codex `#0a84ff`, Kimi `#40c8e0`, Antigravity `#ff6fb1`, OpenCode `#c9ced6`, Grok `#f5f5f7`, others `#8e8e93`). A new model on the same provider only flashes, at half strength. With Reduce Motion the badge swaps in place and the flash is faint.
- **Pull requests** (not shown yet: the feed does not read them until a real linked pull request's check fields have been seen): an orb whose thread has a pull request wears a thin lit band 1.2 orbs across, tilted like his rings. Silver and faint with a light running round it while checks run, green when they pass, red with a gap and a slow glow when they fail; it fades when the pull request closes or merges. See `docs/t3boii-pr-ring.png`.
- **Scheduled tasks** (a prototype, on unless the feed runs with flag `-seeds`; `t3boii.debug.seeds()` shows samples): each enabled T3 scheduled task is a small glossy teardrop in its provider's colour on a little halo over his head, turning once every 40 s, at most eight. A seed glows brighter over the last five minutes before its task runs. When it runs, the seed drops into his T3, which flares, and grows back on the halo; a task bound to a thread with an orb out sends a glint to that orb instead. A task whose last run failed has a hairline crack. With Reduce Motion the halo stands still. See `docs/t3boii-seeds.png`.
- **Snoozed:** A thread snoozed in T3 while its orb still shows (working, asking or failed) rests as a frosted egg at his feet: the orb drops out of its place and elongates into an egg, its icon dim through a frosted shell. The eggs sit in a shallow row, the one that wakes soonest in the middle and the rest out to either side, at most six; any more snoozed orbs stay where they are. An egg breathes very slowly. In its last minute it rocks, more and more, and in its last twenty seconds it hops every six. When its thread wakes, white cracks draw across it, the shell splits into two 3D half-shells that fall away tumbling, and the orb pops out and flies back to its place; if the thread finished while snoozed, it hatches, hovers a moment, and is swallowed. With Reduce Motion an egg stays still and its rim glows amber over its last minute, and it crossfades back. See `docs/t3boii-eggs.png`.
- **Failure:** A thread that fails makes him flinch. Its orb cracks and turns to red glass, the whole sphere, its icon and its logo tinted red, with a chip bitten out of its edge. It jolts on its ring, then goes down to the worry zone beside his lower body, alternating sides, four to a row. There it shivers faintly and every two or three seconds sputters a few dark ember chips with a flicker, and he frowns at it, glancing back now and then, until you look at it (hover it a moment, click it, or settle the thread in T3). Then it greys, sinks and fades. It stays until seen even after its thread has gone, for up to ten minutes. If the thread runs again first, a thin violet beam reaches it from his T3, its cracks fill with violet light and seal, the red drains to clear glass, and it flies home to its ring: one orb per thread, mended. With Reduce Motion it fades to its place, with no chips, shiver or beam, and only dims slowly. See `docs/t3boii-worry.png`.
- **Limits:** When a provider refuses work for a rate or usage limit (T3 ends the run with an error such as "Usage limit reached", "You've reached your 5-hour usage limit" or "Selected model is at capacity"), T3boii cries: tears well at his lower lids and run glassy down his cheeks, leaving a wet streak, and drip off; he sobs with little shudders, his lids droop, his mouth turns down in a trembling pout and he slumps, for a few seconds. Then he stays glum (heavy lids, a frown, eyes low, now and then a tear) until the limit clears: the provider is seen working again, the time it gave passes, or ten minutes go by with no new refusal. Each thread it refused dies where it is: its orb darkens to a dark glass ball under a big copy of the provider's logo, then is eaten away from within, a violet ember rim running ahead of the hole, while dark glossy chips crumble off it and fall; the logo goes last. Its satellites go with it. It stays gone unless its thread comes back working. He cries once per limit, however many threads hit it.
- **Activity trails:** What each thread is doing trails behind its orb like a comet's tail: soft glowing words laid along the path the orb has just flown, clearly legible at the orb and fading toward the tail, from its newest activity ("reading pet.js", "running swift build", "thinking…", or the start of what the agent said). Words always read left to right. A satellite's trail is shorter and a little fainter. Hover an orb and its trail lights up and he looks at it; a waiting thread's trail is amber, a failed one's red. Every half-minute or so he glances at one of his threads on his own. There are no speech bubbles or tooltips.
- **Emotes:** Idle, he stares blankly ahead, and now and then looks around, stretches or hops. A new agent lights the T3 on his forehead like violet neon, its glow bleeding into the skin round the letters, and it flares as three ripples of psychic light lift off it, each spreading from a crisp crest into a soft, wavering band that never cuts into his head. The orb kindles in the T3 as a ball of light, condenses into itself as it rises out of his head, and swings out round him into its slot; its violet aura fades as it settles, and so does the T3. A finished agent (T3 reports its thread ended; one that merely stops being listed fades instead) is sucked in: his lips purse into a round O, spirals of air stream into his mouth, he gulps, then grins a lopsided grin. When the last agent is gone, he does a short dance with a spin.
- **Workload:** With many threads going he concentrates: he blinks more, his eyes dart between orbs, he breathes faster, and he floats a little lower, as if carrying them.
- **Mood:** What the work around him says shows in how he holds himself, blended so nothing steps. Dozy after eight seconds with nothing to do: heavy lids, a slow breath, head down (sleep still comes later, as before). Focused with three or more threads, or one working hard: lids up, a small concentration frown, leaning in. Satisfied for five to ten seconds after he swallows one: a contented squint and smile and a little settle-bounce. Fretful while a failure goes unlooked-at or a question has waited twenty seconds: frowning, quick shallow breaths, quick blinks, arms in, a faint trembling mouth, checking on the problem more often. Satisfied lets him savour a meal while something is wrong, without the worry vanishing. Each mood holds a few seconds once entered. See `docs/t3boii-moods.png`.
- **Sleep:** Left alone with no agents for about 75 seconds (half that late at night), he yawns, then nods off: his lids close, his head droops, he breathes slow and deep, and Zs float up. After a while asleep, he drools. The mouse coming close, a pet, or a new agent wakes him with a start, and he has a big stretch.
- **Time of day:** Late at night he is a little dimmer and drowsier, his eyes glow less and he bobs more slowly; in the morning he is a touch brighter.
- **Gaze:** His eyes follow the mouse while it moves; otherwise they follow his orbiting agents, the orb he is talking about, or a failed orb he is frowning at.
- **Eyes and lids:** His eyelids always wrap over the outside of his eyes, and his eyes turn less while his lids are lowered, so no squint, blink, drowsy droop, grin, dance or gaze lets an eye show through a lid, and a blink closes fully. The eye glow only lands on bare eye. When his mouth lights up, the light comes from the dark inside of his mouth, never his lips.
- **Power:** The more agents orbit, the higher he floats and the rounder he swells. Threads and subagents count the same. With a few going his eyes look normal; from 5 they start to glow, and from 15 they are white right across. His mouth stays dark until 20, the most he can hold: then it opens a little and heavenly light pours out of it, god rays fanning across his face from a warm glare between his lips.
- **Touch:** Stroking him with the mouse or clicking him pets him: he squints, smiles, blushes and leans in; after a second of stroking, hearts pop out. Dragging him carries him, shaking him while carried makes his limbs flop, and shaking him hard spins him right round, leaving him dizzy with stars circling his head.
- **Sounds:** Playing with him makes quiet, non-verbal sounds, never words, and never shrill: everything is deep, soft and roomy, like a big soft creature in a large space. A low warm purr-hum while stroked, a muffled low bloop per heart, a soft bassy thud on a click, a low whoomp when picked up, a cushioned thud when let go, a low rubbery wub when shaken, a dark airy whoosh as he spins and a woozy low drone while dizzy, a soft low hum swell on hovering an orb, and a drowsy murmur if the mouse wakes him. While the mouse rests on him or one of his orbs, his own animations are heard too, in the same deep style: a low swell as a new orb glows out of his forehead, a dark inward rush as one is sucked in and a soft gulp after, a dull thunk and groan when a thread fails, a patient low hum as a question mark forms, a padded bass groove for the all-done dance, a deep yawn, a slow snore with the Zs, a soft bloop per drool drip, a whoomp for a stretch, and dark sniffles and a low quivering whimper when he cries over a limit. At most two of these play at once, each has its own cooldown, and they fade out quickly when the mouse leaves; with the mouse elsewhere he is silent. The clips are low-passed below about 3 kHz and given a reverb tail. Each sound has its own cooldown, never overlaps itself, and varies slightly in level and only downward in pitch. **T3boii sounds** in the Subscription Usage card's gear menu turns them off.
- **Motion:** At rest he breathes, blinks and floats at no more than 30 fps; flights, petting and dragging run at 60 fps. Rendering pauses when the pet is covered or the screen sleeps.
- **Reduce Motion:** The pet honours the system Reduce Motion setting: flights become fades, rings stand still, limbs do not flop, there are no sparks, wind, hearts, Zs, drool, fidgets or spins, the mouth light holds still and he does not glance about unprompted, and the dance is a small sway. Crying over a limit is a sad face with tears that only well and fade, no sobbing shudder; a dying orb only darkens under its logo and fades, with no dissolve or chips.
- **Demo mode:** `scripts/demo.sh` (a Darwin notification, `local.codex.LocalModelWidget.demo`) plays a ~44 s scripted show for screen recordings, built only from the behaviour above: asleep (Zs, drool, a drip), woken (startle, stretch), threads and subagents glowing out of his forehead with activity trails, now and then one swallowed, one waiting under a question mark, one failing and retried, a build to 20+ (white eyes, light from his mouth), Codex hitting its limit (he cries, three Codex threads and a Codex subagent dissolve under its logo, the light goes out), then swallowed back in waves and the all-done dance. `scripts/demo.sh limit [provider]` (`….demo.limit[.<provider>]`; `window.t3boii.debug.limit(provider)`) fakes just a limit on the real orbit: that provider's orbs (default: the provider with the most) dissolve and he cries; nine seconds later the real orbit comes back. It uses the owner's real projects with their resolved icons (`DemoProjects`), ignores real snapshots and the mouse while it runs, plays his animation sounds without needing the mouse on him, and holds off fidgets, then hands the orbit back to the real threads. Petting and shaking are left for the owner to record by hand. `window.t3boii.demo(false)` stops it.

This motion is the one allowed exception to "no decorative motion"; no card animates for decoration.

### Desk Pet (Shoggoth)

The Shoggoth is the second pet, picked with **Pet** in the Subscription Usage card's gear menu; T3boii stays the default and is unchanged. It is the owner's model: a grey, faceted blob with a dozen tentacles covered in pixel-art eyes, wearing a yellow "UwU" smiley mask over its real face, a flower of eight eyes. It runs on the same brain as T3boii (`pet.js`), so it does everything he does, when he does it; only how it shows each thing is its own (`Resources/Pet/bodies/shoggoth.js`). It has no bones: every motion below is a deformation of its lit materials.

- **Frame, art style, motion, Reduce Motion, sounds, demo:** as T3boii. Everything that comes out of it is 3D and lit. It stands a quarter shorter than him on screen, being much wider. With Reduce Motion its tentacles barely wriggle and never tremble.
- **Its face:** the mask is a visor hinged at its top edge. Whenever T3boii's mouth would open (to swallow, yawn, gasp, be shaken), the mask flips up and the eye-flower shows; half open is enough to clear it. The flower's irises take the **Shoggoth tint** (gear menu; red by default, six presets or any colour), applied live.
- **Its forehead:** the top of its head, above the mask. A new agent lights it violet, three ripples lift off it, all its eyes flash violet, and the orb kindles there and swings out. Scheduled seeds drop into it; a mending beam leaves from it.
- **Swallow:** the mask flips up, the flower sucks inward and the wind spirals into it; the orb goes into the flower, the mask drops, and a gulp ripples back from the flower through its head. The lopsided grin after is a lopsided tilt of its head. The all-done dance is T3boii's, with its tentacles waving round it in turn.
- **Orbit and everything round it:** rings hug its round middle; the top of a ring tucks about a third of an orb behind its top (between its head and the tentacles arching over it) and the bottom crosses in front of its lower tentacles. Messages come as glints from behind it; queued seeds, moons, provider flips, pull request rings and orb breaths are T3boii's. Question and approval marks float beside its head; failed orbs sink to the worry zone beside its lower body; snoozed eggs rest in a row at its underside; scheduled seeds circle over its head.
- **Moods:** dozy: heavy lids, slow breath, head down, tentacles sagging. Focused: lids up, leaning in, a quicker wriggle. Satisfied: a squint and T3boii's settle-bounce. Fretful: quick shallow breaths and quick blinks, tentacles drawn in, their tips trembling.
- **Nod:** for a new question it dips and tilts its head toward the question's side.
- **Gaze:** its painted eyes cannot move, so its head turns toward whatever T3boii would look at: the mouse, its orbs, a failed orb it frowns at, a question.
- **Eyes and lids:** every eye on it, the eye-flower's eight included, blinks, squints and droops as one, its lids closing from top and bottom (on the flower, from both sides of each eye toward its spoke). Power whitens only bare eye inside each eye's outline, brightest in its middle; its pupil and iris show through the glow until the eye goes white right across at 15 agents.
- **Power:** it floats higher and swells as T3boii does, its tentacles lift and spread, its eyes glow from 5 agents and are white from 15, and at 20 the mask lifts and light pours out of the eye-flower (T3boii's god rays and glare, from the flower).
- **Failure:** it flinches (its tentacles recoil, its head jolts), then frowns at the orb, its head dipping toward it, until you look.
- **Limits:** where T3boii cries, it darkens and droops: its tentacles sag, its head hangs, its sobs shudder through its tentacles, and its front eyes weep dark glassy ooze that runs down its skin and drips off. Glum after, it stays dim and droopy, with now and then a drop of ooze. The refused threads' orbs dissolve as T3boii's do.
- **Sleep:** its eyes close, its head droops, it breathes slow and deep, its tentacles sag, and Zs float up; after a while asleep it drools from under the mask's lower edge. It wakes with a start and stretches its tentacles out.
- **Touch:** petted, it squints, its head flushes pink, it leans in, and hearts pop out. Carried and shaken, its tentacles swing on springs against your hand; shaken hard, it spins with its tentacles flung out and is dizzy, with stars over its head.
- **Workload, time of day, activity trails:** as T3boii.
- **Ported from Blender:** the eye-flower material follows its Blender graph (`docs/shoggoth-shader-nodes.png`): nearest sampling, irises (HSL lightness between 0.15 and 0.37) times the tint, Blender's RGB curve approximated by the straight line min(1, x / 0.25) (Blender's is a smooth spline through the same points), and an alpha cut at 0.5. Both eye textures clip outside their image as Blender draws them.

### Utility Menu

The utility menu is the progressive disclosure point for secondary controls.

- **Trigger:** A compact icon button in the header.
- **Mode:** Desktop and Float live inside the menu instead of consuming panel chrome.
- **Unload:** Unload is a visible button on the loaded model row, not a menu item.
- **Quit:** Quit lives in the utility menu.
- **Status:** Last-updated/status text is available in the menu instead of the main panel surface.
- **Force Quit:** Keep Force Quit visible on each process row. A compact destructive icon is acceptable only with an explicit tooltip and accessibility label that names the target app.

## 6. Do's and Don'ts

### Do:

- **Do** preserve native SwiftUI materials, system typography, and macOS control behavior.
- **Do** keep the widget compact, glanceable, and quiet.
- **Do** use green only for loaded or actively relevant model state.
- **Do** use red only for destructive actions like Force Quit, and label the target clearly.
- **Do** order app memory rows from highest memory usage to lowest.
- **Do** make state readable without relying on color alone: active, pending, disabled, and error states need text or control-state support.
- **Do** keep labels short and practical because this is a private desktop utility.

### Don't:

- **Don't** make this feel like a web app squeezed into a Mac panel.
- **Don't** use flashy gradients, oversized hero-style typography, gamer or terminal themes, decorative illustrations, glassy spectacle, heavy branding, or novelty controls.
- **Don't** add marketing copy, onboarding tours, feature explainers, testimonials, or pricing-style layouts.
- **Don't** add internal card shadows, gradient text, side-stripe accents, or decorative motion. The desk pet is the one documented exception (see Desk Pet).
- **Don't** replace native controls with custom controls unless the system control cannot express the required state.
- **Don't** hide Force Quit behind an unlabeled icon, swipe-only gesture, or ambiguous destructive affordance.
