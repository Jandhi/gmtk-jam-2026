extends Control
## Battle scene: turn loop, input, and event playback.
## All gameplay lives in Sim — this file only sends orders in and animates
## the SimEvents that come back. Orders are played from a hand of cards:
## draw one per turn, click a card to enter targeting, click a unit to play it.

const CELL := 96
const GRID_POS := Vector2(52, 180)

const UNIT_VIEW_SCENE := preload("res://scenes/battle/unit_view.tscn")
const CARD_SCENE := preload("res://scenes/ui/card.tscn")
const CARD_BACK_TEXTURE := preload("res://assets/art/UI/card_back_red.png")
const HEALTH_BOX_TEXTURE := preload("res://assets/art/UI/health-box.png")
const CARD_SLOT_TEXTURE := preload("res://assets/art/UI/card_slot.png")

const HAND_LIMIT := 7
const OPENING_HAND := 4

const MUSIC_BATTLE := preload("res://assets/audio/music/battle_march.wav")
const MUSIC_SHOP := preload("res://assets/audio/music/shop_theme.wav")

## Arrays are variant pools — _sfx() picks one at random.
const SFX := {
	&"hit_melee": [
		preload("res://assets/audio/sfx/hit_melee_1.wav"),
		preload("res://assets/audio/sfx/hit_melee_2.wav"),
		preload("res://assets/audio/sfx/hit_melee_3.wav"),
	],
	&"shoot": preload("res://assets/audio/sfx/shoot.wav"),
	&"blast": preload("res://assets/audio/sfx/blast.wav"),
	&"line_breath": preload("res://assets/audio/sfx/line_breath.wav"),
	&"riposte": preload("res://assets/audio/sfx/riposte.wav"),
	&"shield_block": preload("res://assets/audio/sfx/shield_block.wav"),
	&"heal": preload("res://assets/audio/sfx/heal.wav"),
	&"unit_death": preload("res://assets/audio/sfx/unit_death.wav"),
	&"keep_hit_melee": preload("res://assets/audio/sfx/keep_hit_melee.wav"),
	&"keep_hit_ranged": preload("res://assets/audio/sfx/keep_hit_ranged.wav"),
	&"keep_life_lost": preload("res://assets/audio/sfx/keep_life_lost.wav"),
	&"card_draw": preload("res://assets/audio/sfx/card_draw.wav"),
	&"card_select": preload("res://assets/audio/sfx/card_select.wav"),
	&"card_play": preload("res://assets/audio/sfx/card_play.wav"),
	&"order_reject": preload("res://assets/audio/sfx/order_reject.wav"),
	&"shop_open": preload("res://assets/audio/sfx/shop_open.wav"),
	&"shop_buy": preload("res://assets/audio/sfx/shop_buy.wav"),
	&"gold_gain": preload("res://assets/audio/sfx/gold_gain.wav"),
	&"turn_tick": preload("res://assets/audio/sfx/turn_tick.wav"),
	&"battle_win": preload("res://assets/audio/sfx/battle_win.wav"),
	&"battle_lose": preload("res://assets/audio/sfx/battle_lose.wav"),
}

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

# The shop drops in every SHOP_INTERVAL ticks; bought cards join the discard.
# Gold trickles in per tick and spikes on kills.
const SHOP_INTERVAL := 20
const SHOP_STOCK := 3
const GOLD_PER_TICK := 1
const GOLD_PER_KILL := 3
const SHOP_PRICES := {
	Order.ADVANCE: 5,
	Order.RETREAT: 4,
	Order.MOVE_UP: 4,
	Order.MOVE_DOWN: 4,
	Order.DELAY: 6,
	Order.HASTEN: 8,
}
const SHOP_HIDDEN_Y := -340.0
const SHOP_SHOWN_Y := 140.0

var sim: Sim
var db: Dictionary
var views := {}  # unit_id -> UnitController (unit_view.tscn)
var busy := false

var deck: Array[StringName] = []
var discard: Array[StringName] = []
var gold := 0

var _shop_open := false
var _shop_panel: PanelContainer
var _shop_cards_box: HBoxContainer
var _shop_gold_label: Label

var _selected_card: CardController = null
var _hovered_id := -1
var _audio_unlocked := false  # web: audio may only start after a user gesture

