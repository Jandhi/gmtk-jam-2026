extends Node2D
## Battle scene: turn loop, input, and event playback.
## All gameplay lives in Sim — this file only sends orders in and animates
## the SimEvents that come back.

const CELL := 96
const GRID_POS := Vector2(52, 120)
const ORDERS_PER_TURN := 2

const ORDER_DEFS := [
	[Order.ADVANCE, "1 Advance"],
	[Order.RETREAT, "2 Retreat"],
	[Order.MOVE_UP, "3 Move Up"],
	[Order.MOVE_DOWN, "4 Move Down"],
	[Order.DELAY, "5 Delay +1"],
	[Order.HASTEN, "6 Hasten -1"],
]

var sim: Sim
var db: Dictionary
var views := {}  # unit_id -> UnitView
var selected_id := -1
var queued: Array = []
var busy := false

var _status_label: Label
var _tick_label: Label
var _end_turn_btn: Button
var _tooltip: PanelContainer
var _tooltip_label: Label
var _banner: Label
var _restart_btn: Button
var _fx_layer: Node2D


func _ready() -> void:
	db = CreatureDB.load_all()
	sim = Sim.new(randi())
	_spawn_armies()
	_fx_layer = Node2D.new()
	add_child(_fx_layer)
	_build_ui()
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
	var v := UnitView.new()
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


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_tick_label = Label.new()
	_tick_label.position = Vector2(52, 24)
	_tick_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(_tick_label)

	_status_label = Label.new()
	_status_label.position = Vector2(52, 56)
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.modulate = Color(0.85, 0.85, 0.85)
	layer.add_child(_status_label)

	var bar := HBoxContainer.new()
	bar.position = Vector2(52, 630)
	bar.add_theme_constant_override("separation", 10)
	layer.add_child(bar)
	for def in ORDER_DEFS:
		var btn := Button.new()
		btn.text = def[1]
		btn.custom_minimum_size = Vector2(130, 44)
		btn.pressed.connect(_queue_order.bind(def[0]))
		bar.add_child(btn)
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "End Turn (Space)"
	_end_turn_btn.custom_minimum_size = Vector2(180, 44)
	_end_turn_btn.pressed.connect(_end_turn)
	bar.add_child(_end_turn_btn)

	_tooltip = PanelContainer.new()
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 13)
	_tooltip.add_child(_tooltip_label)
	_tooltip.visible = false
	layer.add_child(_tooltip)

	_banner = Label.new()
	_banner.position = Vector2(0, 280)
	_banner.size = Vector2(1280, 80)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 52)
	_banner.visible = false
	layer.add_child(_banner)

	_restart_btn = Button.new()
	_restart_btn.text = "Restart (R)"
	_restart_btn.position = Vector2(580, 380)
	_restart_btn.custom_minimum_size = Vector2(120, 44)
	_restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	_restart_btn.visible = false
	layer.add_child(_restart_btn)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			queued.clear()
			_update_status()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_end_turn()
			KEY_R:
				if sim.winner != -1:
					get_tree().reload_current_scene()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var idx: int = event.keycode - KEY_1
				_queue_order(ORDER_DEFS[idx][0])


func _click(pos: Vector2) -> void:
	if busy:
		return
	var cell := cell_at(pos)
	selected_id = -1
	if cell.x != -1:
		var u := sim.unit_at(cell.x, cell.y)
		if u != null and u.side == Sim.SIDE_PLAYER:
			selected_id = u.id
	queue_redraw()
	_update_status()


func _queue_order(type: StringName) -> void:
	if busy or sim.winner != -1 or selected_id == -1:
		return
	if queued.size() >= ORDERS_PER_TURN:
		return
	queued.append(Order.make(selected_id, type))
	_update_status()


func _end_turn() -> void:
	if busy or sim.winner != -1:
		return
	busy = true
	selected_id = -1
	queue_redraw()
	var events := sim.tick(queued)
	queued.clear()
	_update_status()
	await _play_events(events)
	busy = false
	_update_status()


func _update_status() -> void:
	_tick_label.text = "Tick %d" % sim.tick_count
	if busy:
		_status_label.text = "Resolving..."
		return
	var parts := ["Orders: %d/%d queued" % [queued.size(), ORDERS_PER_TURN]]
	for o in queued:
		var u := sim.get_unit(o.unit_id)
		parts.append("%s->%s" % [u.creature.name, o.type])
	if selected_id != -1:
		parts.append("| Selected: %s" % sim.get_unit(selected_id).creature.name)
	else:
		parts.append("| Click one of your units, then an order. Right-click clears orders.")
	_status_label.text = "  ".join(parts)


func _play_events(events: Array) -> void:
	for e in events:
		match e.type:
			&"unit_moved":
				var v: UnitView = views.get(e.data.unit)
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
				_flash(e.data.target)
				await _wait(0.22)
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
				var dv: UnitView = views.get(e.data.unit)
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
		var v: UnitView = views.get(u.id)
		if v != null:
			v.refresh(u)


func _punch(unit_id: int) -> void:
	var v: UnitView = views.get(unit_id)
	if v == null:
		return
	var tw := create_tween()
	tw.tween_property(v, "scale", Vector2(1.25, 1.25), 0.06)
	tw.tween_property(v, "scale", Vector2.ONE, 0.06)


func _flash(unit_id: int) -> void:
	var v: UnitView = views.get(unit_id)
	if v == null:
		return
	v.modulate = Color(1, 0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(v, "modulate", Color.WHITE, 0.25)


func _float_text(unit_id: int, text: String, color: Color) -> void:
	var v: UnitView = views.get(unit_id)
	if v == null:
		return
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.position = v.position + Vector2(-16, -70)
	label.add_theme_font_size_override("font_size", 18)
	_fx_layer.add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 34, 0.7)
	tw.tween_property(label, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(label.queue_free)


func _process(_delta: float) -> void:
	queue_redraw()
	_update_tooltip()


func _update_tooltip() -> void:
	if busy:
		_tooltip.visible = false
		return
	var mouse := get_viewport().get_mouse_position()
	var cell := cell_at(mouse)
	var u := sim.unit_at(cell.x, cell.y) if cell.x != -1 else null
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


func _draw() -> void:
	for lane in Sim.LANES + 1:
		var y := GRID_POS.y + lane * CELL
		draw_line(Vector2(GRID_POS.x, y), Vector2(GRID_POS.x + Sim.COLS * CELL, y), Color(0.35, 0.35, 0.35), 2.0)
	for col in Sim.COLS + 1:
		var x := GRID_POS.x + col * CELL
		draw_line(Vector2(x, GRID_POS.y), Vector2(x, GRID_POS.y + Sim.LANES * CELL), Color(0.35, 0.35, 0.35), 2.0)
	if selected_id != -1:
		var u := sim.get_unit(selected_id)
		if u != null and u.is_alive():
			var top_left := GRID_POS + Vector2(u.col * CELL, u.lane * CELL)
			draw_rect(Rect2(top_left, Vector2(CELL, CELL)), Color(1, 0.9, 0.2), false, 3.0)
