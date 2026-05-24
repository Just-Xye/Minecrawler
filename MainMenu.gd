extends CanvasLayer

# ─────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────

const MAIN_GAME_SCENE := "res://scenes/Main.tscn"
const FADE_DURATION := 0.5

const BGM_TRACKS := [
	"res://Sounds/bgm/falling.ogg",
	"res://Sounds/bgm/far-north.ogg",
	"res://Sounds/bgm/you-not-the-same.ogg",
	"res://Sounds/bgm/food-court.ogg"
]

# ─────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────

signal start_button_pressed
signal options_button_pressed
signal credits_button_pressed
signal quit_button_pressed

# ─────────────────────────────────────────────
# UI NODES
# ─────────────────────────────────────────────

@onready var center_ui: Control = $CenterContainer
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var options_button: Button = $CenterContainer/VBoxContainer/OptionsButton
@onready var credits_button: Button = $CenterContainer/VBoxContainer/CreditsButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

@onready var start_sound: AudioStreamPlayer = $CenterContainer/VBoxContainer/StartButton/AudioStreamPlayer
@onready var options_sound: AudioStreamPlayer = $CenterContainer/VBoxContainer/OptionsButton/AudioStreamPlayer
@onready var credits_sound: AudioStreamPlayer = $CenterContainer/VBoxContainer/CreditsButton/AudioStreamPlayer
@onready var quit_sound: AudioStreamPlayer = $CenterContainer/VBoxContainer/QuitButton/AudioStreamPlayer

# ─────────────────────────────────────────────
# AUDIO
# ─────────────────────────────────────────────

const CASSETTE_EJECT := "res://Sounds/UI/cassette-eject.wav"
const CASSETTE_INSERT := "res://Sounds/UI/cassette-insert.wav"

var _bgm: AudioStreamPlayer
var _cassette_eject_player: AudioStreamPlayer
var _cassette_insert_player: AudioStreamPlayer

var _bgm_index := 0
var _is_transitioning := false
var _is_audio_muted := true  # Start muted (splash screen is showing)
var _audio_enabled := false  # Track if audio has been enabled

var _button_anims := {}

# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────

## Returns the SettingsManager autoload node, or null if it doesn't exist.
## Prevents crashes when SettingsManager isn't registered as an autoload.
func _get_settings_manager() -> Node:
	return get_node_or_null("/root/SettingsManager")

# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────

func _ready() -> void:
	layer = 1
	_setup_audio()
	_connect_signals()
	_fade_in()
	_style_buttons()

	# Start with audio muted (splash screen is showing)
	_mute_all_audio(true)

	# Connect to settings system for volume control
	_connect_audio_settings()

# ─────────────────────────────────────────────
# PUBLIC METHODS FOR SPLASH SCREEN
# ─────────────────────────────────────────────

func stop_bgm() -> void:
	if _bgm and is_instance_valid(_bgm):
		_bgm.stop()
		_bgm.stream = null

	if _cassette_eject_player and is_instance_valid(_cassette_eject_player):
		_cassette_eject_player.stop()

	if _cassette_insert_player and is_instance_valid(_cassette_insert_player):
		_cassette_insert_player.stop()

	_bgm_index = 0
	_is_transitioning = false

func mute_audio(muted: bool) -> void:
	_is_audio_muted = muted

	if muted:
		_mute_all_audio(true)
	else:
		_unmute_all_audio()
		_start_bgm_cycle()

func _mute_all_audio(muted: bool) -> void:
	var volume := -80.0 if muted else 0.0

	if _bgm:
		_bgm.volume_db = volume
		if muted:
			_bgm.stop()

	if _cassette_eject_player:
		_cassette_eject_player.volume_db = volume
		if muted:
			_cassette_eject_player.stop()

	if _cassette_insert_player:
		_cassette_insert_player.volume_db = volume
		if muted:
			_cassette_insert_player.stop()

	var button_sounds := [start_sound, options_sound, credits_sound, quit_sound]
	for sound in button_sounds:
		if sound:
			sound.volume_db = volume

func _unmute_all_audio() -> void:
	var sm := _get_settings_manager()
	if sm:
		var music_volume: float = sm.get_setting("music_volume", 0.7)
		var music_db := linear_to_db(music_volume)
		if _bgm:
			_bgm.volume_db = music_db

		var sfx_volume: float = sm.get_setting("sfx_volume", 0.8)
		var sfx_db := linear_to_db(sfx_volume)
		if _cassette_eject_player:
			_cassette_eject_player.volume_db = sfx_db
		if _cassette_insert_player:
			_cassette_insert_player.volume_db = sfx_db

		var button_sounds := [start_sound, options_sound, credits_sound, quit_sound]
		for sound in button_sounds:
			if sound:
				sound.volume_db = sfx_db
	else:
		# Fallback default volumes when SettingsManager is absent
		if _bgm:
			_bgm.volume_db = -10
		if _cassette_eject_player:
			_cassette_eject_player.volume_db = -10
		if _cassette_insert_player:
			_cassette_insert_player.volume_db = -10

