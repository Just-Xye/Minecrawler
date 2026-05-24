# TileDebugVisualizer.gd
extends Node3D

class_name TileDebugVisualizer

# ─────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────

const RADIUS : int = 3
const TILE_SIZE : float = 1.0

# Colors
const COLOR_CLOSEST : Color = Color(0.0, 1.0, 0.0, 0.8)      # Green
const COLOR_MID : Color = Color(1.0, 1.0, 0.0, 0.8)          # Yellow
const COLOR_FARTHEST : Color = Color(1.0, 0.0, 0.0, 0.8)     # Red
const COLOR_ERROR : Color = Color(0.0, 0.0, 0.0, 0.9)        # Black
const COLOR_MINE : Color = Color(1.0, 0.0, 0.0, 0.5)         # Semi-transparent red
const COLOR_FLAGGED : Color = Color(0.93, 0.74, 0.37, 0.7)   # Flag color

# ─────────────────────────────────────────────────────────────
# NODES
# ─────────────────────────────────────────────────────────────

var debug_sprites : Dictionary = {}  # Vector2i -> Sprite3D
var chunk_manager : ChunkManager = null
var player : Node3D = null

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready():
	set_process(true)

func _process(delta):
	if chunk_manager and player:
		_update_debug_visuals()

# ─────────────────────────────────────────────────────────────
# PUBLIC METHODS
# ─────────────────────────────────────────────────────────────

func set_targets(manager: ChunkManager, player_node: Node3D) -> void:
	chunk_manager = manager
	player = player_node

func _update_debug_visuals() -> void:
	if not chunk_manager or not player:
		return
	
	var player_grid_pos = chunk_manager.world_to_grid(player.global_position)
	var new_visible_tiles = {}
	
	# Loop through all tiles in radius
	for dx in range(-RADIUS, RADIUS + 1):
		for dz in range(-RADIUS, RADIUS + 1):
			var gx = player_grid_pos.x + dx
			var gz = player_grid_pos.y + dz
			var key = Vector2i(gx, gz)
			new_visible_tiles[key] = true
			
			# Calculate distance for color
			var distance = Vector2(dx, dz).length()
			var normalized_dist = distance / RADIUS
			
			# Get tile data
			var tile_data = chunk_manager.get_map_cell(gx, gz)
			var color = _get_color_for_tile(tile_data, normalized_dist)
			
			# Create or update debug sprite
			if not debug_sprites.has(key):
				_create_debug_sprite(key, gx, gz, color, tile_data)
			else:
				_update_debug_sprite(key, color, tile_data)
	
	# Remove sprites that are out of range
	for key in debug_sprites.keys():
		if not new_visible_tiles.has(key):
			debug_sprites[key].queue_free()
			debug_sprites.erase(key)

func _get_color_for_tile(tile_data: Dictionary, normalized_dist: float) -> Color:
	var state = tile_data.get("state", "hidden")
	
	# Error handling
	if state == "error" or not tile_data:
		return COLOR_ERROR
	
	# Special colors for mines and flagged tiles
	if state == "mine":
		return COLOR_MINE
	if state == "flagged":
		return COLOR_FLAGGED
	
	# Gradient from green (closest) to red (farthest)
	var color = COLOR_CLOSEST.lerp(COLOR_FARTHEST, normalized_dist)
	
	# Make revealed tiles slightly brighter
	if state == "revealed":
		color = color.lightened(0.3)
	
	return color

func _create_debug_sprite(key: Vector2i, gx: int, gz: int, color: Color, tile_data: Dictionary) -> void:
	# Create a Sprite3D for visual feedback
	var sprite = Sprite3D.new()
	sprite.name = "DebugTile_%d_%d" % [gx, gz]
	
	# Create a colored quad texture
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	
	# Set position in world space
	sprite.position = Vector3(gx + 0.5, 0.1, gz + 0.5)
	sprite.scale = Vector3(0.95, 0.95, 0.95)
	sprite.pixel_size = 0.05
	
	# Add a Label3D for text information
	var label = Label3D.new()
	label.name = "DebugLabel"
	label.position = Vector3(0, 0.2, 0)
	label.scale = Vector3(0.1, 0.1, 0.1)
	label.font_size = 32
	label.modulate = Color.WHITE
	label.outline_size = 4
	label.outline_modulate = Color.BLACK
	
	# Set label text based on tile data
	var text = _get_tile_display_text(gx, gz, tile_data)
	label.text = text
	
	sprite.add_child(label)
	add_child(sprite)
	
	debug_sprites[key] = sprite

func _update_debug_sprite(key: Vector2i, color: Color, tile_data: Dictionary) -> void:
	var sprite = debug_sprites[key]
	if not sprite:
		return
	
	# Update texture color
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	
	# Update label text
	var label = sprite.get_node_or_null("DebugLabel")
	if label:
		var text = _get_tile_display_text(key.x, key.y, tile_data)
		label.text = text

func _get_tile_display_text(gx: int, gz: int, tile_data: Dictionary) -> String:
	var state = tile_data.get("state", "unknown")
	var number = tile_data.get("number", 0)
	
	match state:
		"revealed":
			if number == 0:
				return "□"
			else:
				return str(number)
		"mine":
			return "💣"
		"flagged":
			return "⚑"
		"hidden":
			return "?"
		_:
			return "!"

# ─────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────

func clear_all() -> void:
	for sprite in debug_sprites.values():
		sprite.queue_free()
	debug_sprites.clear()
