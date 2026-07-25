extends Control
## Battle scene: turn loop, input, and event playback.
## All gameplay lives in Sim — this file only sends orders in and animates
## the SimEvents that come back. Orders are played from a hand of cards:
## draw one per turn, click a card to enter targeting, click a unit to play it.

const CELL := 96
const GRID_POS := Vector2(52, 180)

const UNIT_VIEW_SCENE := preload("res://scenes/battle/unit_view.tscn")
const CARD_SCENE := preload("res://scenes/ui/card.tscn")

const HAND_LIMIT := 8
const OPENING_HAND := 4

## Starting deck: order card type -> copies.
const STARTING_DECK := {
	Order.ADVANCE: 5,
	Order.RETREAT: 3,
	Order.MOVE_UP: 3,
	Order.MOVE_DOWN: 3,
	Order.DELAY: 3,
	Order.HASTEN: 3,
}

## Tempo cards may target any unit; movement cards only your own.
const ANY_TARGET_CARDS: Array[StringName] = [Order.DELAY, Order.HASTEN]

var sim: Sim
var db: Dictionary
var views := {}  # unit_id -> UnitController (unit_view.tscn)
var busy := false

var deck: Array[StringName] = []
var discard: Array[StringName] = []

var _selected_card: CardController = null
var _hovered_id := -1

var _status_label: Label
var _tick_label: Label
var _end_turn_btn: Button
var _hand_box: HBoxContainer
var _tooltip: PanelContainer
var _tooltip_label: Label
var _banner: Label
var _restart_btn: Button
var _fx_layer: Node2D
var _overlay: Node2D  # grid + targeting highlights, above the background but below units


func _ready() -> void:
	db = CreatureDB.load_all()
	sim = Sim.new(randi())
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_spawn_armies()
	_fx_layer = Node2D.new()
	add_child(_fx_layer)
	_build_ui()
	_build_deck()
	for i in OPENING_HAND:
		_draw_card()
	_refresh_views()
	_update_status()
	# Debug: `godot --path . -- --screenshot out.png` saves a frame and quits.
	var args := OS.get_cmdline_user_args()
	var shot_idx := args.find("--screenshot")
	if shot_idx != -1:
		await _wait(1.0)
		var path := args[shot_idx + 1] if args.size() > shot_idx + 1 else "user://screenshot.png"
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()


func _spawn_armies() -> void:
	var player := [
		["Mage", 0, 0], ["Knight", 0, 1],
		["Scout", 1, 0], ["Guard", 1, 2],
		["Priest", 2, 0], ["Gladiator", 2, 1],
	]
	var enemy := [
		["Goblin", 0, 10], ["Assassin", 0, 11],
		["Wolf", 1, 9], ["Ogre", 1, 11],
		["Skeleton", 2, 10], ["Adult Red Dragon", 2, 11],
	]
	for row in player:
		_spawn_view(sim.spawn(db[row[0]], Sim.SIDE_PLAYER, row[1], row[2]))
	for row in enemy:
		_spawn_view(sim.spawn(db[row[0]], Sim.SIDE_ENEMY, row[1], row[2]))


func _spawn_view(unit: SimUnit) -> void:
	var v: UnitController = UNIT_VIEW_SCENE.instantiate()
	v.position = cell_pos(unit.lane, unit.col)
	add_child(v)
	v.setup(unit)
	views[unit.id] = v


func cell_pos(lane: int, col: int) -> Vector2:
	return GRID_POS + Vector2(col * CELL + CELL / 2.0, lane * CELL + CELL / 2.0)


func cell_at(pos: Vector2) -> Vector2i:
	var local := pos - GRID_POS
	if local.x < 0 or local.y < 0:
		return Vector2i(-1, -1)
	var col := int(local.x / CELL)
	var lane := int(local.y / CELL)
	if lane >= Sim.LANES or col >= Sim.COLS:
		return Vector2i(-1, -1)
	return Vector2i(lane, col)


# --- Cards ---


func _build_deck() -> void:
	deck.clear()
	for type in STARTING_DECK:
		for i in STARTING_DECK[type]:
			deck.append(type)
	deck.shuffle()


func _draw_card() -> void:
	if _hand_box.get_child_count() >= HAND_LIMIT:
		return
	if deck.is_empty():
		deck = discard.duplicate()
		discard.clear()
		deck.shuffle()
	if deck.is_empty():
		return
	var type: StringName = deck.pop_back()
	var card: CardController = CARD_SCENE.instantiate()
	_hand_box.add_child(card)
	card.setup_order(type)
	card.gui_input.connect(_on_card_gui_input.bind(card))


func _on_card_gui_input(event: InputEvent, card: CardController) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_card(card)


func _toggle_card(card: CardController) -> void:
	if busy or sim.winner != -1:
		return
	if _selected_card == card:
		card.set_selected(false)
		_selected_card = null
	else:
		if _selected_card != null:
			_selected_card.set_selected(false)
		_selected_card = card
		card.set_selected(true)
	_update_status()


