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
const SPEED_HUNT            : float = 7.5
const SPEED_PLAYER_REF      : float = 5.5
const LOS_REACT_MIN         : float = 0.5
const LOS_REACT_MAX         : float = 2.0
const DESPAWN_TIMEOUT       : float = 300.0
const RESPAWN_AFTER_DESPAWN : float = 5.0
const WANDER_RETARGET_TIME  : float = 3.0
const STEP_INTERVAL         : float = 0.12
const LOS_MAX_DIST          : float = 18.0
const ENTITY_HEIGHT         : float = 0.5
const ROTATION_SPEED        : float = 8.0
const MIN_PATH_DISTANCE     : float = 0.4
const STUCK_THRESHOLD       : float = 0.6
const STUCK_MOVE_MIN        : float = 0.08

# Jumpscare constants
const JUMPSCARE_FACE_OFFSET : float = 1.2
const JUMPSCARE_CAM_HEIGHT  : float = 0.8

# First-spawn lock
const FIRST_SPAWN_LOCK      : float = 60.0

# ─────────────────────────────────────────────────────────────
# PATHFINDING TUNABLES
# ─────────────────────────────────────────────────────────────

const ASTAR_MAX_NODES_WANDER     : int   = 400
const ASTAR_MAX_NODES_CHASE      : int   = 600
const ASTAR_MAX_NODES_HUNT       : int   = 800

const REPATH_INTERVAL_WANDER     : float = 1.2
const REPATH_INTERVAL_CHASE      : float = 0.35
const REPATH_INTERVAL_LAST_KNOWN : float = 0.55
const REPATH_INTERVAL_HUNT       : float = 0.18

const REPATH_TARGET_DRIFT        : float = 2.5
const MAX_STUCK_REPATHS          : int   = 8
const FLOW_FALLBACK_ENABLED      : bool  = true

const CACHE_MAX_SIZE             : int   = 800
const CACHE_TTL_FRAMES           : int   = 6

# ─────────────────────────────────────────────────────────────
# SOUND CONSTANTS
# ─────────────────────────────────────────────────────────────

const SOUND_MAX_DISTANCE    : float = 50.0
const SOUND_UPDATE_INTERVAL : float = 0.1
const SIGHT_SOUND_COOLDOWN  : float = 5.0
const JUMPSCARE_VOLUME_DB   : float = -6.0
const SPAWN_SOUND_VOLUME_DB : float = -18.0

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

enum MoveMode { WANDER, CHASE_LOS, LAST_KNOWN, HUNT }

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

var _spawn_timer     : float = 0.0
var _despawn_timer   : float = 0.0
var _respawn_timer   : float = 0.0
var _wander_timer    : float = 0.0
var _step_timer      : float = 0.0
var _los_react_timer : float = 0.0
var _repath_timer    : float = 0.0

var _skip_active_wait : bool = false
var _is_hunting       : bool = false

var _first_input_received   : bool  = false
var _first_spawn_lock_timer : float = 0.0

var _entity_node : Node3D  = null
var _entity_pos  : Vector3 = Vector3.ZERO

var _current_speed : float = SPEED_SLOW
var _target_speed  : float = SPEED_SLOW
var _los_reacting  : bool  = false

var _path                 : Array[Vector3] = []
var _current_target_index : int      = 0
var _last_known_player    : Vector3  = Vector3.ZERO
var _last_path_target     : Vector2i = Vector2i(-9999, -9999)

var _last_position      : Vector3 = Vector3.ZERO
var _stuck_timer        : float   = 0.0
var _stuck_repath_count : int     = 0

var _prev_player_pos   : Vector3 = Vector3.ZERO
var _prev_player_basis : Basis   = Basis.IDENTITY

var _current_rotation : float = 0.0
var _movement_direction : Vector3 = Vector3.ZERO
var _has_los : bool = false

var _animation_player : AnimationPlayer = null
var _current_anim     : String = ""

# Jumpscare state
var _jumpscare_rotation_forced : bool = false

# ─────────────────────────────────────────────────────────────
# WALKABILITY CACHE
# ─────────────────────────────────────────────────────────────

var _walkable_cache : Dictionary = {}
var _current_frame  : int = 0

# ─────────────────────────────────────────────────────────────
# AUDIO
# ─────────────────────────────────────────────────────────────

var _audio_stream_player   : AudioStreamPlayer3D = null
var _sight_sound_player    : AudioStreamPlayer3D = null
var _spawn_sound_player    : AudioStreamPlayer3D = null
var _sound_update_timer    : float = 0.0
var _is_sound_playing      : bool  = false
var _last_sight_sound_time : float = 0.0

var _jumpscare_player : AudioStreamPlayer = null
var _jumpscare_timer  : float = 0.0

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

func _on_world_ready() -> void:
	_state = State.WAITING_FOR_ACTIVE

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_current_frame = Engine.get_process_frames()

	if _first_input_received and _first_spawn_lock_timer < FIRST_SPAWN_LOCK:
		_first_spawn_lock_timer += delta

	match _state:
		State.WAITING_FOR_WORLD:
			pass

		State.WAITING_FOR_ACTIVE:
			if _spawn_timer < 0.0:
				return
			if _is_player_active():
				if not _first_input_received:
					_first_input_received = true
					print("[EntityManager] First player input — spawn lock started.")
				_begin_spawn_delay()

		State.SPAWN_DELAY:
			if _spawn_timer < 0.0:
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
				_update_entity_rotation(delta)
				_update_animation()
			_update_sound(delta)

		State.JUMPSCARE:
			_tick_jumpscare(delta)

		State.DESPAWNED:
			if _respawn_timer < 0.0:
				return
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				_state = State.WAITING_FOR_ACTIVE
				_skip_active_wait = true

