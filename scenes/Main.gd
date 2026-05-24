extends Node3D

# ─────────────────────────────────────────────────────────────
# NODE REFERENCES
# ─────────────────────────────────────────────────────────────

@onready var chunk_manager    : ChunkManager     = $GridManager
@onready var player           : CharacterBody3D  = $Player
@onready var free_camera      : Camera3D         = $FreeCamera
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var map_drawer       : Control          = $HUD/MapContainer/VBoxContainer/MapDrawer
@onready var pixelate_rect    : ColorRect        = $HUD/PixelateRect

# ─────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────

const PULSE_VISION_DURATION    : float = 5.0
const PULSE_VISION_COOLDOWN    : float = 30.0
const PULSE_VISION_FOG_DENSITY : float = 0.005

const MAP_FADE_DURATION        : float = 0.2

const ENEMY_CATCH_RADIUS       : float = 1.5
const HIDE_HUD_KEY             : int   = KEY_G

# ─────────────────────────────────────────────────────────────
# DEBUG TOGGLE
# ─────────────────────────────────────────────────────────────

const DEBUG_ENABLED_BY_DEFAULT : bool = false

# ─────────────────────────────────────────────────────────────
# CAMERA BOB CONSTANTS
# ─────────────────────────────────────────────────────────────

const BOB_SPEED       : float = 9.0
const BOB_AMPLITUDE_Y : float = 0.035
const BOB_AMPLITUDE_X : float = 0.015
const BOB_TILT_FORWARD: float = 1.2
const BOB_TILT_BACK   : float = 1.2
const BOB_TILT_SIDE   : float = 1.8
const BOB_RETURN_SPEED: float = 8.0

# ─────────────────────────────────────────────────────────────
# AMBIANCE / OMINOUS SOUND CONSTANTS
# ─────────────────────────────────────────────────────────────

const AMBIANCE_PATHS : Array[String] = [
	"res://Sounds/world/ambiance/ambiance.ogg",
]

const OMINOUS_PATHS : Array[String] = [
	"res://Sounds/world/ominous/rumble1.wav",
	"res://Sounds/world/ominous/rumble2.wav",
	"res://Sounds/world/ominous/rumble3.wav",
]

const AMBIANCE_INTERVAL_MIN : float = 60.0
const AMBIANCE_INTERVAL_MAX : float = 180.0
const OMINOUS_INTERVAL_MIN  : float = 30.0
const OMINOUS_INTERVAL_MAX  : float = 90.0

# ─────────────────────────────────────────────────────────────
# STATE VARIABLES
# ─────────────────────────────────────────────────────────────

var player_camera      : Camera3D = null
var is_free_cam_active : bool     = false

var target_fog_density   : float = 0.15
var fog_adjust_speed     : float = 2.0
var fog_enabled          : bool  = true
var original_fog_density : float = 0.15

var pixelate_shader_material : ShaderMaterial
var antialiasing_enabled     : bool = false

var _loading_screen : CanvasLayer = null

var _tile_debugger : TileDebugVisualizer = null
var _debug_visible : bool = false

var _entity_manager : EntityManager = null
var _star_manager   : StarManager   = null

var _map_visible : bool = false

var _hud_visible        : bool = true
var _hud_scene_instance : Node = null

var _world_exporter : Node = null

# Debug toggle state (runtime)
var _debug_enabled : bool = DEBUG_ENABLED_BY_DEFAULT

# ─────────────────────────────────────────────────────────────
# PULSE VISION STATE
# ─────────────────────────────────────────────────────────────

var _pulse_active         : bool  = false
var _pulse_timer          : float = 0.0
var _pulse_cooldown_timer : float = 0.0
var _pulse_hud_label      : Label = null

# ─────────────────────────────────────────────────────────────
# LIVES HUD
# ─────────────────────────────────────────────────────────────

var _lives_label : Label = null

# ─────────────────────────────────────────────────────────────
# GAME STATE
# ─────────────────────────────────────────────────────────────

var _game_over        : bool        = false
var _game_over_canvas : CanvasLayer = null
var _jumpscare_active : bool        = false

# ─────────────────────────────────────────────────────────────
# DEBUG STATE VARIABLES
# ─────────────────────────────────────────────────────────────

var _player_immune      : bool = false
var _spawn_cycle_paused : bool = false
var _enemy_path_visible : bool = false
var _enemy_path_line    : MeshInstance3D = null

# ─────────────────────────────────────────────────────────────
# CAMERA BOB STATE
# ─────────────────────────────────────────────────────────────

var _bob_time      : float   = 0.0
var _bob_base_y    : float   = 0.0
var _bob_active    : bool    = false

# ─────────────────────────────────────────────────────────────
# AUDIO STATE
# ─────────────────────────────────────────────────────────────

var _ambiance_player  : AudioStreamPlayer = null
var _ominous_player   : AudioStreamPlayer = null
var _ambiance_timer   : float = 0.0
var _ominous_timer    : float = 0.0

# ─────────────────────────────────────────────────────────────
# PAUSE MENU STATE
# ─────────────────────────────────────────────────────────────

var _paused              : bool        = false
var _pause_canvas        : CanvasLayer = null
var _debug_info_label    : Label       = null

# ─────────────────────────────────────────────────────────────
# CACHED REFERENCES (Performance Optimization)
# ─────────────────────────────────────────────────────────────

var _cached_star_counter : Label = null
var _cached_hud_node     : Node = null
var _cached_map_container : Control = null

# Signal connection tracking to avoid redundant checks
var _signals_connected : bool = false

# ─────────────────────────────────────────────────────────────
# LIFECYCLE METHODS
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_cache_references()
	_debug_print_nodes()
	_setup_cameras()
	_setup_smooth_fog()
	_setup_loading_screen()
	_setup_minimap()
	_setup_signals()
	_setup_pixelate_shader()
	_setup_developer_console()
	_setup_tile_debugger()
	_setup_entity_manager()
	_setup_enemy_path_visualizer()
	_setup_pulse_vision_hud()
	_setup_lives_hud()
	_setup_star_manager()
	_hud_scene_instance = $HUD
	_setup_world_exporter()
	_setup_audio()
	_connect_audio_settings()
	_verify_menu_cleanup()
	_setup_ground_collision()
	
	if player and "eye_height" in player:
		_bob_base_y = player.eye_height

func _cache_references() -> void:
	"""Cache frequently accessed nodes for performance"""
	_cached_hud_node = $HUD
	_cached_map_container = $HUD/MapContainer if $HUD else null

func _get_star_counter() -> Label:
	"""Lazy-load star counter reference"""
	if not _cached_star_counter and _cached_hud_node:
		_cached_star_counter = _cached_hud_node.get_node_or_null("StarCounter")
	return _cached_star_counter

