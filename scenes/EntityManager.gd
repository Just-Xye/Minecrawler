class_name EntityManager
extends Node3D

# ─────────────────────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────────────────────

signal enemy_defeated
signal jumpscare_finished

# ─────────────────────────────────────────────────────────────
# TUNABLES
# ─────────────────────────────────────────────────────────────

const COLLISION_HEIGHT      : float = 1.8
const COLLISION_RADIUS      : float = 1.2
const SAFE_RADIUS           : int   = 15
const SPAWN_DELAY_MIN       : float = 10.0
const SPAWN_DELAY_MAX       : float = 15.0
const SPEED_SLOW            : float = 3.5
const SPEED_FAST            : float = 6.2
const SPEED_PLAYER_REF      : float = 5.5
const LOS_REACT_MIN         : float = 0.5
const LOS_REACT_MAX         : float = 2.0
const DESPAWN_TIMEOUT       : float = 300.0
const RESPAWN_AFTER_DESPAWN : float = 5.0
const WANDER_RETARGET_TIME  : float = 2.5
const STEP_INTERVAL         : float = 0.15
const LOS_MAX_DIST          : float = 18.0
const ENTITY_HEIGHT         : float = 0.5
const ROTATION_SPEED        : float = 5.0
const RANDOM_PATH_BIAS      : float = 0.6
const STUCK_THRESHOLD       : float = 0.5
const MIN_PATH_DISTANCE     : float = 0.5
const MIN_GAP_SIZE          : float = 1.5

# 3-minute initial lock before the sweeper can ever spawn
const FIRST_SPAWN_LOCK      : float = 180.0

# Pathfinding cooldowns (performance optimization)
const BFS_COOLDOWN_WANDER     : float = 1.0   # Recalc path every 1s when wandering
const BFS_COOLDOWN_CHASE      : float = 0.3   # Recalc path every 0.3s when chasing
const BFS_COOLDOWN_LAST_KNOWN : float = 0.5   # Recalc path every 0.5s when tracking
const MAX_CACHE_SIZE          : int   = 500   # Max cache entries before clearing

# Sound constants
const SOUND_MAX_DISTANCE    : float = 50.0
const SOUND_MIN_DISTANCE    : float = 10.0
const SOUND_UPDATE_INTERVAL : float = 0.1
const SIGHT_SOUND_COOLDOWN  : float = 5.0
const JUMPSCARE_VOLUME_DB   : float = -6.0
const SPAWN_SOUND_VOLUME_DB : float = -18.0

# BFS limits
const BFS_MAX_STEPS         : int = 300  # Reduced from 500 for performance

# ─────────────────────────────────────────────────────────────
# STATE MACHINE
# ─────────────────────────────────────────────────────────────

enum State {
	WAITING_FOR_WORLD,
	WAITING_FOR_ACTIVE,
	SPAWN_DELAY,
	ALIVE,
	DESPAWNED,
	JUMPSCARE,
	JUMPSCARE_DESPAWN,
}

enum MoveMode { WANDER, CHASE_LOS, LAST_KNOWN }

# ─────────────────────────────────────────────────────────────
# REFERENCES
# ─────────────────────────────────────────────────────────────

var chunk_manager : ChunkManager    = null
var player        : CharacterBody3D = null

# ─────────────────────────────────────────────────────────────
# INTERNAL STATE
# ─────────────────────────────────────────────────────────────

var _state          : State    = State.WAITING_FOR_WORLD
var _move_mode      : MoveMode = MoveMode.WANDER
var _collision_body : CharacterBody3D = null

# Timers
var _spawn_timer     : float = 0.0
var _despawn_timer   : float = 0.0
var _respawn_timer   : float = 0.0
var _wander_timer    : float = 0.0
var _step_timer      : float = 0.0
var _los_react_timer : float = 0.0
var _bfs_cooldown    : float = 0.0  # Performance: throttle BFS calls

var _skip_active_wait : bool = false

# 3-minute lock
var _first_input_received     : bool  = false
var _first_spawn_lock_timer   : float = 0.0

# Entity
var _entity_node : Node3D  = null
var _entity_pos  : Vector3 = Vector3.ZERO

# Movement
var _current_speed : float = SPEED_SLOW
var _target_speed  : float = SPEED_SLOW
var _los_reacting  : bool  = false

# Pathfinding
var _last_known_player    : Vector3 = Vector3.ZERO
var _wander_target        : Vector3 = Vector3.ZERO
var _path                 : Array[Vector3] = []
var _current_target_index : int = 0

# Player tracking
var _player_was_active : bool  = false
var _prev_player_pos   : Vector3 = Vector3.ZERO
var _prev_player_basis : Basis   = Basis.IDENTITY

# Rotation
var _target_rotation  : float = 0.0
var _current_rotation : float = 0.0

# Animation
var _animation_player : AnimationPlayer = null
var _current_anim     : String = ""

# Stuck detection
var _last_position      : Vector3 = Vector3.ZERO
var _stuck_timer        : float   = 0.0
var _path_refresh_count : int     = 0

# ─────────────────────────────────────────────────────────────
# CACHING (Performance optimization)
# ─────────────────────────────────────────────────────────────