# ═══════════════════════════════════════════════════════════════
#  ENTITY ROTATION
# ═══════════════════════════════════════════════════════════════

func _update_entity_rotation(delta: float) -> void:
	if not _entity_node:
		return
	
	var target_angle: float
	
	if _has_los or _is_hunting:
		var direction := (player.global_position - _entity_pos).normalized()
		target_angle = atan2(direction.x, direction.z)
	else:
		if _movement_direction.length() > 0.1 and not _path.is_empty():
			target_angle = atan2(_movement_direction.x, _movement_direction.z)
		else:
			target_angle = _current_rotation
	
	var rotation_speed = ROTATION_SPEED * (2.0 if _is_hunting else 1.0)
	_current_rotation = lerp_angle(_current_rotation, target_angle, rotation_speed * delta)
	_entity_node.rotation.y = _current_rotation

# ═══════════════════════════════════════════════════════════════
#  WALKABILITY CACHE
# ═══════════════════════════════════════════════════════════════

func _tile_key(wx: int, wz: int) -> int:
	return (wx & 0xFFFFFFFF) | ((wz & 0xFFFFFFFF) << 32)

func _invalidate_cache() -> void:
	_walkable_cache.clear()

func _cache_prune() -> void:
	if _walkable_cache.size() > CACHE_MAX_SIZE:
		var expired : Array = []
		for k in _walkable_cache:
			if (_current_frame - _walkable_cache[k]["f"]) > CACHE_TTL_FRAMES:
				expired.append(k)
		for k in expired:
			_walkable_cache.erase(k)
		if _walkable_cache.size() > CACHE_MAX_SIZE:
			_walkable_cache.clear()

func _is_tile_walkable(wx: int, wz: int) -> bool:
	var key   := _tile_key(wx, wz)
	var entry  = _walkable_cache.get(key)
	if entry and (_current_frame - entry["f"]) <= CACHE_TTL_FRAMES:
		return entry["v"]

	_cache_prune()

	if not chunk_manager:
		return false

	var chunk_pos := Vector2i(
		floori(float(wx) / chunk_manager.CHUNK_SIZE),
		floori(float(wz) / chunk_manager.CHUNK_SIZE)
	)
	if not chunk_manager.chunks.has(chunk_pos):
		_walkable_cache[key] = {"v": false, "f": _current_frame}
		return false

	var cell   := chunk_manager.get_map_cell(wx, wz)
	var result : bool = cell["state"] == "revealed"
	_walkable_cache[key] = {"v": result, "f": _current_frame}
	return result

func _is_diagonal_passable(fx: int, fz: int, tx: int, tz: int) -> bool:
	var dx := tx - fx
	var dz := tz - fz
	if dx == 0 or dz == 0:
		return true
	return _is_tile_walkable(fx + dx, fz) and _is_tile_walkable(fx, fz + dz)

# ═══════════════════════════════════════════════════════════════
#  A* PATHFINDING
# ═══════════════════════════════════════════════════════════════

const _DIRS : Array[Vector2i] = [
	Vector2i( 1, 0), Vector2i(-1, 0), Vector2i( 0, 1), Vector2i( 0,-1),
	Vector2i( 1, 1), Vector2i( 1,-1), Vector2i(-1, 1), Vector2i(-1,-1),
]
const _CARDINAL_COST : float = 1.0
const _DIAGONAL_COST : float = 1.414

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dz := absi(a.y - b.y)
	return _CARDINAL_COST * maxi(dx, dz) + (_DIAGONAL_COST - _CARDINAL_COST) * mini(dx, dz)

func _astar_path(from: Vector3, to: Vector3, max_nodes: int, randomize_ties: bool = false) -> Array[Vector3]:
	if not chunk_manager:
		return []

	var start := Vector2i(floori(from.x), floori(from.z))
	var goal  := Vector2i(floori(to.x),   floori(to.z))

	if start == goal:
		return []

	if not _is_tile_walkable(goal.x, goal.y):
		goal = _nearest_walkable_to(goal, start, 4)
		if goal == start:
			return []

	var open_set : Array    = []
	var g_cost   : Dictionary = {}
	var parent   : Dictionary = {}

	g_cost[start] = 0.0
	_pq_push(open_set, [_heuristic(start, goal), 0.0, start])

	var expanded : int  = 0
	var found    : bool = false

	while open_set.size() > 0 and expanded < max_nodes:
		var entry = _pq_pop(open_set)
		var cur : Vector2i = entry[2]
		expanded += 1

		if cur == goal:
			found = true
			break

		var cur_g : float = g_cost.get(cur, INF)

		var dir_list = _DIRS.duplicate()
		if randomize_ties:
			dir_list.shuffle()

		for d in dir_list:
			var nb : Vector2i = cur + d
			if not _is_tile_walkable(nb.x, nb.y):
				continue
			if not _is_diagonal_passable(cur.x, cur.y, nb.x, nb.y):
				continue

			var step_cost : float = _DIAGONAL_COST if (d.x != 0 and d.y != 0) else _CARDINAL_COST
			var tent_g    : float = cur_g + step_cost
			var exist_g   : float = g_cost.get(nb, INF)

			if tent_g < exist_g:
				g_cost[nb] = tent_g
				parent[nb] = cur
				_pq_push(open_set, [tent_g + _heuristic(nb, goal), tent_g, nb])

	if not found:
		if not FLOW_FALLBACK_ENABLED:
			return []
		return _partial_path_to_closest(parent, g_cost, goal)

	var tiles : Array[Vector2i] = []
	var step  : Vector2i = goal
	while parent.has(step):
		tiles.push_front(step)
		step = parent[step]

	return _tiles_to_world(tiles, from.y)

