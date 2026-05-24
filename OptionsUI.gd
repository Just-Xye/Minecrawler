# OptionsUI.gd (Fully Styled)
extends CanvasLayer

# ─────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────

signal back_pressed
signal settings_changed

# ─────────────────────────────────────────────
# UI NODES - MAIN
# ─────────────────────────────────────────────

@onready var panel: Panel = $Panel
@onready var tab_container: TabContainer = $Panel/TabContainer
@onready var back_button: Button = $Panel/VBoxContainer/BackButton
@onready var apply_button: Button = $Panel/VBoxContainer/ApplyButton
@onready var reset_button: Button = $Panel/VBoxContainer/ResetButton
@onready var save_notification: Panel = $Panel/SaveNotification

# ─────────────────────────────────────────────
# UI NODES - GRAPHICS TAB
# ─────────────────────────────────────────────

@onready var fullscreen_check: CheckBox = $Panel/TabContainer/Graphics/FullscreenCheck
@onready var vsync_check: CheckBox = $Panel/TabContainer/Graphics/VSyncCheck
@onready var resolution_option: OptionButton = $Panel/TabContainer/Graphics/ResolutionOption
@onready var quality_option: OptionButton = $Panel/TabContainer/Graphics/QualityOption
@onready var shadow_option: OptionButton = $Panel/TabContainer/Graphics/ShadowOption
@onready var aa_option: OptionButton = $Panel/TabContainer/Graphics/AAOption
@onready var fps_label: Label = $Panel/TabContainer/Graphics/FPSLabel

# ─────────────────────────────────────────────
# UI NODES - AUDIO TAB
# ─────────────────────────────────────────────

@onready var master_slider: HSlider = $Panel/TabContainer/Audio/MasterSlider
@onready var master_value: Label = $Panel/TabContainer/Audio/MasterValue
@onready var music_slider: HSlider = $Panel/TabContainer/Audio/MusicSlider
@onready var music_value: Label = $Panel/TabContainer/Audio/MusicValue
@onready var sfx_slider: HSlider = $Panel/TabContainer/Audio/SFXSlider
@onready var sfx_value: Label = $Panel/TabContainer/Audio/SFXValue
@onready var ui_slider: HSlider = $Panel/TabContainer/Audio/UISlider
@onready var ui_value: Label = $Panel/TabContainer/Audio/UIValue
@onready var mute_check: CheckBox = $Panel/TabContainer/Audio/MuteCheck
@onready var test_sound_button: Button = $Panel/TabContainer/Audio/TestSoundButton

# ─────────────────────────────────────────────
# UI NODES - GAMEPLAY TAB
# ─────────────────────────────────────────────

@onready var sensitivity_slider: HSlider = $Panel/TabContainer/Gameplay/SensitivitySlider
@onready var sensitivity_value: Label = $Panel/TabContainer/Gameplay/SensitivityValue
@onready var invert_y_check: CheckBox = $Panel/TabContainer/Gameplay/InvertYCheck
@onready var language_option: OptionButton = $Panel/TabContainer/Gameplay/LanguageOption

# ─────────────────────────────────────────────
# UI NODES - CONTROLS TAB
# ─────────────────────────────────────────────

@onready var control_scheme_option: OptionButton = $Panel/TabContainer/Controls/ControlSchemeOption
@onready var rebind_container: VBoxContainer = $Panel/TabContainer/Controls/RebindContainer

# ─────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────

const CONFIG_PATH := "user://settings.cfg"
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

const QUALITY_PRESETS := {
	0: "Low",
	1: "Medium", 
	2: "High",
	3: "Ultra"
}

const SHADOW_QUALITY := {
	0: "Low",
	1: "Medium",
	2: "High",
	3: "Ultra"
}

const AA_OPTIONS := {
	0: "Off",
	1: "FXAA",
	2: "MSAA 2x",
	3: "MSAA 4x",
	4: "MSAA 8x",
	5: "TAA"
}

