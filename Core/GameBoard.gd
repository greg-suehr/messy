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
const MIN_BOARD_SIZE := Vector2i(20, 20)
const MAX_BOARD_SIZE := Vector2i(80, 80)

# HARDENED COLOR PALETTE
const BOARD_BG_COLOR := Color("#0a0a0f")  # Near black
const BOARD_BG_SECONDARY := Color("#12121a")  # Slightly lighter for grid
const BORDER_PRIMARY := Color("#FF2D6A")  # Hot magenta
const BORDER_SECONDARY := Color("#00F0FF")  # Electric cyan
const BORDER_WARNING := Color("#FF4444")  # Danger red
const GRID_COLOR_BASE := Color("#1a1a24")  # Dark grid
const GRID_COLOR_ACCENT := Color("#2a2a3a")  # Slightly visible

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

var _border_phase: float = 0.0
var _pulse_intensity: float = 0.0
var _warning_flash: float = 0.0
var _corner_glow_phase: float = 0.0


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
	SignalBus.chaos_level_changed.connect(_on_chaos_changed)


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
	var padding = TILE_SIZE * 1.5
	
	spawn_edges["north"] = []
	for x in range(int(-half_size.x + padding), int(half_size.x - padding), TILE_SIZE):
		spawn_edges["north"].append(Vector2(x, -half_size.y + TILE_SIZE * 0.5))
	
	spawn_edges["south"] = []
	for x in range(int(-half_size.x + padding), int(half_size.x - padding), TILE_SIZE):
		spawn_edges["south"].append(Vector2(x, half_size.y - TILE_SIZE * 0.5))
	
	spawn_edges["east"] = []
	for y in range(int(-half_size.y + padding), int(half_size.y - padding), TILE_SIZE):
		spawn_edges["east"].append(Vector2(half_size.x - TILE_SIZE * 0.5, y))
	
	spawn_edges["west"] = []
	for y in range(int(-half_size.y + padding), int(half_size.y - padding), TILE_SIZE):
		spawn_edges["west"].append(Vector2(-half_size.x + TILE_SIZE * 0.5, y))


# =============================================================================
# SPATIAL QUERIES
# =============================================================================
func get_random_board_position() -> Vector2:
	var margin = TILE_SIZE * 2
	return Vector2(
		randf_range(board_rect.position.x + margin, board_rect.end.x - margin),
		randf_range(board_rect.position.y + margin, board_rect.end.y - margin)
	)


func get_random_edge_position(edge: String = "") -> Vector2:
	if edge.is_empty():
		var edges = ["north", "south", "east", "west"]
		edge = edges[randi() % edges.size()]
	
	if not spawn_edges.has(edge) or spawn_edges[edge].is_empty():
		return get_exit_position(edge)
	
	return spawn_edges[edge][randi() % spawn_edges[edge].size()]


func get_exit_position(from_edge: String = "") -> Vector2:
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
	return get_exit_position()


func is_inside_board(pos: Vector2) -> bool:
	return board_rect.has_point(pos)


func clamp_to_board(pos: Vector2, margin: float = 0.0) -> Vector2:
	var inner_rect = board_rect.grow(-margin)
	return Vector2(
		clampf(pos.x, inner_rect.position.x, inner_rect.end.x),
		clampf(pos.y, inner_rect.position.y, inner_rect.end.y)
	)


func get_nearest_box(pos: Vector2, thing_type_id: String = "") -> Box:
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
	var result: Array[Box] = []
	for box in active_boxes:
		if is_instance_valid(box) and box.thing_type_id == thing_type_id:
			result.append(box)
	return result


func get_scattered_things() -> Array[Thing]:
	var result: Array[Thing] = []
	for thing in active_things:
		if is_instance_valid(thing) and not thing.is_in_box:
			result.append(thing)
	return result


func get_things_near(pos: Vector2, radius: float) -> Array[Thing]:
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


func _on_chaos_changed(particle_count: int, messiness_ratio: float) -> void:
	# Increase warning visuals with chaos
	_warning_flash = messiness_ratio


# =============================================================================
# UPDATE & DRAWING
# =============================================================================
func _process(delta: float) -> void:
	_border_phase += delta * 2.0
	_corner_glow_phase += delta * 3.0
	_pulse_intensity = lerpf(_pulse_intensity, _warning_flash, delta * 2.0)
	
	if _border_phase > TAU:
		_border_phase -= TAU
	
	queue_redraw()


func _draw() -> void:
	_draw_background()
	_draw_grid()
	_draw_border()
	_draw_corner_markers()
	
	# Draw warning overlay when chaos is high
	if _pulse_intensity > 0.3:
		_draw_warning_overlay()


func _draw_background() -> void:
	# Main dark background
	draw_rect(board_rect, BOARD_BG_COLOR)
	
	# Subtle inner gradient effect (darker edges)
	var inner_rect = board_rect.grow(-8)
	draw_rect(inner_rect, BOARD_BG_SECONDARY)


