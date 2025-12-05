extends Node
## ThingTypes - Registry of all Thing type definitions
##
## Things are the core resource players manage. Each type has a distinct
## color and shape for easy visual identification.

# =============================================================================
# THING TYPE DATA
# =============================================================================
class ThingType:
	var id: String
	var display_name: String
	var color: Color
	var shape: String  # "triangle", "star", "circle", "square", "hexagon"
	var unlock_round: int  # Round when this type becomes available
	var base_score: int  # Points for returning to correct box
	
	func _init(
		p_id: String,
		p_name: String,
		p_color: Color,
		p_shape: String,
		p_unlock: int = 1,
		p_score: int = 10
	) -> void:
		id = p_id
		display_name = p_name
		color = p_color
		shape = p_shape
		unlock_round = p_unlock
		base_score = p_score


# =============================================================================
# REGISTRY
# =============================================================================
var _types: Dictionary = {}
var _unlock_order: Array[String] = []


func _ready() -> void:
	_register_default_types()


func _register_default_types() -> void:
	# Core palette from GDD:
	# Cyan triangle, magenta star, lime circle, gold square, coral hexagon
	
	_register(ThingType.new(
		"cyan_triangle",
		"Cyan Triangle",
		Color("#00FFFF"),
		"triangle",
		1,  # Available from round 1
		10
	))
	
	_register(ThingType.new(
		"magenta_star",
		"Magenta Star",
		Color("#FF00FF"),
		"star",
		2,  # Unlocks round 2
		10
	))
	
	_register(ThingType.new(
		"lime_circle",
		"Lime Circle",
		Color("#32CD32"),
		"circle",
		4,  # Unlocks round 4
		10
	))
	
	_register(ThingType.new(
		"gold_square",
		"Gold Square",
		Color("#FFD700"),
		"square",
		6,  # Unlocks round 6
		10
	))
	
	_register(ThingType.new(
		"coral_hexagon",
		"Coral Hexagon",
		Color("#FF7F50"),
		"hexagon",
		8,  # Unlocks round 8
		10
	))


func _register(thing_type: ThingType) -> void:
	_types[thing_type.id] = thing_type
	_unlock_order.append(thing_type.id)


# =============================================================================
# PUBLIC API
# =============================================================================
func get_type(type_id: String) -> ThingType:
	return _types.get(type_id, null)


func get_all_types() -> Array:
	return _types.values()


func get_unlocked_types(current_round: int) -> Array:
	var unlocked: Array = []
	for type_id in _unlock_order:
		var thing_type = _types[type_id]
		if thing_type.unlock_round <= current_round:
			unlocked.append(thing_type)
	return unlocked


func get_types_for_round(current_round: int, max_types: int = -1) -> Array:
	var available = get_unlocked_types(current_round)
	if max_types > 0 and available.size() > max_types:
		available = available.slice(0, max_types)
	return available


func get_random_unlocked_type(current_round: int) -> ThingType:
	var available = get_unlocked_types(current_round)
	if available.is_empty():
		return null
	return available[randi() % available.size()]


func get_type_by_shape(shape: String) -> ThingType:
	for thing_type in _types.values():
		if thing_type.shape == shape:
			return thing_type
	return null


func get_type_by_color(color: Color) -> ThingType:
	for thing_type in _types.values():
		if thing_type.color.is_equal_approx(color):
			return thing_type
	return null


# =============================================================================
# SHAPE DRAWING HELPERS
# =============================================================================
## Returns vertex positions for drawing the shape (normalized -1 to 1)
func get_shape_vertices(shape: String) -> PackedVector2Array:
	match shape:
		"triangle":
			return PackedVector2Array([
				Vector2(0, -1),
				Vector2(-0.866, 0.5),
				Vector2(0.866, 0.5)
			])
		"star":
			var points: PackedVector2Array = []
			for i in range(10):
				var angle = (i * TAU / 10) - PI/2
				var radius = 1.0 if i % 2 == 0 else 0.4
				points.append(Vector2(cos(angle), sin(angle)) * radius)
			return points
		"circle":
			var points: PackedVector2Array = []
			for i in range(32):
				var angle = i * TAU / 32
				points.append(Vector2(cos(angle), sin(angle)))
			return points
		"square":
			return PackedVector2Array([
				Vector2(-0.7, -0.7),
				Vector2(0.7, -0.7),
				Vector2(0.7, 0.7),
				Vector2(-0.7, 0.7)
			])
		"hexagon":
			var points: PackedVector2Array = []
			for i in range(6):
				var angle = (i * TAU / 6) - PI/2
				points.append(Vector2(cos(angle), sin(angle)))
			return points
		_:
			# Default to square
			return PackedVector2Array([
				Vector2(-0.7, -0.7),
				Vector2(0.7, -0.7),
				Vector2(0.7, 0.7),
				Vector2(-0.7, 0.7)
			])