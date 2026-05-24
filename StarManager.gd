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

# ─────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────

var chunk_manager : ChunkManager = null
var player : CharacterBody3D = null
var _counter_label : Label = null
var _tile_scene : PackedScene = null

var _stars : Array[Dictionary] = []
var _sound_timer : float = 0.0
var _game_won : bool = false
var _time : float = 0.0

var _portal_node : Node3D = null
var _portal_tile : Vector2i = Vector2i.ZERO
var _portal_active : bool = false

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_setup_audio()

func _process(delta: float) -> void:
	if not player or _game_won:
		return

	_time += delta
	_sound_timer += delta

	_update_star_animations(delta)
	_update_portal_pulse(delta)

# ─────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────

func setup(cm: ChunkManager, p: CharacterBody3D) -> void:
	chunk_manager = cm
	player = p
	_tile_scene = cm.tile_scene

func place_stars_now() -> void:
	_place_stars()
	_setup_counter_hud()

func _setup_audio() -> void:
	var audio := get_node_or_null("ProximityAudio")
	if audio and audio.stream:
		audio.play()

# ─────────────────────────────────────────────────────────────
# STAR PLACEMENT
# ─────────────────────────────────────────────────────────────

func _place_stars() -> void:
	var max_retries : int = 10
	
	for attempt in range(max_retries):
		_stars.clear()
		
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
			var tile := Vector2i(wx, wz)

			var too_close := false
			for used in used_tiles:
				if tile.distance_squared_to(used) < 100:
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
			if not chunk_manager.chunks.has(cp):
				var chunk := Chunk.new()
				chunk.chunk_pos = cp
				chunk.generate(chunk_manager._global_seed, chunk_manager._make_mine_lookup())
				chunk_manager.chunks[cp] = chunk

			var lx := posmod(wx, chunk_manager.CHUNK_SIZE)
			var lz := posmod(wz, chunk_manager.CHUNK_SIZE)
			var idx := lx * Chunk.SIZE + lz
			if chunk_manager.chunks[cp].tile_mine[idx] == 1:
				continue

			used_tiles.append(tile)
			_stars.append({
				"world_tile": tile,
				"star_node": null,
				"revealed": false,
				"collected": false,
			})
			placed += 1
			print("[StarManager] Star %d/%d placed at tile %s" % [placed, STAR_COUNT, tile])

		if placed >= STAR_COUNT:
			print("[StarManager] ✓ All %d/%d stars placed." % [placed, STAR_COUNT])
			emit_signal("stars_spawned", placed)
			return

		push_warning("[StarManager] Only placed %d/%d stars, retrying in 1s..." % [placed, STAR_COUNT])
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(self):
			return

	push_error("[StarManager] Failed to place all stars after %d attempts!" % max_retries)
	emit_signal("stars_spawned", _stars.size())

# ─────────────────────────────────────────────────────────────
# TILE REVEAL HANDLER
# ─────────────────────────────────────────────────────────────

func on_tile_revealed(world_x: int, world_z: int) -> void:
	for i in range(_stars.size()):
		var star := _stars[i]
		if star["revealed"] or star["collected"]:
			continue
			
		if star["world_tile"] == Vector2i(world_x, world_z):
			star["revealed"] = true
			_spawn_star_visual(i)
			emit_signal("star_revealed", i)
			print("[StarManager] Star %d revealed at %s!" % [i, star["world_tile"]])

# ─────────────────────────────────────────────────────────────
# STAR VISUALS
# ─────────────────────────────────────────────────────────────

func _spawn_star_visual(idx: int) -> void:
	var tile : Vector2i = _stars[idx]["world_tile"]
	var star_node := _build_star_visual(idx)
	
	add_child(star_node)
	star_node.global_position = Vector3(tile.x + 0.5, 0.3, tile.y + 0.5)
	_stars[idx]["star_node"] = star_node

func _build_star_visual(idx: int) -> Node3D:
	var star_scene = load(STAR_PELLET_SCENE)
	
	if not star_scene:
		push_error("[StarManager] Could not load StarPellet.tscn")
		return _build_fallback_visual(idx)
	
	var root = star_scene.instantiate()
	root.name = "Star_%d" % idx
	
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
	
	var audio := AudioStreamPlayer3D.new()
	audio.name = "ProximityAudio"
	audio.max_distance = PROXIMITY_SOUND_RANGE
	audio.unit_size = 4.0
	audio.autoplay = false
	
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