func _pq_push(heap: Array, entry: Array) -> void:
	var lo := 0; var hi := heap.size(); var f : float = entry[0]
	while lo < hi:
		var mid := (lo + hi) / 2
		if heap[mid][0] < f: lo = mid + 1
		else:                 hi = mid
	heap.insert(lo, entry)

func _pq_pop(heap: Array) -> Array:
	return heap.pop_front()

func _nearest_walkable_to(target: Vector2i, reference: Vector2i, radius: int) -> Vector2i:
	var best := reference; var best_d := INF
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var c := target + Vector2i(dx, dz)
			if _is_tile_walkable(c.x, c.y):
				var d := _heuristic(c, reference)
				if d < best_d: best_d = d; best = c
	return best

func _partial_path_to_closest(parent: Dictionary, g_cost: Dictionary, goal: Vector2i) -> Array[Vector3]:
	if parent.is_empty():
		return []
	var best_node : Vector2i = Vector2i.ZERO
	var best_h    : float    = INF
	var any       : bool     = false
	for node in g_cost.keys():
		if not (node is Vector2i): continue
		var h := _heuristic(node, goal)
		if h < best_h: best_h = h; best_node = node; any = true
	if not any:
		return []
	var tiles : Array[Vector2i] = []
	var step  : Vector2i = best_node
	while parent.has(step):
		tiles.push_front(step)
		step = parent[step]
	return _tiles_to_world(tiles, _entity_pos.y)

func _tiles_to_world(tiles: Array[Vector2i], y: float) -> Array[Vector3]:
	var result : Array[Vector3] = []
	for t in tiles:
		result.append(Vector3(t.x + 0.5, y, t.y + 0.5))
	return result

# ═══════════════════════════════════════════════════════════════
#  PATH SIMPLIFICATION
# ═══════════════════════════════════════════════════════════════

func _simplify_path(path: Array[Vector3]) -> Array[Vector3]:
	if path.size() <= 2:
		return path
	var result : Array[Vector3] = [path[0]]
	var anchor := 0; var i := 1
	while i < path.size():
		if not _has_clear_path_world(path[anchor], path[i]):
			result.append(path[i - 1])
			anchor = i - 1
		i += 1
	result.append(path[path.size() - 1])
	return result

func _has_clear_path_world(a: Vector3, b: Vector3) -> bool:
	var ax := floori(a.x); var az := floori(a.z)
	var bx := floori(b.x); var bz := floori(b.z)
	var dx := absi(bx - ax); var dz := absi(bz - az)
	var sx := 1 if ax < bx else -1; var sz := 1 if az < bz else -1
	var err := dx - dz
	var steps := dx + dz + 2
	for _i in range(steps):
		if not _is_tile_walkable(ax, az): return false
		if ax == bx and az == bz: break
		var e2 := err * 2
		if e2 > -dz: err -= dz; ax += sx
		if e2 <  dx: err += dx; az += sz
	return true

# ═══════════════════════════════════════════════════════════════
#  REPATH SYSTEM
# ═══════════════════════════════════════════════════════════════

func _should_repath(target_tile: Vector2i) -> bool:
	if _repath_timer <= 0.0: return true
	if _path.is_empty():     return true
	if _last_path_target.distance_squared_to(target_tile) > int(REPATH_TARGET_DRIFT * REPATH_TARGET_DRIFT):
		return true
	if _current_target_index < _path.size():
		var nxt := _path[_current_target_index]
		if not _is_tile_walkable(floori(nxt.x), floori(nxt.z)):
			return true
	return false

func _do_repath(target_pos: Vector3, mode: MoveMode) -> void:
	var max_nodes : int
	var rand_ties : bool = false
	match mode:
		MoveMode.WANDER:
			max_nodes = ASTAR_MAX_NODES_WANDER
			rand_ties = true
		MoveMode.CHASE_LOS:
			max_nodes = ASTAR_MAX_NODES_CHASE
		MoveMode.LAST_KNOWN:
			max_nodes = ASTAR_MAX_NODES_CHASE
		MoveMode.HUNT:
			max_nodes = ASTAR_MAX_NODES_HUNT
		_:
			max_nodes = ASTAR_MAX_NODES_CHASE

	var new_path := _astar_path(_entity_pos, target_pos, max_nodes, rand_ties)
	new_path = _simplify_path(new_path)

	if new_path.is_empty() and mode != MoveMode.WANDER:
		new_path = _astar_path(_entity_pos, target_pos, 150, false)

	_path = new_path
	_current_target_index = 0
	_last_path_target = Vector2i(floori(target_pos.x), floori(target_pos.z))

	match mode:
		MoveMode.WANDER:     _repath_timer = REPATH_INTERVAL_WANDER
		MoveMode.CHASE_LOS:  _repath_timer = REPATH_INTERVAL_CHASE
		MoveMode.LAST_KNOWN: _repath_timer = REPATH_INTERVAL_LAST_KNOWN
		MoveMode.HUNT:       _repath_timer = REPATH_INTERVAL_HUNT
		_:                   _repath_timer = REPATH_INTERVAL_CHASE

# ═══════════════════════════════════════════════════════════════
#  ALIVE UPDATE
# ═══════════════════════════════════════════════════════════════