func _process(delta: float) -> void:
	if _game_over or _jumpscare_active or _paused:
		return
	_update_player_position(delta)
	_update_minimap()
	_update_fog(delta)
	_update_enemy_path_line()
	_check_enemy_catch()
	_update_camera_bob(delta)
	_update_ambient_audio(delta)

func _input(event: InputEvent) -> void:
	if _jumpscare_active:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _game_over:
			_toggle_pause()
		return

	if _paused or _game_over:
		return

	_handle_camera_input(event)
	_handle_visual_input(event)
	_handle_debug_input(event)
	_handle_console_input(event)
	_handle_pulse_vision_input(event)
	_handle_map_input(event)
	_handle_hud_toggle_input(event)
	_handle_debug_toggle_input(event)

# ─────────────────────────────────────────────────────────────
# INITIALIZATION & SETUP METHODS
# ─────────────────────────────────────────────────────────────

func _setup_loading_screen() -> void:
	if player and player.has_method("disable_controls"):
		player.disable_controls()

	var loading_scene := preload("res://UI/LoadingScreen.tscn")
	_loading_screen = loading_scene.instantiate()
	add_child(_loading_screen)

	if chunk_manager:
		chunk_manager.spawn_chunk_progress.connect(_on_spawn_progress)
		chunk_manager.spawn_chunks_ready.connect(_on_spawn_ready)

func _setup_minimap() -> void:
	if chunk_manager and player:
		chunk_manager.update_player_position(player.global_position, 0.0, Vector3.ZERO)
	if map_drawer and chunk_manager:
		map_drawer.grid_manager = chunk_manager
		chunk_manager.map_updated.connect(_on_map_updated)
		_update_minimap()

func _setup_signals() -> void:
	"""Optimized signal connections - connect once"""
	if _signals_connected:
		return
	
	if chunk_manager and chunk_manager.has_signal("map_updated"):
		if not chunk_manager.map_updated.is_connected(_on_map_updated):
			chunk_manager.map_updated.connect(_on_map_updated)
	
	if _entity_manager:
		if not _entity_manager.enemy_defeated.is_connected(_on_enemy_defeated):
			_entity_manager.enemy_defeated.connect(_on_enemy_defeated)
	
	_signals_connected = true

func _setup_pixelate_shader() -> void:
	if pixelate_rect:
		pixelate_rect.set_pixel_size(1.0)
		pixelate_shader_material = pixelate_rect.material
		if pixelate_shader_material:
			pixelate_shader_material.set_shader_parameter("antialiasing", 1 if antialiasing_enabled else 0)

func _setup_developer_console() -> void:
	var console_scene = preload("res://scenes/DeveloperConsole.tscn")
	var console = console_scene.instantiate()
	add_child(console)
	console.visible = false

func _setup_tile_debugger() -> void:
	_tile_debugger = TileDebugVisualizer.new()
	add_child(_tile_debugger)
	_tile_debugger.set_targets(chunk_manager, player)
	_tile_debugger.set_process(false)

func _setup_entity_manager() -> void:
	_entity_manager = EntityManager.new()
	_entity_manager.name = "EntityManager"
	add_child(_entity_manager)
	call_deferred("_setup_entity_manager_targets")

func _setup_entity_manager_targets() -> void:
	if _entity_manager and chunk_manager and player:
		_entity_manager.set_targets(chunk_manager, player)
		if _entity_manager.has_signal("jumpscare_finished"):
			_entity_manager.jumpscare_finished.connect(_on_jumpscare_finished)

func _setup_enemy_path_visualizer() -> void:
	_enemy_path_line = MeshInstance3D.new()
	_enemy_path_line.name    = "EnemyPathLine"
	_enemy_path_line.visible = false
	var path_material = StandardMaterial3D.new()
	path_material.albedo_color    = Color(1, 0.2, 0.2, 1)
	path_material.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	path_material.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	path_material.render_priority = 127
	path_material.no_depth_test   = true
	_enemy_path_line.material_override = path_material
	_enemy_path_line.mesh = ImmediateMesh.new()
	add_child(_enemy_path_line)

func _setup_pulse_vision_hud() -> void:
	_pulse_hud_label = Label.new()
	_pulse_hud_label.name = "PulseVisionLabel"
	_pulse_hud_label.add_theme_font_size_override("font_size", 18)
	_pulse_hud_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_pulse_hud_label.position = Vector2(16, 60)
	$HUD.add_child(_pulse_hud_label)

func _setup_lives_hud() -> void:
	_lives_label = Label.new()
	_lives_label.name = "LivesLabel"
	_lives_label.add_theme_font_size_override("font_size", 22)
	_lives_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_lives_label.position = Vector2(16, 16)
	$HUD.add_child(_lives_label)
	_refresh_lives_hud()
	if player:
		if player.has_signal("life_lost"):
			player.life_lost.connect(_on_life_lost)
		if player.has_signal("life_gained"):
			player.life_gained.connect(_on_life_gained)
		if player.has_signal("lives_depleted"):
			player.lives_depleted.connect(_on_lives_depleted)

func _setup_world_exporter() -> void:
	var script = load("res://WorldExporter.gd")
	if not script:
		push_error("[Main] Could not load WorldExporter.gd")
		return
	_world_exporter = Node.new()
	_world_exporter.name = "WorldExporter"
	_world_exporter.set_script(script)
	add_child(_world_exporter)

func _setup_star_manager() -> void:
	_star_manager = StarManager.new()
	_star_manager.name = "StarManager"
	add_child(_star_manager)
	call_deferred("_wire_star_manager")

func _wire_star_manager() -> void:
	if _star_manager and chunk_manager and player:
		_star_manager.setup(chunk_manager, player)
		_star_manager.star_collected.connect(_on_star_collected)
		_star_manager.all_stars_collected.connect(_on_all_stars_collected)
		_star_manager.stars_spawned.connect(_on_stars_spawned)
		chunk_manager.tile_revealed.connect(_on_tile_revealed_for_stars)
		chunk_manager.tile_revealed.connect(_on_tile_revealed_mine_check)
		_star_manager.game_won.connect(_on_game_won)
		call_deferred("_apply_hud_visibility_to_star_counter")

func _apply_hud_visibility_to_star_counter() -> void:
	await get_tree().process_frame
	var star_counter = _get_star_counter()
	if star_counter and not _hud_visible:
		star_counter.visible = false

# ─────────────────────────────────────────────────────────────
# AUDIO SETUP
# ─────────────────────────────────────────────────────────────

func _connect_audio_settings() -> void:
	if not SettingsManager:
		return
	
	if not SettingsManager.volume_changed.is_connected(_on_volume_changed):
		SettingsManager.volume_changed.connect(_on_volume_changed)
	
	var master_volume = SettingsManager.get_setting("master_volume", 0.8)
	var music_volume = SettingsManager.get_setting("music_volume", 0.7)
	var sfx_volume = SettingsManager.get_setting("sfx_volume", 0.8)
	var ui_volume = SettingsManager.get_setting("ui_volume", 0.9)
	
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("UI", ui_volume)

