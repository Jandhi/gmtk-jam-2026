extends SceneTree
## Scratch harness: plays whole battles with a scripted player so balance can be
## read off numbers instead of thumbs. Mirrors battle.gd's card layer (deck,
## 1 draw/turn, hand limit, shop every 20 ticks, gold) closely enough that the
## outcomes mean something. Not part of CI.
##
##   godot --headless --path . --script res://scripts/tests/playtest_sim.gd
##
## Three player skill levels, so the numbers say something about the *design*
## rather than about one bot:
##   passive — never plays a card. The "AFK floor": should always lose.
##   bodies  — deploys unit cards, never gives an order. Isolates whether raw
##             material is enough, i.e. whether orders are load-bearing.
##   tempo   — deploys AND spends orders on the countdown. The intended game.
## bodies vs tempo is the headline: if they win at the same rate, the whole
## order mechanic is decoration.

const RUNS := 60
const MAX_TICKS := 250

# Mirrors of battle.gd. Kept in sync by hand; if that file's economy changes,
# these need the same edit or the report quietly measures the wrong game.
const STARTING_DECK := {
	Order.ADVANCE: 5, Order.RETREAT: 3, Order.MOVE_UP: 3,
	Order.MOVE_DOWN: 3, Order.DELAY: 3, Order.HASTEN: 3,
}
const HAND_LIMIT := 7
const OPENING_HAND := 3
const SHOP_INTERVAL := 20
const SHOP_STOCK := 3
const GOLD_PER_TICK := 1
const GOLD_PER_KILL := 3
const SHOP_PRICES := {
	Order.ADVANCE: 12, Order.RETREAT: 10, Order.MOVE_UP: 10,
	Order.MOVE_DOWN: 10, Order.DELAY: 15, Order.HASTEN: 20,
}

var db: Dictionary


func _init() -> void:
	db = CreatureDB.load_all()
	print("=== %d runs per skill level, cap %d ticks ===\n" % [RUNS, MAX_TICKS])
	var results := {}
	for skill in ["passive", "bodies", "tempo"]:
		results[skill] = _run_batch(skill)
	_report(results)
	_unit_census()
	diagnose()
	quit(0)


func _run_batch(skill: String) -> Dictionary:
	var wins := 0
	var losses := 0
	var stalls := 0
	var lengths: Array[int] = []
	var margins: Array[int] = []   # player keep lives left on a win
	var deficits: Array[int] = []  # enemy keep lives left on a loss
	for seed_value in RUNS:
		var r := _play_one(seed_value + 1, skill)
		lengths.append(r.ticks)
		if r.winner == Sim.SIDE_PLAYER:
			wins += 1
			margins.append(r.player_lives)
		elif r.winner == Sim.SIDE_ENEMY:
			losses += 1
			deficits.append(r.enemy_lives)
		else:
			stalls += 1
	return {
		"wins": wins, "losses": losses, "stalls": stalls,
		"lengths": lengths, "margins": margins, "deficits": deficits,
	}


