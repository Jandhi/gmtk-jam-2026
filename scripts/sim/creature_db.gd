class_name CreatureDB
extends RefCounted
## Loads creature definitions from the CSV spreadsheet.
## Columns: name,health,armour,power,delay,action,range,initiative,abilities
## abilities is |-separated (e.g. "fast|ignores_armour").


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
		db[c.name] = c
	return db
