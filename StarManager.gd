extends Node3D
class_name StarManager

# ─────────────────────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────────────────────

signal star_revealed(star_index: int)
signal star_collected(star_index: int)
signal all_stars_collected
signal stars_spawned(count: int)
signal game_won

# ─────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────

const STAR_PELLET_SCENE : String = "res://items/StarPellet/StarPellet.tscn"
const STAR_COUNT        : int   = 3
const SAFE_SPAWN_RADIUS : int   = 20
const SEARCH_RADIUS     : int   = 60
const COLLECT_RANGE     : float = 1.5
const PROXIMITY_SOUND_RANGE : float = 30.0
const SOUND_UPDATE_INTERVAL : float = 0.1
const PORTAL_TOUCH_RANGE : float = 1.2
const PORTAL_SAFE_RADIUS : int   = 15

# Star teleport constants
const STAR_TELEPORT_DISTANCE : int = 60
const STAR_TELEPORT_WARNING_TIME : float = 5.0
const STAR_TELEPORT_COOLDOWN : float = 30.0

# ─────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────

var _pulse_ghost_nodes : Dictionary = {}

var chunk_manager : ChunkManager = null
var player : CharacterBody3D = null
var _counter_label : Label = null
var _tile_scene : PackedScene = null

# Persistent star registry - stores star data even when chunk is unloaded
var star_registry : Dictionary = {}  # Vector2i (tile position) -> star_data Dictionary

# Runtime star nodes (cleared when chunks unload, recreated when chunks load)
var _star_nodes : Dictionary = {}  # Vector2i (tile position) -> Node3D

var _sound_timer : float = 0.0
var _game_won : bool = false
var _time : float = 0.0

var _portal_node : Node3D = null
var _portal_tile : Vector2i = Vector2i.ZERO
var _portal_active : bool = false

# Star teleport state
var _teleport_warning_active : bool = false
var _teleport_timer : float = 0.0
var _teleport_cooldown_timer : float = 0.0
var _teleport_warning_label : Label = null
var _last_teleport_time : float = -STAR_TELEPORT_COOLDOWN

# Cached references for performance
var _cached_hud : CanvasLayer = null

# Signal connection tracking
var _chunk_signals_connected : bool = false
var _stars_placement_started : bool = false  # Guard against double place_stars_now calls
var _stars_placement_complete : bool = false  # True only after all STAR_COUNT stars confirmed placed

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_setup_audio()
	_setup_teleport_warning_label()

func _process(delta: float) -> void:
	if not player or _game_won:
		return

	_time += delta
	_sound_timer += delta

	_update_star_animations(delta)
	_update_portal_pulse(delta)
	_update_teleport_system(delta)

# ─────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────

func setup(cm: ChunkManager, p: CharacterBody3D) -> void:
	chunk_manager = cm
	player = p
	_tile_scene = cm.tile_scene
	_connect_chunk_signals()

func _connect_chunk_signals() -> void:
	if not chunk_manager or _chunk_signals_connected:
		return
	
	if chunk_manager.has_signal("chunk_load_completed"):
		if not chunk_manager.chunk_load_completed.is_connected(_on_chunk_loaded):
			chunk_manager.chunk_load_completed.connect(_on_chunk_loaded)
	
	if chunk_manager.has_signal("chunk_unloaded"):
		if not chunk_manager.chunk_unloaded.is_connected(_on_chunk_unloaded):
			chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
	
	_chunk_signals_connected = true

func _on_chunk_loaded(chunk_pos: Vector2i) -> void:
	# Don't attempt to respawn stars until placement has fully completed
	if not _stars_placement_complete:
		return
	_respawn_stars_in_chunk(chunk_pos)

func _on_chunk_unloaded(chunk_pos: Vector2i) -> void:
	_remove_star_visuals_in_chunk(chunk_pos)

func _respawn_stars_in_chunk(chunk_pos: Vector2i) -> void:
	for star_tile in star_registry.keys():
		var star_chunk := Vector2i(
			floori(float(star_tile.x) / chunk_manager.CHUNK_SIZE),
			floori(float(star_tile.y) / chunk_manager.CHUNK_SIZE)
		)
		if star_chunk == chunk_pos:
			var star_data = star_registry[star_tile]
			if star_data["revealed"] and not star_data["collected"]:
				_spawn_star_visual_at_tile(star_tile, star_data)

