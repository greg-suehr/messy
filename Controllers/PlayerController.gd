extends CharacterBody2D
class_name PlayerController
## PlayerController - Main player character for Messy
##
## Handles movement, picking up Things, managing a stack of held Things,
## and dropping Things into Boxes. 
##
## - SPACE: Always picks up nearby Things (adds to top of stack)
## - E: Drop from TOP of stack (only works when near a matching Box)
## - Q: Drop from BOTTOM of stack (only works when near a matching Box)

# =============================================================================
# CONSTANTS
# =============================================================================
const SPEED := 300.0
const ACCELERATION := 2000.0
const FRICTION := 1500.0
const PICKUP_RADIUS := 40.0
const BOX_INTERACTION_RADIUS := 60.0  # How close to be for box interactions
const MAX_STACK_SIZE := 10  # Increased for more tactical depth

# Stun/mismatch feedback
const MISMATCH_STUN_DURATION := 0.25  # Seconds of movement lockout
const MISMATCH_KNOCKBACK_FORCE := 200.0  # Pixels/second knockback

# Visual
const PLAYER_COLOR := Color("#FFFFFF")
const PLAYER_SIZE := 20.0

# =============================================================================
# STATE
# =============================================================================
var thing_stack: Array[Thing] = []
var is_active: bool = false  # Only process input during ACTIVE phase

# Stun state
var _is_stunned: bool = false
var _stun_timer: float = 0.0
var _stun_flash_timer: float = 0.0  # For visual stun indicator

# Visual
var _pulse_scale: float = 1.0
var _move_direction: Vector2 = Vector2.ZERO

# Box proximity tracking
var _nearest_box: Box = null
var _is_near_any_box: bool = false

# References
var _game_board: GameBoard = null
var _stack_ui = null  # Reference to StackUI for hints


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


func set_stack_ui(ui) -> void:
	_stack_ui = ui


# =============================================================================
# INPUT PROCESSING
# =============================================================================
func _physics_process(delta: float) -> void:
	if not is_active:
		velocity = Vector2.ZERO
		return
	
	# Process stun timer
	_process_stun(delta)
	
	# Only handle normal movement/actions if not stunned
	if not _is_stunned:
		_handle_movement(delta)
		_handle_actions()
	else:
		# During stun, apply friction to knockback velocity
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * 2.0 * delta)
	
	_update_box_proximity()
	
	move_and_slide()
	
	# Clamp to board bounds
	if _game_board:
		global_position = _game_board.clamp_to_board(global_position, PLAYER_SIZE)
	
	# Update held things positions (hide them, they're shown in UI now)
	_update_stack_positions()
	
	# Emit position for audio/visual systems
	SignalBus.publish("player.moved", {"position": global_position})
	
	queue_redraw()


func _process_stun(delta: float) -> void:
	"""Process stun timer and visual effects."""
	if _is_stunned:
		_stun_timer -= delta
		_stun_flash_timer += delta * 20.0  # Fast flash
		
		if _stun_timer <= 0:
			_is_stunned = false
			_stun_timer = 0.0
			_stun_flash_timer = 0.0


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