func _build_fallback_visual(idx: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Star_Fallback_%d" % idx
	
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
	
	return root

func _load_star_sound() -> AudioStream:
	var paths = ["res://Sounds/Star/star_hum.ogg"]
	for path in paths:
		if ResourceLoader.exists(path):
			return load(path)
	return null

# ─────────────────────────────────────────────────────────────
# STAR ANIMATIONS
# ─────────────────────────────────────────────────────────────

func _update_star_animations(delta: float) -> void:
	for i in range(_stars.size()):
		var star := _stars[i]
		if not star["revealed"] or star["collected"]:
			continue
			
		var node : Node3D = star["star_node"]
		if not is_instance_valid(node):
			continue

		var tile : Vector2i = star["world_tile"]
		var base_pos := Vector3(tile.x + 0.5, 0.8, tile.y + 0.5)

		node.position.y = base_pos.y + sin(_time * 2.0 + i * 2.1) * 0.15
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
	print("[StarManager] try_collect_nearby called")
	
	if _game_won or not player:
		print("[StarManager] Game won or no player")
		return

	for i in range(_stars.size()):
		var star := _stars[i]
		if not star["revealed"] or star["collected"]:
			continue
			
		var node : Node3D = star["star_node"]
		if not is_instance_valid(node):
			continue

		var dist := player.global_position.distance_to(node.global_position)
		print("[StarManager] Star %d distance: %.2f" % [i, dist])
		
		if dist <= COLLECT_RANGE:
			print("[StarManager] Collecting star %d!" % i)
			_collect_star(i)
			return

func _collect_star(idx: int) -> void:
	var star := _stars[idx]
	star["collected"] = true

	var node : Node3D = star["star_node"]
	if is_instance_valid(node):
		var tween := node.create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_parallel(true)
		
		tween.tween_property(node, "scale", Vector3(2.0, 2.0, 2.0), 0.2)
		_fade_out_star(node, tween)
		tween.tween_callback(node.queue_free)
		tween.tween_callback(_check_win)
	else:
		_check_win()

	_update_counter()
	emit_signal("star_collected", idx)
	print("[StarManager] Star %d collected! (%d/%d)" % [idx, _count_collected(), STAR_COUNT])

func _check_win() -> void:
	if _count_collected() >= STAR_COUNT:
		_trigger_win()

func _fade_out_star(node: Node3D, tween: Tween) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.material_override:
			var mat := child.material_override as StandardMaterial3D
			if mat:
				tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
		
		if child is OmniLight3D:
			tween.tween_property(child, "light_energy", 0.0, 0.2)

# ─────────────────────────────────────────────────────────────
# UI COUNTER
# ─────────────────────────────────────────────────────────────

func _setup_counter_hud() -> void:
	# Wait a frame to ensure the scene tree is fully settled
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	var tree := get_tree()
	if not tree:
		return

	var current_scene := tree.current_scene
	if not current_scene:
		return

	var hud := current_scene.get_node_or_null("HUD")
	if not hud:
		# Fallback: search from root
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

func _update_counter() -> void:
	if not _counter_label or not is_instance_valid(_counter_label):
		return
		
	var collected := _count_collected()
	_counter_label.text = "Stars: %d / %d" % [collected, STAR_COUNT]
	
	var tween := _counter_label.create_tween()
	tween.tween_property(_counter_label, "modulate", Color(1.5, 1.3, 0.2), 0.1)
	tween.tween_property(_counter_label, "modulate", Color(1, 1, 1), 0.4)

func _count_collected() -> int:
	var count := 0
	for star in _stars:
		if star["collected"]:
			count += 1
	return count

# ─────────────────────────────────────────────────────────────
# EXIT PORTAL (1x1 tile with working collision)
# ─────────────────────────────────────────────────────────────

func _trigger_win() -> void:
	_game_won = true
	print("[StarManager] All stars collected — spawning exit portal...")
	_spawn_exit_portal()
	emit_signal("all_stars_collected")

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

	print("[StarManager] Exit portal spawned at tile %s" % tile)

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

	return candidates[randi() % candidates.size()]

func _build_portal_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "ExitPortal"

	# Single tile portal
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

	# Lights
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

	# EXIT label
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

	# FIXED: Collision area with signal connection
	var area := Area3D.new()
	area.name = "TouchArea"
	area.collision_layer = 0
	area.collision_mask = 1  # Detect player on layer 1
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
	print("[StarManager] Portal touched by: ", body.name)
	
	# Check if it's the player
	if body == player or (player and body.name == "Player"):
		print("[StarManager] Player touched portal! Triggering win...")
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

	# Distance check as fallback
	var dist_to_portal := player.global_position.distance_to(_portal_node.global_position)
	if dist_to_portal <= PORTAL_TOUCH_RANGE:
		print("[StarManager] Player within distance %.2f of portal" % dist_to_portal)
		_trigger_real_win()

# ─────────────────────────────────────────────────────────────
# WIN
# ─────────────────────────────────────────────────────────────

func _trigger_real_win() -> void:
	if not _portal_active:
		return
		
	_portal_active = false
	print("[StarManager] *** PLAYER TOUCHED EXIT PORTAL — GAME WON! ***")
	emit_signal("game_won")

# ─────────────────────────────────────────────────────────────
# GETTERS
# ─────────────────────────────────────────────────────────────

func get_collected_count() -> int:
	return _count_collected()

func get_star_count() -> int:
	return _stars.size()

func is_game_won() -> bool:
	return _game_won
