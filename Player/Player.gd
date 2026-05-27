extends CharacterBody3D

# ─────────────────────────────────────────────────────────────
# EXPORTS
# ─────────────────────────────────────────────────────────────
@export var interact_range     : float = 2.5
@export var base_speed         : float = 2.5
@export var gravity            : float = 20.0
@export var jump_force         : float = 7.0
@export var eye_height         : float = 0.3
@export var sprint_multiplier  : float = 1.8
@export var slow_multiplier    : float = 0.5
@export var chunk_manager_path : NodePath
@export var spawn_height       : float = 1.5

# ─────────────────────────────────────────────────────────────
# LIVES
# ─────────────────────────────────────────────────────────────
const MAX_LIVES          : int   = 4
const HIT_INVULN_SECS    : float = 1.5
const SPAWN_HEIGHT_OFFSET : float = 2.0

var lives        : int   = MAX_LIVES
var is_immortal  : bool  = false
var _hit_timer   : float = 0.0

signal life_lost(lives_remaining: int)
signal life_gained(lives_remaining: int)
signal lives_depleted

# ─────────────────────────────────────────────────────────────
# WEAPON STATE
# ─────────────────────────────────────────────────────────────
var _has_weapon : bool = false
var _weapon_equipped : bool = false
var _weapon_manager = null
var _weapon_model : Node3D = null
var _is_shooting : bool = false
var _shoot_cooldown : float = 0.0
const SHOOT_COOLDOWN_TIME : float = 0.5

# ─────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────
var _rotation_x : float = 0.0
var _rotation_y : float = 0.0
var _has_moved  : bool  = false
var _current_speed : float = 5.0
var _initial_spawn_complete  : bool = false
var _position_retry_count    : int  = 0
const MAX_POSITION_RETRIES   : int  = 10
var _camera_locked : bool = false
var _is_sinking_with_tile : bool = false
var _sink_tween : Tween = null
var _original_ground_y : float = 0.0

var _mouse_sensitivity_value : float = 0.0015
var _invert_y : bool = false

@onready var camera        : Camera3D  = $Camera3D
@onready var chunk_manager : ChunkManager = get_node_or_null(chunk_manager_path)
@onready var weapon_holder : Node3D    = $Camera3D/WeaponHolder
@onready var shoot_ray_cast: RayCast3D = $Camera3D/ShootRayCast

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.position.y = eye_height
	_current_speed = base_speed
	
	_connect_settings()
	add_to_group("player")
	
	if not weapon_holder:
		weapon_holder = Node3D.new()
		weapon_holder.name = "WeaponHolder"
		camera.add_child(weapon_holder)
		weapon_holder.position = Vector3(0.3, -0.2, -0.5)
	
	if not shoot_ray_cast:
		shoot_ray_cast = RayCast3D.new()
		shoot_ray_cast.name = "ShootRayCast"
		camera.add_child(shoot_ray_cast)
		shoot_ray_cast.target_position = Vector3(0, 0, -interact_range)
		shoot_ray_cast.collision_mask  = 2
	
	if not chunk_manager:
		push_warning("Player: ChunkManager not assigned via NodePath!")
		_initial_spawn_complete = true
		enable_controls()
	else:
		if chunk_manager.has_signal("spawn_chunks_ready"):
			if chunk_manager.spawn_chunks_ready.is_connected(_on_initial_spawn_ready):
				chunk_manager.spawn_chunks_ready.disconnect(_on_initial_spawn_ready)
			chunk_manager.spawn_chunks_ready.connect(_on_initial_spawn_ready)
		call_deferred("_try_initial_position")

func set_player_mouse_sensitivity(value: float) -> void:
	_mouse_sensitivity_value = value
	print("[Player] Mouse sensitivity set to: ", value)

func _on_settings_changed() -> void:
	if SettingsManager:
		set_player_mouse_sensitivity(SettingsManager.get_setting("sensitivity", 0.0015))

func _connect_settings() -> void:
	if not SettingsManager:
		print("[Player] SettingsManager not found, using defaults")
		_mouse_sensitivity_value = 0.0015
		_invert_y = false
		return
	
	_mouse_sensitivity_value = SettingsManager.get_setting("sensitivity", 0.0015)
	_invert_y = SettingsManager.get_setting("invert_y", false)
	
	if not SettingsManager.sensitivity_changed.is_connected(_on_sensitivity_changed):
		SettingsManager.sensitivity_changed.connect(_on_sensitivity_changed)
	if not SettingsManager.invert_y_changed.is_connected(_on_invert_y_changed):
		SettingsManager.invert_y_changed.connect(_on_invert_y_changed)
	
	print("[Player] Settings loaded - Sensitivity: ", _mouse_sensitivity_value, " Invert Y: ", _invert_y)

