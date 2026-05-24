class_name ChunkManager
extends Node

# ─────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────

const CHUNK_SIZE      : int = 20
const MINE_COUNT      : int = 40
const RENDER_RADIUS   : int = 1
const DATA_RADIUS     : int = 2
const TILES_PER_FRAME : int = 30
const BUFFER_INTERVAL : float = 0.25
const FLOOD_RETRY_DELAY : float = 1.0

# Thread pool settings
const THREAD_POOL_SIZE : int = 4

# AFTER
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

# ─────────────────────────────────────────────────────────────
# EXPORTED VARIABLES
# ─────────────────────────────────────────────────────────────

@export var tile_scene : PackedScene

# ─────────────────────────────────────────────────────────────
# CORE STATE VARIABLES
# ─────────────────────────────────────────────────────────────

var chunks        : Dictionary = {}
var chunk_nodes   : Dictionary = {}
var loaded_chunks : Dictionary = {}

var pulse_time    : float = 0.0

var current_chunk : Vector2i = Vector2i.ZERO
var _global_seed  : int      = 0

var _loading_screen = null

# ─────────────────────────────────────────────────────────────
# ASYNC SPAWNING STATE
# ─────────────────────────────────────────────────────────────

var _spawn_queue : Array[Chunk] = []
var _is_spawning : bool = false
var _batch_chunk : Chunk = null
var _batch_node  : Node3D = null
var _batch_index : int = 0

# ─────────────────────────────────────────────────────────────
# BUFFER & STREAMING STATE
# ─────────────────────────────────────────────────────────────

var _buffer_timer : float = 0.0
var _last_chunk_for_buffer : Vector2i = Vector2i.ZERO

# ─────────────────────────────────────────────────────────────
# LOADING TRACKING STATE
# ─────────────────────────────────────────────────────────────

const SPAWN_CHUNK_COUNT : int = 9

var _spawn_required  : Dictionary = {}
var _spawn_completed : Dictionary = {}
var spawn_ready      : bool       = false
var _loading_complete : bool      = false

# ─────────────────────────────────────────────────────────────
# THREAD POOL STATE
# ─────────────────────────────────────────────────────────────

var _pending_data_chunks : Dictionary = {}
var _completed_data_chunks : Array[Vector2i] = []
var _thread_mutex : Mutex = Mutex.new()
var _thread_semaphore : Semaphore = Semaphore.new()
var _threads_active : bool = true

# ─────────────────────────────────────────────────────────────
# FLOOD REVEAL STATE
# ─────────────────────────────────────────────────────────────

var _in_flood_reveal : bool = false
var _flood_retry_count : int = 0
const MAX_FLOOD_RETRIES : int = 10
var _pending_flood_reveal : bool = false
var _pending_start_cp : Vector2i = Vector2i.ZERO
var _pending_start_lx : int = 0
var _pending_start_lz : int = 0
var _is_retrying : bool = false
var _retry_timer : float = 0.0
var _is_initial_flood_reveal : bool = false  # ADDED: Track initial vs player-triggered

# ─────────────────────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────────────────────

signal map_updated
signal chunk_load_started(chunk_pos: Vector2i)
signal chunk_load_completed(chunk_pos: Vector2i)
signal tile_revealed(chunk_pos: Vector2i, local_x: int, local_z: int, is_mine: bool)
signal tile_flagged(chunk_pos: Vector2i, local_x: int, local_z: int, flagged: bool)
signal spawn_chunks_ready
signal spawn_chunk_progress(completed: int, total: int)

# ─────────────────────────────────────────────────────────────
# LIFECYCLE METHODS
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_validate_dependencies()
	_initialize_seed()
	_initialize_spawn_tracking()
	_connect_signals()
	_initialize_world()
	_find_loading_screen()
	_last_chunk_for_buffer = current_chunk
	_start_thread_pool()

func _exit_tree() -> void:
	_stop_thread_pool()

