extends Resource
class_name Chunk

# ─────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────

# MUST match ChunkManager.CHUNK_SIZE
const SIZE : int = 16 

# ─────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────

var chunk_pos : Vector2i
var generated : bool = false
var is_reload : bool = false

# Legacy support for safe_cells (The actual safe-zone logic 
# should now be handled by the oracle in ChunkManager.gd)
var safe_cells : Array = []

# Flat Tile Storage (index = x * SIZE + z)
var tile_mine     : PackedByteArray
var tile_number   : PackedByteArray
var tile_revealed : PackedByteArray
var tile_flagged  : PackedByteArray

# ─────────────────────────────────────────────────────────────
# PUBLIC METHODS
# ─────────────────────────────────────────────────────────────

## Entry point for generating chunk data.
## mine_lookup: Callable(world_x, world_z) -> bool
func generate(_global_seed: int, mine_lookup: Callable) -> void:
	if generated:
		return

	var total := SIZE * SIZE
	
	# Initialize arrays
	tile_mine     = PackedByteArray(); tile_mine.resize(total);     tile_mine.fill(0)
	tile_number   = PackedByteArray(); tile_number.resize(total);   tile_number.fill(0)
	tile_revealed = PackedByteArray(); tile_revealed.resize(total); tile_revealed.fill(0)
	tile_flagged  = PackedByteArray(); tile_flagged.resize(total);  tile_flagged.fill(0)

	_place_mines(mine_lookup)
	_calculate_numbers(mine_lookup)

	generated = true

## Returns a dictionary of tile data for a local coordinate.
func get_tile_dict(lx: int, lz: int) -> Dictionary:
	var i := lx * SIZE + lz
	if i < 0 or i >= tile_mine.size():
		return {}
		
	return {
		"is_mine"  : tile_mine[i]   == 1,
		"number"   : tile_number[i],
		"revealed" : tile_revealed[i] == 1,
		"flagged"  : tile_flagged[i]  == 1,
	}

# ─────────────────────────────────────────────────────────────
# PRIVATE GENERATION LOGIC
# ─────────────────────────────────────────────────────────────

func _place_mines(mine_lookup: Callable) -> void:
	var base_wx : int = chunk_pos.x * SIZE
	var base_wz : int = chunk_pos.y * SIZE

	for x in range(SIZE):
		for z in range(SIZE):
			var wx : int = base_wx + x
			var wz : int = base_wz + z

			# Consult the global oracle for mine placement
			if mine_lookup.call(wx, wz):
				tile_mine[x * SIZE + z] = 1


func _calculate_numbers(mine_lookup: Callable) -> void:
	var base_wx : int = chunk_pos.x * SIZE
	var base_wz : int = chunk_pos.y * SIZE

	for x in range(SIZE):
		for z in range(SIZE):
			var idx = x * SIZE + z
			
			# If this tile is a mine, we don't need a number label
			if tile_mine[idx] == 1:
				continue

			var count := 0
			# Check all 8 neighbors in world space
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					
					var nx : int = base_wx + x + dx
					var nz : int = base_wz + z + dz
					
					# Query the oracle for neighbors. 
					# This ensures seamless borders between chunks.
					if mine_lookup.call(nx, nz):
						count += 1

			tile_number[idx] = count

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

func _in_bounds(x: int, z: int) -> bool:
	return x >= 0 and x < SIZE and z >= 0 and z < SIZE