# ─────────────────────────────────────────────
# SIGNAL CONNECTIONS
# ─────────────────────────────────────────────

func _connect_signals() -> void:
	if start_button and not start_button.pressed.is_connected(_on_start_pressed):
		start_button.pressed.connect(_on_start_pressed)

	if options_button and not options_button.pressed.is_connected(_on_options_pressed):
		options_button.pressed.connect(_on_options_pressed)

	if credits_button and not credits_button.pressed.is_connected(_on_credits_pressed):
		credits_button.pressed.connect(_on_credits_pressed)

	if quit_button and not quit_button.pressed.is_connected(_on_quit_pressed):
		quit_button.pressed.connect(_on_quit_pressed)

# ─────────────────────────────────────────────
# AUDIO SETTINGS INTEGRATION
# ─────────────────────────────────────────────

func _connect_audio_settings() -> void:
	# FIX: guard before await in case node is freed during splash
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	var sm := _get_settings_manager()
	if sm:
		if sm.has_signal("volume_changed") and not sm.volume_changed.is_connected(_on_volume_changed):
			sm.volume_changed.connect(_on_volume_changed)

		# Only apply volume if not muted by splash screen
		if not _is_audio_muted:
			var music_volume: float = sm.get_setting("music_volume", 0.7)
			_apply_music_volume(music_volume)

			var sfx_volume: float = sm.get_setting("sfx_volume", 0.8)
			_apply_button_sound_volume(sfx_volume)

func _on_volume_changed(bus_name: String, volume_linear: float) -> void:
	if _is_audio_muted:
		return

	if bus_name == "Music":
		_apply_music_volume(volume_linear)
	elif bus_name == "SFX":
		_apply_button_sound_volume(volume_linear)

func _apply_music_volume(volume_linear: float) -> void:
	if _bgm and not _is_audio_muted:
		_bgm.volume_db = linear_to_db(volume_linear)

func _apply_button_sound_volume(volume_linear: float) -> void:
	if _is_audio_muted:
		return

	var volume_db := linear_to_db(volume_linear)

	var button_sounds := [start_sound, options_sound, credits_sound, quit_sound]
	for sound in button_sounds:
		if sound:
			sound.volume_db = volume_db

	if _cassette_eject_player:
		_cassette_eject_player.volume_db = volume_db
	if _cassette_insert_player:
		_cassette_insert_player.volume_db = volume_db

# ─────────────────────────────────────────────
# BUTTON HANDLERS
# ─────────────────────────────────────────────

func _on_start_pressed() -> void:
	start_button_pressed.emit()
	_play_button_sound(start_sound)

	# Stop all menu audio immediately
	_stop_all_audio_immediately()
	
	# Kill the menu world before fading out
	_kill_menu_world()

	await _fade_out()

	_cleanup_before_scene_change()
	
	# Use GameManager to transition (or direct change if no GameManager)
	if has_node("/root/GameManager"):
		GameManager.start_game()
	else:
		# Fallback to direct scene change
		get_tree().change_scene_to_file(MAIN_GAME_SCENE)

func _kill_menu_world() -> void:
	print("[TitleScreen] Killing menu world...")

	# Stop all MenuChunkManagers FIRST
	var managers = get_tree().get_nodes_in_group("menu_chunk_manager")

	for manager in managers:
		if not is_instance_valid(manager):
			continue

		print("[TitleScreen] Deactivating MenuChunkManager: ", manager.name)

		# Stop all processing
		manager.set_process(false)
		manager.set_physics_process(false)
		manager.set_process_input(false)
		manager.set_process_unhandled_input(false)

		# Call internal cleanup
		if manager.has_method("deactivate"):
			manager.deactivate()

		if manager.has_method("cleanup_all_chunks"):
			manager.cleanup_all_chunks()

		# Remove from tree immediately
		manager.queue_free()

	# Remove all menu chunk visuals
	var menu_chunks = get_tree().get_nodes_in_group("menu_chunks")

	for chunk in menu_chunks:
		if is_instance_valid(chunk):
			chunk.queue_free()

	# Remove menu world container
	var menu_world = get_node_or_null("../MenuWorld")

	if menu_world and is_instance_valid(menu_world):
		menu_world.queue_free()

	# Force scene tree cleanup
	await get_tree().process_frame
	await get_tree().process_frame

	print("[TitleScreen] Menu world fully destroyed.")