func _on_sensitivity_changed(value: float) -> void:
	_mouse_sensitivity_value = value
	print("[Player] Mouse sensitivity changed to: ", value)

func _on_invert_y_changed(value: bool) -> void:
	_invert_y = value
	print("[Player] Invert Y changed to: ", value)

func _try_initial_position() -> void:
	await get_tree().create_timer(0.5).timeout
	_position_on_clear_tile()

func _process(delta: float) -> void:
	if _shoot_cooldown > 0:
		_shoot_cooldown -= delta

func _physics_process(delta: float) -> void:
	if _hit_timer > 0:
		_hit_timer -= delta
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0:
		velocity.y = 0

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force

	# Movement
	var input_dir    := _get_movement_input()
	var direction    := _calculate_movement_direction(input_dir)
	var current_speed := _get_current_speed()

	if direction != Vector3.ZERO:
		direction = direction.normalized()
		if not _has_moved:
			_has_moved = true
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)

	move_and_slide()

	if chunk_manager and is_instance_valid(chunk_manager):
		chunk_manager.update_player_position(global_position, delta, velocity)

# Add to Player.gd
func force_look_at(target_pos: Vector3) -> void:
	var dir = (target_pos - global_position).normalized()
	_rotation_y = rad_to_deg(atan2(dir.x, dir.z))
	_rotation_x = 0.0 # Level the head
	rotation_degrees.y = _rotation_y
	camera.rotation_degrees.x = _rotation_x

# ─────────────────────────────────────────────────────────────
# JUMPSCARE
# ─────────────────────────────────────────────────────────────

func lock_camera(locked: bool) -> void:
	_camera_locked = locked
	if locked:
		# Optionally force velocity to zero
		velocity = Vector3.ZERO

# ─────────────────────────────────────────────────────────────
# TILE SINKING (called by tiles when they sink)
# ─────────────────────────────────────────────────────────────

func sink_with_tile(start_y: float, target_y: float, duration: float) -> void:
	"""Called by tiles to make the player sink along with them"""
	if _is_sinking_with_tile:
		return
	
	_is_sinking_with_tile = true
	_original_ground_y = start_y
	
	if _sink_tween and is_instance_valid(_sink_tween):
		_sink_tween.kill()
	
	_sink_tween = create_tween()
	if not _sink_tween:
		_is_sinking_with_tile = false
		return
	
	# Calculate target player Y position (feet stay on tile surface)
	var sink_distance = start_y - target_y
	var target_player_y = global_position.y - sink_distance
	
	_sink_tween.set_ease(Tween.EASE_IN)
	_sink_tween.set_trans(Tween.TRANS_CUBIC)
	_sink_tween.tween_property(self, "position:y", target_player_y, duration)
	_sink_tween.finished.connect(_on_sink_with_tile_finished, CONNECT_ONE_SHOT)

func _on_sink_with_tile_finished() -> void:
	_is_sinking_with_tile = false
	_sink_tween = null

# ─────────────────────────────────────────────────────────────
# LIVES SYSTEM
# ─────────────────────────────────────────────────────────────
func lose_life() -> void:
	if is_immortal:
		print("[Player] Immortal mode - no life lost")
		return
	
	if _hit_timer > 0:
		print("[Player] Invincible - no life lost (%.1fs left)" % _hit_timer)
		return
	
	if lives > 0:
		lives -= 1
		_hit_timer = HIT_INVULN_SECS
		print("[Player] Life lost! Lives remaining: %d" % lives)
		life_lost.emit(lives)
		
		if lives <= 0:
			lives_depleted.emit()

func lose_all_lives() -> void:
	if is_immortal:
		print("[Player] Immortal mode - no lives lost")
		return
	
	lives = 0
	print("[Player] Caught by enemy — all lives lost!")
	_flash_red_screen()
	lives_depleted.emit(lives)

func gain_life() -> void:
	if lives < MAX_LIVES:
		lives += 1
		print("[Player] Life gained! Lives: %d" % lives)
		life_gained.emit(lives)
	else:
		print("[Player] Already at max lives (%d)" % MAX_LIVES)

func reset_lives() -> void:
	lives = MAX_LIVES
	_hit_timer = 0.0

func toggle_immortal() -> void:
	is_immortal = not is_immortal
	print("[Player] Immortality: %s" % ("ON" if is_immortal else "OFF"))

