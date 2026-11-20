# Mobile HUD and postmortem validation

The implementation uses the vendored NetHack 5.0.0 engine and Godot 4.7.1.
The PC reference comparison is in [PC_FLOW.md](PC_FLOW.md). Physical-device
acceptance remains the owner's later testing step.

## Reproduce the automated checks

```sh
python3 scripts/build.py host
python3 scripts/test_ui.py
python3 -m unittest discover -s tests -v
```

The UI runner imports generated textures first, runs tests sequentially, checks
their completion messages, and fails on script errors even when Godot exits zero.

| Requirement | Verification |
| --- | --- |
| Worker lifecycle and stale requests | Native smoke exercises copied events, stale-response rejection, 265 command boundaries, save/restore, process-kill checkpoint recovery and save failure. |
| Actual death during disclosures | Native death run backgrounds every disclosure prompt. A second run is killed at a disclosure; the native entry point refuses its retired directory. No dead-game save is confirmed. |
| Postmortem UI and journal | `postmortem_smoke.gd` covers unchanged pending controls, versioned atomic report round-trip, corrupt/unsupported report recovery, cold opening, dismissal and reopening. Normalized outcomes update the report without replacing pages. |
| Death followed by another character | `death_smoke.gd` drives a real character to death, preserves each pending page across pause/resume, reopens the journal without a worker, and starts a fresh run with the same name. |
| Resource values and conditions | `widget_smoke.gd` checks exact current/max values, zero maxima, active polymorph-style HP updates, hunger/condition badges, and large resource values with enlarged text. Resources use read-only ProgressBars. |
| Character, equipment and private item data | `character_smoke.gd` checks engine identity/equipment snapshots, appearance tiles, stack counts and upstream actions. A native worker-only fixture verifies an intentionally unidentified potion hides its true type and blessing state, then confirms those appear when identified. The fixture is excluded from distributed bridges; supplemental values contain no hidden properties. |
| Counts and multiselection | `menu_smoke.gd` operates the actual widgets and checks response payloads: preselection, multiple stacks, count retention, whole stacks, command-specific counts, and complete numeric yes/no answers including zero. Native numeric checks cover invalid input and long overflow. |
| Browsing and Back | Native inventory stress and the character UI test verify unchanged turn counts while browsing. Real Android Back was checked from details to Inventory and Inventory to gameplay. Automatic Back-to-exit is disabled. |
| Touch scrolling | `scroll_smoke.gd` checks dragging over controls/text, inertia, boundaries, stopping a fling, stationary taps and horizontal shortcuts. Landscape log/actions have separate scroll owners. |
| Wrapped log text | `log_smoke.gd` checks latest-white/previous-gray rendering, literal engine text, and bottom following after wrapping at phone/tablet sizes and 100%/150% text. |
| Modal bounds | Widget tests cover phone/tablet portrait/landscape, enlarged text, full-viewport backdrop, constrained content, and simulated cutout/keyboard exclusions. Informational modals reject stray gameplay keys and map taps. |
| Silent living-game resume | `ui_smoke.gd` checks both save-before-foreground and foreground-before-save orderings, with no confirmation screen or restore greeting. It also checks bundled-asset refresh preserves saved games. |

## Android emulator checks

The isolated API 36 arm64 touch emulator has no hardware keyboard. Checks include
native text and number keyboards, 1080×2400 at 420 dpi, and a 2400×1600 tablet
viewport at 320 dpi, in both orientations with 100% and enlarged text. The tall
cutout overlay reports real Android safe-area insets; the content stays inside
them while the modal backdrop fills the viewport.

The emulator exercised creation confirmation, the upstream introduction and
tutorial choice, sprite/ASCII rendering, character and inventory tabs, engine
item actions, nested Back, and landscape side panels. Postmortem verification
retained the pending disclosure across Home/foreground, completed ten disclosure
pages, retained the final journal across backgrounding, force-stopped the process,
and reopened the same read-only journal. The retired run's save directory was
empty. Dismissal persisted, and reusing its name created a separate run directory.

The validation bundle contains revised screenshots, the terminal PC transcript,
test logs and Android report evidence. APK/AAB metadata and native bridge markers
are checked against the committed revision when packaging the corresponding
source archive. The debug APK and unsigned AAB are test artifacts; signing,
publication and physical-device acceptance are separate release steps.
