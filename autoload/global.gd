extends Node

const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")
const InputCommands = preload("res://autoload/input/input_commands.gd")
const ZIndexEditor = preload("res://ui_scenes/zIndex/z_index_editor.gd")

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")

const MicrophoneMonitorService = preload("res://autoload/runtime/microphone_monitor.gd")
const BlinkSchedulerService = preload("res://autoload/runtime/blink_scheduler.gd")
const SpriteRegistryService = preload("res://autoload/domain/sprite_registry.gd")
const SelectionStateService = preload("res://autoload/domain/selection_state.gd")

# Shared UI layout constants used by both sidebar panels. ROW_GAP is the
# baseline vertical distance between adjacent widgets; DIVIDER_PAD is the
# padding on EACH side of a divider line. Tuning either reflows every panel
# that uses them, so the two sidebars (and any future panels) stay in sync.
const UI_ROW_GAP = 8
const UI_DIVIDER_PAD = 12

#Global Node Reference
var main = null
var spriteEdit = null
var fail = null
var mouse = null
var spriteList = null
var chain = null
var _sprite_registry := SpriteRegistryService.new()
var _selection_state := SelectionStateService.new()

var animationTick = 0

var cursorWorldPos = Vector2.ZERO
var _cursorScreenToWorldOffset: Vector2 = Vector2.ZERO

var filtering = true
var _text_field_active: bool = false
var _z_editor: Node2D = null
var _z_style_normal: StyleBoxFlat = null
var _z_style_focus: StyleBoxFlat = null
var _suppress_keys_frame: int = -1

var _screenshot_key_held: bool = false
var _screenshot_press_time: int = 0

# Object selection remains readable through the long-standing Global property,
# but writes go through select_sprite()/clear_selection() so invalidation and
# click-cycle state cannot diverge.
var heldSprite:
	get:
		return _selection_state.current

var reparentMode = false

# Eye-tracking layer pick mode: active while the user is whip-picking a target
# layer for the held sprite's eye tracking. Source sprite is captured at pick start.
var eyeTrackPickMode: bool = false
var eyeTrackPickSource = null
# When true, the next picked sprite broadcasts to every sprite with eyeTrack on.
# When false, only eyeTrackPickSource is assigned.
var eyeTrackPickBroadcast: bool = false

# Global kill switch for eye tracking. Toggled from the eye section's enable
# checkbox while in global scope (no sprite selected, ≥1 sprite has eyeTrack on).
# Sprite-level eyeTrack flags are never modified by this switch.
var eyeTrackingGloballyEnabled: bool = true
var originMode = false
# On while tracing a layer's wiggle ribbon path on the canvas (entered from the
# Physics tab). Canvas clicks are routed to the WigglePathEditor instead of the
# usual sprite selection while this is set.
var wigglePathMode = false
var awaitingToggleBind = false
# Animation-tab "Bind key" capture: while awaitingAnimKeyBind, the next background
# keypress is written into animKeyBindClip["key"] (a live clip dict on a sprite's
# animClips) instead of triggering animations. Set by ui_scenes/spriteEditMenu's
# Animation tab, consumed in main.gd's bg key handler.
var awaitingAnimKeyBind = false
var animKeyBindClip = null
var _origin_press_time = 0
var scrollSelection = 0
var _scroll_input = 0

var backgroundColor = Color(0.0,0.0,0.0,0.0) 

#Blink
var blinkSpeed = 1.0
var blinkChance = 200
var blink = false
var blinkTick = 0

#Audio Listener

var speaking = false
var micMuted = false
var spectrum
var volume = 0
var volumeSensitivity = 0.0

var volumeLimit = 0.0
var senseLimit = 0.0

#Speak Signals
signal startSpeaking
signal stopSpeaking
signal notification_requested(text: String)
signal selection_changed(current: Object, previous: Object)

var _microphone_monitor = null
var _blink_scheduler = BlinkSchedulerService.new()

