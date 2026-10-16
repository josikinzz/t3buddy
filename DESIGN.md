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
- **Art style:** Everything that comes out of him is 3D and lit like he is: puffy glossy hearts, bevelled Zs, a glassy drool strand, spiral tubes of wind, glowing rings, and the god rays and warm glare of light pouring from his mouth. Nothing is a flat vector sticker.
- **Orbit:** Each active agent is an orb on a halo of near-circular rings hugging the edge of his round body, so every thread is in view at once. The rings lean back a little: the lower half passes in front of his legs, the upper half just behind the top of his head, and an orb grows and brightens a touch on the near side. Each ring in use is a faint, translucent veil of light: two thin strands weaving about each other, drifting motes, and soft sparks running round.
- **Orbs:** Every orb is shaded as a small sphere. A project favicon keeps its own transparent background inside a clear glass bubble; a monogram is a solid shaded ball. A thread's provider logo, transparent as in T3 Code (Claude in `#d97757`), sits small on the lower part of its sphere over the project icon, which keeps its full size and place, with a soft shadow so it reads on any icon; a thread never reads as a subagent. A logo with no transparency (Grok Bot's) is cut to a circle, and a Grok Bot agent's photo avatar is ringed in its colour. A thread's subagents circle it as satellites, each a dark glossy sphere wearing only its provider logo; a task delegated through T3 is one satellite, not two. A thread keeps one orb for its whole life: a new turn, a message sent to it, a change of state or a gap of one poll in what T3 reports never swallows and respawns it, and a thread whose own turn has ended keeps its orb while its subagents or delegated tasks work, so they stay its satellites. A thread that stirs again after a lull only glows briefly, as an orb leaving his forehead does. No orb shows a count. An orb breathes quickly while its thread is busy and slowly when it is quiet; a thread quiet for minutes drifts out from its ring and dims, so a stuck agent stands out.
- **Needs you:** A thread waiting on its owner leaves the halo: T3boii holds its orb out in both hands, bouncing, the orb pulsing amber with a `!`, and his eyes go from you to it and back. Its trail reads "needs you" in amber. Clicking the orb opens the thread. Further waiting orbs bob in a row below it.
- **Failure:** A thread that fails makes him flinch. Its orb cracks and turns to red glass, the whole sphere, its icon and its logo tinted red, and stays just outside its ring, and he frowns at it, glancing back now and then, until you look at it (hover it a moment, or click it). Then it greys, sinks and fades. It stays until seen even after its thread has gone, for up to ten minutes.
- **Limits:** When a provider refuses work for a rate or usage limit (T3 ends the run with an error such as "Usage limit reached", "You've reached your 5-hour usage limit" or "Selected model is at capacity"), T3boii cries: tears well at his lower lids and run glassy down his cheeks, leaving a wet streak, and drip off; he sobs with little shudders, his lids droop, his mouth turns down in a trembling pout and he slumps, for a few seconds. Then he stays glum (heavy lids, a frown, eyes low, now and then a tear) until the limit clears: the provider is seen working again, the time it gave passes, or ten minutes go by with no new refusal. Each thread it refused dies where it is: its orb darkens to a dark glass ball under a big copy of the provider's logo, then is eaten away from within, a violet ember rim running ahead of the hole, while dark glossy chips crumble off it and fall; the logo goes last. Its satellites go with it. It stays gone unless its thread comes back working. He cries once per limit, however many threads hit it.
- **Activity trails:** What each thread is doing trails behind its orb like a comet's tail: soft glowing words laid along the path the orb has just flown, clearly legible at the orb and fading toward the tail, from its newest activity ("reading pet.js", "running swift build", "thinking…", or the start of what the agent said). Words always read left to right. A satellite's trail is shorter and a little fainter. Hover an orb and its trail lights up and he looks at it; a waiting thread's trail is amber, a failed one's red. Every half-minute or so he glances at one of his threads on his own. There are no speech bubbles or tooltips.
- **Emotes:** Idle, he stares blankly ahead, and now and then looks around, stretches or hops. A new agent makes the T3 on his forehead glow and send out rings, and the orb floats out of it. A finished agent (gone from two polls in a row, about five seconds) is sucked in: his lips purse into a round O, spirals of air stream into his mouth, he gulps, then grins a lopsided grin. When the last agent is gone, he does a short dance with a spin.
- **Workload:** With many threads going he concentrates: he blinks more, his eyes dart between orbs, he breathes faster, and he floats a little lower, as if carrying them.
- **Sleep:** Left alone with no agents for about 75 seconds (half that late at night), he yawns, then nods off: his lids close, his head droops, he breathes slow and deep, and Zs float up. After a while asleep, he drools. The mouse coming close, a pet, or a new agent wakes him with a start, and he has a big stretch.
- **Time of day:** Late at night he is a little dimmer and drowsier, his eyes glow less and he bobs more slowly; in the morning he is a touch brighter.
- **Gaze:** His eyes follow the mouse while it moves; otherwise they follow his orbiting agents, the orb he is talking about, or a failed orb he is frowning at.
- **Eyes and lids:** His eyelids always wrap over the outside of his eyes, and his eyes turn less while his lids are lowered, so no squint, blink, drowsy droop, grin, dance or gaze lets an eye show through a lid, and a blink closes fully. The eye glow only lands on bare eye. When his mouth lights up, the light comes from the dark inside of his mouth, never his lips.
- **Power:** The more agents orbit, the higher he floats and the rounder he swells. Threads and subagents count the same. With a few going his eyes look normal; from 5 they start to glow, and from 15 they are white right across. His mouth stays dark until 20, the most he can hold: then it opens a little and heavenly light pours out of it, god rays fanning across his face from a warm glare between his lips.
- **Touch:** Stroking him with the mouse or clicking him pets him: he squints, smiles, blushes and leans in; after a second of stroking, hearts pop out. Dragging him carries him, shaking him while carried makes his limbs flop, and shaking him hard spins him right round, leaving him dizzy with stars circling his head.
- **Sounds:** Playing with him makes quiet, non-verbal sounds, never words, and never shrill: everything is deep, soft and roomy, like a big soft creature in a large space. A low warm purr-hum while stroked, a muffled low bloop per heart, a soft bassy thud on a click, a low whoomp when picked up, a cushioned thud when let go, a low rubbery wub when shaken, a dark airy whoosh as he spins and a woozy low drone while dizzy, a soft low hum swell on hovering an orb, and a drowsy murmur if the mouse wakes him. While the mouse rests on him or one of his orbs, his own animations are heard too, in the same deep style: a low swell as a new orb glows out of his forehead, a dark inward rush as one is sucked in and a soft gulp after, a dull thunk and groan when a thread fails, a patient low hum as he holds out a waiting orb, a padded bass groove for the all-done dance, a deep yawn, a slow snore with the Zs, a soft bloop per drool drip, a whoomp for a stretch, and dark sniffles and a low quivering whimper when he cries over a limit. At most two of these play at once, each has its own cooldown, and they fade out quickly when the mouse leaves; with the mouse elsewhere he is silent. The clips are low-passed below about 3 kHz and given a reverb tail. Each sound has its own cooldown, never overlaps itself, and varies slightly in level and only downward in pitch. **T3boii sounds** in the Subscription Usage card's gear menu turns them off.
- **Motion:** At rest he breathes, blinks and floats at no more than 30 fps; flights, petting and dragging run at 60 fps. Rendering pauses when the pet is covered or the screen sleeps.
- **Reduce Motion:** The pet honours the system Reduce Motion setting: flights become fades, rings stand still, limbs do not flop, there are no sparks, wind, hearts, Zs, drool, fidgets or spins, the mouth light holds still and he does not glance about unprompted, and the dance is a small sway. Crying over a limit is a sad face with tears that only well and fade, no sobbing shudder; a dying orb only darkens under its logo and fades, with no dissolve or chips.
- **Demo mode:** `scripts/demo.sh` (a Darwin notification, `local.codex.LocalModelWidget.demo`) plays a ~44 s scripted show for screen recordings, built only from the behaviour above: asleep (Zs, drool, a drip), woken (startle, stretch), threads and subagents glowing out of his forehead with activity trails, now and then one swallowed, one held out waiting, one failing and retried, a build to 20+ (white eyes, light from his mouth), Codex hitting its limit (he cries, three Codex threads and a Codex subagent dissolve under its logo, the light goes out), then swallowed back in waves and the all-done dance. `scripts/demo.sh limit [provider]` (`….demo.limit[.<provider>]`; `window.t3boii.debug.limit(provider)`) fakes just a limit on the real orbit: that provider's orbs (default: the provider with the most) dissolve and he cries; nine seconds later the real orbit comes back. It uses the owner's real projects with their resolved icons (`DemoProjects`), ignores real snapshots and the mouse while it runs, plays his animation sounds without needing the mouse on him, and holds off fidgets, then hands the orbit back to the real threads. Petting and shaking are left for the owner to record by hand. `window.t3boii.demo(false)` stops it.

This motion is the one allowed exception to "no decorative motion"; no card animates for decoration.

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