func _update_alive(delta: float) -> void:
	if not is_instance_valid(_entity_node):
		_state = State.WAITING_FOR_ACTIVE
		return

	_despawn_timer -= delta
	if _despawn_timer <= 0.0:
		_do_despawn()
		return

	_repath_timer -= delta
	_step_timer   -= delta

	var player_tile_center : Vector3 = _get_tile_center(player.global_position if player else Vector3.ZERO)
	_has_los = _is_hunting or _check_line_of_sight(player_tile_center)

	if _has_los:
		_last_known_player = player_tile_center
		_despawn_timer     = DESPAWN_TIMEOUT

		if _move_mode == MoveMode.WANDER or _move_mode == MoveMode.LAST_KNOWN:
			_play_sight_sound()
			_move_mode       = MoveMode.HUNT if _is_hunting else MoveMode.CHASE_LOS
			_los_react_timer = 0.0 if _is_hunting else randf_range(LOS_REACT_MIN, LOS_REACT_MAX)
			_los_reacting    = not _is_hunting
			_current_speed   = SPEED_SLOW
			_path.clear()
			_repath_timer    = 0.0
			_last_path_target = Vector2i(-9999, -9999)

		if _los_reacting:
			_los_react_timer -= delta
			if _los_react_timer <= 0.0:
				_los_reacting = false
				_target_speed = SPEED_HUNT if _is_hunting else SPEED_FAST
		else:
			_target_speed = SPEED_HUNT if _is_hunting else SPEED_FAST
			if _is_hunting:
				_move_mode = MoveMode.HUNT
	else:
		if _move_mode == MoveMode.CHASE_LOS or _move_mode == MoveMode.HUNT:
			_move_mode    = MoveMode.LAST_KNOWN
			_target_speed = SPEED_SLOW
			_path.clear()
			_repath_timer = 0.0
		elif _move_mode == MoveMode.LAST_KNOWN:
			if _entity_pos.distance_to(_last_known_player) < MIN_PATH_DISTANCE * 2.0:
				_move_mode    = MoveMode.WANDER
				_target_speed = SPEED_SLOW
				_path.clear()
				_repath_timer = 0.0

	_current_speed = lerpf(_current_speed, _target_speed, delta * 4.0)

	var movement := (_entity_pos - _last_position).length()
	if movement < STUCK_MOVE_MIN and not _path.is_empty():
		_stuck_timer += delta
		if _stuck_timer >= STUCK_THRESHOLD:
			_stuck_timer = 0.0
			_stuck_repath_count += 1
			if _stuck_repath_count >= MAX_STUCK_REPATHS:
				print("[EntityManager] Max stuck repaths — despawning.")
				_do_despawn()
				return
			print("[EntityManager] Stuck! Force-repath #%d" % _stuck_repath_count)
			_path.clear()
			_repath_timer = 0.0
			_last_path_target = Vector2i(-9999, -9999)
	else:
		if movement > STUCK_MOVE_MIN:
			_stuck_timer        = 0.0
			_stuck_repath_count = 0
		_last_position = _entity_pos

	if _step_timer <= 0.0:
		_step_timer = STEP_INTERVAL
		_tick_pathfinding(player_tile_center)

	_move_entity(delta)
	_entity_node.global_position = _entity_pos

func _tick_pathfinding(player_pos: Vector3) -> void:
	var target_pos : Vector3

	match _move_mode:
		MoveMode.HUNT, MoveMode.CHASE_LOS:
			target_pos = player_pos
		MoveMode.LAST_KNOWN:
			target_pos = _last_known_player
		MoveMode.WANDER:
			_wander_timer -= STEP_INTERVAL
			if _wander_timer <= 0.0 or _path.is_empty():
				_wander_timer     = WANDER_RETARGET_TIME
				target_pos        = _pick_wander_target()
				_repath_timer     = 0.0
				_last_path_target = Vector2i(-9999, -9999)
			else:
				return
		_:
			return

	var target_tile := Vector2i(floori(target_pos.x), floori(target_pos.z))
	if _should_repath(target_tile):
		_do_repath(target_pos, _move_mode)

func _pick_wander_target() -> Vector3:
	if not chunk_manager:
		return _entity_pos
	for _attempt in range(12):
		var angle : float = randf() * TAU
		var dist  : float = randf_range(5.0, 14.0)
		var tx    : int   = floori(_entity_pos.x + cos(angle) * dist)
		var tz    : int   = floori(_entity_pos.z + sin(angle) * dist)
		if _is_tile_walkable(tx, tz):
			return _get_tile_center(Vector3(tx, _entity_pos.y, tz))
	return _entity_pos

func _move_entity(delta: float) -> void:
	if _path.is_empty():
		_movement_direction = Vector3.ZERO
		return
	if _current_target_index >= _path.size():
		_path.clear()
		_current_target_index = 0
		_movement_direction = Vector3.ZERO
		return

	var target : Vector3 = _path[_current_target_index]
	var diff   : Vector3 = target - _entity_pos
	diff.y = 0.0
	var dist : float = diff.length()

	if not _is_tile_walkable(floori(target.x), floori(target.z)):
		_path.clear()
		_current_target_index = 0
		_repath_timer = 0.0
		_movement_direction = Vector3.ZERO
		return

	if dist < MIN_PATH_DISTANCE:
		_entity_pos           = target
		_current_target_index += 1
		return

	var move_dist : float = _current_speed * delta
	var move_dir          = diff.normalized()
	
	_movement_direction = move_dir

	if move_dist >= dist:
		_entity_pos           = target
		_current_target_index += 1
	else:
		_entity_pos += move_dir * move_dist

	_entity_pos.y = ENTITY_HEIGHT

	if is_instance_valid(_entity_node) and _entity_node is CharacterBody3D:
		_entity_node.velocity   = move_dir * _current_speed
		_entity_node.velocity.y = 0.0
		_entity_node.move_and_slide()

func _check_line_of_sight(target: Vector3) -> bool:
	if not chunk_manager or not player:
		return false
	var dist : float = _entity_pos.distance_to(target)
	if dist > LOS_MAX_DIST:
		return false
	var ax := floori(_entity_pos.x); var az := floori(_entity_pos.z)
	var bx := floori(target.x);      var bz := floori(target.z)
	var dx := absi(bx - ax); var dz := absi(bz - az)
	var sx := 1 if ax < bx else -1; var sz := 1 if az < bz else -1
	var err := dx - dz
	var steps := dx + dz + 2
	for _i in range(steps):
		if not (ax == floori(_entity_pos.x) and az == floori(_entity_pos.z)):
			var cell := chunk_manager.get_map_cell(ax, az)
			if cell["state"] == "hidden":
				return false
		if ax == bx and az == bz: break
		var e2 := err * 2
		if e2 > -dz: err -= dz; ax += sx
		if e2 <  dx: err += dx; az += sz
	return true