# Right-click a slider to reset it to its registered default. Stores the default
# in node metadata and attaches a one-shot gui_input listener; calling again on
# the same slider just updates the default without double-connecting.
func make_slider_resettable(slider: Range, default_value):
	if slider == null:
		return
	slider.set_meta("_reset_default", default_value)
	if slider.has_meta("_reset_registered"):
		return
	slider.set_meta("_reset_registered", true)
	slider.gui_input.connect(func(event: InputEvent):
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
			return
		if not is_instance_valid(slider):
			return
		slider.accept_event()
		var default = slider.get_meta("_reset_default")
		# Skip if already at default so we don't push a redundant undo snapshot via
		# the slider's value_changed handler
		if is_equal_approx(slider.value, default):
			notify_user("Already at default.")
			return
		slider.value = default
		notify_user("Reset to default."))

func _ready():
	_selection_state.changed.connect(_on_selection_changed)
	_microphone_monitor = MicrophoneMonitorService.new()
	_microphone_monitor.name = "MicrophoneMonitor"
	add_child(_microphone_monitor)
	_microphone_monitor.speaking_started.connect(_on_microphone_speaking_started)
	_microphone_monitor.speaking_stopped.connect(_on_microphone_speaking_stopped)
	# Automated production-scene checks verify real scene lifecycles without
	# opening the host's capture device or consuming persisted configuration.
	if not Saving.is_isolated_session():
		_microphone_monitor.initialize(Saving.settings.get("audioDevice", ""))
	spectrum = _microphone_monitor.spectrum


func attach_main(main_node: Node) -> void:
	main = main_node


func attach_failure_overlay(overlay: CanvasItem) -> void:
	fail = overlay


func attach_mouse(mouse_node: Node2D) -> void:
	mouse = mouse_node


func detach_mouse(mouse_node: Node2D) -> void:
	if mouse == mouse_node:
		mouse = null


func attach_sprite_edit(editor: CanvasItem) -> void:
	spriteEdit = editor


func detach_sprite_edit(editor: CanvasItem) -> void:
	if spriteEdit == editor:
		spriteEdit = null


func attach_sprite_list(list_node: CanvasItem) -> void:
	spriteList = list_node


func detach_sprite_list(list_node: CanvasItem) -> void:
	if spriteList == list_node:
		spriteList = null


func attach_chain(chain_node: Node2D) -> void:
	chain = chain_node


func detach_chain(chain_node: Node2D) -> void:
	if chain == chain_node:
		chain = null


func detach_main(main_node: Node) -> void:
	if main != main_node:
		return
	main = null
	fail = null
	_z_editor = null
	clear_selection()
	spriteEdit = null
	spriteList = null
	mouse = null
	chain = null
	reparentMode = false
	originMode = false
	wigglePathMode = false
	eyeTrackPickMode = false
	eyeTrackPickSource = null
	eyeTrackPickBroadcast = false
	_sprite_registry.clear()


func register_sprite(sprite: Object) -> void:
	_sprite_registry.register(sprite)


func unregister_sprite(sprite: Object) -> void:
	if heldSprite == sprite:
		clear_selection()
	_sprite_registry.unregister(sprite)


func sprite_by_id(sprite_id: Variant) -> Object:
	return _sprite_registry.by_id(sprite_id)


func sprite_nodes() -> Array:
	return _sprite_registry.all()


func sprite_count() -> int:
	return _sprite_registry.size()


func maximum_sprite_z() -> int:
	return _sprite_registry.maximum_z()


func is_eye_track_target(sprite_id: Variant) -> bool:
	return _sprite_registry.is_eye_target(sprite_id)


func select_sprite(sprite: Object) -> Object:
	return _selection_state.select(sprite)


func clear_selection() -> Object:
	return _selection_state.clear()



func sprite_from_hit_area(area: Area2D) -> Node:
	## Sprite selection Area2Ds are nested exactly three levels below the sprite
	## root. Keep that scene-shape knowledge here rather than duplicating fragile
	## parent chains in input and selection consumers.
	var current: Node = area
	for _level in range(3):
		if current == null:
			return null
		current = current.get_parent()
	return current


func is_text_entry_active() -> bool:
	return _text_field_active


func has_text_entry_focus() -> bool:
	return _is_any_field_focused()


func is_z_index_editor_active() -> bool:
	return _z_editor != null and _z_editor.is_active()


