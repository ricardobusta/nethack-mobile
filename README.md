# NetHack Mobile

An unofficial, free, offline Android port of NetHack. Built with **Godot
4.7.1**, GDScript, and the original C game engine. Phones and tablets,
portrait and landscape, classic ASCII and upstream tiles.

This repository is a working port under development, not a published store
release. See [release acceptance](docs/RELEASE.md) for remaining device checks.

## Build and run

Install Python 3.12+, CMake 3.22+, Ninja, a C99/C++17 compiler, and Godot
4.7.1 with its export templates. Sources and dependencies are vendored;
normal native builds require no source downloads.

```sh
python3 scripts/build.py host
godot --headless --path godot --editor --quit
godot --path godot
```

The host build runs native integration tests, including save/restore,
repeated sessions, tile mapping coverage, stale-input rejection, and
recovery after killing a process at a checkpoint.

For Android, install an NDK r27 or newer, Android SDK/platform/build tools,
and JDK 17. Set `ANDROID_NDK_HOME` to the actual NDK directory:

```sh
python3 scripts/build.py android-arm64-v8a --skip-prepare
python3 scripts/build.py android-x86_64 --skip-prepare
python3 scripts/export.py apk
```

The APK uses a debug key and is written to `dist/nethack-mobile-debug.apk`.
Install it with `adb install -r dist/nethack-mobile-debug.apk`.

For an unsigned release AAB, set `NETHACK_ANDROID_SDK` to a writable SDK
containing the packages required by the pinned Godot templates, then run:

```sh
python3 scripts/export.py aab
```

Native Android builds target API 26 and use 16 KB ELF segment alignment.
Both Gradle export presets set minimum SDK 26 and target SDK 36.

## Play

Tap an adjacent cell to move/interact; tap a known distant destination to
use NetHack travel. Drag to pan and pinch to zoom. **Center** follows the
character again. **Stop** cancels input or interrupts travel/repeated actions.

Use the bottom action bar for common actions, **Commands** for the complete
searchable command list, **Direction** for precise directions, and **Keys**
for prefixes, counts, and Ctrl/Alt commands. Item menus support quantities;
zero means the whole stack. Change display mode and customize actions in
settings. Physical keyboards are also supported.

Use **Save and suspend** before leaving. Checkpoints support recovery after
process death. Standard permadeath applies. Saves and bones stay in private
storage, separated by engine version, edit level, and port save-format version.

## Manually update NetHack

```sh
python3 scripts/upstream.py check
python3 scripts/upstream.py import
python3 scripts/upstream.py verify
```

`check` is read-only. `import` resolves the latest official stable GitHub
release to a commit, checks local vendor integrity, stages the archive,
applies patches, and runs isolated native integration tests before replacing
the source and lock file. It never commits or publishes. Review the diff,
license, tile coverage and save compatibility, then commit the milestone.
There is no scheduled updater or in-app code download.

## Verify and release

```sh
python3 -m unittest discover -s tests -v
godot --headless --path godot --script res://tests/ui_smoke.gd
godot --headless --path godot --script res://tests/scroll_smoke.gd
godot --headless --path godot --script res://tests/widget_smoke.gd
```

See [architecture](docs/ARCHITECTURE.md) and
[release/signing instructions](docs/RELEASE.md). iOS builds are deferred;
the engine C API and platform boundary are kept portable. Unity is not used.

Reusable mobile input scenes and sizing conventions are documented in
[the UI component library](godot/ui/README.md).

## License

The port is distributed under the [NetHack General Public License](LICENSE).
Preserve [notices](NOTICE) and publish the exact matching source archive with
every distributed build. Godot/godot-cpp and Lua retain their MIT licenses.
Original upstream files remain pristine in `vendor/nethack`; dated mobile
changes live in `patches` and are applied only to generated build trees.
