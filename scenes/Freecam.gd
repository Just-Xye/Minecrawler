extends Camera3D

# ─────────────────────────────────────────────────────────────
# EXPORTS
# ─────────────────────────────────────────────────────────────

@export var move_speed : float = 10.0
@export var look_sensitivity : float = 0.002
@export var sprint_multiplier : float = 2.0
@export var slow_multiplier : float = 0.1

# ─────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────

var is_active : bool = false
var _base_speed : float = 10.0

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_base_speed = move_speed
	set_process(false)
	set_process_input(false)

# ─────────────────────────────────────────────────────────────
# PUBLIC METHODS
# ─────────────────────────────────────────────────────────────

func activate(initial_transform: Transform3D) -> void:
	is_active = true
	global_transform = initial_transform
	make_current()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_process(true)
	set_process_input(true)
	print("FreeCamera: Activated")

func deactivate() -> void:
	is_active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_process(false)
	set_process_input(false)
	print("FreeCamera: Deactivated")

# ─────────────────────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not is_active:
		return
	
	if event is InputEventMouseMotion:
		# Horizontal rotation
		rotate_y(-event.relative.x * look_sensitivity)
		
		# Vertical rotation (clamped)
		var new_rotation_x = rotation.x - event.relative.y * look_sensitivity
		rotation.x = clamp(new_rotation_x, deg_to_rad(-89.0), deg_to_rad(89.0))
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_deactivate_from_camera()

# ─────────────────────────────────────────────────────────────
# PROCESS
# ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not is_active:
		return
	
	# Get current speed with modifiers
	var current_speed = _base_speed
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed = _base_speed * sprint_multiplier
	elif Input.is_key_pressed(KEY_CTRL):
		current_speed = _base_speed * slow_multiplier
	
	# Movement input using direct key checks
	var input_dir := Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W):
		input_dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		input_dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		input_dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		input_dir += transform.basis.x
	if Input.is_key_pressed(KEY_Q):
		input_dir -= Vector3.UP
	if Input.is_key_pressed(KEY_E):
		input_dir += Vector3.UP
	
	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		position += input_dir * current_speed * delta

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

func _deactivate_from_camera() -> void:
	if not is_active:
		return
	
	# Find and toggle free cam in main scene
	var main = get_tree().current_scene
	if main and main.has_method("_toggle_free_cam"):
		main._toggle_free_cam()
	else:
		deactivate()
