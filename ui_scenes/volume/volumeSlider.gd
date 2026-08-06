extends HSlider

func _ready() -> void:
	value_changed.connect(_on_value_changed)
	_on_value_changed(value)

func _on_value_changed(new_value: float) -> void:
	Global.volumeLimit = max_value - new_value
	Saving.settings["volume"] = new_value