func _remove_star_visuals_in_chunk(chunk_pos: Vector2i) -> void:
	var to_remove : Array[Vector2i] = []
	for star_tile in _star_nodes.keys():
		var star_chunk := Vector2i(
			floori(float(star_tile.x) / chunk_manager.CHUNK_SIZE),
			floori(float(star_tile.y) / chunk_manager.CHUNK_SIZE)
		)
		if star_chunk == chunk_pos:
			var node = _star_nodes[star_tile]
			if is_instance_valid(node):
				node.queue_free()
			to_remove.append(star_tile)
	for star_tile in to_remove:
		_star_nodes.erase(star_tile)

func place_stars_now() -> void:
	if _stars_placement_started:
		return
	_stars_placement_started = true
	_place_stars()
	_setup_counter_hud()
	_cache_hud_reference()

func _cache_hud_reference() -> void:
	var tree := get_tree()
	if not tree:
		return
	var current_scene := tree.current_scene
	if not current_scene:
		return
	_cached_hud = current_scene.get_node_or_null("HUD")
	if not _cached_hud:
		_cached_hud = tree.root.get_node_or_null("Main/HUD")

func _setup_audio() -> void:
	var audio := get_node_or_null("ProximityAudio")
	if audio and audio.stream:
		audio.play()

func _setup_teleport_warning_label() -> void:
	_teleport_warning_label = Label.new()
	_teleport_warning_label.name = "StarTeleportWarning"
	_teleport_warning_label.add_theme_font_size_override("font_size", 24)
	_teleport_warning_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_teleport_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_teleport_warning_label.anchor_left = 0.0
	_teleport_warning_label.anchor_right = 1.0
	_teleport_warning_label.anchor_top = 0.15
	_teleport_warning_label.anchor_bottom = 0.15
	_teleport_warning_label.modulate.a = 0.0
	_teleport_warning_label.visible = false
	add_child(_teleport_warning_label)

# ─────────────────────────────────────────────────────────────
# STAR TELEPORT SYSTEM
# ─────────────────────────────────────────────────────────────

func _update_teleport_system(delta: float) -> void:
	if _game_won:
		return
	
	if _teleport_cooldown_timer > 0:
		_teleport_cooldown_timer -= delta
	
	var nearest_star_dist := INF
	var nearest_star_tile := Vector2i.ZERO
	
	for star_tile in star_registry.keys():
		var star_data = star_registry[star_tile]
		if star_data["collected"] or not star_data["revealed"]:
			continue
		
		var star_pos := Vector3(star_tile.x + 0.5, 0, star_tile.y + 0.5)
		var dist := player.global_position.distance_to(star_pos)
		
		if dist < nearest_star_dist:
			nearest_star_dist = dist
			nearest_star_tile = star_tile
	
	var tiles_away := nearest_star_dist / 1.0
	var is_too_far := tiles_away > STAR_TELEPORT_DISTANCE and nearest_star_tile != Vector2i.ZERO
	var can_teleport := _teleport_cooldown_timer <= 0 and (_time - _last_teleport_time) >= STAR_TELEPORT_COOLDOWN
	
	if is_too_far and can_teleport and not _teleport_warning_active:
		_start_teleport_warning(nearest_star_tile)
	elif not is_too_far and _teleport_warning_active:
		_cancel_teleport_warning()
	
	if _teleport_warning_active:
		_teleport_timer -= delta
		_update_teleport_warning_display()
		if _teleport_timer <= 0.0:
			_execute_teleport(nearest_star_tile)

func _start_teleport_warning(star_tile: Vector2i) -> void:
	_teleport_warning_active = true
	_teleport_timer = STAR_TELEPORT_WARNING_TIME
	_teleport_warning_label.visible = true
	_teleport_warning_label.modulate.a = 1.0
	_teleport_warning_label.set_meta("target_star_tile", star_tile)

