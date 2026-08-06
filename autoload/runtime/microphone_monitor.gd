class_name MicrophoneMonitor
extends Node

signal speaking_started
signal speaking_stopped

const FREQUENCY_MIN_HZ := 20.0
const FREQUENCY_MAX_HZ := 20000.0

var volume: float = 0.0
var sensitivity: float = 0.0
var volume_limit: float = 0.0
var sense_limit: float = 0.0
var muted: bool = false
var speaking: bool = false
var spectrum: AudioEffectSpectrumAnalyzerInstance = null

var _player: AudioStreamPlayer = null
var _restart_generation := 0


func initialize(saved_device: String = "") -> void:
	if not saved_device.is_empty() and saved_device in AudioServer.get_input_device_list():
		AudioServer.input_device = saved_device
	_refresh_spectrum()
	start_microphone()


func sample(delta: float, simulate_speaking: bool = false) -> void:
	if spectrum == null:
		_refresh_spectrum()
	var measured := 0.0
	if spectrum != null:
		measured = spectrum.get_magnitude_for_frequency_range(FREQUENCY_MIN_HZ, FREQUENCY_MAX_HZ).length()
	update_from_level(measured, delta, simulate_speaking)


func update_from_level(measured: float, delta: float, simulate_speaking: bool = false) -> void:
	volume = maxf(measured, 0.0)
	sensitivity = next_sensitivity(sensitivity, volume, volume_limit, delta)
	var next_speaking := not muted and (simulate_speaking or sensitivity > sense_limit)
	if next_speaking == speaking:
		return
	speaking = next_speaking
	if speaking:
		speaking_started.emit()
	else:
		speaking_stopped.emit()


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


func stop_microphone() -> void:
	_restart_generation += 1
	if is_instance_valid(_player):
		_player.stop()
		_player.queue_free()
	_player = null


func restart_microphone(delay_seconds: float = 0.0) -> void:
	_restart_generation += 1
	var generation := _restart_generation
	if is_instance_valid(_player):
		_player.stop()
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
	stop_microphone()
	speaking = false
	volume = 0.0
	sensitivity = 0.0


static func next_sensitivity(previous: float, measured: float, threshold: float, delta: float) -> float:
	var decayed := lerpf(previous, 0.0, clampf(delta * 2.0, 0.0, 1.0))
	return 1.0 if measured > threshold else decayed


func _refresh_spectrum() -> void:
	spectrum = null
	var bus_index := AudioServer.get_bus_index(&"MIC")
	if bus_index < 0:
		return
	for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
		var instance := AudioServer.get_bus_effect_instance(bus_index, effect_index)
		if instance is AudioEffectSpectrumAnalyzerInstance:
			spectrum = instance
			return