func begin_reparenting() -> bool:
	if heldSprite == null:
		return false
	reparentMode = true
	originMode = false
	wigglePathMode = false
	if is_instance_valid(chain):
		chain.enable(true)
	return true


func set_wiggle_path_editing(enabled: bool) -> void:
	wigglePathMode = enabled and heldSprite != null
	if wigglePathMode:
		reparentMode = false
		originMode = false


func begin_eye_track_pick(source: Object = null, broadcast: bool = false) -> void:
	eyeTrackPickMode = true
	eyeTrackPickSource = source
	eyeTrackPickBroadcast = broadcast


func cancel_eye_track_pick() -> void:
	_clear_eye_track_pick()


func finish_eye_track_pick(target: Object) -> void:
	_finish_eye_track_pick(target)


func begin_animation_key_capture(clip: Dictionary) -> void:
	awaitingAnimKeyBind = true
	animKeyBindClip = clip


# True while the animation tab's "Bind key" is armed, so the input decoder can
# route the next background key to the binding instead of triggering clips.
func is_awaiting_animation_key_capture() -> bool:
	return awaitingAnimKeyBind and animKeyBindClip != null


func apply_animation_key_capture(key: String) -> bool:
	if not awaitingAnimKeyBind or animKeyBindClip == null:
		return false
	animKeyBindClip["key"] = key
	awaitingAnimKeyBind = false
	animKeyBindClip = null
	return true


func begin_visibility_key_capture() -> void:
	awaitingToggleBind = true


func finish_visibility_key_capture() -> void:
	awaitingToggleBind = false


func _on_selection_changed(current: Object, previous: Object) -> void:
	selection_changed.emit(current, previous)


func _exit_tree() -> void:
	if is_instance_valid(_microphone_monitor):
		_microphone_monitor.shutdown()


func selectMicrophone(device_name: String, restart_delay_seconds: float = 1.0) -> bool:
	if not is_instance_valid(_microphone_monitor):
		return false
	return _microphone_monitor.select_device(device_name, restart_delay_seconds)

func _on_microphone_speaking_started() -> void:
	speaking = true
	startSpeaking.emit()


func _on_microphone_speaking_stopped() -> void:
	speaking = false
	stopSpeaking.emit()


func _process(delta):
	_text_field_active = _is_any_field_focused()
	animationTick += 1

	if is_instance_valid(main):
		cursorWorldPos = Vector2(DisplayServer.mouse_get_position()) + _cursorScreenToWorldOffset

	_update_microphone(delta)
	blinking()
	if not is_instance_valid(main):
		return
	
	_run_key_commands()

	if main != null and heldSprite != null and !_text_field_active:
		if main.editMode:
			if wigglePathMode and Input.is_action_just_pressed("ui_cancel"):
				wigglePathMode = false
				notify_user("Finished editing ribbon path.")
			if Input.is_action_just_pressed("origin"):
				_origin_press_time = Time.get_ticks_msec()
			if Input.is_action_pressed("origin") and !originMode:
				if Time.get_ticks_msec() - _origin_press_time >= 300:
					originMode = true
					reparentMode = false
					wigglePathMode = false
					if is_instance_valid(chain):
						chain.enable(false)
					notify_user("Origin adjustment mode.")
			if Input.is_action_just_released("origin"):
				if Time.get_ticks_msec() - _origin_press_time < 300:
					if heldSprite != null:
						MutationCommands.structural(func():
							heldSprite.snapOriginToMouse()
							return true)
						notify_user("Snapped origin to cursor.")
				else:
					if originMode:
						originMode = false
						notify_user("Exited origin adjustment mode.")

	else:
		reparentMode = false
		originMode = false
		wigglePathMode = false
		if is_instance_valid(chain):
			chain.enable(reparentMode)

	if main.editMode:
		if reparentMode:
			RenderingServer.set_default_clear_color(Color(0.18, 0.25, 0.35))
		elif wigglePathMode:
			RenderingServer.set_default_clear_color(Color(0.28, 0.20, 0.25))
		elif originMode or eyeTrackPickMode:
			RenderingServer.set_default_clear_color(Color(0.25, 0.18, 0.3))
		else:
			RenderingServer.set_default_clear_color(Color(0.3, 0.3, 0.3))

	
	scrollSprites()

	# Screenshot/record key release (outside control block so release is caught
	# even if Ctrl is released before K)
	if _screenshot_key_held and Input.is_action_just_released("screenshot"):
		main.onScreenshotReleased()
		_screenshot_key_held = false


