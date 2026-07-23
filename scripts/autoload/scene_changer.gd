extends CanvasLayer
## Autoload: scene changes with a quick fade.
## Usage: SceneChanger.change_to("res://scenes/game.tscn")

var _fade: ColorRect


func _ready() -> void:
	layer = 100
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


func change_to(scene_path: String, fade_time := 0.25) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, fade_time)
	await tween.finished
	get_tree().change_scene_to_file(scene_path)
	tween = create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, fade_time)