func _update_teleport_warning_display() -> void:
	if not _teleport_warning_label:
		return
	
	var seconds := maxf(0, ceil(_teleport_timer))
	var star_tile: Vector2i = _teleport_warning_label.get_meta("target_star_tile", Vector2i.ZERO)
	
	if star_tile != Vector2i.ZERO and star_registry.has(star_tile):
		var direction := _get_direction_to_star(star_tile)
		_teleport_warning_label.text = "⚠ STAR FAR AWAY! Warping to %s in %d... ⚠" % [direction, seconds]
		var alpha := 0.5 + sin(_time * 8.0) * 0.5
		_teleport_warning_label.modulate.a = alpha

func _get_direction_to_star(star_tile: Vector2i) -> String:
	if not player:
		return "unknown"
	
	var player_tile_x := floori(player.global_position.x)
	var player_tile_z := floori(player.global_position.z)
	var dx := star_tile.x - player_tile_x
	var dz := star_tile.y - player_tile_z
	
	if abs(dx) > abs(dz):
		return "EAST" if dx > 0 else "WEST"
	else:
		return "SOUTH" if dz > 0 else "NORTH"

func _cancel_teleport_warning() -> void:
	_teleport_warning_active = false
	_teleport_warning_label.visible = false
	_teleport_warning_label.modulate.a = 0.0

func _execute_teleport(star_tile: Vector2i) -> void:
	_teleport_warning_active = false
	_teleport_warning_label.visible = false
	
	if star_tile == Vector2i.ZERO or not star_registry.has(star_tile):
		return
	
	var star_data = star_registry[star_tile]
	if star_data["collected"]:
		return
	
	var teleport_pos := Vector3(star_tile.x + 0.5, 0.5, star_tile.y + 0.5)
	
	var ray_origin := teleport_pos + Vector3(0, 5, 0)
	var ray_end := teleport_pos - Vector3(0, 10, 0)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_bodies = true
	query.collision_mask = 1
	
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		teleport_pos.y = result.position.y + 1.5
	
	_flash_teleport_screen()
	player.global_position = teleport_pos
	
	if chunk_manager:
		chunk_manager.update_player_position(teleport_pos, 0.016, Vector3.ZERO)
	
	_last_teleport_time = _time
	_teleport_cooldown_timer = STAR_TELEPORT_COOLDOWN

func _flash_teleport_screen() -> void:
	if not _cached_hud:
		return
	
	var flash := ColorRect.new()
	flash.color = Color(1.0, 1.0, 1.0, 0.8)
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cached_hud.add_child(flash)
	
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)

# ─────────────────────────────────────────────────────────────
# STAR PLACEMENT
# ─────────────────────────────────────────────────────────────

func _place_stars() -> void:
	var max_retries : int = 10
	
	for attempt in range(max_retries):
		star_registry.clear()
		_star_nodes.clear()
		
		var placed : int = 0
		var tries : int = 0
		var used_tiles : Array[Vector2i] = []

		print("[StarManager] Placing %d stars (attempt %d/%d)..." % [STAR_COUNT, attempt + 1, max_retries])

		while placed < STAR_COUNT and tries < 2000:
			tries += 1

			var angle := randf() * TAU
			var dist := randf_range(SAFE_SPAWN_RADIUS, SEARCH_RADIUS)
			var wx := int(cos(angle) * dist)
			var wz := int(sin(angle) * dist)
			var star_tile := Vector2i(wx, wz)

			var too_close := false
			for used in used_tiles:
				if star_tile.distance_squared_to(used) < 100:
					too_close = true
					break
			if too_close:
				continue

			var cell := chunk_manager.get_map_cell(wx, wz)
			if cell["state"] != "hidden":
				continue

			var cp := Vector2i(
				floori(float(wx) / chunk_manager.CHUNK_SIZE),
				floori(float(wz) / chunk_manager.CHUNK_SIZE)
			)
			
			if not chunk_manager.ensure_chunk_exists(cp):
				await get_tree().process_frame
				if not is_instance_valid(self) or not chunk_manager:
					return
				tries -= 1
				continue

			var lx := posmod(wx, chunk_manager.CHUNK_SIZE)
			var lz := posmod(wz, chunk_manager.CHUNK_SIZE)
			var idx := lx * Chunk.SIZE + lz
			
			if chunk_manager.chunks[cp].tile_mine[idx] == 1:
				continue

			used_tiles.append(star_tile)
			star_registry[star_tile] = {
				"world_tile": star_tile,
				"revealed": false,
				"collected": false,
			}
			placed += 1
			print("[StarManager] Star %d/%d placed at tile %s" % [placed, STAR_COUNT, star_tile])

		if placed >= STAR_COUNT:
			print("[StarManager] ✓ All %d/%d stars placed." % [placed, STAR_COUNT])
			_stars_placement_complete = true
			emit_signal("stars_spawned", placed)
			return

		push_warning("[StarManager] Only placed %d/%d stars, retrying in 1s..." % [placed, STAR_COUNT])
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(self):
			return

	push_error("[StarManager] Failed to place all stars after %d attempts!" % max_retries)
	_stars_placement_complete = true
	emit_signal("stars_spawned", star_registry.size())

