extends CanvasLayer

# ─────────────────────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────────────────────

signal splash_finished

# ─────────────────────────────────────────────────────────────
# UI NODES
# ─────────────────────────────────────────────────────────────

@onready var background: ColorRect = $ColorRect
@onready var animated_logo: AnimatedSprite2D = $CenterContainer/VBoxContainer/AnimatedSprite2D

# ─────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────

var _chunk_manager: MenuChunkManager
var _splash_started: bool = false
var _spinner_tween: Tween
var _check_timer: Timer
var _main_menu_instance: Node

# The number of chunks needed for full render radius
# With RENDER_RADIUS = 2, that's a 5x5 grid = 25 chunks
const REQUIRED_RENDER_CHUNKS : int = 25  # (RENDER_RADIUS * 2 + 1) ^ 2 = 5^2 = 25

# ─────────────────────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	
	# Make background full screen
	if background:
		background.anchor_left = 0.0
		background.anchor_top = 0.0
		background.anchor_right = 1.0
		background.anchor_bottom = 1.0
	
	# Play logo animation
	if animated_logo and animated_logo.sprite_frames:
		animated_logo.play("default")
	
	# Load the MainMenu scene using call_deferred
	call_deferred("_load_main_menu")

# ─────────────────────────────────────────────────────────────
# LOAD MAIN MENU (FOR CHUNK GENERATION)
# ─────────────────────────────────────────────────────────────

func _load_main_menu() -> void:
	print("[SplashScreen] Loading MainMenu scene...")
	
	# Load MainMenu scene
	var main_menu_scene = preload("res://UI/MainMenu.tscn")
	_main_menu_instance = main_menu_scene.instantiate()
	
	# Add to root using call_deferred
	get_tree().root.call_deferred("add_child", _main_menu_instance)
	
	# Wait for it to be added
	await get_tree().process_frame
	
	# Move to back so splash screen is visible
	get_tree().root.call_deferred("move_child", _main_menu_instance, 0)
	
	# DISABLE AUDIO on MainMenu - prevent music from playing
	_disable_audio_on_main_menu()
	
	# Temporarily disable processing so it doesn't take input
	_main_menu_instance.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Wait a moment for initialization
	await get_tree().create_timer(0.5).timeout
	
	# Find the chunk manager (inside MenuWorld)
	_find_chunk_manager()

func _disable_audio_on_main_menu() -> void:
	if not _main_menu_instance:
		return
	
	var menu_ui = _find_title_screen()
	if menu_ui and menu_ui.has_method("mute_audio"):
		menu_ui.mute_audio(true)
		print("[SplashScreen] Audio muted on TitleScreen")

func _find_title_screen():
	"""Find the TitleScreen/CanvasLayer in the MainMenu scene"""
	if not _main_menu_instance:
		return null
	
	for child in _main_menu_instance.get_children():
		if child is CanvasLayer:
			return child
	return null

func _enable_audio_on_main_menu() -> void:
	if not _main_menu_instance:
		return
	
	var menu_ui = _find_title_screen()
	if menu_ui:
		if menu_ui.has_method("mute_audio"):
			menu_ui.mute_audio(false)
			print("[SplashScreen] Audio unmuted on TitleScreen")
		
		if menu_ui.has_method("_fade_in"):
			menu_ui._fade_in()

# ─────────────────────────────────────────────────────────────
# CHUNK GENERATION MONITORING
# ─────────────────────────────────────────────────────────────

func _find_chunk_manager() -> void:
	print("[SplashScreen] Looking for MenuChunkManager...")
	
	if not _main_menu_instance:
		print("[SplashScreen] No MainMenu instance!")
		_finish_splash()
		return
	
	# Find MenuWorld, then GridManager (which has MenuChunkManager)
	var menu_world = _main_menu_instance.get_node_or_null("MenuWorld")
	if menu_world:
		_chunk_manager = menu_world.get_node_or_null("GridManager")
		if not _chunk_manager:
			_chunk_manager = menu_world.get_node_or_null("ChunkManager")
	
	if not _chunk_manager:
		print("[SplashScreen] MenuChunkManager not found in MenuWorld!")
		_finish_splash()
		return
	
	print("[SplashScreen] MenuChunkManager found!")
	print("[SplashScreen] CHUNK_SIZE: ", _chunk_manager.CHUNK_SIZE)
	print("[SplashScreen] RENDER_RADIUS: ", _chunk_manager.RENDER_RADIUS)
	print("[SplashScreen] Required chunks for full render: ", REQUIRED_RENDER_CHUNKS)
	print("[SplashScreen] Monitoring chunks...")
	
	# Enable processing on MainMenu so chunks generate
	_main_menu_instance.process_mode = Node.PROCESS_MODE_INHERIT
	
	# Connect to signals
	if _chunk_manager.has_signal("spawn_chunks_ready"):
		if not _chunk_manager.spawn_chunks_ready.is_connected(_on_spawn_chunks_ready):
			_chunk_manager.spawn_chunks_ready.connect(_on_spawn_chunks_ready)
			print("[SplashScreen] Connected to spawn_chunks_ready signal")
	
	if _chunk_manager.has_signal("spawn_chunk_progress"):
		if not _chunk_manager.spawn_chunk_progress.is_connected(_on_spawn_chunk_progress):
			_chunk_manager.spawn_chunk_progress.connect(_on_spawn_chunk_progress)
			print("[SplashScreen] Connected to spawn_chunk_progress signal")
	
	# Start periodic check
	_check_timer = Timer.new()
	_check_timer.wait_time = 0.3
	_check_timer.timeout.connect(_check_chunk_status)
	add_child(_check_timer)
	_check_timer.start()
	
	# Also check immediately
	_check_chunk_status()

