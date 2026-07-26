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
const MOVE_ARROW_TEXTURE := preload("res://assets/art/UI/tile_arrow.png")
const MOVE_DESTINATION_TEXTURE := preload("res://assets/art/UI/destination_tile.png")

# --- Action VFX ---
# 4-frame 32x32 strips cut from assets/art/Free  Effect Bullet Impact
# Explosion 32x32 V1/ into assets/art/vfx/. Played on each unit a hit lands
# on, keyed by the attacker's action — give another action an effect by
# adding a line here. Melee fires every tick and already has a lunge and a
# knockback, so it gets the quietest strip at half the scale; the blast is
# the one that's allowed to be loud. Spares: explosion_fireball,
# explosion_puff, explosion_bloom, impact_shards, impact_sparks, impact_star.
const VFX_FRAMES := 4
# "offset" lifts the strip off the cell centre onto the body — a taller strip
# needs more lift to sit in the same place, so it's tuned per effect.
const MELEE_VFX := {"strip": preload("res://assets/art/vfx/impact_hit.png"), "scale": 2.5, "offset": -12.0}
const ACTION_VFX := {
	&"blast": {"strip": preload("res://assets/art/vfx/explosion_burst.png"), "scale": 4.0, "offset": -40.0},
	&"strike": MELEE_VFX,
	&"shield_strike": MELEE_VFX,
	&"skirmish": MELEE_VFX,
	&"riposte": MELEE_VFX,
}

const GAME_TITLE := "Toll the Hour"
# Light fill over a dark shadow: the pale red carries against the sky, and the
# dark copy behind it sharpens the silhouette. The other way round, the shadow
# sat mid-way between fill and sky and just blurred the letters.
const TITLE_COLOR := Color("d95763")
const TITLE_SHADOW_COLOR := Color("ac3232")
const TITLE_SHADOW_OFFSET := Vector2(12, 12)  # whole pixels at the art's 4x scale
const TITLE_FONT_SIZE := 120
const TITLE_POS := Vector2(0, 170)  # below the clouds, above the horizon gap
const SKY_TEXTURE := preload("res://assets/art/sky.png")
const BACKGROUND_TEXTURE := preload("res://assets/art/background.png")

## Title-screen clouds, back to front. Each drifts left at its own speed —
## the far layer barely moves, the near one is noticeably quicker, which is
## what sells the depth. Speeds are pixels per second at 1280 wide.
const CLOUD_LAYERS := [
	{"tex": preload("res://assets/art/farclouds.png"), "speed": 5.0},
	{"tex": preload("res://assets/art/medclouds.png"), "speed": 11.0},
	{"tex": preload("res://assets/art/nearclouds.png"), "speed": 24.0},
]
const MENU_PAN_TIME := 1.1  # seconds to pan from the sky down to the board
## The title card is a band of sky MENU_SCROLL tall sitting directly on top of
## the board, which starts pushed down by the same amount. Panning moves both
## by MENU_SCROLL in the same tween, so they travel locked together as one
## tall image. The board's own sky is this same colour, so the join is
## invisible and the strip of board showing below the card reads as horizon.
const MENU_SCROLL := 560.0
const SKY_COLOR := Color("5286bc")  # matches the top of background.png exactly

const HAND_LIMIT := 7
const OPENING_HAND := 3

# The duel the battle opens on: your fighter against theirs, mid-board. Both
# must exist in data/creatures.csv on the matching side.
const OPENING_PLAYER_UNIT := "Knight"
const OPENING_ENEMY_UNIT := "Wight"

# Hand layout (manual, so cards can tween freely — a container would
# overwrite animated positions on every sort).
const HAND_CARD_W := 128.0
const HAND_CARD_SEP := 8.0
const HAND_SELECTED_LIFT := -24.0
const DISCARD_PILE_POS := Vector2(8, 580)
const DRAW_PILE_POS := Vector2(1176, 580)
const PILE_CARD_SCALE := 0.75

# --- Audio (fill me in!) ---
# Drop files into assets/audio/ and replace null with preload("res://...").
# Every play call is already wired; null / empty entries stay silent.
# Arrays are variant pools — one is picked at random per play.
# Two mixes of the same piece, played as simultaneous layers so the shop
# transition is a crossfade rather than a track change — they stay in step
# for the whole session, whatever the player does.
const MUSIC_LAYERS := {
	&"battle": preload("res://assets/audio/music/theme.mp3"),
	&"shop": preload("res://assets/audio/music/theme_piano.mp3"),
}
const MUSIC_FADE := 1.2  # crossfade seconds when the shop opens/closes

const SFX := {
	&"hit_melee": [                                        # damage lands (melee & ranged)
		preload("res://assets/audio/sfx/hit1.mp3"),
		preload("res://assets/audio/sfx/hit2.mp3"),
		preload("res://assets/audio/sfx/hit3.mp3"),
	],
	&"shield_block": [                                     # 0-damage "Blocked" hit: a clang
		preload("res://assets/audio/sfx/sword.mp3"),
		preload("res://assets/audio/sfx/sword2.mp3"),
	],
	&"shoot": preload("res://assets/audio/sfx/ranged.mp3"),
	&"blast": preload("res://assets/audio/sfx/blast.mp3"),
	&"line_breath": null,                                  # no sound for this one yet
	&"riposte": preload("res://assets/audio/sfx/sword3.mp3"),
	&"heal": null,                                         # no sound for this one yet
	&"unit_death": null,                                   # side-aware, see SFX_BY_SIDE
	&"gold_gain": null,                                    # no sound for this one yet
	&"keep_hit_melee": [
		preload("res://assets/audio/sfx/castle_impact.mp3"),
		preload("res://assets/audio/sfx/castle_impact2.mp3"),
	],
	&"keep_hit_ranged": [
		preload("res://assets/audio/sfx/castle_impact.mp3"),
		preload("res://assets/audio/sfx/castle_impact2.mp3"),
	],
	&"keep_life_lost": null,                               # no sound for this one yet
	&"card_draw": preload("res://assets/audio/sfx/click1.mp3"),
	&"card_select": [
		preload("res://assets/audio/sfx/click2.mp3"),
		preload("res://assets/audio/sfx/click3.mp3"),
	],
	&"card_play": [                                        # the unit acknowledges the order
		preload("res://assets/audio/sfx/soldier_yes.mp3"),
		preload("res://assets/audio/sfx/soldier_yes2.mp3"),
		preload("res://assets/audio/sfx/soldier_alright.mp3"),
		preload("res://assets/audio/sfx/soldier_alright2.mp3"),
		preload("res://assets/audio/sfx/soldier_onmyway.mp3"),
		preload("res://assets/audio/sfx/soldier_exactly.mp3"),
		preload("res://assets/audio/sfx/soldier_iguess.mp3"),
	],
	&"order_reject": [                                     # "that can't be done, sir"
		preload("res://assets/audio/sfx/soldier_itsimpossible.mp3"),
		preload("res://assets/audio/sfx/soldier_iwouldntgothere.mp3"),
		preload("res://assets/audio/sfx/soldier_idontthinkthatistherightdirection.mp3"),
	],
	&"shop_open": preload("res://assets/audio/sfx/shopopen.mp3"),
	&"shop_buy": preload("res://assets/audio/sfx/purchase.mp3"),
	&"unit_move": [                                        # a step of the march
		preload("res://assets/audio/sfx/step1.mp3"),
		preload("res://assets/audio/sfx/step2.mp3"),
		preload("res://assets/audio/sfx/step3.mp3"),
	],
	&"turn_tick": null,                                    # no sound for this one yet
	&"battle_win": null,                                   # no sound for this one yet
	&"battle_lose": null,                                  # no sound for this one yet
}