# Foreground key commands. The decoder owns which action maps to which command
# and every guard that suppresses it; this loop only runs what it is handed.
func _run_key_commands() -> void:
	var fired := {}
	for action in InputCommands.FOREGROUND_ORDER:
		fired[action] = Input.is_action_just_pressed(action)
	var commands: Array = InputCommands.decode_foreground(fired, {
		"has_selection": heldSprite != null,
		"edit_mode": main.editMode,
		"control_held": Input.is_action_pressed("control"),
		"text_focus": _text_field_active,
		"file_dialog_open": main.fileSystemOpen,
	})
	for command in commands:
		_run_key_command(command)


func _run_key_command(command: String) -> void:
	match command:
		"layer_depth_down":
			_nudge_z(-1)
		"layer_depth_up":
			_nudge_z(1)
		"toggle_reparent_mode":
			reparentMode = !reparentMode
			originMode = false
			wigglePathMode = false
			if is_instance_valid(chain):
				chain.enable(reparentMode)
		"unlink_layer":
			if heldSprite != null and heldSprite.parentId != null:
				MutationCommands.structural(func():
					unlinkSprite()
					return true)
		"refresh_avatar":
			refresh()
		"save_images":
			saveImagesFromData()
		"undo":
			UndoManager.undo()
		"redo":
			UndoManager.redo()
		"screenshot_press":
			_screenshot_key_held = true
			_screenshot_press_time = Time.get_ticks_msec()
			main.onScreenshotPressed()


func _update_microphone(delta: float) -> void:
	if not is_instance_valid(_microphone_monitor):
		volume = 0.0
		volumeSensitivity = 0.0
		speaking = false
		return
	_microphone_monitor.volume_limit = volumeLimit
	_microphone_monitor.sense_limit = senseLimit
	_microphone_monitor.muted = micMuted
	_microphone_monitor.sample(delta, Input.is_action_pressed("simMic"))
	volume = _microphone_monitor.volume
	volumeSensitivity = _microphone_monitor.sensitivity
	speaking = _microphone_monitor.speaking
	spectrum = _microphone_monitor.spectrum
	
	
# One discrete history entry per key press, matching the pre-command behavior
# (is_action_just_pressed fires once per press, so this is not a held gesture).
func _nudge_z(step: int) -> void:
	MutationCommands.structural(func():
		heldSprite.z += step
		heldSprite.setZIndex()
		return true)
	notify_user("Moved sprite layer.")


# The z-index overlay is a UI component; Global keeps only the routing surface.
func _show_z_input() -> void:
	if heldSprite == null or main == null:
		return
	if _z_editor == null or not is_instance_valid(_z_editor):
		_z_editor = ZIndexEditor.new()
		main.add_child(_z_editor)
		_z_editor.setup(self)
	_z_editor.open()


func _hide_z_input() -> void:
	if _z_editor != null and is_instance_valid(_z_editor):
		_z_editor.close()
	_suppress_keys_frame = Engine.get_process_frames()


