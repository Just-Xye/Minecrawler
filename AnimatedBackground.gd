# AnimatedBackground.gd
extends ColorRect

# ============================================================
# FILES
# ============================================================

@export var video_paths: Array[String] = [
	"res://movies/movie1.ogv",
	"res://movies/movie2.ogv"
]

@export var bgm_paths: Array[String] = [
	"res://Sounds/bgm/falling.ogg",
	"res://Sounds/bgm/far-north.ogg",
	"res://Sounds/bgm/you-not-the-same.ogg",
	"res://Sounds/bgm/food-court.ogg"
]

# ============================================================
# SETTINGS
# ============================================================

@export var crossfade_duration: float = 1.0
@export var bgm_volume: float = -10.0
@export var video_volume: float = -80.0
@export var loop_videos: bool = true
@export var loop_bgm: bool = true

# ============================================================
# INTERNAL STATE
# ============================================================

var _video_index: int = 0
var _bgm_index: int = 0

var _video_player: VideoStreamPlayer
var _bgm_player: AudioStreamPlayer
var _is_transitioning: bool = false

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	randomize()
	_setup_video_player()
	_setup_bgm_player()
	_start_playback()

# ============================================================
# SETUP VIDEO
# ============================================================

func _setup_video_player() -> void:
	_video_player = VideoStreamPlayer.new()
	add_child(_video_player)

	_video_player.volume_db = video_volume
	_video_player.expand = true

	_video_player.anchor_left = 0
	_video_player.anchor_top = 0
	_video_player.anchor_right = 1
	_video_player.anchor_bottom = 1
	_video_player.offset_left = 0
	_video_player.offset_top = 0
	_video_player.offset_right = 0
	_video_player.offset_bottom = 0

	if not _video_player.finished.is_connected(_on_video_finished):
		_video_player.finished.connect(_on_video_finished)

# ============================================================
# SETUP AUDIO
# ============================================================

func _setup_bgm_player() -> void:
	_bgm_player = AudioStreamPlayer.new()
	add_child(_bgm_player)

	_bgm_player.volume_db = bgm_volume

	if not _bgm_player.finished.is_connected(_on_bgm_finished):
		_bgm_player.finished.connect(_on_bgm_finished)

# ============================================================
# START
# ============================================================

func _start_playback() -> void:
	if bgm_paths.size() > 0:
		_bgm_index = randi() % bgm_paths.size()

	if video_paths.size() > 0:
		_video_index = 0  # or also random if you want

	_play_video(_video_index)
	_play_bgm(_bgm_index)

# ============================================================
# VIDEO PLAYBACK (FIXED)
# ============================================================

func _play_video(index: int) -> void:
	if video_paths.is_empty():
		return

	if index >= video_paths.size():
		if loop_videos:
			index = 0
			_video_index = 0
		else:
			return

	var path: String = video_paths[index]

	if not FileAccess.file_exists(path):
		print("Missing video: ", path)
		return

	var stream := VideoStreamTheora.new()
	stream.file = path

	_video_player.stream = stream
	_video_player.play()

# ============================================================
# VIDEO FINISHED
# ============================================================

func _on_video_finished() -> void:
	if _is_transitioning:
		return

	_is_transitioning = true

	await _crossfade_out()

	_video_index += 1

	if _video_index >= video_paths.size():
		if loop_videos:
			_video_index = 0
		else:
			_is_transitioning = false
			return

	_play_video(_video_index)

	await _crossfade_in()

	_is_transitioning = false

# ============================================================
# CROSSFADE (ONLY BACKGROUND COLOR, SAFE)
# ============================================================

func _crossfade_out() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(0, 0, 0, 1), crossfade_duration)
	await tween.finished

func _crossfade_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), crossfade_duration)
	await tween.finished

# ============================================================
# AUDIO PLAYBACK (FIXED GODOT 4)
# ============================================================

func _play_bgm(index: int) -> void:
	if bgm_paths.is_empty():
		return

	if index >= bgm_paths.size():
		if loop_bgm:
			index = 0
			_bg_index_reset()
		else:
			return

	var path: String = bgm_paths[index]

	if not FileAccess.file_exists(path):
		print("Missing BGM: ", path)
		return

	var stream := AudioStreamOggVorbis.load_from_file(path)

	_bgm_player.stream = stream
	_bgm_player.play()

func _bg_index_reset() -> void:
	_bgm_index = 0

# ============================================================
# BGM FINISHED
# ============================================================

func _on_bgm_finished() -> void:
	_bgm_index += 1

	if _bgm_index >= bgm_paths.size():
		if loop_bgm:
			_bgm_index = 0
		else:
			return

	_play_bgm(_bgm_index)

# ============================================================
# CONTROL FUNCTIONS
# ============================================================

func pause() -> void:
	if _video_player:
		_video_player.stream_paused = true
	if _bgm_player:
		_bgm_player.stream_paused = true

func play() -> void:
	if _video_player:
		_video_player.stream_paused = false
	if _bgm_player:
		_bgm_player.stream_paused = false

func stop() -> void:
	if _video_player:
		_video_player.stop()
	if _bgm_player:
		_bgm_player.stop()

	_video_index = 0
	_bgm_index = 0

# ============================================================
# CLEANUP
# ============================================================

func _exit_tree() -> void:
	stop()