const LANGUAGES := {
	0: "English",
	1: "Spanish",
	2: "French",
	3: "German",
	4: "Japanese",
	5: "Chinese"
}

# ─────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────

var settings: Dictionary = {}
var is_dirty: bool = false
var fps_counter: float = 0.0
var test_audio: AudioStreamPlayer

# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────

func _ready() -> void:
	layer = 2
	_setup_test_audio()
	_load_settings()
	_populate_options()
	_connect_signals()
	_update_ui_from_settings()
	_start_fps_monitor()
	_apply_visual_styles()
	
	# Start hidden
	if panel:
		panel.scale = Vector2(0.9, 0.9)
		panel.modulate = Color(1, 1, 1, 0)

func _setup_test_audio() -> void:
	test_audio = AudioStreamPlayer.new()
	add_child(test_audio)

# ─────────────────────────────────────────────
# VISUAL STYLES
# ─────────────────────────────────────────────

func _apply_visual_styles() -> void:
	_style_panel()
	_style_tabs()
	_style_buttons()
	_style_checkboxes()
	_style_sliders()
	_style_option_buttons()
	_style_labels()

func _style_panel() -> void:
	if not panel:
		return
	
	# Main panel style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.3)
	style.set_corner_radius_all(20)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.2)
	panel.add_theme_stylebox_override("panel", style)

func _style_tabs() -> void:
	if not tab_container:
		return
	
	# Tab bar style
	var tab_style = StyleBoxFlat.new()
	tab_style.bg_color = Color(2.357, 2.357, 2.357, 0.0)
	tab_style.set_corner_radius_all(8)
	
	# Selected tab style
	var selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color(1, 1, 1, 0.15)
	selected_style.set_corner_radius_all(8)
	selected_style.set_border_width_all(1)
	selected_style.border_color = Color(1, 1, 1, 0.3)
	
	tab_container.add_theme_stylebox_override("tab_fg", selected_style)
	tab_container.add_theme_stylebox_override("tab_bg", tab_style)
	
	# Tab text colors and size - INCREASED SIZE
	tab_container.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	tab_container.add_theme_color_override("font_selected_color", Color(1, 1, 1))

func _style_buttons() -> void:
	var buttons = [back_button, apply_button, reset_button, test_sound_button]
	
	for button in buttons:
		if not button:
			continue
		
		# Prevent double styling
		if button.has_meta("options_styled"):
			continue
		button.set_meta("options_styled", true)
		
		# Normal state
		var normal = StyleBoxFlat.new()
		normal.bg_color = Color(1, 1, 1, 0.13)
		normal.set_corner_radius_all(12)
		normal.set_border_width_all(1)
		normal.border_color = Color(1, 1, 1, 0.25)
		
		# Hover state
		var hover = StyleBoxFlat.new()
		hover.bg_color = Color(1, 1, 1, 0.24)
		hover.set_corner_radius_all(12)
		hover.set_border_width_all(1)
		hover.border_color = Color(1, 1, 1, 0.4)
		
		# Pressed state
		var pressed = StyleBoxFlat.new()
		pressed.bg_color = Color(1, 1, 1, 0.08)
		pressed.set_corner_radius_all(12)
		pressed.set_border_width_all(1)
		pressed.border_color = Color(1, 1, 1, 0.15)
		
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		
		button.add_theme_color_override("font_color", Color.WHITE)
		
		button.add_theme_constant_override("padding_left", 20)
		button.add_theme_constant_override("padding_right", 20)
		button.add_theme_constant_override("padding_top", 8)
		button.add_theme_constant_override("padding_bottom", 8)
		
		# Set pivot to center for proper scaling
		button.pivot_offset = button.size / 2
		button.resized.connect(func(): 
			if is_instance_valid(button):
				button.pivot_offset = button.size / 2
		)
		
		# Hover animation with center scaling
		button.mouse_entered.connect(func(): 
			if is_instance_valid(button):
				_tween_button_scale(button, Vector2(1.05, 1.05), 0.15)
		)
		button.mouse_exited.connect(func(): 
			if is_instance_valid(button):
				_tween_button_scale(button, Vector2(1.0, 1.0), 0.15)
		)

