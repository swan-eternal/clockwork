extends Node

# Music autoload. Plays the level music on the Music bus with looping.
# Singleton — register in project.godot's [autoload] section under
# the name "AudioManager" so it starts when the game launches.
#
# The Music bus already exists in default_bus_layout.tres (Master,
# Music, SFX); no audio bus setup needed here, just route the
# AudioStreamPlayer to it via `bus = "Music"`.

const MUSIC = preload("res://assets/audio/nojisuma-clock-9323.ogg")

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.stream = MUSIC
	_player.finished.connect(_on_finished)
	add_child(_player)
	_player.play()


# Replay when the stream finishes. Keeps the music looping without
# relying on AudioStream.loop_mode (whose support varies across
# stream types in Godot 4) — connecting to `finished` works for any
# AudioStream subclass.
func _on_finished() -> void:
	if _player:
		_player.play()