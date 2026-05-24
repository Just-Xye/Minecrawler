extends ColorRect

@export var pixel_size : float = 4.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Cover the full screen
	anchor_left   = 0.0
	anchor_top    = 0.0
	anchor_right  = 1.0
	anchor_bottom = 1.0
	offset_left   = 0.0
	offset_top    = 0.0
	offset_right  = 0.0
	offset_bottom = 0.0

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://Shaders/Pixelate.gdshader")
	mat.set_shader_parameter("pixel_size", pixel_size)
	material = mat

func set_pixel_size(size: float) -> void:
	pixel_size = size
	if material:
		material.set_shader_parameter("pixel_size", pixel_size)
