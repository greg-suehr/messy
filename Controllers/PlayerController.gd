extends CharacterBody2D
class_name PlayerController
## PlayerController - Main player character for Messy
##
## Handles movement, picking up Things, managing a stack of held Things,
## and dropping Things into Boxes. Simple, responsive controls tuned for
## the fast-paced "bubblegum hyperpop chaos" aesthetic.

# =============================================================================
# CONSTANTS
# =============================================================================
const SPEED := 300.0
const ACCELERATION := 2000.0
const FRICTION := 1500.0
const PICKUP_RADIUS := 40.0
const DROP_OFFSET := 24.0
const MAX_STACK_SIZE := 5

# Visual
const PLAYER_COLOR := Color("#FFFFFF")
const PLAYER_SIZE := 20.0

# =============================================================================
# STATE
# =============================================================================
var thing_stack: Array[Thing] = []
var is_active: bool = false  # Only process input during ACTIVE phase

# Visual
var _pulse_scale: float = 1.0
var _move_direction: Vector2 = Vector2.ZERO

# References
var _game_board: GameBoard = null


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_setup_collision()
	_connect_signals()
	add_to_group("player")


func _setup_collision() -> void:
	collision_layer = GameBoard.LAYER_PLAYER
	collision_mask = GameBoard.LAYER_WALLS
	
	# Add collision shape if not present
	if get_node_or_null("CollisionShape2D") == null:
		var shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = PLAYER_SIZE * 0.6
		shape.shape = circle
		add_child(shape)


func _connect_signals() -> void:
	SignalBus.round_active_started.connect(_on_round_started)
	SignalBus.round_ended.connect(_on_round_ended)
	SignalBus.game_paused.connect(_on_game_paused)
	SignalBus.game_resumed.connect(_on_game_resumed)


func set_game_board(board: GameBoard) -> void:
	_game_board = board


# =============================================================================
# INPUT PROCESSING
# =============================================================================
func _physics_process(delta: float) -> void:
	if not is_active:
		velocity = Vector2.ZERO
		return
	
	_handle_movement(delta)
	_handle_actions()
	
	move_and_slide()
	
	# Clamp to board bounds
	if _game_board:
		global_position = _game_board.clamp_to_board(global_position, PLAYER_SIZE)
	
	# Update held things positions
	_update_stack_positions()
	
	# Emit position for audio/visual systems
	SignalBus.publish("player.moved", {"position": global_position})
	
	queue_redraw()


func _handle_movement(delta: float) -> void:
	# Get input vector (supports both WASD and arrow keys)
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")
	
	# Also check WASD explicitly for better response
	if Input.is_action_pressed("move_left"):
		input_dir.x = -1
	elif Input.is_action_pressed("move_right"):
		input_dir.x = 1
	if Input.is_action_pressed("move_up"):
		input_dir.y = -1
	elif Input.is_action_pressed("move_down"):
		input_dir.y = 1
	
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
		_move_direction = input_dir
		velocity = velocity.move_toward(input_dir * SPEED, ACCELERATION * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)


func _handle_actions() -> void:
	# Primary action: Pickup nearby thing OR drop from top of stack
	if Input.is_action_just_pressed("action_primary") or Input.is_action_just_pressed("ui_accept"):
		if thing_stack.is_empty():
			_try_pickup_thing()
		else:
			_drop_thing_top()
	
	# Secondary action: Drop from bottom of stack
	if Input.is_action_just_pressed("action_secondary"):
		if not thing_stack.is_empty():
			_drop_thing_bottom()