var _walkable_cache : Dictionary = {}  # Cache walkability results
var _width_cache    : Dictionary = {}  # Cache tile width results
var _cache_frame    : int = 0          # Frame number for cache invalidation

# ─────────────────────────────────────────────────────────────
# AUDIO
# ─────────────────────────────────────────────────────────────

var _audio_stream_player    : AudioStreamPlayer3D = null
var _sight_sound_player     : AudioStreamPlayer3D = null
var _spawn_sound_player     : AudioStreamPlayer3D = null
var _sound_update_timer     : float = 0.0
var _is_sound_playing       : bool  = false
var _last_sight_sound_time  : float = 0.0

# Jumpscare
var _jumpscare_player       : AudioStreamPlayer = null
var _jumpscare_timer        : float = 0.0

# ─────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────

func set_targets(cm: ChunkManager, p: CharacterBody3D) -> void:
	chunk_manager = cm
	player        = p
	if chunk_manager:
		chunk_manager.spawn_chunks_ready.connect(_on_world_ready, CONNECT_ONE_SHOT)
		chunk_manager.chunk_load_completed.connect(_on_chunk_loaded)

func _on_chunk_loaded(_chunk_pos: Vector2i) -> void:
	_invalidate_cache()

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Tick the first-spawn lock
	if _first_input_received and _first_spawn_lock_timer < FIRST_SPAWN_LOCK:
		_first_spawn_lock_timer += delta

	match _state:
		State.WAITING_FOR_WORLD:
			pass

		State.WAITING_FOR_ACTIVE:
			if _spawn_timer < 0:
				return
			if _is_player_active():
				if not _first_input_received:
					_first_input_received = true
					print("[EntityManager] First player input — 3-minute spawn lock started.")

				if _skip_active_wait:
					_begin_spawn_delay()
					_skip_active_wait = false
				else:
					_player_was_active = true
					_begin_spawn_delay()

		State.SPAWN_DELAY:
			if _spawn_timer < 0:
				return
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				if _first_spawn_lock_timer < FIRST_SPAWN_LOCK:
					_spawn_timer = 5.0
					return
				_try_spawn()

		State.ALIVE:
			_update_alive(delta)
			if player and is_instance_valid(_entity_node):
				_rotate_towards_player(delta)
				_update_animation(delta)
			_update_sound(delta)

		State.JUMPSCARE:
			_tick_jumpscare(delta)

		State.DESPAWNED:
			if _respawn_timer < 0:
				return
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				_state = State.WAITING_FOR_ACTIVE
				_skip_active_wait = true

# ─────────────────────────────────────────────────────────────
# CACHE MANAGEMENT
# ─────────────────────────────────────────────────────────────

func _invalidate_cache() -> void:
	"""Clear caches when chunks change"""
	_walkable_cache.clear()
	_width_cache.clear()
	_cache_frame = Engine.get_process_frames()

func _is_tile_wide_enough_cached(wx: int, wz: int) -> bool:
	"""Cached version of width check - 3x3 cell lookup"""
	var cache_key := "%d,%d" % [wx, wz]
	
	if _width_cache.has(cache_key):
		return _width_cache[cache_key]
	
	if not chunk_manager:
		return false
	
	# Check 3x3 area around tile
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var check_x := wx + dx
			var check_z := wz + dz
			var cell := chunk_manager.get_map_cell(check_x, check_z)
			if cell["state"] == "hidden" or cell["state"] == "mine":
				_width_cache[cache_key] = false
				return false
	
	_width_cache[cache_key] = true
	return true

func _is_tile_walkable_cached(wx: int, wz: int) -> bool:
	"""Cached version of walkability check"""
	var cache_key := "%d,%d" % [wx, wz]
	
	# Periodic cache cleanup
	if _cache_frame != Engine.get_process_frames():
		_cache_frame = Engine.get_process_frames()
		if _walkable_cache.size() > MAX_CACHE_SIZE:
			_walkable_cache.clear()
			_width_cache.clear()
	
	if _walkable_cache.has(cache_key):
		return _walkable_cache[cache_key]
	
	if not chunk_manager:
		return false
	
	var chunk_pos := Vector2i(
		floori(float(wx) / chunk_manager.CHUNK_SIZE),
		floori(float(wz) / chunk_manager.CHUNK_SIZE)
	)
	if not chunk_manager.chunks.has(chunk_pos):
		return false
	
	var cell := chunk_manager.get_map_cell(wx, wz)
	if cell["state"] == "revealed" and not _is_tile_wide_enough_cached(wx, wz):
		_walkable_cache[cache_key] = false
		return false
	
	var result = cell["state"] == "revealed"
	_walkable_cache[cache_key] = result
	return result

func _is_diagonal_passable_cached(fx: int, fz: int, tx: int, tz: int) -> bool:
	var dx := tx - fx
	var dz := tz - fz
	if dx == 0 or dz == 0:
		return true
	return _is_tile_walkable_cached(fx + dx, fz) and _is_tile_walkable_cached(fx, fz + dz)

# ─────────────────────────────────────────────────────────────
# DEBUG SKIP
# ─────────────────────────────────────────────────────────────

func skip_first_spawn_lock() -> void:
	_first_spawn_lock_timer = FIRST_SPAWN_LOCK
	_first_input_received   = true
	print("[EntityManager] DEBUG: First-spawn lock skipped.")

