# Ambit roadmap

Ambit reshapes your Mac around what you are doing. Pick a mode (Deep Work, Study, Plan, Browse, Chill, Meeting, Creative, Music) and Ambit changes the wallpaper, appearance, Dock, volume, apps and Focus, then puts everything back.

## How we work: round robin, one mode at a time
We go around the modes in turns. Each turn picks one mode, adds one or two features to it, the owner tests them in the real app and sends review notes, then we move to the next mode. When every mode has had a turn, we start again. Features that several modes share (such as floating panels) are built once, in the first turn that needs them.

**Order of the first round:** Meeting, Music, Deep Work, Study, Plan, Browse, Chill, Creative.

| Mode | Feature ideas for its turns (candidates, to be chosen together) |
|---|---|
| **Meeting** | Floating notepad that saves into Apple Notes as you type. Agenda from Calendar. Start by itself when a calendar event begins. A mic and camera reminder. A prompt at the end to save action items. |
| **Music** | Floating mini player that stays above every window, including full-screen apps. Controls the Music or Spotify app you already use. A default playlist per mode. Now playing in the menu bar. |
| **Deep Work** | Top-three priorities panel. Countdown or Pomodoro option. A "distraction jar" to jot a stray thought without leaving. Website blocking later. |
| **Study** | Reading timer and reading log. Breaks that start by themselves. Quick highlight and note capture. A warmer screen tint. |
| **Plan** | Daily plan on sticky notes. Time blocks from Calendar. Carry unfinished items over to tomorrow. |
| **Browse** | Tidy up other windows. A reading list. A time box with a gentle nudge ("20 minutes are up"). |
| **Chill** | Ambient sounds. Dimmer screen. A sleep timer that ends the mode by itself. |
| **Creative** | Floating reference board. An idea parking lot. Tool windows arranged for you. |

## Done, end to end
- **App:** a window (mode list, mode editor, History) plus a menu bar popover. Native SwiftUI; the window uses system sidebar, toolbar and materials.
- **Modes:** eight starter modes (Music is new and only has its settings so far; its floating player comes in its turn), each saved as data and fully editable: name, tagline, symbol, wallpaper, light/dark, accent colour, apps to hide, apps to open, Dock, volume, Focus shortcuts, restore on exit.
- **Sessions:** start, pause, end, discard. A count-up timer, recorded in History (sessions under 5 seconds are not recorded). Menu bar commands with Option-Command 1 to 9.
- **Wallpapers:** 35 curated 4K images, five per mode, from Wikimedia Commons with license and credit for each. They download on demand and are checked by hash.
- **What a mode changes on the Mac:** wallpaper, light/dark, Dock auto-hide, volume, hide apps, open apps, and a Focus through your own shortcuts. All of it is undone when the session ends.
- **Safety:** each change is saved before it is made, only changes Ambit can put back, and only undoes what is still Ambit's. If you change something yourself mid-session, Ambit leaves it. Crash and quit recovery. Wallpapers are handled per Space.
- **Review before first start:** a mode lists exactly what it will change and waits for your OK, again after edits.
- **Tests:** 58 unit tests on the core logic (`Packages/AmbitCore`).

## Known gaps in what exists
- The editor is one long form. Modes are not yet customised in depth (see Next).
- Session panel parts (timer, priorities, sound, quick note) can be toggled and saved, but there is no on-screen panel yet, and no priorities list or notes exist.
- Keyboard shortcuts work only while Ambit is the front app. There are no global hotkeys.
- Triggers by time or by the app you open are not built, nor the start animation or HUD.
- No sound or music. No stats beyond the History list.
- No app icon, the bundle identifier is a placeholder, and there is no licence or release pipeline.
- Window tiling and the macOS accent colour are not implemented.

## Open issues (start the next chat here)
1. **Sidebar goes blank after starting or switching to a mode** (reported with screenshots; fine on launch). Not reproduced here, and the window's structure looked correct with the owner's real modes. Changes made to remove the likely causes, **not yet re-tested by the owner**: sidebar rows now keep one fixed shape with a system "On" badge, the first-start review sheet is attached to the detail column instead of the whole split view, and each mode's screen is rebuilt fresh. If it is still blank: try a plain sidebar list style without the glass material, and look at whether the Meeting notepad panel or the review sheet is the trigger (the debug build's `AMBIT_DUMP=/path/out.txt` lists the window's views).
2. Always-visible fat scroll bars in screenshots are the Mac's own setting (System Settings > Appearance > Show scroll bars), not Ambit.
3. Meeting notepad is built but unverified in the real app: typing without leaving the call app, appearing over full-screen apps, the Notes permission, and a new note per session.
4. Dock/appearance, hide apps, volume and Focus effects are built and were live-tested only for hide apps, volume, Dock and appearance. Focus needs the owner's own shortcuts.

## Round one, in progress: Meeting
**Built, waiting for the owner's test:** the floating panel foundation (a draggable panel that floats above windows, follows you across Spaces, tries to sit over full-screen apps, and remembers where you left it) and the Meeting notepad on top of it. The notepad opens docked at the right edge when Meeting starts, can be switched on or off per mode in the editor, and saves into a new note per session in the "Ambit Meetings" folder in Notes (the folder is editable per mode). Text is kept in a local draft until Notes has it, and a draft left by a crash is saved at the next launch. Features added to a starter mode after release reach already-saved modes once (`PresetUpgrades`), so a later "off" is never undone.

**Not yet verified in the real app:** typing into the panel without leaving the call app, appearing over full-screen apps, and the macOS permission to control Notes. Next for Meeting after review: agenda from Calendar, start by itself when an event begins, end-of-meeting prompt.

## Next (round one)
1. **Floating panels** and 2. **Meeting notepad:** built, see above.
3. **Music mode's floating player.** The Music mode now exists as a starter mode. Its player stays on top of every window, including full-screen apps, and controls the Music or Spotify app you already use. Spotify login for playlists comes later.
4. **Deeper per-mode customisation.** Each mode gets its own list of components, each with its own settings, instead of one shared form. The two items above become components, along with the timer, priorities and sound.

## Later
Global hotkeys, automatic modes by time or by app, start animation and HUD, ambient sounds, stats and gentle goals, window tiling, live wallpapers, app icon, signed and notarised releases on GitHub.

## Open questions
- What should each existing mode get beyond apps and themes? (Per-mode ideas wanted; see Next 4.)
- Which licence?