func _flash_red_screen() -> void:
	if not camera:
		return
	
	var overlay := ColorRect.new()
	overlay.color = Color(1.0, 0.0, 0.0, 0.5)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var hud := get_node_or_null("/root/Main/HUD")
	if hud:
		hud.add_child(overlay)
		var tween := overlay.create_tween()
		tween.tween_property(overlay, "color:a", 0.0, 0.5)
		tween.tween_callback(overlay.queue_free)

# ─────────────────────────────────────────────────────────────
# WEAPON FUNCTIONS
# ─────────────────────────────────────────────────────────────
func _on_weapon_picked_up() -> void:
	_has_weapon = true
	print("[Player] Weapon acquired!")

func _equip_weapon() -> void:
	if not _has_weapon or _weapon_equipped:
		return
	_weapon_equipped = true
	if not _weapon_model:
		var weapon_scene = load("res://items/deagle.tscn")
		if weapon_scene:
			_weapon_model = weapon_scene.instantiate()
			if "is_equipped" in _weapon_model:
				_weapon_model.is_equipped = true
			weapon_holder.add_child(_weapon_model)
		else:
			_weapon_model = MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(0.2, 0.1, 0.4)
			_weapon_model.mesh = box_mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.3, 0.3)
			_weapon_model.material_override = mat
			weapon_holder.add_child(_weapon_model)
	_weapon_model.visible = true
	_play_weapon_animation("equip")
	print("[Player] Weapon equipped")

func _unequip_weapon() -> void:
	if not _weapon_equipped:
		return
	_weapon_equipped = false
	if _weapon_model:
		_play_weapon_animation("unequip")
		await get_tree().create_timer(0.2).timeout
		_weapon_model.visible = false
	print("[Player] Weapon unequipped")

func _shoot_weapon() -> void:
	if not _weapon_equipped or _is_shooting:
		return
	if _shoot_cooldown > 0:
		return
	_is_shooting = true
	_shoot_cooldown = SHOOT_COOLDOWN_TIME
	_play_weapon_animation("shoot")
	
	if shoot_ray_cast.is_colliding():
		var collider = shoot_ray_cast.get_collider()
		var enemy = _find_enemy_parent(collider)
		if enemy and enemy.has_method("defeat"):
			enemy.defeat()
			_has_weapon = false
			_weapon_equipped = false
			if _weapon_model:
				_weapon_model.visible = false
			if _weapon_manager:
				_weapon_manager.weapon_picked_up.disconnect(_on_weapon_picked_up)
			_add_shoot_effect()
			print("[Player] Enemy defeated with weapon!")
	await get_tree().create_timer(0.2).timeout
	_is_shooting = false

func _find_enemy_parent(node: Node) -> Node:
	var current = node
	while current:
		if current.has_method("defeat"):
			return current
		current = current.get_parent()
	return null

func _play_weapon_animation(anim_type: String) -> void:
	if not _weapon_model:
		return
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	match anim_type:
		"equip":
			_weapon_model.scale = Vector3(0, 0, 0)
			tween.tween_property(_weapon_model, "scale", Vector3(1, 1, 1), 0.3)
		"unequip":
			tween.tween_property(_weapon_model, "scale", Vector3(0, 0, 0), 0.2)
		"shoot":
			var original_pos = _weapon_model.position
			tween.tween_property(_weapon_model, "position", original_pos + Vector3(0, 0, -0.1), 0.05)
			tween.tween_property(_weapon_model, "position", original_pos, 0.1)
			_add_muzzle_flash()

func _add_muzzle_flash() -> void:
	if not _weapon_model:
		return
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	flash.mesh = sphere
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 0.8, 0)
	material.emission_enabled = true
	material.emission = Color(1, 0.5, 0)
	material.emission_energy_multiplier = 2.0
	flash.material_override = material
	flash.position = Vector3(0, 0, -0.3)
	_weapon_model.add_child(flash)
	await get_tree().create_timer(0.1).timeout
	flash.queue_free()

func _add_shoot_effect() -> void:
	var hit_effect = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.2
	hit_effect.mesh = sphere
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 0, 0)
	material.emission_enabled = true
	material.emission = Color(1, 0, 0)
	material.emission_energy_multiplier = 1.0
	hit_effect.material_override = material
	add_child(hit_effect)
	await get_tree().create_timer(0.2).timeout
	hit_effect.queue_free()

# ─────────────────────────────────────────────────────────────
# SPAWN POSITIONING
# ─────────────────────────────────────────────────────────────
func _on_initial_spawn_ready() -> void:
	print("[Player] Spawn chunks ready signal received")
	_position_on_clear_tile()

