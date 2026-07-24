extends Control
##
## Settings screen for Clockwork. Three volume sliders (master /
## music / SFX) that read and write to the project's audio buses
## (see default_bus_layout.tres). Persistence (saving to disk via
## ConfigFile) is a separate TODO; for the jam, settings reset on
## game launch.
##

# Audio bus names. These must match the bus/0/name (etc.) entries
## in default_bus_layout.tres. @export so a build with a different
## bus layout can override without touching the script.
@export var master_bus: String = "Master"
@export var music_bus: String = "Music"
@export var sfx_bus: String = "SFX"
## Where the Back button takes the player.
@export var back_scene: String = "res://scenes/main_menu.tscn"

# Volume range: slider 0..100 maps to dB -60..0. -60 dB is
## effectively silent but still resolves to a real value, so the
## AudioServer doesn't error out at the extremes.
@export var min_db: float = -60.0
@export var max_db: float = 0.0

@onready var _master_slider: HSlider = $CenterContainer/VBox/Grid/MasterSlider
@onready var _music_slider: HSlider = $CenterContainer/VBox/Grid/MusicSlider
@onready var _sfx_slider: HSlider = $CenterContainer/VBox/Grid/SFXSlider
@onready var _chromatic_slider: HSlider = $CenterContainer/VBox/Grid/ChromaticSlider
@onready var _back_button: Button = $CenterContainer/VBox/BackButton

func _ready() -> void:
	_master_slider.value_changed.connect(_on_master_value_changed)
	_music_slider.value_changed.connect(_on_music_value_changed)
	_sfx_slider.value_changed.connect(_on_sfx_value_changed)
	_chromatic_slider.value_changed.connect(_on_chromatic_value_changed)
	_back_button.pressed.connect(_on_back_pressed)
	# Initialize slider values from the current bus volumes so
	# reopening the settings screen shows the actual state.
	_master_slider.value = _slider_for_bus(master_bus)
	_music_slider.value = _slider_for_bus(music_bus)
	_sfx_slider.value = _slider_for_bus(sfx_bus)
	# Same pattern for the chromatic aberration intensity -- read
	# from the autoload so the slider reflects whatever the
	# current value is (default 0.05, or whatever the user set
	# last time).
	_chromatic_slider.value = ChromaticAberration.get_intensity() * 100.0

func _on_master_value_changed(value: float) -> void:
	_set_bus_volume(master_bus, value)

func _on_music_value_changed(value: float) -> void:
	_set_bus_volume(music_bus, value)

func _on_sfx_value_changed(value: float) -> void:
	_set_bus_volume(sfx_bus, value)

func _on_chromatic_value_changed(value: float) -> void:
	# Slider is 0..100; the shader's intensity uniform is 0..1.
	# Scale down so the slider value matches the percentage of
	# the effect the user wants.
	ChromaticAberration.set_intensity(value / 100.0)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(back_scene)

func _set_bus_volume(bus_name: String, slider_value: float) -> void:
	# Map the slider's 0..100 range to dB (linear for now; a
	# logarithmic curve would feel more natural but linear is
	# fine for a jam). If the bus is missing (e.g. the layout
	# wasn't created), get_bus_index returns -1 and we silently
	# no-op so the slider still moves without crashing.
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var t := slider_value / _master_slider.max_value
	AudioServer.set_bus_volume_db(idx, lerp(min_db, max_db, t))

func _slider_for_bus(bus_name: String) -> float:
	# Inverse of _set_bus_volume -- read the bus's current dB and
	# map back to a 0..100 slider value. Returns 100 (full volume)
	# if the bus is missing, which is the safest default.
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 100.0
	var db := AudioServer.get_bus_volume_db(idx)
	return (db - min_db) / (max_db - min_db) * _master_slider.max_value
