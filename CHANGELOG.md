# Changelog

## 0.1.0 — Android preview — 2026-11-21

This preview uses NetHack 5.0.0 and Godot 4.7.1. It is an unpublished test
build for Android phones and tablets.

### Gameplay and camera

- Play the original NetHack engine with ASCII or upstream tile graphics.
- Use touch movement, travel, targeting, a direction pad, virtual keys, and
  a searchable command browser with customizable action shortcuts.
- Automatically center the player when entering another floor or dungeon
  branch, including when camera following is disabled.
- Use the saved **Follow: On/Off** toggle to center on every player move.
  With Follow on, manual panning lasts until the next move.
- Use **Center** to recenter once without changing Follow. Centering keeps
  the current zoom; targeting and ordinary redraws preserve a panned view.

### Mobile interface

- Show HP and Power in read-only bars with exact values, alongside hunger,
  encumbrance, and condition badges.
- Open character attributes and equipment from the top-left player portrait.
  Access Inventory from its own shortcut or the Character/Inventory tabs.
- Show item appearance icons, stack quantities, equipment state, and known
  names. Item details use the engine's available actions and discovery rules.
- Support inventory quantities and multiple selections, with nested Back
  navigation and no turns spent browsing information.
- Scale reusable touch controls and readable text for phone and tablet
  resolutions, enlarged text, safe areas, and software keyboards.
- Drag scrollable lists directly over their text and controls.
- Fill the viewport with modal backdrops while keeping content within the
  usable area.
- Arrange landscape gameplay as **log | map | actions**, with independently
  scrollable side panels and a larger central map.
- Display the latest message in white and older messages in gray. Scroll
  to the end of wrapped messages so their final lines remain visible.
- Add an original teal shield app icon with a silver rim, crossed axes,
  and a white **@**.

### Session reliability and PC flow

- Resume living games immediately and silently after backgrounding.
- Preserve pending death disclosures, report pages, and scroll position
  across backgrounding without attempting to save the dead character.
- Keep a versioned, atomic, read-only **Last run** report that can reopen
  after process termination. Leaving the report returns to Characters.
- Recover safely from corrupt reports and allow starting another character
  after death.
- Retain upstream character confirmation, introductions, tutorial choices,
  item actions, numeric answers, and postmortem disclosure choices.
- Include checkpoint recovery, stale-input rejection, and save-failure
  reporting.

### Verification and availability

- Native host checks and all nine Godot UI regressions pass.
- The latest debug APK passed signature and alignment checks and was
  installed and launched on the Android emulator.
- Physical-device acceptance remains pending. iOS builds are deferred.

See [mobile validation](docs/MOBILE_VALIDATION.md) and the
[PC flow comparison](docs/PC_FLOW.md) for coverage and limitations.