func _process(delta: float) -> void:
	_update_pulse_animation(delta)
	_process_retry_timer(delta)
	_process_completed_chunks()

# ─────────────────────────────────────────────────────────────
# THREAD POOL MANAGEMENT
# ─────────────────────────────────────────────────────────────

func _start_thread_pool() -> void:
	_threads_active = true
	for i in range(THREAD_POOL_SIZE):
		var thread := Thread.new()
		thread.start(_thread_worker.bind(i))
		print("[ChunkManager] Started worker thread ", i)

func _stop_thread_pool() -> void:
	_threads_active = false
	for i in range(THREAD_POOL_SIZE * 2):
		_thread_semaphore.post()
	
	await get_tree().create_timer(0.5).timeout
	print("[ChunkManager] Thread pool stopped")

func _thread_worker(thread_id: int) -> void:
	while _threads_active:
		_thread_semaphore.wait()
		if not _threads_active:
			break
		
		var chunk_pos : Vector2i = Vector2i.ZERO
		var should_generate : bool = false
		
		_thread_mutex.lock()
		for cp in _pending_data_chunks.keys():
			if _pending_data_chunks[cp] == false:
				chunk_pos = cp
				_pending_data_chunks[cp] = true
				should_generate = true
				break
		_thread_mutex.unlock()
		
		if should_generate:
			var chunk := Chunk.new()
			chunk.chunk_pos = chunk_pos
			chunk.generate(_global_seed, _make_mine_lookup_static(_global_seed))
			
			_thread_mutex.lock()
			chunks[chunk_pos] = chunk
			_completed_data_chunks.append(chunk_pos)
			_thread_mutex.unlock()
			
			call_deferred("_process_completed_chunks")

func _process_completed_chunks() -> void:
	_thread_mutex.lock()
	var completed := _completed_data_chunks.duplicate()
	_completed_data_chunks.clear()
	_thread_mutex.unlock()
	
	for cp in completed:
		if chunks.has(cp):
			_thread_mutex.lock()
			_pending_data_chunks.erase(cp)
			_thread_mutex.unlock()
			_enqueue_chunk_visual(chunks[cp])

# ─────────────────────────────────────────────────────────────
# INITIALIZATION & SETUP
# ─────────────────────────────────────────────────────────────

func _validate_dependencies() -> void:
	if tile_scene == null:
		push_error("ChunkManager: tile_scene missing")
		return

func _initialize_seed() -> void:
	randomize()
	_global_seed = (randi() << 32) | randi()

func _initialize_spawn_tracking() -> void:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_spawn_required[Vector2i(dx, dz)] = true

func _connect_signals() -> void:
	spawn_chunks_ready.connect(_on_spawn_chunks_ready)

func _initialize_world() -> void:
	var pos : Vector2i = Vector2i.ZERO
	var mid : int = CHUNK_SIZE / 2

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cp : Vector2i = Vector2i(dx, dz)
			var chunk : Chunk = Chunk.new()
			chunk.chunk_pos = cp

			if cp == Vector2i.ZERO:
				for sdx in range(-1, 2):
					for sdz in range(-1, 2):
						chunk.safe_cells.append(Vector2i(mid + sdx, mid + sdz))

			chunk.generate(_global_seed, _make_mine_lookup())
			chunks[cp] = chunk

	current_chunk = pos
	_update_chunk_streaming()

	_pending_flood_reveal = true
	_pending_start_cp = pos
	_pending_start_lx = mid
	_pending_start_lz = mid

# ─────────────────────────────────────────────────────────────
# UPDATE LOOPS
# ─────────────────────────────────────────────────────────────

func _update_pulse_animation(delta: float) -> void:
	pulse_time += delta * 3.0

func _process_retry_timer(delta: float) -> void:
	if _is_retrying:
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			_is_retrying = false
			_execute_flood_reveal_with_retry()