# Add this helper function for button scaling
func _tween_button_scale(button: Button, target_scale: Vector2, duration: float) -> void:
	if not is_instance_valid(button):
		return
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(button, "scale", target_scale, duration)

func _style_checkboxes() -> void:
	var checkboxes = [fullscreen_check, vsync_check, mute_check, invert_y_check]
	
	for checkbox in checkboxes:
		if not checkbox:
			continue
		
		checkbox.add_theme_color_override("font_color", Color(0.9, 0.9, 1))
		
		# Custom check icon color
		checkbox.add_theme_color_override("check_v_offset", 0)
		checkbox.add_theme_constant_override("check_h_separation", 10)

func _style_sliders() -> void:
	var sliders = [master_slider, music_slider, sfx_slider, ui_slider, sensitivity_slider]
	
	for slider in sliders:
		if not slider:
			continue
		
		# Create slider styles
		var grabber = StyleBoxFlat.new()
		grabber.bg_color = Color(1, 1, 1, 0.8)
		grabber.set_corner_radius_all(6)
		
		var groove = StyleBoxFlat.new()
		groove.bg_color = Color(1, 1, 1, 0.2)
		groove.set_corner_radius_all(4)
		
		slider.add_theme_stylebox_override("grabber", grabber)
		slider.add_theme_stylebox_override("grabber_highlight", grabber)
		slider.add_theme_stylebox_override("groove", groove)
		
		slider.add_theme_constant_override("grabber_size", 18)
		slider.add_theme_constant_override("grabber_offset", 4)

func _style_option_buttons() -> void:
	var option_buttons = [resolution_option, quality_option, shadow_option, aa_option, language_option, control_scheme_option]
	
	for option in option_buttons:
		if not option:
			continue
		
		# Normal state
		var normal = StyleBoxFlat.new()
		normal.bg_color = Color(1, 1, 1, 0.1)
		normal.set_corner_radius_all(8)
		normal.set_border_width_all(1)
		normal.border_color = Color(1, 1, 1, 0.2)
		
		# Hover state
		var hover = StyleBoxFlat.new()
		hover.bg_color = Color(1, 1, 1, 0.2)
		hover.set_corner_radius_all(8)
		hover.set_border_width_all(1)
		hover.border_color = Color(1, 1, 1, 0.35)
		
		# Pressed state
		var pressed = StyleBoxFlat.new()
		pressed.bg_color = Color(1, 1, 1, 0.05)
		pressed.set_corner_radius_all(8)
		pressed.set_border_width_all(1)
		pressed.border_color = Color(1, 1, 1, 0.15)
		
		option.add_theme_stylebox_override("normal", normal)
		option.add_theme_stylebox_override("hover", hover)
		option.add_theme_stylebox_override("pressed", pressed)
		
		option.add_theme_color_override("font_color", Color(0.9, 0.9, 1))
		
		# Center text
		option.alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		# Set pivot to center for scaling
		option.pivot_offset = option.size / 2
		option.resized.connect(func(): 
			if is_instance_valid(option):
				option.pivot_offset = option.size / 2
		)
		
		# Hover animation
		option.mouse_entered.connect(func(): 
			if is_instance_valid(option):
				_tween_button_scale(option, Vector2(1.02, 1.02), 0.15)
		)
		option.mouse_exited.connect(func(): 
			if is_instance_valid(option):
				_tween_button_scale(option, Vector2(1.0, 1.0), 0.15)
		)
		
		# Style dropdown popup
		_style_dropdown_popup(option)