func _set_bus_volume(bus_name: String, volume_linear: float) -> void:
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		var volume_db = linear_to_db(volume_linear)
		AudioServer.set_bus_volume_db(bus_index, volume_db)

func _on_volume_changed(bus_name: String, volume_linear: float) -> void:
	_set_bus_volume(bus_name, volume_linear)

func _setup_audio() -> void:
	_ambiance_player = AudioStreamPlayer.new()
	_ambiance_player.name    = "AmbiancePlayer"
	_ambiance_player.bus     = "Music"
	add_child(_ambiance_player)

	_ominous_player = AudioStreamPlayer.new()
	_ominous_player.name     = "OminousPlayer"
	_ominous_player.bus      = "SFX"
	add_child(_ominous_player)

	_ambiance_timer = randf_range(AMBIANCE_INTERVAL_MIN, AMBIANCE_INTERVAL_MAX)
	_ominous_timer  = randf_range(OMINOUS_INTERVAL_MIN * 0.5, OMINOUS_INTERVAL_MAX * 0.5)

func _update_ambient_audio(delta: float) -> void:
	_ambiance_timer -= delta
	if _ambiance_timer <= 0.0 and not _ambiance_player.playing:
		_play_random_from(_ambiance_player, AMBIANCE_PATHS)
		_ambiance_timer = randf_range(AMBIANCE_INTERVAL_MIN, AMBIANCE_INTERVAL_MAX)

	_ominous_timer -= delta
	if _ominous_timer <= 0.0 and not _ominous_player.playing:
		_play_random_from(_ominous_player, OMINOUS_PATHS)
		_ominous_timer = randf_range(OMINOUS_INTERVAL_MIN, OMINOUS_INTERVAL_MAX)

func _play_random_from(player_node: AudioStreamPlayer, paths: Array[String]) -> void:
	if paths.is_empty():
		return
	var path := paths[randi() % paths.size()]
	if not ResourceLoader.exists(path):
		push_warning("[Main] Audio file not found: " + path)
		return
	var stream = load(path)
	if stream:
		player_node.stream = stream
		player_node.play()

# ─────────────────────────────────────────────────────────────
# CAMERA MANAGEMENT
# ─────────────────────────────────────────────────────────────

func _setup_cameras() -> void:
	player_camera = _find_player_camera()
	if player_camera == null:
		push_error("No player camera found!")
		return
	if free_camera == null:
		push_error("FreeCamera missing!")
		return
	player_camera.far = 100.0
	player_camera.make_current()

func _find_player_camera() -> Camera3D:
	if player == null:
		return null
	var candidates : Array[Node] = [player]
	while candidates.size() > 0:
		var current : Node = candidates.pop_front()
		if current is Camera3D:
			return current
		for child in current.get_children():
			candidates.append(child)
	return null

func _toggle_free_cam() -> void:
	if free_camera == null or player_camera == null:
		push_error("Missing camera refs!")
		return
	is_free_cam_active = not is_free_cam_active
	if is_free_cam_active:
		if free_camera.has_method("activate"):
			free_camera.activate(player_camera.global_transform)
		else:
			free_camera.global_transform = player_camera.global_transform
			free_camera.make_current()
		if player.has_method("disable_controls"):
			player.disable_controls()
	else:
		if free_camera.has_method("deactivate"):
			free_camera.deactivate()
		player_camera.make_current()
		if player.has_method("enable_controls"):
			player.enable_controls()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ─────────────────────────────────────────────────────────────
# CAMERA BOB
# ─────────────────────────────────────────────────────────────

func _update_camera_bob(delta: float) -> void:
	if not player_camera or is_free_cam_active:
		return
	if not player or not player.is_spawn_complete():
		return
	if not player.is_on_floor():
		player_camera.position.y = lerp(player_camera.position.y, _bob_base_y, BOB_RETURN_SPEED * delta)
		player_camera.rotation_degrees.z = lerp(player_camera.rotation_degrees.z, 0.0, BOB_RETURN_SPEED * delta)
		player_camera.rotation_degrees.x = lerp(player_camera.rotation_degrees.x, 0.0, BOB_RETURN_SPEED * delta)
		return

	var vel    : Vector3 = player.velocity
	var yaw    : float   = deg_to_rad(player.rotation_degrees.y)
	var forward_dot : float =  vel.x * sin(yaw) + vel.z * cos(yaw)
	var right_dot   : float =  vel.x * cos(yaw) - vel.z * sin(yaw)
	var speed_h     : float  = Vector2(vel.x, vel.z).length()

	var is_moving : bool = speed_h > 0.3

	if is_moving:
		_bob_time += delta * BOB_SPEED
		var bob_y   : float = sin(_bob_time) * BOB_AMPLITUDE_Y
		var bob_x   : float = cos(_bob_time * 0.5) * BOB_AMPLITUDE_X

		var fwd_n  : float = clamp(forward_dot / maxf(speed_h, 0.001), -1.0, 1.0)
		var rgt_n  : float = clamp(right_dot   / maxf(speed_h, 0.001), -1.0, 1.0)

		var tilt_x : float = 0.0

		if fwd_n > 0.0:
			tilt_x = -fwd_n * BOB_TILT_FORWARD
		elif fwd_n < 0.0:
			tilt_x = -fwd_n * BOB_TILT_BACK
		var tilt_z : float = -rgt_n * BOB_TILT_SIDE

		player_camera.position.y          = lerp(player_camera.position.y,          _bob_base_y + bob_y, 12.0 * delta)
		player_camera.position.x          = lerp(player_camera.position.x,          bob_x,               12.0 * delta)
		player_camera.rotation_degrees.z  = lerp(player_camera.rotation_degrees.z,  tilt_z,              10.0 * delta)
		player_camera.rotation_degrees.x = lerp(
			player_camera.rotation_degrees.x,
			player_camera.rotation_degrees.x + tilt_x * delta * 2.0,
			6.0 * delta
		)
	else:
		player_camera.position.y         = lerp(player_camera.position.y,         _bob_base_y, BOB_RETURN_SPEED * delta)
		player_camera.position.x         = lerp(player_camera.position.x,         0.0,         BOB_RETURN_SPEED * delta)
		player_camera.rotation_degrees.z = lerp(player_camera.rotation_degrees.z, 0.0,         BOB_RETURN_SPEED * delta)

# ─────────────────────────────────────────────────────────────
# FOG MANAGEMENT
# ─────────────────────────────────────────────────────────────