## Orders resolve instantly (a free action that doesn't advance the clock).
## Rejected orders (blocked cell, idle unit for tempo cards) keep the card.
func _play_card(card: CardController, unit: SimUnit) -> void:
	var events := sim.apply_order(Order.make(unit.id, card.order_type))
	var applied := false
	for e in events:
		if e.type == &"order_applied":
			applied = true
	if not applied:
		_float_text(unit.id, "Can't", Color(1, 0.5, 0.4))
		return
	discard.append(card.order_type)
	_float_text(unit.id, card.name_label.text, Color(1, 0.9, 0.3))
	_selected_card = null
	card.queue_free()
	busy = true
	_update_status()
	await _play_events(events)
	busy = false
	_update_status()


# --- Input & turn loop ---


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _selected_card != null:
				_toggle_card(_selected_card)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_end_turn()
			KEY_R:
				if sim.winner != -1:
					get_tree().reload_current_scene()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				var idx: int = event.keycode - KEY_1
				if idx < _hand_box.get_child_count():
					_toggle_card(_hand_box.get_child(idx))


func _click(pos: Vector2) -> void:
	if busy or _selected_card == null:
		return
	var cell := cell_at(pos)
	if cell.x == -1:
		return
	var u := sim.unit_at(cell.x, cell.y)
	if u == null:
		return
	var own_only: bool = not (_selected_card.order_type in ANY_TARGET_CARDS)
	if own_only and u.side != Sim.SIDE_PLAYER:
		_float_text(u.id, "Your units only", Color(1, 0.6, 0.4))
		return
	_play_card(_selected_card, u)


func _end_turn() -> void:
	if busy or sim.winner != -1:
		return
	if _selected_card != null:
		_selected_card.set_selected(false)
		_selected_card = null
	busy = true
	var events := sim.tick()
	_update_status()
	await _play_events(events)
	busy = false
	_draw_card()
	_update_status()


func _update_status() -> void:
	_tick_label.text = "Tick %d" % sim.tick_count
	if busy:
		_status_label.text = "Resolving..."
		return
	var parts := ["Deck %d | Discard %d" % [deck.size(), discard.size()]]
	if _selected_card != null:
		parts.append("| Targeting: %s — click a unit, or the card to cancel" % _selected_card.name_label.text)
	else:
		parts.append("| Click a card (1-8), then a unit. Space ends the turn.")
	_status_label.text = "  ".join(parts)


# --- UI construction ---


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_tick_label = Label.new()
	_tick_label.position = Vector2(52, 24)
	_tick_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(_tick_label)

	_status_label = Label.new()
	_status_label.position = Vector2(52, 56)
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.modulate = Color(0.85, 0.85, 0.85)
	layer.add_child(_status_label)

	_hand_box = HBoxContainer.new()
	_hand_box.position = Vector2(0, 536)
	_hand_box.size = Vector2(1280, 176)
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_box.add_theme_constant_override("separation", 8)
	layer.add_child(_hand_box)

	_end_turn_btn = Button.new()
	_end_turn_btn.text = "End Turn (Space)"
	_end_turn_btn.add_theme_font_size_override("font_size", 20)
	_end_turn_btn.position = Vector2(1040, 24)
	_end_turn_btn.custom_minimum_size = Vector2(190, 44)
	_end_turn_btn.pressed.connect(_end_turn)
	layer.add_child(_end_turn_btn)

	_tooltip = PanelContainer.new()
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 20)
	_tooltip.add_child(_tooltip_label)
	_tooltip.visible = false
	layer.add_child(_tooltip)

	_banner = Label.new()
	_banner.position = Vector2(0, 280)
	_banner.size = Vector2(1280, 80)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 50)
	_banner.visible = false
	layer.add_child(_banner)

	_restart_btn = Button.new()
	_restart_btn.text = "Restart (R)"
	_restart_btn.add_theme_font_size_override("font_size", 20)
	_restart_btn.position = Vector2(580, 380)
	_restart_btn.custom_minimum_size = Vector2(120, 44)
	_restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	_restart_btn.visible = false
	layer.add_child(_restart_btn)


# --- Event playback ---