func _style_dropdown_popup(option: OptionButton) -> void:
	var popup = option.get_popup()
	if not popup:
		return
	
	# Style the popup panel background
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.1, 0.98)  # Dark glass background
	panel_style.set_corner_radius_all(12)  # Rounded corners
	panel_style.set_border_width_all(2)  # Border width
	panel_style.border_color = Color(1, 1, 1, 0.25)  # Border color
	panel_style.shadow_size = 20  # Add shadow
	panel_style.shadow_color = Color(0, 0, 0, 0.5)  # Shadow color
	panel_style.shadow_offset = Vector2(0, 4)  # Shadow offset
	popup.add_theme_stylebox_override("panel", panel_style)
	
	# Style popup items (normal state)
	popup.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	
	# Style popup items (hover state)
	popup.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	
	# Style hover background
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(1, 1, 1, 0.15)
	hover_style.set_corner_radius_all(6)
	popup.add_theme_stylebox_override("hover", hover_style)
	
	# Style selected/focused item
	var selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color(1, 1, 1, 0.1)
	selected_style.set_corner_radius_all(6)
	selected_style.set_border_width_all(1)
	selected_style.border_color = Color(1, 1, 1, 0.2)
	popup.add_theme_stylebox_override("selected", selected_style)
	
	# Add padding to popup items
	popup.add_theme_constant_override("h_separation", 10)
	popup.add_theme_constant_override("icon_max_width", 0)
	
	# Style the scrollbar if needed
	_style_popup_scrollbar(popup)

func _style_popup_scrollbar(popup: PopupMenu) -> void:
	# Get scroll container if it exists
	var scroll_container = popup.get_node("ScrollContainer") if popup.has_node("ScrollContainer") else null
	if scroll_container:
		var v_scroll = scroll_container.get_v_scroll_bar()
		if v_scroll:
			# Style scrollbar background
			var scroll_style = StyleBoxFlat.new()
			scroll_style.bg_color = Color(1, 1, 1, 0.05)
			scroll_style.set_corner_radius_all(4)
			v_scroll.add_theme_stylebox_override("scroll", scroll_style)
			
			# Style scrollbar grabber
			var grabber_style = StyleBoxFlat.new()
			grabber_style.bg_color = Color(1, 1, 1, 0.2)
			grabber_style.set_corner_radius_all(4)
			v_scroll.add_theme_stylebox_override("grabber", grabber_style)
			
			# Style scrollbar grabber on hover
			var grabber_hover_style = StyleBoxFlat.new()
			grabber_hover_style.bg_color = Color(1, 1, 1, 0.3)
			grabber_hover_style.set_corner_radius_all(4)
			v_scroll.add_theme_stylebox_override("grabber_highlight", grabber_hover_style)

# Also add animation to the dropdown
func _add_dropdown_animation(option: OptionButton) -> void:
	# Connect to popup opening signal
	var popup = option.get_popup()
	if popup:
		popup.about_to_popup.connect(func():
			# Animate popup appearance
			popup.scale = Vector2(0.9, 0.9)
			popup.modulate.a = 0
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.15)
			tween.tween_property(popup, "modulate:a", 1.0, 0.1)
		)

func _style_labels() -> void:
	var labels = [master_value, music_value, sfx_value, ui_value, sensitivity_value, fps_label]
	
	for label in labels:
		if not label:
			continue
		
		label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))

# ─────────────────────────────────────────────
# SIGNAL CONNECTIONS
# ─────────────────────────────────────────────

