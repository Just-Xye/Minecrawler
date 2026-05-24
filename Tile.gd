extends Node3D

# ─────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────

var is_mine        : bool = false
var is_revealed    : bool = false
var is_flagged     : bool = false
var adjacent_mines : int  = 0

var grid_manager = null
var grid_x : int = 0
var grid_z : int = 0
var chunk  = null
var chunk_pos : Vector2i = Vector2i.ZERO

# ─────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────

const HOLD_DURATION  : float = 5.0
const COLOR_DEFAULT  : Color = Color(0.22, 0.24, 0.27)
const COLOR_FLAGGED  : Color = Color(0.75, 0.65, 0.40)
const COLOR_MINE     : Color = Color(0.55, 0.18, 0.18)
const SINK_DEPTH     : float = 8.5
const SINK_DURATION  : float = 0.35

const EMISSION_BASE  : float = 1.0
const EMISSION_PULSE : float = 0.3

# ─────────────────────────────────────────────
# NODES
# ─────────────────────────────────────────────

@onready var mesh         : MeshInstance3D = $MeshInstance3D
@onready var mesh_outline : MeshInstance3D = $Outline
@onready var static_body  : StaticBody3D = $StaticBody3D
@onready var collision_shape : CollisionShape3D = $StaticBody3D/CollisionShape3D

# ─────────────────────────────────────────────
# SHADER
# ─────────────────────────────────────────────

var mat : ShaderMaterial = null
var _material_valid : bool = false

# ─────────────────────────────────────────────
# HOLD
# ─────────────────────────────────────────────

var _holding   : bool  = false
var _hold_time : float = 0.0

# ─────────────────────────────────────────────
# SINK
# ─────────────────────────────────────────────

var _sink_tween       : Tween = null
var _surface_y        : float = 0.0
var _outline_offset_y : float = 0.0

# ─────────────────────────────────────────────
# PULSE
# ─────────────────────────────────────────────

var _should_pulse : bool = false
var _emit_color   : Color = Color.BLACK
var _pulse_cache  : float = 0.0

# ─────────────────────────────────────────────
# MATERIAL MANAGEMENT
# ─────────────────────────────────────────────

func _ensure_material() -> bool:
	if _material_valid and mat and is_instance_valid(mat):
		return true
	
	if not mesh or not is_instance_valid(mesh):
		return false
	
	mat = ShaderMaterial.new()
	var shader = preload("res://Shaders/tile_unified.gdshader")
	
	if not shader:
		push_error("Tile: Failed to load shader from res://Shaders/tile_unified.gdshader")
		_material_valid = false
		return false
	
	mat.shader = shader
	mesh.material_override = mat
	_material_valid = true
	
	return true

func _safe_set_shader_param(param: String, value) -> void:
	if not _material_valid:
		if not _ensure_material():
			return
	
	if mat and is_instance_valid(mat):
		mat.set_shader_parameter(param, value)

# ─────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────

func _ready() -> void:
	if not is_inside_tree():
		return
	
	if not mesh:
		push_error("Tile: MeshInstance3D node not found")
		return
	if not mesh_outline:
		push_error("Tile: Outline node not found")
		return
	
	_surface_y        = mesh.position.y
	_outline_offset_y = mesh_outline.position.y - mesh.position.y
	
	if not _ensure_material():
		return
	
	mat.set_shader_parameter("base_color",      COLOR_DEFAULT)
	mat.set_shader_parameter("revealed",        0.0)
	mat.set_shader_parameter("holding",         0.0)
	mat.set_shader_parameter("flagged",         0.0)
	mat.set_shader_parameter("emission_color",  Color.BLACK)
	mat.set_shader_parameter("emission_energy", 0.0)
	_material_valid = true

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	
	if _holding and not is_revealed and not is_flagged:
		_hold_time += delta
		_safe_set_shader_param("holding", clamp(_hold_time / HOLD_DURATION, 0.0, 1.0))
		if _hold_time >= HOLD_DURATION:
			_finish_hold_reveal()
	
	if _should_pulse and grid_manager and grid_manager.has_method("get_pulse_time"):
		var global_pulse = grid_manager.get_pulse_time()
		var new_pulse = EMISSION_BASE + sin(global_pulse) * EMISSION_PULSE
		if new_pulse != _pulse_cache:
			_pulse_cache = new_pulse
			_safe_set_shader_param("emission_energy", new_pulse)

# ─────────────────────────────────────────────
# HOLD (Input handled by Player raycast)
# ─────────────────────────────────────────────

func start_hold() -> void:
	if is_revealed or is_flagged:
		return
	_holding   = true
	_hold_time = 0.0

func stop_hold() -> void:
	_holding   = false
	_hold_time = 0.0
	_safe_set_shader_param("holding", 0.0)

func _finish_hold_reveal() -> void:
	_holding   = false
	_hold_time = 0.0
	_safe_set_shader_param("holding", 0.0)
	if grid_manager and grid_manager.has_method("reveal_tile"):
		grid_manager.reveal_tile(chunk_pos, grid_x, grid_z)

