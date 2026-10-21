extends RefCounted

const BlinkScheduler = preload("res://autoload/runtime/blink_scheduler.gd")
const MicrophoneMonitor = preload("res://autoload/runtime/microphone_monitor.gd")
const AppVersion = preload("res://autoload/runtime/app_version.gd")
const UpdateFeed = preload("res://autoload/runtime/update_feed.gd")


func run(t) -> void:
	_test_app_version(t)
	_test_update_feed(t)
	_test_blink_scheduler(t)
	_test_microphone_envelope(t)
	_test_microphone_state_transitions(t)
	_test_global_source_boundaries(t)


# The updater decides whether a GitHub release is newer by this ordering, and
# Windows version resources carry the numeric form, so both must stay monotonic.
func _test_app_version(t) -> void:
	t.assert_true(AppVersion.is_valid("1.7.0-alpha.3"), "a prerelease version is valid")
	t.assert_true(AppVersion.is_valid("v1.7.0"), "a release tag with its v prefix is valid")
	t.assert_false(AppVersion.is_valid("1.7.0a"), "the old letter-suffix scheme is not comparable and is rejected")
	var ordered := ["1.6.1", "1.7.0-alpha.1", "1.7.0-alpha.3", "1.7.0-alpha.10", "1.7.0-beta.1", "1.7.0-rc.2", "1.7.0", "1.7.1-alpha.1", "1.10.0"]
	for index in range(ordered.size() - 1):
		t.assert_equal(AppVersion.compare(ordered[index], ordered[index + 1]), -1, "%s sorts before %s" % [ordered[index], ordered[index + 1]])
		t.assert_equal(AppVersion.compare(ordered[index + 1], ordered[index]), 1, "%s sorts after %s" % [ordered[index + 1], ordered[index]])
	t.assert_equal(AppVersion.compare("v1.7.0-beta.2", "1.7.0-beta.2"), 0, "a tag equals its version")
	t.assert_true(AppVersion.is_prerelease("1.7.0-rc.1"), "rc builds are prereleases")
	t.assert_false(AppVersion.is_prerelease("1.7.0"), "a plain version is a release")
	t.assert_equal(AppVersion.windows_numeric("1.7.0-alpha.3"), "1.7.0.3", "alpha N maps to build N")
	t.assert_equal(AppVersion.windows_numeric("1.7.0-beta.2"), "1.7.0.102", "beta N maps to build 100+N")
	t.assert_equal(AppVersion.windows_numeric("1.7.0-rc.1"), "1.7.0.201", "rc N maps to build 200+N")
	t.assert_equal(AppVersion.windows_numeric("1.7.0"), "1.7.0.1000", "a release outranks every prerelease build")


static func _release(tag: String, prerelease := false, assets := ["setup", "sums"], draft := false) -> Dictionary:
	var listed := []
	var version := tag.trim_prefix("v")
	if assets.has("setup"):
		listed.append({"name": "PixelLabStudio-v%s-Windows-x64-Setup.exe" % version, "browser_download_url": "https://dl/%s/setup" % version, "size": 1234})
	if assets.has("sums"):
		listed.append({"name": "SHA256SUMS.txt", "browser_download_url": "https://dl/%s/sums" % version, "size": 200})
	listed.append({"name": "PixelLabStudio-v%s-macOS-universal.zip" % version, "browser_download_url": "https://dl/%s/mac" % version})
	return {"tag_name": tag, "name": "PixelLab Studio " + tag, "html_url": "https://page/" + tag, "prerelease": prerelease, "draft": draft, "assets": listed}


