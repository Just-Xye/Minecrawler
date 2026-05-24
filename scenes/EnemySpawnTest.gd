extends Node3D

@export var enemy_scene : PackedScene

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("spawn_enemy"):
		if enemy_scene:
			var enemy = enemy_scene.instantiate()
			add_child(enemy)
			enemy.global_position = get_node("/root/Main/Player").global_position
			print("Enemy spawned!")
