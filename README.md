# Ambit

> **Git is the source of truth for this project.** The repository on GitHub (`deepanshu946/ambit`) holds the real, current code and docs. Everything is committed and pushed there; any copy on a laptop is a working copy. If a copy and the repository disagree, the repository wins.

Create the environment you want to work in. A native macOS app: pick a mode (Deep Work, Study, Plan, Browse, Chill, Meeting, Creative, Music) and Ambit shapes your Mac around it.

**Status:** early. Modes are editable (wallpaper gallery, apps to hide or open, Dock, volume, Focus shortcut, look) and sessions are timed and recorded. Starting a session changes your Mac and ending it puts everything back: wallpaper, light/dark appearance, Dock auto-hide, volume, hidden apps, opened apps, and a Focus (through your own shortcuts).

## Build
- Xcode 27, macOS 26+ target.
- `open Ambit.xcodeproj` and run, or `xcodebuild -scheme Ambit build`.
- Logic tests: `cd Packages/AmbitCore && swift test`.

## Layout
- `Ambit/` the SwiftUI app (windows, menu bar, views).
- `Packages/AmbitCore/` models, session clock, storage. No UI, fully tested.
- `Wallpapers/` curated 4K wallpaper manifest and fetch script (images are downloaded, not committed).

Ambit is not sandboxed: changing the wallpaper, hiding apps and setting the Dock need system access. Builds are ad-hoc signed; open them with right-click → Open.

## Wallpaper swapping: what it does and its limits
- Ambit saves what is on your desktop **before** changing anything, and puts it back when the session ends, when you quit, or at the next launch if Ambit ever closed badly.
- It only changes a wallpaper it can prove it can put back. A picture managed by another app (for example Unsplash Wallpapers, which keeps files in its own protected container) can't be restored, so Ambit leaves it alone and says so. Pick a photo in System Settings > Wallpaper to use the feature.
- macOS keeps a wallpaper **per Space** and only lets an app read and set the current one. Ambit changes the desktop you are on when the session starts. If you end the session from another Space, Ambit waits and restores the first one when you return to it. It never writes your original onto the wrong Space.
- A second wallpaper manager (an app that rotates pictures) will fight Ambit for the desktop.
- Dev: `AMBIT_WALLPAPER_DIR` (use already-downloaded images), `AMBIT_STATE_DIR` (keep a test run away from your real modes and history), `AMBIT_SELFTEST=1` (Debug builds only: drives real sessions and checks the desktop after each step).

## What a mode can change, and how it stays safe
Every change follows the same rules, in code and in tests: it is saved to disk **before** it is made, only things Ambit can put back are changed, and only a change that is still Ambit's gets undone. If you change something yourself during a session, Ambit leaves your change alone.

| Change | How | Notes |
|---|---|---|
| Wallpaper | NSWorkspace | see the section above |
| Light / Dark | System Events | not done if your Mac is on Auto appearance |
| Dock auto-hide | System Events | macOS asks once whether Ambit may control System Events |
| Volume | CoreAudio | only on an output that allows it; restores onto the same output device |
| Hide apps | NSRunningApplication | never quits anything; only unhides apps Ambit hid |
| Open apps | NSWorkspace | not undone: Ambit never quits apps |
| Focus | the Shortcuts app | macOS has no Focus API, so a mode names one shortcut that turns a Focus on and one that turns it off |

- **Review before the first start.** A mode that changes the Mac lists exactly what it will do and waits for your OK. It asks again whenever those changes are edited.
- **Not built:** window tiling and changing the macOS accent colour.
- **Live tests (Debug builds):** `AMBIT_SELFTEST=wallpaper|apps|events`. Launch with `open -n --env ...` so macOS treats Ambit, not your shell, as the app asking for permission.

## Development
- **Workflow:** round robin, one mode at a time. Each turn adds one or two features to one mode, then moves to the next mode (plan in [ROADMAP.md](ROADMAP.md)). Within a turn, one feature at a time. A feature is built, compiled and unit-tested, then handed to the owner, who tests it in the real app and sends review notes. Fixes and the next feature follow from that review. Nothing is called done until the owner has tried it.
- **Commits:** small and described in plain words. `main` is always the latest working state.
- **Status and plans:** see [ROADMAP.md](ROADMAP.md).
- **Design skills (optional, not in this repo):** while developing with Claude Code, two MIT-licensed skills were used for macOS design and SwiftUI correctness: [apple-hig](https://github.com/ebuntario/apple-hig) and [swiftui-expert-skill](https://github.com/AvdLee/SwiftUI-Agent-Skill). Install them into `.claude/skills/` if you want the same guidance; that folder is git-ignored.
- **License:** not chosen yet. Choose one before making the repository public.