# ─────────────────────────────────────────────────────────────
# WORLD GENERATION (MINE ORACLE)
# ─────────────────────────────────────────────────────────────

const _PX         : int   = 1000003
const _PZ         : int   = 999983
const _MINE_DENSITY : float = float(MINE_COUNT) / float(CHUNK_SIZE * CHUNK_SIZE)

func _is_world_mine(wx: int, wz: int) -> bool:
	var threshold : int = int(_MINE_DENSITY * 0x7FFFFFFF)
	var h : int = hash(_global_seed ^ (wx * _PX) ^ (wz * _PZ))
	return absi(h) % 0x7FFFFFFF < threshold

func _make_mine_lookup() -> Callable:
	return func(wx: int, wz: int) -> bool:
		return _is_world_mine(wx, wz)

func _make_mine_lookup_static(seed: int) -> Callable:
	return func(wx: int, wz: int) -> bool:
		var threshold : int = int(_MINE_DENSITY * 0x7FFFFFFF)
		var h : int = hash(seed ^ (wx * _PX) ^ (wz * _PZ))
		return absi(h) % 0x7FFFFFFF < threshold

# ─────────────────────────────────────────────────────────────
# CHUNK LOADING & SPAWNING
# ─────────────────────────────────────────────────────────────

func load_chunk(pos: Vector2i) -> void:
	if chunks.has(pos):
		if not chunk_nodes.has(pos):
			_enqueue_chunk_visual(chunks[pos])
		return
	
	if _pending_data_chunks.has(pos):
		return
	
	_thread_mutex.lock()
	if not _pending_data_chunks.has(pos):
		_pending_data_chunks[pos] = false
		_thread_semaphore.post()
	_thread_mutex.unlock()

func _enqueue_chunk_visual(chunk: Chunk) -> void:
	for c in _spawn_queue:
		if c.chunk_pos == chunk.chunk_pos:
			return

	if _batch_chunk != null and _batch_chunk.chunk_pos == chunk.chunk_pos:
		return

	chunk.is_reload = loaded_chunks.has(chunk.chunk_pos)
	_spawn_queue.append(chunk)

	if not _is_spawning:
		_process_spawn_queue()

func _process_spawn_queue() -> void:
	if _spawn_queue.is_empty():
		_is_spawning = false
		return

	_is_spawning = true
	_batch_chunk = _spawn_queue.pop_front()

	if not chunks.has(_batch_chunk.chunk_pos):
		_process_spawn_queue()
		return

	_batch_node = Node3D.new()
	_batch_node.name = "Chunk_%d_%d" % [_batch_chunk.chunk_pos.x, _batch_chunk.chunk_pos.y]
	add_child(_batch_node)

	_batch_index = 0

	emit_signal("chunk_load_started", _batch_chunk.chunk_pos)
	_spawn_batch()
	_try_finish_loading()

func _spawn_batch() -> void:
	if _batch_chunk == null or not is_instance_valid(_batch_node):
		return

	var total : int = CHUNK_SIZE * CHUNK_SIZE
	var end   : int = mini(_batch_index + TILES_PER_FRAME, total)

	var cp       : Vector2i = _batch_chunk.chunk_pos
	var base_pos : Vector3  = Vector3(cp.x * CHUNK_SIZE, 1.5, cp.y * CHUNK_SIZE)
	var should_animate : bool = not _batch_chunk.is_reload

	for i in range(_batch_index, end):
		var x : int = i / CHUNK_SIZE
		var z : int = i % CHUNK_SIZE

		var idx      : int  = x * Chunk.SIZE + z
		var is_mine  : bool = _batch_chunk.tile_mine[idx]     == 1
		var number   : int  = _batch_chunk.tile_number[idx]
		var revealed : bool = _batch_chunk.tile_revealed[idx] == 1
		var flagged  : bool = _batch_chunk.tile_flagged[idx]  == 1

		var tile : Node3D = tile_scene.instantiate()
		_batch_node.add_child(tile)

		tile.position    = base_pos + Vector3(x + 0.5, 1.5, z + 0.5)
		tile.grid_manager = self
		tile.chunk_pos   = cp
		tile.grid_x      = x
		tile.grid_z      = z

		_sync_tile_visual_from_data(tile, is_mine, number, revealed, flagged, should_animate)

	_batch_index = end

	if _batch_index >= total:
		if not chunks.has(cp):
			if is_instance_valid(_batch_node):
				_batch_node.queue_free()
			_batch_chunk = null
			_batch_node = null
			if is_inside_tree():
				await get_tree().process_frame
			_process_spawn_queue()
			return

		chunk_nodes[cp] = _batch_node
		loaded_chunks[cp] = true

		emit_signal("chunk_load_completed", cp)
		_update_spawn_progress(cp)
		_try_finish_loading()
		
		_batch_chunk = null
		_batch_node  = null

		if not is_inside_tree():
			return
		await get_tree().process_frame
		_process_spawn_queue()
	else:
		if not is_inside_tree():
			return
		await get_tree().process_frame
		_spawn_batch()

