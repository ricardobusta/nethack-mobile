# Release preparation and acceptance

## Build artifacts

Use the pinned Godot 4.7.1 editor and export templates, godot-cpp 10.0.0 targeting
API 4.7, Lua 5.4.8, and the locked NetHack release. `toolchain.json` records the
baseline. Android Gradle template package requirements can be inspected in the
generated `godot/android/build/config.gradle`; for this template these include
build tools 36.1.0, compile SDK 36, and JDK 17. Use a writable SDK, not an SDK
managed by another game engine.

1. Commit the final milestone. Verify a clean `git status`.
2. Run `python3 scripts/build.py host` to regenerate data and build metadata
   from that commit; this also runs process-death recovery tests.
3. Build both Android ABIs with `--skip-prepare` and run the Godot UI smoke test.
4. Export the debug APK and unsigned release AAB using `scripts/export.py`.
5. Run `python3 scripts/package_release.py` to create the matching complete
   source archive, `release.json`, and `SHA256SUMS` in `dist`.

Generate the 512 px listing icon and 1024×500 feature graphic from the original
vector branding with `godot --path godot --script res://tests/store_assets.gd`.
They are written to `dist/store`; review them with the owner before publication.
Capture phone/tablet screenshots from the actual release build. Google's current
[preview-asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151)
remain the final authority for listing dimensions and formats.

The source packager rejects uncommitted state, stale generated metadata, or an
APK built from different metadata. Native libraries are stripped only in their
shipping Android copies; host/build archives retain symbols for diagnosis.

The debug APK is installable but is not a store release. The release AAB is
unsigned by default. Set the following environment variables locally and use
`python3 scripts/export.py aab --signed` to produce an owner-signed AAB:

- `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`
- `GODOT_ANDROID_KEYSTORE_RELEASE_USER`
- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`

Never commit keystores, passwords, or export credential files. Final application
ID (`org.nethackmobile.app` provisionally), signing identity, Play account and
listing approval belong to the owner. Publishing is not automated.

## Acceptance status

Automated coverage includes updater failure handling, archive path rejection,
native menus/commands, tile coverage, repeated sessions, save/restore, stale
input, process-death checkpoint recovery, and Godot UI/orientation reflow.
Emulator testing covers native Android launch, touch character creation and
portrait/landscape rendering. These checks do not prove store readiness.

Before a store submission, record results on a physical Android phone and
tablet, including a device using 16 KB memory pages where available:

- Both orientations; rotation during item selection, quantity input and text
  entry; keyboard and display cutouts; readable status and 48 dp touch targets.
- ASCII/tile parity, zoom/pan, diagonal movement, travel interruption, pet
  interaction, ranged targeting, multi-selection, counts and modifiers.
- Full game lifecycle: role creation, stairs, save/restore, death and a fresh
  game after death. Complete a long playthrough with all command categories.
- Home/background/lock, OS process termination, restore after interruption,
  low storage, and termination during save/checkpoint writes. Verify no false
  "saved" confirmation and no silent destruction of an incompatible save.
- Play pre-launch report, current target-API policy, ELF and ZIP alignment of
  every native library, signing, and the exact artifact/version to publish.

Full TalkBack navigation has not been implemented or certified. Scalable text
and keyboard support are present; do not advertise screen-reader accessibility.

## Draft Play listing

**Name:** NetHack Mobile

**Short description:** Classic NetHack, offline, with touch controls, ASCII and tiles.

**Description:** Explore NetHack's dungeons on your Android phone or tablet.
Play the original turn-based game with tap-to-travel, a customizable action
bar, searchable commands, and precise direction and keyboard controls. Switch
between classic text and standard tiles, zoom the map, and play in portrait or
landscape. Free and open source, with no ads, accounts, purchases, or analytics.
An unofficial community port; not endorsed by the NetHack DevTeam.

Use actual release screenshots from a phone and tablet. The included adaptive
icon is original vector artwork; confirm listing branding before publication.

## Draft privacy statement

NetHack Mobile operates offline. It does not collect or transmit personal data,
use analytics or advertising SDKs, require an account, or include purchases.
Character names, saves, bones, scores, preferences and diagnostic game logs are
stored locally in app-private storage. Platform backup is disabled. Uninstalling
the app removes local app data unless the operating system retains it separately.
Opening source or license links uses the user's browser and that site's policy.

Before publication, provide the owner's contact details and host this statement
at the final public privacy-policy URL. Complete the Play Data Safety form from
the actual signed artifact and the store's current definitions.

## License/source delivery

Every binary distribution must retain NGPL and dependency notices and provide
the exact corresponding complete source. Publish the generated source archive
beside its binary, with checksums and build instructions, and keep older releases
available for users with older saves. Source links must be publicly accessible;
a private repository link is not sufficient for recipients without access.
