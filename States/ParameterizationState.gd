extends Node
## ParameterizationState - Manages the upgrade tree and star economy
##
## Players spend earned stars between rounds to purchase upgrades that
## increase difficulty and scoring potential. This state tracks available
## upgrades, purchased upgrades, and preview calculations.

# =============================================================================
# UPGRADE DEFINITIONS
# =============================================================================
class Upgrade:
	var id: String
	var display_name: String
	var description: String
	var category: String  # "boxes", "board", "guys", "things"
	var cost: int
	var prerequisites: Array[String]
	var unlock_round: int
	var effect: Dictionary  # What this upgrade does
	var purchased: bool = false
	
	func _init(
		p_id: String,
		p_name: String,
		p_desc: String,
		p_category: String,
		p_cost: int,
		p_prereqs: Array[String] = [],
		p_unlock: int = 1,
		p_effect: Dictionary = {}
	) -> void:
		id = p_id
		display_name = p_name
		description = p_desc
		category = p_category
		cost = p_cost
		prerequisites = p_prereqs
		unlock_round = p_unlock
		effect = p_effect


# =============================================================================
# STATE
# =============================================================================
var _upgrades: Dictionary = {}  # id -> Upgrade
var _purchased_ids: Array[String] = []

# Preview state
var _preview_upgrade_id: String = ""


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_register_default_upgrades()
	_connect_signals()


func _connect_signals() -> void:
	SignalBus.upgrade_preview_requested.connect(_on_preview_requested)


func _register_default_upgrades() -> void:
	"""Register the default upgrade tree."""
	
	# === BOX UPGRADES ===
	_register(Upgrade.new(
		"box_2",
		"+1 Box",
		"Add a second box type to the board.",
		"boxes",
		1,
		[],
		1,
		{"param_box_count": 2}
	))
	
	_register(Upgrade.new(
		"box_3",
		"+1 Box",
		"Add a third box type to the board.",
		"boxes",
		1,
		["box_2"],
		3,
		{"param_box_count": 3}
	))
	
	_register(Upgrade.new(
		"box_4",
		"+1 Box",
		"Add a fourth box type to the board.",
		"boxes",
		2,
		["box_3"],
		5,
		{"param_box_count": 4}
	))
	
	_register(Upgrade.new(
		"box_5",
		"+1 Box",
		"Add a fifth box type to the board. Maximum chaos!",
		"boxes",
		2,
		["box_4"],
		8,
		{"param_box_count": 5}
	))
	
	# === BOARD EXPANSION UPGRADES ===
	_register(Upgrade.new(
		"expand_small",
		"Expand Board (Small)",
		"Increase board size slightly. More room to run!",
		"board",
		1,
		[],
		2,
		{"board_expand": 2}
	))
	
	_register(Upgrade.new(
		"expand_medium",
		"Expand Board (Medium)",
		"Increase board size moderately.",
		"board",
		2,
		["expand_small"],
		4,
		{"board_expand": 2}
	))
	
	_register(Upgrade.new(
		"expand_large",
		"Expand Board (Large)",
		"Significantly increase board size.",
		"board",
		2,
		["expand_medium"],
		7,
		{"board_expand": 2}
	))
	
	# === THING TYPE UPGRADES ===
	_register(Upgrade.new(
		"thing_type_2",
		"Unlock Magenta Stars",
		"Add magenta star things to the mix.",
		"things",
		1,
		[],
		2,
		{"param_thing_types": 2, "unlock_thing": "magenta_star"}
	))
	
	_register(Upgrade.new(
		"thing_type_3",
		"Unlock Lime Circles",
		"Add lime circle things. Getting colorful!",
		"things",
		1,
		["thing_type_2"],
		4,
		{"param_thing_types": 3, "unlock_thing": "lime_circle"}
	))
	
	_register(Upgrade.new(
		"thing_type_4",
		"Unlock Gold Squares",
		"Add gold square things. Shiny!",
		"things",
		2,
		["thing_type_3"],
		6,
		{"param_thing_types": 4, "unlock_thing": "gold_square"}
	))
	
	_register(Upgrade.new(
		"thing_type_5",
		"Unlock Coral Hexagons",
		"Add coral hexagon things. Full rainbow chaos!",
		"things",
		2,
		["thing_type_4"],
		8,
		{"param_thing_types": 5, "unlock_thing": "coral_hexagon"}
	))
	
	# === GUY TYPE UPGRADES ===
	_register(Upgrade.new(
		"guy_scavenger",
		"Scavenger Guys",
		"Unlock faster guys that target low boxes.",
		"guys",
		2,
		[],
		7,
		{"param_guy_types": 2, "unlock_guy": "scavenger"}
	))
	
	_register(Upgrade.new(
		"guy_thief",
		"Thief Guys",
		"Unlock sneaky guys. Watch your stack!",
		"guys",
		2,
		["guy_scavenger"],
		10,
		{"param_guy_types": 3, "unlock_guy": "thief"}
	))
	
	# === SPAWN RATE MODIFIERS ===
	_register(Upgrade.new(
		"spawn_faster",
		"Faster Spawns",
		"Guys spawn more frequently. More chaos, more points!",
		"guys",
		1,
		[],
		3,
		{"guy_spawn_rate_mult": 0.85}
	))
	
	_register(Upgrade.new(
		"spawn_fastest",
		"Maximum Chaos",
		"Even faster guy spawns. Good luck!",
		"guys",
		2,
		["spawn_faster"],
		6,
		{"guy_spawn_rate_mult": 0.75}
	))


