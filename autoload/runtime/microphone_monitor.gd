class_name MicrophoneMonitor
extends Node

signal speaking_started
signal speaking_stopped

## Voice detection, from the microphone's actual samples.
##
## Each frame the MIC bus's AudioEffectCapture hands over every sample that
## arrived since the last frame, and their RMS is the level. The bus's own filters
## keep that to the voice band first. An envelope follower then smooths the level
## with a fast attack and a slower release, and a gate with hysteresis and a hold
## turns it into "speaking": the Duration bar jumps to full whenever the gate is
## open, drains at 1 ms per ms once it closes, and the mouth stays open until the
## bar falls past its thumb.
##
## This replaced a spectrum-analyser reading: the loudest single FFT bin of the
## latest 256 samples, taken once a frame. That looked at about a third of the
## audio, landed on a random point in each pitch period, and ignored the energy
## spread across a voice's harmonics. It read about 5 dB low on a vowel and
## changed by 36-58% of its level from one frame to the next while speaking,
## against about 10% here (simulated on voice-like test signals).

# What silence reads as, and the bottom of the Level meter.
const FLOOR_DB := -60.0
# Rising levels are followed almost at once (about a frame), falling ones more
# slowly, which is what removes the flicker without delaying the mouth.
const ATTACK_SECONDS := 0.015
const RELEASE_SECONDS := 0.07
# The gate opens at the threshold and closes this far below it, so a level
# hovering at the threshold cannot chatter the mouth open and shut.
const HYSTERESIS_DB := 4.0
# Full scale of the Duration bar. It drains in real milliseconds, so a thumb at
# `duration_threshold` holds the mouth open DURATION_FULL_MS - duration_threshold
# ms after the voice stops: further left holds longer.
const DURATION_FULL_MS := 1000.0

# Set by Global from the viewer's two meters.
var threshold_db: float = -40.0
var duration_threshold: float = 850.0
var muted: bool = false

# Read by Global for the meters and the avatar.
var level_db: float = FLOOR_DB
var duration: float = 0.0
var speaking: bool = false

var _player: AudioStreamPlayer = null
var _restart_generation := 0
var _capture: AudioEffectCapture = null
var _envelope := 0.0
var _last_rms := 0.0
var _gate_open := false


func initialize(saved_device: String = "") -> void:
	if not saved_device.is_empty() and saved_device in AudioServer.get_input_device_list():
		AudioServer.input_device = saved_device
	_refresh_capture()
	start_microphone()


func sample(delta: float, simulate_speaking: bool = false) -> void:
	if _capture == null:
		_refresh_capture()
	# A frame can run before the audio thread has delivered anything new. That is
	# not silence, so the last measurement stands until fresh samples arrive.
	if _capture != null:
		var frames := _capture.get_frames_available()
		if frames > 0:
			_last_rms = buffer_rms(_capture.get_buffer(frames))
	update_from_rms(_last_rms, delta, simulate_speaking)


func update_from_rms(rms: float, delta: float, simulate_speaking: bool = false) -> void:
	_envelope = follow_envelope(_envelope, rms, delta)
	level_db = to_db(_envelope)
	if level_db >= threshold_db or (_gate_open and level_db >= threshold_db - HYSTERESIS_DB):
		_gate_open = true
		duration = DURATION_FULL_MS
	else:
		_gate_open = false
		duration = maxf(0.0, duration - delta * 1000.0)
	var next_speaking := not muted and (simulate_speaking or _gate_open or duration > duration_threshold)
	if next_speaking == speaking:
		return
	speaking = next_speaking
	if speaking:
		speaking_started.emit()
	else:
		speaking_stopped.emit()


# RMS of a block of stereo frames, taking the louder channel of each frame. A
# mono microphone can arrive on one channel only, and averaging it with a silent
# one would read 3 dB low.
static func buffer_rms(buffer: PackedVector2Array) -> float:
	if buffer.is_empty():
		return 0.0
	var total := 0.0
	for frame in buffer:
		total += maxf(frame.x * frame.x, frame.y * frame.y)
	return sqrt(total / buffer.size())


# One step of a one-pole envelope follower. The time constants are in seconds,
# so the result does not depend on the frame rate.
static func follow_envelope(previous: float, rms: float, delta: float) -> float:
	if delta <= 0.0:
		return previous
	var seconds := ATTACK_SECONDS if rms > previous else RELEASE_SECONDS
	return rms + (previous - rms) * exp(-delta / seconds)


static func to_db(amplitude: float) -> float:
	if amplitude <= 0.0:
		return FLOOR_DB
	return maxf(FLOOR_DB, 20.0 * log(amplitude) / log(10.0))


func start_microphone() -> void:
	if is_instance_valid(_player):
		return
	var player := AudioStreamPlayer.new()
	player.name = "MicrophoneCapture"
	player.stream = AudioStreamMicrophone.new()
	player.bus = &"MIC"
	add_child(player)
	player.play()
	_player = player
	# Whatever was captured before this start belongs to the previous device.
	if _capture != null:
		_capture.clear_buffer()


func stop_microphone(immediate: bool = false) -> void:
	_restart_generation += 1
	if is_instance_valid(_player):
		_player.stop()
		# Release the native microphone playback before deleting the player. A
		# SceneTree shutdown has no later deferred-delete pass, so it must free the
		# player synchronously after its stream reference has been cleared.
		_player.stream = null
		if immediate:
			_player.free()
		else:
			_player.queue_free()
	_player = null


func restart_microphone(delay_seconds: float = 0.0) -> void:
	_restart_generation += 1
	var generation := _restart_generation
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null
		_player.queue_free()
	_player = null
	if delay_seconds > 0.0:
		await get_tree().create_timer(delay_seconds).timeout
	if generation != _restart_generation or not is_inside_tree():
		return
	start_microphone()


func select_device(device_name: String, restart_delay_seconds: float = 1.0) -> bool:
	if not (device_name in AudioServer.get_input_device_list()):
		return false
	AudioServer.input_device = device_name
	restart_microphone(restart_delay_seconds)
	return true


func shutdown() -> void:
	stop_microphone(true)
	speaking = false
	level_db = FLOOR_DB
	duration = 0.0
	_envelope = 0.0
	_last_rms = 0.0
	_gate_open = false


func _refresh_capture() -> void:
	_capture = null
	var bus_index := AudioServer.get_bus_index(&"MIC")
	if bus_index < 0:
		return
	for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect := AudioServer.get_bus_effect(bus_index, effect_index)
		if effect is AudioEffectCapture:
			_capture = effect
			return
