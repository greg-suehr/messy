extends Node2D
class_name GameBoard
## GameBoard - Manages the play area for Messy
##
## Handles board boundaries, spawn positions, collision layers,
## and spatial queries for boxes, things, and guys.

# =============================================================================
# CONSTANTS
# =============================================================================
const TILE_SIZE := 32
const MIN_BOARD_SIZE := Vector2i(6, 6)
const MAX_BOARD_SIZE := Vector2i(20, 20)

# Colors from GDD
const BOARD_BG_COLOR := Color("#1a1a2e")  # Deep navy
const BOARD_BORDER_COLOR_1 := Color("#FF69B4")  # Hot pink
const BOARD_BORDER_COLOR_2 := Color("#00FFFF")  # Cyan

# Collision layers
const LAYER_PLAYER := 1
const LAYER_THINGS := 2
const LAYER_BOXES := 4
const LAYER_GUYS := 8
const LAYER_WALLS := 16

# =============================================================================
# EXPORTS
# =============================================================================
@export var initial_size := Vector2i(8, 8)

# =============================================================================
# STATE
# =============================================================================
var board_size: Vector2i = Vector2i(8, 8)
var board_rect: Rect2  # World-space bounds
var spawn_edges: Dictionary = {}  # "north", "south", "east", "west" -> Array of positions

# Entity tracking
var active_boxes: Array[Box] = []
var active_things: Array[Thing] = []
var active_guys: Array[Guy] = []

# Visual
var _border_gradient_offset: float = 0.0


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_connect_signals()
	set_board_size(initial_size)


func _connect_signals() -> void:
	SignalBus.round_setup_started.connect(_on_round_setup)
	SignalBus.box_spawned.connect(_on_box_spawned)
	SignalBus.thing_spawned.connect(_on_thing_spawned)
	SignalBus.guy_spawned.connect(_on_guy_spawned)
	SignalBus.guy_despawned.connect(_on_guy_despawned)


# =============================================================================
# BOARD CONFIGURATION
# =============================================================================
func set_board_size(new_size: Vector2i) -> void:
	board_size = new_size.clamp(MIN_BOARD_SIZE, MAX_BOARD_SIZE)
	_recalculate_bounds()
	_calculate_spawn_edges()
	queue_redraw()


func expand_board(direction: String, amount: int = 2) -> void:
	"""Expand the board in a direction. Called from parameterization."""
	match direction:
		"north", "south":
			board_size.y += amount
		"east", "west":
			board_size.x += amount
		"all":
			board_size += Vector2i(amount, amount)
	
	board_size = board_size.clamp(MIN_BOARD_SIZE, MAX_BOARD_SIZE)
	_recalculate_bounds()
	_calculate_spawn_edges()
	queue_redraw()


func _recalculate_bounds() -> void:
	var pixel_size = Vector2(board_size) * TILE_SIZE
	# Center the board at origin
	board_rect = Rect2(-pixel_size * 0.5, pixel_size)
	
	# Update GameState
	GameState.param_board_size = board_size


func _calculate_spawn_edges() -> void:
	"""Calculate valid spawn positions along each edge for boxes."""
	spawn_edges.clear()
	
	var half_size = Vector2(board_size) * TILE_SIZE * 0.5
	var padding = TILE_SIZE * 1.5  # Keep away from corners
	
	# North edge (top)
	spawn_edges["north"] = []
	for x in range(int(-half_size.x + padding), int(half_size.x - padding), TILE_SIZE):
		spawn_edges["north"].append(Vector2(x, -half_size.y + TILE_SIZE * 0.5))
	
	# South edge (bottom)
	spawn_edges["south"] = []
	for x in range(int(-half_size.x + padding), int(half_size.x - padding), TILE_SIZE):
		spawn_edges["south"].append(Vector2(x, half_size.y - TILE_SIZE * 0.5))
	
	# East edge (right)
	spawn_edges["east"] = []
	for y in range(int(-half_size.y + padding), int(half_size.y - padding), TILE_SIZE):
		spawn_edges["east"].append(Vector2(half_size.x - TILE_SIZE * 0.5, y))
	
	# West edge (left)
	spawn_edges["west"] = []
	for y in range(int(-half_size.y + padding), int(half_size.y - padding), TILE_SIZE):
		spawn_edges["west"].append(Vector2(-half_size.x + TILE_SIZE * 0.5, y))