func _on_spawn_chunk_progress(completed: int, total: int) -> void:
	print("[SplashScreen] Chunk progress: %d/%d" % [completed, total])
	
	# With RENDER_RADIUS = 2, we need all 25 render chunks
	if completed >= REQUIRED_RENDER_CHUNKS:
		print("[SplashScreen] All %d render chunks completed!" % REQUIRED_RENDER_CHUNKS)
		_finish_splash()

func _on_spawn_chunks_ready() -> void:
	print("[SplashScreen] spawn_chunks_ready signal received!")
	_finish_splash()

func _check_chunk_status() -> void:
	if not _chunk_manager:
		return
	
	# Check if spawn_ready is true
	if _chunk_manager.spawn_ready:
		print("[SplashScreen] spawn_ready is true!")
		_finish_splash()
		return
	
	# Check if loading is complete
	if _chunk_manager.is_loading_complete():
		print("[SplashScreen] is_loading_complete is true!")
		_finish_splash()
		return
	
	# Check if we have the full render area loaded (5x5 grid from -2 to +2)
	var loaded_count = 0
	var required_chunks = 0
	
	for x in range(-_chunk_manager.RENDER_RADIUS, _chunk_manager.RENDER_RADIUS + 1):
		for z in range(-_chunk_manager.RENDER_RADIUS, _chunk_manager.RENDER_RADIUS + 1):
			var chunk_pos = Vector2i(x, z)
			required_chunks += 1
			if _chunk_manager.chunk_nodes.has(chunk_pos) or _chunk_manager.loaded_chunks.has(chunk_pos):
				loaded_count += 1
	
	# Also check if spawn_completed size meets requirement
	if _chunk_manager._spawn_completed.size() >= REQUIRED_RENDER_CHUNKS:
		print("[SplashScreen] Spawn completed size: %d" % _chunk_manager._spawn_completed.size())
		_finish_splash()
		return
	
	if loaded_count >= required_chunks:
		print("[SplashScreen] Full render area loaded! (%d/%d chunks)" % [loaded_count, required_chunks])
		_finish_splash()

# ─────────────────────────────────────────────────────────────
# SPLASH FINISH & TRANSITION
# ─────────────────────────────────────────────────────────────

func _finish_splash() -> void:
	if _splash_started:
		return
	_splash_started = true
	
	print("[SplashScreen] Finishing splash screen...")
	
	# Stop timer
	if _check_timer and _check_timer.is_inside_tree():
		_check_timer.stop()
		_check_timer.queue_free()
	
	# Stop spinner animation
	if _spinner_tween:
		_spinner_tween.kill()
	
	# Disconnect signals
	if _chunk_manager:
		if _chunk_manager.has_signal("spawn_chunks_ready") and _chunk_manager.spawn_chunks_ready.is_connected(_on_spawn_chunks_ready):
			_chunk_manager.spawn_chunks_ready.disconnect(_on_spawn_chunks_ready)
		if _chunk_manager.has_signal("spawn_chunk_progress") and _chunk_manager.spawn_chunk_progress.is_connected(_on_spawn_chunk_progress):
			_chunk_manager.spawn_chunk_progress.disconnect(_on_spawn_chunk_progress)
	
	# Fade out
	await _fade_out()
	
	print("[SplashScreen] Showing MainMenu...")
	
	# Enable audio on MainMenu before showing it
	_enable_audio_on_main_menu()
	
	# Find and show TitleScreen (CanvasLayer)
	if _main_menu_instance:
		var title_screen = _find_title_screen()
		if title_screen:
			title_screen.visible = true
			if title_screen.has_method("_fade_in"):
				title_screen._fade_in()
		
		# Enable processing on MainMenu
		_main_menu_instance.process_mode = Node.PROCESS_MODE_INHERIT
	
	# Emit finished signal
	emit_signal("splash_finished")
	
	# Remove splash screen
	queue_free()

func _fade_out() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	
	if background:
		tween.tween_property(background, "modulate:a", 0.0, 0.5)
	if animated_logo:
		tween.tween_property(animated_logo, "modulate:a", 0.0, 0.5)
	
	await tween.finished
