# Publishing a Release

> Updated: 2026-10-21 — first written for v1.7.0-alpha.3, the first release
> with the Windows installer and the in-app updater.

This is the whole process, from picking a version number to checking that
people's apps can see the update. If you only need the short version:

1. Bump the version in `project.godot` and `export_presets.cfg`.
2. Run the tests, then commit and push `main`.
3. Push the tag `v<version>`. CI builds the Windows installer and zip into a
   **draft** release.
4. Export the macOS build on a Mac and upload it to the draft.
5. Write the release notes, then publish.

The rest of this page explains each step and what to do when something goes wrong.

---

## How a release reaches people

- **Windows, installed:** the installed app checks GitHub once a day at startup,
  and whenever **Settings → Updates → Check for updates now** is pressed. It
  offers any published release that is newer than itself. "Update now" downloads
  the installer, checks it against `SHA256SUMS.txt`, installs it silently, and
  reopens the app.
- **Windows portable zip, and macOS:** the app offers the release too, but its
  button opens the release page instead, and the user downloads it themselves.
- **Drafts are invisible** to the app and to anyone without push access, so a
  release stays private until you publish it.
- **Pre-releases are only offered to some users.** That means anyone running a
  pre-release themselves, or anyone who ticked **Pre-releases** in Settings →
  Updates. Everyone else only sees full releases.

**v1.7.0-alpha.3 is the first build with the updater.** Anyone on v1.7.0b or
older has to download and install it by hand once. Say so in that release's
notes. From then on, updates reach them in the app.

---

## One-time setup

### Windows machine (only needed for local builds; CI does this on its own)