func _position_on_clear_tile() -> void:
	if _initial_spawn_complete:
		return
	if not chunk_manager:
		print("[Player] No chunk_manager, spawning at default position")
		global_position = Vector3(10.5, spawn_height, 10.5)
		_initial_spawn_complete = true
		enable_controls()
		return
	var center_chunk = Vector2i(0, 0)
	var center_tile_x = 10
	var center_tile_z = 10
	var spawn_pos = _find_clear_spawn_position(center_chunk, center_tile_x, center_tile_z)
	if spawn_pos == Vector3.ZERO:
		print("[Player] Center tile not clear, searching for clear spawn location...")
		spawn_pos = _find_nearest_clear_tile(center_chunk, center_tile_x, center_tile_z)
	if spawn_pos != Vector3.ZERO:
		global_position = spawn_pos
		_initial_spawn_complete = true
		_adjust_to_ground_height()
		print("[Player] Spawned at clear tile position: ", global_position)
		enable_controls()
	else:
		_position_retry_count += 1
		if _position_retry_count <= MAX_POSITION_RETRIES:
			print("[Player] No clear tile found (attempt %d/%d), retrying in 0.5s..." % [_position_retry_count, MAX_POSITION_RETRIES])
			await get_tree().create_timer(0.5).timeout
			_position_on_clear_tile()
		else:
			print("[Player] WARNING: Could not find clear tile after %d attempts! Spawning at default position." % MAX_POSITION_RETRIES)
			global_position = Vector3(10.5, spawn_height, 10.5)
			_initial_spawn_complete = true
			enable_controls()

func _adjust_to_ground_height() -> void:
	var ray_origin := global_position + Vector3(0, SPAWN_HEIGHT_OFFSET, 0)
	var ray_end := global_position - Vector3(0, 20.0, 0)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_bodies = true
	query.collision_mask = 1
	query.exclude = [self]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	
	if not result.is_empty():
		# Check if we hit a tile first (tiles are at higher Y than ground plane)
		var hit_node = result["collider"]
		var tile = _find_tile_parent(hit_node)
		
		if tile and tile.has_method("get_tile_top_height"):
			var tile_top = tile.get_tile_top_height()
			global_position.y = tile_top + 0.1  # Slightly above tile surface
			print("[Player] Placed on tile at height: %.2f" % global_position.y)
		else:
			var ground_y = result.position.y
			global_position.y = ground_y + spawn_height
			print("[Player] Placed on ground at height: %.2f" % global_position.y)
	else:
		global_position.y = spawn_height
		print("[Player] No ground found, using default height: %.2f" % spawn_height)

func _find_tile_parent(node: Node) -> Node:
	var current = node
	while current:
		if current.has_method("get_tile_top_height"):
			return current
		current = current.get_parent()
	return null

func _find_clear_spawn_position(chunk_pos: Vector2i, local_x: int, local_z: int) -> Vector3:
	if not chunk_manager:
		return Vector3.ZERO
	var global_x = chunk_pos.x * chunk_manager.CHUNK_SIZE + local_x
	var global_z = chunk_pos.y * chunk_manager.CHUNK_SIZE + local_z
	var cell = chunk_manager.get_map_cell(global_x, global_z)
	if cell["state"] == "revealed" and cell["number"] == 0:
		return Vector3(global_x + 0.5, spawn_height, global_z + 0.5)
	return Vector3.ZERO

func _find_nearest_clear_tile(center_chunk: Vector2i, center_x: int, center_z: int) -> Vector3:
	for radius in range(1, 25):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dz) != radius:
					continue
				var check_x = center_x + dx
				var check_z = center_z + dz
				var chunk_offset = Vector2i(0, 0)
				var local_x = check_x
				var local_z = check_z
				if local_x < 0:
					chunk_offset.x -= 1
					local_x += chunk_manager.CHUNK_SIZE
				elif local_x >= chunk_manager.CHUNK_SIZE:
					chunk_offset.x += 1
					local_x -= chunk_manager.CHUNK_SIZE
				if local_z < 0:
					chunk_offset.y -= 1
					local_z += chunk_manager.CHUNK_SIZE
				elif local_z >= chunk_manager.CHUNK_SIZE:
					chunk_offset.y += 1
					local_z -= chunk_manager.CHUNK_SIZE
				var check_chunk = center_chunk + chunk_offset
				var pos = _find_clear_spawn_position(check_chunk, local_x, local_z)
				if pos != Vector3.ZERO:
					if _is_tile_truly_clear(pos):
						return pos
	return Vector3.ZERO

