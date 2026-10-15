#!/bin/sh
# Plays T3boii's scripted demo (about 43 s) in the running app, for screen recordings.
# The app listens for this Darwin notification (PetDemoTrigger); nothing goes over the network.
# Run it again to restart the demo from the top.
exec notifyutil -p local.codex.LocalModelWidget.demo
