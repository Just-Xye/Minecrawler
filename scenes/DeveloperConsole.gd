extends CanvasLayer
class_name DeveloperConsole

# ─────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────

const MAX_HISTORY := 100
const MAX_LINES := 200
const CONSOLE_KEY := KEY_QUOTELEFT

# ─────────────────────────────────────────────
# NODES
# ─────────────────────────────────────────────

@onready var panel: Panel = $Panel 
@onready var output: RichTextLabel = $Panel/VBoxContainer/Output
@onready var input_line: LineEdit = $Panel/VBoxContainer/InputLine

# ─────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────

var is_open := false

var command_history: Array[String] = []
var history_index := -1

# Command system
var commands: Dictionary = {}     # name -> Callable
var cvars: Dictionary = {}        # name -> value

# ─────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────

func _ready() -> void:
	visible = false
	is_open = false

	if output == null or input_line == null:
		push_error("DeveloperConsole: Output or InputLine node not found — check node names match the script paths exactly")
		return

	output.bbcode_enabled = true
	output.scroll_following = true

	_register_default_commands()
	_register_default_cvars()

	input_line.text_submitted.connect(_on_command_entered)

	_add_log("Console ready. Type [color=#aaffaa]help[/color] for commands.", Color.GREEN)

# ─────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == CONSOLE_KEY:
			_toggle_console()
			get_viewport().set_input_as_handled()

		elif is_open and event.keycode == KEY_ESCAPE:
			_close_console()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP:
				_history_up()
			KEY_DOWN:
				_history_down()
			KEY_TAB:
				_autocomplete()

# ─────────────────────────────────────────────
# CORE CONSOLE CONTROL
# ─────────────────────────────────────────────

func _toggle_console():
	if is_open:
		_close_console()
	else:
		_open_console()

func _open_console():
	is_open = true
	visible = true
	await get_tree().process_frame
	input_line.clear()
	input_line.grab_focus()

func _close_console():
	is_open = false
	visible = false
	input_line.release_focus()

# ─────────────────────────────────────────────
# COMMAND SYSTEM
# ─────────────────────────────────────────────

func register_command(name: String, callable: Callable):
	commands[name] = callable

func register_cvar(name: String, default_value):
	cvars[name] = default_value

func _register_default_commands():
	register_command("help", _cmd_help)
	register_command("clear", _cmd_clear)
	register_command("echo", _cmd_echo)
	register_command("set", _cmd_set)
	register_command("get", _cmd_get)
	register_command("list", _cmd_list)

	# Debug/game commands
	register_command("fps", _cmd_fps)
	register_command("tree", _cmd_tree)

func _register_default_cvars():
	register_cvar("timescale", 1.0)
	register_cvar("fog_density", 0.04)

# ─────────────────────────────────────────────
# COMMAND EXECUTION
# ─────────────────────────────────────────────

func _on_command_entered(text: String):
	if text.strip_edges().is_empty():
		return
	
	_add_log("> " + text, Color.YELLOW)
	
	command_history.append(text)
	if command_history.size() > MAX_HISTORY:
		command_history.pop_front()
	history_index = -1
	
	var result = _execute(text)
	if result != "":
		_add_log(result)
	
	input_line.clear()
	input_line.grab_focus()

func _execute(text: String) -> String:
	var parts = _parse_command(text)
	if parts.is_empty():
		return ""
	
	var cmd = parts[0]
	var args = parts.slice(1)
	
	# Command
	if commands.has(cmd):
		return str(commands[cmd].call(args))
	
	# CVar direct access
	if cvars.has(cmd):
		if args.is_empty():
			return cmd + " = " + str(cvars[cmd])
		else:
			cvars[cmd] = _auto_cast(args[0])
			return cmd + " set to " + str(cvars[cmd])
	
	return "Unknown command: " + cmd

# ─────────────────────────────────────────────
# PARSER (handles quotes)
# ─────────────────────────────────────────────

func _parse_command(text: String) -> Array:
	var result: Array = []
	var current := ""
	var in_quotes := false
	
	for c in text:
		if c == "\"":
			in_quotes = !in_quotes
		elif c == " " and not in_quotes:
			if current != "":
				result.append(current)
				current = ""
		else:
			current += c
	
	if current != "":
		result.append(current)
	
	return result

func _auto_cast(value: String):
	if value.is_valid_float():
		return float(value)
	elif value.is_valid_int():
		return int(value)
	elif value == "true":
		return true
	elif value == "false":
		return false
	return value

# ─────────────────────────────────────────────
# BUILT-IN COMMANDS
# ─────────────────────────────────────────────

func _cmd_help(args):
	return "Commands:\n" + "\n".join(commands.keys())

func _cmd_clear(args):
	output.clear()
	return ""

func _cmd_echo(args):
	return " ".join(args)

func _cmd_set(args):
	if args.size() < 2:
		return "Usage: set <var> <value>"
	var name = args[0]
	var value = _auto_cast(args[1])
	cvars[name] = value
	return name + " = " + str(value)

func _cmd_get(args):
	if args.is_empty():
		return "Usage: get <var>"
	return str(cvars.get(args[0], "Not found"))

func _cmd_list(args):
	var out := "=== CVars ===\n"
	for k in cvars:
		out += k + " = " + str(cvars[k]) + "\n"
	return out

func _cmd_fps(args):
	return "FPS: " + str(Engine.get_frames_per_second())

func _cmd_tree(args):
	return _print_tree(get_tree().root, 0)

func _print_tree(node: Node, depth: int) -> String:
	var indent = "  ".repeat(depth)
	var out = indent + node.name + "\n"
	for c in node.get_children():
		out += _print_tree(c, depth + 1)
	return out

# ─────────────────────────────────────────────
# LOGGING SYSTEM
# ─────────────────────────────────────────────

func log(msg: String):
	_add_log(msg, Color.WHITE)

func warn(msg: String):
	_add_log("[WARN] " + msg, Color.YELLOW)

func error(msg: String):
	_add_log("[ERROR] " + msg, Color.RED)

func _add_log(text: String, color: Color = Color.WHITE) -> void:
	output.append_text("[color=#" + color.to_html() + "]" + text + "[/color]\n")
	# scroll_following = true handles auto-scroll; no manual call needed
	
	if output.get_paragraph_count() > MAX_LINES:
		output.clear()  # fallback: full clear if too many lines

# ─────────────────────────────────────────────
# HISTORY
# ─────────────────────────────────────────────

func _history_up():
	if history_index < command_history.size() - 1:
		history_index += 1
		input_line.text = command_history[command_history.size() - 1 - history_index]
		input_line.caret_column = input_line.text.length()

func _history_down():
	if history_index > 0:
		history_index -= 1
		input_line.text = command_history[command_history.size() - 1 - history_index]
	elif history_index == 0:
		history_index = -1
		input_line.clear()

# ─────────────────────────────────────────────
# AUTOCOMPLETE
# ─────────────────────────────────────────────

func _autocomplete() -> void:
	var text := input_line.text
	var matches : Array[String] = []
	for cmd in commands.keys():
		if cmd.begins_with(text):
			matches.append(cmd)
	if matches.size() == 1:
		input_line.text = matches[0] + " "
		input_line.caret_column = input_line.text.length()
	elif matches.size() > 1:
		_add_log(" ".join(matches), Color.CYAN)
