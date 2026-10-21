# Windows Installer Plan

> Updated: 2026-10-21 — Phases 1–5 implemented on `refactor`; Phase 6 is design only.

Goal: ship PixelLab Studio on Windows as a normal installed application — Start
menu entry, Settings → Apps entry, clean uninstall, and `.pixlab` avatar files
that open in the app on double-click — built so a future GitHub-releases
auto-updater can drive it silently.

## Decisions

| Topic | Decision |
|---|---|
| Installer tool | **Inno Setup 6** — free, scriptable, runs in CI, handles upgrades, uninstall and file associations natively, and supports silent installs for the updater. |
| Install scope | **Per user**, no admin. Installs to `%LOCALAPPDATA%\Programs\PixelLab Studio`, registry under `HKCU`. Updates never show a UAC prompt. |
| Avatar extension | New saves are written as `.pixlab`. Load still accepts `.save`. Only `.pixlab` is associated. File contents (JSON) are unchanged. |
| Second launch | If the app is already running, a double-clicked file is handed to the running window, and the new process exits. |
| Versioning | Every build that ships gets a new semver version (`1.7.0-alpha.3`, `1.7.0`). Assets are never rebuilt in place on an existing tag. |

## Where it lives

| Piece | Files |
|---|---|
| `.pixlab` saves, launch file, dropped files | `main_scenes/controllers/save_controller.gd` (`avatar_save_path`, `startup_restore(launch_file)`, `open_external_avatar`, `on_files_dropped`), wired in `main_scenes/main.gd` |
| Single instance | `autoload/instance_lock.gd` — must stay the **first** autoload |
| Version | `application/config/version` in `project.godot`; `autoload/runtime/app_version.gd` |
| Installer | `installer/windows/PixelLabStudio.iss`, `installer/windows/build.ps1` |
| Release CI | `.github/workflows/windows-release.yml` |
| Contracts | `tests/unit/test_release_contract.gd` (`_test_windows_install_contract`, version and extension checks), `test_main_controllers.gd` (`_test_avatar_file_extension_contract`), `test_runtime_services.gd` (`_test_app_version`) |

The architecture guide's Autoload Singletons, Save/Load and "Windows installer
and versioning" sections describe the data flow.

## Building

```bash
powershell -File installer/windows/build.ps1 -Godot "C:\path\to\Godot_v4.6.3-stable_win64.exe"
```

Output goes to `.artifacts/installer/windows/`:
- `PixelLabStudio-v<ver>-Windows-x64-Setup.exe`
- `PixelLabStudio-v<ver>-Windows-x64.zip` (portable build)
- `SHA256SUMS.txt`

The asset names are fixed because the updater will match on them.

One-time machine setup:
- **Godot 4.6.3 export templates.**
- **Inno Setup 6.** For example, `winget install JRSoftware.InnoSetup --scope user`.
- **`D3D12Core.x86_64.dll` in the templates folder.** The architecture guide's
  D3D12 note explains why. The build stops if the export lacks it.

**Releasing:**
1. Bump `config/version`, and the Windows preset's `file_version` /
   `product_version` to `AppVersion.windows_numeric()` of it. The tests and
   `build.ps1` both check that these match.
2. Commit, then push tag `v<version>`.
3. The workflow attaches the assets to a draft release. Add notes and the macOS
   build there, then publish.

## Phase 6 — Future auto-updater (design constraints only)

- **Checking.** Query `GET https://api.github.com/repos/WeebLabs/PixelLabStudio/releases/latest`,
  which returns stable releases only. A beta opt-in would use `/releases` and
  take the newest prerelease. Check at most once a day: the unauthenticated
  limit is 60 requests an hour per IP.
- **Comparing.** Compare the tag with `AppVersion.compare(tag, AppVersion.current())`.
- **Installing.** Download the `-Setup.exe` asset with `HTTPRequest` and verify
  it against `SHA256SUMS.txt`. Then run
  `OS.create_process(setup, ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/CLOSEAPPLICATIONS", "/RELAUNCH"])`
  and quit. Don't wait on the process: setup's relaunched app is its child, so
  waiting blocks until the app exits.
- **Scope.** Only installed copies self-update. They're the ones with
  `HKCU\Software\PixelLab Studio\InstallDir`. The portable zip links to the
  release page instead.
- **Before quitting.** Save the session first.

## Known gaps

- **Not tried by hand:** dropping a file onto the window. The handler is wired
  and its path filter is unit-tested.
- **Window flash:** a handed-off second launch can flash its window briefly
  before it exits.
- **Unsigned installer:** it shows SmartScreen's "Windows protected your PC"
  warning until it builds up reputation. The README tells users how to get past
  it. Signing (for example with Azure Trusted Signing) can be added later
  without changing anything else.
- **Virtual webcam:** that work is on `main`, not `refactor`. When it lands, its
  DirectShow filter needs a one-time elevated `regsvr32`. An in-app "Enable
  virtual camera" action keeps the install per user.

## Test record (2026-10-21, Windows 11, Godot 4.6.3)

- **Unit suites:** 1077 assertions, 0 failures. The baseline without these
  changes was 1026, 0 failures.
- **Integration run:** 834 assertions with the same 4 layer-list centring
  failures, then a segfault on exit, exactly as on unmodified `refactor`. The
  Windows export smoke fails the same way on both, because the pack runs and
  then crashes on exit. Both problems already existed on this machine.
  `refactor`'s GitHub test runs have been failing on all three platforms since
  2026-09-17.
- **Installer:**
  - Silent install: files, Start menu shortcut, Settings → Apps entry
    (publisher Weeb Labs, version 1.7.0-alpha.3) and the association were all
    in place.
  - Opening `Lennie one.pixlab` from a folder named `test dir ä` loaded it.
  - Opening a second file while running loaded it in the same process.
  - A silent `/CLOSEAPPLICATIONS /RELAUNCH` reinstall over the running app
    closed and relaunched it.
  - Uninstall left no files, registry keys or shortcut. User data was kept.