func _update_spawn_progress(cp: Vector2i) -> void:
	if not spawn_ready and _spawn_required.has(cp) and not _spawn_completed.has(cp):
		_spawn_completed[cp] = true
		var done  : int = _spawn_completed.size()
		var total_req : int = SPAWN_CHUNK_COUNT
		emit_signal("spawn_chunk_progress", done, total_req)
		if done >= total_req:
			spawn_ready = true
			emit_signal("spawn_chunks_ready")

func _on_spawn_chunks_ready() -> void:
	if _pending_flood_reveal:
		_pending_flood_reveal = false
		# Set flag for initial flood reveal (no animation)
		_is_initial_flood_reveal = true
		_execute_flood_reveal_with_retry()
		_is_initial_flood_reveal = false
		print("[ChunkManager] 3x3 chunks ready - executing initial flood reveal")
	
	if _loading_complete and _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.dismiss()

# ─────────────────────────────────────────────────────────────
# FLOOD REVEAL SYSTEM
# ─────────────────────────────────────────────────────────────

func _pack_key(cp: Vector2i, lx: int, lz: int) -> int:
	return (int(cp.x) & 0xFFFF) << 48 | (int(cp.y) & 0xFFFF) << 32 | (lx & 0xFFFF) << 16 | (lz & 0xFFFF)

func _execute_flood_reveal_with_retry() -> void:
	_flood_reveal(_pending_start_cp, _pending_start_lx, _pending_start_lz)
	
	if not is_inside_tree():
		return
	await get_tree().process_frame
	
	if not _has_3x3_clear_area(_pending_start_cp, _pending_start_lx, _pending_start_lz):
		_flood_retry_count += 1
		
		if _flood_retry_count <= MAX_FLOOD_RETRIES:
			print("[ChunkManager] No 3x3 clear area detected! Retry %d/%d..." % [_flood_retry_count, MAX_FLOOD_RETRIES])
			emit_signal("spawn_chunk_progress", 9 + _flood_retry_count, 9 + MAX_FLOOD_RETRIES)
			_is_retrying = true
			_retry_timer = FLOOD_RETRY_DELAY
			_regenerate_world()
			return
		else:
			print("[ChunkManager] ERROR: Failed to create 3x3 clear area after %d attempts! Forcing generation layout..." % MAX_FLOOD_RETRIES)
			_force_3x3_clear_area(_pending_start_cp, _pending_start_lx, _pending_start_lz)
			_loading_complete = true
	else:
		print("[ChunkManager] 3x3 clear area verified successfully on attempt: ", _flood_retry_count)
		_loading_complete = true
		
	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.dismiss()

