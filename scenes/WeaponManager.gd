# WeaponManager.gd
extends Node3D
class_name WeaponManager

# ─────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────

const WEAPON_SPAWN_DELAY : float = 10.0
const WEAPON_RESPAWN_DELAY : float = 180.0
const WEAPON_SAFE_RADIUS : int = 10
const WEAPON_SPAWN_ATTEMPTS : int = 50

# ─────────────────────────────────────────────────────────────
# REFERENCES
# ─────────────────────────────────────────────────────────────

var _chunk_manager : ChunkManager = null
var _player : CharacterBody3D = null
var _weapon_scene : PackedScene = null
var _current_weapon : Deagle = null
var _spawn_timer : float = 0.0
var _weapon_picked_up : bool = false
var _weapon_active : bool = false

# ─────────────────────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────────────────────

signal weapon_spawned(position: Vector3)
signal weapon_picked_up
signal weapon_respawned

# ─────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────

func setup(manager: ChunkManager, player_node: CharacterBody3D, weapon_scene_path: String) -> void:
	_chunk_manager = manager
	_player = player_node
	_weapon_scene = load(weapon_scene_path)
	
	if not _weapon_scene:
		push_error("[WeaponManager] Could not load weapon scene from: ", weapon_scene_path)
		return
	
	_spawn_timer = WEAPON_SPAWN_DELAY
	_weapon_active = false
	
	print("[WeaponManager] Initialized, weapon will spawn in ", WEAPON_SPAWN_DELAY, " seconds")

# ─────────────────────────────────────────────────────────────
# PROCESS
# ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _chunk_manager or not _player:
		return
	
	if _weapon_picked_up:
		return
	
	if _weapon_active and _current_weapon and is_instance_valid(_current_weapon):
		if _weapon_respawn_timer > 0:
			_weapon_respawn_timer -= delta
			if _weapon_respawn_timer <= 0:
				_respawn_weapon()
		return
	
	if not _weapon_active:
		_spawn_timer -= delta
		if _spawn_timer <= 0:
			_spawn_weapon()

var _weapon_respawn_timer : float = 0.0

# ─────────────────────────────────────────────────────────────
# WEAPON SPAWNING
# ─────────────────────────────────────────────────────────────

func _spawn_weapon() -> void:
	if _weapon_picked_up or _weapon_active:
		return
	
	var spawn_pos = _find_weapon_spawn_position()
	if spawn_pos == Vector3.ZERO:
		print("[WeaponManager] No valid spawn location found, retrying in 5 seconds")
		_spawn_timer = 5.0
		return
	
	# 1. Create instance
	_current_weapon = _weapon_scene.instantiate()

	# 2. Set properties BEFORE adding to tree (preferred)
	_current_weapon.position = spawn_pos
	_current_weapon.set_chunk_manager(_chunk_manager)
	_current_weapon.weapon_picked_up.connect(_on_weapon_picked_up)
	
	# 3. Add to scene tree ONCE
	add_child(_current_weapon) 
	
	_weapon_active = true
	_weapon_respawn_timer = WEAPON_RESPAWN_DELAY
	
	print("[WeaponManager] Weapon spawned at ", spawn_pos)
	weapon_spawned.emit(spawn_pos)

func _respawn_weapon() -> void:
	if _weapon_picked_up:
		return
	
	if _current_weapon and is_instance_valid(_current_weapon):
		_current_weapon.queue_free()
	
	_weapon_active = false
	_spawn_timer = 0.0
	_spawn_weapon()
	weapon_respawned.emit()
	print("[WeaponManager] Weapon respawned at new location")

func _find_weapon_spawn_position() -> Vector3:
	if not _chunk_manager or not _player:
		return Vector3.ZERO
	
	var player_pos = _player.global_position
	var player_tile = Vector2i(floori(player_pos.x), floori(player_pos.z))
	
	var candidates : Array[Vector2i] = []
	var search_radius = 25
	
	for wx in range(player_tile.x - search_radius, player_tile.x + search_radius + 1):
		for wz in range(player_tile.y - search_radius, player_tile.y + search_radius + 1):
			var dist = Vector2(wx - player_tile.x, wz - player_tile.y).length()
			if dist < WEAPON_SAFE_RADIUS:
				continue
			
			var cell = _chunk_manager.get_map_cell(wx, wz)
			if cell["state"] == "revealed" and cell["number"] == 0:
				candidates.append(Vector2i(wx, wz))
	
	if candidates.is_empty():
		print("[WeaponManager] No valid tiles found for weapon spawn")
		return Vector3.ZERO
	
	var selected = candidates[randi() % candidates.size()]
	return Vector3(selected.x + 0.5, 0.1, selected.y + 0.5)

# ─────────────────────────────────────────────────────────────
# SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────

func _on_weapon_picked_up() -> void:
	_weapon_picked_up = true
	_weapon_active = false
	weapon_picked_up.emit()
	print("[WeaponManager] Weapon picked up by player!")

# ─────────────────────────────────────────────────────────────
# PUBLIC METHODS
# ─────────────────────────────────────────────────────────────

func has_weapon() -> bool:
	return _weapon_picked_up

func reset_weapon() -> void:
	_weapon_picked_up = false
	_weapon_active = false
	_spawn_timer = WEAPON_SPAWN_DELAY
	_weapon_respawn_timer = 0.0
	
	if _current_weapon and is_instance_valid(_current_weapon):
		_current_weapon.queue_free()
		_current_weapon = null