var _status_label: Label
var _tick_label: Label
var _end_turn_btn: Button
var _hand_box: HBoxContainer
var _tooltip: PanelContainer
var _tooltip_label: Label
var _banner: Label
var _restart_btn: Button
var _draw_pile: TextureRect
var _draw_count: Label
var _discard_pile: CardController
var _discard_count: Label

# Keep displays, indexed by side. Shown values update from playback events
# (not live sim state) so the bars move when the hit lands, like unit health.
var _keep_fills: Array = [null, null]
var _keep_lives_labels: Array = [null, null]
var _shown_keep_hp: Array[int] = [Sim.KEEP_MAX_HP, Sim.KEEP_MAX_HP]
var _shown_keep_lives: Array[int] = [Sim.KEEP_LIVES, Sim.KEEP_LIVES]
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
	_refresh_views(true)
	_update_status()
	# Debug: `godot --path . -- --screenshot out.png` saves a frame and quits.
	# Add `--shop` to capture with the shop open.
	var args := OS.get_cmdline_user_args()
	if args.has("--shop"):
		_open_shop()
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
	_sfx(&"card_draw")
	var card: CardController = CARD_SCENE.instantiate()
	_hand_box.add_child(card)
	card.setup_order(type)
	card.gui_input.connect(_on_card_gui_input.bind(card))


func _on_card_gui_input(event: InputEvent, card: CardController) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_card(card)


func _toggle_card(card: CardController) -> void:
	if busy or _shop_open or sim.winner != -1:
		return
	_sfx(&"card_select")
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
		_sfx(&"order_reject")
		_float_text(unit.id, "Can't", Color(1, 0.5, 0.4))
		return
	_sfx(&"card_play")
	discard.append(card.order_type)
	_float_text(unit.id, card.name_label.text, Color(1, 0.9, 0.3))
	_selected_card = null
	card.queue_free()
	busy = true
	_update_status()
	await _play_events(events)
	busy = false
	_update_status()


# --- Audio ---


## First mouse/key press unlocks audio (web autoplay rule) and starts music.
func _input(event: InputEvent) -> void:
	if _audio_unlocked:
		return
	if (event is InputEventMouseButton or event is InputEventKey) and event.pressed:
		_audio_unlocked = true
		AudioManager.play_music(MUSIC_SHOP if _shop_open else MUSIC_BATTLE)


func _sfx(key: StringName, volume_db := 0.0) -> void:
	if not _audio_unlocked:
		return
	var stream = SFX[key]
	if stream is Array:
		stream = stream[randi() % stream.size()]
	AudioManager.play_sfx(stream, volume_db)


# --- Shop ---