## Sounds that depend on who it happened to: your soldiers have voices, the
## things they fight don't. Looked up by Sim.SIDE_*; falls back to silence.
const SFX_BY_SIDE := {
	&"unit_death": {
		Sim.SIDE_PLAYER: [
			preload("res://assets/audio/sfx/soldier_death1.mp3"),
			preload("res://assets/audio/sfx/soldier_death2.mp3"),
			preload("res://assets/audio/sfx/soldier_death3.mp3"),
		],
		Sim.SIDE_ENEMY: [preload("res://assets/audio/sfx/monsterdeath.mp3")],
	},
	&"unit_spawn": {                                       # reporting for duty
		Sim.SIDE_PLAYER: [
			preload("res://assets/audio/sfx/soldier_canihelpyou.mp3"),
			preload("res://assets/audio/sfx/soldier_goodmorning.mp3"),
			preload("res://assets/audio/sfx/soldier_greetings.mp3"),
		],
		Sim.SIDE_ENEMY: [],                                # the horrors don't introduce themselves
	},
	&"unit_attack": {
		Sim.SIDE_PLAYER: [
			preload("res://assets/audio/sfx/swing1.mp3"),
			preload("res://assets/audio/sfx/swing2.mp3"),
			preload("res://assets/audio/sfx/swing3.mp3"),
			preload("res://assets/audio/sfx/soldier_attack.mp3"),
			preload("res://assets/audio/sfx/soldier_grunt1.mp3"),
			preload("res://assets/audio/sfx/soldier_grunt2.mp3"),
		],
		Sim.SIDE_ENEMY: [preload("res://assets/audio/sfx/monsterattack.mp3")],
	},
}

## Your beasts take the place of the soldier pools above: they still swing,
## they just don't talk. Enemy beasts are unaffected — the monster sounds
## already suit a wolf.
const SFX_BEAST := {
	&"unit_spawn": [],                                     # no "reporting for duty"
	&"unit_death": [],                                     # no dying words
	&"unit_attack": [
		preload("res://assets/audio/sfx/swing1.mp3"),
		preload("res://assets/audio/sfx/swing2.mp3"),
		preload("res://assets/audio/sfx/swing3.mp3"),
	],
}

# --- Rules text ---
# Plain-English names and descriptions, so a tooltip never shows a raw
# identifier like "shield_strike". These are the only place the game explains
# how an action works, so they say what the unit DOES, not what it is.
const ACTION_NAMES := {
	&"strike": "Strike",
	&"shield_strike": "Shield Strike",
	&"skirmish": "Skirmish",
	&"shoot": "Volley",
	&"blast": "Blast",
	&"line": "Piercing Line",
	&"riposte": "Riposte",
	&"heal": "Mend",
	&"shoot_retreat": "Harry",
	&"summon": "Raise Dead",
}
const ACTION_BLURBS := {
	&"strike": "Every %d ticks, hits whatever stands in front of it.",
	&"shield_strike": "Raises a shield the tick before it swings, blocking %d damage. Strikes only if nothing hit it.",
	&"skirmish": "Hits the unit in front, then darts two tiles back out of reach.",
	&"shoot": "Fires down its lane at the nearest enemy within %d tiles.",
	&"blast": "Detonates on the nearest enemy in range — and everything next to them, allies included.",
	&"line": "Sends a shot down the whole lane, hitting every enemy within %d tiles.",
	&"riposte": "Holds its guard. Negates the next melee hit that lands and strikes straight back.",
	&"heal": "Restores health to the most wounded ally beside it instead of attacking.",
	&"shoot_retreat": "Looses an arrow at the nearest enemy within %d tiles, then backs away to keep its distance.",
	&"summon": "Raises a skeleton in an empty tile beside it instead of attacking.",
}
## Traits worth a line in the tooltip. Ones the sim doesn't read yet are
## deliberately absent — better silent than promising something that won't happen.
const ABILITY_BLURBS := {
	&"fast": "Fast — covers two tiles per march.",
	&"slow": "Slow — only marches every other tick.",
	&"ignores_armour": "Ignores armour entirely.",
	&"poison": "Poison — its wounds keep bleeding after the hit.",
	&"lifesteal": "Lifesteal — heals itself for the damage it deals.",
	&"missile_resist": "Missile Resist — shrugs off arrows and other shots.",
	&"heals_allies_on_attack": "Mends nearby allies every time it attacks.",
	&"summons_skeletons": "Raises skeletons to fight alongside it.",
}

## Order types with their own bark, overriding the generic card_play pool.
const SFX_BY_ORDER := {
	Order.RETREAT: preload("res://assets/audio/sfx/soldier_retreat.mp3"),
}

## Starting deck: order card type -> copies.
## Starting deck: order card type -> copies. Deliberately lean — you draw one
## a turn, so a thick deck means the tempo cards you actually want are buried.
## The shop is where you thicken it, and choose what with.
const STARTING_DECK := {
	Order.ADVANCE: 2,
	Order.RETREAT: 1,
	Order.MOVE_UP: 1,
	Order.MOVE_DOWN: 1,
	Order.DELAY: 2,
	Order.HASTEN: 2,
}

## Tempo cards may target any unit; movement cards only your own.
const ANY_TARGET_CARDS: Array[StringName] = [Order.DELAY, Order.HASTEN]

# The shop drops in every SHOP_INTERVAL ticks; bought cards join the discard.
# Gold trickles in per tick and spikes on kills.
const SHOP_INTERVAL := 20
const SHOP_STOCK := 3
const GOLD_PER_TICK := 1
const GOLD_PER_KILL := 3
## Order prices, scaled alongside the unit costs in data/creatures.csv. The
## tempo cards cost most: they're the ones that actually play the countdown.
const SHOP_PRICES := {
	Order.ADVANCE: 12,
	Order.RETREAT: 10,
	Order.MOVE_UP: 10,
	Order.MOVE_DOWN: 10,
	Order.DELAY: 15,
	Order.HASTEN: 20,
}
const SHOP_HIDDEN_X := -1300.0
const SHOP_SHOWN_X := 0.0
const SHOP_SCREEN_TEXTURE := preload("res://assets/art/shop screen.png")
const MERCHANT_TEXTURE := preload("res://assets/art/merchant.png")

var sim: Sim
var db: Dictionary
var views := {}  # unit_id -> UnitController (unit_view.tscn)
var busy := false

var deck: Array[StringName] = []
var discard: Array[StringName] = []
## Unit cards that are out on the board: unit id -> card type. The card is
## held by the unit it summoned and only reaches the discard when it dies,
## so losing reinforcements is what cycles them back into the deck.
var _deployed_cards := {}
var gold := 0

var _shop_open := false
var _shop_panel: Control
var _shop_cards_box: HBoxContainer
var _shop_gold_label: Label

var _selected_card: CardController = null
var _hovered_id := -1
var _debug_hover := false  # --hover: act as if the mouse sat on cell (0,0)
var _audio_unlocked := false  # web: audio may only start after a user gesture

var _status_label: Label
var _tick_label: Label
var _end_turn_btn: Button
var _hand_box: Control
var _tooltip: PanelContainer
var _tooltip_name: Label
var _tooltip_desc: Label
var _tooltip_abilities: Label
var _tip_hp: Label
var _tip_armour: Label
var _tip_power: Label
var _tip_delay: Label
var _tip_range: Label
var _tip_init: Label
var _banner: Label
var _hud: CanvasLayer
var _menu: Control
var _menu_ui: Control  # title/tagline/button — fades out ahead of the scenery
var _tip_panel: Control
var _tip_heading: Label
var _tip_body: Label
var _tip_close: Button
var _tips_seen := {}  # lesson key -> shown; each explainer fires once a session
var _cloud_layers: Array = []  # [TextureRect, ...] back to front, for parallax
var _restart_btn: Button
var _draw_pile: TextureRect
var _draw_count: Label
var _discard_pile: CardController
var _discard_count: Label
var _discard_drop: Control      # click target over the discard pile
var _discard_hint: PanelContainer  # "Click to discard", only while a card is up