func _setup_smooth_fog() -> void:
	if not world_environment:
		push_warning("WorldEnvironment missing - fog disabled")
		return
	if not world_environment.environment:
		world_environment.environment = Environment.new()
	var env := world_environment.environment
	env.fog_enabled            = true
	env.fog_mode               = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density            = target_fog_density
	env.fog_light_color        = Color(0.35, 0.4, 0.45)
	env.fog_aerial_perspective = 0.5
	env.fog_sun_scatter        = 0.2
	env.background_mode        = Environment.BG_COLOR
	env.background_color       = Color(0.0, 0.0, 0.0, 1.0)
	original_fog_density       = target_fog_density

func _update_fog(delta: float) -> void:
	_update_pulse_vision_timers(delta)
	_update_pulse_hud_display()
	if world_environment and world_environment.environment and fog_enabled:
		var current_density : float = world_environment.environment.fog_density
		if absf(current_density - target_fog_density) > 0.001:
			world_environment.environment.fog_density = lerpf(
				current_density, target_fog_density, delta * fog_adjust_speed
			)

func _toggle_fog() -> void:
	if not world_environment or not world_environment.environment:
		push_warning("Cannot toggle fog - WorldEnvironment missing!")
		return
	fog_enabled = not fog_enabled
	world_environment.environment.fog_enabled = fog_enabled
	if fog_enabled:
		target_fog_density = original_fog_density
	else:
		world_environment.environment.fog_density = 0.0
		target_fog_density = 0.0

func set_fog_density(density: float, instant: bool = false) -> void:
	if not world_environment or not world_environment.environment:
		return
	original_fog_density = clamp(density, 0.0, 1.0)
	if fog_enabled:
		if instant:
			world_environment.environment.fog_density = original_fog_density
			target_fog_density = original_fog_density
		else:
			target_fog_density = original_fog_density

func is_fog_enabled() -> bool:
	return fog_enabled if world_environment and world_environment.environment else false

# ─────────────────────────────────────────────────────────────
# HUD HIDER
# ─────────────────────────────────────────────────────────────

func _toggle_hud() -> void:
	_hud_visible = not _hud_visible
	if _hud_scene_instance:
		_hud_scene_instance.visible = _hud_visible
	if _pulse_hud_label:
		_pulse_hud_label.visible = _hud_visible
	if _lives_label:
		_lives_label.visible = _hud_visible
	var star_counter = _get_star_counter()
	if star_counter:
		star_counter.visible = _hud_visible

func _refresh_hud_visibility() -> void:
	if not _hud_visible:
		if _hud_scene_instance:
			_hud_scene_instance.visible = false
		if _pulse_hud_label:
			_pulse_hud_label.visible = false
		if _lives_label:
			_lives_label.visible = false
		var star_counter = _get_star_counter()
		if star_counter:
			star_counter.visible = false

# ─────────────────────────────────────────────────────────────
# VISUAL EFFECTS
# ─────────────────────────────────────────────────────────────

func _cycle_pixel_size() -> void:
	if not pixelate_rect:
		return
	const SIZES : Array[float] = [1.0, 2.0, 3.0, 4.0, 6.0, 8.0]
	var current : float = pixelate_rect.pixel_size
	var idx     : int   = SIZES.find(current)
	var next    : float = SIZES[(idx + 1) % SIZES.size()]
	pixelate_rect.set_pixel_size(next)

func _toggle_antialiasing() -> void:
	antialiasing_enabled = not antialiasing_enabled
	if pixelate_shader_material:
		pixelate_shader_material.set_shader_parameter("antialiasing", 1 if antialiasing_enabled else 0)

# ─────────────────────────────────────────────────────────────
# MINIMAP
# ─────────────────────────────────────────────────────────────

func _handle_map_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map") or (event is InputEventKey and event.pressed and event.keycode == KEY_M):
		_toggle_map()

func _toggle_map() -> void:
	_map_visible = not _map_visible
	if not _cached_map_container:
		_cached_map_container = $HUD/MapContainer
	
	if _cached_map_container:
		var tween := _cached_map_container.create_tween()
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		if _map_visible:
			_cached_map_container.modulate.a = 0.0
			_cached_map_container.visible    = true
			tween.tween_property(_cached_map_container, "modulate:a", 1.0, MAP_FADE_DURATION)
		else:
			tween.tween_property(_cached_map_container, "modulate:a", 0.0, MAP_FADE_DURATION)
			tween.tween_callback(func(): _cached_map_container.visible = false)

func _update_minimap() -> void:
	if map_drawer and player:
		map_drawer.update_player_pos(player.global_position.x, player.global_position.z)

func _on_map_updated() -> void:
	if map_drawer and player:
		map_drawer.update_player_pos(player.global_position.x, player.global_position.z)

# ─────────────────────────────────────────────────────────────
# PLAYER & ENTITY MANAGEMENT
# ─────────────────────────────────────────────────────────────

func _update_player_position(delta: float) -> void:
	if chunk_manager and player:
		chunk_manager.update_player_position(
			player.global_position,
			delta,
			player.velocity if "velocity" in player else Vector3.ZERO
		)

func _on_spawn_progress(completed: int, total: int) -> void:
	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.set_progress(completed, total)

func _on_spawn_ready() -> void:
	if chunk_manager and chunk_manager.has_method("is_loading_complete"):
		if not chunk_manager.is_loading_complete():
			return
	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.dismiss()
	if _star_manager:
		_star_manager.place_stars_now()

# ─────────────────────────────────────────────────────────────
# LIVES SYSTEM
# ─────────────────────────────────────────────────────────────

func _refresh_lives_hud() -> void:
	if not _lives_label:
		return
	if player and player.is_immortal:
		_lives_label.text = "♥ IMMORTAL"
		_lives_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		return
	var lives     : int = player.lives if player else 4
	var max_hearts: int = 5
	var hearts    := ""
	for i in range(max_hearts):
		hearts += ("♥ " if i < lives else "♡ ")
	_lives_label.text = hearts.strip_edges()
	_lives_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))

func _on_life_gained(_lives_remaining: int) -> void:
	_refresh_lives_hud()
	if _lives_label:
		var tween := _lives_label.create_tween()
		tween.tween_property(_lives_label, "modulate", Color(0.3, 1.5, 0.3), 0.08)
		tween.tween_property(_lives_label, "modulate", Color(1, 1, 1), 0.35)

func _on_life_lost(_lives_remaining: int) -> void:
	_refresh_lives_hud()
	if _lives_label:
		var tween := _lives_label.create_tween()
		tween.tween_property(_lives_label, "modulate", Color(2.0, 0.3, 0.3), 0.08)
		tween.tween_property(_lives_label, "modulate", Color(1, 1, 1), 0.35)
	_flash_damage_vignette()

func _on_lives_depleted() -> void:
	if _jumpscare_active:
		return
	_trigger_game_over()

func _trigger_game_over() -> void:
	_game_over = true
	if player:
		player.disable_controls()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_show_game_over_screen()

