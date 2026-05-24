extends Resource
class_name Chunk

const SIZE       := 20
const MINE_COUNT := 40

# Mine density as a ratio — used by the global hash check.
# 40 mines / 400 tiles = 0.10 (10 %).
const MINE_DENSITY : float = float(MINE_COUNT) / float(SIZE * SIZE)

var chunk_pos : Vector2i
var generated : bool = false
var is_reload : bool = false

# Tiles pre-marked safe before generation (spawn flood zone only).
# These are in LOCAL coords (Vector2i).
var safe_cells : Array = []

# ─────────────────────────────────────────────────────────────
# FLAT TILE STORAGE  (x * SIZE + z)
# ─────────────────────────────────────────────────────────────

var tile_mine     : PackedByteArray
var tile_number   : PackedByteArray
var tile_revealed : PackedByteArray
var tile_flagged  : PackedByteArray

# ─────────────────────────────────────────────────────────────
# COMPAT SHIM
# ─────────────────────────────────────────────────────────────

func get_tile_dict(lx: int, lz: int) -> Dictionary:
	var i := lx * SIZE + lz
	return {
		"is_mine"  : tile_mine[i]   == 1,
		"number"   : tile_number[i],
		"revealed" : tile_revealed[i] == 1,
		"flagged"  : tile_flagged[i]  == 1,
	}

# ─────────────────────────────────────────────────────────────
# GENERATE
#
# global_seed  : the single world seed from ChunkManager
# mine_lookup  : Callable(world_x: int, world_z: int) -> bool
#                Returns true if that world-space tile is a mine.
#                Provided by ChunkManager so that _calculate_numbers
#                can peek across chunk borders without this class
#                needing a back-reference to the manager.
# ─────────────────────────────────────────────────────────────

func generate(global_seed: int, mine_lookup: Callable) -> void:
	if generated:
		return

	var total := SIZE * SIZE
	tile_mine     = PackedByteArray(); tile_mine.resize(total);     tile_mine.fill(0)
	tile_number   = PackedByteArray(); tile_number.resize(total);   tile_number.fill(0)
	tile_revealed = PackedByteArray(); tile_revealed.resize(total); tile_revealed.fill(0)
	tile_flagged  = PackedByteArray(); tile_flagged.resize(total);  tile_flagged.fill(0)

	# Build flat safe-cell set for O(1) lookup
	var safe_flat := PackedByteArray(); safe_flat.resize(total); safe_flat.fill(0)
	for v in safe_cells:
		safe_flat[v.x * SIZE + v.y] = 1

	_place_mines(global_seed, safe_flat)
	_calculate_numbers(mine_lookup)

	generated = true

# ─────────────────────────────────────────────────────────────
# MINE PLACEMENT  — global hash, no RNG state, no chunk ordering
#
# For every tile we compute:
#   hash(global_seed XOR (world_x * LARGE_PRIME) XOR world_z)
# and compare it against the density threshold.  The result is
# identical no matter which chunk generates first or last.
# ─────────────────────────────────────────────────────────────

# Two large primes to spread bits across both axes independently.
const _PX : int = 1000003
const _PZ : int = 999983

func _place_mines(global_seed: int, safe_flat: PackedByteArray) -> void:
	var base_wx : int = chunk_pos.x * SIZE
	var base_wz : int = chunk_pos.y * SIZE

	# Threshold in [0, 0x7FFFFFFF] space — hash() returns a non-negative int.
	var threshold : int = int(MINE_DENSITY * 0x7FFFFFFF)

	for x in range(SIZE):
		for z in range(SIZE):
			if safe_flat[x * SIZE + z] == 1:
				continue

			var wx : int = base_wx + x
			var wz : int = base_wz + z

			# XOR-mix seed with scaled coordinates then hash.
			# wrapping_* keeps arithmetic in 64-bit without overflow errors.
			var h : int = hash(global_seed ^ (wx * _PX) ^ (wz * _PZ))

			# hash() can return negative; abs() keeps the comparison safe.
			if absi(h) % 0x7FFFFFFF < threshold:
				tile_mine[x * SIZE + z] = 1

# ─────────────────────────────────────────────────────────────
# NUMBER CALCULATION
#
# Uses mine_lookup(world_x, world_z) so border tiles correctly
# count mines that live in neighbouring chunks.
# ─────────────────────────────────────────────────────────────

func _calculate_numbers(mine_lookup: Callable) -> void:
	var base_wx : int = chunk_pos.x * SIZE
	var base_wz : int = chunk_pos.y * SIZE

	for x in range(SIZE):
		for z in range(SIZE):
			if tile_mine[x * SIZE + z] == 1:
				continue

			var count := 0
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					if mine_lookup.call(base_wx + x + dx, base_wz + z + dz):
						count += 1

			tile_number[x * SIZE + z] = count

# ─────────────────────────────────────────────────────────────
# FLOOD COLLECT  (spawn safe-area pre-reveal)
# ─────────────────────────────────────────────────────────────

func flood_collect_clear(sx: int, sz: int) -> Array:
	var result : Array = []
	if not _in_bounds(sx, sz) or tile_mine[sx * SIZE + sz] == 1:
		return result

	var visited := PackedByteArray()
	visited.resize(SIZE * SIZE)
	visited.fill(0)

	var queue : Array[Vector2i] = [Vector2i(sx, sz)]

	while queue.size() > 0:
		var p : Vector2i = queue.pop_front()
		var pi := p.x * SIZE + p.y

		if visited[pi] == 1:
			continue
		visited[pi] = 1

		if tile_mine[pi] == 1:
			continue

		tile_revealed[pi] = 1
		result.append(p)

		if tile_number[pi] == 0:
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					var nx := p.x + dx
					var nz := p.y + dz
					if _in_bounds(nx, nz) and visited[nx * SIZE + nz] == 0:
						queue.append(Vector2i(nx, nz))

	return result

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

func _in_bounds(x: int, z: int) -> bool:
	return x >= 0 and x < SIZE and z >= 0 and z < SIZE
