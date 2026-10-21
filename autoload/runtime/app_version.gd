class_name AppVersion
extends RefCounted

## The app's version lives in one place: application/config/version in
## project.godot, as semver (1.7.0, 1.7.0-alpha.3, 1.7.0-beta.1, 1.7.0-rc.1).
## Release tags are "v" + that string; installer/windows/build.ps1 refuses a tag
## that doesn't match. The future updater compares GitHub release tags against
## current() with compare().

const PRERELEASE_RANKS := {"alpha": 0, "beta": 1, "rc": 2}
const RELEASE_RANK := 3
const PATTERN := "^(\\d+)\\.(\\d+)\\.(\\d+)(?:-(alpha|beta|rc)\\.(\\d+))?$"


static func current() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func is_valid(version: String) -> bool:
	return RegEx.create_from_string(PATTERN).search(version.trim_prefix("v")) != null


## [major, minor, patch, pre_rank, pre_number]. A release with no prerelease
## suffix outranks every prerelease of the same x.y.z, as in semver.
static func parse(version: String) -> Array[int]:
	var match := RegEx.create_from_string(PATTERN).search(version.strip_edges().trim_prefix("v"))
	if match == null:
		return [0, 0, 0, 0, 0] as Array[int]
	var label := match.get_string(4)
	var rank := int(PRERELEASE_RANKS.get(label, RELEASE_RANK))
	var number := match.get_string(5).to_int() if not label.is_empty() else 0
	return [match.get_string(1).to_int(), match.get_string(2).to_int(), match.get_string(3).to_int(), rank, number] as Array[int]


## -1 if a < b, 0 if equal, 1 if a > b.
static func compare(a: String, b: String) -> int:
	var left := parse(a)
	var right := parse(b)
	for index in range(left.size()):
		if left[index] != right[index]:
			return -1 if left[index] < right[index] else 1
	return 0


static func is_prerelease(version: String) -> bool:
	return parse(version)[3] != RELEASE_RANK


## Windows version resources are four 16-bit numbers, so the prerelease label
## folds into the fourth: alpha.N -> N, beta.N -> 100+N, rc.N -> 200+N,
## release -> 1000. Keeps builds of one x.y.z ordered. build.ps1 mirrors this.
static func windows_numeric(version: String) -> String:
	var parts := parse(version)
	var build := 1000
	if parts[3] != RELEASE_RANK:
		build = parts[3] * 100 + parts[4]
	return "%d.%d.%d.%d" % [parts[0], parts[1], parts[2], build]