# ─────────────────────────────────────────────────────────────
# TILE REVEAL HANDLER
# ─────────────────────────────────────────────────────────────

func on_tile_revealed(world_x: int, world_z: int) -> void:
	var revealed_tile := Vector2i(world_x, world_z)
	
	if star_registry.has(revealed_tile):
		var star_data = star_registry[revealed_tile]
		if not star_data["revealed"] and not star_data["collected"]:
			star_data["revealed"] = true
			_spawn_star_visual_at_tile(revealed_tile, star_data)
			emit_signal("star_revealed", star_registry.keys().find(revealed_tile))

func _spawn_star_visual_at_tile(star_tile: Vector2i, star_data: Dictionary) -> void:
	if star_data["collected"]:
		return
	if _star_nodes.has(star_tile) and is_instance_valid(_star_nodes[star_tile]):
		return
	
	var star_node := _build_star_visual(star_tile)
	add_child(star_node)
	star_node.global_position = Vector3(star_tile.x + 0.5, 0.3, star_tile.y + 0.5)
	_star_nodes[star_tile] = star_node

# ─────────────────────────────────────────────────────────────
# STAR VISUALS
# ─────────────────────────────────────────────────────────────

func _build_star_visual(star_tile: Vector2i) -> Node3D:
	var star_scene = load(STAR_PELLET_SCENE)
	
	if not star_scene:
		return _build_fallback_visual(star_tile)
	
	var root = star_scene.instantiate()
	root.name = "Star_%d_%d" % [star_tile.x, star_tile.y]
	
	var star_color := Color(1.0, 0.9, 0.2, 1.0)
	
	var mesh_instances = _find_all_mesh_instances(root)
	for mesh_instance in mesh_instances:
		_apply_yellow_emission_material(mesh_instance, star_color)
	
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.2)
	light.light_energy = 2.0
	light.omni_range = 4.0
	light.position = Vector3(0, 0.2, 0)
	root.add_child(light)
	
	# FIX: Increase proximity audio volume
	var audio := AudioStreamPlayer3D.new()
	audio.name = "ProximityAudio"
	audio.max_distance = PROXIMITY_SOUND_RANGE
	audio.unit_size = 4.0
	audio.autoplay = false
	audio.volume_db = 6.0  # Add this line - increase volume by 6dB
	
	var stream = _load_star_sound()
	if stream:
		audio.stream = stream
	root.add_child(audio)
	
	var label := Label3D.new()
	label.name = "CollectPrompt"
	label.text = "Press E to collect"
	label.font_size = 48
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color(1, 1, 1, 0)
	label.position = Vector3(0, 0.55, 0)
	root.add_child(label)
	
	return root

func _find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			results.append(child)
		results.append_array(_find_all_mesh_instances(child))
	return results

