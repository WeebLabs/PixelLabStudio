extends MainLoop

const REQUIRED_NATIVE_CLASSES: Array[String] = [
	"BackgroundInputCapture",
	"PSDNative",
]


func _initialize() -> void:
	var missing: Array[String] = []
	for native_class_name in REQUIRED_NATIVE_CLASSES:
		if not ClassDB.class_exists(native_class_name):
			missing.append(native_class_name)

	if missing.is_empty():
		print("native_extension_smoke_test: all native classes loaded")
		return

	var message := "Missing native classes: %s" % ", ".join(missing)
	push_error(message)
	assert(missing.is_empty(), message)


func _process(_delta: float) -> bool:
	return true