func _regenerate_world() -> void:
	get_tree().paused = true
	
	for cp in chunk_nodes.keys():
		if is_instance_valid(chunk_nodes[cp]):
			chunk_nodes[cp].queue_free()
	
	chunks.clear()
	chunk_nodes.clear()
	loaded_chunks.clear()
	_spawn_completed.clear()
	_spawn_queue.clear()
	
	_is_spawning = false
	_batch_chunk = null
	_batch_node = null
	spawn_ready = false
	_loading_complete = false
	
	_global_seed = (randi() << 32) | randi()
	_initialize_world()
	
	for cp in chunks.keys():
		_enqueue_chunk_visual(chunks[cp])

func _has_3x3_clear_area(center_cp: Vector2i, center_lx: int, center_lz: int) -> bool:
	var base_gx = center_cp.x * CHUNK_SIZE + center_lx
	var base_gz = center_cp.y * CHUNK_SIZE + center_lz
	
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var gx = base_gx + dx
			var gz = base_gz + dz
			var cell = get_map_cell(gx, gz)
			if cell["state"] == "mine" or cell["state"] == "hidden":
				return false
	return true

func _force_3x3_clear_area(center_cp: Vector2i, center_lx: int, center_lz: int) -> void:
	var base_gx = center_cp.x * CHUNK_SIZE + center_lx
	var base_gz = center_cp.y * CHUNK_SIZE + center_lz
	
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var gx = base_gx + dx
			var gz = base_gz + dz
			var cp = Vector2i(floori(float(gx) / CHUNK_SIZE), floori(float(gz) / CHUNK_SIZE))
			var lx = posmod(gx, CHUNK_SIZE)
			var lz = posmod(gz, CHUNK_SIZE)
			
			if chunks.has(cp):
				var chunk = chunks[cp]
				var idx = lx * Chunk.SIZE + lz
				
				if chunk.tile_mine[idx] == 1:
					chunk.tile_mine[idx] = 0
					chunk.tile_number[idx] = 0
					_recount_numbers_around(cp, lx, lz)
				
				if chunk.tile_revealed[idx] == 0:
					chunk.tile_revealed[idx] = 1
					var tile = get_tile_node(cp, lx, lz)
					if tile:
						_sync_tile_visual_from_data(tile, false, 0, true, false, not _is_initial_flood_reveal)
	
	print("[ChunkManager] Forced 3x3 clear area as fallback configuration.")

func _recount_numbers_around(cp: Vector2i, lx: int, lz: int) -> void:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var nx = lx + dx
			var nz = lz + dz
			var n_cp = cp
			
			if nx < 0:
				n_cp.x -= 1
				nx += CHUNK_SIZE
			elif nx >= CHUNK_SIZE:
				n_cp.x += 1
				nx -= CHUNK_SIZE
			
			if nz < 0:
				n_cp.y -= 1
				nz += CHUNK_SIZE
			elif nz >= CHUNK_SIZE:
				n_cp.y += 1
				nz -= CHUNK_SIZE
			
			if chunks.has(n_cp):
				var n_chunk = chunks[n_cp]
				var n_idx = nx * Chunk.SIZE + nz
				
				if n_chunk.tile_mine[n_idx] == 0:
					var count = 0
					for sx in range(-1, 2):
						for sz in range(-1, 2):
							if sx == 0 and sz == 0:
								continue
							var wx = nx + sx
							var wz = nz + sz
							var w_cp = n_cp
							
							if wx < 0:
								w_cp.x -= 1
								wx += CHUNK_SIZE
							elif wx >= CHUNK_SIZE:
								w_cp.x += 1
								wx -= CHUNK_SIZE
							
							if wz < 0:
								w_cp.y -= 1
								wz += CHUNK_SIZE
							elif wz >= CHUNK_SIZE:
								w_cp.y += 1
								wz -= CHUNK_SIZE
							
							if chunks.has(w_cp):
								var w_idx = wx * Chunk.SIZE + wz
								if chunks[w_cp].tile_mine[w_idx] == 1:
									count += 1
					
					n_chunk.tile_number[n_idx] = count