func _is_any_field_focused() -> bool:
	if _suppress_keys_frame == Engine.get_process_frames():
		return true
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _input(event):
	# Refresh screen-to-world offset whenever the cursor is inside the window,
	# so out-of-window tracking can extrapolate from DisplayServer.mouse_get_position().
	if event is InputEventMouseMotion and main != null:
		_cursorScreenToWorldOffset = main.get_global_mouse_position() - Vector2(DisplayServer.mouse_get_position())

	# Z-index overlay: Escape to cancel, click outside to dismiss, N to open
	if event is InputEventKey and event.pressed and !event.echo:
		if is_z_index_editor_active():
			if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
				_hide_z_input()
				get_viewport().set_input_as_handled()
				return
		elif main != null and !main.fileSystemOpen and heldSprite != null and main.editMode:
			if event.physical_keycode == KEY_N and !_is_any_field_focused():
				_show_z_input()
				get_viewport().set_input_as_handled()
				return
	if is_z_index_editor_active() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _z_editor.is_click_outside(main.get_global_mouse_position()):
			_hide_z_input()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if reparentMode:
			reparentMode = false
			if is_instance_valid(chain):
				chain.enable(false)
			notify_user("Linking cancelled.")
			get_viewport().set_input_as_handled()
			return
		if eyeTrackPickMode:
			_clear_eye_track_pick()
			notify_user("Eye target pick cancelled.")
			get_viewport().set_input_as_handled()
			return
	# Wheel while the cursor is over a sidebar (left/right panel or top bar):
	# the avatar must not zoom or cycle selection. A slider/spinbox under the
	# cursor adjusts by one step only while Ctrl is held, and that case is
	# consumed so the section doesn't move. Without Ctrl the wheel is NOT
	# consumed: it falls through so the enclosing scrollable section scrolls
	# instead (sidebar sliders are scrollable=false, so they don't self-adjust on
	# the pass-through; the right sidebar's ScrollContainer and the left sidebar's
	# position.y scroll in sprite_viewer._input both pick it up). Either way we
	# return so the wheel never reaches the sprite-cycle accumulator below.
	# Sliders outside the sidebars (settings, volume) keep default wheel behavior.
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if isMouseOverSidebar():
			var rng := _hovered_range()
			if rng != null and Input.is_action_pressed("control"):
				var ed = rng.get("editable")
				if ed == null or bool(ed):
					var stp: float = rng.step if rng.step > 0.0 else 1.0
					if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
						stp = -stp
					rng.value = clampf(rng.value + stp, rng.min_value, rng.max_value)
				get_viewport().set_input_as_handled()
			return
	if !Input.is_action_pressed("control"):
		if event.is_action_pressed("scrollUp"):
			_scroll_input += 1
		if event.is_action_pressed("scrollDown"):
			_scroll_input -= 1

# True while the cursor is over application chrome rather than the canvas: the
# left/right sidebars and top menu bar in edit mode, the revealed portion of the
# menu bar in viewer mode. Screen-space bounds are used because the panel
# backgrounds are MOUSE_FILTER_IGNORE, so gui_get_hovered_control() reads null
# over their blank areas. Shared by the zoom guard, the Ctrl+scroll slider
# nudge, and the sprite-cycle scroll accumulator. Bounds match mouse_cursor.gd.
func isMouseOverSidebar() -> bool:
	if main == null:
		return false
	var vp = get_viewport()
	if vp == null:
		return false
	var left_width := -1.0 if spriteEdit == null else float(spriteEdit.panel_width)
	var right_width := -1.0 if spriteList == null else float(spriteList.panel_width)
	return SidebarUIFactory.is_over_app_chrome(
		vp.get_mouse_position(),
		vp.get_visible_rect().size,
		main.editMode,
		left_width,
		right_width,
		SidebarUIFactory.MENU_BAR_HEIGHT,
		SidebarUIFactory.LEFT_CHROME_PADDING,
		SidebarUIFactory.RIGHT_CHROME_PADDING,
		main.controlPanel.chrome_height(),
	)

# Walk up from the control under the cursor to the nearest Range (HSlider /
# VSlider / SpinBox). Null when the cursor is not over an adjustable range.
func _hovered_range() -> Range:
	var ctl = get_viewport().gui_get_hovered_control()
	while ctl != null:
		if ctl is Range:
			return ctl
		ctl = ctl.get_parent_control()
	return null

func select(areas):

	if main.fileSystemOpen:
		return

	for area in areas:
		if area.is_in_group("canvas_input_blocker"):
			return

	# Eye-track pick mode consumes the click; empty clicks are a no-op so the user
	# doesn't accidentally deselect the source sprite mid-pick. Right-click cancels.
	if eyeTrackPickMode:
		if areas.size() > 0:
			var picked = sprite_from_hit_area(areas[0])
			_finish_eye_track_pick(picked)
		return

	var prevSpr = heldSprite
	if areas.size() <= 0:
		clear_selection()
		originMode = false
		wigglePathMode = false
		return

	_selection_state.choose_from_hits(areas, sprite_from_hit_area)
	if heldSprite == null:
		return
	
	var count = heldSprite.path.get_slice_count("/") - 1
	var i1 = heldSprite.path.get_slice("/",count)
	notify_user("Selected sprite \"" + i1 + "\"" + ".")
	
	heldSprite.set_physics_process(true)
	
	if reparentMode:
		if prevSpr == heldSprite:
			reparentMode = false
			return
		if heldSprite.parentId == prevSpr.id:
			return
		
		MutationCommands.structural(func():
			linkSprite(prevSpr, heldSprite)
			return true)
		if is_instance_valid(chain):
			chain.enable(reparentMode)
	
	spriteEdit.setImage()