func _draw_grid() -> void:
	# Harsh industrial grid
	var base_alpha = 0.15 + _pulse_intensity * 0.1
	
	# Main grid lines
	for x in range(int(board_rect.position.x), int(board_rect.end.x) + 1, TILE_SIZE):
		var is_major = int(x) % (TILE_SIZE * 4) == 0
		var grid_color = GRID_COLOR_ACCENT if is_major else GRID_COLOR_BASE
		grid_color.a = base_alpha * (1.5 if is_major else 1.0)
		
		draw_line(
			Vector2(x, board_rect.position.y),
			Vector2(x, board_rect.end.y),
			grid_color, 1.0 if is_major else 0.5
		)
	
	for y in range(int(board_rect.position.y), int(board_rect.end.y) + 1, TILE_SIZE):
		var is_major = int(y) % (TILE_SIZE * 4) == 0
		var grid_color = GRID_COLOR_ACCENT if is_major else GRID_COLOR_BASE
		grid_color.a = base_alpha * (1.5 if is_major else 1.0)
		
		draw_line(
			Vector2(board_rect.position.x, y),
			Vector2(board_rect.end.x, y),
			grid_color, 1.0 if is_major else 0.5
		)


func _draw_border() -> void:
	var border_width = 3.0
	var outer_width = 1.0
	
	var corners = [
		board_rect.position,
		Vector2(board_rect.end.x, board_rect.position.y),
		board_rect.end,
		Vector2(board_rect.position.x, board_rect.end.y)
	]
	
	# Draw each edge with animated color
	for i in range(4):
		var start = corners[i]
		var end = corners[(i + 1) % 4]
		
		# Phase-shifted color per edge
		var t = fmod(_border_phase + (float(i) * PI / 2.0), TAU) / TAU
		var edge_color = BORDER_PRIMARY.lerp(BORDER_SECONDARY, sin(t * PI))
		
		# Add warning tint
		if _pulse_intensity > 0.5:
			edge_color = edge_color.lerp(BORDER_WARNING, (_pulse_intensity - 0.5) * 2.0)
		
		# Main border
		draw_line(start, end, edge_color, border_width, true)
		
		# Outer glow line
		var glow_color = edge_color
		glow_color.a = 0.3
		var offset = Vector2.ZERO
		match i:
			0: offset = Vector2(0, -2)  # Top
			1: offset = Vector2(2, 0)   # Right
			2: offset = Vector2(0, 2)   # Bottom
			3: offset = Vector2(-2, 0)  # Left
		draw_line(start + offset, end + offset, glow_color, outer_width, true)


func _draw_corner_markers() -> void:
	var marker_size = 12.0
	var corners = [
		board_rect.position,
		Vector2(board_rect.end.x, board_rect.position.y),
		board_rect.end,
		Vector2(board_rect.position.x, board_rect.end.y)
	]
	
	for i in range(4):
		var corner = corners[i]
		var pulse = sin(_corner_glow_phase + i * PI / 2) * 0.3 + 0.7
		var marker_color = BORDER_PRIMARY.lerp(BORDER_SECONDARY, float(i) / 4.0)
		marker_color.a = pulse
		
		# Draw L-shaped corner marker
		var h_dir = 1 if i in [0, 3] else -1
		var v_dir = 1 if i in [0, 1] else -1
		
		draw_line(corner, corner + Vector2(marker_size * h_dir, 0), marker_color, 2.0)
		draw_line(corner, corner + Vector2(0, marker_size * v_dir), marker_color, 2.0)
		
		# Corner dot
		draw_circle(corner, 3, marker_color)


func _draw_warning_overlay() -> void:
	# Pulsing red vignette when chaos is high
	var warning_alpha = (_pulse_intensity - 0.3) * 0.3
	var warning_color = BORDER_WARNING
	warning_color.a = warning_alpha * (0.5 + sin(_border_phase * 4) * 0.5)
	
	# Draw edge warnings
	var edge_size = 20.0
	
	# Top edge
	var top_rect = Rect2(board_rect.position, Vector2(board_rect.size.x, edge_size))
	draw_rect(top_rect, warning_color)
	
	# Bottom edge
	var bottom_rect = Rect2(Vector2(board_rect.position.x, board_rect.end.y - edge_size), Vector2(board_rect.size.x, edge_size))
	draw_rect(bottom_rect, warning_color)
	
	# Left edge
	var left_rect = Rect2(board_rect.position, Vector2(edge_size, board_rect.size.y))
	draw_rect(left_rect, warning_color)
	
	# Right edge
	var right_rect = Rect2(Vector2(board_rect.end.x - edge_size, board_rect.position.y), Vector2(edge_size, board_rect.size.y))
	draw_rect(right_rect, warning_color)


# =============================================================================
# PUBLIC API
# =============================================================================
func get_board_pixel_size() -> Vector2:
	return Vector2(board_size) * TILE_SIZE


func get_board_center() -> Vector2:
	return board_rect.get_center()


func get_stocked_ratio() -> float:
	if active_boxes.is_empty():
		return 1.0
	
	var stocked_count = 0
	for box in active_boxes:
		if is_instance_valid(box) and box.has_things():
			stocked_count += 1
	
	return float(stocked_count) / float(active_boxes.size())
