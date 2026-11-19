# Architecture and upstream maintenance

## Boundaries

- `vendor/nethack` is the pristine stable release pinned in `upstream.lock.json`.
  `patches` contains dated changes for mobile paths, session status reset, and
  named status fields. Builds never modify the vendor tree.
- The host generates monster/object headers, game data, the DLB archive, and
  release-matched glyph/tile mappings. The atlas converter uses the standard
  text tile sources, in the same monsters/objects/other ordering as upstream.
- The native build compiles upstream core sources listed in its Makefile,
  Lua, and the Unix platform entry point. The older libnh entry point has
  drifted from the current core; the maintained Unix entry point is renamed
  to `nhmain`, retaining upstream initialization and restore behavior.
- `native/mobile.h` is a Godot-independent C interface. One engine worker
  owns all NetHack state. Its window shim copies events into a bounded queue;
  no engine pointers or Godot objects cross threads. The C++ GDExtension
  exposes owned Dictionaries and Arrays to GDScript on the main thread.
- Prompt responses carry monotonically increasing request IDs. Stale or
  duplicate responses are rejected. Menus retain engine identifiers only on
  the worker; the UI sends entry indices and quantities.

## Platform and lifecycle

App-private absolute prefixes replace process-wide working-directory changes.
System configuration is resolved before early initialization. Terminal support,
shell commands, mail, and process signal handlers are excluded or adapted.
Engine exits return through the worker's termination boundary, not app exit.

The UI uses one displayed map for ASCII and tile rendering. No gameplay state
is reconstructed by the frontend. Travel, adjacent interaction, targeting,
inventory, and command availability come from the engine. UI gestures cannot
send taps for undisplayed/unexplored cells.

All UI scroll areas share `mobile_scroll.gd`. Touch gestures belong to the
scroll area before its children receive input, so dragging buttons, text fields,
quantity controls or labels moves the whole list. Stationary taps use normal GUI
dispatch; swipes suppress item activation, coast after release, and stay within
the content bounds. Touching a moving list stops it without activating a row.
Mouse wheels, keyboard focus and scrollbar dragging retain Godot's behavior.

The reusable scene library in `godot/ui/widgets` supplies action buttons, labeled
text/search fields with validation, numeric steppers and full-row toggles. A shared
theme sets typography, colors, spacing and touch sizes. Android uses a canvas in
density-independent units; changing resolution preserves readable physical text
and touch sizes. Forms cap their width on tablets, scroll above the keyboard, and
game action strips scroll horizontally on narrow screens. See `godot/ui/README.md`
for component contracts and verification commands.

Checkpoints are written only at top-level command boundaries, not inside
targeting, text, or menu prompts. On pause/suspend, incomplete prompts are
cancelled until the engine reaches a safe boundary, then upstream save runs.
Death and finished games are not saved as live games. Self-recovery preserves
checkpoint files and offers recovery after process termination.

Returning from normal app backgrounding automatically restores a successfully
suspended session without a confirmation screen or restore greeting. Restoration
waits for both the save to finish and the app to return to the foreground.
Explicit Save and suspend keeps its resume controls; save failures remain visible.

Upstream checkpoints are not transactional snapshots of the entire filesystem.
Interruption during a checkpoint or disk exhaustion still needs physical-device
fault testing. A failed save is reported; the UI must not claim a successful
suspension when the engine did not confirm one.

## Upgrades

Run the manual updater only when ready to review an engine upgrade. A staging
build gets its own temporary source, generated data, and native test directory.
Failed validation leaves the vendored source, lock, and current generated app
data intact. Import does not change application version numbers or publish.

Bundled support files carry a content digest. On an app update, the installer
refreshes those files atomically before starting the engine; saves, bones,
scores, and other runtime files are outside the bundle manifest and remain intact.

Save storage is namespaced as `engine-version-edit-level-mobile1`. Any port
change affecting save layout must increment `mobile1`. Older namespaces remain
on disk; automatic migration or loading with a different engine is unsupported.
Before shipping an incompatible upgrade, document the policy for unfinished
games and provide access to the matching older binary/source release.

## Future iOS port

Reuse the C engine protocol, GDScript screens, and app-private storage adapter.
Add an iOS static-library/XCFramework registration/export layer, lifecycle hooks,
signing configuration, and real-device acceptance. No iOS export is claimed by
the Android milestone. Godot 4.7 APIs and godot-cpp 10.0.0 are pinned explicitly;
the bindings now use an independent version series.
