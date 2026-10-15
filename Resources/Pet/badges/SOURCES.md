# Provider badge sources

Each badge is the vendor's mark, unmodified, on a transparent background as in T3 Code (marks drawn in black are white here so they read on the desktop). The file name is the
T3 driver id the orb's `provider` carries; anything unknown uses `generic.svg`. `grokBot.png` is the
one non-T3 badge: Grok Bot orbs carry provider `grokBot`, while T3's own `grok` threads keep `grok.svg`.

| File | Mark | Source | Licence |
|---|---|---|---|
| `codex.svg` | OpenAI blossom, white | `@lobehub/icons-static-svg@1.95.1` `icons/openai.svg` | MIT (lobe-icons) |
| `claudeAgent.svg` | Claude spark, tinted `#d97757` (T3's Claude tint) | `simple-icons@16.35.0` `icons/claude.svg` (source: claude.ai) | CC0-1.0 |
| `grok.svg` | xAI mark, white | `@lobehub/icons-static-svg@1.95.1` `icons/xai.svg` | MIT (lobe-icons) |
| `antigravity.svg` | Google Antigravity mark, full colour | `@lobehub/icons-static-svg@1.95.1` `icons/antigravity-color.svg` | MIT (lobe-icons) |
| `cursor.svg` | Cursor cube, white | `simple-icons@16.35.0` `icons/cursor.svg` (source: cursor.com/brand) | CC0-1.0 |
| `opencode.svg` | OpenCode mark, white | `simple-icons@16.35.0` `icons/opencode.svg` (source: opencode repo `packages/identity/mark.svg`) | CC0-1.0 |
| `pi.svg` | Pi mark, white | `simple-icons@16.35.0` `icons/pi.svg` (source: pi.dev favicon) | CC0-1.0 |
| `kimi.svg` | Kimi mark, white (T3 reports a `kimi` provider instance) | `@lobehub/icons-static-svg@1.95.1` `icons/kimi.svg` | MIT (lobe-icons) |
| `grokBot.png` | Grok Bot app icon (white ball with two black eyes on a dark squircle), 128 × 128 PNG; also the face of the inflight Grok orb | `/Applications/Grok Bot.app/Contents/Resources/icon.icns` (bundle `com.anysphere.sand`), `icon_128x128@2x.png` (256 px) | Grok Bot's own app icon |
| `generic.svg` | Unbranded four-point spark | Drawn for this widget | — |

simple-icons dropped OpenAI and carries no xAI or Antigravity mark, so those come from
lobe-icons, which redraws each vendor's published mark. The marks remain the vendors'
trademarks; they identify which provider runs a thread and imply no endorsement.

To regenerate: `npm pack simple-icons@16.35.0 @lobehub/icons-static-svg@1.95.1`, unpack each
into its own empty directory, and wrap the listed `icons/*.svg` path data in a 32 × 32 viewBox
(the mark at 28 × 28, offset 2, no backdrop).

To regenerate `grokBot.png`: `iconutil -c iconset "/Applications/Grok Bot.app/Contents/Resources/icon.icns" -o <empty dir>/icon.iconset`,
take `icon_128x128@2x.png`, find the squircle's opaque bounds (204 px square at 26,26), trim 3 % of that side from
each edge (a centred 192 px square, which drops the transparent margin and the squircle's rim so the art fills a
circle), and scale it to 128 × 128 with CoreGraphics. The artwork is otherwise unchanged; the page clips it round.

## T3boii character

`../T3-rigged.glb` is the original T3boii character, not a provider mark: Design by maria_rcks ([@maria_rcks](https://x.com/maria_rcks) on X), model by Meshy, animated by Sol 6.1 and Opus 5.5.
