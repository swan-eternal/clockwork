extends Control
##
## Settings screen for Clockwork. Three volume sliders (master /
## music / SFX) that read and write to the project's audio buses
## (see default_bus_layout.tres), plus a chromatic aberration
## intensity slider. Settings persist across game launches via
## ConfigFile (user://settings.cfg).
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

## Path and section name for the persisted settings file.
## user:// resolves to the per-user app data directory.
const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "settings"

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

	# Try to load saved settings; fall back to current bus/autoload
	# state if no save exists (first launch) or the file is unreadable.
	if not _load_settings():
		_master_slider.set_value_no_signal(_slider_for_bus(master_bus))
		_music_slider.set_value_no_signal(_slider_for_bus(music_bus))
		_sfx_slider.set_value_no_signal(_slider_for_bus(sfx_bus))
		_chromatic_slider.set_value_no_signal(ChromaticAberration.get_intensity() * 100.0)

	# Apply the slider values to the audio buses and the chromatic
	# aberration shader. We use set_value_no_signal above to avoid
	# triggering value_changed during load, so we apply explicitly here.
	_set_bus_volume(master_bus, _master_slider.value)
	_set_bus_volume(music_bus, _music_slider.value)
	_set_bus_volume(sfx_bus, _sfx_slider.value)
	ChromaticAberration.set_intensity(_chromatic_slider.value / 100.0)

func _on_master_value_changed(value: float) -> void:
	_set_bus_volume(master_bus, value)
	_save_settings()

func _on_music_value_changed(value: float) -> void:
	_set_bus_volume(music_bus, value)
	_save_settings()

func _on_sfx_value_changed(value: float) -> void:
	_set_bus_volume(sfx_bus, value)
	_save_settings()

func _on_chromatic_value_changed(value: float) -> void:
	# Slider is 0..100; the shader's intensity uniform is 0..1.
	# Scale down so the slider value matches the percentage of
	# the effect the user wants.
	ChromaticAberration.set_intensity(value / 100.0)
	_save_settings()

func _on_back_pressed() -> void:
	# If we were opened from another scene (typically the pause
	# menu while in a level), return there so the player keeps
	# their level state. Otherwise fall back to the configured
	# back_scene (main menu by default).
	var target := SceneHistory.previous_scene_path if not SceneHistory.previous_scene_path.is_empty() else back_scene
	# Clear so a future "back from settings" doesn't use a stale
	# path from a previous session.
	SceneHistory.previous_scene_path = ""
	get_tree().change_scene_to_file(target)

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

# Persist the current slider values to user://settings.cfg.
# Called from each value_changed handler so the on-disk copy stays
# in sync with the user's most recent change.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, "master", _master_slider.value)
	config.set_value(CONFIG_SECTION, "music", _music_slider.value)
	config.set_value(CONFIG_SECTION, "sfx", _sfx_slider.value)
	config.set_value(CONFIG_SECTION, "chromatic", _chromatic_slider.value)
	config.save(CONFIG_PATH)

# Read user://settings.cfg and apply the saved values to the sliders.
# Uses set_value_no_signal so loading doesn't trigger save_settings
# via the value_changed signals.
# Returns true on successful load, false if the file doesn't exist
# or is unreadable (caller falls back to current bus/autoload state).
func _load_settings() -> bool:
	var config := ConfigFile.new()
	var err := config.load(CONFIG_PATH)
	if err != OK:
		return false
	_master_slider.set_value_no_signal(config.get_value(CONFIG_SECTION, "master", 100.0))
	_music_slider.set_value_no_signal(config.get_value(CONFIG_SECTION, "music", 100.0))
	_sfx_slider.set_value_no_signal(config.get_value(CONFIG_SECTION, "sfx", 100.0))
	_chromatic_slider.set_value_no_signal(config.get_value(CONFIG_SECTION, "chromatic", 5.0))
	return true