func _play_sight_sound() -> void:
	if not _sight_sound_player:
		return
	var t : float = Time.get_ticks_msec() / 1000.0
	if t - _last_sight_sound_time < SIGHT_SOUND_COOLDOWN:
		return
	_last_sight_sound_time = t
	if not _sight_sound_player.stream:
		_load_sight_sound()
	_sight_sound_player.play()
	print("[EntityManager] 👁️ Enemy spotted player!")

func _get_tile_center(pos: Vector3) -> Vector3:
	return Vector3(floori(pos.x) + 0.5, pos.y, floori(pos.z) + 0.5)

func _is_player_active() -> bool:
	if not player: return false
	var moved   : bool = player.global_position.distance_to(_prev_player_pos) > 0.05
	var rotated : bool = not player.global_transform.basis.is_equal_approx(_prev_player_basis)
	_prev_player_pos   = player.global_position
	_prev_player_basis = player.global_transform.basis
	return moved or rotated

# ─────────────────────────────────────────────────────────────
# SPAWN
# ─────────────────────────────────────────────────────────────

func _begin_spawn_delay() -> void:
	_spawn_timer = randf_range(SPAWN_DELAY_MIN, SPAWN_DELAY_MAX)
	_state       = State.SPAWN_DELAY

func _try_spawn() -> void:
	if not chunk_manager or not player:
		return
	var spawn_tile : Vector2i = _find_spawn_tile()
	if spawn_tile == Vector2i(-9999, -9999):
		_spawn_timer = 3.0
		return

	if is_instance_valid(_entity_node):
		_entity_node.queue_free()
		_entity_node = null

	_entity_pos  = Vector3(spawn_tile.x + 0.5, ENTITY_HEIGHT, spawn_tile.y + 0.5)
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
	_repath_timer         = 0.0
	_wander_timer         = 0.0
	_step_timer           = 0.0
	_los_react_timer      = 0.0
	_los_reacting         = false
	_last_known_player    = _get_tile_center(player.global_position)
	_move_mode            = MoveMode.WANDER
	_path.clear()
	_current_target_index = 0
	_last_path_target     = Vector2i(-9999, -9999)
	_last_position        = _entity_pos
	_stuck_timer          = 0.0
	_stuck_repath_count   = 0
	_movement_direction   = Vector3.ZERO
	_has_los              = false
	_invalidate_cache()

	_state = State.ALIVE
	print("[EntityManager] Entity spawned at tile ", spawn_tile)

func _find_spawn_tile() -> Vector2i:
	if not chunk_manager or not player:
		return Vector2i(-9999, -9999)
	var pp  : Vector3 = player.global_position
	var px  : int     = floori(pp.x)
	var pz  : int     = floori(pp.z)
	var rr  : int     = chunk_manager.RENDER_RADIUS * chunk_manager.CHUNK_SIZE
	var candidates : Array[Vector2i] = []
	for wx in range(px - rr, px + rr + 1):
		for wz in range(pz - rr, pz + rr + 1):
			var dist : float = Vector2(wx - px, wz - pz).length()
			if dist < SAFE_RADIUS: continue
			if not _is_tile_walkable(wx, wz): continue
			var ok := true
			for ddx in [-1, 0, 1]:
				for ddz in [-1, 0, 1]:
					if ddx == 0 and ddz == 0: continue
					if not _is_tile_walkable(wx + ddx, wz + ddz):
						ok = false; break
				if not ok: break
			if ok: candidates.append(Vector2i(wx, wz))
	if candidates.is_empty():
		return Vector2i(-9999, -9999)
	candidates.sort_custom(func(a, b):
		return Vector2(a.x - px, a.y - pz).length_squared() > Vector2(b.x - px, b.y - pz).length_squared())
	var pool : int = maxi(1, candidates.size() / 4)
	return candidates[randi() % pool]

func _do_despawn() -> void:
	print("[EntityManager] Entity despawning")
	_stop_sound()
	if is_instance_valid(_entity_node):
		_entity_node.queue_free()
		_entity_node = null
	_state              = State.DESPAWNED
	_respawn_timer      = RESPAWN_AFTER_DESPAWN
	_path.clear()
	_current_target_index = 0
	_stuck_repath_count   = 0
	_stuck_timer          = 0.0
	_movement_direction   = Vector3.ZERO
	_invalidate_cache()

func force_hunt_player() -> void:
	_is_hunting = true
	if _state == State.ALIVE:
		_move_mode    = MoveMode.HUNT
		_target_speed = SPEED_HUNT
		_path.clear()
		_repath_timer = 0.0
		print("[EntityManager] HUNT MODE ACTIVATED!")

# ─────────────────────────────────────────────────────────────
# ANIMATION
# ─────────────────────────────────────────────────────────────

func _setup_animation() -> void:
	if not _entity_node: return
	_animation_player = _entity_node.find_child("AnimationPlayer", true, false)
	if _animation_player: _play_animation("idle")

func _play_animation(anim_name: String, speed: float = 1.0) -> void:
	if not _animation_player: return
	if _current_anim == anim_name: return
	var alts := {
		"idle": ["idle", "Idle", "IDLE", "standing", "Standing"],
		"walk": ["walk", "Walk", "WALK", "walking", "Walking", "run", "Run"]
	}
	for alt in alts.get(anim_name, [anim_name]):
		if _animation_player.has_animation(alt):
			_current_anim = alt
			_animation_player.play(alt, -1, speed)
			return