func _find_menu_chunk_manager_in_scene():
	# Search by group
	var managers = get_tree().get_nodes_in_group("menu_chunk_manager")
	if managers.size() > 0:
		return managers[0]
	
	# Try common paths relative to this node
	var paths = [
		"../../MenuChunkManager",
		"../MenuChunkManager", 
		"MenuChunkManager",
		"/root/MainMenu/MenuChunkManager"
	]
	
	for path in paths:
		var node = get_node_or_null(path)
		if node:
			return node
	
	return null

func _stop_all_audio_immediately() -> void:
	if _bgm and is_instance_valid(_bgm):
		_bgm.stop()
		_bgm.stream = null

	if _cassette_eject_player and is_instance_valid(_cassette_eject_player):
		_cassette_eject_player.stop()

	if _cassette_insert_player and is_instance_valid(_cassette_insert_player):
		_cassette_insert_player.stop()

	var button_sounds := [start_sound, options_sound, credits_sound, quit_sound]
	for sound in button_sounds:
		if sound and is_instance_valid(sound):
			sound.stop()

func _cleanup_before_scene_change() -> void:
	for data in _button_anims.values():
		if data.has("tween"):
			var tween = data["tween"]
			if tween and is_instance_valid(tween):
				tween.kill()
	_button_anims.clear()

	# Disconnect SettingsManager signal safely
	var sm := _get_settings_manager()
	if sm and sm.has_signal("volume_changed"):
		if sm.volume_changed.is_connected(_on_volume_changed):
			sm.volume_changed.disconnect(_on_volume_changed)

	_stop_all_audio_immediately()

func _on_options_pressed() -> void:
	options_button_pressed.emit()
	_play_button_sound(options_sound)

func _on_credits_pressed() -> void:
	credits_button_pressed.emit()
	_play_button_sound(credits_sound)

func _on_quit_pressed() -> void:
	quit_button_pressed.emit()
	_play_button_sound(quit_sound)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()

func _play_button_sound(audio_player: AudioStreamPlayer) -> void:
	if _is_audio_muted:
		return

	if audio_player and audio_player.stream:
		audio_player.play()
	else:
		push_warning("Button sound not found or no audio stream assigned")

# ─────────────────────────────────────────────
# BUTTON STYLING
# ─────────────────────────────────────────────

func _style_buttons() -> void:
	_apply_button_style(start_button)
	_apply_button_style(options_button)
	_apply_button_style(credits_button)
	_apply_button_style(quit_button)

func _apply_button_style(button: Button) -> void:
	if button == null:
		return

	if button.has_meta("styled"):
		return
	button.set_meta("styled", true)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0.13)
	normal.set_corner_radius_all(15)
	normal.set_border_width_all(1)
	normal.border_color = Color(1, 1, 1, 0.28)
	normal.shadow_size = 0

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.24)
	hover.set_corner_radius_all(15)
	hover.set_border_width_all(2)
	hover.border_color = Color(1, 1, 1, 0.40)
	hover.shadow_size = 0

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1, 1, 1, 0.10)
	pressed.set_corner_radius_all(15)
	pressed.set_border_width_all(2)
	pressed.border_color = Color(1, 1, 1, 0.22)
	pressed.shadow_size = 0

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)

	button.add_theme_color_override("font_color", Color.WHITE)
	button.custom_minimum_size = Vector2(200, 50)

	button.pivot_offset = button.size / 2
	button.resized.connect(func():
		button.pivot_offset = button.size / 2
	)

	_button_anims[button] = {
		"hovering": false,
		"tween": null
	}

	button.mouse_entered.connect(func():
		if not is_instance_valid(button) or not _button_anims.has(button):
			return
		_button_anims[button]["hovering"] = true
		_tween_button_scale(button, Vector2(1.05, 1.05), 0.25)
	)

	button.mouse_exited.connect(func():
		if not is_instance_valid(button) or not _button_anims.has(button):
			return
		_button_anims[button]["hovering"] = false
		_tween_button_scale(button, Vector2(1.0, 1.0), 0.25)
	)

	button.button_down.connect(func():
		if not is_instance_valid(button) or not _button_anims.has(button):
			return
		_tween_button_scale(button, Vector2(0.98, 0.98), 0.08)
	)

	button.button_up.connect(func():
		if not is_instance_valid(button) or not _button_anims.has(button):
			return
		var data: Dictionary = _button_anims[button]
		var target := Vector2(1.05, 1.05) if data.get("hovering", false) else Vector2(1.0, 1.0)
		_tween_button_scale(button, target, 0.12)
	)

