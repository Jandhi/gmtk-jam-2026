extends Node
## Autoload: fire-and-forget SFX with pitch variation, plus music playback.
## Usage: AudioManager.play_sfx(preload("res://assets/audio/sfx/jump.ogg"))
##        AudioManager.play_music(preload("res://assets/audio/music/theme.ogg"))
##
## Music comes in two flavours. play_music() swaps a single track outright.
## play_layers()/fade_layers() run several mixes of the SAME piece at once —
## see the layered-music section below.

## Quiet enough to be inaudible without being -inf, so a layer that's faded
## out is still streaming and still in step with its siblings.
const LAYER_SILENT_DB := -60.0

var _music_player: AudioStreamPlayer
var _layers := {}         # StringName -> AudioStreamPlayer, all started together
var _layer_weights := {}  # StringName -> 0.0-1.0, so an interrupted fade resumes from where it is
var _layer_tween: Tween


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


# --- Layered music ---
# Several mixes of the same piece playing at once. Every layer is started in
# the same frame and never stopped, so they stay sample-aligned for the whole
# session however often the mix changes — a "crossfade" is only a volume move,
# never a seek or a restart. Layers must be the same length or they drift
# apart on loop.


## Start the stack. streams is {name: AudioStream}; everything begins silent,
## so follow with fade_layers() (or pass weights to start audible).
func play_layers(streams: Dictionary, weights := {}) -> void:
	stop_layers()
	for name in streams:
		var weight := clampf(weights.get(name, 0.0), 0.0, 1.0)
		var player := AudioStreamPlayer.new()
		player.stream = streams[name]
		player.bus = &"Music"
		player.volume_db = _weight_to_db(weight)
		add_child(player)
		_layers[name] = player
		_layer_weights[name] = weight
	# Second pass: every layer plays in the same frame, so they start in step.
	for player in _layers.values():
		player.play()


## Move the mix. weights is {name: 0.0-1.0}; layers you leave out fade to
## silence, so passing {&"shop": 1.0} is a full crossfade onto that layer.
##
## Weights cross linearly and are turned into amplitude by _weight_to_db, so
## the pair follows an equal-power curve: the outgoing layer hangs on longer
## and the incoming one comes up quicker, and the halfway point sums back to
## full loudness instead of sagging.
func fade_layers(weights: Dictionary, duration := 1.0) -> void:
	if _layers.is_empty():
		return
	if _layer_tween != null:
		_layer_tween.kill()
		_layer_tween = null
	var from := _layer_weights.duplicate()
	var to := {}
	for name in _layers:
		to[name] = clampf(weights.get(name, 0.0), 0.0, 1.0)
	if duration <= 0.0:
		_apply_mix(1.0, from, to)
		return
	_layer_tween = create_tween()
	_layer_tween.tween_method(_apply_mix.bind(from, to), 0.0, 1.0, duration)


func stop_layers() -> void:
	if _layer_tween != null:
		_layer_tween.kill()
		_layer_tween = null
	for player in _layers.values():
		player.queue_free()
	_layers.clear()
	_layer_weights.clear()


## One step of a crossfade: t runs 0->1 across the whole move.
func _apply_mix(t: float, from: Dictionary, to: Dictionary) -> void:
	for name in _layers:
		var weight := lerpf(from.get(name, 0.0), to.get(name, 0.0), t)
		_layer_weights[name] = weight
		_layers[name].volume_db = _weight_to_db(weight)


func is_playing_layers() -> bool:
	return not _layers.is_empty()


## Weight -> volume on an equal-power curve: amplitude is the square root of
## the weight, so two layers at 0.5 sit at -3dB each and sum back to full
## instead of the -27dB hole a straight dB ramp leaves in the middle.
func _weight_to_db(weight: float) -> float:
	var w := clampf(weight, 0.0, 1.0)
	if w <= 0.0:
		return LAYER_SILENT_DB
	return maxf(linear_to_db(sqrt(w)), LAYER_SILENT_DB)
