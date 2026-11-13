# Security policy

## What the mod does on your machine

The mod runs inside Baldur's Gate 3 through the Script Extender. It:

- reads game state (flags, journal, approval) through the Script Extender;
- writes one settings file, `Script Extender/CompanionRoadmap/settings.json`, in your BG3 user folder;
- stores manual check-offs inside your savegame;
- exchanges messages only between the game's own server and clients (relevant in multiplayer).

It makes no internet connections and runs no external programs.

The developer tools in `tools/` run LSLib's `Divine.exe` on your machine to read your local game files into `tools/.cache/`. They never upload anything.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please report security problems privately with GitHub's **Report a vulnerability** button on the repository's *Security* tab, not in a public issue. Include the steps to reproduce it and your mod and Script Extender versions.