# Keep displays, indexed by side. Shown values update from playback events
# (not live sim state) so the bars move when the hit lands, like unit health.
var _keep_fills: Array = [null, null]
var _keep_lives_labels: Array = [null, null]
var _shown_keep_hp: Array[int] = [Sim.KEEP_MAX_HP, Sim.KEEP_MAX_HP]
var _shown_keep_lives: Array[int] = [Sim.KEEP_LIVES, Sim.KEEP_LIVES]
var _fx_layer: Node2D
var _overlay: Node2D  # grid + targeting highlights, above the background but below units
var _world: Control   # board + units + fx; panned as one piece by the title screen
## One "the horde stirs" call-out per wave, not per horror. Reset each turn.
var _wave_announced := false


func _ready() -> void:
	db = CreatureDB.load_all()
	sim = Sim.new(randi())
	# Hand the sim the roster its wave director draws from. Without this the
	# enemy never reinforces — which is what the sim tests want, and what the
	# game very much does not.
	sim.enemy_pool = CreatureDB.pool(db, &"enemy")
	# What the Lich's `summon` conjures. The sim never names a creature itself,
	# so a side with no entry here simply shoots instead of summoning.
	if db.has("Skeleton"):
		sim.summon_units[Sim.SIDE_ENEMY] = db["Skeleton"]
	# Everything on the board hangs off _world so the title screen can slide it
	# as one piece. The sky card and the board then pan together and read as a
	# single camera move rather than a curtain pulling back off a static map.
	_world = Control.new()
	_world.size = Vector2(1280, 720)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)
	move_child(_world, 0)
	$TextureRect.reparent(_world)
	_world.position.y = MENU_SCROLL  # starts below the view, behind the sky
	_overlay = Node2D.new()
	_world.add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_spawn_armies()
	_fx_layer = Node2D.new()
	_world.add_child(_fx_layer)
	_build_ui()
	_build_tip_panel()
	_build_menu()  # after the HUD exists, since it hides it
	_build_deck()
	_deal_opening_hand()
	_refresh_views(true)
	_update_status()
	# Debug: `godot --path . -- --screenshot out.png` saves a frame and quits.
	# Add `--shop` to capture with the shop open.
	# `--hover` parks the mouse over the first unit cell (tooltip capture).
	# `--pan [frac]` dismisses the title card first, catching the pan at
	# `frac` of the way through (default 0.45).
	# Capture tooling, not gameplay — a release build has no business reading
	# argv or writing PNGs, least of all in a browser.
	if not OS.is_debug_build():
		return
	var args := OS.get_cmdline_user_args()
	if args.has("--shop"):
		_open_shop()
	_debug_hover = args.has("--hover")
	var shot_idx := args.find("--screenshot")
	if shot_idx != -1:
		await _wait(1.0)
		if args.has("--raze"):
			_close_menu()
			await _wait(MENU_PAN_TIME + 0.1)
			_show_tip(&"gold", "Gold",
				"That kill paid %d gold. Ending a turn pays %d more, so gold comes in faster the harder you fight.\n\nSpend it when the shop rolls in — on fresh orders, or on units to field from your own back ranks." % [GOLD_PER_KILL, GOLD_PER_TICK])
			await _wait(0.4)
		if args.has("--sel"):
			# Select the first hand card so the discard prompt is on screen.
			var hand := _hand_cards()
			if not hand.is_empty():
				_toggle_card(hand[0])
			await _wait(0.2)
		if args.has("--tip"):
			# The title card covers everything, so pan it away first, then park
			# the cursor on a shop card to capture its tooltip.
			_close_menu()
			await _wait(MENU_PAN_TIME + 0.2)
			var idx := int(args[args.find("--tip") + 1]) if args.size() > args.find("--tip") + 1 and args[args.find("--tip") + 1].is_valid_int() else 0
			var c := _shop_cards_box.get_child(idx) as Control
			Input.warp_mouse(c.get_global_rect().get_center())
			await _wait(0.2)
		if args.has("--pan"):
			_close_menu()
			var frac := float(args[args.find("--pan") + 1]) if args.size() > args.find("--pan") + 1 else 0.45
			await _wait(MENU_PAN_TIME * frac)
		var path := args[shot_idx + 1] if args.size() > shot_idx + 1 else "user://screenshot.png"
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()


func _spawn_armies() -> void:
	# One fighter each, facing off in the centre lane. Everything else you
	# field comes off unit cards from the deck, so the opening turn is about
	# spending your three orders to win that single duel.
	# Both open already winding up, so the countdowns — the thing the whole
	# game is about — are on screen before the player's first move.
	var player := [[OPENING_PLAYER_UNIT, 1, 5]]
	var enemy := [[OPENING_ENEMY_UNIT, 1, 6]]
	for row in player:
		_spawn_view(sim.spawn(db[row[0]], Sim.SIDE_PLAYER, row[1], row[2], true))
	for row in enemy:
		_spawn_view(sim.spawn(db[row[0]], Sim.SIDE_ENEMY, row[1], row[2], true))


func _spawn_view(unit: SimUnit) -> void:
	var v: UnitController = UNIT_VIEW_SCENE.instantiate()
	v.position = cell_pos(unit.lane, unit.col)
	_world.add_child(v)
	v.setup(unit)
	views[unit.id] = v
	# Silent for the opening armies (audio isn't unlocked yet) — this is for
	# units brought in mid-battle off a card.
	_sfx_unit(&"unit_spawn", unit.id)


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
	# Unit cards come from the spreadsheet's "Num in Starter Deck" column, so
	# the opening deck is designed there rather than here.
	for c in CreatureDB.pool(db, &"player"):
		for i in c.starter_count:
			deck.append(Order.unit_card(c.name))
	deck.shuffle()


## The opening hand is orders only: turn one is about winning the centre duel
## with tempo, so a hand of unit cards you can't use yet would be a dud draw.
## Unit cards stay in the deck and come up on later draws as normal.
func _deal_opening_hand() -> void:
	for i in OPENING_HAND:
		var idx := -1
		for j in range(deck.size() - 1, -1, -1):
			if not Order.is_unit_card(deck[j]):
				idx = j
				break
		if idx == -1:
			break  # deck is all unit cards; take what we can get
		# Float it to the top so the normal draw path (and its animation) runs.
		var type: StringName = deck[idx]
		deck.remove_at(idx)
		deck.append(type)
		_draw_card()


func _draw_card() -> void:
	if _hand_cards().size() >= HAND_LIMIT:
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
	_setup_card(card, type)
	card.gui_input.connect(_on_card_gui_input.bind(card))
	# Slide in from under the draw pile.
	card.position = DRAW_PILE_POS - _hand_box.position
	card.scale = Vector2(PILE_CARD_SCALE, PILE_CARD_SCALE)
	create_tween().tween_property(card, "scale", Vector2.ONE, 0.2)
	_layout_hand()


## Hand cards still animating out (played) are excluded from layout.
func _hand_cards() -> Array:
	var out := []
	for c in _hand_box.get_children():
		if not c.get_meta("dying", false):
			out.append(c)
	return out


