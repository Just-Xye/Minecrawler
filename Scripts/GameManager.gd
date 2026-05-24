# GameManager.gd
extends Node

signal game_starting
signal menu_cleaned_up

var menu_world: Node = null

func start_game() -> void:
	print("[GameManager] Starting game - cleaning up menu...")
	emit_signal("game_starting")
	
	# Clean up menu world
	await _cleanup_menu_world()
	
	# Load game scene
	print("[GameManager] Loading game scene...")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _cleanup_menu_world() -> void:
	print("[GameManager] Cleaning up menu world...")
	
	# Find and cleanup MenuChunkManager
	var menu_cm = _find_menu_chunk_manager()
	if menu_cm:
		print("[GameManager] Found MenuChunkManager, deactivating...")
		if menu_cm.has_method("deactivate"):
			menu_cm.deactivate()
		if menu_cm.has_method("cleanup_all_chunks"):
			menu_cm.cleanup_all_chunks()
		menu_cm.queue_free()
	
	# Clean up all menu chunks
	var menu_chunks = get_tree().get_nodes_in_group("menu_chunks")
	print("[GameManager] Cleaning up %d menu chunks..." % menu_chunks.size())
	for chunk in menu_chunks:
		if is_instance_valid(chunk):
			chunk.queue_free()
	
	# Clean up menu chunk managers
	var managers = get_tree().get_nodes_in_group("menu_chunk_manager")
	for manager in managers:
		if is_instance_valid(manager) and manager != menu_cm:
			manager.queue_free()
	
	# Wait one frame for cleanup
	await get_tree().process_frame
	
	# Force garbage collection hint
	await get_tree().create_timer(0.1).timeout
	
	emit_signal("menu_cleaned_up")
	print("[GameManager] Menu cleanup complete")

func _find_menu_chunk_manager():
	# Try different paths to find the MenuChunkManager
	var paths = [
		"MenuChunkManager",
		"MainMenu/MenuChunkManager",
		"CanvasLayer/MenuChunkManager",
        "/root/MainMenu/MenuChunkManager"
	]
	
	for path in paths:
		var node = get_node_or_null(path)
		if node:
			return node
	
	# Search by group
	var managers = get_tree().get_nodes_in_group("menu_chunk_manager")
	if managers.size() > 0:
		return managers[0]
	
	return null
