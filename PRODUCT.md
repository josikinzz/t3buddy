# Product

## Register

product

## Users

The primary users are the people who use this Mac. This machine is an AI-running and agent-running workstation, and these widgets exist as local controls for that environment. This is a private desktop utility, not a public product, so the interface should assume local context and avoid marketing language, onboarding theater, or broad-audience explanation.

Users are likely running coding agents in T3 Code and local models (Bonsai, Magnitude, Ollama) while doing other work on the machine. They need quick awareness of which agents are running or waiting on them, which model is loaded, how much of each subscription is used, whether memory pressure is high, and which processes are consuming the most memory, with low-friction actions (unload a model, force quit a process) that need no terminal.

## Product Purpose

Local Model Widget is a companion heads-up display for T3 Code: one transparent desktop-level dashboard of compact cards plus a desk pet. The cards are:

- **Local Models:** the model currently loaded on Bonsai, Magnitude or Ollama, with an Unload button.
- **Subscription Usage:** plan, 5-hour, weekly and monthly quota use for Claude, Codex and Kimi accounts found on this machine.
- **Process Memory:** unified memory use and the heaviest processes, each with a Force Quit action.
- **Tokens:** today's token total and a 7-day per-provider graph read from local Claude Code, Codex and Kimi session logs.

T3boii, the desk pet, shows every active T3 Code thread and subagent (read over T3 Code's MCP server) and Grok Bot's live work as orbs around him. Success means the family feels like part of macOS: calm, glanceable, trustworthy, and easy to ignore until needed.

## Brand Personality

Quiet, native, practical.

The product should feel like a small system utility: restrained, legible, and direct. Its tone should be plain and useful, with no attempt to sound like a public SaaS product or branded assistant.

## Anti-references

Do not make this feel like a web app squeezed into a Mac panel. Avoid flashy gradients, oversized hero-style typography, gamer or terminal themes, decorative illustrations, glassy spectacle, heavy branding, and novelty controls that fight macOS conventions.

Avoid public-product framing such as marketing copy, onboarding tours, feature explainers, testimonials, pricing-style layouts, or personality-forward empty states.

## Deliberate Exceptions

Two parts of the desktop dashboard break the anti-references above on purpose, because the owner asked for them. DESIGN.md documents their limits.

- **Today's token total** is one large numeral on the Tokens card, so it reads from across the room.
- **T3boii,** the desk pet, floats freely with no box and shows each active agent as an orb on a halo around him. He shows agent activity through his own body: spawning, sucking in finished agents, dancing when they are all done, powering up as more agents run, holding out a thread that needs you, frowning at a cracked orb when a thread fails, with what each thread is doing trailing behind its orb in faint glowing words. His eyes follow the mouse and his agents; left alone, he fidgets, yawns and falls asleep. He can be petted, shaken and spun. His motion idles at a low frame rate, pauses when covered or asleep, and honours Reduce Motion.

## Design Principles

1. Feel native before feeling distinctive.
2. Optimize for glancing, not browsing.
3. Keep model state, memory pressure, and top memory consumers visually clear.
4. Prefer system controls and familiar macOS interaction patterns.
5. Keep direct actions obvious, especially destructive actions like Force Quit.
6. Stay compact without hiding important state.

## Accessibility & Inclusion

Follow normal macOS accessibility expectations: readable contrast, clear focus behavior where practical, sensible VoiceOver labels for interactive controls, and reduced-motion-friendly state changes. Color should not be the only signal for loaded, idle, pending, disabled, warning, destructive, or error states. Force Quit actions should include the target app name in the accessible label.
