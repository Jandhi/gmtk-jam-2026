extends SceneTree
## Headless sim tests. Run with:
##   godot --headless --path . --script res://scripts/tests/sim_test.gd
## Exits non-zero on failure (used by CI).

var failures := 0
var db: Dictionary


func _init() -> void:
	db = CreatureDB.load_all()
	_test_db_loads()
	_test_basic_fight_resolves()
	_test_determinism()
	_test_armour_reduces_damage()
	_test_ignores_armour()
	_test_swap_order()
	_test_delay_and_hasten_orders()
	_test_line_hits_multiple()
	_test_heal()
	_test_no_rest_after_firing()
	_test_hasten_fires_instantly()
	_test_riposte_counters()
	_test_keep_siege()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)


func run_ticks(sim: Sim, n: int) -> Array:
	var all_events: Array = []
	for i in n:
		all_events.append_array(sim.tick())
		if sim.winner != -1:
			break
	return all_events


func events_of(events: Array, type: StringName) -> Array:
	return events.filter(func(e): return e.type == type)


func _test_db_loads() -> void:
	print("db_loads:")
	check(db.size() >= 12, "at least 12 creatures loaded")
	check(db.has("Goblin") and db["Goblin"].power == 3, "goblin stats parsed")
	check(db["Wolf"].has_ability(&"fast"), "abilities parsed")


func _test_basic_fight_resolves() -> void:
	print("basic_fight_resolves:")
	var sim := Sim.new(42)
	sim.spawn(db["Goblin"], Sim.SIDE_PLAYER, 1, 2)
	sim.spawn(db["Goblin"], Sim.SIDE_ENEMY, 1, 9)
	var events := run_ticks(sim, 50)
	check(sim.winner != -1, "battle ends within 50 ticks")
	check(events_of(events, &"unit_died").size() >= 1, "someone died")
	check(events_of(events, &"unit_moved").size() >= 5, "units marched toward each other")


func _test_determinism() -> void:
	print("determinism:")
	var results: Array = []
	for run in 2:
		var sim := Sim.new(1234)
		sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 0, 1)
		sim.spawn(db["Wolf"], Sim.SIDE_PLAYER, 1, 1)
		sim.spawn(db["Ogre"], Sim.SIDE_ENEMY, 0, 10)
		sim.spawn(db["Goblin"], Sim.SIDE_ENEMY, 1, 10)
		var events := run_ticks(sim, 100)
		results.append([sim.winner, sim.tick_count, events.size()])
	check(results[0][0] == results[1][0], "same winner")
	check(results[0][1] == results[1][1], "same tick count")
	check(results[0][2] == results[1][2], "same event count")


func _test_armour_reduces_damage() -> void:
	print("armour:")
	var sim := Sim.new(7)
	sim.spawn(db["Goblin"], Sim.SIDE_PLAYER, 0, 4)  # power 3
	sim.spawn(db["Knight"], Sim.SIDE_ENEMY, 0, 5)   # armour 3
	var events := run_ticks(sim, 10)
	var goblin_hits := events_of(events, &"damage_dealt").filter(
		func(e): return e.data.attacker == 1)
	check(not goblin_hits.is_empty(), "goblin attacked")
	for e in goblin_hits:
		check(e.data.amount == 0, "goblin power 3 fully blocked by armour 3")
		break


func _test_ignores_armour() -> void:
	print("ignores_armour:")
	var sim := Sim.new(7)
	sim.spawn(db["Assassin"], Sim.SIDE_PLAYER, 0, 4)  # power 7, ignores armour
	sim.spawn(db["Knight"], Sim.SIDE_ENEMY, 0, 5)     # armour 3
	var events := run_ticks(sim, 8)
	var hits := events_of(events, &"damage_dealt").filter(
		func(e): return e.data.attacker == 1)
	check(not hits.is_empty(), "assassin attacked")
	for e in hits:
		check(e.data.amount == 7, "full 7 damage through armour")
		break


func _test_swap_order() -> void:
	print("swap_order:")
	var sim := Sim.new(1)
	var a := sim.spawn(db["Goblin"], Sim.SIDE_PLAYER, 0, 2)
	var b := sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 0, 3)
	sim.apply_order(Order.make(a.id, Order.ADVANCE))
	check(a.col == 3 and b.col == 2, "advancing into ally swaps positions")


func _test_delay_and_hasten_orders() -> void:
	print("delay_hasten:")
	var sim := Sim.new(1)
	var g := sim.spawn(db["Guard"], Sim.SIDE_PLAYER, 0, 5)
	sim.spawn(db["Ogre"], Sim.SIDE_ENEMY, 0, 7)
	sim.tick()  # guard sees ogre within 1+delay and starts winding up
	check(g.windup == db["Guard"].delay, "guard started windup")
	var before := g.windup
	sim.apply_order(Order.make(g.id, Order.DELAY))
	sim.tick()
	check(g.windup == before, "delay +1 then tick -1 nets no progress")
	sim.apply_order(Order.make(g.id, Order.HASTEN))
	sim.tick()
	check(g.windup == before - 2, "hasten -1 plus tick -1")