func _apply_yellow_emission_material(mesh_instance: MeshInstance3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mesh_instance.material_override = mat

func _build_fallback_visual(star_tile: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Star_Fallback_%d_%d" % [star_tile.x, star_tile.y]
	
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	mi.mesh = sphere
	
	var star_color := Color(1.0, 0.85, 0.1, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = star_color
	mat.emission_enabled = true
	mat.emission = star_color
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	root.add_child(mi)
	
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.2)
	light.light_energy = 2.0
	light.omni_range = 4.0
	light.position = Vector3(0, 0.2, 0)
	root.add_child(light)
	
	# Add audio to fallback visual as well
	var audio := AudioStreamPlayer3D.new()
	audio.name = "ProximityAudio"
	audio.max_distance = PROXIMITY_SOUND_RANGE
	audio.unit_size = 4.0
	audio.autoplay = false
	audio.volume_db = 6.0  # Increase volume
	
	var stream = _load_star_sound()
	if stream:
		audio.stream = stream
	root.add_child(audio)
	
	return root

func _load_star_sound() -> AudioStream:
	var paths = [
		"res://Sounds/Star/star_hum.ogg",
	]
	for path in paths:
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream:
				print("[StarManager] Loaded star sound: ", path)
				return stream
	print("[StarManager] WARNING: Star sound not found at any path!")
	return null

# ─────────────────────────────────────────────────────────────
# STAR ANIMATIONS
# ─────────────────────────────────────────────────────────────

func _update_star_animations(delta: float) -> void:
	for star_tile in _star_nodes.keys():
		var node : Node3D = _star_nodes[star_tile]
		if not is_instance_valid(node):
			_star_nodes.erase(star_tile)
			continue
		
		var star_data = star_registry[star_tile]
		if not star_data["revealed"] or star_data["collected"]:
			continue

		var base_pos := Vector3(star_tile.x + 0.5, 0.8, star_tile.y + 0.5)
		node.position.y = base_pos.y + sin(_time * 2.0 + star_tile.x * 2.1) * 0.15
		node.rotation.y += delta * 1.2

		var dist := player.global_position.distance_to(node.global_position)
		var label : Label3D = node.get_node_or_null("CollectPrompt")
		if label:
			var alpha := clampf(1.0 - (dist - 1.0) / (COLLECT_RANGE * 2.0), 0.0, 1.0)
			label.modulate.a = alpha

		if _sound_timer >= SOUND_UPDATE_INTERVAL:
			var audio : AudioStreamPlayer3D = node.get_node_or_null("ProximityAudio")
			if audio and audio.stream:
				var pitch := lerpf(0.8, 1.6, clampf(1.0 - (dist / PROXIMITY_SOUND_RANGE), 0.0, 1.0))
				audio.pitch_scale = pitch

	if _sound_timer >= SOUND_UPDATE_INTERVAL:
		_sound_timer = 0.0

# ─────────────────────────────────────────────────────────────
# COLLECTION
# ─────────────────────────────────────────────────────────────

func try_collect_nearby() -> void:
	if _game_won or not player:
		return

	for star_tile in _star_nodes.keys():
		var node : Node3D = _star_nodes[star_tile]
		if not is_instance_valid(node):
			continue
		
		var star_data = star_registry[star_tile]
		if star_data["collected"] or not star_data["revealed"]:
			continue

		var dist := player.global_position.distance_to(node.global_position)
		if dist <= COLLECT_RANGE:
			_collect_star(star_tile)
			return

func _collect_star(star_tile: Vector2i) -> void:
	var star_data = star_registry[star_tile]
	star_data["collected"] = true

	var node : Node3D = _star_nodes.get(star_tile)
	if is_instance_valid(node):
		var tween := node.create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_parallel(true)
		tween.tween_property(node, "scale", Vector3(2.0, 2.0, 2.0), 0.2)
		
		for child in node.get_children():
			if child is MeshInstance3D and child.material_override:
				var mat := child.material_override as StandardMaterial3D
				if mat:
					tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
			if child is OmniLight3D:
				tween.tween_property(child, "light_energy", 0.0, 0.2)
		
		tween.tween_callback(node.queue_free)
		tween.tween_callback(_check_win)
		_star_nodes.erase(star_tile)
	else:
		_check_win()

	_update_counter()
	var keys = star_registry.keys()
	emit_signal("star_collected", keys.find(star_tile))

func _check_win() -> void:
	if _count_collected() >= STAR_COUNT:
		_trigger_win()

func _count_collected() -> int:
	var count := 0
	for star_data in star_registry.values():
		if star_data["collected"]:
			count += 1
	return count

# ─────────────────────────────────────────────────────────────
# UI COUNTER
# ─────────────────────────────────────────────────────────────

func _setup_counter_hud() -> void:
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	var tree := get_tree()
	if not tree:
		return

	var current_scene := tree.current_scene
	if not current_scene:
		return

	var hud = current_scene.get_node_or_null("HUD")
	if not hud:
		hud = tree.root.get_node_or_null("Main/HUD")
	if not hud:
		push_warning("[StarManager] HUD node not found")
		return

	_counter_label = Label.new()
	_counter_label.name = "StarCounter"
	_counter_label.add_theme_font_size_override("font_size", 22)
	_counter_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_counter_label.position = Vector2(16, 90)
	_counter_label.text = "Stars: 0 / %d" % STAR_COUNT
	hud.add_child(_counter_label)
	_cached_hud = hud

func _update_counter() -> void:
	if not _counter_label or not is_instance_valid(_counter_label):
		return
		
	var collected := _count_collected()
	_counter_label.text = "Stars: %d / %d" % [collected, STAR_COUNT]
	
	var tween := _counter_label.create_tween()
	tween.tween_property(_counter_label, "modulate", Color(1.5, 1.3, 0.2), 0.1)
	tween.tween_property(_counter_label, "modulate", Color(1, 1, 1), 0.4)

# ─────────────────────────────────────────────────────────────
# EXIT PORTAL
# ─────────────────────────────────────────────────────────────

func _trigger_win() -> void:
	_game_won = true
	print("[StarManager] All stars collected — spawning exit portal...")
	_spawn_exit_portal()
	emit_signal("all_stars_collected")
	
	var entity_manager = get_node("/root/Main/EntityManager")
	if entity_manager and entity_manager.has_method("force_hunt_player"):
		entity_manager.force_hunt_player()
		print("[StarManager] Triggered enemy hunt mode!")

func _spawn_exit_portal() -> void:
	var tile := _find_portal_tile()
	if tile == Vector2i(-9999, -9999):
		push_warning("[StarManager] Could not find portal tile — spawning at origin fallback")
		tile = Vector2i(5, 5)

	_portal_tile = tile
	_portal_node = _build_portal_visual()
	add_child(_portal_node)
	_portal_node.global_position = Vector3(tile.x + 0.5, 0.0, tile.y + 0.5)
	_portal_active = true

func _find_portal_tile() -> Vector2i:
	var candidates : Array[Vector2i] = []

	for cp in chunk_manager.chunks.keys():
		if not chunk_manager.loaded_chunks.has(cp):
			continue

		var base_wx : int = cp.x * chunk_manager.CHUNK_SIZE
		var base_wz : int = cp.y * chunk_manager.CHUNK_SIZE

		for lx in range(chunk_manager.CHUNK_SIZE):
			for lz in range(chunk_manager.CHUNK_SIZE):
				var wx := base_wx + lx
				var wz := base_wz + lz
				var dist := Vector2(wx, wz).length()
				if dist < PORTAL_SAFE_RADIUS:
					continue
				var cell := chunk_manager.get_map_cell(wx, wz)
				if cell["state"] == "revealed" and cell["number"] == 0:
					candidates.append(Vector2i(wx, wz))

	if candidates.is_empty():
		return Vector2i(-9999, -9999)

	# Pick the tile farthest from the player
	var player_pos := Vector2.ZERO
	if player:
		player_pos = Vector2(player.global_position.x, player.global_position.z)

	var best_tile := candidates[0]
	var best_dist := player_pos.distance_squared_to(Vector2(best_tile.x, best_tile.y))
	for tile in candidates:
		var d := player_pos.distance_squared_to(Vector2(tile.x, tile.y))
		if d > best_dist:
			best_dist = d
			best_tile = tile
	return best_tile

func _build_portal_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "ExitPortal"

	if _tile_scene:
		var tile_inst : Node3D = _tile_scene.instantiate()
		tile_inst.set_script(null)
		tile_inst.position = Vector3(0, 1.5, 0.0)
		root.add_child(tile_inst)
		_apply_portal_material(tile_inst)
	else:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 2.5, 1.0)
		mi.mesh = box
		mi.position = Vector3(0, 1.25, 0)
		root.add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 1.0, 1.0)
	light.light_energy = 4.0
	light.omni_range = 8.0
	light.position = Vector3(0, 1.5, 0)
	root.add_child(light)

	var pulse_light := OmniLight3D.new()
	pulse_light.name = "PulseLight"
	pulse_light.light_color = Color(0.8, 0.9, 1.0)
	pulse_light.light_energy = 2.0
	pulse_light.omni_range = 5.0
	pulse_light.position = Vector3(0, 1.5, 0)
	root.add_child(pulse_light)

	var label := Label3D.new()
	label.name = "PortalLabel"
	label.text = "EXIT"
	label.font_size = 96
	label.pixel_size = 0.007
	label.modulate = Color(1.0, 1.0, 1.0)
	label.outline_size = 8
	label.outline_modulate = Color(0.5, 0.8, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = Vector3(0, 2.8, 0)
	root.add_child(label)

	var area := Area3D.new()
	area.name = "TouchArea"
	area.collision_layer = 0
	area.collision_mask = 1
	area.body_entered.connect(_on_portal_touched)
	
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 2.5, 1.5)
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	area.add_child(col)
	root.add_child(area)

	return root

