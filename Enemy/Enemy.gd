extends Node3D

var player : Node3D

func _ready() -> void:
	player = get_node("/root/Main/Player")

func _process(delta: float) -> void:
	if player:
		look_at(player.global_position, Vector3.UP)
