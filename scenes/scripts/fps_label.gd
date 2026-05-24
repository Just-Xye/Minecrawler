extends Label

func _ready() -> void:
	# Set up the label appearance
	add_theme_color_override("font_color", Color.GREEN)
	position = Vector2(10, 10)
	z_index = 100

func _process(delta: float) -> void:
	var fps = Engine.get_frames_per_second()
	text = "FPS: " + str(fps)
	
	# Color code based on performance
	if fps < 30:
		add_theme_color_override("font_color", Color.RED)
	elif fps < 60:
		add_theme_color_override("font_color", Color.YELLOW)
	else:
		add_theme_color_override("font_color", Color.GREEN)