# ─────────────────────────────────────────────────────────────
# SOUND SYSTEM
# ─────────────────────────────────────────────────────────────

func _setup_sound() -> void:
	if not _entity_node:
		return

	_audio_stream_player = AudioStreamPlayer3D.new()
	_audio_stream_player.name = "EntitySound"
	var sound_stream = load("res://Sounds/Sweeper/sample_sound.ogg")
	if sound_stream:
		_audio_stream_player.stream = sound_stream
	else:
		push_error("[EntityManager] Could not load sample_sound.ogg")
		return
	_audio_stream_player.max_distance = SOUND_MAX_DISTANCE
	_audio_stream_player.max_db       = 0.0
	_audio_stream_player.unit_size    = 1.0
	_audio_stream_player.autoplay     = false
	_audio_stream_player.finished.connect(_on_sound_finished)
	_entity_node.add_child(_audio_stream_player)
	_is_sound_playing = true

	_sight_sound_player = AudioStreamPlayer3D.new()
	_sight_sound_player.name = "SightSound"
	_sight_sound_player.max_distance = SOUND_MAX_DISTANCE
	_sight_sound_player.max_db       = 0.0
	_sight_sound_player.unit_size    = 1.0
	_sight_sound_player.autoplay     = false
	_entity_node.add_child(_sight_sound_player)

	_spawn_sound_player = AudioStreamPlayer3D.new()
	_spawn_sound_player.name         = "SpawnSound"
	_spawn_sound_player.max_distance = 200.0
	_spawn_sound_player.unit_size    = 0.3
	_spawn_sound_player.volume_db    = SPAWN_SOUND_VOLUME_DB
	_spawn_sound_player.autoplay     = false
	var spawn_stream = load("res://Sounds/Sweeper/spawn.wav")
	if spawn_stream:
		_spawn_sound_player.stream = spawn_stream
	_entity_node.add_child(_spawn_sound_player)

	call_deferred("_play_sound_deferred")

func _play_sound_deferred() -> void:
	if _audio_stream_player and is_instance_valid(_audio_stream_player) and _is_sound_playing:
		_audio_stream_player.play()
	if _spawn_sound_player and is_instance_valid(_spawn_sound_player):
		_spawn_sound_player.play()
		print("[EntityManager] Spawn sound playing (very distant).")

func _on_sound_finished() -> void:
	if _audio_stream_player and is_instance_valid(_audio_stream_player) and _is_sound_playing:
		_audio_stream_player.play()

func _load_sight_sound() -> void:
	if not _sight_sound_player:
		return
	var sight_stream = load("res://Sounds/Sweeper/seen.wav")
	if sight_stream:
		_sight_sound_player.stream = sight_stream
	else:
		_sight_sound_player.stream = _audio_stream_player.stream if _audio_stream_player else null

func _update_sound(delta: float) -> void:
	if not _audio_stream_player or not player:
		return
	_sound_update_timer += delta
	if _sound_update_timer >= SOUND_UPDATE_INTERVAL:
		_sound_update_timer = 0.0
		if _audio_stream_player:
			var speed_factor = clamp(_current_speed / SPEED_FAST, 0.8, 1.5)
			_audio_stream_player.pitch_scale = lerp(_audio_stream_player.pitch_scale, speed_factor, 0.1)

func _stop_sound() -> void:
	if _audio_stream_player and _is_sound_playing:
		_audio_stream_player.stop()
		_is_sound_playing = false
		if _audio_stream_player.finished.is_connected(_on_sound_finished):
			_audio_stream_player.finished.disconnect(_on_sound_finished)
	if _sight_sound_player:
		_sight_sound_player.stop()
	if _spawn_sound_player:
		_spawn_sound_player.stop()

# ─────────────────────────────────────────────────────────────
# JUMPSCARE
# ─────────────────────────────────────────────────────────────

func trigger_jumpscare() -> void:
	if _state == State.JUMPSCARE or _state == State.JUMPSCARE_DESPAWN:
		return

	_state = State.JUMPSCARE
	_stop_sound()
	_despawn_timer = -999.0

	if is_instance_valid(_entity_node):
		_entity_node.global_position = _entity_pos

	if player and is_instance_valid(_entity_node):
		_face_player_toward_entity()

	_jumpscare_player = AudioStreamPlayer.new()
	_jumpscare_player.name      = "JumpscareSound"
	_jumpscare_player.volume_db = JUMPSCARE_VOLUME_DB
	var js_stream = load("res://Sounds/Sweeper/jumpscare.wav")
	if js_stream:
		_jumpscare_player.stream = js_stream
	add_child(_jumpscare_player)
	_jumpscare_player.play()
	_jumpscare_player.finished.connect(_on_jumpscare_finished)

	if js_stream:
		_jumpscare_timer = js_stream.get_length() + 0.5
	else:
		_jumpscare_timer = 3.0
	print("[EntityManager] Jumpscare triggered!")

func _face_player_toward_entity() -> void:
	if not player or not is_instance_valid(_entity_node):
		return

	var dir : Vector3 = (_entity_pos - player.global_position)
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return

	var target_y := atan2(dir.x, dir.z)

	if player.has_method("get") and "_rotation_y" in player:
		player._rotation_y = rad_to_deg(target_y)
		player.rotation_degrees.y = player._rotation_y
		if "_rotation_x" in player:
			player._rotation_x = 0.0
		var cam : Camera3D = player.get_node_or_null("Camera3D")
		if cam:
			cam.rotation_degrees.x = 0.0