## Tween every card to its centered slot; the selected card sits lifted.
func _layout_hand() -> void:
	var cards := _hand_cards()
	var total := cards.size() * HAND_CARD_W + maxi(cards.size() - 1, 0) * HAND_CARD_SEP
	var x0 := (1280.0 - total) / 2.0
	for i in cards.size():
		var card: Control = cards[i]
		var target := Vector2(x0 + i * (HAND_CARD_W + HAND_CARD_SEP), 0.0)
		if card == _selected_card:
			target.y = HAND_SELECTED_LIFT
		if card.has_meta("slide"):
			var old: Tween = card.get_meta("slide")
			if old.is_valid():
				old.kill()
		var tw := create_tween()
		tw.tween_property(card, "position", target, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		card.set_meta("slide", tw)


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
	_layout_hand()
	_update_status()


## Retire a played card's node. to_pile flies it onto the discard pile (the
## pile display, refreshed underneath, takes over as it lands); otherwise it
## fades where it stood — a deployed unit card isn't in the pile to land on.
func _discard_card_view(card: CardController, to_pile: bool) -> void:
	card.set_selected(false)
	card.set_meta("dying", true)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card.has_meta("slide"):
		var old: Tween = card.get_meta("slide")
		if old.is_valid():
			old.kill()
	var fly := create_tween().set_parallel(true)
	if to_pile:
		fly.tween_property(card, "position", DISCARD_PILE_POS - _hand_box.position, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fly.tween_property(card, "scale", Vector2(PILE_CARD_SCALE, PILE_CARD_SCALE), 0.28)
	else:
		fly.tween_property(card, "position:y", card.position.y - 40.0, 0.28)
		fly.tween_property(card, "modulate:a", 0.0, 0.28)
	fly.chain().tween_callback(card.queue_free)


## Unit cards deploy into an empty cell in your own back ranks. The card is
## spent but does NOT go to the discard — the unit is holding it. It only
## cycles back when that unit dies (see the unit_died handler).
func _deploy_card(card: CardController, cell: Vector2i) -> void:
	var creature: CreatureData = db[Order.card_creature(card.order_type)]
	var events := sim.deploy(creature, Sim.SIDE_PLAYER, cell.x, cell.y)
	if events.is_empty():
		_sfx_voice(&"order_reject", creature)
		var why := "Your back ranks only" if not sim.in_deploy_zone(Sim.SIDE_PLAYER, cell.y) else "Cell taken"
		_float_text_at(cell_pos(cell.x, cell.y) + Vector2(-40, -60), why, Color(1, 0.6, 0.4))
		return
	var unit_id: int = events[0].data.unit
	_deployed_cards[unit_id] = card.order_type
	_spawn_view(sim.get_unit(unit_id))
	_selected_card = null
	_discard_card_view(card, false)
	_layout_hand()
	_refresh_views()  # show the newcomer's real intent (it'll be marching)
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
	# Retreating has its own line; everything else gets a generic "yes, sir".
	# Beasts acknowledge nothing — they just do it.
	if not unit.creature.has_ability(&"beast"):
		if _audio_unlocked and SFX_BY_ORDER.has(card.order_type):
			AudioManager.play_sfx(SFX_BY_ORDER[card.order_type])
		else:
			_sfx(&"card_play")
	discard.append(card.order_type)
	_float_text(unit.id, card.name_label.text, Color(1, 0.9, 0.3))
	_selected_card = null
	_discard_card_view(card, true)
	_layout_hand()
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
		# Both layers start together; the one the player is looking at comes
		# in at full volume rather than fading up, so unlocking audio sounds
		# like the music was always there.
		AudioManager.play_layers(MUSIC_LAYERS, {&"shop" if _shop_open else &"battle": 1.0})


func _sfx(key: StringName, volume_db := 0.0) -> void:
	if not _audio_unlocked:
		return
	var stream = SFX.get(key)
	if stream is Array:
		stream = stream.pick_random() if not stream.is_empty() else null
	if stream != null:
		AudioManager.play_sfx(stream, volume_db)


## Like _sfx, but picks the pool for whoever it happened to — your soldiers
## have voices, the things they fight only make noise.
func _sfx_side(key: StringName, side: int, volume_db := 0.0) -> void:
	_play_pool(SFX_BY_SIDE.get(key, {}).get(side, []), volume_db)


## Same, resolved from a unit id. Silent if the unit is already gone. Your
## beasts swap to the wordless pool — only yours, since the enemy sounds are
## already growls and a wolf is welcome to them.
func _sfx_unit(key: StringName, unit_id: int, volume_db := 0.0) -> void:
	var u := sim.get_unit(unit_id)
	if u == null:
		return
	if u.side == Sim.SIDE_PLAYER and u.creature.has_ability(&"beast"):
		_play_pool(SFX_BEAST.get(key, []), volume_db)
		return
	_sfx_side(key, u.side, volume_db)


func _play_pool(pool, volume_db := 0.0) -> void:
	if not _audio_unlocked:
		return
	if pool is Array and not pool.is_empty():
		AudioManager.play_sfx(pool.pick_random(), volume_db)


## A spoken line, but only from something with a mouth and manners. The dog,
## the griffon and the unicorn are tagged "beast" in creatures.csv and keep
## quiet rather than answering an order with "yes, sir".
func _sfx_voice(key: StringName, creature: CreatureData, volume_db := 0.0) -> void:
	if creature != null and not creature.has_ability(&"beast"):
		_sfx(key, volume_db)


## Crossfade the music layers to match where the player is. Both keep
## streaming either way — only the balance between them moves.
func _fade_music(duration := MUSIC_FADE) -> void:
	if not _audio_unlocked:
		return
	AudioManager.fade_layers({&"shop" if _shop_open else &"battle": 1.0}, duration)


# --- Shop ---


## Everything the shop can stock: the order cards, plus a unit card for every
## creature on your roster — the shop is where the rest of the army comes from.
func _shop_pool() -> Array[StringName]:
	var pool: Array[StringName] = []
	pool.append_array(Order.ALL)
	for c in CreatureDB.pool(db, &"player"):
		pool.append(Order.unit_card(c.name))
	return pool


## Orders are priced here; units are priced by the spreadsheet's Gold Cost.
func _card_price(type: StringName) -> int:
	if Order.is_unit_card(type):
		return db[Order.card_creature(type)].cost
	return SHOP_PRICES.get(type, 0)


## Dress a card node as whichever kind of card this type is.
func _setup_card(card: CardController, type: StringName) -> void:
	if Order.is_unit_card(type):
		card.setup_unit(type, db[Order.card_creature(type)])
	else:
		card.setup_order(type)


func _open_shop() -> void:
	_shop_open = true
	_sfx(&"shop_open")
	_fade_music()
	for c in _shop_cards_box.get_children():
		c.queue_free()
	var types := _shop_pool()
	types.shuffle()
	for i in mini(SHOP_STOCK, types.size()):
		var card: CardController = CARD_SCENE.instantiate()
		_shop_cards_box.add_child(card)
		_setup_card(card, types[i])
		card.show_cost(_card_price(types[i]))
		card.gui_input.connect(_on_shop_card_input.bind(card))
	_refresh_shop_gold()
	var tw := create_tween()
	tw.tween_property(_shop_panel, "position:x", SHOP_SHOWN_X, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_shop() -> void:
	_shop_open = false
	if sim.winner == -1:
		_fade_music()
	var tw := create_tween()
	tw.tween_property(_shop_panel, "position:x", SHOP_HIDDEN_X, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_update_status()


func _on_shop_card_input(event: InputEvent, card: CardController) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_buy_card(card)


## Bought cards go straight to the discard pile and cycle in on reshuffle.
func _buy_card(card: CardController) -> void:
	if card.get_meta("sold", false):
		return
	var price: int = _card_price(card.order_type)
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
				# Space doubles as "start" while the title screen is up.
				if _menu_open():
					_close_menu()
				else:
					_end_turn()
			KEY_R:
				if sim.winner != -1:
					get_tree().reload_current_scene()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				var idx: int = event.keycode - KEY_1
				var cards := _hand_cards()
				if idx < cards.size():
					_toggle_card(cards[idx])


func _click(pos: Vector2) -> void:
	if busy or _selected_card == null:
		return
	var cell := cell_at(pos)
	if cell.x == -1:
		return
	# Unit cards target an empty cell in your own back ranks, not a unit.
	if Order.is_unit_card(_selected_card.order_type):
		_deploy_card(_selected_card, cell)
		return
	var u := sim.unit_at(cell.x, cell.y)
	if u == null:
		return
	var own_only: bool = not (_selected_card.order_type in ANY_TARGET_CARDS)
	if own_only and u.side != Sim.SIDE_PLAYER:
		_sfx_voice(&"order_reject", u.creature)
		_float_text(u.id, "Your units only", Color(1, 0.6, 0.4))
		return
	_play_card(_selected_card, u)


func _end_turn() -> void:
	if busy or _shop_open or _menu_open() or sim.winner != -1:
		return
	if _selected_card != null:
		_selected_card.set_selected(false)
		_selected_card = null
		_layout_hand()
	busy = true
	_sfx(&"turn_tick")
	var events := sim.tick()
	gold += GOLD_PER_TICK
	_wave_announced = false
	_update_status()
	await _play_events(events)
	busy = false
	_draw_card()
	_update_status()
	if sim.winner == -1 and sim.tick_count % SHOP_INTERVAL == 0:
		_open_shop()


func _update_status() -> void:
	# The wave countdown is on the HUD on purpose: knowing the horde is two ticks
	# out is exactly the information Delay/Hasten are for.
	var until_wave: int = maxi(sim.next_wave_tick() - sim.tick_count, 0)
	_tick_label.text = "Tick %d    Gold %d    Wave in %d" % [sim.tick_count, gold, until_wave]
	_refresh_piles()
	if _discard_hint != null:
		_discard_hint.visible = _selected_card != null and not busy and not _shop_open
	if busy:
		_status_label.text = "Resolving..."
		return
	if _selected_card != null:
		if Order.is_unit_card(_selected_card.order_type):
			_status_label.text = "Deploying: %s — click a highlighted back-rank cell, or the card to cancel" % _selected_card.name_label.text
		else:
			_status_label.text = "Targeting: %s — click a unit, or the card to cancel" % _selected_card.name_label.text
	else:
		_status_label.text = "Click a card (1-7), then a unit. Space ends the turn."


func _on_discard_pile_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_discard_selected()


## Bin the selected card. Free, but it costs you the card — the point is to
## clear a hand clogged with orders you can't use, not to filter for free.
func _discard_selected() -> void:
	if busy or _shop_open or _menu_open() or _selected_card == null:
		return
	var card := _selected_card
	_selected_card = null
	discard.append(card.order_type)
	_sfx(&"card_select")
	_discard_card_view(card, true)
	_layout_hand()
	_update_status()


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


## One icon + value cell for the tooltip stat rows. Returns the value label.
func _tip_stat(row: HBoxContainer, icon_path: String) -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	row.add_child(box)
	var icon := TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 20)
	box.add_child(label)
	return label


func _pile_count_label(pos: Vector2, layer: CanvasLayer) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = Vector2(96, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)
	return label


# --- UI construction ---


## Title screen laid over the board. It sits on its own CanvasLayer above the
## rest of the UI and eats clicks, so nothing behind it can be played until
## it's dismissed. Dismissing is also what unlocks audio on the web.
func _build_menu() -> void:
	_hud.visible = false  # no tick counter, gold or cards behind the title
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	_menu = Control.new()
	_menu.size = Vector2(1280, 720)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks on the board
	menu_layer.add_child(_menu)

	# The title card IS the sky sitting above the battlefield — Begin pans the
	# view down to the board by sliding this whole card up out of frame.
	# Flat fill rather than sky.png: the art's sky is a single colour with the
	# clouds painted in, and we want those clouds as separate moving layers.
	# A ColorRect also takes any height without distorting a 4x-scaled sprite.
	var sky := ColorRect.new()
	sky.color = SKY_COLOR
	sky.size = Vector2(1280, MENU_SCROLL)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(sky)

	# Each layer is two copies side by side; scrolling the pair left and
	# wrapping at one screen width makes an endless drift with no seam.
	for layer in CLOUD_LAYERS:
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.set_meta("speed", layer.speed)
		for i in 2:
			var copy := TextureRect.new()
			copy.texture = layer.tex
			copy.position = Vector2(i * 1280, 0)
			copy.size = Vector2(1280, 720)
			copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(copy)
		_menu.add_child(holder)
		_cloud_layers.append(holder)

	# No painted horizon needed: the real board is sitting right below the card
	# already, showing its own treeline through the gap.

	# Title text lives on its own layer so it can clear out early: the scenery
	# only pans far enough to line up with the board, which isn't far enough to
	# carry the button and hint off the top of the screen.
	_menu_ui = Control.new()
	_menu_ui.size = Vector2(1280, 720)
	_menu_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE  # children still clickable
	_menu.add_child(_menu_ui)

	# Pixel-art drop shadow: a second copy of the title sitting behind the
	# first, offset a whole number of pixels. A font outline was the obvious
	# approach, but its thickness never lands on clean pixels at this size.
	# Added first so it draws underneath.
	_menu_ui.add_child(_title_copy(TITLE_SHADOW_OFFSET, TITLE_SHADOW_COLOR))
	_menu_ui.add_child(_title_copy(Vector2.ZERO, TITLE_COLOR))

	var tagline := Label.new()
	tagline.text = "Every unit fights on a countdown. Spend your orders to win the beat."
	tagline.position = Vector2(0, 330)
	tagline.size = Vector2(1280, 40)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 22)
	# Dark text: this sits on the pale sky, not on the dimmed board it used to.
	tagline.add_theme_color_override("font_color", Color("222034"))
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_ui.add_child(tagline)

	# Hand-styled rather than the default Godot widget, which reads as an OS
	# control next to pixel art. Square corners, a hard 4px border (one art
	# pixel at 4x), and palette colours pulled from the title.
	var begin := Button.new()
	begin.text = "Begin"
	begin.add_theme_font_size_override("font_size", 34)
	begin.add_theme_color_override("font_color", Color("f4e7d3"))
	begin.add_theme_color_override("font_hover_color", Color("ffffff"))
	begin.add_theme_stylebox_override("normal", _menu_button_style(Color("222034")))
	begin.add_theme_stylebox_override("hover", _menu_button_style(Color("ac3232")))
	begin.add_theme_stylebox_override("pressed", _menu_button_style(Color("45283c")))
	begin.add_theme_stylebox_override("focus", _menu_button_style(Color("222034")))
	begin.position = Vector2(520, 396)
	begin.custom_minimum_size = Vector2(240, 72)
	begin.size = Vector2(240, 72)
	begin.pressed.connect(_close_menu)
	_menu_ui.add_child(begin)

	var hint := Label.new()
	hint.text = "or press Space"
	hint.position = Vector2(0, 480)
	hint.size = Vector2(1280, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color("3f3f74"))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_ui.add_child(hint)


## One-shot explainer, keyed so each lesson shows once per session. Called at
## the moment the rule first bites — playback awaits it, so the board holds
## still until it's dismissed and nothing animates away behind the text.
## Teach only the rules a player can't infer from watching; every one of these
## interrupts the game.
func _show_tip(key: StringName, heading: String, body: String) -> void:
	if _tips_seen.has(key) or _tip_panel == null:
		return
	_tips_seen[key] = true
	_tip_heading.text = heading
	_tip_body.text = body
	_tip_panel.modulate.a = 0.0
	_tip_panel.visible = true
	create_tween().tween_property(_tip_panel, "modulate:a", 1.0, 0.25)
	await _tip_close.pressed
	_sfx(&"card_select")
	var tw := create_tween()
	tw.tween_property(_tip_panel, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): _tip_panel.visible = false)
	await tw.finished


func _build_tip_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5  # over the HUD, under the title card
	add_child(layer)
	_tip_panel = Control.new()
	_tip_panel.size = Vector2(1280, 720)
	_tip_panel.visible = false
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing plays behind it
	layer.add_child(_tip_panel)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("222034f2")
	box.border_color = TITLE_COLOR
	box.set_border_width_all(4)
	box.set_corner_radius_all(0)
	box.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", box)
	panel.position = Vector2(300, 210)
	panel.custom_minimum_size = Vector2(680, 0)
	panel.size = Vector2(680, 0)
	_tip_panel.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	_tip_heading = Label.new()
	_tip_heading.add_theme_font_size_override("font_size", 34)
	_tip_heading.add_theme_color_override("font_color", TITLE_COLOR)
	col.add_child(_tip_heading)

	_tip_body = Label.new()
	_tip_body.add_theme_font_size_override("font_size", 19)
	_tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_body.custom_minimum_size = Vector2(630, 0)
	col.add_child(_tip_body)

	_tip_close = Button.new()
	_tip_close.text = "Got it  ✕"
	_tip_close.add_theme_font_size_override("font_size", 22)
	_tip_close.add_theme_color_override("font_color", Color("f4e7d3"))
	_tip_close.add_theme_stylebox_override("normal", _menu_button_style(Color("45283c")))
	_tip_close.add_theme_stylebox_override("hover", _menu_button_style(Color("ac3232")))
	_tip_close.add_theme_stylebox_override("pressed", _menu_button_style(Color("222034")))
	_tip_close.add_theme_stylebox_override("focus", _menu_button_style(Color("45283c")))
	_tip_close.custom_minimum_size = Vector2(0, 52)
	col.add_child(_tip_close)


## Flat, square-cornered button face — pixel art has no rounded corners.
func _menu_button_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = TITLE_COLOR
	s.set_border_width_all(4)
	s.set_corner_radius_all(0)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## One layer of the title. Two of these stacked make the drop shadow.
func _title_copy(offset: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.text = GAME_TITLE
	l.position = TITLE_POS + offset
	l.size = Vector2(1280, 160)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _close_menu() -> void:
	if _menu == null or not _menu.visible:
		return
	_sfx(&"card_select")
	# Sky up and board up by the same distance, in the same tween with the same
	# easing, so they move as one image. The card ends fully off the top and
	# the board lands exactly in place.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_menu, "position:y", -MENU_SCROLL, MENU_PAN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_world, "position:y", 0.0, MENU_PAN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# Text clears out early — it shouldn't ride the scroll down over the board.
	tw.tween_property(_menu_ui, "modulate:a", 0.0, MENU_PAN_TIME * 0.4)
	# HUD only once the board has landed, or it would sit at its final spot
	# while the board underneath was still moving. CanvasLayers can't fade.
	tw.chain().tween_callback(func():
		_menu.visible = false
		_hud.visible = true)
	_update_status()


## Dev-only shortcuts, gated on OS.is_debug_build() so they exist when running
## from the editor and vanish from the exported build. build_web.sh and CI both
## use --export-release, so nothing here ships to itch.
func _build_debug_menu(layer: CanvasLayer) -> void:
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
	var dbg_wave_btn := Button.new()
	dbg_wave_btn.text = "Force Wave"
	dbg_wave_btn.add_theme_font_size_override("font_size", 16)
	dbg_wave_btn.pressed.connect(func():
		sim.force_wave()
		_update_status())
	debug_box.add_child(dbg_wave_btn)


func _menu_open() -> bool:
	return _menu != null and _menu.visible


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# Everything the HUD owns hangs off this, so the title screen can hide the
	# lot in one go rather than tracking each widget.
	_hud = layer

	_tick_label = Label.new()
	_tick_label.position = Vector2(52, 24)
	_tick_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(_tick_label)

	_status_label = Label.new()
	_status_label.position = Vector2(52, 56)
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.modulate = Color(0.85, 0.85, 0.85)
	layer.add_child(_status_label)

	_hand_box = Control.new()
	_hand_box.position = Vector2(0, 536)
	_hand_box.size = Vector2(1280, 176)
	_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# Click target over the discard pile. With a card selected, clicking here
	# throws it away — a way out of a hand full of orders you can't use.
	_discard_drop = Control.new()
	_discard_drop.position = DISCARD_PILE_POS
	_discard_drop.size = Vector2(HAND_CARD_W, 176) * PILE_CARD_SCALE
	_discard_drop.mouse_filter = Control.MOUSE_FILTER_STOP
	_discard_drop.gui_input.connect(_on_discard_pile_input)
	layer.add_child(_discard_drop)
	# Prompt above the pile, shown only while something is selected.
	_discard_hint = PanelContainer.new()
	var hint_box := StyleBoxFlat.new()
	hint_box.bg_color = Color("222034ee")
	hint_box.border_color = TITLE_COLOR
	hint_box.set_border_width_all(3)
	hint_box.set_corner_radius_all(0)
	hint_box.set_content_margin_all(8)
	_discard_hint.add_theme_stylebox_override("panel", hint_box)
	_discard_hint.position = Vector2(8, 496)
	_discard_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_hint.visible = false
	var hint_label := Label.new()
	hint_label.text = "Click to discard"
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", Color("f4e7d3"))
	_discard_hint.add_child(hint_label)
	layer.add_child(_discard_hint)
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

	# Unit tooltip: name, two icon-stat rows, abilities line.
	_tooltip = PanelContainer.new()
	_tooltip.visible = false
	# Above the shop panel, which is built after this and would otherwise
	# cover the tooltip for the very cards it's describing.
	_tooltip.z_index = 100
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Opaque panel: the default theme's is see-through, which over the shop
	# art made the text unreadable.
	var tip_bg := StyleBoxFlat.new()
	tip_bg.bg_color = Color("222034ee")
	tip_bg.border_color = Color("4e4a4e")
	tip_bg.set_border_width_all(3)
	tip_bg.set_corner_radius_all(0)
	tip_bg.set_content_margin_all(10)
	_tooltip.add_theme_stylebox_override("panel", tip_bg)
	layer.add_child(_tooltip)
	var tip_box := VBoxContainer.new()
	tip_box.add_theme_constant_override("separation", 4)
	_tooltip.add_child(tip_box)
	_tooltip_name = Label.new()
	_tooltip_name.add_theme_font_size_override("font_size", 20)
	tip_box.add_child(_tooltip_name)
	# What the unit actually does, in words. Wrapped to a readable measure —
	# this is most players' only explanation of how an action works.
	_tooltip_desc = Label.new()
	_tooltip_desc.add_theme_font_size_override("font_size", 15)
	_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_desc.custom_minimum_size = Vector2(300, 0)
	_tooltip_desc.modulate = Color(0.85, 0.85, 0.85)
	tip_box.add_child(_tooltip_desc)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 16)
	tip_box.add_child(row1)
	_tip_hp = _tip_stat(row1, "res://assets/art/UI/heart.png")
	_tip_armour = _tip_stat(row1, "res://assets/art/UI/chestplate.png")
	_tip_power = _tip_stat(row1, "res://assets/art/UI/sword-icon.png")
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	tip_box.add_child(row2)
	_tip_delay = _tip_stat(row2, "res://assets/art/UI/hourglass.png")
	_tip_range = _tip_stat(row2, "res://assets/art/UI/target.png")
	_tip_init = _tip_stat(row2, "res://assets/art/UI/lightning.png")
	_tooltip_abilities = Label.new()
	_tooltip_abilities.add_theme_font_size_override("font_size", 16)
	_tooltip_abilities.modulate = Color(1, 0.9, 0.6)
	tip_box.add_child(_tooltip_abilities)

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

	# Dev helpers only — never built into what players get.
	if OS.is_debug_build():
		_build_debug_menu(layer)

	# Shop: hanging-board art on a full-screen (320x180 @ 4x) canvas, parked
	# off the left edge; opening slides it in, merchant first. Added last so
	# it draws over the rest of the UI. Content is positioned inside the
	# board, which spans roughly (140,108)..(1140,520) on screen.
	_shop_panel = Control.new()
	_shop_panel.position = Vector2(SHOP_HIDDEN_X, 0)
	_shop_panel.size = Vector2(1280, 720)
	_shop_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(_shop_panel)
	var shop_tex := TextureRect.new()
	shop_tex.texture = SHOP_SCREEN_TEXTURE
	shop_tex.scale = Vector2(4, 4)
	shop_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_panel.add_child(shop_tex)
	# The merchant shares the same full-screen canvas, presenting the wares.
	var merchant_tex := TextureRect.new()
	merchant_tex.texture = MERCHANT_TEXTURE
	merchant_tex.scale = Vector2(4, 4)
	merchant_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_panel.add_child(merchant_tex)
	_shop_gold_label = Label.new()
	_shop_gold_label.position = Vector2(140, 124)
	_shop_gold_label.size = Vector2(1000, 28)
	_shop_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_gold_label.add_theme_font_size_override("font_size", 20)
	_shop_panel.add_child(_shop_gold_label)
	_shop_cards_box = HBoxContainer.new()
	_shop_cards_box.position = Vector2(140, 196)
	_shop_cards_box.size = Vector2(1000, 176)
	_shop_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_cards_box.add_theme_constant_override("separation", 24)
	_shop_panel.add_child(_shop_cards_box)
	var leave_btn := Button.new()
	leave_btn.text = "Leave Shop"
	leave_btn.add_theme_font_size_override("font_size", 20)
	leave_btn.position = Vector2(565, 440)
	leave_btn.custom_minimum_size = Vector2(150, 44)
	leave_btn.pressed.connect(_close_shop)
	_shop_panel.add_child(leave_btn)


# --- Event playback ---


func _play_events(events: Array) -> void:
	for e in events:
		match e.type:
			&"unit_deployed":
				# Enemy reinforcements, walking on at the top of the tick. Player
				# deploys go through _deploy_card, which spawns its own view
				# outside playback, so those events never reach here — the
				# views check keeps it that way if that ever changes.
				var nu := sim.get_unit(e.data.unit)
				if nu != null and not views.has(e.data.unit):
					_spawn_view(nu)
					_wave_entrance(e.data.unit)
					if e.data.get("wave", false) and not _wave_announced:
						_wave_announced = true
						_float_keep_text(Sim.SIDE_ENEMY, "The horde stirs!", Color(1, 0.5, 0.5))
					await _wait(0.18)
			&"unit_moved":
				var v: UnitController = views.get(e.data.unit)
				if v != null:
					_sfx(&"unit_move")
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
					# The unit's own effort (a grunt, or a growl), then the
					# sound the action itself makes.
					_sfx_unit(&"unit_attack", e.data.unit)
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
				var atk := sim.get_unit(e.data.attacker)
				if atk != null and ACTION_VFX.has(atk.creature.action):
					_play_vfx(e.data.target, ACTION_VFX[atk.creature.action])
				_float_text(e.data.target, text, Color(1, 0.4, 0.4))
				_hit_reaction(e.data)
				var hv: UnitController = views.get(e.data.target)
				if hv != null:
					hv.apply_hp_delta(-e.data.amount)
				await _wait(0.26)
			&"poison_applied":
				_float_text(e.data.unit, "Poisoned", Color(0.6, 1, 0.4))
				await _wait(0.12)
			&"poison_ticked":
				# No attacker to lunge and no hit to flash — rot just eats a
				# point off the bar, which is the whole read.
				_float_text(e.data.unit, "-%d" % e.data.amount, Color(0.6, 1, 0.4))
				var pv: UnitController = views.get(e.data.unit)
				if pv != null:
					pv.apply_hp_delta(-e.data.amount)
				await _wait(0.2)
			&"healed":
				_sfx(&"heal")
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
				_sfx(&"keep_life_lost")
				_shown_keep_hp[e.data.side] = e.data.hp
				_shown_keep_lives[e.data.side] = e.data.lives
				_refresh_keep(e.data.side)
				_float_keep_text(e.data.side, "Keep falls!", Color(1, 0.8, 0.3))
				await _wait(0.4)
				# Explain the raze the first time it happens: the armies are
				# about to vanish and nothing else in the game says why.
				await _show_tip(&"raze", "The keep falls",
					"Breaking a keep costs the attacker everything. The army that broke it is razed where it stands — yours or theirs.\n\nEach keep has three lives. Take all three to win, but you will have to rebuild in between.")
			&"unit_died":
				var dv: UnitController = views.get(e.data.unit)
				_sfx_unit(&"unit_death", e.data.unit)
				# A deployed unit was holding its card; dying releases it into
				# the discard, so losing reinforcements cycles them back in.
				if _deployed_cards.has(e.data.unit):
					discard.append(_deployed_cards[e.data.unit])
					_deployed_cards.erase(e.data.unit)
				if sim.get_unit(e.data.unit).side == Sim.SIDE_ENEMY:
					gold += GOLD_PER_KILL
					_sfx(&"gold_gain")
					if dv != null:
						_float_text_at(dv.position + Vector2(-16, -190), "+%dg" % GOLD_PER_KILL, Color(1, 0.85, 0.3))
					# First kill: the +Ng that just floated up needs explaining,
					# and so does the trickle they've been earning all along.
					await _show_tip(&"gold", "Gold",
						"That kill paid %d gold. Ending a turn pays %d more, so gold comes in faster the harder you fight.\n\nSpend it when the shop rolls in — on fresh orders, or on units to field from your own back ranks." % [GOLD_PER_KILL, GOLD_PER_TICK])
				if dv != null:
					views.erase(e.data.unit)
					# Razed by a keep breach: go up in smoke rather than fading
					# quietly. The whole army goes at once, so these aren't
					# awaited one at a time.
					var razed: bool = e.data.get("razed", false)
					if razed:
						_play_vfx_at(dv.position, ACTION_VFX[&"blast"])
					var tw := create_tween()
					tw.tween_property(dv, "modulate:a", 0.0, 0.25)
					tw.tween_callback(dv.queue_free)
					if not razed:
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


## Play a one-shot effect strip centred on a unit, then throw it away. The
## strip is a plain Sprite2D stepped by a tween rather than an AnimatedSprite,
## so adding an effect is just dropping a PNG in assets/art/vfx/.
func _play_vfx(unit_id: int, vfx: Dictionary) -> void:
	var v: UnitController = views.get(unit_id)
	if v != null:
		_play_vfx_at(v.position, vfx)


## Reinforcements fade up and settle rather than popping in at full size — the
## wave arrives mid-tick, so without this the eye reads it as a rendering glitch
## in the middle of the fighting rather than as new arrivals.
func _wave_entrance(unit_id: int) -> void:
	var v: UnitController = views.get(unit_id)
	if v == null:
		return
	var home := v.position
	v.position = home + Vector2(0, -28)
	v.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(v, "modulate:a", 1.0, 0.22)
	tw.tween_property(v, "position", home, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Same, at a bare position — for effects that outlive the view they belong to.
func _play_vfx_at(pos: Vector2, vfx: Dictionary) -> void:
	var s := Sprite2D.new()
	s.texture = vfx.strip
	s.hframes = VFX_FRAMES
	s.scale = Vector2(vfx.scale, vfx.scale)
	s.position = pos + Vector2(0, vfx.offset)
	_fx_layer.add_child(s)
	var tw := create_tween()
	for f in VFX_FRAMES:
		tw.tween_callback(s.set_frame.bind(f))
		tw.tween_interval(0.06)
	tw.tween_callback(s.queue_free)


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


func _process(delta: float) -> void:
	_overlay.queue_redraw()
	_update_tooltip()
	if _menu_open():
		_drift_clouds(delta)


## Slide each cloud pair left, wrapping at one screen width. fmod keeps the
## offset in (-1280, 0], so the trailing copy is always covering the gap.
func _drift_clouds(delta: float) -> void:
	for holder in _cloud_layers:
		var speed: float = holder.get_meta("speed")
		holder.position.x = fmod(holder.position.x - speed * delta, 1280.0)


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
	_refresh_damage_preview()


## Mark the health of everyone the hovered unit's pending attack would take
## off. Cleared while busy — the bars lag the sim during playback, so a
## preview drawn against them would sit at the wrong place.
func _refresh_damage_preview() -> void:
	var damage := {}
	var hu: SimUnit = sim.get_unit(_hovered_id) if _hovered_id != -1 else null
	if hu != null and hu.is_alive() and not busy:
		damage = sim.intent_preview(hu).damage
	for id in views:
		views[id].show_damage_preview(damage.get(id, 0))


func _update_tooltip() -> void:
	if busy:
		_tooltip.visible = false
		_set_hovered(-1)
		return
	var mouse := get_viewport().get_mouse_position()
	# A unit card under the cursor wins over the board: it's what you're
	# reading right now, whether that's in hand or on the shop shelf.
	var card := _unit_card_at(mouse)
	if card != null:
		_set_hovered(-1)
		_fill_tooltip(db[Order.card_creature(card.order_type)], -1, -1)
		_place_tooltip_beside(card.get_global_rect())
		return
	var cell := cell_at(mouse)
	var u := sim.unit_at(cell.x, cell.y) if cell.x != -1 else null
	if _debug_hover and u == null:
		u = sim.unit_at(0, 1)
	_set_hovered(u.id if u != null else -1)
	if u == null:
		_tooltip.visible = false
		return
	_fill_tooltip(u.creature, u.hp, u.windup)
	_place_tooltip(mouse)


## Whichever unit card is under `pos` — hand or shop — or null. Order cards
## have no creature to describe and fall through to the board.
func _unit_card_at(pos: Vector2) -> CardController:
	var cards := _hand_cards()
	if _shop_open:
		for c in _shop_cards_box.get_children():
			if c is CardController:
				cards.append(c)
	for card in cards:
		if not Order.is_unit_card(card.order_type):
			continue
		if card.get_global_rect().has_point(pos):
			return card
	return null


## Fill the tooltip for a creature. `hp`/`windup` come from a unit on the
## board; pass -1 for a card, which has no live state to show yet.
func _fill_tooltip(c: CreatureData, hp: int, windup: int) -> void:
	_tooltip_name.text = "%s — %s" % [c.name, ACTION_NAMES.get(c.action, String(c.action))]
	# Blurbs take at most one number: the cadence for a plain strike, the
	# block for a shield, the reach for anything that fires down a lane.
	var blurb: String = ACTION_BLURBS.get(c.action, "")
	if blurb.contains("%d"):
		match c.action:
			&"strike":
				blurb = blurb % c.delay
			&"shield_strike":
				blurb = blurb % Sim.SHIELD_REDUCTION
			_:
				blurb = blurb % c.attack_range
	for a in c.abilities:
		if ABILITY_BLURBS.has(a):
			blurb += "\n" + ABILITY_BLURBS[a]
	_tooltip_desc.text = blurb
	_tooltip_desc.visible = not blurb.is_empty()
	_tip_hp.text = "%d/%d" % [hp, c.health] if hp >= 0 else str(c.health)
	_tip_armour.text = str(c.armour)
	_tip_power.text = str(c.power)
	_tip_delay.text = "%d (%d!)" % [c.delay, windup] if windup > 0 else str(c.delay)
	_tip_range.text = str(c.attack_range)
	_tip_init.text = str(c.initiative)
	# No raw trait list: ABILITY_BLURBS above already spells out every trait
	# that does something, and the list leaked internal tags like "beast".
	_tooltip_abilities.visible = false


## Park the tooltip beside a card rather than under the cursor — the cursor is
## on the card, so anchoring to it always covered the thing being described.
## Prefers the card's right, flips to its left when that would run off screen.
func _place_tooltip_beside(card: Rect2) -> void:
	_tooltip.reset_size()
	var s := _tooltip.size
	const PAD := 12.0
	var x := card.position.x + card.size.x + PAD
	if x + s.x > 1280.0:
		x = card.position.x - PAD - s.x
	# Top-aligned with the card, pulled up if a tall panel would overhang.
	var y := minf(card.position.y, 720.0 - s.y - 8.0)
	_tooltip.position = Vector2(maxf(x, 8.0), maxf(y, 8.0))
	_tooltip.visible = true


## Park the tooltip near the cursor. When it won't fit on the usual side it
## flips to the other one rather than being clamped.
func _place_tooltip(mouse: Vector2) -> void:
	_tooltip.reset_size()
	var s := _tooltip.size
	const PAD := 18.0
	var x := mouse.x + PAD
	if x + s.x > 1280.0:
		x = mouse.x - PAD - s.x   # flip to the left of the cursor
	var y := mouse.y + PAD
	if y + s.y > 720.0:
		y = mouse.y - PAD - s.y   # flip above the cursor
	# Last resort if it fits on neither side: keep it on screen.
	_tooltip.position = Vector2(maxf(x, 8.0), maxf(y, 8.0))
	_tooltip.visible = true


## Drawn on _overlay (via its draw signal) so it renders above the painted
## background; the root's own _draw would be covered by the TextureRect child.
func _draw_overlay() -> void:
	var line_color := Color(0, 0, 0, 0.15)
	
	# While targeting, outline every cell the selected card may target: empty
	# back-rank cells for a unit card, otherwise the units it can be played on.
	if _selected_card != null and not busy:
		if Order.is_unit_card(_selected_card.order_type):
			for cell in sim.deploy_cells(Sim.SIDE_PLAYER):
				_draw_cell_highlight(cell, Color(0.4, 0.8, 1, 0.18), Color(0.5, 0.85, 1, 0.9))
		else:
			var any_target: bool = _selected_card.order_type in ANY_TARGET_CARDS
			for u in sim.alive_units():
				if any_target or u.side == Sim.SIDE_PLAYER:
					var top_left := GRID_POS + Vector2(u.col * CELL, u.lane * CELL)
					_overlay.draw_rect(Rect2(top_left, Vector2(CELL, CELL)), Color(1, 0.9, 0.2, 0.8), false, 3.0)
	# Hovered unit: preview where its intent lands (red = hit, white = march
	# destination, green = heal target; keep hits mark the off-grid tile).
	if _hovered_id != -1 and not busy:
		var hu := sim.get_unit(_hovered_id)
		if hu != null and hu.is_alive():
			var prev := sim.intent_preview(hu)
			for cell in prev.move:
				_draw_move_arrow(cell, sim.forward(hu.side))
			if not prev.move.is_empty():
				var dest: Vector2i = prev.move[-1]
				var dest_pos := cell_pos(dest.x, dest.y) - Vector2(CELL, CELL) / 2.0
				_overlay.draw_texture_rect(MOVE_DESTINATION_TEXTURE, Rect2(dest_pos, Vector2(CELL, CELL)), false)
			for cell in prev.hit:
				_draw_cell_highlight(cell, Color(1, 0.3, 0.2, 0.2), Color(1, 0.3, 0.2, 0.9))
			for cell in prev.heal:
				_draw_cell_highlight(cell, Color(0.3, 1, 0.4, 0.2), Color(0.3, 1, 0.4, 0.9))
			if prev.keep != -1:
				var kcol := -1 if prev.keep == Sim.SIDE_PLAYER else Sim.COLS
				_draw_cell_highlight(Vector2i(hu.lane, kcol), Color(1, 0.3, 0.2, 0.2), Color(1, 0.3, 0.2, 0.9))


## One step of a march: an arrow half a tile back from the stepped-into cell,
## so it straddles the edge the unit crosses and points the way it goes. The
## sprite faces right; a negative width mirrors it for the enemy side (that
## flips the texture in place — `position` stays the left edge either way).
func _draw_move_arrow(cell: Vector2i, dir: int) -> void:
	var centre := cell_pos(cell.x, cell.y) - Vector2(dir * CELL / 2.0, 0)
	var rect := Rect2(centre - Vector2(CELL, CELL) / 2.0, Vector2(CELL, CELL))
	if dir < 0:
		rect.size.x = -CELL
	_overlay.draw_texture_rect(MOVE_ARROW_TEXTURE, rect, false)


func _draw_cell_highlight(cell: Vector2i, fill: Color, outline: Color) -> void:
	var top_left := GRID_POS + Vector2(cell.y * CELL, cell.x * CELL)
	_overlay.draw_rect(Rect2(top_left, Vector2(CELL, CELL)), fill, true)
	_overlay.draw_rect(Rect2(top_left, Vector2(CELL, CELL)), outline, false, 3.0)
