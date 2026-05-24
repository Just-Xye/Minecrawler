# Deagle.gd
extends Area3D
class_name Deagle

# ─────────────────────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────────────────────

signal weapon_picked_up

# ─────────────────────────────────────────────────────────────
# EXPORTS
# ─────────────────────────────────────────────────────────────

@export var pickup_sound : AudioStream
@export var rotation_speed : float = 2.0
@export var bob_height : float = 0.2
@export var bob_speed : float = 2.0
@export var is_equipped : bool = false

# ─────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────

var _start_y : float = 0.0
var _time : float = 0.0
var _chunk_manager : ChunkManager = null

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_start_y = position.y
	body_entered.connect(_on_body_entered)
	
	var particles = GPUParticles3D.new()
	particles.amount = 20
	particles.lifetime = 1.0
	particles.one_shot = false
	particles.emitting = true
	
	var particle_material = ParticleProcessMaterial.new()

	# REMOVE THIS LINE:
	# particle_material.flag_disable_z = true 

	# FIX THIS LINE:
	# In Godot 4, it is 'particle_flag_align_y'
	particle_material.particle_flag_align_y = true

	particle_material.direction = Vector3(0, 1, 0)
	particle_material.spread = 180.0
	particle_material.gravity = Vector3(0, -1, 0)
	particle_material.initial_velocity_min = 1.0
	particle_material.initial_velocity_max = 2.0
	particle_material.scale_min = 0.05
	particle_material.scale_max = 0.1
	particle_material.color = Color(1, 0.8, 0.2, 1)
	
	# Don't forget to actually assign the material to the particles!
	particles.process_material = particle_material
	
	add_child(particles)

func _process(delta: float) -> void:
	if is_equipped:
		return
	# Rotate the weapon
	_time += delta
	rotate_y(rotation_speed * delta)
	
	# Bobbing animation
	position.y = _start_y + sin(_time * bob_speed) * bob_height

# ─────────────────────────────────────────────────────────────
# PUBLIC METHODS
# ─────────────────────────────────────────────────────────────

func set_chunk_manager(manager: ChunkManager) -> void:
	_chunk_manager = manager

func set_position_on_tile(world_x: int, world_z: int) -> void:
	global_position = Vector3(world_x + 0.5, 1.0, world_z + 0.5)

# ─────────────────────────────────────────────────────────────
# SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────

func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		_pickup()

func _pickup() -> void:
	set_process(false)
	# Play pickup sound
	if pickup_sound:
		var audio = AudioStreamPlayer3D.new()
		audio.stream = pickup_sound
		audio.max_distance = 20.0
		add_child(audio)
		audio.play()
		await audio.finished
		audio.queue_free()
	
	# Emit signal
	weapon_picked_up.emit()
	
	# Notify player
	var player = get_node("/root/Main/Player")
	if player and player.has_method("on_weapon_picked_up"):
		player.on_weapon_picked_up()
	
	# Remove weapon
	queue_free()