# What the updater offers, from the shape GitHub's /releases endpoint returns.
func _test_update_feed(t) -> void:
	var releases := [
		_release("v1.7.0-alpha.3", true),
		_release("v1.7.0b", true),
		_release("v1.7.0-beta.1", true),
		_release("v1.6.1"),
		_release("v1.8.0", false, ["setup", "sums"], true),
	]
	t.assert_true(UpdateFeed.pick_update(releases, "1.6.1", false, true).is_empty(), "a stable user on the newest stable release is offered nothing")
	var beta := UpdateFeed.pick_update(releases, "1.7.0-alpha.3", true, true)
	t.assert_equal(beta.get("version"), "1.7.0-beta.1", "a pre-release user is offered the newest newer pre-release")
	t.assert_equal(beta.get("setup_url"), "https://dl/1.7.0-beta.1/setup", "the offer carries the Windows setup asset")
	t.assert_equal(beta.get("checksums_url"), "https://dl/1.7.0-beta.1/sums", "and the checksum file")
	t.assert_equal(beta.get("setup_size"), 1234, "and the setup size for download progress")
	t.assert_true(beta.get("prerelease"), "and says it is a pre-release")
	t.assert_true(UpdateFeed.pick_update(releases, "1.7.0-beta.1", true, true).is_empty(), "drafts and non-semver tags are never offered")
	t.assert_equal(UpdateFeed.pick_update(releases, "1.6.0", false, true).get("version"), "1.6.1", "stable users skip pre-releases")

	var stable := releases + [_release("v1.7.0")]
	t.assert_equal(UpdateFeed.pick_update(stable, "1.7.0-beta.1", true, true).get("version"), "1.7.0", "a release outranks the pre-releases before it")
	var no_installer := [_release("v1.7.1", false, ["sums"])]
	t.assert_true(UpdateFeed.pick_update(no_installer, "1.7.0", false, true).is_empty(), "a self-installing copy needs the setup asset")
	t.assert_equal(UpdateFeed.pick_update(no_installer, "1.7.0", false, false).get("page_url"), "https://page/v1.7.1", "a portable copy only needs the release page")
	t.assert_true(UpdateFeed.pick_update([_release("v1.7.1", false, ["setup"])], "1.7.0", false, true).is_empty(), "and the checksum file, since nothing unverified is run")
	t.assert_true(UpdateFeed.pick_update({"message": "API rate limit exceeded"}, "1.7.0", true, true).is_empty(), "an error object from GitHub is not a release list")
	t.assert_true(UpdateFeed.pick_update(null, "1.7.0", true, true).is_empty(), "an unparsable response offers nothing")

	var digest := "0123456789abcdef".repeat(4)
	var sums := "%s  PixelLabStudio-v1.7.0-Windows-x64-Setup.exe\r\n%s *other.zip\n" % [digest, "f".repeat(64)]
	t.assert_equal(UpdateFeed.checksum_for(sums, "PixelLabStudio-v1.7.0-Windows-x64-Setup.exe"), digest, "the setup's digest is read from SHA256SUMS.txt")
	t.assert_equal(UpdateFeed.checksum_for(sums, "other.zip"), "f".repeat(64), "binary-mode entries are read too")
	t.assert_equal(UpdateFeed.checksum_for(sums, "missing.exe"), "", "an unlisted file has no digest")
	t.assert_equal(UpdateFeed.checksum_for("zz  bad.exe", "bad.exe"), "", "a malformed line is ignored")

	var day := UpdateFeed.CHECK_INTERVAL_SECONDS
	t.assert_true(UpdateFeed.should_check(true, 1000, 0), "the first launch checks")
	t.assert_false(UpdateFeed.should_check(true, 1000 + day - 1, 1000), "checks are at most daily")
	t.assert_true(UpdateFeed.should_check(true, 1000 + day, 1000), "a day later it checks again")
	t.assert_true(UpdateFeed.should_check(true, 500, 1000), "a clock set backwards does not stop checks")
	t.assert_false(UpdateFeed.should_check(false, 1000 + day * 10, 0), "turning checks off stops them")
	t.assert_true(UpdateFeed.include_prereleases(false, "1.7.0-alpha.3"), "a pre-release build is offered pre-releases")
	t.assert_false(UpdateFeed.include_prereleases(false, "1.7.0"), "a release build is not, unless opted in")
	t.assert_true(UpdateFeed.include_prereleases(true, "1.7.0"), "opting in offers them")
	t.assert_equal(UpdateFeed.setup_asset_name("v1.7.0-rc.1"), "PixelLabStudio-v1.7.0-rc.1-Windows-x64-Setup.exe", "the setup name matches build.ps1")
	t.assert_true(UpdateFeed.installer_arguments().has("/RELAUNCH"), "a silent install relaunches the app")

	var install_dir := OS.get_temp_dir().path_join("pixlab-install-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(install_dir)
	var exe := install_dir.path_join("PixelLab Studio.exe")
	t.assert_false(UpdateFeed.is_installed_copy(exe, true), "a folder without the uninstaller is a portable copy")
	var uninstaller := FileAccess.open(install_dir.path_join("unins000.exe"), FileAccess.WRITE)
	uninstaller.close()
	t.assert_true(UpdateFeed.is_installed_copy(exe, true), "the uninstaller beside the exe marks an installed copy")
	t.assert_false(UpdateFeed.is_installed_copy(exe, false), "only Windows copies install updates themselves")
	DirAccess.remove_absolute(install_dir.path_join("unins000.exe"))
	DirAccess.remove_absolute(install_dir)


func _test_blink_scheduler(t) -> void:
	var scheduler := BlinkScheduler.new()
	scheduler.speed = 1.0
	scheduler.chance = 2
	scheduler.tick = 5.0
	t.assert_true(scheduler.advance_with_roll(0.0, 0.0), "a successful deterministic roll starts a blink")
	t.assert_equal(scheduler.tick, -12.0, "a blink retains the legacy twelve-frame duration")
	for _frame in range(11):
		scheduler.advance_with_roll(0.0, 1.0)
	t.assert_true(scheduler.active, "blink remains active before its final duration frame")
	scheduler.advance_with_roll(0.0, 1.0)
	t.assert_false(scheduler.active, "blink clears on the final duration frame")

	# The chance is per 60 fps frame, so a longer frame is proportionally more
	# likely to blink and the rate does not follow the frame rate.
	scheduler.chance = 2
	scheduler.tick = 100.0
	scheduler.active = false
	t.assert_false(scheduler.advance_with_roll(0.0, 0.6, 1.0), "a roll above the per-frame chance does not blink")
	scheduler.tick = 100.0
	t.assert_true(scheduler.advance_with_roll(0.0, 0.6, 2.0), "the same roll blinks on a frame worth two")
	scheduler.tick = 100.0
	scheduler.active = false
	t.assert_false(scheduler.advance_with_roll(0.0, 0.3, 0.5), "and does not on a frame worth half")

	# The same elapsed time gives the same blink count whatever the step.
	t.assert_equal(
		_blinks_over(BlinkScheduler.new(), 600, 1.0), _blinks_over(BlinkScheduler.new(), 150, 4.0),
		"blink count follows elapsed time, not frame count",
	)

	scheduler.chance = 0
	scheduler.speed = -5.0
	scheduler.tick = 1.0
	scheduler.advance_with_roll(0.0, 0.0)
	t.assert_true(scheduler.chance == 0, "invalid caller configuration is handled without mutating public preferences")
	t.assert_true(scheduler.active, "zero chance input is safely evaluated as one-in-one without division by zero")


# Blinks over `steps` steps, each worth `step` 60 fps frames, with a fixed roll
# sequence so the two step sizes see the same randomness per unit of time.
func _blinks_over(scheduler, steps: int, step: float) -> int:
	scheduler.speed = 1.0
	scheduler.chance = 60
	var blinks := 0
	var was := false
	var elapsed := 0.0
	for index in steps:
		elapsed += step
		# One deterministic "roll" per 60 fps frame worth of time.
		var roll := 0.0 if int(elapsed) % 120 < int(step) else 1.0
		var now: bool = scheduler.advance_with_roll(0.0, roll, step)
		if now and not was:
			blinks += 1
		was = now
	return blinks


func _test_microphone_envelope(t) -> void:
	# Level: the RMS of every frame, from whichever channel is louder.
	var steady := PackedVector2Array()
	var left_only := PackedVector2Array()
	for i in 480:
		var v := 0.5 if i % 2 == 0 else -0.5
		steady.append(Vector2(v, v))
		left_only.append(Vector2(v, 0.0))
	t.assert_approx(MicrophoneMonitor.buffer_rms(steady), 0.5, 0.00001, "RMS of a full-scale square at 0.5 is 0.5")
	t.assert_approx(MicrophoneMonitor.buffer_rms(left_only), 0.5, 0.00001, "a mono microphone on one channel is not read 3 dB low")
	t.assert_equal(MicrophoneMonitor.buffer_rms(PackedVector2Array()), 0.0, "no samples read as silence")
	t.assert_approx(MicrophoneMonitor.to_db(1.0), 0.0, 0.0001, "full scale is 0 dBFS")
	t.assert_approx(MicrophoneMonitor.to_db(0.1), -20.0, 0.0001, "a tenth of full scale is -20 dBFS")
	t.assert_equal(MicrophoneMonitor.to_db(0.0), MicrophoneMonitor.FLOOR_DB, "silence reads as the floor")

	# Envelope: fast up, slower down, and independent of the frame rate.
	var rise := MicrophoneMonitor.follow_envelope(0.0, 1.0, 1.0 / 60.0)
	var fall := 1.0 - MicrophoneMonitor.follow_envelope(1.0, 0.0, 1.0 / 60.0)
	t.assert_true(rise > 0.6, "the envelope follows a rising level within about a frame")
	t.assert_true(fall < rise * 0.5, "and lets a falling level go more slowly, which is what removes the flicker")
	var one_step := MicrophoneMonitor.follow_envelope(0.2, 0.8, 1.0 / 60.0)
	var two_steps := MicrophoneMonitor.follow_envelope(MicrophoneMonitor.follow_envelope(0.2, 0.8, 1.0 / 120.0), 0.8, 1.0 / 120.0)
	t.assert_approx(one_step, two_steps, 0.000001, "the envelope does not depend on the frame rate")
	t.assert_equal(MicrophoneMonitor.follow_envelope(0.3, 0.9, 0.0), 0.3, "a zero-length frame changes nothing")


func _test_microphone_state_transitions(t) -> void:
	var monitor := MicrophoneMonitor.new()
	monitor.threshold_db = -30.0
	# A thumb 200 ms short of full: the mouth stays open 200 ms after the voice.
	monitor.duration_threshold = MicrophoneMonitor.DURATION_FULL_MS - 200.0
	var transitions := {"started": 0, "stopped": 0}
	monitor.speaking_started.connect(func(): transitions["started"] += 1)
	monitor.speaking_stopped.connect(func(): transitions["stopped"] += 1)
	var frame := 1.0 / 60.0
	var loud := pow(10.0, -20.0 / 20.0)

	monitor.update_from_rms(loud, frame)
	t.assert_true(monitor.speaking, "a voice well over the threshold opens the gate on its first frame")
	t.assert_equal(transitions["started"], 1, "speaking start emits exactly once")
	for i in 30:
		monitor.update_from_rms(loud, frame)
	t.assert_equal(transitions["started"], 1, "steady speaking state does not emit duplicate starts")
	t.assert_approx(monitor.level_db, -20.0, 0.1, "the level settles on the voice's RMS in dBFS")
	t.assert_approx(monitor.duration, MicrophoneMonitor.DURATION_FULL_MS, 0.001, "while the gate is open the Duration bar is full")

	# Hysteresis: once open, a level just under the threshold keeps it open.
	var just_under := pow(10.0, -32.0 / 20.0)
	for i in 120:
		monitor.update_from_rms(just_under, frame)
	t.assert_true(monitor.speaking, "a level 2 dB under the threshold does not close an open gate")
	t.assert_approx(monitor.duration, MicrophoneMonitor.DURATION_FULL_MS, 0.001, "and does not start the Duration bar draining")

	# Silence: the envelope releases, the gate closes, and the hold drains.
	var frames_to_stop := 0
	while monitor.speaking and frames_to_stop < 600:
		monitor.update_from_rms(0.0, frame)
		frames_to_stop += 1
	t.assert_false(monitor.speaking, "silence closes the gate once the hold runs out")
	t.assert_equal(transitions["stopped"], 1, "one stop transition")
	var seconds := frames_to_stop * frame
	t.assert_true(seconds > 0.2 and seconds < 0.5, "the mouth closes after the release and the 200 ms hold, not at once (%.3f s)" % seconds)
	t.assert_true(monitor.duration <= monitor.duration_threshold, "the mouth closed as the Duration bar fell past its thumb")
	t.assert_true(monitor.duration > 0.0, "and before the bar emptied")

	# A gate that closed does not reopen below the threshold.
	for i in 120:
		monitor.update_from_rms(just_under, frame)
	t.assert_false(monitor.speaking, "a closed gate needs the full threshold to open again")

	monitor.update_from_rms(loud, frame)
	t.assert_true(monitor.speaking, "and opens again on a voice")
	monitor.muted = true
	monitor.update_from_rms(loud, frame)
	t.assert_false(monitor.speaking, "mute overrides an active microphone level")
	t.assert_equal(transitions["stopped"], 2, "mute emits one speaking stop transition")
	monitor.update_from_rms(0.0, frame, true)
	t.assert_true(monitor.speaking, "the simulate key still speaks while muted")
	monitor.update_from_rms(loud, frame)
	t.assert_false(monitor.speaking, "releasing the simulate key while muted closes the mouth")
	monitor.muted = false
	monitor.update_from_rms(0.0, frame, true)
	t.assert_true(monitor.speaking, "the simulate key speaks regardless of level")
	monitor.free()


func _test_global_source_boundaries(t) -> void:
	var source := FileAccess.get_file_as_string("res://autoload/global.gd")
	t.assert_true(source.contains("MicrophoneMonitorService"), "Global delegates microphone lifecycle to the runtime service")
	t.assert_true(source.contains("BlinkSchedulerService"), "Global delegates blink timing to the runtime service")
	t.assert_true(source.contains("signal notification_requested"), "Global exposes notifications as a lifecycle-safe signal")
	t.assert_false(source.contains("get_bus_effect_instance(1, 1)"), "audio lookup no longer depends on hard-coded bus/effect indexes")
	t.assert_false(source.contains("for child in get_children():\n\t\tchild.queue_free()"), "microphone reset no longer deletes unrelated Global children")
	t.assert_false(source.contains("updatePusherNode"), "Global no longer retains a stale-prone notification UI reference")
	var microphone_source := FileAccess.get_file_as_string("res://autoload/runtime/microphone_monitor.gd")
	t.assert_true(microphone_source.count("_player.stream = null") >= 2, "microphone stop and restart release native playback before player deletion")
	t.assert_true(microphone_source.contains("stop_microphone(true)"), "microphone shutdown frees native playback before the final deferred-delete pass")