# =============================================================================
# THING MANAGEMENT
# =============================================================================
func _try_pickup_thing() -> void:
	if thing_stack.size() >= MAX_STACK_SIZE:
		SignalBus.publish("ui.popup", {
			"message": "Stack full!",
			"position": global_position + Vector2(0, -40),
			"type": "warning"
		})
		return
	
	# Find nearest pickable thing
	var nearest: Thing = null
	var nearest_dist := PICKUP_RADIUS * PICKUP_RADIUS
	
	if _game_board:
		var nearby = _game_board.get_things_near(global_position, PICKUP_RADIUS)
		for thing in nearby:
			var dist = global_position.distance_squared_to(thing.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = thing
	
	if nearest:
		_pickup_thing(nearest)


func _pickup_thing(thing: Thing) -> void:
	thing.pick_up_by_player()
	thing_stack.append(thing)
	
	SignalBus.publish("player.thing.picked_up", {
		"thing": thing,
		"stack_size": thing_stack.size()
	})
	
	SignalBus.publish("player.stack.changed", {
		"stack": thing_stack.duplicate()
	})
	
	SignalBus.publish("audio.sfx", {
		"sfx_id": "pickup",
		"position": global_position
	})
	
	_pulse_scale = 1.15  # Brief visual feedback


func _drop_thing_top() -> void:
	if thing_stack.is_empty():
		return
	
	var thing = thing_stack.pop_back()
	_drop_thing(thing)


func _drop_thing_bottom() -> void:
	if thing_stack.is_empty():
		return
	
	var thing = thing_stack.pop_front()
	_drop_thing(thing)


func _drop_thing(thing: Thing) -> void:
	# Calculate drop position (slightly in front of player)
	var drop_pos = global_position
	if _move_direction.length() > 0:
		drop_pos += _move_direction * DROP_OFFSET
	
	thing.drop_at(drop_pos)
	
	# Check if dropped near matching box (handled by Box collision detection)
	var into_box = false
	if _game_board:
		var box = _game_board.get_nearest_box(drop_pos, thing.thing_type_id)
		if box and drop_pos.distance_to(box.global_position) < 48:
			into_box = true
			# Box.add_thing will be triggered by area overlap
	
	SignalBus.publish("player.thing.dropped", {
		"thing": thing,
		"into_box": into_box
	})
	
	SignalBus.publish("player.stack.changed", {
		"stack": thing_stack.duplicate()
	})
	
	SignalBus.publish("audio.sfx", {
		"sfx_id": "drop",
		"position": drop_pos
	})


func _update_stack_positions() -> void:
	"""Position held things above player, stacked vertically."""
	for i in range(thing_stack.size()):
		var thing = thing_stack[i]
		if is_instance_valid(thing):
			var offset_y = -PLAYER_SIZE - (i * 16)
			thing.global_position = global_position + Vector2(0, offset_y)


# =============================================================================
# STATE MANAGEMENT
# =============================================================================
func reset_for_round() -> void:
	"""Reset player state for a new round."""
	# Drop all held things
	for thing in thing_stack:
		if is_instance_valid(thing):
			thing.queue_free()
	thing_stack.clear()
	
	# Reset position to center
	global_position = Vector2.ZERO
	velocity = Vector2.ZERO
	is_active = false


func get_stack_size() -> int:
	return thing_stack.size()


func get_stack() -> Array[Thing]:
	return thing_stack.duplicate()


func peek_stack_top() -> Thing:
	if thing_stack.is_empty():
		return null
	return thing_stack.back()


func peek_stack_bottom() -> Thing:
	if thing_stack.is_empty():
		return null
	return thing_stack.front()


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_round_started(_round_number: int) -> void:
	is_active = true
	global_position = Vector2.ZERO


func _on_round_ended(_round_number: int, _result: String) -> void:
	is_active = false


func _on_game_paused() -> void:
	is_active = false


func _on_game_resumed() -> void:
	if GameState.phase == GameState.GamePhase.ACTIVE:
		is_active = true


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	# Pulse animation decay
	_pulse_scale = lerpf(_pulse_scale, 1.0, 0.2)
	
	var draw_size = PLAYER_SIZE * _pulse_scale
	
	# Draw body (simple circle for now)
	draw_circle(Vector2.ZERO, draw_size, PLAYER_COLOR)
	
	# Draw direction indicator
	if _move_direction.length() > 0:
		var indicator_pos = _move_direction * draw_size * 0.6
		draw_circle(indicator_pos, draw_size * 0.25, PLAYER_COLOR.darkened(0.3))
	
	# Draw outline
	draw_arc(Vector2.ZERO, draw_size, 0, TAU, 32, PLAYER_COLOR.darkened(0.4), 2.0, true)
	
	# Draw stack indicator (small dots)
	for i in range(thing_stack.size()):
		var dot_y = -draw_size - 6 - (i * 8)
		draw_circle(Vector2(0, dot_y), 3, Color.WHITE)