# =============================================================================
# SPATIAL QUERIES
# =============================================================================
func get_random_board_position() -> Vector2:
	"""Get a random position inside the board, avoiding edges."""
	var margin = TILE_SIZE * 2
	return Vector2(
		randf_range(board_rect.position.x + margin, board_rect.end.x - margin),
		randf_range(board_rect.position.y + margin, board_rect.end.y - margin)
	)


func get_random_edge_position(edge: String = "") -> Vector2:
	"""Get a random position along an edge. If edge is empty, pick random edge."""
	if edge.is_empty():
		var edges = ["north", "south", "east", "west"]
		edge = edges[randi() % edges.size()]
	
	if not spawn_edges.has(edge) or spawn_edges[edge].is_empty():
		return get_exit_position(edge)
	
	return spawn_edges[edge][randi() % spawn_edges[edge].size()]


func get_exit_position(from_edge: String = "") -> Vector2:
	"""Get a position outside the board for guys to exit to."""
	var half_size = Vector2(board_size) * TILE_SIZE * 0.5
	var exit_margin = TILE_SIZE * 3
	
	if from_edge.is_empty():
		var edges = ["north", "south", "east", "west"]
		from_edge = edges[randi() % edges.size()]
	
	match from_edge:
		"north":
			return Vector2(randf_range(-half_size.x, half_size.x), -half_size.y - exit_margin)
		"south":
			return Vector2(randf_range(-half_size.x, half_size.x), half_size.y + exit_margin)
		"east":
			return Vector2(half_size.x + exit_margin, randf_range(-half_size.y, half_size.y))
		"west":
			return Vector2(-half_size.x - exit_margin, randf_range(-half_size.y, half_size.y))
		_:
			return Vector2(half_size.x + exit_margin, 0)


func get_spawn_position_for_guy() -> Vector2:
	"""Get a position outside the board for guys to spawn at."""
	return get_exit_position()


func is_inside_board(pos: Vector2) -> bool:
	"""Check if a position is inside the playable area."""
	return board_rect.has_point(pos)


func clamp_to_board(pos: Vector2, margin: float = 0.0) -> Vector2:
	"""Clamp a position to stay within board bounds."""
	var inner_rect = board_rect.grow(-margin)
	return Vector2(
		clampf(pos.x, inner_rect.position.x, inner_rect.end.x),
		clampf(pos.y, inner_rect.position.y, inner_rect.end.y)
	)


