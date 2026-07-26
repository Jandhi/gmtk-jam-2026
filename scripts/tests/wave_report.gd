extends SceneTree
## Scratch harness: prints the wave schedule and what an unattended board does,
## so the ramp can be eyeballed without playing 80 turns by hand. Not part of
## CI. Run with:
##   godot --headless --path . --script res://scripts/tests/wave_report.gd


func _init() -> void:
	var db := CreatureDB.load_all()
	print("=== wave schedule (seed 1) ===")
	var sim := Sim.new(1)
	sim.enemy_pool = CreatureDB.pool(db, &"enemy")
	sim.summon_units[Sim.SIDE_ENEMY] = db["Skeleton"]
	for t in 90:
		var events := sim.tick()
		var arrived := []
		for e in events:
			if e.type == &"unit_deployed":
				arrived.append(sim.get_unit(e.data.unit).creature.name)
		if arrived.is_empty():
			continue
		var live := 0
		for u in sim.alive_units():
			if u.side == Sim.SIDE_ENEMY:
				live += 1
		print("  t%-3d budget %.1f  every %d  ->  %s   (board: %d)" % [
			sim.tick_count, sim.wave_budget(), sim.wave_interval(),
			", ".join(arrived), live])

	print("\n=== unattended board: how fast does the keep fall? ===")
	for seed_value in [1, 2, 3, 4, 5]:
		var s := Sim.new(seed_value)
		s.enemy_pool = CreatureDB.pool(db, &"enemy")
		s.summon_units[Sim.SIDE_ENEMY] = db["Skeleton"]
		s.spawn(db["Knight"], Sim.SIDE_PLAYER, 1, 5, true)
		s.spawn(db["Wight"], Sim.SIDE_ENEMY, 1, 6, true)
		var first_life := -1
		for t in 200:
			s.tick()
			if first_life == -1 and s.keep_lives[Sim.SIDE_PLAYER] < Sim.KEEP_LIVES:
				first_life = s.tick_count
			if s.winner != -1:
				break
		print("  seed %d: first keep life lost t%d, battle over t%d (winner %d)" % [
			seed_value, first_life, s.tick_count, s.winner])
	# Gold is +1/tick and +3/kill, and waves are now most of the kill supply —
	# so what a shop visit can actually afford depends on the ramp. Prices were
	# rescaled 3x; this checks the income was too.
	print("\n=== gold at each shop visit (kills come from waves) ===")
	var g := Sim.new(1)
	g.enemy_pool = CreatureDB.pool(db, &"enemy")
	g.summon_units[Sim.SIDE_ENEMY] = db["Skeleton"]
	g.spawn(db["Knight"], Sim.SIDE_PLAYER, 1, 5, true)
	g.spawn(db["Guard"], Sim.SIDE_PLAYER, 0, 1, true)
	g.spawn(db["Scout"], Sim.SIDE_PLAYER, 2, 1, true)
	var gold := 0
	for t in 80:
		for e in g.tick():
			if e.type == &"unit_died" and g.get_unit(e.data.unit).side == Sim.SIDE_ENEMY:
				gold += 3
		gold += 1
		if g.tick_count % 20 == 0:
			print("  shop at t%-3d -> %d gold banked" % [g.tick_count, gold])
	quit(0)
