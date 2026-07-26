class_name CreatureDB
extends RefCounted
## Loads creature definitions from the CSV spreadsheet.
## Columns: name,health,armour,power,delay,action,range,initiative,abilities,
## unit_type,tier,side,cost,starter_count
## abilities is |-separated (e.g. "fast|ignores_armour").
##
## data/creatures.csv is generated from the design sheet by
## data/gen_creatures.py — edit the sheet and re-run that, not the CSV.


static func load_all(path: String = "res://data/creatures.csv") -> Dictionary:
	var db := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CreatureDB: cannot open %s" % path)
		return db
	var header := file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < header.size() or row[0].strip_edges().is_empty():
			continue
		var c := CreatureData.new()
		c.name = row[0].strip_edges()
		c.health = int(row[1])
		c.armour = int(row[2])
		c.power = int(row[3])
		c.delay = int(row[4])
		c.action = StringName(row[5].strip_edges())
		c.attack_range = int(row[6])
		c.initiative = int(row[7])
		for a in row[8].split("|", false):
			c.abilities.append(StringName(a.strip_edges()))
		c.unit_type = row[9].strip_edges()
		c.tier = int(row[10])
		c.side = StringName(row[11].strip_edges())
		c.cost = int(row[12])
		c.starter_count = int(row[13])
		db[c.name] = c
	return db


## Every creature on one side's roster, cheapest first — the pool to draw
## armies and shop stock from. side is &"player" or &"enemy".
static func pool(db: Dictionary, side: StringName, tier := 0) -> Array:
	var out := []
	for c in db.values():
		if c.side == side and (tier == 0 or c.tier == tier):
			out.append(c)
	out.sort_custom(func(a, b): return a.cost < b.cost if a.cost != b.cost else a.name < b.name)
	return out