func _connect_signals() -> void:
	# Main buttons
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if apply_button:
		apply_button.pressed.connect(_apply_settings)
	if reset_button:
		reset_button.pressed.connect(_reset_to_defaults)
	
	# Graphics
	if fullscreen_check:
		fullscreen_check.toggled.connect(_on_setting_changed)
	if vsync_check:
		vsync_check.toggled.connect(_on_setting_changed)
	if resolution_option:
		resolution_option.item_selected.connect(_on_setting_changed)
	if quality_option:
		quality_option.item_selected.connect(_on_quality_changed)
	if shadow_option:
		shadow_option.item_selected.connect(_on_setting_changed)
	if aa_option:
		aa_option.item_selected.connect(_on_setting_changed)
	
	# Audio
	if master_slider:
		master_slider.value_changed.connect(_on_master_volume_changed)
	if music_slider:
		music_slider.value_changed.connect(_on_music_volume_changed)
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	if ui_slider:
		ui_slider.value_changed.connect(_on_ui_volume_changed)
	if mute_check:
		mute_check.toggled.connect(_on_mute_toggled)
	if test_sound_button:
		test_sound_button.pressed.connect(_play_test_sound)
	
	# Gameplay
	if sensitivity_slider:
		sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	if invert_y_check:
		invert_y_check.toggled.connect(_on_setting_changed)
	if language_option:
		language_option.item_selected.connect(_on_setting_changed)

# ─────────────────────────────────────────────
# POPULATE UI OPTIONS
# ─────────────────────────────────────────────

func _populate_options() -> void:
	# Resolutions
	if resolution_option:
		for res in RESOLUTIONS:
			resolution_option.add_item("%d x %d" % [res.x, res.y])
	
	# Quality presets
	if quality_option:
		for key in QUALITY_PRESETS:
			quality_option.add_item(QUALITY_PRESETS[key])
	
	# Shadow quality
	if shadow_option:
		for key in SHADOW_QUALITY:
			shadow_option.add_item(SHADOW_QUALITY[key])
	
	# Anti-aliasing
	if aa_option:
		for key in AA_OPTIONS:
			aa_option.add_item(AA_OPTIONS[key])
	
	# Languages
	if language_option:
		for key in LANGUAGES:
			language_option.add_item(LANGUAGES[key])
	
	# Control schemes
	if control_scheme_option:
		control_scheme_option.add_item("Keyboard & Mouse")
		control_scheme_option.add_item("Controller")
		control_scheme_option.add_item("Custom")

# ─────────────────────────────────────────────
# LOAD/SAVE SETTINGS
# ─────────────────────────────────────────────

func _load_settings() -> void:
	var config = ConfigFile.new()
	
	if config.load(CONFIG_PATH) == OK:
		# Graphics
		settings.fullscreen = config.get_value("graphics", "fullscreen", true)
		settings.vsync = config.get_value("graphics", "vsync", true)
		settings.resolution_index = config.get_value("graphics", "resolution_index", 3)
		settings.quality_index = config.get_value("graphics", "quality_index", 2)
		settings.shadow_index = config.get_value("graphics", "shadow_index", 2)
		settings.aa_index = config.get_value("graphics", "aa_index", 3)
		
		# Audio
		settings.master_volume = config.get_value("audio", "master_volume", 0.8)
		settings.music_volume = config.get_value("audio", "music_volume", 0.7)
		settings.sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
		settings.ui_volume = config.get_value("audio", "ui_volume", 0.9)
		settings.muted = config.get_value("audio", "muted", false)
		
		# Gameplay
		settings.sensitivity = config.get_value("gameplay", "sensitivity", 1.0)
		settings.invert_y = config.get_value("gameplay", "invert_y", false)
		settings.language_index = config.get_value("gameplay", "language_index", 0)
	else:
		_reset_to_defaults()

func _save_settings() -> void:
	var config = ConfigFile.new()
	
	# Graphics
	config.set_value("graphics", "fullscreen", settings.fullscreen)
	config.set_value("graphics", "vsync", settings.vsync)
	config.set_value("graphics", "resolution_index", settings.resolution_index)
	config.set_value("graphics", "quality_index", settings.quality_index)
	config.set_value("graphics", "shadow_index", settings.shadow_index)
	config.set_value("graphics", "aa_index", settings.aa_index)
	
	# Audio
	config.set_value("audio", "master_volume", settings.master_volume)
	config.set_value("audio", "music_volume", settings.music_volume)
	config.set_value("audio", "sfx_volume", settings.sfx_volume)
	config.set_value("audio", "ui_volume", settings.ui_volume)
	config.set_value("audio", "muted", settings.muted)
	
	# Gameplay
	config.set_value("gameplay", "sensitivity", settings.sensitivity)
	config.set_value("gameplay", "invert_y", settings.invert_y)
	config.set_value("gameplay", "language_index", settings.language_index)
	
	config.save(CONFIG_PATH)
	_show_save_notification()