func _update_animation() -> void:
	if not _animation_player: return
	var moving := _current_speed > 0.5 and not _path.is_empty()
	if moving: _play_animation("walk", clampf(_current_speed / SPEED_SLOW * 1.5, 0.5, 2.0))
	else:      _play_animation("idle")

func _setup_animation_fallback(entity: Node3D) -> void:
	var ap   = AnimationPlayer.new(); ap.name = "AnimationPlayer"; entity.add_child(ap)
	var idle = Animation.new(); idle.length = 1.0; idle.loop_mode = Animation.LOOP_LINEAR
	var ti   = idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(ti, NodePath(":rotation:y"))
	idle.track_insert_key(ti, 0.0, 0.0); idle.track_insert_key(ti, 0.5, 0.1); idle.track_insert_key(ti, 1.0, 0.0)
	ap.add_animation("idle", idle)
	var walk = Animation.new(); walk.length = 0.5; walk.loop_mode = Animation.LOOP_LINEAR
	var tw   = walk.add_track(Animation.TYPE_VALUE)
	walk.track_set_path(tw, NodePath(":rotation:y"))
	walk.track_insert_key(tw, 0.0, -0.15); walk.track_insert_key(tw, 0.25, 0.15); walk.track_insert_key(tw, 0.5, -0.15)
	ap.add_animation("walk", walk)

# ─────────────────────────────────────────────────────────────
# SOUND
# ─────────────────────────────────────────────────────────────

func _setup_sound() -> void:
	if not _entity_node: return
	_audio_stream_player = AudioStreamPlayer3D.new()
	_audio_stream_player.name = "EntitySound"
	var s = load("res://Sounds/Sweeper/sample_sound.ogg")
	if s: _audio_stream_player.stream = s
	else: push_error("[EntityManager] Could not load sample_sound.ogg"); return
	_audio_stream_player.max_distance = SOUND_MAX_DISTANCE
	_audio_stream_player.max_db = 0.0; _audio_stream_player.unit_size = 1.0
	_audio_stream_player.autoplay = false
	_audio_stream_player.finished.connect(_on_sound_finished)
	_entity_node.add_child(_audio_stream_player)
	_is_sound_playing = true

	_sight_sound_player = AudioStreamPlayer3D.new()
	_sight_sound_player.name = "SightSound"
	_sight_sound_player.max_distance = SOUND_MAX_DISTANCE
	_sight_sound_player.max_db = 0.0; _sight_sound_player.unit_size = 1.0
	_sight_sound_player.autoplay = false
	_entity_node.add_child(_sight_sound_player)

	_spawn_sound_player = AudioStreamPlayer3D.new()
	_spawn_sound_player.name = "SpawnSound"
	_spawn_sound_player.max_distance = 200.0; _spawn_sound_player.unit_size = 0.3
	_spawn_sound_player.volume_db = SPAWN_SOUND_VOLUME_DB; _spawn_sound_player.autoplay = false
	var ss = load("res://Sounds/Sweeper/spawn.wav")
	if ss: _spawn_sound_player.stream = ss
	_entity_node.add_child(_spawn_sound_player)
	call_deferred("_play_sound_deferred")

func _play_sound_deferred() -> void:
	if _audio_stream_player and is_instance_valid(_audio_stream_player) and _is_sound_playing:
		_audio_stream_player.play()
	if _spawn_sound_player and is_instance_valid(_spawn_sound_player):
		_spawn_sound_player.play()

func _on_sound_finished() -> void:
	if _audio_stream_player and is_instance_valid(_audio_stream_player) and _is_sound_playing:
		_audio_stream_player.play()

func _load_sight_sound() -> void:
	if not _sight_sound_player: return
	var ss = load("res://Sounds/Sweeper/seen.wav")
	if ss: _sight_sound_player.stream = ss
	elif _audio_stream_player: _sight_sound_player.stream = _audio_stream_player.stream

func _update_sound(delta: float) -> void:
	if not _audio_stream_player or not player: return
	_sound_update_timer += delta
	if _sound_update_timer >= SOUND_UPDATE_INTERVAL:
		_sound_update_timer = 0.0
		var sf : float = clamp(_current_speed / SPEED_FAST, 0.8, 1.5)
		_audio_stream_player.pitch_scale = lerp(_audio_stream_player.pitch_scale, sf, 0.1)

func _stop_sound() -> void:
	if _audio_stream_player and _is_sound_playing:
		_audio_stream_player.stop(); _is_sound_playing = false
		if _audio_stream_player.finished.is_connected(_on_sound_finished):
			_audio_stream_player.finished.disconnect(_on_sound_finished)
	if _sight_sound_player: _sight_sound_player.stop()
	if _spawn_sound_player: _spawn_sound_player.stop()

# ═══════════════════════════════════════════════════════════════
#  JUMPSCARE SYSTEM (COMPLETELY REWRITTEN)
# ═══════════════════════════════════════════════════════════════

