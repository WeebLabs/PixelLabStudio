class_name UpdateFeed
extends RefCounted

## Pure decisions for the GitHub-releases updater: which release to offer, which
## assets it needs, and when to check. The network, the prompt and the install
## live in main_scenes/controllers/update_controller.gd.
##
## Asset names are fixed by installer/windows/build.ps1:
##   PixelLabStudio-v<version>-Windows-x64-Setup.exe
##   PixelLabStudio-v<version>-Windows-x64.zip
##   SHA256SUMS.txt

const AppVersion = preload("res://autoload/runtime/app_version.gd")

const RELEASES_API := "https://api.github.com/repos/WeebLabs/PixelLabStudio/releases?per_page=30"
const CHECKSUMS_ASSET := "SHA256SUMS.txt"
const CHECK_INTERVAL_SECONDS := 24 * 60 * 60
## Bounds what the updater will accept from the feed and download.
const MAX_FEED_BYTES := 4 * 1024 * 1024
const MAX_INSTALLER_BYTES := 512 * 1024 * 1024


static func setup_asset_name(version: String) -> String:
	return "PixelLabStudio-v%s-Windows-x64-Setup.exe" % version.trim_prefix("v")


## Prereleases are offered when the user opted in, and always while the running
## build is itself a prerelease: someone on an alpha should get the next alpha.
static func include_prereleases(opted_in: bool, current: String) -> bool:
	return opted_in or AppVersion.is_prerelease(current)


static func should_check(enabled: bool, now: int, last_check: int) -> bool:
	return enabled and (last_check <= 0 or now - last_check >= CHECK_INTERVAL_SECONDS or now < last_check)


## Picks the newest release that is newer than `current` from the GitHub
## /releases JSON. Drafts, tags that are not semver (the old v1.7.0a scheme) and
## excluded prereleases are skipped. With `require_installer`, a release only
## counts when it carries both the Windows setup and the checksum file; without
## it (portable copies, other platforms) the release page is enough.
##
## Returns {} when nothing qualifies, otherwise:
##   version, tag, name, page_url, prerelease,
##   setup_name, setup_url, setup_size, checksums_url   (empty when absent)
static func pick_update(releases: Variant, current: String, allow_prereleases: bool, require_installer: bool) -> Dictionary:
	if not releases is Array:
		return {}
	var best := {}
	for release in releases:
		if not release is Dictionary:
			continue
		if bool(release.get("draft", false)):
			continue
		var prerelease := bool(release.get("prerelease", false))
		if prerelease and not allow_prereleases:
			continue
		var tag := String(release.get("tag_name", ""))
		if not AppVersion.is_valid(tag):
			continue
		var version := tag.trim_prefix("v")
		if AppVersion.compare(version, current) <= 0:
			continue
		if not best.is_empty() and AppVersion.compare(version, best["version"]) <= 0:
			continue
		var candidate := {
			"version": version,
			"tag": tag,
			"name": String(release.get("name", tag)),
			"page_url": String(release.get("html_url", "")),
			"prerelease": prerelease,
			"setup_name": "",
			"setup_url": "",
			"setup_size": 0,
			"checksums_url": "",
		}
		var assets: Variant = release.get("assets", [])
		if assets is Array:
			for asset in assets:
				if not asset is Dictionary:
					continue
				var asset_name := String(asset.get("name", ""))
				if asset_name == setup_asset_name(version):
					candidate["setup_name"] = asset_name
					candidate["setup_url"] = String(asset.get("browser_download_url", ""))
					candidate["setup_size"] = int(asset.get("size", 0))
				elif asset_name == CHECKSUMS_ASSET:
					candidate["checksums_url"] = String(asset.get("browser_download_url", ""))
		if require_installer and (candidate["setup_url"].is_empty() or candidate["checksums_url"].is_empty()):
			continue
		if candidate["page_url"].is_empty() and candidate["setup_url"].is_empty():
			continue
		best = candidate
	return best


## The lowercase SHA-256 listed for `file_name` in a sha256sum-style file
## ("<hex>  <name>" or "<hex> *<name>"), or "" when it is not listed.
static func checksum_for(sums_text: String, file_name: String) -> String:
	for raw_line in sums_text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		var space := line.find(" ")
		if space != 64:
			continue
		var digest := line.substr(0, 64).to_lower()
		var listed := line.substr(space).strip_edges().trim_prefix("*")
		if listed == file_name and _is_hex(digest):
			return digest
	return ""


## Only a copy the installer put in place may replace itself; Inno Setup leaves
## its uninstaller beside the executable. The portable zip links to the page.
static func is_installed_copy(executable_path: String, is_windows: bool) -> bool:
	if not is_windows:
		return false
	var directory := executable_path.get_base_dir()
	return FileAccess.file_exists(directory.path_join("unins000.exe"))


static func installer_arguments() -> PackedStringArray:
	return PackedStringArray(["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CLOSEAPPLICATIONS", "/RELAUNCH"])


static func _is_hex(text: String) -> bool:
	for character in text:
		if not character in "0123456789abcdef":
			return false
	return true
