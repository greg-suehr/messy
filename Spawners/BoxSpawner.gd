extends Node
class_name BoxSpawner
## BoxSpawner - Manages spawning boxes on the game board edges
##
## Boxes are distributed along the edges of the game board. The spawner
## ensures even distribution and handles the initial stocking of Things.

# =============================================================================
# CONFIGURATION
# =============================================================================
@export var box_scene: PackedScene
@export var thing_scene: PackedScene
@export var initial_things_per_box: int = 5

# =============================================================================
# STATE
# =============================================================================
var spawned_boxes: Array[Box] = []
var _game_board: GameBoard = null


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	SignalBus.round_setup_started.connect(_on_round_setup)


func set_game_board(board: GameBoard) -> void:
	_game_board = board


# =============================================================================
# SPAWNING
# =============================================================================
func spawn_boxes_for_round(round_number: int) -> void:
	"""Spawn boxes based on round parameters and unlocked thing types."""
	clear_boxes()
	
	var box_count = GameState.param_box_count
	var thing_types = ThingTypes.get_types_for_round(round_number, GameState.param_thing_types)
	
	if thing_types.is_empty():
		push_error("BoxSpawner: No thing types available for round %d" % round_number)
		return
	
	# Distribute boxes across edges
	var edge_positions = _calculate_box_positions(box_count)
	
	for i in range(box_count):
		# Cycle through thing types
		var thing_type = thing_types[i % thing_types.size()]
		var pos = edge_positions[i]
		
		_spawn_box(thing_type.id, pos)
	
	# Stock boxes with initial things
	await get_tree().process_frame  # Wait for boxes to be added to tree
	_stock_all_boxes()


func _spawn_box(thing_type_id: String, position: Vector2) -> Box:
	"""Spawn a single box at the specified position."""
	var box: Box
	
	if box_scene:
		box = box_scene.instantiate() as Box
	else:
		box = Box.new()
	
	box.thing_type_id = thing_type_id
	box.global_position = position
	
	# Add to scene tree
	if _game_board:
		_game_board.add_child(box)
	else:
		get_parent().add_child(box)
	
	spawned_boxes.append(box)
	
	SignalBus.publish("box.spawned", {
		"box": box,
		"thing_type_id": thing_type_id
	})
	
	return box


func _calculate_box_positions(count: int) -> Array[Vector2]:
	"""Calculate evenly distributed positions along board edges."""
	var positions: Array[Vector2] = []
	
	if not _game_board:
		push_error("BoxSpawner: No game board reference")
		return positions
	
	# Get available edge positions
	var all_edges = ["north", "south", "east", "west"]
	var edge_index = 0
	
	for i in range(count):
		var edge = all_edges[edge_index % all_edges.size()]
		var edge_positions = _game_board.spawn_edges.get(edge, [])
		
		if edge_positions.is_empty():
			# Fallback to random position
			positions.append(_game_board.get_random_edge_position(edge))
		else:
			# Distribute evenly along this edge
			var _boxes_on_edge = _count_boxes_planned_for_edge(positions, edge, count, all_edges)
			var edge_slot = _get_next_slot_on_edge(edge, positions, edge_positions)
			positions.append(edge_slot)
		
		edge_index += 1
	
	return positions


func _count_boxes_planned_for_edge(_planned: Array[Vector2], edge: String, total: int, edges: Array) -> int:
	"""Estimate how many boxes will be on this edge."""
	@warning_ignore("integer_division")
	var boxes_per_edge = total / edges.size()
	return boxes_per_edge + (1 if total % edges.size() > edges.find(edge) else 0)


func _get_next_slot_on_edge(edge: String, used_positions: Array[Vector2], available: Array) -> Vector2:
	"""Get the next available position on an edge, avoiding used positions."""
	if available.is_empty():
		return Vector2.ZERO
	
	# Find spacing between boxes
	var used_on_edge: Array[Vector2] = []
	for pos in used_positions:
		if _position_is_on_edge(pos, edge):
			used_on_edge.append(pos)
	
	# Simple approach: pick from available positions, skipping used ones
	for candidate in available:
		var is_used = false
		for used in used_on_edge:
			if candidate.distance_to(used) < 48:  # Minimum spacing
				is_used = true
				break
		if not is_used:
			return candidate
	
	# Fallback: return random available position
	return available[randi() % available.size()]


func _position_is_on_edge(pos: Vector2, edge: String) -> bool:
	"""Check if a position is on a specific edge."""
	if not _game_board:
		return false
	
	var half_size = _game_board.get_board_pixel_size() * 0.5
	var tolerance = GameBoard.TILE_SIZE
	
	match edge:
		"north":
			return abs(pos.y - (-half_size.y + GameBoard.TILE_SIZE * 0.5)) < tolerance
		"south":
			return abs(pos.y - (half_size.y - GameBoard.TILE_SIZE * 0.5)) < tolerance
		"east":
			return abs(pos.x - (half_size.x - GameBoard.TILE_SIZE * 0.5)) < tolerance
		"west":
			return abs(pos.x - (-half_size.x + GameBoard.TILE_SIZE * 0.5)) < tolerance
	
	return false


# =============================================================================
# STOCKING
# =============================================================================
func _stock_all_boxes() -> void:
	"""Stock all boxes with initial Things."""
	for box in spawned_boxes:
		if is_instance_valid(box):
			_stock_box(box, initial_things_per_box)


func _stock_box(box: Box, count: int) -> void:
	"""Spawn Things and add them to a box."""
	for i in range(count):
		var thing: Thing
		
		if thing_scene:
			thing = thing_scene.instantiate() as Thing
		else:
			thing = Thing.new()
		
		thing.thing_type_id = box.thing_type_id
		
		# Add to scene tree first
		if _game_board:
			_game_board.add_child(thing)
		else:
			get_parent().add_child(thing)
		
		# Then add to box (this will position it and update state)
		box.add_thing(thing)
		
		SignalBus.publish("thing.spawned", {
			"thing": thing,
			"thing_type_id": thing.thing_type_id
		})


func spawn_additional_thing(thing_type_id: String) -> Thing:
	"""Spawn a single additional thing, scattered on the board."""
	var thing: Thing
	
	if thing_scene:
		thing = thing_scene.instantiate() as Thing
	else:
		thing = Thing.new()
	
	thing.thing_type_id = thing_type_id
	
	# Position randomly on board
	if _game_board:
		thing.global_position = _game_board.get_random_board_position()
		_game_board.add_child(thing)
	else:
		get_parent().add_child(thing)
	
	SignalBus.publish("thing.spawned", {
		"thing": thing,
		"thing_type_id": thing_type_id
	})
	
	return thing


# =============================================================================
# CLEANUP
# =============================================================================
func clear_boxes() -> void:
	"""Remove all spawned boxes."""
	for box in spawned_boxes:
		if is_instance_valid(box):
			box.queue_free()
	spawned_boxes.clear()


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_round_setup(round_number: int) -> void:
	spawn_boxes_for_round(round_number)


# =============================================================================
# PUBLIC API
# =============================================================================
func get_box_count() -> int:
	return spawned_boxes.size()


func get_boxes() -> Array[Box]:
	return spawned_boxes.duplicate()


func get_boxes_by_type(thing_type_id: String) -> Array[Box]:
	var result: Array[Box] = []
	for box in spawned_boxes:
		if is_instance_valid(box) and box.thing_type_id == thing_type_id:
			result.append(box)
	return result