func trigger_jumpscare() -> void:
	if _state == State.JUMPSCARE or _state == State.JUMPSCARE_DESPAWN:
		return
	
	_state = State.JUMPSCARE
	_stop_sound()
	_despawn_timer = -999.0
	
	if not is_instance_valid(_entity_node) or not player:
		_on_jumpscare_finished()
		return
	
	print("[EntityManager] JUMPSCARE STARTING")
	
	# Disable all player input
	_disable_player_input()
	
	# Position and face the player
	_jumpscare_position_player()
	_jumpscare_force_face_each_other()
	
	# Play eat animation
	_play_eat_animation()
	
	# Play jumpscare sound
	_jumpscare_player = AudioStreamPlayer.new()
	_jumpscare_player.name = "JumpscareSound"
	_jumpscare_player.volume_db = JUMPSCARE_VOLUME_DB
	var js_stream = load("res://Sounds/Sweeper/jumpscare.wav")
	if js_stream:
		_jumpscare_player.stream = js_stream
	add_child(_jumpscare_player)
	
	_jumpscare_player.finished.connect(_on_jumpscare_sound_finished, CONNECT_ONE_SHOT)
	_jumpscare_player.play()
	
	var sound_length = js_stream.get_length() if js_stream else 3.0
	_jumpscare_timer = sound_length + 0.2
	
	print("[EntityManager] Jumpscare triggered! Sound length: ", sound_length)

func _disable_player_input() -> void:
	if not player:
		return
	
	if player.has_method("disable_controls"):
		player.disable_controls()
	if player.has_method("lock_camera"):
		player.lock_camera(true)
	
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)

func _enable_player_input() -> void:
	if not player:
		return
	
	player.set_process_input(true)
	player.set_process_unhandled_input(true)
	player.set_physics_process(true)

func _jumpscare_position_player() -> void:
	if not player or not _entity_node:
		return
	
	var enemy_pos := _entity_node.global_position
	var enemy_transform := _entity_node.global_transform
	var enemy_forward := -enemy_transform.basis.z
	
	if enemy_forward.length() < 0.1:
		enemy_forward = Vector3.FORWARD
	
	enemy_forward.y = 0
	enemy_forward = enemy_forward.normalized()
	
	# Position player in front of enemy
	var player_offset := enemy_forward * JUMPSCARE_FACE_OFFSET
	var player_pos := enemy_pos + player_offset
	player_pos.y = enemy_pos.y - ENTITY_HEIGHT + 0.5
	
	# Adjust camera height
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		if not player.has_meta("original_eye_height"):
			player.set_meta("original_eye_height", cam.position.y)
		cam.position.y = JUMPSCARE_CAM_HEIGHT
	
	player.global_position = player_pos
	print("[EntityManager] Player positioned at: ", player_pos)

func _jumpscare_force_face_each_other() -> void:
	if not player or not _entity_node:
		print("[EntityManager] Cannot face - missing references")
		return
	
	var enemy_pos := _entity_node.global_position
	var player_pos := player.global_position
	
	# Calculate direction and angle
	var dir_to_enemy := (enemy_pos - player_pos).normalized()
	dir_to_enemy.y = 0
	var target_yaw := atan2(dir_to_enemy.x, dir_to_enemy.z)
	var target_yaw_deg := rad_to_deg(target_yaw)
	
	print("[EntityManager] Forcing player to face angle: ", target_yaw_deg)
	
	# Force player rotation multiple ways
	player.rotation_degrees.y = target_yaw_deg
	
	if "_rotation_y" in player:
		player.set("_rotation_y", target_yaw_deg)
	
	var new_transform := player.global_transform
	new_transform.basis = Basis(Vector3.UP, target_yaw)
	player.global_transform = new_transform
	
	# Reset camera pitch
	if "_rotation_x" in player:
		player.set("_rotation_x", 0.0)
	
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.rotation_degrees.x = 0.0
		cam.rotation_degrees.y = 0.0
	
	# Make enemy face player
	var dir_to_player := (player_pos - enemy_pos).normalized()
	dir_to_player.y = 0
	var enemy_target_angle := atan2(dir_to_player.x, dir_to_player.z)
	_entity_node.rotation.y = enemy_target_angle
	_current_rotation = enemy_target_angle
	
	print("[EntityManager] Enemy facing angle: ", rad_to_deg(enemy_target_angle))
	print("[EntityManager] Final player rotation: ", player.rotation_degrees.y)

func _play_eat_animation() -> void:
	if not _entity_node:
		return
	
	var anim_player := _entity_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not anim_player:
		anim_player = _entity_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	
	if anim_player:
		var eat_anim_names = ["eat", "Eat", "attack", "Attack", "bite", "Bite"]
		for anim_name in eat_anim_names:
			if anim_player.has_animation(anim_name):
				anim_player.play(anim_name)
				print("[EntityManager] Playing eat animation: ", anim_name)
				return
		
		if anim_player.has_animation("idle"):
			anim_player.play("idle", -1, 2.0)
		elif anim_player.has_animation("walk"):
			anim_player.play("walk", -1, 3.0)
	else:
		var tween := _entity_node.create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(_entity_node, "scale", Vector3(1.2, 0.8, 1.2), 0.15)
		tween.tween_property(_entity_node, "scale", Vector3(1.0, 1.0, 1.0), 0.15)
		tween.set_loops(3)

func _on_jumpscare_sound_finished() -> void:
	print("[EntityManager] Jumpscare sound finished - ending jumpscare")
	_on_jumpscare_finished()

func _tick_jumpscare(delta: float) -> void:
	_jumpscare_timer -= delta
	if _jumpscare_timer <= 0.0 and _state == State.JUMPSCARE:
		print("[EntityManager] Jumpscare timer fallback - ending jumpscare")
		_on_jumpscare_finished()

func _on_jumpscare_finished() -> void:
	if _state != State.JUMPSCARE:
		print("[EntityManager] Jumpscare already finished, ignoring")
		return
	
	print("[EntityManager] JUMPSCARE FINISHING - Cleaning up")
	
	if is_instance_valid(_jumpscare_player):
		if _jumpscare_player.finished.is_connected(_on_jumpscare_sound_finished):
			_jumpscare_player.finished.disconnect(_on_jumpscare_sound_finished)
		_jumpscare_player.queue_free()
		_jumpscare_player = null
	
	_jumpscare_timer = -999.0
	
	# Restore player camera height
	if player and player.has_meta("original_eye_height"):
		var cam := player.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.position.y = player.get_meta("original_eye_height")
		player.remove_meta("original_eye_height")
	
	_enable_player_input()
	
	_state = State.JUMPSCARE_DESPAWN
	
	if is_instance_valid(_entity_node):
		_entity_node.queue_free()
		_entity_node = null
	
	print("[EntityManager] Emitting jumpscare_finished signal")
	emit_signal("jumpscare_finished")
	
	_state = State.WAITING_FOR_ACTIVE
	_skip_active_wait = true
	_respawn_timer = 0.0