# ─────────────────────────────────────────────
# FLAG
# ─────────────────────────────────────────────

func flag() -> void:
	if is_revealed:
		return
	if grid_manager and grid_manager.has_method("flag_tile"):
		grid_manager.flag_tile(chunk_pos, grid_x, grid_z)

func set_flagged_visual() -> void:
	if not is_inside_tree():
		return
	
	is_flagged = true
	_emit_color = COLOR_FLAGGED
	_should_pulse = true
	_safe_set_shader_param("flagged", 1.0)
	_safe_set_shader_param("emission_color", COLOR_FLAGGED)

func clear_flagged_visual() -> void:
	if not is_inside_tree():
		return
	
	is_flagged    = false
	_should_pulse = false
	_pulse_cache = 0.0
	_safe_set_shader_param("flagged", 0.0)
	_safe_set_shader_param("emission_color", Color.BLACK)
	_safe_set_shader_param("emission_energy", 0.0)
	_clear_label()

# ─────────────────────────────────────────────
# REVEAL (animated)
# ─────────────────────────────────────────────

func reveal(color: Color, text: String = "") -> void:
	if not is_inside_tree():
		return
	
	is_revealed = true
	_holding    = false
	_clear_label()
	
	mat.set_shader_parameter("revealed",  1.0)
	mat.set_shader_parameter("holding",   0.0)
	mat.set_shader_parameter("flagged",   0.0)
	mat.set_shader_parameter("reveal_color", color)
	
	if text != "":
		_emit_color = color
		_should_pulse = true
		mat.set_shader_parameter("emission_color", color)
		_bake_label(text, color)
	elif is_mine:
		_emit_color = COLOR_MINE
		_should_pulse = true
		mat.set_shader_parameter("emission_color", COLOR_MINE)
		_bake_label("💥", COLOR_MINE)
	else:
		_should_pulse = false
		_pulse_cache = 0.0
		mat.set_shader_parameter("emission_energy", 0.0)
		mat.set_shader_parameter("emission_color", Color.BLACK)
		
		var in_flood = false
		if grid_manager:
			if grid_manager.has_method("is_in_flood_reveal"):
				in_flood = grid_manager.is_in_flood_reveal()
			elif "_in_flood_reveal" in grid_manager:
				in_flood = grid_manager._in_flood_reveal
		
		if not in_flood:
			_fake_bounce_light()
	
	if not is_mine:
		_sink()

# ─────────────────────────────────────────────
# REVEAL (no animation — chunk reload)
# ─────────────────────────────────────────────

func set_revealed_no_animation(color: Color, text: String = "") -> void:
	if not is_inside_tree():
		return
	
	is_revealed = true
	_holding    = false
	_clear_label()
	
	mat.set_shader_parameter("revealed",     1.0)
	mat.set_shader_parameter("holding",      0.0)
	mat.set_shader_parameter("flagged",      0.0)
	mat.set_shader_parameter("reveal_color", color)
	
	if text != "":
		_emit_color = color
		_should_pulse = true
		mat.set_shader_parameter("emission_color", color)
		if grid_manager and grid_manager.has_method("get_pulse_time"):
			var global_pulse = grid_manager.get_pulse_time()
			_pulse_cache = EMISSION_BASE + sin(global_pulse) * EMISSION_PULSE
			mat.set_shader_parameter("emission_energy", _pulse_cache)
		_set_sunk_position_immediate()
		_bake_label_no_animation(text, color)
	elif is_mine:
		_emit_color = COLOR_MINE
		_should_pulse = true
		mat.set_shader_parameter("emission_color", COLOR_MINE)
		if grid_manager and grid_manager.has_method("get_pulse_time"):
			var global_pulse = grid_manager.get_pulse_time()
			_pulse_cache = EMISSION_BASE + sin(global_pulse) * EMISSION_PULSE
			mat.set_shader_parameter("emission_energy", _pulse_cache)
		_set_sunk_position_immediate()
		_bake_label_no_animation("💥", COLOR_MINE)
	else:
		_should_pulse = false
		_pulse_cache = 0.0
		mat.set_shader_parameter("emission_energy", 0.0)
		mat.set_shader_parameter("emission_color", Color.BLACK)
		_set_sunk_position_immediate()

# ─────────────────────────────────────────────
# FAKE BOUNCE LIGHT
# ─────────────────────────────────────────────

const BOUNCE_RADIUS : int = 2

