extends Camera3D

# ─────────────────────────────────────────────────────────────
# EXPORTS
# ─────────────────────────────────────────────────────────────

@export var mouse_sensitivity: float = 0.002
@export var drag_factor: float = 6.0
@export var flashlight_energy: float = 2.5
@export var flashlight_angle: float = 45.0
@export var flashlight_range: float = 20.0
@export var flashlight_color: Color = Color(1.0, 0.95, 0.8)

# ─────────────────────────────────────────────────────────────
# NODES
# ─────────────────────────────────────────────────────────────

@onready var flashlight: SpotLight3D = $Flashlight  # Better to create in scene
var flashlight_node: SpotLight3D  # Fallback if not in scene

# ─────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────

var target_rotation: Basis
var current_rotation: Basis
var camera_rotation: Vector3 = Vector3.ZERO
var mouse_captured: bool = false

# ─────────────────────────────────────────────────────────────
# INIT
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	# Setup flashlight
	_setup_flashlight()
	
	# Initialize rotations
	target_rotation = global_transform.basis
	current_rotation = target_rotation

func _setup_flashlight() -> void:
	# Try to find flashlight in scene first
	flashlight_node = $Flashlight if has_node("Flashlight") else null
	
	# If not found, create it
	if not flashlight_node:
		flashlight_node = SpotLight3D.new()
		flashlight_node.name = "Flashlight"
		add_child(flashlight_node)
	
	# Configure spotlight
	flashlight_node.light_energy = flashlight_energy
	flashlight_node.spot_angle = flashlight_angle
	flashlight_node.spot_range = flashlight_range
	flashlight_node.shadow_enabled = true
	flashlight_node.shadow_bias = 0.05
	flashlight_node.light_color = flashlight_color
	
	# Position at camera origin
	flashlight_node.position = Vector3.ZERO

# ─────────────────────────────────────────────────────────────
# UPDATE
# ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Update target rotation to match camera
	target_rotation = transform.basis
	
	# Smoothly interpolate flashlight rotation toward camera rotation
	current_rotation = current_rotation.slerp(target_rotation, delta * drag_factor)
	
	# Apply to flashlight
	if flashlight_node:
		flashlight_node.transform.basis = current_rotation
	
	# Optional: Add slight bob to flashlight for realism
	_add_flashlight_bob(delta)

var bob_time: float = 0.0

func _add_flashlight_bob(delta: float) -> void:
	# Only bob when moving
	var player = get_parent()
	if player and player is CharacterBody3D:
		var velocity = player.velocity
		var is_moving = abs(velocity.x) > 0.1 or abs(velocity.z) > 0.1
		
		if is_moving:
			bob_time += delta * 8.0
			var bob_offset = sin(bob_time) * 0.01
			if flashlight_node:
				flashlight_node.position.y = bob_offset
		else:
			bob_time = 0.0
			if flashlight_node:
				flashlight_node.position.y = 0.0

# ─────────────────────────────────────────────────────────────
# PUBLIC METHODS
# ─────────────────────────────────────────────────────────────

func set_flashlight_enabled(enabled: bool) -> void:
	if flashlight_node:
		flashlight_node.visible = enabled

func get_flashlight() -> SpotLight3D:
	return flashlight_node

# ─────────────────────────────────────────────────────────────
# UTILITY
# ─────────────────────────────────────────────────────────────

func world_to_screen_pos(world_pos: Vector3) -> Vector2:
	return unproject_position(world_pos)