func _on_portal_touched(body: Node) -> void:
	if body == player or (player and body.name == "Player"):
		_trigger_real_win()

func _apply_portal_material(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 1.0, 1.0)
			mat.emission_energy_multiplier = 3.0
			child.material_override = mat
		if child.get_child_count() > 0:
			_apply_portal_material(child)

func _update_portal_pulse(delta: float) -> void:
	if not _portal_active or not is_instance_valid(_portal_node):
		return

	var pulse_light : OmniLight3D = _portal_node.get_node_or_null("PulseLight")
	if pulse_light:
		pulse_light.light_energy = 2.0 + sin(_time * 4.0) * 1.0

	var dist_to_portal := player.global_position.distance_to(_portal_node.global_position)
	if dist_to_portal <= PORTAL_TOUCH_RANGE:
		_trigger_real_win()

func _trigger_real_win() -> void:
	if not _portal_active:
		return
	_portal_active = false
	emit_signal("game_won")

# ─────────────────────────────────────────────────────────────
# PULSE VISION HIGHLIGHT (Public API) - FIXED
# ─────────────────────────────────────────────────────────────

func set_star_pulse_highlight(enabled: bool) -> void:
	if enabled:
		# Show ALL uncollected stars, whether revealed or not
		for star_tile in star_registry.keys():
			var star_data = star_registry[star_tile]
			if star_data["collected"]:
				continue
			
			if star_data["revealed"]:
				# Star is visible — apply through-wall outline to its mesh
				var star_node = _star_nodes.get(star_tile)
				if star_node:
					_apply_star_pulse_outline(star_node, true, Color(1.0, 0.85, 0.2))
			else:
				# Star not yet revealed — spawn a ghost marker visible through walls
				_spawn_pulse_ghost(star_tile)
		
		# Also highlight the exit portal if active
		if _portal_active and is_instance_valid(_portal_node):
			_apply_star_pulse_outline(_portal_node, true, Color(0.4, 0.9, 1.0))
	else:
		# Remove pulse effect from all star visuals
		for star_node in _star_nodes.values():
			if is_instance_valid(star_node):
				_apply_star_pulse_outline(star_node, false, Color.WHITE)
		
		# Remove all pulse ghosts
		for ghost in _pulse_ghost_nodes.values():
			if is_instance_valid(ghost):
				ghost.queue_free()
		_pulse_ghost_nodes.clear()
		
		# Restore exit portal
		if is_instance_valid(_portal_node):
			_apply_star_pulse_outline(_portal_node, false, Color.WHITE)