func _finish_eye_track_pick(target):
	if target == null or (not eyeTrackPickBroadcast and eyeTrackPickSource == null):
		_clear_eye_track_pick()
		return
	if not eyeTrackPickBroadcast and target == eyeTrackPickSource:
		notify_user("A sprite can't eye-track itself.")
		_clear_eye_track_pick()
		return
	if eyeTrackPickBroadcast:
		var receivers: Array = []
		for spr in sprite_nodes():
			if spr.eyeTrack and spr != target:
				receivers.append(spr)
		MutationCommands.structural(func():
			for spr in receivers:
				spr.eyeTrackTargetId = target.id
			return not receivers.is_empty())
		notify_user("Eye target set on " + str(receivers.size()) + " layer(s).")
	else:
		MutationCommands.set_layer_property(eyeTrackPickSource, "eyeTrackTargetId", target.id)
		notify_user("Eye target set to \"" + target.path.get_file() + "\".")
	_flash_pink(target)
	_clear_eye_track_pick()
	if spriteList != null:
		spriteList.refreshEyeUI()

# Brief pink flash on a sprite — used to confirm an eye-track target pick.
# Color matches the layer panel's slider fill so the visual cue is consistent.
func _flash_pink(target):
	if not is_instance_valid(target):
		return
	target.modulate = Color(1.0, 0.7, 0.8)
	var tween = create_tween()
	tween.tween_property(target, "modulate", Color.WHITE, 0.4)

func _clear_eye_track_pick():
	eyeTrackPickMode = false
	eyeTrackPickSource = null
	eyeTrackPickBroadcast = false
	if spriteList != null:
		spriteList.refreshEyePickWhip()

func linkSprite(sprite,newParent):
	if sprite == newParent:
		reparentMode = false

		return
	if newParent.parentId == sprite.id:
		reparentMode = false
		return

	if sprite.is_ancestor_of(newParent):
		notify_user("Can't link to own child sprite!")
		reparentMode = false
		return

	# Zero all ancestor wobbles for stable reparent position
	var saved_wobbles = []
	var current = sprite
	while current != null:
		saved_wobbles.append([current, current.wob.position])
		current.wob.position = Vector2.ZERO
		current = current.parentSprite
	current = newParent
	while current != null:
		var already_saved = false
		for entry in saved_wobbles:
			if entry[0] == current:
				already_saved = true
				break
		if not already_saved:
			saved_wobbles.append([current, current.wob.position])
			current.wob.position = Vector2.ZERO
		current = current.parentSprite

	sprite.reparent(newParent.sprite,true)

	for entry in saved_wobbles:
		entry[0].wob.position = entry[1]

	sprite.parentId = newParent.id
	sprite.parentSprite = newParent

	# Brief pink flash on the new parent — same confirmation cue the eye-track
	# layer pick uses, applied here so successful links feel consistent.
	_flash_pink(newParent)

	reparentMode = false

	Global.spriteList._pending_scroll_target = newParent
	Global.spriteList.refreshHierarchy()
	
	var count = sprite.path.get_slice_count("/") - 1
	var i1 = sprite.path.get_slice("/",count)
	
	count = newParent.path.get_slice_count("/") - 1
	var i2 = newParent.path.get_slice("/",count)
	
	notify_user("Linked sprite \"" + i1 + "\" to sprite \"" + i2 + "\".")
	newParent.set_physics_process(true)