func _tick_jumpscare(delta: float) -> void:
	if is_instance_valid(_entity_node) and player:
		var dir : Vector3 = (player.global_position - _entity_pos)
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			var angle := atan2(dir.x, dir.z)
			_current_rotation = lerp_angle(_current_rotation, angle, 20.0 * delta)
			_entity_node.rotation.y = _current_rotation

	_jumpscare_timer -= delta
	if _jumpscare_timer <= 0.0:
		_on_jumpscare_finished()

func _on_jumpscare_finished() -> void:
	if is_instance_valid(_jumpscare_player):
		if _jumpscare_player.finished.is_connected(_on_jumpscare_finished):
			_jumpscare_player.finished.disconnect(_on_jumpscare_finished)
		_jumpscare_player.queue_free()
		_jumpscare_player = null

	_jumpscare_timer = -999.0
	_state = State.JUMPSCARE_DESPAWN

	if is_instance_valid(_entity_node):
		_entity_node.queue_free()
		_entity_node = null

	emit_signal("jumpscare_finished")
	print("[EntityManager] Jumpscare finished — signalling game over.")
	
	_state = State.WAITING_FOR_ACTIVE
	_skip_active_wait = true
	_respawn_timer = 0.0

# ─────────────────────────────────────────────────────────────
# ANIMATION
# ─────────────────────────────────────────────────────────────

func _setup_animation() -> void:
	if not _entity_node:
		return
	_animation_player = _entity_node.find_child("AnimationPlayer", true, false)
	if _animation_player:
		_play_animation("idle")

func _play_animation(anim_name: String, speed: float = 1.0) -> void:
	if not _animation_player:
		return
	if _current_anim == anim_name:
		return
	if _animation_player.has_animation(anim_name):
		_current_anim = anim_name
		_animation_player.play(anim_name, -1, speed)
	else:
		var alt_names = {
			"idle": ["idle", "Idle", "IDLE", "standing", "Standing"],
			"walk": ["walk", "Walk", "WALK", "walking", "Walking", "run", "Run"]
		}
		for alt in alt_names.get(anim_name, []):
			if _animation_player.has_animation(alt):
				_current_anim = alt
				_animation_player.play(alt, -1, speed)
				return

func _update_animation(delta: float) -> void:
	if not _animation_player:
		return
	var is_moving = _current_speed > 0.5 and not _path.is_empty()
	if is_moving:
		var anim_speed = (_current_speed / SPEED_SLOW) * 1.5
		anim_speed = clamp(anim_speed, 0.5, 2.0)
		_play_animation("walk", anim_speed)
	else:
		_play_animation("idle")

# ─────────────────────────────────────────────────────────────
# ROTATION
# ─────────────────────────────────────────────────────────────

func _rotate_towards_player(delta: float) -> void:
	if not player or not _entity_node:
		return
	var direction  = (player.global_position - _entity_pos).normalized()
	var target_angle = atan2(direction.x, direction.z)
	_current_rotation = lerp_angle(_current_rotation, target_angle, ROTATION_SPEED * delta)
	_entity_node.rotation.y = _current_rotation

# ─────────────────────────────────────────────────────────────
# SIGNAL HANDLER
# ─────────────────────────────────────────────────────────────

func _on_world_ready() -> void:
	_state = State.WAITING_FOR_ACTIVE

# ─────────────────────────────────────────────────────────────
# PLAYER ACTIVITY DETECTION
# ─────────────────────────────────────────────────────────────

func _is_player_active() -> bool:
	if not player:
		return false
	var moved   : bool = player.global_position.distance_to(_prev_player_pos) > 0.05
	var rotated : bool = not player.global_transform.basis.is_equal_approx(_prev_player_basis)
	_prev_player_pos   = player.global_position
	_prev_player_basis = player.global_transform.basis
	return moved or rotated

# ─────────────────────────────────────────────────────────────
# SPAWN DELAY
# ─────────────────────────────────────────────────────────────

func _begin_spawn_delay() -> void:
	_spawn_timer = randf_range(SPAWN_DELAY_MIN, SPAWN_DELAY_MAX)
	_state       = State.SPAWN_DELAY

# ─────────────────────────────────────────────────────────────
# SPAWN ATTEMPT
# ─────────────────────────────────────────────────────────────