func _register(upgrade: Upgrade) -> void:
	_upgrades[upgrade.id] = upgrade


# =============================================================================
# UPGRADE QUERIES
# =============================================================================
func get_upgrade(id: String) -> Upgrade:
	return _upgrades.get(id, null)


func get_all_upgrades() -> Array:
	return _upgrades.values()


func get_upgrades_by_category(category: String) -> Array:
	var result: Array = []
	for upgrade in _upgrades.values():
		if upgrade.category == category:
			result.append(upgrade)
	return result


func get_available_upgrades(current_round: int, current_stars: int) -> Array:
	"""Get upgrades that can be purchased right now."""
	var available: Array = []
	
	for upgrade in _upgrades.values():
		if is_upgrade_available(upgrade.id, current_round, current_stars):
			available.append(upgrade)
	
	return available


func is_upgrade_available(id: String, current_round: int, current_stars: int) -> bool:
	"""Check if an upgrade can be purchased."""
	var upgrade = _upgrades.get(id, null)
	if upgrade == null:
		return false
	
	# Already purchased
	if upgrade.purchased:
		return false
	
	# Round requirement
	if upgrade.unlock_round > current_round:
		return false
	
	# Cost check
	if upgrade.cost > current_stars:
		return false
	
	# Prerequisites
	for prereq_id in upgrade.prerequisites:
		var prereq = _upgrades.get(prereq_id, null)
		if prereq == null or not prereq.purchased:
			return false
	
	return true


func is_upgrade_purchased(id: String) -> bool:
	return id in _purchased_ids


# =============================================================================
# PURCHASING
# =============================================================================
func purchase_upgrade(id: String) -> bool:
	"""Attempt to purchase an upgrade. Returns true if successful."""
	var upgrade = _upgrades.get(id, null)
	if upgrade == null:
		return false
	
	if not is_upgrade_available(id, GameState.current_round, GameState.stars_available):
		return false
	
	# Deduct stars
	var remaining = GameState.stars_available - upgrade.cost
	
	SignalBus.publish("stars.spent", {
		"amount": upgrade.cost,
		"remaining": remaining,
		"upgrade_id": id
	})
	
	# Mark as purchased
	upgrade.purchased = true
	_purchased_ids.append(id)
	
	# Apply effects
	_apply_upgrade_effects(upgrade)
	
	SignalBus.publish("upgrade.purchased", {
		"upgrade_id": id,
		"category": upgrade.category
	})
	
	return true


