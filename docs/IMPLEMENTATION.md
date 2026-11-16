# Release milestones

1. License, pristine upstream source, manually triggered updater, dependency pins.
2. Native engine, host build, protocol and integration tests.
3. Godot frontend: ASCII/tiles, complete touch input, adaptive layouts.
4. Android native build/export, persistence and lifecycle verification.
5. Release packaging, matching sources, store assets and device acceptance.

Commit every completed milestone. Never run Unity in batch mode.

Android is the first release target. Keep the C bridge independent of Godot
and platform-specific lifecycle/storage code isolated for later iOS support.
No cloud services, advertisements, purchases, telemetry, or accounts.

Store release requires physical phone/tablet acceptance and owner signing
credentials. A build is not store-ready merely because it compiles.
