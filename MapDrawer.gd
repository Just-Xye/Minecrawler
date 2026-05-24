extends Control

# ─────────────────────────────────────────────
# REFERENCES
# ─────────────────────────────────────────────

var grid_manager : Node = null
var player       : Node = null

# ─────────────────────────────────────────────
# SETTINGS
# ─────────────────────────────────────────────

const TILE_SIZE      : int   = 14
const VISIBLE_RADIUS : int   = 4

const COLOR_HIDDEN   : Color = Color(0.75, 0.75, 0.75)
const COLOR_REVEALED : Color = Color(0.87, 0.87, 0.87)
const COLOR_MINE     : Color = Color(1.0,  0.2,  0.2)
const COLOR_BG       : Color = Color(0.5,  0.5,  0.5)

const COLOR_PLAYER           : Color = Color(1.0, 1.0, 0.0)
const COLOR_PLAYER_OUTLINE   : Color = Color(0.8, 0.8, 0.2)

const FRAME_TEXTURE : Texture2D = preload("res://textures/ui/map_frame.png")

const NUMBER_COLORS : Dictionary = {
	1: Color(0.2,  0.6,  1.0),
	2: Color(0.2,  0.8,  0.2),
	3: Color(1.0,  0.3,  0.3),
	4: Color(0.4,  0.2,  0.8),
	5: Color(1.0,  0.5,  0.2),
	6: Color(0.2,  0.8,  0.8),
	7: Color(0.8,  0.2,  0.8),
	8: Color(0.6,  0.6,  0.6),
}

# ─────────────────────────────────────────────
# SMOOTH MOVEMENT
# ─────────────────────────────────────────────

var player_grid  : Vector2i = Vector2i.ZERO
var player_exact : Vector2  = Vector2.ZERO

var smooth_factor : float = 0.15
var use_smoothing : bool  = true

var current_offset : Vector2 = Vector2.ZERO
var target_offset  : Vector2 = Vector2.ZERO

var diameter  : int   = 0
var center_px : float = 0.0
var center_pz : float = 0.0

# ─────────────────────────────────────────────

func _ready() -> void:
	diameter = VISIBLE_RADIUS * 2 + 1

	custom_minimum_size = Vector2(
		float(diameter * TILE_SIZE),
		float(diameter * TILE_SIZE)
	)

	center_px = custom_minimum_size.x * 0.5
	center_pz = custom_minimum_size.y * 0.5

	# Anchor to center
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	position = -custom_minimum_size * 0.5

	# Frame
	var frame := TextureRect.new()
	frame.texture = FRAME_TEXTURE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	add_child(frame)
	move_child(frame, 0)

	var padding : float = 20.0
	frame.position = Vector2(-padding, -padding)
	frame.size = custom_minimum_size + Vector2(padding * 2.0, padding * 2.0)

# ─────────────────────────────────────────────

func _draw() -> void:
	if grid_manager == null:
		return

	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), COLOR_BG)

	var x_offset : float = 0.0
	var z_offset : float = 0.0

	if use_smoothing:
		var frac_x : float = player_exact.x - floor(player_exact.x)
		var frac_z : float = player_exact.y - floor(player_exact.y)

		target_offset = Vector2(-frac_x * TILE_SIZE, -frac_z * TILE_SIZE)
		var is_moving : bool = target_offset.length() > 0.01
		
		if is_moving:
			current_offset = current_offset.lerp(target_offset, smooth_factor)
		else:
			current_offset = target_offset
		
		current_offset.x = 0.0 if abs(current_offset.x) < 0.01 else current_offset.x
		current_offset.y = 0.0 if abs(current_offset.y) < 0.01 else current_offset.y
		
		x_offset = round(current_offset.x)
		z_offset = round(current_offset.y)

	var base_x : int = int(floor(player_exact.x))
	var base_z : int = int(floor(player_exact.y))

	# Expand by 1 tile so scrolling never exposes "new empty space"
	var start_x : int = base_x - VISIBLE_RADIUS - 1
	var start_z : int = base_z - VISIBLE_RADIUS - 1

	for dx in range(diameter + 2):
		for dz in range(diameter + 2):
			var gx : int = start_x + dx
			var gz : int = start_z + dz

			var px : float = float(dx * TILE_SIZE) + x_offset
			var py : float = float(dz * TILE_SIZE) + z_offset

			if px + TILE_SIZE < 0.0 or px > custom_minimum_size.x:
				continue
			if py + TILE_SIZE < 0.0 or py > custom_minimum_size.y:
				continue

			var rect := Rect2(px, py, TILE_SIZE - 1, TILE_SIZE - 1)

			var cell : Dictionary = {}
			if "get_map_cell" in grid_manager:
				cell = grid_manager.get_map_cell(gx, gz)

			_draw_tile(rect, px, py, cell)

	_draw_player_marker()

# ─────────────────────────────────────────────

func _draw_tile(rect: Rect2, px: float, py: float, cell: Dictionary) -> void:
	var state : String = cell.get("state", "hidden")
	var number : int   = int(cell.get("number", 0))

	match state:
		"hidden":
			draw_rect(rect, COLOR_HIDDEN)
			draw_rect(rect, Color(0.9, 0.9, 0.9), false, 0.5)

		"flagged":
			draw_rect(rect, COLOR_HIDDEN)
			var flag_size : float = TILE_SIZE * 0.5
			var flag_rect := Rect2(
				px + (TILE_SIZE - flag_size) * 0.5,
				py + (TILE_SIZE - flag_size) * 0.5,
				flag_size,
				flag_size
			)
			draw_rect(flag_rect, Color(1.0, 0.6, 0.0))

		"revealed":
			draw_rect(rect, COLOR_REVEALED)

			if number > 0:
				var col : Color = NUMBER_COLORS.get(number, Color.WHITE)
				var font : Font = ThemeDB.fallback_font
				var text : String = str(number)

				var text_size : Vector2 = font.get_string_size(text)
				var text_x : float = px + (TILE_SIZE - text_size.x) * 0.5
				var text_y : float = py + TILE_SIZE - 2

				draw_string(font, Vector2(text_x, text_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TILE_SIZE, col)

		"mine":
			draw_rect(rect, COLOR_MINE)
			var font : Font = ThemeDB.fallback_font
			draw_string(font, Vector2(px + 1.0, py + TILE_SIZE - 2.0), "💣")

# ─────────────────────────────────────────────

func _draw_player_marker() -> void:
	var size : float = float(TILE_SIZE - 2)

	draw_rect(
		Rect2(center_px - size * 0.5, center_pz - size * 0.5, size, size),
		COLOR_PLAYER_OUTLINE
	)

	var inner : float = size - 2.0

	draw_rect(
		Rect2(center_px - inner * 0.5, center_pz - inner * 0.5, inner, inner),
		COLOR_PLAYER
	)

	draw_circle(Vector2(center_px, center_pz), 1.5, Color.WHITE)

# ─────────────────────────────────────────────

func update_player_pos(world_x: float, world_z: float) -> void:
	player_exact = Vector2(world_x, world_z)

	var new_grid : Vector2i = Vector2i(
		int(floor(world_x)),
		int(floor(world_z))
	)

	if new_grid != player_grid:
		player_grid = new_grid
		current_offset = Vector2.ZERO
		target_offset = Vector2.ZERO

	queue_redraw()

# ─────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			use_smoothing = not use_smoothing

			if not use_smoothing:
				current_offset = Vector2.ZERO
				target_offset = Vector2.ZERO
				queue_redraw()
