#!/bin/sh
# Plays T3boii's scripted demo (about 44 s) in the running app, for screen recordings.
# The app listens for this Darwin notification (PetDemoTrigger); nothing goes over the network.
# Run it again to restart the demo from the top.
#
#   scripts/demo.sh                   the demo
#   scripts/demo.sh limit [provider]  a made-up rate limit on the real orbit: he cries and that
#                                     provider's orbs dissolve (default: the provider with the most orbs)
name=local.codex.LocalModelWidget.demo
if [ "$1" = limit ]; then
  case "${2:-}" in
    "") exec notifyutil -p "$name.limit" ;;
    codex|claudeAgent|cursor|grok|grokBot|kimi|opencode|pi|antigravity) exec notifyutil -p "$name.limit.$2" ;;
    *) echo "unknown provider: $2 (codex, claudeAgent, cursor, grok, grokBot, kimi, opencode, pi, antigravity)" >&2; exit 64 ;;
  esac
fi
exec notifyutil -p "$name"
