class_name UnitController
extends Node2D
## Controller for unit_view.tscn. Edit the look (layout, sizes, colors, fonts)
## in the scene; this script only wires sim state into those nodes.
## Reads state via refresh(); never computes gameplay.

const PLAYER_HP_COLOR := Color(0.4, 0.9, 0.35)
const ENEMY_HP_COLOR := Color(0.9, 0.3, 0.3)

const ACTION_LABELS := {
	&"strike": "STR", &"shoot": "SHT", &"shield_strike": "SHD", &"riposte": "RIP",
	&"skirmish": "SKR", &"blast": "BLA", &"line": "LIN", &"heal": "HEA",
}

# Actions without an entry here fall back to their text label (blast/line/heal
# icons not drawn yet — see assets/art/UI/).
const ACTION_ICONS := {
	&"strike": "res://assets/art/UI/sword-icon.png",
	&"shoot": "res://assets/art/UI/target.png",
	&"shield_strike": "res://assets/art/UI/shield-icon.png",
	&"riposte": "res://assets/art/UI/reverse-icon.png",
	&"skirmish": "res://assets/art/UI/skirmish.png",
}

## Idle squash & stretch, pivoting at the feet (SpriteAnchor sits at ground level).
@export var idle_squash := 0.02
@export var idle_period := 2.0

var unit_id := 0

var _idle_tween: Tween
var _knock_tween: Tween
var _anchor_home := Vector2.ZERO

const MELEE_LUNGE := 40.0
const HIT_KNOCKBACK := 16.0

@onready var sprite_anchor: Node2D = $SpriteAnchor
@onready var sprite: Sprite2D = $SpriteAnchor/Sprite
@onready var health_bar_bg: NinePatchRect = $HealthBarBG
@onready var health_bar_fill: ColorRect = $HealthBarBG/HealthBarFill
@onready var shield_bar_fill: ColorRect = $HealthBarBG/ShieldBarFill
@onready var action_icon: Sprite2D = $ActionIcon
@onready var hover_circle: Sprite2D = $HoverCircle
@onready var delay_label: Label = $DelayLabel
@onready var action_label: Label = $ActionLabel

var _max_hp := 1
var _fill_width := 0.0
var _hover_time := 0.0

const HOVER_FPS := 2.0


func set_hovered(hovered: bool) -> void:
	hover_circle.visible = hovered
	if hovered:
		_hover_time = 0.0


func _process(delta: float) -> void:
	if hover_circle.visible:
		_hover_time += delta
		hover_circle.frame = int(_hover_time * HOVER_FPS) % hover_circle.hframes


func setup(unit: SimUnit) -> void:
	unit_id = unit.id
	_max_hp = unit.creature.health
	_fill_width = health_bar_fill.size.x
	var tex_path := "res://assets/art/Monsters/%s.PNG" % unit.creature.name
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
	# The art faces left natively, so the player's side (facing right) flips.
	sprite.flip_h = unit.side == Sim.SIDE_PLAYER
	health_bar_fill.color = PLAYER_HP_COLOR if unit.side == Sim.SIDE_PLAYER else ENEMY_HP_COLOR
	_anchor_home = sprite_anchor.position
	hover_circle.visible = false
	refresh(unit)
	_start_idle()


func _start_idle() -> void:
	# Random phase offset so the whole army doesn't bob in unison.
	var tw := create_tween()
	tw.tween_interval(randf() * idle_period)
	tw.tween_callback(_loop_idle)


func _loop_idle() -> void:
	var half := idle_period / 2.0
	var squashed := Vector2(1.0 + idle_squash, 1.0 - idle_squash)
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(sprite_anchor, "scale", squashed, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(sprite_anchor, "scale", Vector2.ONE, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## One-shot stretch (attacking): tall and narrow, then settle back to idle.
func play_stretch() -> void:
	_play_impulse(Vector2(0.85, 1.18))


## One-shot squash (taking a hit): wide and flat, then settle back to idle.
func play_squash() -> void:
	_play_impulse(Vector2(1.22, 0.82))


## Melee attack: lunge toward the defender (dir = +1 right / -1 left) and snap back.
func melee_attack(dir: float) -> void:
	play_stretch()
	_play_knock(dir * MELEE_LUNGE, 0.08, 0.14)


## Taking a hit (melee or ranged): knocked away from the attacker, then recover.
func get_hit(dir: float) -> void:
	play_squash()
	_play_knock(dir * HIT_KNOCKBACK, 0.06, 0.16)


func _play_knock(dx: float, out_time: float, back_time: float) -> void:
	if _knock_tween != null:
		_knock_tween.kill()
	sprite_anchor.position = _anchor_home
	_knock_tween = create_tween()
	_knock_tween.tween_property(sprite_anchor, "position:x", _anchor_home.x + dx, out_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_knock_tween.tween_property(sprite_anchor, "position:x", _anchor_home.x, back_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _play_impulse(peak: Vector2) -> void:
	if _idle_tween != null:
		_idle_tween.kill()
	var tw := create_tween()
	tw.tween_property(sprite_anchor, "scale", peak, 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite_anchor, "scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_loop_idle)


## Three display states: winding up (icon + number), marching (shoe),
## or genuinely inert (nothing shown).
func refresh(unit: SimUnit, moving := false) -> void:
	health_bar_fill.size.x = maxf(0.0, _fill_width * float(unit.hp) / float(_max_hp))
	delay_label.text = str(unit.windup) if unit.windup > 0 else ""
	# Active shielding shows as a blue overlay on the health bar, sized in
	# HP-equivalents of the damage reduction (full bar if it exceeds max HP).
	var shield_frac := 0.0
	if unit.shield_active:
		shield_frac = minf(float(Sim.SHIELD_REDUCTION) / float(_max_hp), 1.0)
	shield_bar_fill.size.x = _fill_width * shield_frac
	shield_bar_fill.visible = shield_frac > 0.0
	var icon_path := ""
	var fallback_label := false
	if unit.windup > 0:
		icon_path = ACTION_ICONS.get(unit.creature.action, "")
		fallback_label = icon_path.is_empty()  # blast/line/heal icons not drawn yet
	elif moving:
		icon_path = "res://assets/art/UI/shoe-icon.png"
	action_icon.flip_h = unit.windup <= 0 and moving and unit.side == Sim.SIDE_ENEMY
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		action_icon.texture = load(icon_path)
		action_icon.visible = true
		action_label.visible = false
	else:
		action_icon.visible = false
		action_label.visible = fallback_label
		if fallback_label:
			action_label.text = ACTION_LABELS.get(unit.creature.action, "?")
