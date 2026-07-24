extends Area2D
##
## Clockwork victory flag — emits `player_won` when the player
## (anything in the "player" group) enters the area. Fires both a
## confetti burst (visual) and the win SFX (audio) on the same frame
## for a satisfying "I won!" payoff.
##
## Touch-to-win only. The level scene catches `player_won` and runs
## the win flow (stop clock, show LevelCompleteUI, advance level).
##

signal player_won

@onready var _confetti: GPUParticles2D = $Confetti
@onready var _win_sound: AudioStreamPlayer = $WinSound

func _ready() -> void:
	# Wire the Area2D's body_entered signal. The flag itself doesn't
	# need to be in any group — it's a *target* for the player's
	# detection, not a thing that detects.
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# Filter to "player" group only — body_entered fires for any
	# PhysicsBody that enters, which includes future death zones,
	# level tiles, etc. The co-add rule from MEMORY.md applies: the
	# `add_to_group("player")` call lives in player.gd._ready.
	if body.is_in_group("player"):
		# Fire confetti at the same instant as player_won. The
		# particles are configured with one_shot = true so they
		# auto-stop after the burst (~1.2s).
		_confetti.emitting = true
		# Play the win SFX on the same frame — lands with the
		# LevelCompleteUI fade-in kicked off by level.gd.
		_win_sound.play()
		player_won.emit()