func scrollSprites():
	var scroll = _scroll_input
	_scroll_input = 0

	if originMode:
		return

	if Input.is_action_pressed("control"):
		return

	if !main.editMode:
		return

	if main.fileSystemOpen:
		return

	if get_viewport().gui_get_hovered_control() != null and !is_z_index_editor_active():
		return

	if heldSprite == null:
		scrollSelection = 0

	if scroll == 0:
		return
	
	
	var obj = sprite_nodes()
	
	if obj.size() <= 0:
		return
	
	scrollSelection += scroll
	if scrollSelection >= obj.size():
		scrollSelection = 0
	elif scrollSelection < 0:
		scrollSelection = obj.size() - 1
	
	select_sprite(obj[scrollSelection])
	
	var count = heldSprite.path.get_slice_count("/") - 1
	var i1 = heldSprite.path.get_slice("/",count)
	notify_user("Selected sprite \"" + i1 + "\"" + ".")
	
	heldSprite.set_physics_process(true)

	spriteEdit.setImage()

	if _z_editor != null and is_instance_valid(_z_editor):
		_z_editor.sync_to_selection()

func blinking():
	_blink_scheduler.speed = maxf(blinkSpeed, 0.0)
	_blink_scheduler.chance = maxi(int(blinkChance), 1)
	_blink_scheduler.active = blink
	_blink_scheduler.tick = blinkTick
	blink = _blink_scheduler.advance()
	blinkTick = _blink_scheduler.tick
	
func epicFail(err):
	print(fail)
	if fail == null:
		return
	
	fail.get_node("type").text = ""
	match err:
		ERR_FILE_CORRUPT:
			fail.get_node("type").text = "FILE CORRUPT"
		ERR_FILE_NOT_FOUND:
			fail.get_node("type").text = "FILE NOT FOUND"
		ERR_FILE_CANT_OPEN:
			fail.get_node("type").text = "FILE CANT OPEN"
		ERR_FILE_ALREADY_IN_USE:
			fail.get_node("type").text = "FILE IN USE"
		ERR_FILE_NO_PERMISSION:
			fail.get_node("type").text = "MISSING PERMISSION"
		ERR_INVALID_DATA:
			fail.get_node("type").text = "DATA INVALID"
		ERR_FILE_CANT_READ:
			fail.get_node("type").text = "CANT READ FILE"
	
	fail.visible = true
	await get_tree().create_timer(2.5).timeout
	fail.visible = false

func refresh():
	var objs = sprite_nodes()
	for object in objs:
		object.replaceSprite(object.path)
		object.sprite.frame = 0
		object.remadePolygon = false
	notify_user("Refreshed all sprites.")

func unlinkChildren(parentSpr):
	var children = parentSpr.getAllLinkedSprites()
	if children.size() == 0:
		return
	var saved_wob = parentSpr.wob.position
	parentSpr.wob.position = Vector2.ZERO
	for child in children:
		var glob = child.global_position
		child.reparent(main.origin, false)
		child.parentId = null
		child.parentSprite = null
		child.position = glob - main.origin.position
	parentSpr.wob.position = saved_wob

func unlinkSprite():
	if heldSprite == null:
		return
	if heldSprite.parentId == null:
		return

	# Zero all ancestor wobbles for stable position calculation
	var saved_wobbles = []
	var current = heldSprite
	while current != null:
		saved_wobbles.append([current, current.wob.position])
		current.wob.position = Vector2.ZERO
		current = current.parentSprite

	var glob = heldSprite.global_position
	glob = Vector2(int(glob.x),int(glob.y))

	heldSprite.reparent(main.origin, false)
	heldSprite.set_owner(main.origin)
	heldSprite.parentId = null
	heldSprite.parentSprite = null
	heldSprite.position = glob - main.origin.position

	for entry in saved_wobbles:
		entry[0].wob.position = entry[1]

	Global.spriteList.refreshHierarchy()
	notify_user("Unlinked sprite.")

func saveImagesFromData():
	var sprites = sprite_nodes()
	if sprites.size() <= 0:
		return
	for sprite in sprites:
		var img = sprite.imageData
		var array = sprite.path.split("/",false)
		var length = sprite.path.length() - array[array.size()-1].length()
		
		DirAccess.make_dir_recursive_absolute(sprite.path.left(length-1))
		img.save_png(sprite.path)
	
	notify_user("Saved all avatar images to computer.")
	
func notify_user(text: String) -> void:
	notification_requested.emit(text)