func _flash_damage_vignette() -> void:
	var flash := ColorRect.new()
	flash.color         = Color(0.8, 0.0, 0.0, 0.35)
	flash.anchor_right  = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.4)
	tween.tween_callback(flash.queue_free)

# ─────────────────────────────────────────────────────────────
# ENEMY CATCH & JUMPSCARE
# ─────────────────────────────────────────────────────────────

func _check_enemy_catch() -> void:
	if not _entity_manager or not _entity_manager.is_entity_alive():
		return
	if not player:
		return
	var dist := _entity_manager.get_entity_position().distance_to(player.global_position)
	if dist <= ENEMY_CATCH_RADIUS:
		_on_enemy_caught()

func _on_enemy_caught() -> void:
	if _jumpscare_active or _game_over:
		return
	_jumpscare_active = true

	print("[Main] Player caught — triggering jumpscare.")

	if player and player.has_method("disable_controls"):
		player.disable_controls()

	if player and player.has_method("lose_all_lives"):
		player.lose_all_lives()

	if _entity_manager and _entity_manager.has_method("trigger_jumpscare"):
		_entity_manager.trigger_jumpscare()
	else:
		_on_jumpscare_finished()

func _on_jumpscare_finished() -> void:
	_jumpscare_active = false
	_trigger_game_over()

func _add_screen_shake() -> void:
	if not player_camera:
		return
	var original_pos := player_camera.position
	var tween := player_camera.create_tween()
	tween.set_parallel(true)
	for i in range(6):
		var offset := Vector3(randf_range(-0.1, 0.1), randf_range(-0.05, 0.05), 0)
		tween.tween_property(player_camera, "position", original_pos + offset, 0.05)
		tween.tween_interval(0.05)
	tween.tween_property(player_camera, "position", original_pos, 0.05)

# ─────────────────────────────────────────────────────────────
# MINE HIT
# ─────────────────────────────────────────────────────────────

func _on_tile_revealed_mine_check(cp: Vector2i, lx: int, lz: int, is_mine: bool) -> void:
	if not is_mine:
		return
	if player and player.has_method("lose_life"):
		player.lose_life()
	var explosion_audio := AudioStreamPlayer.new()
	explosion_audio.stream = preload("res://Sounds/level/explosion.wav")
	explosion_audio.bus = "SFX"
	add_child(explosion_audio)
	explosion_audio.finished.connect(func(): explosion_audio.queue_free())
	explosion_audio.play()

# ─────────────────────────────────────────────────────────────
# PAUSE MENU
# ─────────────────────────────────────────────────────────────

func _toggle_pause() -> void:
	if _game_over or _jumpscare_active:
		return
	_paused = not _paused
	if _paused:
		_show_pause_menu()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().paused = true
	else:
		_close_pause_menu()
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _show_pause_menu() -> void:
	if _pause_canvas and is_instance_valid(_pause_canvas):
		return

	_pause_canvas = CanvasLayer.new()
	_pause_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_canvas)

	var overlay := ColorRect.new()
	overlay.color         = Color(0.0, 0.0, 0.0, 0.72)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter  = Control.MOUSE_FILTER_STOP
	_pause_canvas.add_child(overlay)

	var center := CenterContainer.new()
	center.anchor_right  = 1.0
	center.anchor_bottom = 1.0
	_pause_canvas.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	var resume_btn := _make_menu_button("Resume", Color(0.25, 0.45, 0.28))
	vbox.add_child(resume_btn)
	resume_btn.pressed.connect(_toggle_pause)

	var options_btn := _make_menu_button("Options", Color(0.28, 0.35, 0.5))
	vbox.add_child(options_btn)
	options_btn.pressed.connect(_show_pause_options)

	var reset_btn := _make_menu_button("Reset World", Color(0.5, 0.38, 0.18))
	vbox.add_child(reset_btn)
	reset_btn.pressed.connect(_confirm_reset)

	var menu_btn := _make_menu_button("Quit to Main Menu", Color(0.3, 0.35, 0.45))
	vbox.add_child(menu_btn)
	menu_btn.pressed.connect(_confirm_quit_to_menu)

	if _debug_enabled:
		var debug_panel := _build_debug_keys_panel()
		vbox.add_child(debug_panel)

func _close_pause_menu() -> void:
	if _pause_canvas and is_instance_valid(_pause_canvas):
		_pause_canvas.queue_free()
		_pause_canvas = null

func _show_pause_options() -> void:
	print("[Main] Options panel (pause) not yet implemented.")

func _confirm_reset() -> void:
	_show_confirmation("Reset the world?", func():
		get_tree().paused = false
		get_tree().reload_current_scene()
	)

func _confirm_quit_to_menu() -> void:
	_show_confirmation("Return to Main Menu?", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://UI/MainMenu.tscn")
	)

func _show_confirmation(message: String, on_confirm: Callable) -> void:
	var confirm_canvas := CanvasLayer.new()
	confirm_canvas.layer = 10
	confirm_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(confirm_canvas)

	var bg := ColorRect.new()
	bg.color         = Color(0.0, 0.0, 0.0, 0.85)
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter  = Control.MOUSE_FILTER_STOP
	confirm_canvas.add_child(bg)

	var cc := CenterContainer.new()
	cc.anchor_right  = 1.0
	cc.anchor_bottom = 1.0
	confirm_canvas.add_child(cc)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 1.0)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.content_margin_left   = 28.0
	style.content_margin_right  = 28.0
	style.content_margin_top    = 22.0
	style.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", style)
	cc.add_child(panel)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	panel.add_child(vb)

	var lbl := Label.new()
	lbl.text = message
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vb.add_child(lbl)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)

	var yes := _make_menu_button("Confirm", Color(0.65, 0.18, 0.18))
	yes.custom_minimum_size = Vector2(130, 44)
	hb.add_child(yes)
	yes.pressed.connect(func():
		confirm_canvas.queue_free()
		on_confirm.call()
	)

	var no := _make_menu_button("Cancel", Color(0.28, 0.35, 0.45))
	no.custom_minimum_size = Vector2(130, 44)
	hb.add_child(no)
	no.pressed.connect(func(): confirm_canvas.queue_free())