## One full battle. Returns the outcome plus how close it was.
func _play_one(seed_value: int, skill: String) -> Dictionary:
	var sim := Sim.new(seed_value)
	sim.enemy_pool = CreatureDB.pool(db, &"enemy")
	sim.summon_units[Sim.SIDE_ENEMY] = db["Skeleton"]
	sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 1, 5, true)
	sim.spawn(db["Wight"], Sim.SIDE_ENEMY, 1, 6, true)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919  # independent of the sim's own stream
	var deck: Array[StringName] = []
	var discard: Array[StringName] = []
	var hand: Array[StringName] = []
	var deployed := {}  # unit id -> card type, returned to discard on death
	var gold := 0

	for type in STARTING_DECK:
		for i in STARTING_DECK[type]:
			deck.append(type)
	for c in CreatureDB.pool(db, &"player"):
		for i in c.starter_count:
			deck.append(Order.unit_card(c.name))
	_shuffle(deck, rng)
	# Opening hand is orders only, same as the real game.
	var held_units: Array[StringName] = []
	while hand.size() < OPENING_HAND and not deck.is_empty():
		var card: StringName = deck.pop_back()
		if Order.is_unit_card(card):
			held_units.append(card)
		else:
			hand.append(card)
	deck.append_array(held_units)
	_shuffle(deck, rng)

	while sim.winner == -1 and sim.tick_count < MAX_TICKS:
		if skill != "passive":
			_take_turn(sim, hand, discard, deployed, skill, rng)
		var events := sim.tick()
		gold += GOLD_PER_TICK
		for e in events:
			if e.type == &"unit_died":
				var u := sim.get_unit(e.data.unit)
				if u != null and u.side == Sim.SIDE_ENEMY:
					gold += GOLD_PER_KILL
				if deployed.has(e.data.unit):
					discard.append(deployed[e.data.unit])
					deployed.erase(e.data.unit)
		# Draw one, reshuffling the discard when the deck runs dry.
		if deck.is_empty() and not discard.is_empty():
			deck = discard.duplicate()
			discard.clear()
			_shuffle(deck, rng)
		if not deck.is_empty() and hand.size() < HAND_LIMIT:
			hand.append(deck.pop_back())
		if skill != "passive" and sim.tick_count % SHOP_INTERVAL == 0:
			gold = _shop(hand, discard, gold, rng)

	return {
		"winner": sim.winner, "ticks": sim.tick_count,
		"player_lives": sim.keep_lives[Sim.SIDE_PLAYER],
		"enemy_lives": sim.keep_lives[Sim.SIDE_ENEMY],
	}


## Spend the hand. Orders are free actions, so a turn plays every card it can
## usefully play — exactly the loop a real player runs.
func _take_turn(sim: Sim, hand: Array, discard: Array, deployed: Dictionary,
		skill: String, rng: RandomNumberGenerator) -> void:
	var played := true
	while played:
		played = false
		for i in hand.size():
			var card: StringName = hand[i]
			if _play_card(sim, card, deployed, skill, rng):
				hand.remove_at(i)
				if not Order.is_unit_card(card):
					discard.append(card)
				played = true
				break


func _play_card(sim: Sim, card: StringName, deployed: Dictionary,
		skill: String, rng: RandomNumberGenerator) -> bool:
	if Order.is_unit_card(card):
		var creature: CreatureData = db.get(Order.card_creature(card))
		if creature == null:
			return false
		# Deploy into the emptiest lane, at the very back, so reinforcements
		# march up rather than teleporting into the fight.
		var cells := sim.deploy_cells(Sim.SIDE_PLAYER)
		if cells.is_empty():
			return false
		var best: Vector2i = cells[0]
		var best_key := Vector2i(999, 999)
		for c in cells:
			var count := 0
			for u in sim.alive_units():
				if u.side == Sim.SIDE_PLAYER and u.lane == c.x:
					count += 1
			var key := Vector2i(count, c.y)  # emptiest lane, lowest col
			if key < best_key:
				best_key = key
				best = c
		var events := sim.deploy(creature, Sim.SIDE_PLAYER, best.x, best.y)
		if events.is_empty():
			return false
		deployed[events[0].data.unit] = card
		return true

	if skill != "tempo":
		return false  # "bodies" fields units but never touches the clock

	match card:
		Order.HASTEN:
			# Land your blow first: hurry a unit that is already winding up with
			# an enemy in reach. Firing sooner can kill before they swing back.
			var t := _pick(sim, Sim.SIDE_PLAYER, func(u): return u.windup > 1 and _has_target(sim, u))
			if t != null:
				return _ok(sim.apply_order(Order.make(t.id, Order.HASTEN)))
		Order.DELAY:
			# Push back the enemy that is closest to firing at us.
			var t := _pick(sim, Sim.SIDE_ENEMY, func(u): return u.windup == 1 and _has_target(sim, u))
			if t == null:
				t = _pick(sim, Sim.SIDE_ENEMY, func(u): return u.windup > 0 and _has_target(sim, u))
			if t != null:
				return _ok(sim.apply_order(Order.make(t.id, Order.DELAY)))
		Order.ADVANCE:
			# Push someone with nothing to hit toward the enemy keep.
			var t := _pick(sim, Sim.SIDE_PLAYER, func(u): return u.windup <= 0 and not _has_target(sim, u))
			if t != null:
				return _ok(sim.apply_order(Order.make(t.id, Order.ADVANCE)))
		Order.RETREAT:
			# Pull a badly hurt unit out of reach so it lives to swing again.
			var t := _pick(sim, Sim.SIDE_PLAYER, func(u):
				return u.hp <= u.creature.health / 3 and _has_target(sim, u))
			if t != null:
				return _ok(sim.apply_order(Order.make(t.id, Order.RETREAT)))
		Order.MOVE_UP, Order.MOVE_DOWN:
			# Shift someone idle into a lane where the enemy is unopposed.
			var t := _pick(sim, Sim.SIDE_PLAYER, func(u): return not _has_target(sim, u))
			if t != null:
				return _ok(sim.apply_order(Order.make(t.id, card)))
	return false


