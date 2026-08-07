# LocalVocal Flatpak installer failure report

## Summary

The installer initially stopped during the LocalVocal Flatpak build with:

```text
error: org.freedesktop.Sdk/x86_64/25.08 not installed
Failed to init: Unable to find sdk org.freedesktop.Sdk//25.08 version stable
```

That SDK issue was fixed. On the next run, SDK installation succeeded and the
LocalVocal build completed successfully. The installer then stopped during the
installation phase with:

```text
App dir 'build-dir' is not empty. Please delete the existing contents or use --force-clean.
```

The host packages, OBS Flatpak, source checkout, SDK installation, dependency
builds, and plugin compilation all completed successfully. The remaining
failure was caused by the install command being run against an already-built
directory without the required cleanup option.

## Cause

The installer and the cloned repository requested different SDKs:

| Source | SDK requested |
| --- | --- |
| Installer script | `org.kde.Sdk//6.8` |
| LocalVocal manifest | `org.freedesktop.Sdk//25.08` |

The manifest is authoritative for a Flatpak build. Installing
`org.kde.Sdk//6.8` cannot satisfy a build that declares
`org.freedesktop.Sdk//25.08`; SDK IDs and branches are separate Flatpak refs.

The KDE 6.8 end-of-life notice was therefore unrelated to the immediate error.
It was a warning about an SDK that the build did not use.

### Second failure: non-empty build directory

The script first ran:

```bash
./flatpak/build.sh --disable-rofiles-fuse --force-clean build-dir "$MANIFEST"
```

It then ran a separate install command without `--force-clean`. Since the
first command populated `build-dir`, `flatpak-builder` correctly refused to
reuse it for the second command. The fallback command had the same problem.

## Changes made

`install-obs-localvocal-flatpak.sh` now:

1. Clones or updates LocalVocal before installing build SDKs.
2. Reads the `sdk:` value directly from the checked-out manifest.
3. Installs that SDK from the user Flathub remote.
4. Reads and installs every manifest-declared `sdk-extensions` entry using the
   same SDK branch.
5. Avoids hard-coding the obsolete KDE SDK and branch.
6. Builds and installs in one `build.sh` invocation using `--force-clean`.
7. Uses `--force-clean` on the fallback `flatpak-builder --install` command.

For the repository state shown in the failure, this resolves to:

```text
org.freedesktop.Sdk//25.08
org.freedesktop.Sdk.Extension.rust-stable//25.08
```

## Verification

The required refs are available from the configured Flathub remote. Re-run:

```bash
./Linux/install-obs-localvocal-flatpak.sh
```

The build should now proceed through installation. If the upstream manifest
changes its SDK or extensions later, the installer will follow those values
automatically.
