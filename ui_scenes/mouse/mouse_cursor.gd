extends Node2D

var text = ""
var _click_pending = false

@onready var label = $Tooltip/Label
@onready var area = $Area2D

func _ready():
	Global.mouse = self

func _unhandled_input(event):
	if event.is_action_pressed("mouse_left"):
		_click_pending = true

func _process(delta):
	if Global.main.editMode:
		if text != "":
			label.text = text
			visible = true
		else:
			visible = false
		global_position = get_global_mouse_position()
		if _click_pending:
			_click_pending = false
			if !Global.originMode:
				Global.select(area.get_overlapping_areas())
	else:
		_click_pending = false
		visible = false

	text = ""