func _reset_to_defaults() -> void:
	settings.fullscreen = true
	settings.vsync = true
	settings.resolution_index = 3
	settings.quality_index = 2
	settings.shadow_index = 2
	settings.aa_index = 3
	
	settings.master_volume = 0.8
	settings.music_volume = 0.7
	settings.sfx_volume = 0.8
	settings.ui_volume = 0.9
	settings.muted = false
	
	settings.sensitivity = 1.0
	settings.invert_y = false
	settings.language_index = 0
	
	_update_ui_from_settings()
	is_dirty = true

# ─────────────────────────────────────────────
# UPDATE UI FROM SETTINGS
# ─────────────────────────────────────────────

func _update_ui_from_settings() -> void:
	# Graphics
	if fullscreen_check:
		fullscreen_check.button_pressed = settings.fullscreen
	if vsync_check:
		vsync_check.button_pressed = settings.vsync
	if resolution_option:
		resolution_option.selected = settings.resolution_index
	if quality_option:
		quality_option.selected = settings.quality_index
	if shadow_option:
		shadow_option.selected = settings.shadow_index
	if aa_option:
		aa_option.selected = settings.aa_index
	
	# Audio
	if master_slider:
		master_slider.value = settings.master_volume * 100
		_on_master_volume_changed(master_slider.value)
	if music_slider:
		music_slider.value = settings.music_volume * 100
		_on_music_volume_changed(music_slider.value)
	if sfx_slider:
		sfx_slider.value = settings.sfx_volume * 100
		_on_sfx_volume_changed(sfx_slider.value)
	if ui_slider:
		ui_slider.value = settings.ui_volume * 100
		_on_ui_volume_changed(ui_slider.value)
	if mute_check:
		mute_check.button_pressed = settings.muted
	
	# Gameplay
	if sensitivity_slider:
		sensitivity_slider.value = settings.sensitivity * 100
		_on_sensitivity_changed(sensitivity_slider.value)
	if invert_y_check:
		invert_y_check.button_pressed = settings.invert_y
	if language_option:
		language_option.selected = settings.language_index

# ─────────────────────────────────────────────
# APPLY SETTINGS
# ─────────────────────────────────────────────

func _apply_settings() -> void:
	# Apply graphics settings
	SettingsManager.set_setting("fullscreen", settings.fullscreen)
	SettingsManager.set_setting("vsync", settings.vsync)
	
	# Convert resolution index to Vector2i
	var resolution = RESOLUTIONS[settings.resolution_index]
	SettingsManager.set_setting("resolution", resolution)
	
	# Convert quality index to string
	var quality_names = ["Low", "Medium", "High", "Ultra"]
	SettingsManager.set_setting("quality", quality_names[settings.quality_index])
	
	var shadow_names = ["Low", "Medium", "High", "Ultra"]
	SettingsManager.set_setting("shadows", shadow_names[settings.shadow_index])
	
	var aa_names = ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "MSAA 8x", "TAA"]
	SettingsManager.set_setting("antialiasing", aa_names[settings.aa_index])
	
	# Apply audio settings
	SettingsManager.set_setting("master_volume", settings.master_volume)
	SettingsManager.set_setting("music_volume", settings.music_volume)
	SettingsManager.set_setting("sfx_volume", settings.sfx_volume)
	SettingsManager.set_setting("ui_volume", settings.ui_volume)
	SettingsManager.set_setting("muted", settings.muted)
	
	# Apply gameplay settings
	SettingsManager.set_setting("sensitivity", settings.sensitivity)
	SettingsManager.set_setting("invert_y", settings.invert_y)
	
	var language_names = ["English", "Spanish", "French", "German", "Japanese", "Chinese"]
	SettingsManager.set_setting("language", language_names[settings.language_index])
	
	# Save and notify
	_save_settings()
	is_dirty = false
	settings_changed.emit()
	_show_save_notification()

