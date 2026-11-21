# Changelog

These unpublished Android previews use NetHack 5.0.0 and Godot 4.7.1.
Entries identify individual builds while the app version remains 0.1.0.

## 0.1.0 — Camera controls — 2026-11-21

Commit: [`7a7416b`](https://github.com/ricardobusta/nethack-mobile/commit/7a7416b).

### Changes

- Automatically center the player when entering another floor or dungeon
  branch, including when camera following is disabled.
- Use the saved **Follow: On/Off** toggle to center on every player move.
  With Follow on, manual panning lasts until the next move.
- Use **Center** to recenter once without changing Follow. Centering keeps
  the current zoom; targeting and ordinary redraws preserve a panned view.

### Verification

- Native host checks and all nine Godot UI regressions pass.
- The rebuilt debug APK passed signature and alignment checks and was
  installed and launched on the Android emulator.

## 0.1.0 — Mobile HUD and postmortem flow — 2026-11-20

Commit: [`a922853`](https://github.com/ricardobusta/nethack-mobile/commit/a922853).

### Mobile interface

- Show HP and Power in read-only bars with exact values, alongside hunger,
  encumbrance, and condition badges.
- Open character attributes and equipment from the top-left player portrait.
  Access Inventory from its own shortcut or the Character/Inventory tabs.
- Show item appearance icons, stack quantities, equipment state, and known
  names. Item details use the engine's available actions and discovery rules.
- Support inventory quantities and multiple selections, with nested Back
  navigation and no turns spent browsing information.
- Add reusable resource bars, a message log, and a modal host that work with
  the existing scalable mobile controls.
- Fill the viewport with modal backdrops while keeping content within the
  usable area.
- Arrange landscape gameplay as **log | map | actions**, with independently
  scrollable side panels and a larger central map.
- Display the latest message in white and older messages in gray. Scroll
  to the end of wrapped messages so their final lines remain visible.
- Add an original teal shield app icon with a silver rim, crossed axes,
  and a white **@**.

### Session reliability and PC flow

- Preserve immediate, silent resume for living games while treating
  postmortem sessions separately.
- Preserve pending death disclosures, report pages, and scroll position
  across backgrounding without attempting to save the dead character.
- Keep a versioned, atomic, read-only **Last run** report that can reopen
  after process termination. Leaving the report returns to Characters.
- Recover safely from corrupt reports and allow starting another character
  after death.
- Retain upstream character confirmation, introductions, tutorial choices,
  item actions, numeric answers, and postmortem disclosure choices.
- Add engine lifecycle, outcome, character, equipment, and item metadata
  events while preserving worker-thread access and stale-input rejection.

### Verification and availability

- Native checks and eight Godot UI regressions cover death disclosures,
  report recovery, resources, item privacy, quantities, and navigation.
- Compare the port with the vendored NetHack 5.0.0 PC flow and document
  Android emulator checks for phone/tablet layouts and postmortem behavior.
- Physical-device acceptance remains pending. iOS builds are deferred.

See [mobile validation](docs/MOBILE_VALIDATION.md) and the
[PC flow comparison](docs/PC_FLOW.md) for coverage and limitations.