func _try_spawn() -> void:
	if not chunk_manager or not player:
		return

	var spawn_tile : Vector2i = _find_spawn_tile()
	if spawn_tile == Vector2i(-9999, -9999):
		_spawn_timer = 3.0
		return

	var world_x : float = spawn_tile.x + 0.5
	var world_z : float = spawn_tile.y + 0.5

	if is_instance_valid(_entity_node):
		_entity_node.queue_free()
		_entity_node = null

	_entity_pos  = Vector3(world_x, ENTITY_HEIGHT, world_z)
	_entity_node = _build_entity_visual()
	add_child(_entity_node)
	_entity_node.global_position = _entity_pos

	_current_rotation = 0.0
	_entity_node.rotation.y = 0.0

	_setup_animation()
	_setup_sound()

	_current_speed        = SPEED_SLOW
	_target_speed         = SPEED_SLOW
	_despawn_timer        = DESPAWN_TIMEOUT
	_wander_timer         = 0.0
	_los_react_timer      = 0.0
	_los_reacting         = false
	_last_known_player    = _get_tile_center(player.global_position)
	_move_mode            = MoveMode.WANDER
	_path.clear()
	_current_target_index = 0
	_last_position        = _entity_pos
	_stuck_timer          = 0.0
	_path_refresh_count   = 0
	_sound_update_timer   = 0.0
	_bfs_cooldown         = 0.0
	_invalidate_cache()

	_state = State.ALIVE
	print("[EntityManager] Entity spawned at ", _entity_pos)

func _get_tile_center(pos: Vector3) -> Vector3:
	return Vector3(floori(pos.x) + 0.5, pos.y, floori(pos.z) + 0.5)

func _find_spawn_tile() -> Vector2i:
	if not chunk_manager or not player:
		return Vector2i(-9999, -9999)

	var pp : Vector3 = player.global_position
	var px : int     = floori(pp.x)
	var pz : int     = floori(pp.z)
	var cs : int     = chunk_manager.CHUNK_SIZE
	var rr : int     = chunk_manager.RENDER_RADIUS * cs

	var candidates : Array[Vector2i] = []
	
	for wx in range(px - rr, px + rr + 1):
		for wz in range(pz - rr, pz + rr + 1):
			var dist : float = Vector2(wx - px, wz - pz).length()
			if dist < SAFE_RADIUS:
				continue
			var cell : Dictionary = chunk_manager.get_map_cell(wx, wz)
			if cell["state"] == "revealed":
				var has_space := true
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						var check_cell := chunk_manager.get_map_cell(wx + dx, wz + dz)
						if check_cell["state"] == "hidden" or check_cell["state"] == "mine":
							has_space = false
							break
					if not has_space:
						break
				if has_space and _is_tile_wide_enough_cached(wx, wz):
					candidates.append(Vector2i(wx, wz))

	if candidates.is_empty():
		return Vector2i(-9999, -9999)

	candidates.sort_custom(func(a, b):
		var da := Vector2(a.x - px, a.y - pz).length_squared()
		var db := Vector2(b.x - px, b.y - pz).length_squared()
		return da > db)

	var pool_size : int = maxi(1, candidates.size() / 4)
	return candidates[randi() % pool_size]

# ─────────────────────────────────────────────────────────────
# ALIVE UPDATE
# ─────────────────────────────────────────────────────────────

func _update_alive(delta: float) -> void:
	if not is_instance_valid(_entity_node):
		_state = State.WAITING_FOR_ACTIVE
		return

	# DESPAWN TIMER - ONLY DECREMENTED ONCE
	_despawn_timer -= delta
	if _despawn_timer <= 0.0:
		_do_despawn()
		return

	var player_pos : Vector3 = _get_tile_center(player.global_position if player else Vector3.ZERO)
	var has_los    : bool    = _check_line_of_sight(player_pos)

	if has_los:
		_last_known_player = player_pos
		_despawn_timer     = DESPAWN_TIMEOUT

		if _move_mode != MoveMode.CHASE_LOS:
			_play_sight_sound()
			_move_mode       = MoveMode.CHASE_LOS
			_los_react_timer = randf_range(LOS_REACT_MIN, LOS_REACT_MAX)
			_los_reacting    = true
			_current_speed   = SPEED_SLOW
			_path.clear()
			_current_target_index = 0
			_path_refresh_count   = 0

		if _los_reacting:
			_los_react_timer -= delta
			if _los_react_timer <= 0.0:
				_los_reacting = false
				_target_speed = SPEED_FAST
	else:
		if _move_mode == MoveMode.CHASE_LOS:
			_move_mode    = MoveMode.LAST_KNOWN
			_target_speed = SPEED_SLOW
			_path.clear()
			_current_target_index = 0
		elif _move_mode == MoveMode.LAST_KNOWN:
			var dist_to_last_known = _entity_pos.distance_to(_last_known_player)
			if dist_to_last_known < MIN_PATH_DISTANCE:
				_move_mode    = MoveMode.WANDER
				_target_speed = SPEED_SLOW
				_path.clear()
				_current_target_index = 0

	_current_speed = lerpf(_current_speed, _target_speed, delta * 3.0)

	# Stuck detection
	var movement := (_entity_pos - _last_position).length()
	if movement < 0.05:
		_stuck_timer += delta
		if _stuck_timer > STUCK_THRESHOLD:
			_stuck_timer = 0.0
			_path_refresh_count += 1
			_path.clear()
			_current_target_index = 0
			print("[EntityManager] Stuck detected, forcing repath #", _path_refresh_count)
			if _path_refresh_count >= 100:
				print("[EntityManager] Repath limit reached — despawning")
				_do_despawn()
				_state = State.WAITING_FOR_ACTIVE
				_skip_active_wait = true
				_respawn_timer    = 0.0
				_path_refresh_count = 0
				return
	else:
		_stuck_timer    = 0.0
		_last_position  = _entity_pos

	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = STEP_INTERVAL
		_advance_path(player_pos)

	_move_entity(delta)
	_entity_node.global_position = _entity_pos

