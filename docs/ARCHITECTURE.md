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

READY events copy the engine's dungeon and level identifiers with a validity
flag. The map recenters on a new session or changed level identity, including
stairs, portals and branch changes at the same depth; ordinary map redraws
preserve its view. Center is one-shot. The saved Follow toggle centers on player
movement, while allowing temporary panning until the next move. Targeting cursors
and repeated player-position events do not undo a pan. Centering aligns the
player tile's center with the viewport center and preserves zoom.

All UI scroll areas share `mobile_scroll.gd`. Touch gestures belong to the
scroll area before its children receive input, so dragging buttons, text fields,
quantity controls or labels moves the whole list. Stationary taps use normal GUI
dispatch; swipes suppress item activation, coast after release, and stay within
the content bounds. Touching a moving list stops it without activating a row.
Mouse wheels, keyboard focus and scrollbar dragging retain Godot's behavior.

The gameplay message log renders the latest message in white and previous
messages in gray. It follows the scroll bottom after container layout and text
wrapping finish, including rotation and text-size changes. Engine text is added
literally rather than interpreted as markup. Informational modals block keyboard
commands and map taps; actual engine prompts and direction/key controls retain
their input behavior. Android Back is handled by modal navigation, with Godot's
automatic Back-to-exit behavior disabled.

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

The additive phase event reports starting, playing, suspended, postmortem, ended
and error. `really_done` copies the engine outcome and formatted cause before
disclosures; neither the worker nor the UI guesses death from message text.
Postmortem suspension is ignored on both sides of the bridge. The worker keeps
its request ID while the UI keeps its controls and scroll position.

Before publishing postmortem, the worker atomically writes `.mobile-ended` in
the run directory. The native entry point refuses retired directories, including
ones with old live recovery checkpoints. Starting that name again chooses a
fresh `-run-N` directory; previous files are retained. This guard is independent
of the UI report, so report corruption cannot enable a dead-character restore.

`end_report.gd` atomically replaces a versioned UI-only JSON journal containing
the outcome, cause, disclosed pages, last page and scroll offsets. Cold launch
opens an undismissed report without starting an engine. Characters dismisses it;
Last run can reopen it. Invalid/unsupported journals fall back to Characters.
The journal is not a game save. Like upstream checkpoints, filesystem writes
cannot guarantee recovery from arbitrary storage failure or power loss.

Copied character/equipment events are refreshed at command boundaries. Menu
glyph, known item and menu-context events augment existing menus without
changing their indices. The item detail page renders upstream `itemactions`;
canceling and reopening inventory consumes no turns. Numeric responses preserve
PC `yn_number` semantics, including zero and the platform's long limit.

`ui/modal_host.gd` owns a full-viewport input shield. Its panel alone receives
safe-area, maximum-width and keyboard bounds. Resource bars are read-only
ProgressBars. Landscape uses independently scrolling log and action sidebars at
roughly 20% and 16% of viewport width (bounded to 130–280 and 120–200 logical
pixels at normal text size; minimums grow with enlarged text), with remaining
space for the map. Compact portrait combines shortcuts
into one horizontally scrolling row to preserve the map at enlarged text sizes.

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