func _spawn_pulse_ghost(star_tile: Vector2i) -> void:
	"""Spawn a ghost marker for unrevealed stars during pulse vision"""
	if _pulse_ghost_nodes.has(star_tile):
		return
	
	var ghost := Node3D.new()
	ghost.name = "PulseGhost_%d_%d" % [star_tile.x, star_tile.y]
	
	# Glowing sphere visible through walls
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	mi.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	mat.emission_energy_multiplier = 6.0
	mat.no_depth_test = true          # Renders through all geometry
	mat.render_priority = 10
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	ghost.add_child(mi)
	
	# "?" label so it's clear this is an undiscovered star
	var label := Label3D.new()
	label.text = "?"
	label.font_size = 64
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 11
	label.modulate = Color(1.0, 0.9, 0.3, 1.0)
	label.position = Vector3(0, 0.6, 0)
	ghost.add_child(label)
	
	add_child(ghost)
	# Position at tile center, raised to be above tile surface
	ghost.global_position = Vector3(star_tile.x + 0.5, 1.8, star_tile.y + 0.5)
	_pulse_ghost_nodes[star_tile] = ghost

func _outline_tile_at_position(star_tile: Vector2i, enabled: bool) -> void:
	"""Apply gold outline to the tile itself (for unspawned stars)"""
	if not chunk_manager:
		return
	
	# Get the chunk and local coordinates
	var cp := Vector2i(
		floori(float(star_tile.x) / chunk_manager.CHUNK_SIZE),
		floori(float(star_tile.y) / chunk_manager.CHUNK_SIZE)
	)
	var lx := posmod(star_tile.x, chunk_manager.CHUNK_SIZE)
	var lz := posmod(star_tile.y, chunk_manager.CHUNK_SIZE)
	
	var tile = chunk_manager.get_tile_node(cp, lx, lz)
	if tile and tile.has_method("_apply_pulse_outline"):
		var color = Color(1.0, 0.85, 0.2) if enabled else Color.WHITE
		tile._apply_pulse_outline(enabled, color)