# ─────────────────────────────────────────────────────────────
# ENTITY VISUAL BUILDER
# ─────────────────────────────────────────────────────────────

func _build_entity_visual() -> Node3D:
	var scene = preload("res://Enemy/Sweeper/Sweeper.tscn")
	var inst  = scene.instantiate()
	if not inst.find_child("CollisionShape3D", true, false): _setup_collision(inst)
	if not inst.find_child("AnimationPlayer",  true, false): _setup_animation_fallback(inst)
	return inst

func _setup_collision(entity: Node3D) -> void:
	var body = CharacterBody3D.new(); body.name = "CollisionBody"
	for child in entity.get_children(): entity.remove_child(child); body.add_child(child)
	var col = CollisionShape3D.new(); var cyl = CylinderShape3D.new()
	cyl.height = COLLISION_HEIGHT; cyl.radius = COLLISION_RADIUS; col.shape = cyl
	body.add_child(col); body.collision_layer = 2; body.collision_mask = 1
	entity.add_child(body); _collision_body = body

# ─────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────

func is_entity_alive() -> bool:
	return _state == State.ALIVE and is_instance_valid(_entity_node)

func get_entity_position() -> Vector3:
	return _entity_pos

func get_entity_node() -> Node3D:
	return _entity_node

func get_move_mode() -> MoveMode:
	return _move_mode

func get_state() -> State:
	return _state

func get_current_path() -> Array[Vector3]:
	return _path.duplicate()

func is_hunting() -> bool:
	return _is_hunting

func get_first_spawn_lock_remaining() -> float:
	return maxf(0.0, FIRST_SPAWN_LOCK - _first_spawn_lock_timer)

func has_first_input() -> bool:
	return _first_input_received

func set_player_immune(_immune: bool) -> void:
	pass

func skip_first_spawn_lock() -> void:
	_first_spawn_lock_timer = FIRST_SPAWN_LOCK
	_first_input_received   = true
	print("[EntityManager] DEBUG: First-spawn lock skipped.")

func defeat() -> void:
	print("[EntityManager] Enemy defeated!")
	_stop_sound()
	if is_instance_valid(_entity_node): _entity_node.queue_free(); _entity_node = null
	emit_signal("enemy_defeated")
	_state = State.WAITING_FOR_ACTIVE; _skip_active_wait = true; _respawn_timer = 0.0
	_stuck_repath_count = 0; _stuck_timer = 0.0; _invalidate_cache()

func force_spawn() -> void:
	if is_instance_valid(_entity_node): _do_despawn()
	_state = State.WAITING_FOR_ACTIVE; _skip_active_wait = true; _try_spawn()

func force_despawn() -> void:
	if is_instance_valid(_entity_node): _do_despawn()

func spawn_passive() -> void:
	if is_instance_valid(_entity_node): _do_despawn()

func reset_spawn_cycle() -> void:
	match _state:
		State.WAITING_FOR_WORLD: return
		State.WAITING_FOR_ACTIVE:
			_prev_player_pos = Vector3.ZERO; _prev_player_basis = Basis.IDENTITY; _skip_active_wait = false
		State.SPAWN_DELAY:
			_spawn_timer = randf_range(SPAWN_DELAY_MIN, SPAWN_DELAY_MAX)
		State.DESPAWNED:
			_state = State.WAITING_FOR_ACTIVE; _skip_active_wait = true; _respawn_timer = 0.0
		State.ALIVE: return

func pause_spawn_cycle() -> void:
	match _state:
		State.WAITING_FOR_ACTIVE: _spawn_timer   = -1.0
		State.SPAWN_DELAY:        _spawn_timer   = -absf(_spawn_timer)
		State.DESPAWNED:          _respawn_timer = -absf(_respawn_timer)
		_: pass

func resume_spawn_cycle() -> void:
	match _state:
		State.WAITING_FOR_ACTIVE: if _spawn_timer   < 0.0: _spawn_timer   = 0.0
		State.SPAWN_DELAY:        if _spawn_timer   < 0.0: _spawn_timer   = absf(_spawn_timer)
		State.DESPAWNED:          if _respawn_timer < 0.0: _respawn_timer = absf(_respawn_timer)
		_: pass

func force_reset_spawn_cycle() -> void:
	if is_instance_valid(_entity_node): _entity_node.queue_free(); _entity_node = null
	_state = State.WAITING_FOR_ACTIVE; _move_mode = MoveMode.WANDER
	_spawn_timer = 0.0; _despawn_timer = 0.0; _respawn_timer = 0.0; _repath_timer = 0.0
	_wander_timer = 0.0; _step_timer = 0.0; _los_react_timer = 0.0
	_skip_active_wait = false; _current_speed = SPEED_SLOW; _target_speed = SPEED_SLOW
	_los_reacting = false; _last_known_player = Vector3.ZERO
	_path.clear(); _current_target_index = 0; _last_path_target = Vector2i(-9999, -9999)
	_prev_player_pos = Vector3.ZERO; _prev_player_basis = Basis.IDENTITY
	_last_position = Vector3.ZERO; _stuck_timer = 0.0; _stuck_repath_count = 0
	_movement_direction = Vector3.ZERO
	_invalidate_cache()