func _tween_button_scale(button: Button, target_scale: Vector2, duration: float) -> void:
	if not is_instance_valid(button):
		return

	if _button_anims.has(button):
		var old_tween = _button_anims[button].get("tween")
		if old_tween and is_instance_valid(old_tween):
			old_tween.kill()

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(button, "scale", target_scale, duration)

	if _button_anims.has(button):
		_button_anims[button]["tween"] = tween

# ─────────────────────────────────────────────
# AUDIO SETUP
# ─────────────────────────────────────────────

func _setup_audio() -> void:
	_bgm = AudioStreamPlayer.new()
	add_child(_bgm)
	_bgm.bus = "Music"

	_cassette_eject_player = AudioStreamPlayer.new()
	add_child(_cassette_eject_player)
	_cassette_eject_player.bus = "SFX"

	if FileAccess.file_exists(CASSETTE_EJECT):
		_cassette_eject_player.stream = load(CASSETTE_EJECT)

	_cassette_insert_player = AudioStreamPlayer.new()
	add_child(_cassette_insert_player)
	_cassette_insert_player.bus = "SFX"

	if FileAccess.file_exists(CASSETTE_INSERT):
		_cassette_insert_player.stream = load(CASSETTE_INSERT)

	_bgm.finished.connect(_on_bgm_finished)

	if BGM_TRACKS.is_empty():
		return

	randomize()
	_bgm_index = randi() % BGM_TRACKS.size()

func _start_bgm_cycle() -> void:
	if _is_transitioning or _is_audio_muted:
		return

	_is_transitioning = true

	if _cassette_insert_player.stream and not _is_audio_muted:
		_cassette_insert_player.play()

	# FIX: guard before await — node may leave tree during splash transition
	if not is_inside_tree():
		_is_transitioning = false
		return
	await get_tree().create_timer(0.45).timeout

	if not is_instance_valid(self):
		return

	if not _is_audio_muted:
		_play_bgm()

	_is_transitioning = false

func _play_bgm() -> void:
	if BGM_TRACKS.is_empty() or _is_audio_muted:
		return

	var path: String = BGM_TRACKS[_bgm_index]

	if not FileAccess.file_exists(path):
		push_error("Missing BGM: " + path)
		return

	var stream := AudioStreamOggVorbis.load_from_file(path)

	if stream == null:
		push_error("Failed to load BGM: " + path)
		return

	_bgm.stream = stream
	_bgm.play()

	print("Now Playing: ", path.get_file())

func _on_bgm_finished() -> void:
	if _is_transitioning or _is_audio_muted:
		return

	_is_transitioning = true

	if _cassette_eject_player.stream and not _is_audio_muted:
		_cassette_eject_player.play()

	# FIX: guard before first await
	if not is_inside_tree():
		_is_transitioning = false
		return
	await get_tree().create_timer(0.7).timeout

	if not is_instance_valid(self):
		return

	_bgm_index = (_bgm_index + 1) % BGM_TRACKS.size()

	if _cassette_insert_player.stream and not _is_audio_muted:
		_cassette_insert_player.play()

	# FIX: guard before second await
	if not is_inside_tree():
		_is_transitioning = false
		return
	await get_tree().create_timer(0.45).timeout

	if not is_instance_valid(self):
		return

	if not _is_audio_muted:
		_play_bgm()

	_is_transitioning = false

# ─────────────────────────────────────────────
# FADE EFFECTS
# ─────────────────────────────────────────────

func _fade_in() -> void:
	if not is_instance_valid(center_ui):
		return

	center_ui.modulate.a = 0.0

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(center_ui, "modulate:a", 1.0, FADE_DURATION)

func _fade_out() -> void:
	if not is_instance_valid(center_ui):
		return

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(center_ui, "modulate:a", 0.0, FADE_DURATION)
	await tween.finished

# ─────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────

func _enter_tree() -> void:
	# Audio setup safety
	if _bgm == null:
		_setup_audio()

	# Wait until nodes exist
	call_deferred("_post_enter_tree_setup")

func _post_enter_tree_setup() -> void:
	# Ensure node still exists
	if not is_inside_tree():
		return

	# Ensure buttons are valid before connecting
	if is_instance_valid(start_button):
		if not start_button.pressed.is_connected(_on_start_pressed):
			_connect_signals()

	# Connect settings safely
	_connect_audio_settings()

	# Resume BGM if allowed
	if not _is_audio_muted:
		_start_bgm_cycle()

func _exit_tree() -> void:
	_stop_all_audio_immediately()

	for data in _button_anims.values():
		if data.has("tween"):
			var tween = data["tween"]
			if tween and is_instance_valid(tween):
				tween.kill()

	_button_anims.clear()

	var players := [_bgm, _cassette_eject_player, _cassette_insert_player]
	for player in players:
		if player and is_instance_valid(player):
			player.stop()
			player.queue_free()