func _apply_star_pulse_outline(node: Node, enabled: bool, pulse_color: Color) -> void:
	"""Apply gold outline to star visuals - similar to enemy pulse vision"""
	for child in node.get_children():
		if child is MeshInstance3D:
			if enabled:
				# Store original material for later restoration
				if not child.has_meta("_star_pulse_mat_backup"):
					child.set_meta("_star_pulse_mat_backup", child.material_override)
					# Also store surface materials
					var surface_backups: Array = []
					for s in range(child.get_surface_override_material_count()):
						surface_backups.append(child.get_surface_override_material(s))
					child.set_meta("_star_pulse_surf_backup", surface_backups)
				
				# Create outline material (unshaded, glowing)
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = pulse_color
				mat.albedo_color.a = 0.85  # Set alpha BEFORE or AFTER? Works both ways, but clarity
				mat.emission_enabled = true
				mat.emission = pulse_color
				mat.emission_energy_multiplier = 6.0
				mat.no_depth_test = true  # This makes it visible through walls!
				mat.render_priority = 10
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				child.material_override = mat
			else:
				# Restore original material
				if child.has_meta("_star_pulse_mat_backup"):
					child.material_override = child.get_meta("_star_pulse_mat_backup")
					child.remove_meta("_star_pulse_mat_backup")
				if child.has_meta("_star_pulse_surf_backup"):
					var surface_backups: Array = child.get_meta("_star_pulse_surf_backup")
					for s in range(surface_backups.size()):
						child.set_surface_override_material(s, surface_backups[s])
					child.remove_meta("_star_pulse_surf_backup")
		
		elif child is Label3D:
			if enabled:
				if not child.has_meta("_pulse_label_depth_backup"):
					child.set_meta("_pulse_label_depth_backup", child.no_depth_test)
					child.set_meta("_pulse_label_priority_backup", child.render_priority)
				child.no_depth_test = true
				child.render_priority = 11
			else:
				if child.has_meta("_pulse_label_depth_backup"):
					child.no_depth_test = child.get_meta("_pulse_label_depth_backup")
					child.render_priority = child.get_meta("_pulse_label_priority_backup")
					child.remove_meta("_pulse_label_depth_backup")
					child.remove_meta("_pulse_label_priority_backup")
		
		if child.get_child_count() > 0:
			_apply_star_pulse_outline(child, enabled, pulse_color)

func _apply_star_pulse_to_node(node: Node, enabled: bool, pulse_color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			if enabled:
				if not child.has_meta("_pulse_mat_backup"):
					child.set_meta("_pulse_mat_backup", child.material_override)
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = pulse_color
				mat.emission_enabled = true
				mat.emission = pulse_color
				mat.emission_energy_multiplier = 8.0
				mat.no_depth_test = true
				mat.render_priority = 10
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				child.material_override = mat
			else:
				if child.has_meta("_pulse_mat_backup"):
					child.material_override = child.get_meta("_pulse_mat_backup")
					child.remove_meta("_pulse_mat_backup")
		if child.get_child_count() > 0:
			_apply_star_pulse_to_node(child, enabled, pulse_color)

# ─────────────────────────────────────────────────────────────
# GETTERS
# ─────────────────────────────────────────────────────────────

func get_collected_count() -> int:
	return _count_collected()

func get_star_count() -> int:
	return star_registry.size()

func is_game_won() -> bool:
	return _game_won
