# MenuUIManager.gd
extends Node

# ─────────────────────────────────────────────
# PARENT UI ROOT (CanvasLayer container)
# ─────────────────────────────────────────────

@onready var ui_root: CanvasLayer = get_node("../MenuUI")

# ─────────────────────────────────────────────
# UI SCENES
# ─────────────────────────────────────────────

const OPTIONS_SCENE   := preload("res://UI/OptionsUI.tscn")
const CREDITS_SCENE   := preload("res://UI/CreditsUI.tscn")

# ─────────────────────────────────────────────
# INSTANCES
# ─────────────────────────────────────────────

var options_instance: CanvasLayer
var credits_instance: CanvasLayer

# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────

func _ready() -> void:
	# Connect to the MenuUI signals
	if ui_root:
		ui_root.start_button_pressed.connect(_on_start)
		ui_root.options_button_pressed.connect(show_options)
		ui_root.credits_button_pressed.connect(show_credits)
		ui_root.quit_button_pressed.connect(_on_quit)

# ─────────────────────────────────────────────
# MAIN MENU ACTIONS
# ─────────────────────────────────────────────

func _on_start() -> void:
	await get_tree().create_timer(0.16).timeout
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_quit() -> void:
	await get_tree().create_timer(0.16).timeout # Replace 1.5 with your sound duration in seconds
	get_tree().quit()

# ─────────────────────────────────────────────
# OPTIONS
# ─────────────────────────────────────────────

func show_options() -> void:
	# Hide main menu UI but don't remove it
	if ui_root:
		ui_root.visible = false
	
	# Create options instance if needed
	if not options_instance:
		options_instance = OPTIONS_SCENE.instantiate()
		options_instance.back_pressed.connect(_on_options_back)
		add_child(options_instance)
	
	# Show and animate options
	options_instance.visible = true
	if options_instance.has_method("show_options"):
		options_instance.show_options()

func _on_options_back() -> void:
	# Hide options
	if options_instance:
		if options_instance.has_method("_hide_options"):
			await options_instance._hide_options()
		options_instance.visible = false
	
	# Show main menu UI again
	if ui_root:
		ui_root.visible = true
		if ui_root.has_method("_fade_in"):
			ui_root._fade_in()

# ─────────────────────────────────────────────
# CREDITS
# ─────────────────────────────────────────────

func show_credits() -> void:
	# Hide main menu UI but don't remove it
	if ui_root:
		ui_root.visible = false
	
	# Create credits instance if needed
	if not credits_instance:
		credits_instance = CREDITS_SCENE.instantiate()
		credits_instance.back_pressed.connect(_on_credits_back)
		add_child(credits_instance)
	
	# Show and animate credits
	credits_instance.visible = true
	if credits_instance.has_method("show_options"):
		credits_instance.show_options()

func _on_credits_back() -> void:
	# Hide credits
	if credits_instance:
		if credits_instance.has_method("_hide_options"):
			await credits_instance._hide_options()
		credits_instance.visible = false
	
	# Show main menu UI again
	if ui_root:
		ui_root.visible = true
		if ui_root.has_method("_fade_in"):
			ui_root._fade_in()
