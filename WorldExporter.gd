# WorldExporter.gd
# Child Node of Main. Press F5 in-game to export.
# Outputs to ~/.local/share/godot/app_userdata/<project>/exports/
#   world_TIMESTAMP.gltf  — 3D mesh, one MultiMesh per colour group, emission baked in
#   world_TIMESTAMP.json  — full tile data (coords, state, number, colour)

extends Node

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────

const EXPORT_HALF : int   = 2        # 4×4 chunk area (2 chunks each direction)
const TILE_SIZE   : float = 1.0
const TILE_GAP    : float = 0.02
const EXPORT_KEY  : int   = KEY_F5

# Emission multipliers per tile category
const EMIT_NUMBERED : float = 2.0    # numbered tiles glow brightest
const EMIT_MINE     : float = 2.5    # mines glow intensely red
const EMIT_FLAGGED  : float = 1.5    # flags glow amber
const EMIT_CLEAR    : float = 0.0    # fully revealed blank tiles — no glow
const EMIT_HIDDEN   : float = 0.0    # unrevealed tiles — no glow

# ─────────────────────────────────────────────────────────────
# PALETTE
# ─────────────────────────────────────────────────────────────

const COLOR_UNREVEALED : Color = Color(0.22, 0.24, 0.27)
const COLOR_CLEAR      : Color = Color(0.80, 0.80, 0.80)
const COLOR_MINE       : Color = Color(0.55, 0.18, 0.18)
const COLOR_FLAGGED    : Color = Color(0.75, 0.65, 0.40)

