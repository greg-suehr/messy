extends Node
## GuyTypes - Registry of all Guy type definitions
##
## Guys are the chaos agents that scatter Things around the board.
## Different types have different behaviors and visual appearances.

# =============================================================================
# GUY TYPE DATA
# =============================================================================
class GuyType:
	var id: String
	var display_name: String
	var color: Color
	var move_speed: float  # Pixels per second
	var longing_duration: float  # Seconds before tantrum
	var tantrum_particles: int  # Chaos particles spawned on tantrum
	var behavior: String  # "normal", "scavenger", "thief"
	var unlock_round: int
	
	# Behavior modifiers
	var prefers_empty_boxes: bool  # Scavenger behavior
	var steals_from_player: bool  # Thief behavior
	var drops_multiple: bool  # Scatters multiple things
	
	func _init(
		p_id: String,
		p_name: String,
		p_color: Color,
		p_speed: float = 100.0,
		p_longing: float = 8.0,
		p_particles: int = 5,
		p_behavior: String = "normal",
		p_unlock: int = 1
	) -> void:
		id = p_id
		display_name = p_name
		color = p_color
		move_speed = p_speed
		longing_duration = p_longing
		tantrum_particles = p_particles
		behavior = p_behavior
		unlock_round = p_unlock
		
		# Set behavior flags based on type
		prefers_empty_boxes = (behavior == "scavenger")
		steals_from_player = (behavior == "thief")
		drops_multiple = (behavior == "scavenger")


# =============================================================================
# REGISTRY
# =============================================================================
var _types: Dictionary = {}
var _unlock_order: Array[String] = []


func _ready() -> void:
	_register_default_types()


func _register_default_types() -> void:
	# From GDD: Light purple (base), electric lime (scavenger), dark violet (thief)
	
	_register(GuyType.new(
		"normal",
		"Guy",
		Color("#C8A2C8"),  # Light purple
		100.0,  # Speed
		8.0,    # Longing duration (8 seconds per GDD)
		5,      # Tantrum particles (4-6 per GDD)
		"normal",
		1       # Available from start
	))
	
	_register(GuyType.new(
		"scavenger",
		"Scavenger",
		Color("#7FFF00"),  # Electric lime
		130.0,  # Faster
		6.0,    # Shorter patience
		7,      # More chaos
		"scavenger",
		7       # Unlocks later
	))
	
	_register(GuyType.new(
		"thief",
		"Thief",
		Color("#9400D3"),  # Dark violet
		150.0,  # Fastest
		10.0,   # More patient (sneaky)
		4,      # Fewer particles (stealthy)
		"thief",
		10      # Late game
	))


func _register(guy_type: GuyType) -> void:
	_types[guy_type.id] = guy_type
	_unlock_order.append(guy_type.id)


# =============================================================================
# PUBLIC API
# =============================================================================
func get_type(type_id: String) -> GuyType:
	return _types.get(type_id, null)


func get_all_types() -> Array:
	return _types.values()


func get_unlocked_types(current_round: int) -> Array:
	var unlocked: Array = []
	for type_id in _unlock_order:
		var guy_type = _types[type_id]
		if guy_type.unlock_round <= current_round:
			unlocked.append(guy_type)
	return unlocked


func get_types_for_round(current_round: int, max_types: int = -1) -> Array:
	var available = get_unlocked_types(current_round)
	if max_types > 0 and available.size() > max_types:
		available = available.slice(0, max_types)
	return available


func get_random_unlocked_type(current_round: int) -> GuyType:
	var available = get_unlocked_types(current_round)
	if available.is_empty():
		return null
	
	# Weight toward normal guys, with occasional special types
	var weights: Array[float] = []
	for guy_type in available:
		match guy_type.behavior:
			"normal":
				weights.append(3.0)
			"scavenger":
				weights.append(1.5)
			"thief":
				weights.append(1.0)
			_:
				weights.append(1.0)
	
	return _weighted_random(available, weights)


func _weighted_random(items: Array, weights: Array[float]) -> GuyType:
	var total_weight = 0.0
	for w in weights:
		total_weight += w
	
	var roll = randf() * total_weight
	var cumulative = 0.0
	
	for i in range(items.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			return items[i]
	
	return items[-1] if items.size() > 0 else null


# =============================================================================
# BEHAVIOR HELPERS
# =============================================================================
func should_target_empty_box(guy_type: GuyType) -> bool:
	return guy_type.prefers_empty_boxes


func can_steal_from_player(guy_type: GuyType) -> bool:
	return guy_type.steals_from_player


func get_drop_count(guy_type: GuyType) -> int:
	if guy_type.drops_multiple:
		return randi_range(2, 3)
	return 1