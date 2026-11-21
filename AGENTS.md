# Project instructions

- Commit every verified milestone.
- Do not run Unity in batch mode; there is no license for it.
- An APK build explicitly requested by the user creates a new version unless
  the user identifies it as testing-only. Increment the patch version and
  Android version code, and add a dated changelog entry before building.
- Builds the agent initiates to check behavior, debug, or verify changes must
  not bump any version or add changelog entries. Explicitly testing-only APKs
  follow the same rule. Retrying the same requested build does not bump it again.
- Follow the versioning checklist in `docs/RELEASE.md`. Keep version metadata
  consistent and commit it before generating the requested APK.
