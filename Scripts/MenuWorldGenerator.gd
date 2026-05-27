extends Node3D

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────

# World center is at tile (8,8) of chunk (0,0) with CHUNK_SIZE = 16
const WORLD_CENTER   : Vector3 = Vector3(8.5, 0.0, 8.5)

# Smooth follow settings
const FOLLOW_SPEED   : float = 0.03   # Lower = smoother
const ROTATION_SPEED : float = 0.05

# Camera path parameters (simple circle around the 3x3 chunk area)
# The 3x3 chunks span from -16 to +16 on X and Z, so radius ~24 covers it nicely
const PATH_RADIUS    : float = 28.0   # Distance from center
const PATH_HEIGHT    : float = 18.0   # Camera height
const PATH_SPEED     : float = 0.08   # Radians per second

# Secondary drift parameters (adds subtle variation)
const DRIFT_AMOUNT   : float = 3.0    # How much to drift from perfect circle
const DRIFT_SPEED    : float = 0.15   # Drift oscillation speed

# Look target height offset (slightly above center for better view)
const LOOK_HEIGHT    : float = 2.0

# Initial camera offset (starting position before smooth follow kicks in)
const INITIAL_ANGLE  : float = 0.0    # Start angle in radians

# ─────────────────────────────────────────────────────────────
# NODES
# ─────────────────────────────────────────────────────────────

@onready var chunk_manager : MenuChunkManager = $GridManager
@onready var fly_camera    : Camera3D         = $Path3D/PathFollow3D/Camera3D if has_node("Path3D/PathFollow3D/Camera3D") else find_child("Camera3D", true)
@onready var world_env     : WorldEnvironment = $WorldEnvironment

# ─────────────────────────────────────────────────────────────
# INTERNAL STATE
# ─────────────────────────────────────────────────────────────

var _world_ready  : bool  = false
var _time         : float = 0.0
var _current_pos  : Vector3 = Vector3.ZERO
var _current_rot  : Basis = Basis.IDENTITY
var _initialized  : bool = false

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_setup_environment()
	_setup_camera()

	if chunk_manager:
		if chunk_manager.spawn_ready:
			_on_world_ready()
		else:
			if chunk_manager.has_signal("spawn_chunks_ready"):
				chunk_manager.spawn_chunks_ready.connect(_on_world_ready, CONNECT_ONE_SHOT)
			else:
				# Fallback - wait a bit then assume ready
				await get_tree().create_timer(2.0).timeout
				_on_world_ready()

func _setup_camera() -> void:
	if not fly_camera:
		push_error("[MenuWorldGenerator] Camera3D not found!")
		return
	
	fly_camera.make_current()
	fly_camera.near = 0.15
	fly_camera.far = 200.0
	
	# Set initial position
	var start_angle := INITIAL_ANGLE
	_current_pos = WORLD_CENTER + Vector3(cos(start_angle) * PATH_RADIUS, PATH_HEIGHT, sin(start_angle) * PATH_RADIUS)
	fly_camera.global_position = _current_pos
	fly_camera.look_at(WORLD_CENTER + Vector3(0.0, LOOK_HEIGHT, 0.0), Vector3.UP)
	_current_rot = fly_camera.global_transform.basis
	_initialized = true
	
	print("[MenuWorldGenerator] Camera setup complete at position: ", _current_pos)

func _process(delta: float) -> void:
	if not _world_ready or not fly_camera or not _initialized:
		return

	_time += delta

	# Calculate target position along a circular path with subtle drift
	var angle := _time * PATH_SPEED
	
	# Base circle position
	var target_x := cos(angle) * PATH_RADIUS
	var target_z := sin(angle) * PATH_RADIUS
	
	# Add subtle drift for organic feel
	var drift_x := cos(_time * DRIFT_SPEED) * DRIFT_AMOUNT
	var drift_z := sin(_time * DRIFT_SPEED * 0.7) * DRIFT_AMOUNT
	var drift_y := sin(_time * DRIFT_SPEED * 0.5) * 1.5
	
	var target_pos := WORLD_CENTER + Vector3(
		target_x + drift_x,
		PATH_HEIGHT + drift_y,
		target_z + drift_z
	)
	
	# Look target - slightly above center to see tiles better
	var look_target := WORLD_CENTER + Vector3(0.0, LOOK_HEIGHT, 0.0)
	
	# Smoothly move camera
	_current_pos = _current_pos.lerp(target_pos, FOLLOW_SPEED)
	fly_camera.global_position = _current_pos
	
	# Smooth rotation using quaternion slerp
	var target_transform := fly_camera.global_transform.looking_at(look_target, Vector3.UP)
	var q_current := _current_rot.get_rotation_quaternion()
	var q_target := target_transform.basis.get_rotation_quaternion()
	var q_new := q_current.slerp(q_target, ROTATION_SPEED)
	_current_rot = Basis(q_new)
	fly_camera.global_transform.basis = _current_rot
	
	# Keep chunk streaming alive (even though camera doesn't move much, needed for any future features)
	if chunk_manager and chunk_manager.has_method("update_player_position"):
		chunk_manager.update_player_position(fly_camera.global_position, delta)

# ─────────────────────────────────────────────────────────────
# WORLD READY
# ─────────────────────────────────────────────────────────────

func _on_world_ready() -> void:
	print("[MenuWorldGenerator] World ready — revealing tiles and starting cinematic.")
	_reveal_all_loaded_tiles()
	_world_ready = true

func _reveal_all_loaded_tiles() -> void:
	for cp in chunk_manager.chunks.keys():
		var chunk : Chunk = chunk_manager.chunks[cp]
		var cs    : int   = chunk_manager.CHUNK_SIZE

		for lx in range(cs):
			for lz in range(cs):
				var idx : int = lx * Chunk.SIZE + lz
				if chunk.tile_revealed[idx] == 0 and chunk.tile_mine[idx] == 0:
					chunk.tile_revealed[idx] = 1
					var tile = chunk_manager.get_tile_node(cp, lx, lz)
					if tile:
						var number : int = chunk.tile_number[idx]
						if tile.has_method("set_revealed_no_animation"):
							tile.set_revealed_no_animation(
								_number_color(number),
								"" if number == 0 else str(number)
							)

func _number_color(number: int) -> Color:
	if number == 0:
		return Color(0.8, 0.8, 0.8)
	const COLORS := {
		1: Color(0.23, 0.44, 0.62), 2: Color(0.38, 0.55, 0.45),
		3: Color(0.62, 0.42, 0.42), 4: Color(0.42, 0.38, 0.55),
		5: Color(0.60, 0.50, 0.38), 6: Color(0.36, 0.52, 0.55),
		7: Color(0.52, 0.42, 0.52), 8: Color(0.40, 0.40, 0.40),
	}
	return COLORS.get(number, Color.WHITE)

# ─────────────────────────────────────────────────────────────
# ENVIRONMENT
# ─────────────────────────────────────────────────────────────

func _setup_environment() -> void:
	if not world_env:
		return
	var env := Environment.new()
	env.background_mode  = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.04)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.1, 0.1, 0.15)
	env.ambient_light_energy = 0.4

	env.fog_enabled     = true
	env.fog_density     = 0.042
	env.fog_light_color = Color(0.3, 0.35, 0.45)

	world_env.environment = env
	print("[MenuWorldGenerator] Environment setup complete")