func _fake_bounce_light() -> void:
	if not grid_manager or not grid_manager.has_method("get_tile_node"):
		return
	
	var in_flood = false
	if grid_manager.has_method("is_in_flood_reveal"):
		in_flood = grid_manager.is_in_flood_reveal()
	elif "_in_flood_reveal" in grid_manager:
		in_flood = grid_manager._in_flood_reveal
	
	if in_flood:
		return
	
	var chunk_size : int = grid_manager.CHUNK_SIZE
	
	for dx in range(-BOUNCE_RADIUS, BOUNCE_RADIUS + 1):
		for dz in range(-BOUNCE_RADIUS, BOUNCE_RADIUS + 1):
			if dx == 0 and dz == 0:
				continue
			
			var nx    : int = grid_x + dx
			var nz    : int = grid_z + dz
			var n_cpx : int = chunk_pos.x
			var n_cpy : int = chunk_pos.y
			
			if nx < 0:
				n_cpx -= 1
				nx += chunk_size
			elif nx >= chunk_size:
				n_cpx += 1
				nx -= chunk_size
			
			if nz < 0:
				n_cpy -= 1
				nz += chunk_size
			elif nz >= chunk_size:
				n_cpy += 1
				nz -= chunk_size
			
			var neighbor = grid_manager.get_tile_node(Vector2i(n_cpx, n_cpy), nx, nz)
			if neighbor and neighbor.has_method("_apply_bounce_tint") and not neighbor.is_revealed:
				var dist     : float = Vector2(dx, dz).length()
				var strength : float = clampf(1.0 - dist / BOUNCE_RADIUS, 0.0, 1.0) * 0.15
				neighbor._apply_bounce_tint(strength)

func _apply_bounce_tint(amount: float) -> void:
	if is_revealed:
		return
	_safe_set_shader_param("base_color", COLOR_DEFAULT + Color(amount, amount, amount, 0.0))

# ─────────────────────────────────────────────
# SINK
# ─────────────────────────────────────────────

func _sink() -> void:
	if not is_inside_tree():
		return
	
	if _sink_tween and is_instance_valid(_sink_tween):
		_sink_tween.kill()
	
	var target_y : float = _surface_y - SINK_DEPTH
	_sink_tween = create_tween()
	if not _sink_tween:
		return
	
	_sink_tween.set_ease(Tween.EASE_IN)
	_sink_tween.set_trans(Tween.TRANS_CUBIC)
	
	# FIX #1: Move BOTH mesh AND collision shape
	_sink_tween.tween_property(mesh,         "position:y", target_y,                                SINK_DURATION)
	_sink_tween.parallel().tween_property(mesh_outline, "position:y", target_y + _outline_offset_y, SINK_DURATION)
	_sink_tween.parallel().tween_property(collision_shape, "position:y", target_y,                  SINK_DURATION)
	
	# FIX #2: Notify player to sink with the tile
	_sink_tween.tween_callback(func():
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("sink_with_tile"):
			player.sink_with_tile(_surface_y, target_y, SINK_DURATION)
	)

func _set_sunk_position_immediate() -> void:
	if not mesh or not mesh_outline:
		return
	
	var target_y : float = _surface_y - SINK_DEPTH
	mesh.position.y         = target_y
	mesh_outline.position.y = target_y + _outline_offset_y
	collision_shape.position.y = target_y  # FIX #1: Also set collision immediately

# ─────────────────────────────────────────────
# LABELS
# ─────────────────────────────────────────────

func _bake_label(text: String, tile_color: Color) -> void:
	if not is_inside_tree():
		return
	
	_clear_label()
	
	var l := Label3D.new()
	if not l:
		return
	
	l.name              = "TileLabel"
	l.text              = text
	l.font_size         = 64
	l.pixel_size        = 0.006
	l.modulate          = Color.WHITE
	l.outline_size      = 6
	l.outline_modulate  = tile_color.darkened(0.6)
	l.billboard         = BaseMaterial3D.BILLBOARD_DISABLED
	l.rotation_degrees  = Vector3(-90.0, 0.0, 0.0)
	l.position          = Vector3(0.0, _surface_y + 0.01, 0.0)
	add_child(l)
	
	var lt := create_tween()
	if lt:
		lt.set_ease(Tween.EASE_IN)
		lt.set_trans(Tween.TRANS_CUBIC)
		lt.tween_property(l, "position:y", _surface_y - SINK_DEPTH + 0.01, SINK_DURATION)

func _bake_label_no_animation(text: String, tile_color: Color) -> void:
	if not is_inside_tree():
		return
	
	_clear_label()
	
	var l := Label3D.new()
	if not l:
		return
	
	l.name              = "TileLabel"
	l.text              = text
	l.font_size         = 64
	l.pixel_size        = 0.006
	l.modulate          = Color.WHITE
	l.outline_size      = 6
	l.outline_modulate  = tile_color.darkened(0.6)
	l.billboard         = BaseMaterial3D.BILLBOARD_DISABLED
	l.rotation_degrees  = Vector3(-90.0, 0.0, 0.0)
	l.position          = Vector3(0.0, _surface_y - SINK_DEPTH + 0.01, 0.0)
	add_child(l)

func _clear_label() -> void:
	if not is_inside_tree():
		return
	
	var existing = get_node_or_null("TileLabel")
	if existing and is_instance_valid(existing):
		existing.queue_free()

# FIX #1: Helper to get tile top surface height (for player raycast checks)
func get_tile_top_height() -> float:
	return _surface_y
