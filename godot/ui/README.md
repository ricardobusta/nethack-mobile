# Mobile UI components

Instantiate the scenes in `widgets/` instead of recreating inputs in screens.
Apply `mobile_theme.gd.create(text_scale)` to the screen root. Inputs inherit the
theme and update their touch dimensions when it changes.

| Scene | Contract |
| --- | --- |
| `action_button.tscn` | Standard `Button.pressed`; primary/quiet theme variations; scales its minimum height. |
| `text_field.tscn` | Label, `input: LineEdit`, clear action, helper/error state; `text_changed` and `text_submitted` signals. Configure `label_text`, `placeholder`, `helper_text`, `keyboard_type` before adding to the tree. Use `show_error()` for validation. Search fields reuse this scene. |
| `number_field.tscn` | Label, large minus/plus controls, editable numeric keyboard, helper and optional suffix. Configure `minimum`, `maximum`, `step`; read/write `value`, observe `value_changed`. Partial input is allowed; submit/focus exit clamps the committed value. |
| `toggle_field.tscn` | Whole-row toggle with wrapping label, optional helper and explicit On/Off state. Uses standard `toggled`; `set_checked()` updates without emitting. |

`main.gd` has small `_field`, `_toggle`, `_button` factories for these scenes.
Use the same components for character creation, engine prompts, filtering,
inventory quantities, settings, key entry and action customization.

All dimensions are density-independent logical units, with an 18-unit body font,
16-unit minimum body text, 56-unit default controls (48 minimum), and shared
8/16-unit spacing. Android's window canvas uses `pixels / (dpi / 160)`; text-size
preferences then scale the theme, not the canvas a second time. Forms are capped
at 640 logical units and remain scrollable above the software keyboard. Game
action strips scroll horizontally so labels and touch areas retain their size.

Verification:

```sh
godot --headless --path godot --script res://tests/widget_smoke.gd
godot --headless --path godot --script res://tests/scroll_smoke.gd
godot --headless --path godot --script res://tests/ui_smoke.gd
```

For rendered form captures, run `widget_smoke.gd` without `--headless` and append
`-- --screenshot`. Images are written to `build/widgets-*.png`.

For Android software-keyboard acceptance, use a touch-only AVD (`hw.keyboard=no`).
Godot suppresses its virtual keyboard when Android reports a hardware keyboard;
the emulator's "show keyboard with hardware keyboard" setting alone does not
override that engine behavior. Test both text and numeric keyboard types.