func _apply_upgrade_effects(upgrade: Upgrade) -> void:
	"""Apply the effects of a purchased upgrade to GameState."""
	for key in upgrade.effect.keys():
		var value = upgrade.effect[key]
		
		match key:
			"param_box_count":
				GameState.param_box_count = value
			"param_thing_types":
				GameState.param_thing_types = value
			"param_guy_types":
				GameState.param_guy_types = value
			"board_expand":
				GameState.param_board_size += Vector2i(value, value)
			"guy_spawn_rate_mult":
				GameState.param_guy_spawn_rate *= value
			"unlock_thing", "unlock_guy":
				# These are informational - types unlock naturally
				pass


# =============================================================================
# PREVIEW CALCULATIONS
# =============================================================================
func get_upgrade_preview(id: String) -> Dictionary:
	"""Calculate what changes if this upgrade is purchased."""
	var upgrade = _upgrades.get(id, null)
	if upgrade == null:
		return {}
	
	var preview = {
		"id": id,
		"name": upgrade.display_name,
		"description": upgrade.description,
		"cost": upgrade.cost,
		"changes": []
	}
	
	# Calculate impact on game parameters
	for key in upgrade.effect.keys():
		var value = upgrade.effect[key]
		
		match key:
			"param_box_count":
				preview["changes"].append({
					"stat": "Boxes",
					"current": GameState.param_box_count,
					"new": value
				})
			"param_thing_types":
				preview["changes"].append({
					"stat": "Thing Types",
					"current": GameState.param_thing_types,
					"new": value
				})
			"board_expand":
				preview["changes"].append({
					"stat": "Board Size",
					"current": "%dx%d" % [GameState.param_board_size.x, GameState.param_board_size.y],
					"new": "%dx%d" % [GameState.param_board_size.x + value, GameState.param_board_size.y + value]
				})
			"guy_spawn_rate_mult":
				var current_rate = 60.0 / GameState.param_guy_spawn_rate
				var new_rate = 60.0 / (GameState.param_guy_spawn_rate * value)
				preview["changes"].append({
					"stat": "Spawn Rate",
					"current": "%.1f/min" % current_rate,
					"new": "%.1f/min" % new_rate
				})
	
	# Estimate score potential change
	preview["score_potential_change"] = _estimate_score_potential_change(upgrade)
	
	return preview


func _estimate_score_potential_change(upgrade: Upgrade) -> int:
	"""Rough estimate of how this upgrade affects scoring potential."""
	var change = 0
	
	for key in upgrade.effect.keys():
		match key:
			"param_box_count":
				# More boxes = more things = more points
				change += 50
			"board_expand":
				# Bigger board = base score increase
				change += 30
			"param_thing_types":
				# More variety = more complexity = moderate increase
				change += 20
			"guy_spawn_rate_mult":
				# Faster spawns = more chaos = risk/reward
				change += 40
	
	return change


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_preview_requested(upgrade_id: String) -> void:
	_preview_upgrade_id = upgrade_id
	# UI will call get_upgrade_preview() to get the data


# =============================================================================
# STATE MANAGEMENT
# =============================================================================
func reset() -> void:
	"""Reset all upgrades to unpurchased state."""
	_purchased_ids.clear()
	for upgrade in _upgrades.values():
		upgrade.purchased = false


func get_save_data() -> Dictionary:
	return {
		"purchased_upgrades": _purchased_ids.duplicate()
	}


func load_save_data(data: Dictionary) -> void:
	_purchased_ids.clear()
	
	var purchased = data.get("purchased_upgrades", [])
	for id in purchased:
		var upgrade = _upgrades.get(id, null)
		if upgrade:
			upgrade.purchased = true
			_purchased_ids.append(id)
			_apply_upgrade_effects(upgrade)