# OPTIMIZED: Flood reveal with animation control
func _flood_reveal(start_cp: Vector2i, start_lx: int, start_lz: int) -> void:
	_in_flood_reveal = true
	
	var queue: Array = []
	var head: int = 0
	queue.append([start_cp, start_lx, start_lz])
	
	var visited : Dictionary = {}

	while head < queue.size():
		var entry = queue[head]
		head += 1
		
		var cp    : Vector2i = entry[0]
		var lx    : int      = entry[1]
		var lz    : int      = entry[2]

		var key : int = _pack_key(cp, lx, lz)
		if visited.has(key):
			continue
		visited[key] = true

		if not chunks.has(cp):
			continue

		var chunk : Chunk = chunks[cp]
		var idx   : int   = lx * Chunk.SIZE + lz

		if chunk.tile_revealed[idx] == 1 or chunk.tile_mine[idx] == 1:
			continue

		chunk.tile_revealed[idx] = 1
		chunk.tile_flagged[idx]  = 0
		emit_signal("tile_revealed", cp, lx, lz, false)

		var tile = get_tile_node(cp, lx, lz)
		if tile:
			# FIX: Use _is_initial_flood_reveal to determine if we should animate
			var should_animate = not _is_initial_flood_reveal
			_sync_tile_visual_from_data(tile, false, chunk.tile_number[idx], true, false, should_animate)

		if chunk.tile_number[idx] != 0:
			continue

		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if dx == 0 and dz == 0:
					continue

				var nx   : int     = lx + dx
				var nz   : int     = lz + dz
				var n_cp : Vector2i = cp

				if nx < 0:
					n_cp.x -= 1
					nx += CHUNK_SIZE
				elif nx >= CHUNK_SIZE:
					n_cp.x += 1
					nx -= CHUNK_SIZE

				if nz < 0:
					n_cp.y -= 1
					nz += CHUNK_SIZE
				elif nz >= CHUNK_SIZE:
					n_cp.y += 1
					nz -= CHUNK_SIZE

				queue.append([n_cp, nx, nz])

	_in_flood_reveal = false
	emit_signal("map_updated")

# ─────────────────────────────────────────────────────────────
# TILE INTERACTIONS
# ─────────────────────────────────────────────────────────────

func reveal_tile(cp: Vector2i, lx: int, lz: int) -> void:
	if not chunks.has(cp):
		return

	var chunk : Chunk = chunks[cp]
	var idx   : int   = lx * Chunk.SIZE + lz

	if chunk.tile_revealed[idx] == 1 or chunk.tile_flagged[idx] == 1:
		return

	if chunk.tile_mine[idx] == 1:
		chunk.tile_revealed[idx] = 1
		var tile = get_tile_node(cp, lx, lz)
		if tile:
			tile.reveal(Color.RED, "💥")
		emit_signal("tile_revealed", cp, lx, lz, true)
		emit_signal("map_updated")
		return

	# Player-triggered flood reveal should NOT set _is_initial_flood_reveal
	# So the flag remains false, and should_animate will be true
	_flood_reveal(cp, lx, lz)
	emit_signal("map_updated")

func flag_tile(cp: Vector2i, lx: int, lz: int) -> void:
	var chunk = chunks.get(cp)
	if not chunk:
		return

	var idx : int = lx * Chunk.SIZE + lz
	if chunk.tile_revealed[idx] == 1:
		return

	var new_flag : int = 1 if chunk.tile_flagged[idx] == 0 else 0
	chunk.tile_flagged[idx] = new_flag

	var tile = get_tile_node(cp, lx, lz)
	if tile:
		tile.is_flagged = new_flag == 1
		if new_flag == 1:
			tile.set_flagged_visual()
		else:
			tile.clear_flagged_visual()

	emit_signal("tile_flagged", cp, lx, lz, new_flag == 1)
	emit_signal("map_updated")

