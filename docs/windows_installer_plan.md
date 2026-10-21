# Windows Installer Plan

> Updated: 2026-10-21 — Phases 1–6 implemented on `refactor`, including the updater.

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
| Updater | `autoload/runtime/update_feed.gd` (pure decisions), `main_scenes/controllers/update_controller.gd` (check, prompt, download, install), Settings → Updates (`ui_scenes/settings/updates_settings_tab.gd`) |
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

The full procedure, including the macOS build, release notes, recovery from a
bad release and error messages, is in `docs/releasing.md`.

## Phase 6 — The updater

- **When it checks:** at startup at most once a day (setting `updateChecks`, last run in
  `updateLastCheck`), and whenever **Check for updates now** is pressed in
  Settings → Updates. Never in editor runs or the isolated automated sessions.
- **What it offers:** the newest release on `GET /repos/WeebLabs/PixelLabStudio/releases`
  that is newer than the running version, skipping drafts and tags that are not
  semver (so v1.7.0a and v1.7.0b are ignored). Pre-releases count when the user
  ticked **Pre-releases** or is running one, so an alpha user gets the next alpha.
  An installed copy needs the release to carry the setup and `SHA256SUMS.txt`.
- **The prompt:** "Update now", "Later" or "Skip this version". A skipped version
  stays quiet on automatic checks but still shows on a manual one. A background
  result waits for the recovery prompt, a save or a load to finish first.
- **Installing (installed Windows copies, detected by `unins000.exe` beside the exe):**
  1. Download `SHA256SUMS.txt`, then the setup to `user://updates/`, with a
     progress bar.
  2. Refuse and delete the download if its SHA-256 does not match.
  3. Write the session file, so unsaved edits come back through recovery.
  4. Start setup with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RELAUNCH`,
     without waiting on it, and quit.
  5. Setup replaces the files and starts the new build, whose startup clears
     `user://updates/`.
- **Portable zip and macOS:** "Open download page" instead of "Update now".
- **Testing against a local feed:** launch with `-- --update-feed=<url>`, pointing at a
  JSON file shaped like GitHub's `/releases` response.

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
- **Updater, against a local feed with an installed 1.7.0-alpha.3 and a built
  1.7.0-alpha.4:**
  - The startup check found alpha.4 and showed the prompt.
  - "Update now" downloaded the checksums and setup, ran setup silently,
    closed the old process and relaunched 1.7.0.4. The install marker read
    1.7.0-alpha.4.
  - With a wrong digest in `SHA256SUMS.txt`, the download was rejected and
    deleted, nothing ran, and the app stayed on 1.7.0.3.
  - Unit suites: 1117 assertions, 0 failures. Integration: 849 assertions,
    the same 4 failures already there.
- **Audit fixes (installed build):**
  - **Handoff during a slow startup:** the running copy was frozen for 3 s while a
    second avatar was opened. The old 500 ms wait left 2 windows; the fixed build
    kept 1, which loaded the file.
  - **Crash recovery:** a crashed session plus a double-clicked avatar now shows
    the recovery prompt, naming that file, instead of loading over the session.
    Opening another avatar while the prompt was up re-asked with that file. The
    session file survived both.
  - **Input behind modals:** the update prompt and download now hold canvas
    shortcuts like other modals. This is covered by a source contract, not by
    hand.
  - Unit suites: 1127 assertions, 0 failures. Integration: the same 4 failures
    already there.
- **Installer:**
  - Silent install: files, Start menu shortcut, Settings → Apps entry
    (publisher Weeb Labs, version 1.7.0-alpha.3) and the association were all
    in place.
  - Opening `Lennie one.pixlab` from a folder named `test dir ä` loaded it.
  - Opening a second file while running loaded it in the same process.
  - A silent `/CLOSEAPPLICATIONS /RELAUNCH` reinstall over the running app
    closed and relaunched it.
  - Uninstall left no files, registry keys or shortcut. User data was kept.
