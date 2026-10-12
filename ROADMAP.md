# Flow roadmap

Flow reshapes your Mac around what you are doing. Pick a mode (Deep Work, Study, Plan, Browse, Chill, Meeting, Creative) and Flow changes the wallpaper, appearance, Dock, volume, apps and Focus, then puts everything back.

## Done, end to end
- **App:** a window (mode list, mode editor, History) plus a menu bar popover. Native SwiftUI; the window uses system sidebar, toolbar and materials.
- **Modes:** seven starter modes, each saved as data and fully editable: name, tagline, symbol, wallpaper, light/dark, accent colour, apps to hide, apps to open, Dock, volume, Focus shortcuts, restore on exit.
- **Sessions:** start, pause, end, discard. A count-up timer, recorded in History (sessions under 5 seconds are not recorded). Menu bar commands with Option-Command 1 to 9.
- **Wallpapers:** 35 curated 4K images, five per mode, from Wikimedia Commons with license and credit for each. They download on demand and are checked by hash.
- **What a mode changes on the Mac:** wallpaper, light/dark, Dock auto-hide, volume, hide apps, open apps, and a Focus through your own shortcuts. All of it is undone when the session ends.
- **Safety:** each change is saved before it is made, only changes Flow can put back, and only undoes what is still Flow's. If you change something yourself mid-session, Flow leaves it. Crash and quit recovery. Wallpapers are handled per Space.
- **Review before first start:** a mode lists exactly what it will change and waits for your OK, again after edits.
- **Tests:** 58 unit tests on the core logic (`Packages/FlowCore`).

## Known gaps in what exists
- The editor is one long form. Modes are not yet customised in depth (see Next).
- Session panel parts (timer, priorities, sound, quick note) can be toggled and saved, but there is no on-screen panel yet, and no priorities list or notes exist.
- Keyboard shortcuts work only while Flow is the front app. There are no global hotkeys.
- Triggers by time or by the app you open are not built, nor the start animation or HUD.
- No sound or music. No stats beyond the History list.
- No app icon, the bundle identifier is a placeholder, and there is no licence or release pipeline.
- Window tiling and the macOS accent colour are not implemented.

## Next
1. **Floating panels (the foundation for the rest).** Small panels that float above everything, can be dragged and remember where they were, appear on every Space and over full-screen apps, and are switched on per mode.
2. **Meeting mode: a floating notepad.** A notepad beside the call. What you type saves into Apple Notes as you type (one note per meeting). Apple Notes has no direct API, so this goes through scripting and needs a one-time macOS permission.
3. **Music mode (a new mode).** A floating mini player that stays on top of every window, including full-screen apps, controlling the Music or Spotify app you already use. Spotify login for playlists comes later.
4. **Deeper per-mode customisation.** Each mode gets its own list of components, each with its own settings, instead of one shared form. The two items above become components, along with the timer, priorities and sound.

## Later
Global hotkeys, automatic modes by time or by app, start animation and HUD, ambient sounds, stats and gentle goals, window tiling, live wallpapers, app icon, signed and notarised releases on GitHub.

## Open questions
- What should each existing mode get beyond apps and themes? (Per-mode ideas wanted; see Next 4.)
- Which licence?