func get_nearest_box(pos: Vector2, thing_type_id: String = "") -> Box:
	"""Find the nearest box, optionally filtering by thing type."""
	var nearest: Box = null
	var nearest_dist := INF
	
	for box in active_boxes:
		if not is_instance_valid(box):
			continue
		if thing_type_id != "" and box.thing_type_id != thing_type_id:
			continue
		
		var dist = pos.distance_squared_to(box.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = box
	
	return nearest


func get_boxes_of_type(thing_type_id: String) -> Array[Box]:
	"""Get all boxes that hold a specific thing type."""
	var result: Array[Box] = []
	for box in active_boxes:
		if is_instance_valid(box) and box.thing_type_id == thing_type_id:
			result.append(box)
	return result


func get_scattered_things() -> Array[Thing]:
	"""Get all things currently scattered on the board (not in boxes)."""
	var result: Array[Thing] = []
	for thing in active_things:
		if is_instance_valid(thing) and not thing.is_in_box:
			result.append(thing)
	return result


func get_things_near(pos: Vector2, radius: float) -> Array[Thing]:
	"""Get all scattered things within radius of position."""
	var result: Array[Thing] = []
	var radius_sq = radius * radius
	
	for thing in active_things:
		if not is_instance_valid(thing):
			continue
		if thing.is_in_box or thing.is_held_by_player or thing.is_held_by_guy:
			continue
		if pos.distance_squared_to(thing.global_position) <= radius_sq:
			result.append(thing)
	
	return result


# =============================================================================
# ENTITY TRACKING
# =============================================================================
func register_box(box: Box) -> void:
	if box not in active_boxes:
		active_boxes.append(box)


func unregister_box(box: Box) -> void:
	active_boxes.erase(box)


func register_thing(thing: Thing) -> void:
	if thing not in active_things:
		active_things.append(thing)


func unregister_thing(thing: Thing) -> void:
	active_things.erase(thing)


func register_guy(guy: Guy) -> void:
	if guy not in active_guys:
		active_guys.append(guy)


func unregister_guy(guy: Guy) -> void:
	active_guys.erase(guy)


func clear_all_entities() -> void:
	"""Remove all entities from the board. Called between rounds."""
	for box in active_boxes:
		if is_instance_valid(box):
			box.queue_free()
	active_boxes.clear()
	
	for thing in active_things:
		if is_instance_valid(thing):
			thing.queue_free()
	active_things.clear()
	
	for guy in active_guys:
		if is_instance_valid(guy):
			guy.queue_free()
	active_guys.clear()


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_round_setup(_round_number: int) -> void:
	# Apply any pending board size changes from parameterization
	set_board_size(GameState.param_board_size)


func _on_box_spawned(box: Node2D, _thing_type_id: String) -> void:
	if box is Box:
		register_box(box as Box)


func _on_thing_spawned(thing: Node2D, _thing_type_id: String) -> void:
	if thing is Thing:
		register_thing(thing as Thing)


func _on_guy_spawned(guy: Node2D, _guy_type_id: String) -> void:
	if guy is Guy:
		register_guy(guy as Guy)


func _on_guy_despawned(guy: Node2D) -> void:
	if guy is Guy:
		unregister_guy(guy as Guy)


# =============================================================================
# DRAWING
# =============================================================================
func _process(delta: float) -> void:
	# Animate border gradient
	_border_gradient_offset += delta * 0.5
	if _border_gradient_offset > TAU:
		_border_gradient_offset -= TAU
	queue_redraw()


func _draw() -> void:
	# Draw background
	draw_rect(board_rect, BOARD_BG_COLOR)
	
	# Draw animated gradient border
	_draw_gradient_border()
	
	# Draw grid (subtle)
	_draw_grid()


func _draw_gradient_border() -> void:
	var border_width = 4.0
	var corners = [
		board_rect.position,
		Vector2(board_rect.end.x, board_rect.position.y),
		board_rect.end,
		Vector2(board_rect.position.x, board_rect.end.y)
	]
	
	# Draw each edge with gradient color
	for i in range(4):
		var start = corners[i]
		var end = corners[(i + 1) % 4]
		
		# Animated gradient based on position
		var t = (float(i) / 4.0 + _border_gradient_offset / TAU)
		t = fmod(t, 1.0)
		var color = BOARD_BORDER_COLOR_1.lerp(BOARD_BORDER_COLOR_2, sin(t * PI))
		
		draw_line(start, end, color, border_width, true)


func _draw_grid() -> void:
	var grid_color = BOARD_BG_COLOR.lightened(0.1)
	grid_color.a = 0.3
	
	# Vertical lines
	for x in range(int(board_rect.position.x), int(board_rect.end.x) + 1, TILE_SIZE):
		draw_line(
			Vector2(x, board_rect.position.y),
			Vector2(x, board_rect.end.y),
			grid_color, 1.0
		)
	
	# Horizontal lines
	for y in range(int(board_rect.position.y), int(board_rect.end.y) + 1, TILE_SIZE):
		draw_line(
			Vector2(board_rect.position.x, y),
			Vector2(board_rect.end.x, y),
			grid_color, 1.0
		)


# =============================================================================
# PUBLIC API
# =============================================================================
func get_board_pixel_size() -> Vector2:
	return Vector2(board_size) * TILE_SIZE


func get_board_center() -> Vector2:
	return board_rect.get_center()


func get_stocked_ratio() -> float:
	"""Calculate ratio of boxes that currently have things in them."""
	if active_boxes.is_empty():
		return 1.0
	
	var stocked_count = 0
	for box in active_boxes:
		if is_instance_valid(box) and box.has_things():
			stocked_count += 1
	
	return float(stocked_count) / float(active_boxes.size())