func _test_line_hits_multiple() -> void:
	print("line:")
	var sim := Sim.new(9)
	sim.spawn(db["Adult Red Dragon"], Sim.SIDE_ENEMY, 1, 8)
	sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 1, 7)
	sim.spawn(db["Goblin"], Sim.SIDE_PLAYER, 1, 6)
	sim.spawn(db["Skeleton"], Sim.SIDE_PLAYER, 1, 5)
	var events := run_ticks(sim, db["Adult Red Dragon"].delay + 1)
	var fired := events_of(events, &"action_fired").filter(
		func(e): return e.data.action == &"line")
	check(not fired.is_empty(), "dragon fired its line")
	var dragon_hits := events_of(events, &"damage_dealt").filter(
		func(e): return e.data.attacker == 1)
	check(dragon_hits.size() >= 3, "line hit 3+ units (hit %d)" % dragon_hits.size())


func _test_heal() -> void:
	print("heal:")
	var sim := Sim.new(3)
	var priest := sim.spawn(db["Priest"], Sim.SIDE_PLAYER, 0, 1)
	var knight := sim.spawn(db["Knight"], Sim.SIDE_PLAYER, 0, 3)
	sim.spawn(db["Ogre"], Sim.SIDE_ENEMY, 2, 11)
	knight.hp = 5
	var events := run_ticks(sim, db["Priest"].delay + 1)
	var heals := events_of(events, &"healed")
	check(not heals.is_empty(), "priest healed")
	if not heals.is_empty():
		check(heals[0].data.target == knight.id, "healed the damaged knight")
		check(knight.hp == 5 + db["Priest"].power, "heal amount = power")
	check(priest.col == 1, "priest held position instead of marching")


func _test_no_rest_after_firing() -> void:
	print("no_rest_after_firing:")
	var sim := Sim.new(5)
	var g := sim.spawn(db["Goblin"], Sim.SIDE_PLAYER, 0, 4)  # delay 2
	sim.spawn(db["Ogre"], Sim.SIDE_ENEMY, 0, 5)
	sim.tick()  # goblin starts windup 2
	sim.tick()  # windup 1
	var events := sim.tick()  # fires, then restarts windup in the same end phase
	check(not events_of(events, &"action_fired").is_empty(), "goblin fired on tick 3")
	check(g.windup == g.creature.delay, "windup restarted same tick (cadence = delay)")


func _test_hasten_fires_instantly() -> void:
	print("hasten_fires_instantly:")
	var sim := Sim.new(5)
	var g := sim.spawn(db["Goblin"], Sim.SIDE_PLAYER, 0, 4)
	var o := sim.spawn(db["Ogre"], Sim.SIDE_ENEMY, 0, 5)
	sim.tick()  # both start winding up
	sim.tick()  # goblin windup 2 -> 1
	check(g.windup == 1, "goblin at windup 1")
	var events := sim.apply_order(Order.make(g.id, Order.HASTEN))
	check(not events_of(events, &"action_fired").is_empty(), "hasten to 0 fired the strike")
	var hits := events_of(events, &"damage_dealt")
	check(not hits.is_empty() and hits[0].data.target == o.id, "instant strike hit the ogre")
	check(g.windup == -1, "goblin idle after instant fire")


func _test_riposte_counters() -> void:
	print("riposte:")
	# Gladiator (delay 3) winds up as the goblin approaches; when the goblin's
	# strike lands on the gladiator's armed tick, it should be negated + countered.
	var sim := Sim.new(11)
	var glad := sim.spawn(db["Gladiator"], Sim.SIDE_PLAYER, 0, 4)
	sim.spawn(db["Goblin"], Sim.SIDE_ENEMY, 0, 8)
	var events := run_ticks(sim, 30)
	var counters := events_of(events, &"riposte_triggered")
	check(not counters.is_empty(), "riposte triggered at least once")
	check(sim.winner == Sim.SIDE_PLAYER, "gladiator beats goblin")
	check(glad.hp > 0, "gladiator survived")


func _test_keep_siege() -> void:
	print("keep_siege:")
	# Goblin at the wall sieges the enemy keep; the priest (other lane, never
	# marches, nothing to heal) keeps the battle from ending by unit wipe.
	var sim := Sim.new(3)
	sim.spawn(db["Goblin"], Sim.SIDE_PLAYER, 0, 11)
	var priest := sim.spawn(db["Priest"], Sim.SIDE_ENEMY, 2, 11)
	var events := run_ticks(sim, 400)
	var hits := events_of(events, &"keep_damaged")
	check(not hits.is_empty(), "keep took damage")
	if not hits.is_empty():
		check(hits[0].data.side == Sim.SIDE_ENEMY, "enemy keep was hit")
		check(hits[0].data.hp == Sim.KEEP_MAX_HP - db["Goblin"].power, "keep hp dropped by power")
	var lives := events_of(events, &"keep_life_lost")
	check(lives.size() == Sim.KEEP_LIVES, "all keep lives lost")
	if not lives.is_empty():
		check(lives[0].data.lives == Sim.KEEP_LIVES - 1 and lives[0].data.hp == Sim.KEEP_MAX_HP, "losing a life refills the bar")
		check(lives.back().data.lives == 0 and lives.back().data.hp == 0, "last life leaves the keep at zero")
	check(sim.winner == Sim.SIDE_PLAYER and priest.is_alive(), "keep fall wins the battle with defenders alive")