func _apply_audio_settings() -> void:
	var master_bus = AudioServer.get_bus_index("Master")
	
	if master_bus != -1:
		var volume = -80 if settings.muted else linear_to_db(settings.master_volume)
		AudioServer.set_bus_volume_db(master_bus, volume)

# ─────────────────────────────────────────────
# UI EVENT HANDLERS
# ─────────────────────────────────────────────

func _on_setting_changed(_value = null) -> void:
	is_dirty = true
	if apply_button:
		apply_button.disabled = false
	if reset_button:
		reset_button.disabled = false

func _on_quality_changed(index: int) -> void:
	settings.quality_index = index
	_on_setting_changed()

func _on_master_volume_changed(value: float) -> void:
	if master_value:
		master_value.text = "%d%%" % value
	settings.master_volume = value / 100.0
	_on_setting_changed()

func _on_music_volume_changed(value: float) -> void:
	if music_value:
		music_value.text = "%d%%" % value
	settings.music_volume = value / 100.0
	_on_setting_changed()

func _on_sfx_volume_changed(value: float) -> void:
	if sfx_value:
		sfx_value.text = "%d%%" % value
	settings.sfx_volume = value / 100.0
	_on_setting_changed()

func _on_ui_volume_changed(value: float) -> void:
	if ui_value:
		ui_value.text = "%d%%" % value
	settings.ui_volume = value / 100.0
	_on_setting_changed()

func _on_sensitivity_changed(value: float) -> void:
	if sensitivity_value:
		sensitivity_value.text = "%d%%" % value
	settings.sensitivity = value / 100.0
	_on_setting_changed()

func _on_mute_toggled(button_pressed: bool) -> void:
	settings.muted = button_pressed
	_apply_audio_settings()
	_on_setting_changed()

func _play_test_sound() -> void:
	if test_audio and test_audio.stream:
		test_audio.volume_db = linear_to_db(settings.sfx_volume)
		test_audio.play()

func _on_back_pressed() -> void:
	await _hide_options()
	back_pressed.emit()

# ─────────────────────────────────────────────
# ANIMATIONS & VISUALS
# ─────────────────────────────────────────────

# Add these functions to your OptionsUI.gd

func show_options() -> void:
	visible = true
	if panel:
		# Check if panel is still valid
		if is_instance_valid(panel):
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(panel, "modulate:a", 1.0, 0.3)
			tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _hide_options() -> void:
	if panel and is_instance_valid(panel):
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(panel, "modulate:a", 0.0, 0.2)
		tween.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.2).set_ease(Tween.EASE_IN)
		await tween.finished
	visible = false

func _show_save_notification() -> void:
	if not save_notification:
		return
		
	save_notification.modulate.a = 1.0
	save_notification.visible = true
	
	var tween = create_tween()
	tween.tween_property(save_notification, "modulate:a", 0.0, 1.0).set_delay(1.5)
	await tween.finished
	save_notification.visible = false

# ─────────────────────────────────────────────
# FPS MONITOR
# ─────────────────────────────────────────────

func _start_fps_monitor() -> void:
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_update_fps)
	add_child(timer)
	timer.start()

func _update_fps() -> void:
	if not fps_label:
		return
		
	fps_counter = Engine.get_frames_per_second()
	fps_label.text = "FPS: %d" % fps_counter
	
	if fps_counter >= 60:
		fps_label.add_theme_color_override("font_color", Color.GREEN)
	elif fps_counter >= 30:
		fps_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		fps_label.add_theme_color_override("font_color", Color.RED)

# ─────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────

func _exit_tree() -> void:
	if test_audio:
		test_audio.queue_free()