func _update_box_proximity() -> void:
	"""Check if player is near any box and update UI hints."""
	_nearest_box = null
	_is_near_any_box = false
	
	if not _game_board:
		return
	
	# Find nearest box within interaction radius
	var nearest_dist := BOX_INTERACTION_RADIUS * BOX_INTERACTION_RADIUS
	
	for box in _game_board.active_boxes:
		if not is_instance_valid(box):
			continue
		
		var dist = global_position.distance_squared_to(box.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			_nearest_box = box
			_is_near_any_box = true
	
	# Update Stack UI hint
	if _stack_ui and _stack_ui.has_method("set_near_box_hint"):
		var box_type = _nearest_box.thing_type_id if _nearest_box else ""
		_stack_ui.set_near_box_hint(_is_near_any_box, box_type)


func _handle_actions() -> void:
	# SPACE / ui_accept: Always pick up nearby thing
	if Input.is_action_just_pressed("ui_accept"):
		_try_pickup_thing()
	
	# E / action_primary: Drop from TOP of stack (only if near matching box)
	if Input.is_action_just_pressed("action_primary"):
		_try_drop_to_box_top()
	
	# Q / action_secondary: Drop from BOTTOM of stack (only if near matching box)
	if Input.is_action_just_pressed("action_secondary"):
		_try_drop_to_box_bottom()


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
		SignalBus.publish("audio.sfx", {
			"sfx_id": "error",
			"position": global_position
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
	else:
		# No thing nearby - show subtle feedback
		SignalBus.publish("ui.popup", {
			"message": "Nothing nearby",
			"position": global_position + Vector2(0, -40),
			"type": "info"
		})


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


func _try_drop_to_box_top() -> void:
	"""Attempt to drop the top item into a nearby matching box."""
	if thing_stack.is_empty():
		SignalBus.publish("ui.popup", {
			"message": "Stack empty!",
			"position": global_position + Vector2(0, -40),
			"type": "info"
		})
		return
	
	if not _is_near_any_box:
		SignalBus.publish("ui.popup", {
			"message": "Get closer to a Box!",
			"position": global_position + Vector2(0, -40),
			"type": "warning"
		})
		SignalBus.publish("audio.sfx", {
			"sfx_id": "error",
			"position": global_position
		})
		return
	
	# Get top thing and check if it matches nearest box
	var top_thing = thing_stack.back()
	
	if not top_thing.matches_box(_nearest_box):
		# Wrong box type - show error with visual feedback
		SignalBus.publish("ui.popup", {
			"message": "Wrong Box type!",
			"position": global_position + Vector2(0, -40),
			"type": "warning"
		})
		SignalBus.publish("audio.sfx", {
			"sfx_id": "mismatch",  # Percussive rejection sound
			"position": global_position
		})
		# Small stun/knockback effect
		_apply_mismatch_feedback()
		return
	
	# Success! Remove from stack and add to box
	var thing = thing_stack.pop_back()
	_nearest_box.add_thing(thing)
	
	SignalBus.publish("player.thing.dropped", {
		"thing": thing,
		"into_box": true
	})
	
	SignalBus.publish("player.stack.changed", {
		"stack": thing_stack.duplicate()
	})


func _try_drop_to_box_bottom() -> void:
	"""Attempt to drop the bottom item into a nearby matching box."""
	if thing_stack.is_empty():
		SignalBus.publish("ui.popup", {
			"message": "Stack empty!",
			"position": global_position + Vector2(0, -40),
			"type": "info"
		})
		return
	
	if not _is_near_any_box:
		SignalBus.publish("ui.popup", {
			"message": "Get closer to a Box!",
			"position": global_position + Vector2(0, -40),
			"type": "warning"
		})
		SignalBus.publish("audio.sfx", {
			"sfx_id": "error",
			"position": global_position
		})
		return
	
	# Get bottom thing and check if it matches nearest box
	var bottom_thing = thing_stack.front()
	
	if not bottom_thing.matches_box(_nearest_box):
		# Wrong box type
		SignalBus.publish("ui.popup", {
			"message": "Wrong Box type!",
			"position": global_position + Vector2(0, -40),
			"type": "warning"
		})
		SignalBus.publish("audio.sfx", {
			"sfx_id": "mismatch",  # Percussive rejection sound
			"position": global_position
		})
		_apply_mismatch_feedback()
		return
	
	# Success! Remove from stack and add to box
	var thing = thing_stack.pop_front()
	_nearest_box.add_thing(thing)
	
	SignalBus.publish("player.thing.dropped", {
		"thing": thing,
		"into_box": true
	})
	
	SignalBus.publish("player.stack.changed", {
		"stack": thing_stack.duplicate()
	})


func _apply_mismatch_feedback() -> void:
	"""Apply visual/physical feedback when trying to drop wrong thing type.
	Per GDD: Box flashes, player gets hit with a small percussive stun."""
	
	# Trigger box reject flash
	if _nearest_box and is_instance_valid(_nearest_box):
		_nearest_box.flash_reject()
	
	# Apply stun (movement lockout)
	_is_stunned = true
	_stun_timer = MISMATCH_STUN_DURATION
	_stun_flash_timer = 0.0
	
	# Knockback away from box
	if _nearest_box:
		var away_dir = (global_position - _nearest_box.global_position).normalized()
		velocity = away_dir * MISMATCH_KNOCKBACK_FORCE
	
	# Screen shake - percussive feel
	SignalBus.publish("ui.shake", {
		"intensity": 0.35,
		"duration": 0.15
	})
	
	# Red flash on screen for emphasis
	SignalBus.publish("ui.flash", {
		"color": Color(1.0, 0.3, 0.3, 0.3),
		"duration": 0.1
	})
	
	# Publish mismatch event for audio system
	SignalBus.publish("player.box.mismatch", {
		"player": self,
		"box": _nearest_box,
		"position": global_position
	})


func _update_stack_positions() -> void:
	"""Hide held things from the game world (they're displayed in StackUI)."""
	for i in range(thing_stack.size()):
		var thing = thing_stack[i]
		if is_instance_valid(thing):
			# Move things off-screen (they're visualized in StackUI)
			thing.global_position = Vector2(-9999, -9999)
			thing.visible = false


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
	_nearest_box = null
	_is_near_any_box = false
	
	# Reset stun state
	_is_stunned = false
	_stun_timer = 0.0
	_stun_flash_timer = 0.0
	
	SignalBus.publish("player.stack.changed", {
		"stack": []
	})


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


func is_near_box() -> bool:
	return _is_near_any_box


func get_nearest_box() -> Box:
	return _nearest_box


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
	var draw_color = PLAYER_COLOR
	
	# Stun visual effect - red flash oscillation
	if _is_stunned:
		var flash_alpha = abs(sin(_stun_flash_timer)) * 0.6
		draw_color = PLAYER_COLOR.lerp(Color.RED, flash_alpha)
		# Slight size jitter during stun
		draw_size *= 1.0 + sin(_stun_flash_timer * 2.0) * 0.1
	
	# Draw body (simple circle for now)
	draw_circle(Vector2.ZERO, draw_size, draw_color)
	
	# Draw direction indicator (only if not stunned)
	if _move_direction.length() > 0 and not _is_stunned:
		var indicator_pos = _move_direction * draw_size * 0.6
		draw_circle(indicator_pos, draw_size * 0.25, draw_color.darkened(0.3))
	
	# Draw outline
	var outline_color = draw_color.darkened(0.4)
	if _is_stunned:
		outline_color = Color.RED.darkened(0.2)
	draw_arc(Vector2.ZERO, draw_size, 0, TAU, 32, outline_color, 2.0, true)
	
	# Draw box proximity indicator
	if _is_near_any_box and _nearest_box:
		var box_dir = (_nearest_box.global_position - global_position).normalized()
		var indicator_pos = box_dir * (draw_size + 8)
		var box_color = _nearest_box._base_color if _nearest_box else Color.YELLOW
		draw_circle(indicator_pos, 4, box_color)
	
	# Draw stack count indicator (compact)
	if not thing_stack.is_empty():
		var count_pos = Vector2(0, -draw_size - 12)
		var font = ThemeDB.fallback_font
		draw_string(font, count_pos + Vector2(-4, 0), str(thing_stack.size()), HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)