func _is_tile_truly_clear(world_pos: Vector3) -> bool:
	var ray_origin := world_pos + Vector3(0, 0.5, 0)
	var ray_end := world_pos + Vector3(0, 5.0, 0)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_bodies = true
	query.collision_mask = 1
	query.exclude = [self]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty()

# ─────────────────────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	# Check if camera is locked (during jumpscare, death, etc.)
	if _camera_locked:
		return  # Ignore all input during camera lock
	
	if not _initial_spawn_complete:
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_rotation_y -= event.relative.x * _mouse_sensitivity_value
			_rotation_x -= event.relative.y * _mouse_sensitivity_value * (-1 if _invert_y else 1)
			_rotation_x = clampf(_rotation_x, -89.0, 89.0)
			rotation_degrees.y = _rotation_y
			camera.rotation_degrees.x = _rotation_x
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if _has_weapon and not _weapon_equipped:
				_equip_weapon()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if _weapon_equipped:
				_unequip_weapon()
				
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotation_y -= event.relative.x * _mouse_sensitivity_value
		var y_multiplier = -1 if _invert_y else 1
		_rotation_x -= event.relative.y * _mouse_sensitivity_value * y_multiplier
		_rotation_x = clampf(_rotation_x, -89.0, 89.0)
		rotation_degrees.y = _rotation_y
		camera.rotation_degrees.x = _rotation_x

func _unhandled_input(event: InputEvent) -> void:
	if not _initial_spawn_complete:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		var star_manager = get_node_or_null("/root/Main/StarManager")
		if star_manager and star_manager.has_method("try_collect_nearby"):
			star_manager.try_collect_nearby()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _weapon_equipped:
				_shoot_weapon()
			else:
				_shoot_ray_reveal()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_shoot_ray_flag()

# ─────────────────────────────────────────────────────────────
# MOVEMENT HELPERS
# ─────────────────────────────────────────────────────────────
func _get_movement_input() -> Vector2:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):   input_dir.y -= 1
	if Input.is_action_pressed("move_backwards"): input_dir.y += 1
	if Input.is_action_pressed("move_left"):      input_dir.x -= 1
	if Input.is_action_pressed("move_right"):     input_dir.x += 1
	return input_dir

func _calculate_movement_direction(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	var camera_basis := camera.global_transform.basis
	var forward := camera_basis.z; forward.y = 0; forward = forward.normalized()
	var right   := camera_basis.x; right.y   = 0; right   = right.normalized()
	return forward * input_dir.y + right * input_dir.x

func _get_current_speed() -> float:
	var current_speed := base_speed
	if Input.is_action_pressed("sprint") and is_on_floor():
		current_speed *= sprint_multiplier
	elif Input.is_action_pressed("crouch"):
		current_speed *= slow_multiplier
		camera.position.y = lerp(camera.position.y, eye_height * 0.65, 0.15)
	else:
		camera.position.y = lerp(camera.position.y, eye_height, 0.15)
	return current_speed

# ─────────────────────────────────────────────────────────────
# RAYCASTING
# ─────────────────────────────────────────────────────────────
func _shoot_ray_reveal() -> void:
	if not _initial_spawn_complete:
		return
	var tile = _get_tile_under_cursor()
	if tile and tile.has_method("start_hold"):
		tile.start_hold()
		tile._finish_hold_reveal()
	elif tile:
		print("[Player] Tile found but no start_hold method")

func _shoot_ray_flag() -> void:
	if not _initial_spawn_complete:
		return
	var tile = _get_tile_under_cursor()
	if tile and tile.has_method("flag"):
		tile.flag()

func _get_tile_under_cursor() -> Node:
	var mouse_pos  := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir    := camera.project_ray_normal(mouse_pos)
	var ray_end    := ray_origin + ray_dir * interact_range
	var query      := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_bodies = true
	query.collide_with_areas  = true
	query.collision_mask      = 1
	query.exclude             = [self]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	var node = result["collider"]
	while node:
		if "grid_manager" in node:
			return node
		node = node.get_parent()
	return null

# ─────────────────────────────────────────────────────────────
# PUBLIC METHODS
# ─────────────────────────────────────────────────────────────
func disable_controls() -> void:
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)

func enable_controls() -> void:
	print("[Player] Controls enabled!")
	set_physics_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_spawn_complete() -> bool:
	return _initial_spawn_complete

func has_weapon() -> bool:
	return _has_weapon

func is_weapon_equipped() -> bool:
	return _weapon_equipped

func get_current_lives() -> int:
	return lives