| Need | How |
|---|---|
| Godot **4.6.3** | Official build from godotengine.org. The tests refuse any other 4.6.x. |
| Godot 4.6.3 export templates | Editor → *Manage Export Templates* → Download, or extract `Godot_v4.6.3-stable_export_templates.tpz` into `%APPDATA%\Godot\export_templates\4.6.3.stable\`. Rename `.tpz` to `.zip` first if you use PowerShell's `Expand-Archive`. |
| `D3D12Core.x86_64.dll` in that templates folder | `build/native/bin/x64/D3D12Core.dll` from the [Microsoft.Direct3D.D3D12](https://www.nuget.org/packages/Microsoft.Direct3D.D3D12) NuGet package (1.619.3 or any version ≥ 618), renamed. Without it, window transparency renders black. The build stops if it's missing. |
| Inno Setup 6 | `winget install JRSoftware.InnoSetup --scope user` |
| GitHub CLI | `winget install GitHub.cli`, then `gh auth login` |

### Mac (for the macOS build)

- **Godot 4.6.3 and its export templates.**
- **Nothing else.** The macOS preset signs ad hoc and doesn't notarize, so no
  Apple developer account is needed. Users right-click → **Open** the first
  time; the README explains this.

---

## Version numbers

The version lives in **`application/config/version`** in `project.godot`. It
must be semver:

| Kind | Example | Tag | GitHub "pre-release" box |
|---|---|---|---|
| Alpha | `1.7.0-alpha.3` | `v1.7.0-alpha.3` | ticked (CI does it) |
| Beta | `1.7.0-beta.1` | `v1.7.0-beta.1` | ticked |
| Release candidate | `1.7.0-rc.1` | `v1.7.0-rc.1` | ticked |
| Release | `1.7.0` | `v1.7.0` | not ticked |

**Rules:**
- **Every published build gets a new number.** Never upload replacement files to
  an existing tag. The updater compares version numbers, so a rebuild under the
  same number reaches no one. A fix to `1.7.0-alpha.3` ships as `1.7.0-alpha.4`.
- **Order:** alpha < beta < rc < release for the same `x.y.z`.
- **Old-style tags are ignored by the updater.** Tags like `v1.7.0a` don't follow
  the pattern.
- **Prerelease numbers stay below 100.** The Windows version field can't tell
  alpha 100 from beta 0.

### The other two places the version appears

Windows file properties need a four-part number, and the build refuses to run
if it doesn't match. Set **both** `application/file_version` and
`application/product_version` in the `[preset.0.options]` (Windows Desktop)
section of `export_presets.cfg`:

| `config/version` | Windows four-part version |
|---|---|
| `x.y.z-alpha.N` | `x.y.z.N` |
| `x.y.z-beta.N` | `x.y.z.(100 + N)` |
| `x.y.z-rc.N` | `x.y.z.(200 + N)` |
| `x.y.z` | `x.y.z.1000` |

For example, `1.7.0-alpha.4` becomes `1.7.0.4`, `1.7.0-beta.2` becomes
`1.7.0.102`, and `1.7.0` becomes `1.7.0.1000`.

For macOS (`[preset.2.options]`), set `application/short_version` and
`application/version` to just `x.y.z`, for example `1.7.0`. Only change them
when `x.y.z` changes.

---

## Step by step

The examples publish `1.7.0-alpha.4`. Substitute your version.

### 1. Start from an up-to-date `main`

```bash
git checkout main
```

```bash
git pull
```

### 2. Bump the version

In `project.godot`:

```ini
config/version="1.7.0-alpha.4"
```

In `export_presets.cfg`, under the Windows preset:

```ini
application/file_version="1.7.0.4"
application/product_version="1.7.0.4"
```

Change the macOS `short_version` / `version` too if `x.y.z` changed.

### 3. Run the checks

From Git Bash, with the path to Godot 4.6.3:

```bash
GODOT_BIN="/c/path/to/Godot_v4.6.3-stable_win64.exe" ./scripts/run_tests.sh
```

- **Must pass:** the unit suites (`[TEST] … 0 failures`). The release contract
  test also confirms the version and the preset agree.
- **Already failing, so don't treat these as blockers** (as of 2026-10-21):
  - The production-scene integration run reports 4 layer-list centring
    failures, then segfaults on exit on Windows. Because of that,
    `run_tests.sh` stops before the unit suites there. To get unit results
    anyway, run `test_runner.gd` the way the second half of `run_tests.sh` does.
  - The Windows export smoke crashes on exit the same way.
  - The "Godot tests" GitHub workflow has failed on all three platforms since
    2026-09-17.

  Compare against these results. Any **new** failure is a blocker.

### 4. Optional: build and try the installer locally

In PowerShell:

```bash
powershell -File installer/windows/build.ps1 -Godot "C:\path\to\Godot_v4.6.3-stable_win64.exe"
```

The output goes to `.artifacts/installer/windows/`:
- `PixelLabStudio-v1.7.0-alpha.4-Windows-x64-Setup.exe`
- `PixelLabStudio-v1.7.0-alpha.4-Windows-x64.zip`
- `SHA256SUMS.txt`

Install the setup, open a `.pixlab` by double-click, then uninstall. Uninstalling
keeps your settings and avatars.

### 5. Commit and push

```bash
git commit -am "Release: 1.7.0-alpha.4"
```

```bash
git push
```

### 6. Tag and push the tag

```bash
git tag v1.7.0-alpha.4
```

```bash
git push origin v1.7.0-alpha.4
```

The tag must be exactly `v` + `config/version`; otherwise the build fails on
purpose. Tag the commit that has the bumped version.

### 7. Let CI build the Windows release

Pushing the tag starts **Release (Windows)**
(`.github/workflows/windows-release.yml`). It:

1. **Sets up the tools:** downloads Godot 4.6.3 and the export templates
   (checksum-verified and cached), plus the Agility SDK DLL, and installs Inno
   Setup.
2. **Builds:** runs `installer/windows/build.ps1 -Tag v1.7.0-alpha.4`.
3. **Publishes a draft:** creates a **draft** release, ticked as a pre-release
   when the tag contains `-`, and uploads the three files.

Watch it with:

```bash
gh run watch
```

Or open the repository's **Actions** tab. When it finishes, the draft is under
**Releases**.

### 8. Add the macOS build

On the Mac, at the same commit (`git checkout v1.7.0-alpha.4`):

1. Export with the macOS preset, either from the editor (*Project → Export →
   macOS → Export Project*) or headless:
   ```bash
   godot --headless --path . --export-release "macOS" ".artifacts/exports/macos/PixelLab Studio.zip"
   ```
2. Rename the zip to `PixelLabStudio-v1.7.0-alpha.4-macOS-universal.zip`.
3. Upload it to the draft:
   ```bash
   gh release upload v1.7.0-alpha.4 "PixelLabStudio-v1.7.0-alpha.4-macOS-universal.zip"
   ```

Don't upload a second `SHA256SUMS.txt`. The updater only reads the Windows
entries in the one CI made.

### 9. Write the release notes

Edit the draft on GitHub. The house rules are in `CLAUDE.md` under *Release
notes*:
- **New features:** announce each one once.
- **Fixes:** describe what was broken the way users saw it, and that it's fixed.
- **Leave out:** the implementation, the reasoning, and anything from internal
  discussion.
- **Reached differently:** if something is now opened or found in a different
  way, one plain sentence is enough.

The title is `PixelLab Studio v1.7.0-alpha.4`; add "(alpha)" or "(beta)" to
match the earlier releases. Say which Godot version the build is on.

### 10. Publish

Check that the draft has all four files:
- `…-Windows-x64-Setup.exe`
- `…-Windows-x64.zip`
- `…-macOS-universal.zip`
- `SHA256SUMS.txt`

Check that **Set as a pre-release** matches the version. Then click **Publish
release**, or run:

```bash
gh release edit v1.7.0-alpha.4 --draft=false
```

For a full release that should be the one GitHub shows as "Latest", also tick
**Set as the latest release**.

### 11. Check it landed

- **Installer:** download the published Setup.exe from the release page and
  install it. Settings → Updates should show the new version, "installed".
- **Updater:** on a machine still running the previous version, open **Settings
  → Updates → Check for updates now**. It should offer the new version, and
  "Update now" should finish with the app reopening on it. Pre-releases only
  appear if that install is itself a pre-release or has **Pre-releases** ticked.
- **Everyone else:** other users see the update within a day, at their next app
  start.

---

## If something goes wrong

### Before publishing (still a draft)

Nobody has seen a draft, so you can redo it:

1. **Delete the draft:** `gh release delete v1.7.0-alpha.4`
2. **Delete the tag:**
   ```bash
   git push --delete origin v1.7.0-alpha.4
   ```
   ```bash
   git tag -d v1.7.0-alpha.4
   ```
3. Fix, commit, and tag again.

To re-run the CI build for a tag that already exists, use **Actions → Release
(Windows) → Run workflow** and enter the tag. Uploads refuse to overwrite, so
delete that release's assets first.

### After publishing

**Do not replace the files on a published release.** Installed apps that
already updated won't update again, and new downloads would differ from what
earlier users got. Instead:

- **Ship the fix as the next version,** for example `1.7.0-alpha.5`. Apps that
  took the broken build will be offered the fix.
- **If the release is harmful, hide it:** turn it back into a draft
  (`gh release edit v1.7.0-alpha.4 --draft=true`). The updater stops offering it
  right away. Copies that already installed it keep it until the next version.

### If CI can't build

Build locally (step 4), then attach the files to the draft yourself:

```bash
gh release create v1.7.0-alpha.4 --draft --prerelease --verify-tag --title "PixelLab Studio v1.7.0-alpha.4" --notes "Draft"
```

```bash
gh release upload v1.7.0-alpha.4 .artifacts/installer/windows/PixelLabStudio-v1.7.0-alpha.4-Windows-x64-Setup.exe .artifacts/installer/windows/PixelLabStudio-v1.7.0-alpha.4-Windows-x64.zip .artifacts/installer/windows/SHA256SUMS.txt
```

Leave out `--prerelease` for a full release. All three files must come from the
**same** build, because `SHA256SUMS.txt` has to match the Setup.exe byte for byte.

### Error messages

| Message | Cause | Fix |
|---|---|---|
| `Tag 'v…' does not match project.godot config/version '…'` | The tag points at a commit without the bump, or there's a typo. | Delete the tag, then tag the right commit. |
| `Windows preset product_version is '…' but config/version '…' needs '…'` | Step 2 missed `export_presets.cfg`. | Set both Windows version fields to the value shown. |
| `config/version '…' is not MAJOR.MINOR.PATCH[-alpha\|beta\|rc.N]` | The version isn't semver, for example `1.7.0b`. | Use `1.7.0-beta.2` style. |
| `Export is missing x86_64\D3D12Core.dll` | The Agility SDK DLL isn't in the templates folder. | See One-time setup. |
| `Export failed: PixelLab Studio.exe was not produced` | The Godot export failed. Templates missing, or the wrong Godot version. | Check that the templates folder is `4.6.3.stable`, and run the export in the editor to see the error. |
| `Inno Setup ISCC … not found` | Inno Setup isn't installed. | `winget install JRSoftware.InnoSetup --scope user`, or pass `-Iscc`. |
| `gh release upload` says an asset already exists | You're re-running on a release that already has the files. | Draft: delete the assets first. Published: ship a new version instead. |
| The updater says "the latest version" when you expected an update | The release is still a draft, or it's a pre-release and that install isn't opted in, or the tag isn't semver, or the Setup.exe / SHA256SUMS.txt names don't match. | Check each against this page. |
| The updater says "did not match its checksum" | `SHA256SUMS.txt` comes from a different build than the Setup.exe. | Re-upload all three files from one build, as a new version if the release is already published. |

---

## Reference

| What | Where |
|---|---|
| Version | `project.godot` → `application/config/version` |
| Windows file version | `export_presets.cfg` → Windows preset → `file_version`, `product_version` |
| macOS version | `export_presets.cfg` → macOS preset → `short_version`, `version` |
| Windows build script | `installer/windows/build.ps1` |
| Installer definition | `installer/windows/PixelLabStudio.iss`. **Never change its `AppId`.** |
| Release workflow | `.github/workflows/windows-release.yml` |
| Version comparison | `autoload/runtime/app_version.gd` |
| What the updater accepts | `autoload/runtime/update_feed.gd` |
| Design and test record | `docs/windows_installer_plan.md` |

**Release asset names.** These are fixed, because the updater looks for them by
name:

```
PixelLabStudio-v<version>-Windows-x64-Setup.exe
PixelLabStudio-v<version>-Windows-x64.zip
PixelLabStudio-v<version>-macOS-universal.zip
SHA256SUMS.txt
```