func _build_debug_keys_panel() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.12, 0.85)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color(0.3, 0.5, 0.3, 0.8)
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(420, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	var header := Label.new()
	header.text = "DEBUG BINDS (Ctrl+Shift+` to toggle)"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	vb.add_child(header)

	var binds : Array[Array] = [
		["F3",           "Tile debug visualizer"],
		["F4",           "Enemy debug panel"],
		["F5",           "Spawn enemy now"],
		["F6",           "Despawn enemy"],
		["F7",           "Toggle spawn cycle pause"],
		["F8",           "Reset spawn cycle"],
		["F9",           "Spawn passive enemy"],
		["F10",          "Toggle enemy path"],
		["F11",          "Toggle player immunity"],
		["U",            "Toggle immortality (no mine damage)"],
		["Ctrl+Shift+`", "Lock / unlock all debug binds"],
		["Shift+F5",     "Skip 3-minute spawner lock"],
	]

	for pair in binds:
		var row := Label.new()
		row.text = "  %-16s — %s" % [pair[0], pair[1]]
		row.add_theme_font_size_override("font_size", 12)
		row.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
		vb.add_child(row)

	return panel

# ─────────────────────────────────────────────────────────────
# GAME OVER / WIN SCREENS
# ─────────────────────────────────────────────────────────────

func _show_game_over_screen() -> void:
	if _game_over_canvas and is_instance_valid(_game_over_canvas):
		return

	_game_over_canvas = CanvasLayer.new()
	add_child(_game_over_canvas)

	var overlay := ColorRect.new()
	overlay.color         = Color(0.0, 0.0, 0.0, 0.0)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter  = Control.MOUSE_FILTER_STOP
	_game_over_canvas.add_child(overlay)

	var fade := overlay.create_tween()
	fade.tween_property(overlay, "color:a", 0.82, 0.6)

	var center_cont := CenterContainer.new()
	center_cont.anchor_right  = 1.0
	center_cont.anchor_bottom = 1.0
	_game_over_canvas.add_child(center_cont)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	center_cont.add_child(vbox)

	var title := Label.new()
	title.text = "GAME OVER"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate.a = 0.0
	vbox.add_child(title)

	var title_tween := title.create_tween()
	title_tween.tween_interval(0.3)
	title_tween.tween_property(title, "modulate:a", 1.0, 0.5)

	var sub := Label.new()
	sub.text = "You didn't make it out..."
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.0
	vbox.add_child(sub)

	var sub_tween := sub.create_tween()
	sub_tween.tween_interval(0.6)
	sub_tween.tween_property(sub, "modulate:a", 1.0, 0.4)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var try_btn := _make_menu_button("Try Again", Color(0.85, 0.25, 0.25))
	vbox.add_child(try_btn)
	try_btn.pressed.connect(_on_try_again_pressed)

	var menu_btn := _make_menu_button("Main Menu", Color(0.3, 0.35, 0.45))
	vbox.add_child(menu_btn)
	menu_btn.pressed.connect(_on_main_menu_pressed)

func _make_menu_button(label_text: String, bg_color: Color) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(260, 56)
	btn.add_theme_font_size_override("font_size", 24)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.set_corner_radius_all(6)
	normal.set_border_width_all(2)
	normal.border_color = bg_color.lightened(0.3)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = bg_color.lightened(0.18)
	hover.set_corner_radius_all(6)
	hover.set_border_width_all(2)
	hover.border_color = bg_color.lightened(0.5)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = bg_color.darkened(0.15)
	pressed_style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	return btn

func _on_try_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://UI/MainMenu.tscn")

# ─────────────────────────────────────────────────────────────
# STAR HANDLERS
# ─────────────────────────────────────────────────────────────

func _on_tile_revealed_for_stars(cp: Vector2i, lx: int, lz: int, _is_mine: bool) -> void:
	if _star_manager and not _is_mine:
		var wx := cp.x * chunk_manager.CHUNK_SIZE + lx
		var wz := cp.y * chunk_manager.CHUNK_SIZE + lz
		_star_manager.on_tile_revealed(wx, wz)

func _on_star_collected(idx: int) -> void:
	var collected := _star_manager.get_collected_count()
	var total     := _star_manager.get_star_count()
	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = load("res://Sounds/Star/pickup.wav")
	audio_player.bus = "SFX"
	add_child(audio_player)
	audio_player.play()
	audio_player.finished.connect(audio_player.queue_free)
	if player and player.has_method("gain_life"):
		player.gain_life()
		_refresh_lives_hud()
	elif player and player.lives < 5:
		player.lives += 1
		_refresh_lives_hud()
	print("[Main] Star collected! %d / %d" % [collected, total])

func _on_stars_spawned(count: int) -> void:
	print("[Main] Star placement confirmed: %d / %d stars." % [count, StarManager.STAR_COUNT])

func _on_all_stars_collected() -> void:
	print("[Main] All stars collected — exit portal spawned!")
	var hint := Label.new()
	hint.text = "Find the Exit..."
	hint.add_theme_font_size_override("font_size", 28)
	hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left   = 0.0
	hint.anchor_right  = 1.0
	hint.anchor_top    = 0.3
	hint.anchor_bottom = 0.3
	$HUD.add_child(hint)
	var tween := hint.create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(hint, "modulate:a", 0.0, 0.8)
	tween.tween_callback(hint.queue_free)

func _show_win_screen() -> void:
	if player:
		player.disable_controls()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := ColorRect.new()
	panel.color         = Color(0, 0, 0, 0.75)
	panel.anchor_right  = 1.0
	panel.anchor_bottom = 1.0
	canvas.add_child(panel)
	var label := Label.new()
	label.text = "✦  YOU COLLECTED ALL STARS  ✦"
	label.add_theme_font_size_override("font_size", 52)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	label.anchor_right  = 1.0
	label.anchor_bottom = 1.0
	canvas.add_child(label)

# ─────────────────────────────────────────────────────────────
# PULSE VISION SYSTEM
# ─────────────────────────────────────────────────────────────

func _try_activate_pulse_vision() -> void:
	if _pulse_active or _pulse_cooldown_timer > 0.0:
		return
	if not player or not player.is_spawn_complete():
		return
	_pulse_active = true
	_pulse_timer  = PULSE_VISION_DURATION
	_activate_pulse_vision()

func _activate_pulse_vision() -> void:
	if world_environment and world_environment.environment:
		world_environment.environment.background_color = Color(0.0, 0.0, 0.04, 1.0)
	target_fog_density = PULSE_VISION_FOG_DENSITY
	fog_adjust_speed   = 8.0
	if _entity_manager and _entity_manager.is_entity_alive():
		_set_entity_pulse_outline(true)
	_set_star_pulse_highlight(true)

func _deactivate_pulse_vision() -> void:
	_pulse_active         = false
	_pulse_cooldown_timer = PULSE_VISION_COOLDOWN
	target_fog_density    = original_fog_density
	fog_adjust_speed      = 2.0
	if world_environment and world_environment.environment:
		world_environment.environment.background_color = Color(0.0, 0.0, 0.0, 1.0)
	_set_entity_pulse_outline(false)
	_set_star_pulse_highlight(false)

func _update_pulse_vision_timers(delta: float) -> void:
	if _pulse_active:
		_pulse_timer -= delta
		if _pulse_timer <= 0.0:
			_deactivate_pulse_vision()
			return
		if _entity_manager and _entity_manager.is_entity_alive():
			var entity_node := _entity_manager.get_entity_node()
			if is_instance_valid(entity_node):
				_ensure_pulse_applied(entity_node)
	elif _pulse_cooldown_timer > 0.0:
		_pulse_cooldown_timer -= delta

func _ensure_pulse_applied(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			if not child.has_meta("_pulse_mat_backup"):
				child.set_meta("_pulse_mat_backup", child.material_override)
				var surface_backups : Array = []
				for s in range(child.get_surface_override_material_count()):
					surface_backups.append(child.get_surface_override_material(s))
				child.set_meta("_pulse_surf_backup", surface_backups)
				var mat := StandardMaterial3D.new()
				mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color               = Color(1.0, 0.15, 0.15, 1.0)
				mat.emission_enabled           = true
				mat.emission                   = Color(1.0, 0.15, 0.15)
				mat.emission_energy_multiplier = 4.0
				mat.no_depth_test              = true
				mat.render_priority            = 10
				child.material_override        = mat
		if child.get_child_count() > 0:
			_ensure_pulse_applied(child)

func _update_pulse_hud_display() -> void:
	if not _pulse_hud_label:
		return
	if _pulse_active:
		_pulse_hud_label.text = "Pulse Vision: %.1fs" % _pulse_timer
		_pulse_hud_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
	elif _pulse_cooldown_timer > 0.0:
		_pulse_hud_label.text = "Pulse Vision cooldown: %.0fs" % _pulse_cooldown_timer
		_pulse_hud_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	else:
		_pulse_hud_label.text = "Pulse Vision: Ready  [Q]"
		_pulse_hud_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))

