extends Node
## Autoload: fire-and-forget SFX with pitch variation, plus music playback.
## Usage: AudioManager.play_sfx(preload("res://assets/audio/sfx/jump.ogg"))
##        AudioManager.play_music(preload("res://assets/audio/music/theme.ogg"))

var _music_player: AudioStreamPlayer


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)


func play_sfx(stream: AudioStream, volume_db := 0.0, pitch_range := 0.1) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_range, 1.0 + pitch_range)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func play_music(stream: AudioStream, restart := false) -> void:
	if _music_player.stream == stream and _music_player.playing and not restart:
		return
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()
