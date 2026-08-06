extends RefCounted

const APNG = preload("res://autoload/apng_parser.gd")

func run(t) -> void:
	t.assert_false(APNG.is_apng("res://test/testBody.png"), "a normal PNG is not misidentified as APNG")
	t.assert_false(APNG.is_apng("res://tests/fixtures/missing.png"), "a missing file is rejected without an exception")

	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.0, 0.5, 1.0))
	var encoded := image.save_png_to_buffer()
	var decoded := Image.new()
	var error := decoded.load_png_from_buffer(encoded)
	t.assert_equal(error, OK, "Godot can round-trip the PNG buffers used by avatar persistence")
	t.assert_equal(decoded.get_size(), Vector2i(8, 8), "PNG buffer round-trip preserves dimensions")