func _ok(events: Array) -> bool:
	for e in events:
		if e.type == &"order_applied":
			return true
	return false


## Is anything of the other side within this unit's reach right now?
func _has_target(sim: Sim, u: SimUnit) -> bool:
	var reach := 1 if u.creature.attack_range == 0 else u.creature.attack_range
	for v in sim.alive_units():
		if v.side != u.side and v.lane == u.lane and absi(v.col - u.col) <= reach:
			return true
	return false


func _pick(sim: Sim, side: int, predicate: Callable) -> SimUnit:
	for u in sim.alive_units():
		if u.side == side and predicate.call(u):
			return u
	return null


## Buy the priciest thing affordable, twice — a player who saves for the good
## card rather than dribbling gold away on the cheapest one.
func _shop(hand: Array, discard: Array, gold: int, rng: RandomNumberGenerator) -> int:
	var stock: Array[StringName] = []
	var pool: Array[StringName] = []
	pool.append_array(Order.ALL)
	for c in CreatureDB.pool(db, &"player"):
		pool.append(Order.unit_card(c.name))
	_shuffle(pool, rng)
	for i in mini(SHOP_STOCK, pool.size()):
		stock.append(pool[i])
	for _n in 2:
		var best: StringName = &""
		var best_price := -1
		for s in stock:
			var price := _price(s)
			if price <= gold and price > best_price:
				best = s
				best_price = price
		if best == &"":
			break
		gold -= best_price
		discard.append(best)
		stock.erase(best)
	return gold


func _price(type: StringName) -> int:
	if Order.is_unit_card(type):
		var c: CreatureData = db.get(Order.card_creature(type))
		return c.cost if c != null else 999
	return SHOP_PRICES.get(type, 999)


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _report(results: Dictionary) -> void:
	print("%-9s %6s %7s %7s %9s %10s" % ["skill", "win%", "loss%", "stall%", "med ticks", "avg margin"])
	for skill in ["passive", "bodies", "tempo"]:
		var r: Dictionary = results[skill]
		print("%-9s %5d%% %6d%% %6d%% %9d %10s" % [
			skill,
			roundi(100.0 * r.wins / RUNS),
			roundi(100.0 * r.losses / RUNS),
			roundi(100.0 * r.stalls / RUNS),
			_median(r.lengths),
			_avg_str(r.margins, "keep lives left on a win"),
		])
	print("\n  margin = player keep lives remaining when they win (%d = untouched)"
		% Sim.KEEP_LIVES)


func _median(arr: Array) -> int:
	if arr.is_empty():
		return 0
	var s := arr.duplicate()
	s.sort()
	return s[s.size() / 2]


func _avg_str(arr: Array, _label: String) -> String:
	if arr.is_empty():
		return "-"
	var total := 0
	for v in arr:
		total += v
	return "%.1f" % (float(total) / arr.size())