# ─────────────────────────────────────────────────────────────
# TILE VISUAL SYNC
# ─────────────────────────────────────────────────────────────

func _sync_tile_visual_from_data(tile: Node, is_mine: bool, number: int, revealed: bool, flagged: bool, should_animate: bool = true) -> void:
	tile.is_mine       = is_mine
	tile.adjacent_mines = number
	tile.is_revealed   = revealed
	tile.is_flagged    = flagged

	if revealed:
		if is_mine:
			if should_animate and not flagged:
				tile.reveal(Color.RED, "💥")
			else:
				tile.set_revealed_no_animation(Color.RED, "💥")
		elif number == 0:
			if should_animate and not flagged:
				tile.reveal(Color(0.8, 0.8, 0.8), "")
			else:
				tile.set_revealed_no_animation(Color(0.8, 0.8, 0.8), "")
		else:
			var color = COLORS.get(number, Color.WHITE)
			if should_animate and not flagged:
				tile.reveal(color, str(number))
			else:
				tile.set_revealed_no_animation(color, str(number))
	elif flagged:
		tile.set_flagged_visual()

func _sync_tile_visual(tile: Node, data: Dictionary, should_animate: bool = true) -> void:
	_sync_tile_visual_from_data(tile, data["is_mine"], data["number"], data["revealed"], data["flagged"], should_animate)

# ─────────────────────────────────────────────────────────────
# CHUNK STREAMING SYSTEM
# ─────────────────────────────────────────────────────────────

func update_player_position(world_pos: Vector3, delta: float, _velocity: Vector3 = Vector3.ZERO) -> void:
	var new_chunk : Vector2i = Vector2i(
		floori(world_pos.x / CHUNK_SIZE),
		floori(world_pos.z / CHUNK_SIZE)
	)

	var chunk_changed := new_chunk != current_chunk
	
	if chunk_changed:
		current_chunk = new_chunk
		_update_chunk_streaming()
		emit_signal("map_updated")

	# Only generate buffer chunks if chunk changed OR timer expired
	if chunk_changed:
		_generate_buffer_chunks()
		_buffer_timer = BUFFER_INTERVAL
		_last_chunk_for_buffer = current_chunk
	else:
		_buffer_timer -= delta
		if _buffer_timer <= 0.0:
			_generate_buffer_chunks()
			_buffer_timer = BUFFER_INTERVAL
		
	# Ensure missing render chunks are retried
	for dx in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
		for dz in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
			var cp := current_chunk + Vector2i(dx, dz)
			if chunks.has(cp) and not chunk_nodes.has(cp):
				load_chunk(cp)

func _generate_buffer_chunks() -> void:
	if _last_chunk_for_buffer == current_chunk and _buffer_timer > BUFFER_INTERVAL * 0.5:
		return
	
	_last_chunk_for_buffer = current_chunk
	
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var cp : Vector2i = current_chunk + Vector2i(dx, dz)
			if not chunks.has(cp) and not _pending_data_chunks.has(cp):
				load_chunk(cp)  # This will queue for thread pool

func _update_chunk_streaming() -> void:
	var active_data   : Dictionary = {}
	var active_render : Dictionary = {}

	for dx in range(-DATA_RADIUS, DATA_RADIUS + 1):
		for dz in range(-DATA_RADIUS, DATA_RADIUS + 1):
			var cp : Vector2i = current_chunk + Vector2i(dx, dz)
			active_data[cp] = true
			if abs(dx) <= RENDER_RADIUS and abs(dz) <= RENDER_RADIUS:
				active_render[cp] = true

	for cp in active_render.keys():
		load_chunk(cp)

	for cp in chunk_nodes.keys():
		if not active_render.has(cp):
			_unload_visual(cp)

	var to_remove : Array = []
	for cp in chunks.keys():
		if not active_data.has(cp):
			to_remove.append(cp)
	for cp in to_remove:
		if _batch_chunk != null and _batch_chunk.chunk_pos == cp:
			continue
		chunks.erase(cp)