func _play_events(events: Array) -> void:
	for e in events:
		match e.type:
			&"unit_moved":
				var v: UnitController = views.get(e.data.unit)
				if v != null:
					var tw := create_tween()
					tw.tween_property(v, "position", cell_pos(e.data.lane, e.data.col), 0.12)
					await tw.finished
			&"action_fired", &"shield_counter":
				_punch(e.data.unit)
				await _wait(0.12)
			&"damage_dealt":
				var text := "-%d" % e.data.amount if e.data.amount > 0 else "Blocked"
				_float_text(e.data.target, text, Color(1, 0.4, 0.4))
				_hit_reaction(e.data)
				await _wait(0.26)
			&"healed":
				_float_text(e.data.target, "+%d" % e.data.amount, Color(0.4, 1, 0.4))
				await _wait(0.22)
			&"riposte_triggered":
				_float_text(e.data.unit, "Riposte!", Color(1, 0.9, 0.3))
				await _wait(0.18)
			&"shield_up":
				_float_text(e.data.unit, "Shield", Color(0.5, 0.7, 1))
				await _wait(0.12)
			&"unit_died":
				var dv: UnitController = views.get(e.data.unit)
				if dv != null:
					views.erase(e.data.unit)
					var tw := create_tween()
					tw.tween_property(dv, "modulate:a", 0.0, 0.25)
					tw.tween_callback(dv.queue_free)
					await tw.finished
			&"battle_ended":
				_banner.text = "VICTORY" if e.data.winner == Sim.SIDE_PLAYER else "DEFEAT"
				_banner.modulate = Color(0.5, 1, 0.5) if e.data.winner == Sim.SIDE_PLAYER else Color(1, 0.45, 0.45)
				_banner.visible = true
				_restart_btn.visible = true
		_refresh_views()
	_refresh_views()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _refresh_views() -> void:
	for u in sim.alive_units():
		var v: UnitController = views.get(u.id)
		if v != null:
			v.refresh(u, u.windup <= 0 and sim.idle_intent(u) == &"move")


func _punch(unit_id: int) -> void:
	var v: UnitController = views.get(unit_id)
	if v == null:
		return
	v.play_stretch()


## Melee: attacker lunges into the defender; any hit: defender knocked back + red flash.
func _hit_reaction(data: Dictionary) -> void:
	var av: UnitController = views.get(data.attacker)
	var tv: UnitController = views.get(data.target)
	var dir := 1.0
	if av != null and tv != null and tv.position.x != av.position.x:
		dir = signf(tv.position.x - av.position.x)
	if data.get("melee", false) and av != null:
		av.melee_attack(dir)
	if tv != null:
		tv.get_hit(dir)
		tv.modulate = Color(1, 0.3, 0.3)
		var tw := create_tween()
		tw.tween_property(tv, "modulate", Color.WHITE, 0.25)


func _float_text(unit_id: int, text: String, color: Color) -> void:
	var v: UnitController = views.get(unit_id)
	if v == null:
		return
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.position = v.position + Vector2(-16, -160)
	label.add_theme_font_size_override("font_size", 20)
	_fx_layer.add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 34, 0.7)
	tw.tween_property(label, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(label.queue_free)


# --- Hover, tooltip, overlay ---


func _process(_delta: float) -> void:
	_overlay.queue_redraw()
	_update_tooltip()


func _set_hovered(unit_id: int) -> void:
	if unit_id == _hovered_id:
		return
	var old: UnitController = views.get(_hovered_id)
	if old != null:
		old.set_hovered(false)
	var new_view: UnitController = views.get(unit_id)
	if new_view != null:
		new_view.set_hovered(true)
	_hovered_id = unit_id


func _update_tooltip() -> void:
	if busy:
		_tooltip.visible = false
		_set_hovered(-1)
		return
	var mouse := get_viewport().get_mouse_position()
	var cell := cell_at(mouse)
	var u := sim.unit_at(cell.x, cell.y) if cell.x != -1 else null
	_set_hovered(u.id if u != null else -1)
	if u == null:
		_tooltip.visible = false
		return
	var c := u.creature
	var abilities := "-" if c.abilities.is_empty() else ", ".join(c.abilities)
	_tooltip_label.text = "%s\nHP %d/%d   Armour %d\nPower %d   Delay %d   Range %d\nAction: %s   Initiative %d\nAbilities: %s\nWindup: %s" % [
		c.name, u.hp, c.health, c.armour, c.power, c.delay, c.attack_range,
		c.action, c.initiative, abilities,
		str(u.windup) if u.windup > 0 else "idle",
	]
	_tooltip.position = Vector2(minf(mouse.x + 18, 1040), minf(mouse.y + 18, 560))
	_tooltip.visible = true


## Drawn on _overlay (via its draw signal) so it renders above the painted
## background; the root's own _draw would be covered by the TextureRect child.
func _draw_overlay() -> void:
	var line_color := Color(0, 0, 0, 0.15)
	for lane in Sim.LANES + 1:
		var y := GRID_POS.y + lane * CELL
		_overlay.draw_line(Vector2(GRID_POS.x, y), Vector2(GRID_POS.x + Sim.COLS * CELL, y), line_color, 2.0)
	for col in Sim.COLS + 1:
		var x := GRID_POS.x + col * CELL
		_overlay.draw_line(Vector2(x, GRID_POS.y), Vector2(x, GRID_POS.y + Sim.LANES * CELL), line_color, 2.0)
	# While targeting, outline every cell the selected card may target.
	if _selected_card != null and not busy:
		var any_target: bool = _selected_card.order_type in ANY_TARGET_CARDS
		for u in sim.alive_units():
			if any_target or u.side == Sim.SIDE_PLAYER:
				var top_left := GRID_POS + Vector2(u.col * CELL, u.lane * CELL)
				_overlay.draw_rect(Rect2(top_left, Vector2(CELL, CELL)), Color(1, 0.9, 0.2, 0.8), false, 3.0)
