# MenuWorldGenerator.gd
# Attach to a Node3D in your MainMenu scene.
# Handles only the fly camera — world generation is done by ChunkManager.
# Scene tree expected:
#   MenuWorld (Node3D)  ← this script
#   ├── GridManager     ← ChunkManager node, tile_scene assigned in Inspector
#   ├── Path3D
#   │   └── PathFollow3D
#   │       └── Camera3D
#   └── WorldEnvironment

extends Node3D

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────

@export var fly_speed         : float = 0.012   # progress_ratio per second
@export var camera_height     : float = 12.0
@export var path_radius       : float = 40.0
@export var path_points       : int   = 12      # smoothness of the loop
@export var height_variation  : float = 4.0     # how much the height varies along path
@onready var world_env : WorldEnvironment = $WorldEnvironment

# ─────────────────────────────────────────────────────────────
# NODES
# ─────────────────────────────────────────────────────────────

@onready var chunk_manager : MenuChunkManager = $GridManager
@onready var path_3d       : Path3D       = $Path3D
@onready var path_follow   : PathFollow3D = $Path3D/PathFollow3D
@onready var fly_camera    : Camera3D     = $Path3D/PathFollow3D/Camera3D

# ─────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────

var _progress    : float = 0.0
var _world_ready : bool  = false

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	print("[MenuWorld] _ready called")
	print("[MenuWorld] chunk_manager: ", chunk_manager)
	print("[MenuWorld] path_3d: ", path_3d)
	print("[MenuWorld] fly_camera: ", fly_camera)
	_setup_environment()
	_build_camera_path()
	fly_camera.make_current()
	print("[MenuWorld] Camera made current: ", fly_camera.current)
	
	if chunk_manager:
		if chunk_manager.spawn_ready:
			_on_world_ready()
		else:
			chunk_manager.spawn_chunks_ready.connect(_on_world_ready, CONNECT_ONE_SHOT)
	else:
		push_error("[MenuWorldGenerator] GridManager not found.")

func _process(delta: float) -> void:
	if not _world_ready:
		return

	# Advance camera along path, looping
	_progress += fly_speed * delta
	if _progress >= 1.0:
		_progress -= 1.0
	path_follow.progress_ratio = _progress

	# Keep camera always looking toward the world centre with a slight downward tilt
	var look_target := Vector3(0.0, 0.0, 0.0)
	fly_camera.look_at(look_target, Vector3.UP)

	# Drive ChunkManager so it streams chunks under the camera
	chunk_manager.update_player_position(fly_camera.global_position, delta, Vector3.ZERO)

# ─────────────────────────────────────────────────────────────
# WORLD READY
# ─────────────────────────────────────────────────────────────

func _on_world_ready() -> void:
	print("[MenuWorldGenerator] World ready — revealing tiles and starting flythrough.")
	_reveal_all_loaded_tiles()
	_world_ready = true

func _reveal_all_loaded_tiles() -> void:
	# Force reveal every tile in every loaded chunk so colours and pulse are visible
	for cp in chunk_manager.chunks.keys():
		var chunk : Chunk = chunk_manager.chunks[cp]
		var cs    : int   = chunk_manager.CHUNK_SIZE

		for lx in range(cs):
			for lz in range(cs):
				var idx : int = lx * Chunk.SIZE + lz
				if chunk.tile_revealed[idx] == 0 and chunk.tile_mine[idx] == 0:
					chunk.tile_revealed[idx] = 1
					# Sync the visual
					var tile = chunk_manager.get_tile_node(cp, lx, lz)
					if tile:
						var number : int   = chunk.tile_number[idx]
						var color  : Color = _number_color(number)
						tile.set_revealed_no_animation(color, "" if number == 0 else str(number))

func _number_color(number: int) -> Color:
	if number == 0:
		return Color(0.8, 0.8, 0.8)
	const COLORS := {
		1: Color(0.23, 0.44, 0.62),
		2: Color(0.38, 0.55, 0.45),
		3: Color(0.62, 0.42, 0.42),
		4: Color(0.42, 0.38, 0.55),
		5: Color(0.60, 0.50, 0.38),
		6: Color(0.36, 0.52, 0.55),
		7: Color(0.52, 0.42, 0.52),
		8: Color(0.40, 0.40, 0.40),
	}
	return COLORS.get(number, Color.WHITE)

# ─────────────────────────────────────────────────────────────
# CAMERA PATH
# ─────────────────────────────────────────────────────────────

func _build_camera_path() -> void:
	var curve := Curve3D.new()

	for i in range(path_points):
		var angle  : float = (float(i) / float(path_points)) * TAU
		var height : float = camera_height + sin(angle * 2.0) * height_variation
		var x      : float = cos(angle) * path_radius
		var z      : float = sin(angle) * path_radius
		curve.add_point(Vector3(x, height, z))

	# Close the loop by repeating the first point
	var first := curve.get_point_position(0)
	curve.add_point(first)

	path_3d.curve = curve
	print("[MenuWorldGenerator] Camera path built with %d points." % path_points)

# ─────────────────────────────────────────────────────────────
# ENVIRONMENT
# ─────────────────────────────────────────────────────────────

func _setup_environment() -> void:
	var world_env := get_node_or_null("WorldEnvironment")
	if not world_env:
		return

	var env := Environment.new()
	env.background_mode        = Environment.BG_COLOR
	env.background_color       = Color(0.02, 0.02, 0.04)
	env.ambient_light_source   = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color    = Color(0.1, 0.1, 0.15)
	env.ambient_light_energy   = 0.4
	env.fog_enabled            = true
	env.fog_mode               = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density            = 0.025
	env.fog_light_color        = Color(0.3, 0.35, 0.45)
	env.fog_aerial_perspective = 0.4
	world_env.environment      = env
	