func _open_shop() -> void:
	_shop_open = true
	_sfx(&"shop_open")
	if _audio_unlocked:
		AudioManager.play_music(MUSIC_SHOP)
	for c in _shop_cards_box.get_children():
		c.queue_free()
	var types := Order.ALL.duplicate()
	types.shuffle()
	for i in SHOP_STOCK:
		var card: CardController = CARD_SCENE.instantiate()
		_shop_cards_box.add_child(card)
		card.setup_order(types[i])
		card.show_cost(SHOP_PRICES[types[i]])
		card.gui_input.connect(_on_shop_card_input.bind(card))
	_refresh_shop_gold()
	var tw := create_tween()
	tw.tween_property(_shop_panel, "position:y", SHOP_SHOWN_Y, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_shop() -> void:
	_shop_open = false
	if _audio_unlocked and sim.winner == -1:
		AudioManager.play_music(MUSIC_BATTLE)
	var tw := create_tween()
	tw.tween_property(_shop_panel, "position:y", SHOP_HIDDEN_Y, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_update_status()


func _on_shop_card_input(event: InputEvent, card: CardController) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_buy_card(card)


## Bought cards go straight to the discard pile and cycle in on reshuffle.
func _buy_card(card: CardController) -> void:
	if card.get_meta("sold", false):
		return
	var price: int = SHOP_PRICES[card.order_type]
	if gold < price:
		_sfx(&"order_reject")
		card.modulate = Color(1, 0.4, 0.4)
		var tw := create_tween()
		tw.tween_property(card, "modulate", Color.WHITE, 0.3)
		return
	_sfx(&"shop_buy")
	gold -= price
	discard.append(card.order_type)
	card.set_meta("sold", true)
	card.modulate = Color(0.45, 0.45, 0.45)
	_refresh_shop_gold()
	_update_status()


func _refresh_shop_gold() -> void:
	_shop_gold_label.text = "The shop rolls in!  You have %d gold." % gold


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
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
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
		_sfx(&"order_reject")
		_float_text(u.id, "Your units only", Color(1, 0.6, 0.4))
		return
	_play_card(_selected_card, u)


func _end_turn() -> void:
	if busy or _shop_open or sim.winner != -1:
		return
	if _selected_card != null:
		_selected_card.set_selected(false)
		_selected_card = null
	busy = true
	_sfx(&"turn_tick")
	var events := sim.tick()
	gold += GOLD_PER_TICK
	_update_status()
	await _play_events(events)
	busy = false
	_draw_card()
	_update_status()
	if sim.winner == -1 and sim.tick_count % SHOP_INTERVAL == 0:
		_open_shop()


func _update_status() -> void:
	_tick_label.text = "Tick %d    Gold %d" % [sim.tick_count, gold]
	_refresh_piles()
	if busy:
		_status_label.text = "Resolving..."
		return
	if _selected_card != null:
		_status_label.text = "Targeting: %s — click a unit, or the card to cancel" % _selected_card.name_label.text
	else:
		_status_label.text = "Click a card (1-7), then a unit. Space ends the turn."


func _add_pile_slot(pos: Vector2, layer: CanvasLayer) -> void:
	var slot := TextureRect.new()
	slot.texture = CARD_SLOT_TEXTURE
	slot.position = pos
	slot.scale = Vector2(3, 3)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(slot)


func _refresh_piles() -> void:
	_draw_count.text = str(deck.size())
	_draw_pile.visible = deck.size() > 0
	_discard_count.text = str(discard.size())
	_discard_pile.visible = not discard.is_empty()
	if not discard.is_empty():
		_discard_pile.setup_order(discard.back())


## Same pixel dressing as the unit bars: health-box nine-patch, 4px border,
## fill inset 4px inside it.
func _build_keep_bar(side: int, x: float, layer: CanvasLayer) -> void:
	var bg := NinePatchRect.new()
	bg.texture = HEALTH_BOX_TEXTURE
	bg.region_rect = Rect2(0, 0, 32, 32)
	bg.patch_margin_left = 4
	bg.patch_margin_top = 4
	bg.patch_margin_right = 4
	bg.patch_margin_bottom = 4
	bg.position = Vector2(x, GRID_POS.y)
	bg.size = Vector2(16, Sim.LANES * CELL)
	layer.add_child(bg)
	var fill := ColorRect.new()
	fill.color = UnitController.PLAYER_HP_COLOR if side == Sim.SIDE_PLAYER else UnitController.ENEMY_HP_COLOR
	bg.add_child(fill)
	_keep_fills[side] = fill
	var lives := Label.new()
	lives.position = Vector2(x - 16, GRID_POS.y + Sim.LANES * CELL + 4)
	lives.size = Vector2(48, 24)
	lives.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lives.add_theme_font_size_override("font_size", 20)
	layer.add_child(lives)
	_keep_lives_labels[side] = lives
	_refresh_keep(side)


## Bar drains top-down toward empty; lives shown as "xN" beneath it.
func _refresh_keep(side: int) -> void:
	var inner_h := Sim.LANES * CELL - 8.0
	var frac := float(_shown_keep_hp[side]) / float(Sim.KEEP_MAX_HP)
	var fill: ColorRect = _keep_fills[side]
	fill.size = Vector2(8, inner_h * frac)
	fill.position = Vector2(4, 4 + inner_h * (1.0 - frac))
	_keep_lives_labels[side].text = "x%d" % _shown_keep_lives[side]


## Knock the keep bar away from the blow and settle back. Playback awaits
## longer than the shake, so tweens never overlap and home position holds.
func _shake_keep(side: int, dir: float) -> void:
	var bar: NinePatchRect = _keep_fills[side].get_parent()
	var home := bar.position.x
	var tw := create_tween()
	tw.tween_property(bar, "position:x", home + dir * 6.0, 0.05)
	tw.tween_property(bar, "position:x", home, 0.1)


func _float_keep_text(side: int, text: String, color: Color) -> void:
	var x := 8.0 if side == Sim.SIDE_PLAYER else 1180.0
	_float_text_at(Vector2(x, GRID_POS.y + 110), text, color)


func _pile_count_label(pos: Vector2, layer: CanvasLayer) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = Vector2(96, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)
	return label


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

	# Keep health bars flank the grid, sitting on the castles at each edge.
	_build_keep_bar(Sim.SIDE_PLAYER, 20, layer)
	_build_keep_bar(Sim.SIDE_ENEMY, 1244, layer)

	# Bottom-corner piles at 3/4 card size so a full hand doesn't cover them:
	# discard (left) shows the last card played, draw (right) shows the deck.
	# Empty slots sit underneath and show through when a pile runs out.
	_add_pile_slot(Vector2(8, 580), layer)
	_add_pile_slot(Vector2(1176, 580), layer)
	_discard_pile = CARD_SCENE.instantiate()
	_discard_pile.position = Vector2(8, 580)
	_discard_pile.scale = Vector2(0.75, 0.75)
	_discard_pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_discard_pile)
	_discard_count = _pile_count_label(Vector2(8, 552), layer)
	_draw_pile = TextureRect.new()
	_draw_pile.texture = CARD_BACK_TEXTURE
	_draw_pile.position = Vector2(1176, 580)
	_draw_pile.scale = Vector2(3, 3)
	_draw_pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_draw_pile)
	_draw_count = _pile_count_label(Vector2(1176, 552), layer)

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

	# Debug menu: dev helpers, not part of the game.
	var debug_btn := Button.new()
	debug_btn.text = "Debug"
	debug_btn.add_theme_font_size_override("font_size", 16)
	debug_btn.position = Vector2(940, 24)
	debug_btn.custom_minimum_size = Vector2(80, 44)
	layer.add_child(debug_btn)
	var debug_box := VBoxContainer.new()
	debug_box.position = Vector2(940, 72)
	debug_box.visible = false
	layer.add_child(debug_box)
	debug_btn.pressed.connect(func(): debug_box.visible = not debug_box.visible)
	var dbg_shop_btn := Button.new()
	dbg_shop_btn.text = "Trigger Shop"
	dbg_shop_btn.add_theme_font_size_override("font_size", 16)
	dbg_shop_btn.pressed.connect(func():
		if not _shop_open and not busy:
			_open_shop())
	debug_box.add_child(dbg_shop_btn)
	var dbg_gold_btn := Button.new()
	dbg_gold_btn.text = "+10 Gold"
	dbg_gold_btn.add_theme_font_size_override("font_size", 16)
	dbg_gold_btn.pressed.connect(func():
		gold += 10
		_update_status()
		if _shop_open:
			_refresh_shop_gold())
	debug_box.add_child(dbg_gold_btn)

	# Shop panel parks above the screen and tweens down when it opens.
	# Added last so it draws over the rest of the UI.
	_shop_panel = PanelContainer.new()
	_shop_panel.custom_minimum_size = Vector2(480, 0)
	_shop_panel.position = Vector2(400, SHOP_HIDDEN_Y)
	layer.add_child(_shop_panel)
	var shop_box := VBoxContainer.new()
	shop_box.add_theme_constant_override("separation", 12)
	_shop_panel.add_child(shop_box)
	_shop_gold_label = Label.new()
	_shop_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_gold_label.add_theme_font_size_override("font_size", 20)
	shop_box.add_child(_shop_gold_label)
	_shop_cards_box = HBoxContainer.new()
	_shop_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_cards_box.add_theme_constant_override("separation", 12)
	shop_box.add_child(_shop_cards_box)
	var leave_btn := Button.new()
	leave_btn.text = "Leave Shop"
	leave_btn.add_theme_font_size_override("font_size", 20)
	leave_btn.pressed.connect(_close_shop)
	shop_box.add_child(leave_btn)


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
			&"windup_changed", &"windup_started":
				var wv: UnitController = views.get(e.data.unit)
				if wv != null:
					wv.set_shown_windup(e.data.windup)
					if e.type == &"windup_started":
						wv.show_intent_action(e.data.action)
					await _wait(0.06)
			&"action_fired", &"shield_counter":
				var fv: UnitController = views.get(e.data.unit)
				if fv != null:
					fv.clear_intent()
				if e.type == &"action_fired":
					match e.data.action:
						&"shoot":
							_sfx(&"shoot")
						&"blast":
							_sfx(&"blast")
						&"line":
							_sfx(&"line_breath")
				_punch(e.data.unit)
				await _wait(0.12)
			&"damage_dealt":
				var text := "-%d" % e.data.amount if e.data.amount > 0 else "Blocked"
				_sfx(&"shield_block" if e.data.amount == 0 else &"hit_melee")
				_float_text(e.data.target, text, Color(1, 0.4, 0.4))
				_hit_reaction(e.data)
				var hv: UnitController = views.get(e.data.target)
				if hv != null:
					hv.apply_hp_delta(-e.data.amount)
				await _wait(0.26)
			&"healed":
				_sfx(&"heal", -6.0)
				_float_text(e.data.target, "+%d" % e.data.amount, Color(0.4, 1, 0.4))
				var heal_v: UnitController = views.get(e.data.target)
				if heal_v != null:
					heal_v.apply_hp_delta(e.data.amount)
				await _wait(0.22)
			&"riposte_triggered":
				# The counter consumes the windup: clear number + intent icon.
				var rv: UnitController = views.get(e.data.unit)
				if rv != null:
					rv.set_shown_windup(0)
					rv.clear_intent()
				_sfx(&"riposte")
				_float_text(e.data.unit, "Riposte!", Color(1, 0.9, 0.3))
				await _wait(0.18)
			&"shield_up":
				_float_text(e.data.unit, "Shield", Color(0.5, 0.7, 1))
				await _wait(0.12)
			&"keep_damaged":
				# Melee attackers lunge into the castle; the bar only drops
				# (and shakes) once the blow connects.
				var toward_keep := 1.0 if e.data.side == Sim.SIDE_ENEMY else -1.0
				var kav: UnitController = views.get(e.data.attacker)
				if kav != null and e.data.melee:
					kav.melee_attack(toward_keep)
					await _wait(0.08)
				_sfx(&"keep_hit_melee" if e.data.melee else &"keep_hit_ranged")
				_shown_keep_hp[e.data.side] = e.data.hp
				_refresh_keep(e.data.side)
				_shake_keep(e.data.side, toward_keep)
				_float_keep_text(e.data.side, "-%d" % e.data.amount, Color(1, 0.4, 0.4))
				await _wait(0.26)
			&"keep_life_lost":
				_sfx(&"keep_life_lost", -6.0)
				_shown_keep_hp[e.data.side] = e.data.hp
				_shown_keep_lives[e.data.side] = e.data.lives
				_refresh_keep(e.data.side)
				_float_keep_text(e.data.side, "Keep falls!", Color(1, 0.8, 0.3))
				await _wait(0.4)
			&"unit_died":
				var dv: UnitController = views.get(e.data.unit)
				_sfx(&"unit_death")
				if sim.get_unit(e.data.unit).side == Sim.SIDE_ENEMY:
					gold += GOLD_PER_KILL
					_sfx(&"gold_gain")
					if dv != null:
						_float_text_at(dv.position + Vector2(-16, -190), "+%dg" % GOLD_PER_KILL, Color(1, 0.85, 0.3))
				if dv != null:
					views.erase(e.data.unit)
					var tw := create_tween()
					tw.tween_property(dv, "modulate:a", 0.0, 0.25)
					tw.tween_callback(dv.queue_free)
					await tw.finished
			&"battle_ended":
				AudioManager.stop_music()
				_sfx(&"battle_win" if e.data.winner == Sim.SIDE_PLAYER else &"battle_lose")
				_banner.text = "VICTORY" if e.data.winner == Sim.SIDE_PLAYER else "DEFEAT"
				_banner.modulate = Color(0.5, 1, 0.5) if e.data.winner == Sim.SIDE_PLAYER else Color(1, 0.45, 0.45)
				_banner.visible = true
				_restart_btn.visible = true
		_refresh_views()
	_refresh_views(true)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Intents only repaint from sim state when a tick is fully replayed —
## mid-playback they are fed by windup/action events instead.
func _refresh_views(include_intents := false) -> void:
	for u in sim.alive_units():
		var v: UnitController = views.get(u.id)
		if v != null:
			v.refresh(u)
			if include_intents:
				v.refresh_intent(u, u.windup <= 0 and sim.idle_intent(u) == &"move")


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
	_float_text_at(v.position + Vector2(-16, -160), text, color)


func _float_text_at(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.position = pos
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
	
	# While targeting, outline every cell the selected card may target.
	if _selected_card != null and not busy:
		var any_target: bool = _selected_card.order_type in ANY_TARGET_CARDS
		for u in sim.alive_units():
			if any_target or u.side == Sim.SIDE_PLAYER:
				var top_left := GRID_POS + Vector2(u.col * CELL, u.lane * CELL)
				_overlay.draw_rect(Rect2(top_left, Vector2(CELL, CELL)), Color(1, 0.9, 0.2, 0.8), false, 3.0)