## Which horrors actually show up, and how often. A unit that never appears is
## art nobody sees; one that appears every wave is the whole enemy identity.
func _unit_census() -> void:
	print("\n=== enemy units fielded across 40 tempo runs ===")
	var counts := {}
	var total := 0
	for seed_value in 40:
		var sim := Sim.new(seed_value + 1)
		sim.enemy_pool = CreatureDB.pool(db, &"enemy")
		sim.summon_units[Sim.SIDE_ENEMY] = db["Skeleton"]
		sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 1, 5, true)
		sim.spawn(db["Wight"], Sim.SIDE_ENEMY, 1, 6, true)
		for t in 90:
			for e in sim.tick():
				if e.type == &"unit_deployed":
					var n := sim.get_unit(e.data.unit).creature.name
					counts[n] = counts.get(n, 0) + 1
					total += 1
			if sim.winner != -1:
				break
	var names := counts.keys()
	names.sort_custom(func(a, b): return counts[a] > counts[b])
	for n in names:
		print("  %-16s %4d  (%d%%)" % [n, counts[n], roundi(100.0 * counts[n] / total)])
	for c in CreatureDB.pool(db, &"enemy"):
		if not counts.has(c.name):
			print("  %-16s    0  NEVER APPEARS (tier %d)" % [c.name, c.tier])


## Why the numbers look the way they do: board presence over time, and where
## the player's keep damage actually comes from.
func diagnose() -> void:
	print("\n=== board presence, tempo player, averaged over 30 runs ===")
	print("  tick   player units   enemy units   deployed(cum)   dead-card wait")
	var buckets := {}
	for seed_value in 30:
		var sim := Sim.new(seed_value + 1)
		sim.enemy_pool = CreatureDB.pool(db, &"enemy")
		sim.summon_units[Sim.SIDE_ENEMY] = db["Skeleton"]
		sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 1, 5, true)
		sim.spawn(db["Wight"], Sim.SIDE_ENEMY, 1, 6, true)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 7919
		var deck: Array[StringName] = []
		var discard: Array[StringName] = []
		var hand: Array[StringName] = []
		var deployed := {}
		var total_deployed := 0
		for type in STARTING_DECK:
			for i in STARTING_DECK[type]:
				deck.append(type)
		for c in CreatureDB.pool(db, &"player"):
			for i in c.starter_count:
				deck.append(Order.unit_card(c.name))
		_shuffle(deck, rng)
		while sim.winner == -1 and sim.tick_count < 120:
			var before: int = deployed.size()
			_take_turn(sim, hand, discard, deployed, "tempo", rng)
			total_deployed += maxi(deployed.size() - before, 0)
			for e in sim.tick():
				if e.type == &"unit_died" and deployed.has(e.data.unit):
					discard.append(deployed[e.data.unit])
					deployed.erase(e.data.unit)
			if deck.is_empty() and not discard.is_empty():
				deck = discard.duplicate()
				discard.clear()
				_shuffle(deck, rng)
			if not deck.is_empty() and hand.size() < HAND_LIMIT:
				hand.append(deck.pop_back())
			var t: int = sim.tick_count
			if t % 10 == 0:
				var p := 0
				var en := 0
				for u in sim.alive_units():
					if u.side == Sim.SIDE_PLAYER:
						p += 1
					else:
						en += 1
				if not buckets.has(t):
					buckets[t] = [0, 0, 0, 0]
				buckets[t][0] += p
				buckets[t][1] += en
				buckets[t][2] += total_deployed
				buckets[t][3] += 1
	var ticks := buckets.keys()
	ticks.sort()
	for t in ticks:
		var b: Array = buckets[t]
		var n: float = float(b[3])
		print("  %4d %12.1f %13.1f %15.1f     (%d runs alive)" % [
			t, b[0] / n, b[1] / n, b[2] / n, b[3]])
	print("\n  deck size is %d cards with %d unit cards, so a dead unit's card" % [
		_deck_size(), _unit_card_count()])
	print("  takes roughly a full reshuffle to come back around.")


func _deck_size() -> int:
	var n := 0
	for type in STARTING_DECK:
		n += STARTING_DECK[type]
	return n + _unit_card_count()


func _unit_card_count() -> int:
	var n := 0
	for c in CreatureDB.pool(db, &"player"):
		n += c.starter_count
	return n