# ─────────────────────────────────────────────────────────────
# LINE OF SIGHT
# ─────────────────────────────────────────────────────────────

func _play_sight_sound() -> void:
	if not _sight_sound_player:
		return
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_sight_sound_time < SIGHT_SOUND_COOLDOWN:
		return
	_last_sight_sound_time = current_time
	if not _sight_sound_player.stream:
		_load_sight_sound()
	_sight_sound_player.play()
	print("[EntityManager] 👁️ Enemy spotted player!")

func _check_line_of_sight(target: Vector3) -> bool:
	if not chunk_manager or not player:
		return false
	var dist : float = _entity_pos.distance_to(target)
	if dist > LOS_MAX_DIST:
		return false
	var steps : int    = int(dist) + 1
	var dir   : Vector3 = (target - _entity_pos).normalized()
	for i in range(1, steps):
		var sample : Vector3 = _entity_pos + dir * float(i)
		var wx     : int     = floori(sample.x)
		var wz     : int     = floori(sample.z)
		var chunk_pos = Vector2i(floori(float(wx) / chunk_manager.CHUNK_SIZE), floori(float(wz) / chunk_manager.CHUNK_SIZE))
		if not chunk_manager.chunks.has(chunk_pos):
			return false
		var cell : Dictionary = chunk_manager.get_map_cell(wx, wz)
		if cell["state"] == "hidden":
			return false
	return true

# ─────────────────────────────────────────────────────────────
# PATHFINDING (Optimized)
# ─────────────────────────────────────────────────────────────

func _advance_path(player_pos: Vector3) -> void:
	# Throttle BFS calls based on movement mode
	if _bfs_cooldown > 0:
		_bfs_cooldown -= STEP_INTERVAL
		return
	
	var target_pos : Vector3
	var bfs_delay : float = BFS_COOLDOWN_WANDER
	
	match _move_mode:
		MoveMode.CHASE_LOS:
			target_pos = player_pos
			bfs_delay = BFS_COOLDOWN_CHASE
		MoveMode.LAST_KNOWN:
			target_pos = _last_known_player
			bfs_delay = BFS_COOLDOWN_LAST_KNOWN
		MoveMode.WANDER:
			_wander_timer -= STEP_INTERVAL
			if _wander_timer <= 0.0 or _path.is_empty():
				_wander_timer = WANDER_RETARGET_TIME
				target_pos    = _random_wander_target()
				bfs_delay = BFS_COOLDOWN_WANDER
			else:
				return

	target_pos = _get_tile_center(target_pos)
	var current_tile = Vector2i(floori(_entity_pos.x), floori(_entity_pos.z))
	var target_tile  = Vector2i(floori(target_pos.x),  floori(target_pos.z))

	# Only recalculate if target changed significantly
	if _path.is_empty() or _current_target_index >= _path.size() or current_tile.distance_squared_to(target_tile) > 4:
		_bfs_cooldown = bfs_delay  # Set cooldown before expensive BFS
		
		if _move_mode == MoveMode.CHASE_LOS and randf() < RANDOM_PATH_BIAS:
			_path = _bfs_path_randomized(_entity_pos, target_pos)
		else:
			_path = _bfs_path(_entity_pos, target_pos, _move_mode == MoveMode.WANDER)
		_current_target_index = 0
		for i in range(_path.size()):
			_path[i] = _get_tile_center(_path[i])

func _random_wander_target() -> Vector3:
	if not chunk_manager:
		return _entity_pos
	var angle : float = randf() * TAU
	var dist  : float = randf_range(4.0, 10.0)
	var tx    : float = _entity_pos.x + cos(angle) * dist
	var tz    : float = _entity_pos.z + sin(angle) * dist
	return _get_tile_center(Vector3(tx, _entity_pos.y, tz))

func _bfs_path_randomized(from: Vector3, to: Vector3) -> Array[Vector3]:
	if not chunk_manager:
		return []
	var start : Vector2i = Vector2i(floori(from.x), floori(from.z))
	var goal  : Vector2i = Vector2i(floori(to.x),   floori(to.z))
	if start == goal:
		return []
	
	var visited : Dictionary = {}
	var parent  : Dictionary = {}
	var queue   : Array[Vector2i] = [start]
	visited[start] = true
	
	var dirs : Array[Vector2i] = [
		Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
		Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1),
	]
	var found : bool = false
	
	while not queue.is_empty() and visited.size() < BFS_MAX_STEPS:
		var cur : Vector2i = queue.pop_front()
		if cur == goal:
			found = true
			break
		var neighbours := dirs.duplicate()
		neighbours.shuffle()
		for d in neighbours:
			var nb : Vector2i = cur + d
			if visited.has(nb):
				continue
			if not _is_tile_walkable_cached(nb.x, nb.y):
				continue
			if not _is_diagonal_passable_cached(cur.x, cur.y, nb.x, nb.y):
				continue
			visited[nb] = true
			parent[nb]  = cur
			queue.append(nb)
	
	if not found:
		return []
	
	var path_tiles : Array[Vector2i] = []
	var step       : Vector2i        = goal
	while parent.has(step):
		path_tiles.push_front(step)
		step = parent[step]
	
	var path_world : Array[Vector3] = []
	for t in path_tiles:
		path_world.append(Vector3(t.x + 0.5, _entity_pos.y, t.y + 0.5))
	return path_world

