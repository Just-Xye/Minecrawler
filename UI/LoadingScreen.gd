extends CanvasLayer

# ─────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────
const FADE_DURATION   : float = 0.5 
const DOT_COUNT       : int   = 5 
const DOT_CYCLE       : float = 0.18
const DOT_SIZE        : float = 14.0 
const DOT_SPACING     : float = 22.0 

# ─────────────────────────────────────────────────────────────
# NODES
# ─────────────────────────────────────────────────────────────
var background    : ColorRect       = null 
var center        : CenterContainer = null 
var _title_label  : Label           = null 
var _status_label : Label           = null 
var _dot_row      : HBoxContainer   = null 
var _dots         : Array[ColorRect] = [] 
var _play_button  : Button          = null

var _dot_timer    : float = 0.0 
var _active_dot   : int   = 0 

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if _dot_row and _dot_row.visible:
		_tick_dots(delta)


# ─────────────────────────────────────────────────────────────
# UI BUILDER
# ─────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Background
	background = ColorRect.new()
	background.color = Color(0.04, 0.04, 0.06, 1.0)
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	add_child(background)

	# Center container
	center = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 32)
	center.add_child(vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "Loading World..."
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	# Info Panel
	var info_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.85)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	info_panel.add_theme_stylebox_override("panel", style)
	vbox.add_child(info_panel)

	var info_label := Label.new()
	info_label.text = "HOW TO PLAY:\n\n• Move: WASD / Arrow Keys\n• Reveal Tile: Left Click\n• Flag Mine: Right Click\n• Pulse Vision: Q Key\n• Objective: Uncover safe cells and collect 3 Stars!"
	info_label.add_theme_font_size_override("font_size", 16)
	info_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82))
	info_panel.add_child(info_label)

	# Dots
	_dot_row = HBoxContainer.new()
	_dot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dot_row.add_theme_constant_override("separation", int(DOT_SPACING - DOT_SIZE))
	vbox.add_child(_dot_row)

	for i in DOT_COUNT:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.color = Color(0.25, 0.25, 0.30, 1.0)
		_dot_row.add_child(dot)
		_dots.append(dot)

	# Status
	_status_label = Label.new()
	_status_label.text = "Generating chunks (0 / 9)"
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	# Play Button
	_play_button = Button.new()
	_play_button.text = "PLAY"
	_play_button.visible = false
	_play_button.custom_minimum_size = Vector2(240, 60)
	_play_button.add_theme_font_size_override("font_size", 20)
	_play_button.pressed.connect(_on_play_pressed)
	vbox.add_child(_play_button)


# ─────────────────────────────────────────────────────────────
# DOT ANIMATION
# ─────────────────────────────────────────────────────────────
func _tick_dots(delta: float) -> void:
	_dot_timer += delta
	if _dot_timer < DOT_CYCLE:
		return
	_dot_timer -= DOT_CYCLE

	for i in range(DOT_COUNT):
		var age = posmod(_active_dot - i, DOT_COUNT)
		var brightness = 0.1
		if age == 0:      brightness = 1.0
		elif age == 1:    brightness = 0.6
		elif age == 2:    brightness = 0.3

		_dots[i].color = Color(
			lerpf(0.22, 0.6, brightness),
			lerpf(0.22, 0.85, brightness),
			lerpf(0.25, 1.0, brightness),
			1.0
		)
	_active_dot = (_active_dot + 1) % DOT_COUNT


# ─────────────────────────────────────────────────────────────
# PUBLIC API - Call these from your GridManager / World Generator
# ─────────────────────────────────────────────────────────────
func set_progress(completed: int, total: int) -> void:
	if not _status_label:
		return
	if completed > 9:
		_status_label.text = "Regenerating safe area... (Attempt %d/%d)" % [completed - 9, total - 9]
	else:
		_status_label.text = "Generating chunks (%d / %d)" % [completed, total]


func dismiss() -> void:
	if not is_instance_valid(_title_label) or not is_instance_valid(_play_button):
		return
	
	_title_label.text = "World Ready!"
	_status_label.text = "Press PLAY to begin"
	
	_dot_row.visible = false
	_play_button.visible = true
	_play_button.grab_focus()   # Nice UX touch
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_play_pressed() -> void:
	get_tree().paused = false
	
	var main_node = get_parent()
	if main_node and main_node.has_method("start_game"):
		main_node.start_game()
	elif main_node and main_node.get("player") and main_node.player.has_method("enable_controls"):
		main_node.player.enable_controls()
	
	# Fade out
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(background, "modulate:a", 0.0, FADE_DURATION)
	t.tween_property(center, "modulate:a", 0.0, FADE_DURATION)
	t.set_parallel(false)
	t.tween_callback(queue_free)


# Optional: Force show button for debugging
func debug_show_button() -> void:
	dismiss()