func _unload_visual(cp: Vector2i) -> void:
	if _batch_chunk != null and _batch_chunk.chunk_pos == cp:
		return

	if chunk_nodes.has(cp):
		loaded_chunks[cp] = true

		if is_instance_valid(chunk_nodes[cp]):
			chunk_nodes[cp].queue_free()

		chunk_nodes.erase(cp)

	_spawn_queue = _spawn_queue.filter(func(c): return c.chunk_pos != cp)

	if loaded_chunks.size() > 200:
		var to_prune : Array = []
		for lcp in loaded_chunks.keys():
			if abs(lcp.x - current_chunk.x) > 10 or abs(lcp.y - current_chunk.y) > 10:
				to_prune.append(lcp)
		for lcp in to_prune:
			loaded_chunks.erase(lcp)

# ─────────────────────────────────────────────────────────────
# PUBLIC QUERY METHODS
# ─────────────────────────────────────────────────────────────

func get_tile_data(cp: Vector2i, lx: int, lz: int) -> Variant:
	if not chunks.has(cp):
		return null
	var chunk : Chunk = chunks[cp]
	var idx   : int   = lx * Chunk.SIZE + lz
	return {
		"is_mine" : chunk.tile_mine[idx]     == 1,
		"number"  : chunk.tile_number[idx],
		"revealed": chunk.tile_revealed[idx] == 1,
		"flagged" : chunk.tile_flagged[idx]  == 1,
	}

func get_tile_node(cp: Vector2i, lx: int, lz: int) -> Node:
	var idx : int = lx * CHUNK_SIZE + lz

	if chunk_nodes.has(cp):
		var node : Node3D = chunk_nodes[cp]
		if idx >= node.get_child_count():
			return null
		return node.get_child(idx)

	if _batch_chunk != null and _batch_chunk.chunk_pos == cp \
			and is_instance_valid(_batch_node) and idx < _batch_index:
		if idx >= _batch_node.get_child_count():
			return null
		return _batch_node.get_child(idx)

	return null

func get_map_cell(gx: int, gz: int) -> Dictionary:
	var cp : Vector2i = Vector2i(
		floori(float(gx) / CHUNK_SIZE),
		floori(float(gz) / CHUNK_SIZE)
	)
	var lx : int = posmod(gx, CHUNK_SIZE)
	var lz : int = posmod(gz, CHUNK_SIZE)

	if not chunks.has(cp):
		return {"state": "hidden", "number": 0}

	var chunk : Chunk = chunks[cp]
	var idx   : int   = lx * Chunk.SIZE + lz

	var state : String = "hidden"
	if chunk.tile_revealed[idx] == 1:
		state = "mine" if chunk.tile_mine[idx] == 1 else "revealed"
	elif chunk.tile_flagged[idx] == 1:
		state = "flagged"

	return {"state": state, "number": chunk.tile_number[idx]}

func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(floori(world_pos.x), floori(world_pos.z))

func is_in_flood_reveal() -> bool:
	return _in_flood_reveal

func get_pulse_time() -> float:
	return pulse_time

func is_loading_complete() -> bool:
	return _loading_complete
	
func _try_finish_loading() -> void:
	if _loading_complete:
		return

	if not spawn_ready:
		return

	if not are_spawn_chunks_fully_loaded():
		return

	_loading_complete = true

	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.dismiss()
	else:
		push_error("ChunkManager: Loading screen not found - cannot dismiss!")

	emit_signal("spawn_chunks_ready")
	
func are_spawn_chunks_fully_loaded() -> bool:
	for cp in _spawn_required.keys():
		if not chunk_nodes.has(cp):
			return false
	return true

func _find_loading_screen() -> void:
	_loading_screen = get_parent().get_node_or_null("LoadingScreen")
	if not _loading_screen:
		push_warning("ChunkManager: Could not find LoadingScreen node!")
		
		
