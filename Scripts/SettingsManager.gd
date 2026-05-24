# SettingsManager.gd - Add this as an AutoLoad in Project Settings
extends Node

# ─────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────

signal settings_changed
signal volume_changed(bus_name: String, volume: float)
signal graphics_changed
signal controls_changed

# ─────────────────────────────────────────────
# SETTINGS DICTIONARY
# ─────────────────────────────────────────────

var settings: Dictionary = {}

# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────

func _ready() -> void:
	_load_settings()

# ─────────────────────────────────────────────
# PUBLIC METHODS
# ─────────────────────────────────────────────

func get_setting(key: String, default_value = null):
	return settings.get(key, default_value)

func set_setting(key: String, value) -> void:
	if settings[key] != value:
		settings[key] = value
		_apply_setting(key, value)
		settings_changed.emit()
		_save_settings()

func _apply_setting(key: String, value) -> void:
	match key:
		# Graphics
		"fullscreen":
			var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED
			DisplayServer.window_set_mode(mode)
		
		"vsync":
			var mode = DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED
			DisplayServer.window_set_vsync_mode(mode)
		
		"resolution":
			DisplayServer.window_set_size(Vector2i(value.x, value.y))
		
		"quality":
			_apply_quality_preset(value)
		
		"shadows":
			_apply_shadow_quality(value)
		
		"antialiasing":
			_apply_aa_mode(value)
		
		# Audio
		"master_volume":
			_set_bus_volume("Master", value)
			volume_changed.emit("Master", value)
		
		"music_volume":
			_set_bus_volume("Music", value)
			volume_changed.emit("Music", value)
		
		"sfx_volume":
			_set_bus_volume("SFX", value)
			volume_changed.emit("SFX", value)
		
		"ui_volume":
			_set_bus_volume("UI", value)
			volume_changed.emit("UI", value)
		
		"muted":
			var volume = -80 if value else linear_to_db(settings.get("master_volume", 0.8))
			_set_bus_volume("Master", volume)
		
		# Gameplay
		"sensitivity":
			_apply_mouse_sensitivity(value)
		
		"invert_y":
			_apply_invert_y(value)
		
		"language":
			_apply_language(value)

# ─────────────────────────────────────────────
# AUDIO METHODS
# ─────────────────────────────────────────────

func _set_bus_volume(bus_name: String, volume_db: float) -> void:
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, volume_db)

func _set_bus_volume_linear(bus_name: String, volume_linear: float) -> void:
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		var volume_db = linear_to_db(volume_linear)
		AudioServer.set_bus_volume_db(bus_index, volume_db)

# ─────────────────────────────────────────────
# GRAPHICS METHODS
# ─────────────────────────────────────────────

func _apply_quality_preset(quality: String) -> void:
	match quality:
		"Low":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 1024)
		
		"Medium":
			get_viewport().msaa_3d = Viewport.MSAA_2X
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 2048)
		
		"High":
			get_viewport().msaa_3d = Viewport.MSAA_4X
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 4096)
		
		"Ultra":
			get_viewport().msaa_3d = Viewport.MSAA_8X
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 8192)

func _apply_shadow_quality(quality: String) -> void:
	match quality:
		"Low":
			ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 1024)
		"Medium":
			ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 2048)
		"High":
			ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 4096)
		"Ultra":
			ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 8192)

func _apply_aa_mode(mode: String) -> void:
	match mode:
		"Off":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"FXAA":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"MSAA 2x":
			get_viewport().msaa_3d = Viewport.MSAA_2X
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"MSAA 4x":
			get_viewport().msaa_3d = Viewport.MSAA_4X
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"MSAA 8x":
			get_viewport().msaa_3d = Viewport.MSAA_8X
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"TAA":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			get_viewport().use_taa = true

# ─────────────────────────────────────────────
# GAMEPLAY METHODS
# ─────────────────────────────────────────────

func _apply_mouse_sensitivity(sensitivity: float) -> void:
	# Find the player and update sensitivity
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_mouse_sensitivity"):
		player.set_mouse_sensitivity(sensitivity)
	
	# Also emit signal for other listeners
	EventBus.mouse_sensitivity_changed.emit(sensitivity)

func _apply_invert_y(invert: bool) -> void:
	EventBus.invert_y_changed.emit(invert)

func _apply_language(language: String) -> void:
	EventBus.language_changed.emit(language)

# ─────────────────────────────────────────────
# SAVE/LOAD
# ─────────────────────────────────────────────

const CONFIG_PATH := "user://settings.cfg"

func _load_settings() -> void:
	var config = ConfigFile.new()
	
	if config.load(CONFIG_PATH) == OK:
		# Graphics
		settings.fullscreen = config.get_value("graphics", "fullscreen", true)
		settings.vsync = config.get_value("graphics", "vsync", true)
		settings.resolution = config.get_value("graphics", "resolution", Vector2i(1920, 1080))
		settings.quality = config.get_value("graphics", "quality", "High")
		settings.shadows = config.get_value("graphics", "shadows", "High")
		settings.antialiasing = config.get_value("graphics", "antialiasing", "MSAA 4x")
		
		# Audio
		settings.master_volume = config.get_value("audio", "master_volume", 0.8)
		settings.music_volume = config.get_value("audio", "music_volume", 0.7)
		settings.sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
		settings.ui_volume = config.get_value("audio", "ui_volume", 0.9)
		settings.muted = config.get_value("audio", "muted", false)
		
		# Gameplay
		settings.sensitivity = config.get_value("gameplay", "sensitivity", 1.0)
		settings.invert_y = config.get_value("gameplay", "invert_y", false)
		settings.language = config.get_value("gameplay", "language", "English")
	else:
		_set_default_settings()
	
	# Apply all loaded settings
	_apply_all_settings()

func _apply_all_settings() -> void:
	for key in settings:
		_apply_setting(key, settings[key])

func _set_default_settings() -> void:
	settings = {
		# Graphics
		"fullscreen": true,
		"vsync": true,
		"resolution": Vector2i(1920, 1080),
		"quality": "High",
		"shadows": "High",
		"antialiasing": "MSAA 4x",
		
		# Audio
		"master_volume": 0.8,
		"music_volume": 0.7,
		"sfx_volume": 0.8,
		"ui_volume": 0.9,
		"muted": false,
		
		# Gameplay
		"sensitivity": 0.0015,
		"invert_y": false,
		"language": "English"
	}

func _save_settings() -> void:
	var config = ConfigFile.new()
	
	# Graphics
	config.set_value("graphics", "fullscreen", settings.fullscreen)
	config.set_value("graphics", "vsync", settings.vsync)
	config.set_value("graphics", "resolution", settings.resolution)
	config.set_value("graphics", "quality", settings.quality)
	config.set_value("graphics", "shadows", settings.shadows)
	config.set_value("graphics", "antialiasing", settings.antialiasing)
	
	# Audio
	config.set_value("audio", "master_volume", settings.master_volume)
	config.set_value("audio", "music_volume", settings.music_volume)
	config.set_value("audio", "sfx_volume", settings.sfx_volume)
	config.set_value("audio", "ui_volume", settings.ui_volume)
	config.set_value("audio", "muted", settings.muted)
	
	# Gameplay
	config.set_value("gameplay", "sensitivity", settings.sensitivity)
	config.set_value("gameplay", "invert_y", settings.invert_y)
	config.set_value("gameplay", "language", settings.language)
	
	config.save(CONFIG_PATH)