const NUMBER_COLORS : Dictionary = {
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
# INTERNAL STATE
# ─────────────────────────────────────────────────────────────

var _chunk_manager : ChunkManager = null
var _exporting     : bool         = false

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_chunk_manager = get_parent().get_node_or_null("GridManager")
	if not _chunk_manager:
		push_warning("[WorldExporter] GridManager not found — exports will fail.")
	_chunk_manager = get_parent().get_node_or_null("GridManager")
	print("[WorldExporter] _ready fired. ChunkManager: ", _chunk_manager)
	if not _chunk_manager:
		push_warning("[WorldExporter] GridManager not found — exports will fail.")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == EXPORT_KEY:
			if _exporting:
				print("[WorldExporter] Already exporting, please wait.")
				return
			export_world()

# ─────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────

func export_world() -> void:
	if not _chunk_manager:
		push_error("[WorldExporter] No ChunkManager found.")
		return

	_exporting = true
	print("[WorldExporter] Export started…")

	var records : Array = _collect_tiles()
	if records.is_empty():
		push_warning("[WorldExporter] No tiles in export region.")
		_exporting = false
		return

	print("[WorldExporter] %d tiles collected." % records.size())

	var dir := DirAccess.open("user://")
	if not dir.dir_exists("exports"):
		dir.make_dir("exports")

	var timestamp := Time.get_datetime_string_from_system()\
		.replace(":", "-").replace(" ", "_")
	var base_path := "user://exports/world_%s" % timestamp

	_export_json(records, base_path + ".json")
	await _export_gltf(records, base_path + ".gltf")

	print("[WorldExporter] ✓ Done → %s (.gltf + .json)" % base_path)
	_exporting = false

# ─────────────────────────────────────────────────────────────
# TILE COLLECTION
# ─────────────────────────────────────────────────────────────

func _collect_tiles() -> Array:
	var records : Array    = []
	var cc      : Vector2i = _chunk_manager.current_chunk
	var cs      : int      = _chunk_manager.CHUNK_SIZE

	for cx in range(cc.x - EXPORT_HALF, cc.x + EXPORT_HALF):
		for cz in range(cc.y - EXPORT_HALF, cc.y + EXPORT_HALF):
			var cp := Vector2i(cx, cz)
			if not _chunk_manager.chunks.has(cp):
				continue

			var chunk : Chunk = _chunk_manager.chunks[cp]

			for lx in range(cs):
				for lz in range(cs):
					var idx      : int  = lx * Chunk.SIZE + lz
					var is_mine  : bool = chunk.tile_mine[idx]     == 1
					var number   : int  = chunk.tile_number[idx]
					var revealed : bool = chunk.tile_revealed[idx] == 1
					var flagged  : bool = chunk.tile_flagged[idx]  == 1

					var world_x : int = cp.x * cs + lx
					var world_z : int = cp.y * cs + lz

					var state  : String = _tile_state(is_mine, revealed, flagged)
					var color  : Color  = _tile_color(state, number)
					var emit   : float  = _tile_emission(state, number)

					records.append({
						"world_x"  : world_x,
						"world_z"  : world_z,
						"chunk_x"  : cp.x,
						"chunk_z"  : cp.y,
						"local_x"  : lx,
						"local_z"  : lz,
						"state"    : state,
						"number"   : number,
						"is_mine"  : is_mine,
						"flagged"  : flagged,
						"color_r"  : snappedf(color.r, 0.001),
						"color_g"  : snappedf(color.g, 0.001),
						"color_b"  : snappedf(color.b, 0.001),
						"emission" : emit,
					})

	return records

func _tile_state(is_mine: bool, revealed: bool, flagged: bool) -> String:
	if flagged:      return "flagged"
	if not revealed: return "hidden"
	if is_mine:      return "mine"
	return "revealed"

func _tile_color(state: String, number: int) -> Color:
	match state:
		"hidden"   : return COLOR_UNREVEALED
		"mine"     : return COLOR_MINE
		"flagged"  : return COLOR_FLAGGED
		"revealed" :
			if number == 0: return COLOR_CLEAR
			return NUMBER_COLORS.get(number, Color.WHITE)
	return COLOR_UNREVEALED

func _tile_emission(state: String, number: int) -> float:
	match state:
		"hidden"   : return EMIT_HIDDEN
		"mine"     : return EMIT_MINE
		"flagged"  : return EMIT_FLAGGED
		"revealed" :
			if number == 0: return EMIT_CLEAR
			return EMIT_NUMBERED
	return 0.0

# ─────────────────────────────────────────────────────────────
# JSON EXPORT
# ─────────────────────────────────────────────────────────────

func _export_json(records: Array, path: String) -> void:
	var payload := {
		"export_info": {
			"center_chunk_x" : _chunk_manager.current_chunk.x,
			"center_chunk_z" : _chunk_manager.current_chunk.y,
			"export_half"    : EXPORT_HALF,
			"chunk_size"     : _chunk_manager.CHUNK_SIZE,
			"tile_count"     : records.size(),
		},
		"tiles": records
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[WorldExporter] Cannot write JSON: %s" % path)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("[WorldExporter] JSON → %s" % path)

# ─────────────────────────────────────────────────────────────
# GLTF EXPORT
# ─────────────────────────────────────────────────────────────

func _export_gltf(records: Array, path: String) -> void:
	print("[WorldExporter] Building GLTF scene…")

	# Group by colour+emission pair so each unique visual gets its own material
	var groups : Dictionary = {}

	for rec in records:
		var key := "%.3f_%.3f_%.3f_%.1f" % [
			rec["color_r"], rec["color_g"], rec["color_b"], rec["emission"]
		]
		if not groups.has(key):
			groups[key] = {
				"color"    : Color(rec["color_r"], rec["color_g"], rec["color_b"]),
				"emission" : rec["emission"],
				"tiles"    : []
			}
		groups[key]["tiles"].append(rec)

	var root := Node3D.new()
	root.name = "WorldExport"

	# Unit box — height scaled per instance via MultiMesh transform
	var box := BoxMesh.new()
	box.size = Vector3(TILE_SIZE - TILE_GAP, 1.0, TILE_SIZE - TILE_GAP)

	for key in groups.keys():
		var group    : Dictionary = groups[key]
		var color    : Color      = group["color"]
		var emit_val : float      = group["emission"]
		var tiles    : Array      = group["tiles"]

		# ── Material ──────────────────────────────────────────
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.metallic     = 0.05
		mat.roughness    = 0.85

		if emit_val > 0.0:
			mat.emission_enabled           = true
			mat.emission                   = color          # emit same hue as tile
			mat.emission_energy_multiplier = emit_val       # strength varies by type

		# ── MultiMesh ─────────────────────────────────────────
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count   = tiles.size()
		mm.mesh             = box

		for i in range(tiles.size()):
			var rec    : Dictionary = tiles[i]
			var height : float      = 0.6 if rec["state"] == "hidden" else 1.0

			var tx : float = rec["world_x"] + 0.5
			var tz : float = rec["world_z"] + 0.5
			var ty : float = height * 0.5

			mm.set_instance_transform(i,
				Transform3D(
					Basis().scaled(Vector3(1.0, height, 1.0)),
					Vector3(tx, ty, tz)
				)
			)

		var mmi := MultiMeshInstance3D.new()
		mmi.name              = "Tiles_%s" % key.replace(".", "p").replace("-", "n")
		mmi.multimesh         = mm
		mmi.material_override = mat
		root.add_child(mmi)

	_set_owner_recursive(root, root)

	var doc   := GLTFDocument.new()
	var state := GLTFState.new()

	var err := doc.append_from_scene(root, state)
	if err != OK:
		push_error("[WorldExporter] append_from_scene failed (err %d)" % err)
		root.free()
		return

	err = doc.write_to_filesystem(state, path)
	if err != OK:
		push_error("[WorldExporter] write_to_filesystem failed (err %d)" % err)
		root.free()
		return

	print("[WorldExporter] GLTF → %s  (%d material groups, %d tiles)" % [
		path, groups.size(), records.size()])

	root.free()
	await get_tree().process_frame

# ─────────────────────────────────────────────────────────────
# UTILITY
# ─────────────────────────────────────────────────────────────

func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)