func _bfs_path(from: Vector3, to: Vector3, shuffle_neighbours: bool) -> Array[Vector3]:
	if not chunk_manager:
		return []
	var start : Vector2i = Vector2i(floori(from.x), floori(from.z))
	var goal  : Vector2i = Vector2i(floori(to.x),   floori(to.z))
	if start == goal:
		return []
	
	var visited : Dictionary = {}
	var parent  : Dictionary = {}
	var queue   : Array[Vector2i] = [start]
	visited[start] = true
	
	var dirs : Array[Vector2i] = [
		Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
		Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1),
	]
	var found : bool = false
	
	while not queue.is_empty() and visited.size() < BFS_MAX_STEPS:
		var cur : Vector2i = queue.pop_front()
		if cur == goal:
			found = true
			break
		var neighbours := dirs.duplicate()
		if shuffle_neighbours:
			neighbours.shuffle()
		for d in neighbours:
			var nb : Vector2i = cur + d
			if visited.has(nb):
				continue
			if not _is_tile_walkable_cached(nb.x, nb.y):
				continue
			if not _is_diagonal_passable_cached(cur.x, cur.y, nb.x, nb.y):
				continue
			visited[nb] = true
			parent[nb]  = cur
			queue.append(nb)
	
	if not found:
		return []
	
	var path_tiles : Array[Vector2i] = []
	var step       : Vector2i        = goal
	while parent.has(step):
		path_tiles.push_front(step)
		step = parent[step]
	
	var path_world : Array[Vector3] = []
	for t in path_tiles:
		path_world.append(Vector3(t.x + 0.5, _entity_pos.y, t.y + 0.5))
	return path_world

# ─────────────────────────────────────────────────────────────
# MOVEMENT
# ─────────────────────────────────────────────────────────────

func _move_entity(delta: float) -> void:
	if _path.is_empty():
		return
	if _current_target_index >= _path.size():
		_path.clear()
		_current_target_index = 0
		return
	
	var target   : Vector3 = _path[_current_target_index]
	var diff     : Vector3 = target - _entity_pos
	diff.y = 0.0
	var dist     : float   = diff.length()
	
	if dist < MIN_PATH_DISTANCE:
		_entity_pos = target
		_current_target_index += 1
		return
	
	var target_tile := Vector2i(floori(target.x), floori(target.z))
	if not _is_tile_walkable_cached(target_tile.x, target_tile.y):
		_path.clear()
		_current_target_index = 0
		return
	
	var move_dist : float = _current_speed * delta
	var move_dir          = diff.normalized()
	
	if move_dist >= dist:
		_entity_pos = target
		_current_target_index += 1
	else:
		_entity_pos += move_dir * move_dist
	
	_entity_pos.y = ENTITY_HEIGHT
	
	if _entity_node is CharacterBody3D:
		var velocity_vec      = move_dir * _current_speed
		velocity_vec.y        = 0
		_entity_node.velocity = velocity_vec
		_entity_node.move_and_slide()
	else:
		_entity_node.global_position = _entity_pos

# ─────────────────────────────────────────────────────────────
# DESPAWN
# ─────────────────────────────────────────────────────────────

func _do_despawn() -> void:
	print("[EntityManager] Entity despawning")
	_stop_sound()
	if is_instance_valid(_entity_node):
		_entity_node.queue_free()
		_entity_node = null
	_state         = State.DESPAWNED
	_respawn_timer = RESPAWN_AFTER_DESPAWN
	_path.clear()
	_current_target_index = 0
	_path_refresh_count   = 0
	_stuck_timer          = 0.0
	_invalidate_cache()

# ─────────────────────────────────────────────────────────────
# ENTITY VISUAL BUILDER
# ─────────────────────────────────────────────────────────────

func _build_entity_visual() -> Node3D:
	var scene    = preload("res://Enemy/Sweeper/Sweeper.tscn")
	var instance = scene.instantiate()
	if not instance.find_child("CollisionShape3D", true, false):
		_setup_collision(instance)
	if not instance.find_child("AnimationPlayer", true, false):
		_setup_animation_fallback(instance)
	return instance

func _setup_collision(entity: Node3D) -> void:
	var body     = CharacterBody3D.new()
	body.name    = "CollisionBody"
	var children = entity.get_children()
	for child in children:
		entity.remove_child(child)
		body.add_child(child)
	var collision_shape  = CollisionShape3D.new()
	var cylinder_shape   = CylinderShape3D.new()
	cylinder_shape.height = COLLISION_HEIGHT
	cylinder_shape.radius = COLLISION_RADIUS
	collision_shape.shape = cylinder_shape
	body.add_child(collision_shape)
	body.collision_layer = 2
	body.collision_mask  = 1
	entity.add_child(body)
	_collision_body = body

