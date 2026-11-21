# Project instructions

- Commit every verified milestone.
- Do not run Unity in batch mode; there is no license for it.
- An APK build explicitly requested by the user creates a new version unless
  the user identifies it as testing-only. Increment the patch version and
  Android version code, and add a dated changelog entry before building.
- Internal verification builds and explicitly testing-only APKs keep the
  existing version. Retrying the same requested build does not bump it again.
- Follow the versioning checklist in `docs/RELEASE.md`. Keep version metadata
  consistent and commit it before generating the requested APK.