func _set_entity_pulse_outline(enabled: bool) -> void:
	if not _entity_manager:
		return
	var entity_node : Node3D = _entity_manager.get_entity_node()
	if not is_instance_valid(entity_node):
		return
	_apply_pulse_to_meshes(entity_node, enabled, Color(1.0, 0.15, 0.15))

func _apply_pulse_to_meshes(node: Node, enabled: bool, color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			if enabled:
				child.set_meta("_pulse_mat_backup", child.material_override)
				var surface_backups : Array = []
				for s in range(child.get_surface_override_material_count()):
					surface_backups.append(child.get_surface_override_material(s))
				child.set_meta("_pulse_surf_backup", surface_backups)
				var mat := StandardMaterial3D.new()
				mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color               = Color(color.r, color.g, color.b, 1.0)
				mat.emission_enabled           = true
				mat.emission                   = color
				mat.emission_energy_multiplier = 4.0
				mat.no_depth_test              = true
				mat.render_priority            = 10
				child.material_override        = mat
			else:
				if child.has_meta("_pulse_mat_backup"):
					child.material_override = child.get_meta("_pulse_mat_backup")
					child.remove_meta("_pulse_mat_backup")
				if child.has_meta("_pulse_surf_backup"):
					var surface_backups : Array = child.get_meta("_pulse_surf_backup")
					for s in range(surface_backups.size()):
						child.set_surface_override_material(s, surface_backups[s])
					child.remove_meta("_pulse_surf_backup")
		if child.get_child_count() > 0:
			_apply_pulse_to_meshes(child, enabled, color)

func _set_star_pulse_highlight(enabled: bool) -> void:
	if not _star_manager:
		return
	if enabled:
		for child in _star_manager.get_children():
			if child.name.begins_with("Star_"):
				_apply_star_pulse(child, true, Color(1.0, 0.9, 0.2))
		for i in range(_star_manager._stars.size()):
			var beacon_name := "StarBeacon_%d" % i
			if _star_manager.has_node(beacon_name):
				continue
			var star = _star_manager._stars[i]
			if star["revealed"] or star["collected"]:
				continue
			var tile : Vector2i = star["world_tile"]
			var beacon := _build_star_beacon(i, tile)
			_star_manager.add_child(beacon)
	else:
		for child in _star_manager.get_children():
			if child.name.begins_with("StarBeacon_"):
				child.queue_free()
			elif child.name.begins_with("Star_"):
				_apply_star_pulse(child, false, Color.WHITE)

func _apply_star_pulse(node: Node, enabled: bool, pulse_color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			if enabled:
				if not child.has_meta("_pulse_mat_backup"):
					child.set_meta("_pulse_mat_backup", child.material_override)
				var mat := StandardMaterial3D.new()
				mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color               = pulse_color
				mat.emission_enabled           = true
				mat.emission                   = pulse_color
				mat.emission_energy_multiplier = 8.0
				mat.no_depth_test              = true
				mat.render_priority            = 10
				mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
				child.material_override        = mat
			else:
				if child.has_meta("_pulse_mat_backup"):
					child.material_override = child.get_meta("_pulse_mat_backup")
					child.remove_meta("_pulse_mat_backup")
		if child.get_child_count() > 0:
			_apply_star_pulse(child, enabled, pulse_color)

func _build_star_beacon(idx: int, tile: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "StarBeacon_%d" % idx
	root.global_position = Vector3(tile.x + 0.5, 1.0, tile.y + 0.5)
	var mi     := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	mi.mesh = sphere
	var star_color := Color(1.0, 0.9, 0.2, 1.0)
	var mat        := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color               = star_color
	mat.emission_enabled           = true
	mat.emission                   = star_color
	mat.emission_energy_multiplier = 5.0
	mat.no_depth_test              = true
	mat.render_priority            = 10
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	root.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color  = star_color
	light.light_energy = 3.0
	light.omni_range   = 6.0
	root.add_child(light)
	return root

# ─────────────────────────────────────────────────────────────
# ENEMY PATH VISUALIZATION
# ─────────────────────────────────────────────────────────────

func _update_enemy_path_line() -> void:
	if not _enemy_path_visible or not _entity_manager or not _entity_manager.is_entity_alive():
		if _enemy_path_line and _enemy_path_line.visible:
			_enemy_path_line.visible = false
		return
	var path : Array[Vector3] = _entity_manager.get_current_path()
	if path.is_empty():
		_enemy_path_line.visible = false
		return
	_enemy_path_line.visible = true
	var immediate_mesh = _enemy_path_line.mesh as ImmediateMesh
	if not immediate_mesh:
		return
	immediate_mesh.clear_surfaces()
	var all_points : Array[Vector3] = [_entity_manager.get_entity_position()]
	all_points.append_array(path)
	if all_points.size() < 2:
		return
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in all_points:
		immediate_mesh.surface_add_vertex(point)
	immediate_mesh.surface_end()

func _toggle_enemy_path() -> void:
	if not _debug_enabled:
		return
	_enemy_path_visible = not _enemy_path_visible
	if not _enemy_path_visible and _enemy_path_line:
		_enemy_path_line.visible = false

# ─────────────────────────────────────────────────────────────
# TILE DEBUG VISUALIZER
# ─────────────────────────────────────────────────────────────

func _toggle_tile_debug() -> void:
	if not _debug_enabled or not _tile_debugger:
		return
	_debug_visible = not _debug_visible
	_tile_debugger.set_process(_debug_visible)
	if not _debug_visible:
		_tile_debugger.clear_all()

# ─────────────────────────────────────────────────────────────
# DEBUG COMMANDS
# ─────────────────────────────────────────────────────────────

func _toggle_player_immunity() -> void:
	if not _debug_enabled:
		return
	_player_immune = not _player_immune
	if _entity_manager and _entity_manager.has_method("set_player_immune"):
		_entity_manager.set_player_immune(_player_immune)

func _toggle_immortal() -> void:
	if not _debug_enabled:
		return
	if player and player.has_method("toggle_immortal"):
		player.toggle_immortal()
		_refresh_lives_hud()

func _toggle_spawn_cycle() -> void:
	if not _debug_enabled or not _entity_manager:
		return
	_spawn_cycle_paused = not _spawn_cycle_paused
	if _spawn_cycle_paused:
		_entity_manager.pause_spawn_cycle()
	else:
		_entity_manager.resume_spawn_cycle()
	print("Spawn Cycle: ", "PAUSED" if _spawn_cycle_paused else "RESUMED")

func _reset_spawn_cycle() -> void:
	if not _debug_enabled or not _entity_manager:
		return
	_entity_manager.reset_spawn_cycle()
	print("Spawn cycle reset")

func _spawn_enemy_now() -> void:
	if not _debug_enabled or not _entity_manager:
		return
	_entity_manager.force_spawn()

func _despawn_enemy_now() -> void:
	if not _debug_enabled or not _entity_manager:
		return
	if _entity_manager.is_entity_alive():
		_entity_manager.force_despawn()

func _spawn_passive_enemy() -> void:
	if not _debug_enabled or not _entity_manager:
		return
	_entity_manager.spawn_passive()

func _skip_spawn_lock() -> void:
	if not _debug_enabled or not _entity_manager:
		return
	_entity_manager.skip_first_spawn_lock()
	print("[Main] DEBUG: Spawn lock skipped.")

# ─────────────────────────────────────────────────────────────
# SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────

func _on_weapon_picked_up() -> void:
	print("[Main] Weapon picked up!")

func _on_enemy_defeated() -> void:
	print("[Main] Enemy defeated!")

func _on_weapon_spawned(_position: Vector3) -> void:
	print("[Main] Weapon appeared in the world!")

func _on_game_won() -> void:
	print("[Main] *** GAME WON ***")
	_show_win_screen()

# ─────────────────────────────────────────────────────────────
# INPUT HANDLERS
# ─────────────────────────────────────────────────────────────

func _handle_camera_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_freecam"):
		_toggle_free_cam()

func _handle_visual_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pixelate"):
		_cycle_pixel_size()
	if event.is_action_pressed("toggle_aa"):
		_toggle_antialiasing()
	if event.is_action_pressed("toggle_fog"):
		_toggle_fog()
	if event.is_action_pressed("toggle_debug_visualization"):
		_toggle_tile_debug()

func _handle_debug_input(event: InputEvent) -> void:
	if not _debug_enabled:
		return

	if event.is_action_pressed("toggle_player_immunity"):
		_toggle_player_immunity()
	if event.is_action_pressed("toggle_spawn_cycle"):
		_toggle_spawn_cycle()
	if event.is_action_pressed("toggle_enemy_path"):
		_toggle_enemy_path()
	if event.is_action_pressed("spawn_enemy"):
		_spawn_enemy_now()
	if event.is_action_pressed("despawn_enemy"):
		_despawn_enemy_now()
	if event.is_action_pressed("spawn_passive_enemy"):
		_spawn_passive_enemy()
	if event.is_action_pressed("reset_spawn_cycle"):
		_reset_spawn_cycle()

	if event is InputEventKey and event.pressed and event.keycode == KEY_U:
		_toggle_immortal()

	if event is InputEventKey and event.pressed \
			and event.keycode == KEY_F5 \
			and event.shift_pressed \
			and not event.ctrl_pressed:
		_skip_spawn_lock()

		print(
			"[Main] Debug controls %s"
			% ("ENABLED" if _debug_enabled else "DISABLED")
		)

func _handle_console_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		var console = get_node_or_null("DeveloperConsole")
		if console:
			if console.is_open: console._close_console()
			else:               console._open_console()

func _handle_pulse_vision_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		_try_activate_pulse_vision()

func _handle_hud_toggle_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == HIDE_HUD_KEY:
		_toggle_hud()

func _handle_debug_toggle_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and event.keycode == KEY_QUOTELEFT \
			and event.ctrl_pressed \
			and event.shift_pressed:
		_debug_enabled = not _debug_enabled
		print("[Main] Debug binds: ", "ENABLED" if _debug_enabled else "DISABLED")
		_show_debug_toggle_toast()

func _show_debug_toggle_toast() -> void:
	var lbl := Label.new()
	lbl.text = ("🔓 Debug ENABLED" if _debug_enabled else "🔒 Debug DISABLED")
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3) if _debug_enabled else Color(1.0, 0.4, 0.3))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left   = 0.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 0.12
	lbl.anchor_bottom = 0.12
	$HUD.add_child(lbl)
	var tween := lbl.create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tween.tween_callback(lbl.queue_free)

# ─────────────────────────────────────────────────────────────
# UTILITY
# ─────────────────────────────────────────────────────────────

func _debug_print_nodes() -> void:
	print("=== Main.gd Node Debug ===")
	for child in get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
	print("chunk_manager: ", chunk_manager)
	print("player: ",        player)
	if not chunk_manager: push_error("Failed to find GridManager!")
	if not player:        push_error("Failed to find Player!")
	
func _verify_menu_cleanup() -> void:
	print("[Main] Verifying menu cleanup...")
	
	var menu_chunks = get_tree().get_nodes_in_group("menu_chunks")
	if menu_chunks.size() > 0:
		print("[Main] Warning: Found %d leftover menu chunks, cleaning up..." % menu_chunks.size())
		for chunk in menu_chunks:
			if is_instance_valid(chunk):
				chunk.queue_free()
	
	var managers = get_tree().get_nodes_in_group("menu_chunk_manager")
	if managers.size() > 0:
		print("[Main] Warning: Found leftover MenuChunkManager, cleaning up...")
		for manager in managers:
			if manager.has_method("deactivate"):
				manager.deactivate()
			manager.queue_free()
	
	await get_tree().process_frame
	print("[Main] Menu cleanup verification complete")
	
func _setup_ground_collision() -> void:
	var ground = StaticBody3D.new()
	ground.name = "Ground"
	
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	# Make it large enough to cover the playable area
	box_shape.size = Vector3(1000, 0.1, 1000)
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, -0.05, 0)  # Just below tile surface
	
	ground.add_child(collision_shape)
	add_child(ground)
	print("[Main] Ground Collision plane added")