func _setup_animation_fallback(entity: Node3D) -> void:
	var anim_player      = AnimationPlayer.new()
	anim_player.name     = "AnimationPlayer"
	entity.add_child(anim_player)
	var idle_anim        = Animation.new()
	idle_anim.length     = 1.0
	idle_anim.loop_mode  = Animation.LOOP_LINEAR
	var track_idx        = idle_anim.add_track(Animation.TYPE_VALUE)
	idle_anim.track_set_path(track_idx, NodePath(":rotation:y"))
	idle_anim.track_insert_key(track_idx, 0.0, 0.0)
	idle_anim.track_insert_key(track_idx, 0.5, 0.1)
	idle_anim.track_insert_key(track_idx, 1.0, 0.0)
	anim_player.add_animation("idle", idle_anim)
	var walk_anim        = Animation.new()
	walk_anim.length     = 0.5
	walk_anim.loop_mode  = Animation.LOOP_LINEAR
	track_idx            = walk_anim.add_track(Animation.TYPE_VALUE)
	walk_anim.track_set_path(track_idx, NodePath(":rotation:y"))
	walk_anim.track_insert_key(track_idx, 0.0, -0.15)
	walk_anim.track_insert_key(track_idx, 0.25, 0.15)
	walk_anim.track_insert_key(track_idx, 0.5, -0.15)
	anim_player.add_animation("walk", walk_anim)

# ─────────────────────────────────────────────────────────────
# PUBLIC GETTERS / CONTROL
# ─────────────────────────────────────────────────────────────

func is_entity_alive() -> bool:
	return _state == State.ALIVE and is_instance_valid(_entity_node)

func get_entity_position() -> Vector3:
	return _entity_pos

func get_move_mode() -> MoveMode:
	return _move_mode

func get_state() -> State:
	return _state

func get_current_path() -> Array[Vector3]:
	return _path.duplicate()

func set_player_immune(_immune: bool) -> void:
	pass

func reset_spawn_cycle() -> void:
	match _state:
		State.WAITING_FOR_WORLD:
			return
		State.WAITING_FOR_ACTIVE:
			_player_was_active = false
			_prev_player_pos   = Vector3.ZERO
			_prev_player_basis = Basis.IDENTITY
			_skip_active_wait  = false
		State.SPAWN_DELAY:
			_spawn_timer = randf_range(SPAWN_DELAY_MIN, SPAWN_DELAY_MAX)
		State.ALIVE:
			return
		State.DESPAWNED:
			_state        = State.WAITING_FOR_ACTIVE
			_skip_active_wait = true
			_respawn_timer    = 0.0

func pause_spawn_cycle() -> void:
	match _state:
		State.WAITING_FOR_ACTIVE:
			_spawn_timer = -1.0
		State.SPAWN_DELAY:
			_spawn_timer = -abs(_spawn_timer)
		State.ALIVE:
			return
		State.DESPAWNED:
			_respawn_timer = -abs(_respawn_timer)

func resume_spawn_cycle() -> void:
	match _state:
		State.WAITING_FOR_ACTIVE:
			if _spawn_timer < 0:
				_spawn_timer = 0.0
		State.SPAWN_DELAY:
			if _spawn_timer < 0:
				_spawn_timer = abs(_spawn_timer)
		State.DESPAWNED:
			if _respawn_timer < 0:
				_respawn_timer = abs(_respawn_timer)
		State.ALIVE:
			return

func force_reset_spawn_cycle() -> void:
	if is_instance_valid(_entity_node):
		_entity_node.queue_free()
		_entity_node = null
	_state                = State.WAITING_FOR_ACTIVE
	_move_mode            = MoveMode.WANDER
	_spawn_timer          = 0.0
	_despawn_timer        = 0.0
	_respawn_timer        = 0.0
	_wander_timer         = 0.0
	_step_timer           = 0.0
	_los_react_timer      = 0.0
	_skip_active_wait     = false
	_player_was_active    = false
	_current_speed        = SPEED_SLOW
	_target_speed         = SPEED_SLOW
	_los_reacting         = false
	_last_known_player    = Vector3.ZERO
	_wander_target        = Vector3.ZERO
	_path.clear()
	_current_target_index = 0
	_prev_player_pos      = Vector3.ZERO
	_prev_player_basis    = Basis.IDENTITY
	_last_position        = Vector3.ZERO
	_stuck_timer          = 0.0
	_path_refresh_count   = 0
	_bfs_cooldown         = 0.0
	_invalidate_cache()

func force_spawn() -> void:
	if is_instance_valid(_entity_node):
		_do_despawn()
	_state            = State.WAITING_FOR_ACTIVE
	_skip_active_wait = true
	_try_spawn()

func force_despawn() -> void:
	if is_instance_valid(_entity_node):
		_do_despawn()

func spawn_passive() -> void:
	if is_instance_valid(_entity_node):
		_do_despawn()

func defeat() -> void:
	print("[EntityManager] Enemy defeated by player!")
	_stop_sound()
	if is_instance_valid(_entity_node):
		_entity_node.queue_free()
		_entity_node = null
	emit_signal("enemy_defeated")
	_state            = State.WAITING_FOR_ACTIVE
	_skip_active_wait = true
	_respawn_timer    = 0.0
	_path_refresh_count = 0
	_stuck_timer      = 0.0
	_invalidate_cache()

func get_entity_node() -> Node3D:
	return _entity_node

func get_first_spawn_lock_remaining() -> float:
	return maxf(0.0, FIRST_SPAWN_LOCK - _first_spawn_lock_timer)

func has_first_input() -> bool:
	return _first_input_received
