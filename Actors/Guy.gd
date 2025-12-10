extends Area2D
class_name Guy
## Guy - Chaos agents that scatter Things around the Game Board
##
## Guys spawn in the center of the board, target Boxes to acquire Things,
## and scatter them across the board. They use organic arc-based movement
## with boids-like flocking/avoidance behavior.

# =============================================================================
# CONSTANTS
# =============================================================================
# Timing (from GDD revision)
const PATIENCE_LONGING_THRESHOLD := 20.0  # Seconds before entering Longing
const PATIENCE_TANTRUM_THRESHOLD := 30.0  # Seconds before Tantrum
const SPAWN_FADE_DURATION := 0.8  # Fade-in time
const BOUNCE_DURATION := 0.3  # Post-spawn bounce animation

# Movement
const BASE_SPEED := 100.0
const ARC_CURVATURE := 0.4  # How curved the path is (0 = straight, 1 = very curved)
const ARC_RECALCULATION_INTERVAL := 0.5  # How often to recalculate arc path

# Boids parameters
const BOIDS_SEPARATION_RADIUS := 50.0  # Distance to start avoiding others
const BOIDS_SEPARATION_STRENGTH := 150.0  # Force of separation
const BOIDS_PLAYER_AVOIDANCE_RADIUS := 60.0  # Give player more space
const BOIDS_PLAYER_AVOIDANCE_STRENGTH := 200.0

# Visual
const GUY_SIZE := 16.0
const LONGING_PULSE_SPEED := 4.0

# =============================================================================
# ENUMS
# =============================================================================
enum State {
	SPAWNING,   # Fading in at spawn point
	SEEKING,    # Moving toward target box
	AT_BOX,     # At box, taking a thing
	CARRYING,   # Has thing, moving to drop point
	LONGING,    # Can't find thing, getting upset
	TANTRUM,    # Exploding into chaos particles
	LEAVING,    # Exiting the board
	INACTIVE    # Despawned
}

# =============================================================================
# EXPORTS
# =============================================================================
@export var guy_type_id: String = "normal"

# =============================================================================
# STATE
# =============================================================================
var state: State = State.INACTIVE
var guy_type: GuyTypes.GuyType

# Targeting
var preferred_thing_type_id: String = ""
var target_box: Box = null
var target_position: Vector2 = Vector2.ZERO
var exit_position: Vector2 = Vector2.ZERO

# Held thing
var held_thing: Thing = null

# Patience system
var patience_timer: float = 0.0
var is_longing: bool = false

# Movement - Arc pathfinding
var _arc_center: Vector2 = Vector2.ZERO
var _arc_radius: float = 0.0
var _arc_start_angle: float = 0.0
var _arc_end_angle: float = 0.0
var _arc_progress: float = 0.0
var _arc_direction: int = 1  # 1 = counter-clockwise, -1 = clockwise
var _arc_recalc_timer: float = 0.0
var _current_velocity: Vector2 = Vector2.ZERO

# Spawning animation
var _spawn_timer: float = 0.0
var _spawn_alpha: float = 0.0
var _bounce_scale: float = 1.0

# Visual effects
var _pulse_timer: float = 0.0
var _base_color: Color

# References
var _game_board: GameBoard = null
var _guy_spawner = null  # Reference to spawner for boids queries


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_setup_type()
	_setup_collision()
	add_to_group("guys")


func _setup_type() -> void:
	guy_type = GuyTypes.get_type(guy_type_id)
	if guy_type == null:
		push_error("Guy: Invalid guy_type_id '%s'" % guy_type_id)
		guy_type = GuyTypes.get_type("normal")
	
	_base_color = guy_type.color


func _setup_collision() -> void:
	collision_layer = GameBoard.LAYER_GUYS
	collision_mask = GameBoard.LAYER_BOXES | GameBoard.LAYER_THINGS
	
	# Add collision shape if not present
	if get_node_or_null("CollisionShape2D") == null:
		var shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = GUY_SIZE * 0.5
		shape.shape = circle
		add_child(shape)


func initialize(thing_type_id: String, box: Box, exit_pos: Vector2) -> void:
	"""Initialize the guy with targeting information."""
	preferred_thing_type_id = thing_type_id
	target_box = box
	exit_position = exit_pos
	
	# Find game board reference
	_game_board = get_parent() as GameBoard
	if _game_board == null:
		_game_board = get_node_or_null("/root/Main/GameBoard")
	
	# Find guy spawner for boids queries
	_guy_spawner = get_node_or_null("/root/Main/GuySpawner")
	
	# Start in spawning state
	_enter_state(State.SPAWNING)
	
	SignalBus.publish("guy.spawned", {
		"guy": self,
		"guy_type_id": guy_type_id
	})


func set_game_board(board: GameBoard) -> void:
	_game_board = board


# =============================================================================
# STATE MACHINE
# =============================================================================
func _enter_state(new_state: State) -> void:
	var old_state = state
	state = new_state
	
	match new_state:
		State.SPAWNING:
			_spawn_timer = 0.0
			_spawn_alpha = 0.0
			_bounce_scale = 0.5
			modulate.a = 0.0
		
		State.SEEKING:
			patience_timer = 0.0
			is_longing = false
			if target_box and is_instance_valid(target_box):
				target_position = target_box.global_position
				_calculate_arc_path(target_position)
			SignalBus.publish("guy.targeting", {
				"guy": self,
				"box": target_box
			})
		
		State.AT_BOX:
			# Brief pause at box before taking thing
			pass
		
		State.CARRYING:
			# Calculate drop position (scatter near box)
			var scatter_offset = Vector2(
				randf_range(-100, 100),
				randf_range(-100, 100)
			)
			if target_box and is_instance_valid(target_box):
				target_position = target_box.global_position + scatter_offset
			else:
				target_position = global_position + scatter_offset
			_calculate_arc_path(target_position)
		
		State.LONGING:
			is_longing = true
			_pulse_timer = 0.0
			SignalBus.publish("guy.longing", {
				"guy": self,
				"duration": PATIENCE_TANTRUM_THRESHOLD - patience_timer
			})
		
		State.TANTRUM:
			_trigger_tantrum()
		
		State.LEAVING:
			target_position = exit_position
			_calculate_arc_path(target_position)
			SignalBus.publish("guy.left", {"guy": self})
		
		State.INACTIVE:
			SignalBus.publish("guy.despawned", {"guy": self})
			queue_free()


# =============================================================================
# PROCESS
# =============================================================================
func _process(delta: float) -> void:
	if GameState.is_paused:
		return
	
	match state:
		State.SPAWNING:
			_process_spawning(delta)
		State.SEEKING:
			_process_seeking(delta)
		State.AT_BOX:
			_process_at_box(delta)
		State.CARRYING:
			_process_carrying(delta)
		State.LONGING:
			_process_longing(delta)
		State.TANTRUM:
			pass  # Handled by animation
		State.LEAVING:
			_process_leaving(delta)
	
	queue_redraw()


func _process_spawning(delta: float) -> void:
	_spawn_timer += delta
	
	# Fade in
	var fade_progress = _spawn_timer / SPAWN_FADE_DURATION
	_spawn_alpha = clampf(fade_progress, 0.0, 1.0)
	modulate.a = _spawn_alpha
	
	# Bounce animation after fade completes
	if _spawn_timer > SPAWN_FADE_DURATION:
		var bounce_progress = (_spawn_timer - SPAWN_FADE_DURATION) / BOUNCE_DURATION
		if bounce_progress < 1.0:
			# Elastic bounce effect
			_bounce_scale = 1.0 + 0.3 * sin(bounce_progress * PI) * (1.0 - bounce_progress)
		else:
			_bounce_scale = 1.0
			_enter_state(State.SEEKING)


func _process_seeking(delta: float) -> void:
	# Update patience timer
	patience_timer += delta
	
	# Check for longing state
	if patience_timer >= PATIENCE_LONGING_THRESHOLD and not is_longing:
		_enter_state(State.LONGING)
		return
	
	# Move along arc path with boids avoidance
	_move_along_arc(delta)
	
	# Check if reached target box
	if target_box and is_instance_valid(target_box):
		var dist_to_box = global_position.distance_to(target_box.global_position)
		if dist_to_box < GUY_SIZE + 20:
			_enter_state(State.AT_BOX)


func _process_at_box(delta: float) -> void:
	# Continue patience timer while at box
	patience_timer += delta
	
	if patience_timer >= PATIENCE_LONGING_THRESHOLD and not is_longing:
		_enter_state(State.LONGING)
		return
	
	# Try to take a thing from the box
	if target_box and is_instance_valid(target_box):
		if target_box.has_things():
			var thing = target_box.remove_thing(self)
			if thing:
				_pick_up_thing(thing)
				_enter_state(State.CARRYING)
				return
		
		# Box is empty - immediately enter longing
		_enter_state(State.LONGING)
	else:
		# Box disappeared - find another or leave
		_find_new_target_or_leave()


func _process_carrying(delta: float) -> void:
	# Reset patience since we have a thing
	patience_timer = 0.0
	
	# Move to drop position
	_move_along_arc(delta)
	
	# Update held thing position
	if held_thing and is_instance_valid(held_thing):
		held_thing.global_position = global_position + Vector2(0, -GUY_SIZE)
	
	# Check if reached drop position
	var dist_to_target = global_position.distance_to(target_position)
	if dist_to_target < 20:
		_drop_thing()
		
		# Decide what to do next - find another box or leave
		if randf() < 0.7:  # 70% chance to seek another thing
			_find_new_target_or_leave()
		else:
			_enter_state(State.LEAVING)


func _process_longing(delta: float) -> void:
	patience_timer += delta
	_pulse_timer += delta
	
	# Pacing behavior - small random movements
	var pace_offset = Vector2(
		sin(_pulse_timer * 3.0) * 20,
		cos(_pulse_timer * 2.5) * 15
	)
	
	# Apply gentle pacing with boids
	var boids_force = _calculate_boids_force()
	var pace_velocity = pace_offset.normalized() * guy_type.move_speed * 0.3
	_current_velocity = (pace_velocity + boids_force).limit_length(guy_type.move_speed * 0.5)
	global_position += _current_velocity * delta
	
	# Check for tantrum
	if patience_timer >= PATIENCE_TANTRUM_THRESHOLD:
		_enter_state(State.TANTRUM)


func _process_leaving(delta: float) -> void:
	_move_along_arc(delta)
	
	# Check if outside board
	if _game_board:
		if not _game_board.is_inside_board(global_position):
			var dist_to_exit = global_position.distance_to(exit_position)
			if dist_to_exit < 50:
				_enter_state(State.INACTIVE)


# =============================================================================
# ARC PATHFINDING
# =============================================================================
func _calculate_arc_path(destination: Vector2) -> void:
	"""Calculate a circular arc path from current position to destination."""
	var start = global_position
	var end = destination
	var direct_vec = end - start
	var distance = direct_vec.length()
	
	if distance < 10:
		# Too close, just go straight
		_arc_radius = 0
		return
	
	# Determine arc direction (randomly, but consistently per guy)
	_arc_direction = 1 if (hash(get_instance_id()) % 2 == 0) else -1
	
	# Add some randomness to curvature
	var curvature = ARC_CURVATURE * randf_range(0.5, 1.5)
	
	# Calculate arc center perpendicular to the direct path
	var midpoint = (start + end) * 0.5
	var perpendicular = direct_vec.normalized().rotated(PI / 2) * _arc_direction
	
	# The arc center is offset from midpoint
	var offset_distance = distance * curvature
	_arc_center = midpoint + perpendicular * offset_distance
	
	# Calculate radius and angles
	_arc_radius = _arc_center.distance_to(start)
	_arc_start_angle = (start - _arc_center).angle()
	_arc_end_angle = (end - _arc_center).angle()
	
	# Normalize angle difference for smooth interpolation
	var angle_diff = _arc_end_angle - _arc_start_angle
	
	# Ensure we go the "short way" around based on direction
	if _arc_direction > 0:  # Counter-clockwise
		if angle_diff < 0:
			angle_diff += TAU
	else:  # Clockwise
		if angle_diff > 0:
			angle_diff -= TAU
	
	_arc_end_angle = _arc_start_angle + angle_diff
	_arc_progress = 0.0
	_arc_recalc_timer = 0.0


func _move_along_arc(delta: float) -> void:
	"""Move along the calculated arc path with boids avoidance."""
	var target_velocity: Vector2
	
	if _arc_radius < 10:
		# Straight line movement for short distances
		var direct = target_position - global_position
		target_velocity = direct.normalized() * guy_type.move_speed
	else:
		# Arc movement
		var arc_length = abs(_arc_end_angle - _arc_start_angle) * _arc_radius
		var speed_on_arc = guy_type.move_speed / arc_length  # Progress per second
		
		_arc_progress += speed_on_arc * delta
		_arc_progress = clampf(_arc_progress, 0.0, 1.0)
		
		# Calculate position on arc
		var current_angle = lerpf(_arc_start_angle, _arc_end_angle, _arc_progress)
		var arc_position = _arc_center + Vector2(cos(current_angle), sin(current_angle)) * _arc_radius
		
		# Velocity is tangent to arc
		var tangent_angle = current_angle + (PI / 2) * sign(_arc_end_angle - _arc_start_angle)
		target_velocity = Vector2(cos(tangent_angle), sin(tangent_angle)) * guy_type.move_speed
		
		# Recalculate arc periodically to adjust for moving targets
		_arc_recalc_timer += delta
		if _arc_recalc_timer > ARC_RECALCULATION_INTERVAL:
			_arc_recalc_timer = 0.0
			if target_box and is_instance_valid(target_box) and state == State.SEEKING:
				target_position = target_box.global_position
				_calculate_arc_path(target_position)
	
	# Apply boids avoidance
	var boids_force = _calculate_boids_force()
	
	# Blend target velocity with boids force
	var final_velocity = target_velocity + boids_force
	
	# Smooth velocity changes
	_current_velocity = _current_velocity.lerp(final_velocity, delta * 5.0)
	_current_velocity = _current_velocity.limit_length(guy_type.move_speed * 1.3)
	
	# Apply movement
	global_position += _current_velocity * delta
	
	# Clamp to board if we have a reference
	if _game_board and state != State.LEAVING:
		global_position = _game_board.clamp_to_board(global_position, GUY_SIZE)


# =============================================================================
# BOIDS AVOIDANCE
# =============================================================================
func _calculate_boids_force() -> Vector2:
	"""Calculate boids-style separation force from other guys and the player."""
	var separation_force = Vector2.ZERO
	
	# Avoid other guys
	if _guy_spawner and _guy_spawner.has_method("get_active_guys"):
		var other_guys = _guy_spawner.active_guys
		for other in other_guys:
			if other == self or not is_instance_valid(other):
				continue
			
			var to_other = other.global_position - global_position
			var distance = to_other.length()
			
			if distance < BOIDS_SEPARATION_RADIUS and distance > 0:
				# Separation force inversely proportional to distance
				var strength = (1.0 - distance / BOIDS_SEPARATION_RADIUS) * BOIDS_SEPARATION_STRENGTH
				separation_force -= to_other.normalized() * strength
	
	# Alternatively, use game board's active_guys
	elif _game_board:
		for other in _game_board.active_guys:
			if other == self or not is_instance_valid(other):
				continue
			
			var to_other = other.global_position - global_position
			var distance = to_other.length()
			
			if distance < BOIDS_SEPARATION_RADIUS and distance > 0:
				var strength = (1.0 - distance / BOIDS_SEPARATION_RADIUS) * BOIDS_SEPARATION_STRENGTH
				separation_force -= to_other.normalized() * strength
	
	# Avoid player
	var player = _get_player()
	if player:
		var to_player = player.global_position - global_position
		var distance = to_player.length()
		
		if distance < BOIDS_PLAYER_AVOIDANCE_RADIUS and distance > 0:
			var strength = (1.0 - distance / BOIDS_PLAYER_AVOIDANCE_RADIUS) * BOIDS_PLAYER_AVOIDANCE_STRENGTH
			separation_force -= to_player.normalized() * strength
	
	return separation_force


func _get_player() -> Node2D:
	"""Find the player node."""
	var players = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as Node2D
	return null


# =============================================================================
# THING MANAGEMENT
# =============================================================================
func _pick_up_thing(thing: Thing) -> void:
	held_thing = thing
	thing.pick_up_by_guy(self)
	
	SignalBus.publish("guy.took_thing", {
		"guy": self,
		"thing": thing,
		"box": target_box
	})
	
	SignalBus.publish("audio.sfx", {
		"sfx_id": "guy_take",
		"position": global_position
	})


func _drop_thing() -> void:
	if held_thing and is_instance_valid(held_thing):
		held_thing.drop_at(global_position)
		
		SignalBus.publish("guy.dropped_thing", {
			"guy": self,
			"thing": held_thing,
			"position": global_position
		})
		
		SignalBus.publish("audio.sfx", {
			"sfx_id": "guy_drop",
			"position": global_position
		})
		
		held_thing = null


func _find_new_target_or_leave() -> void:
	"""Find a new box to target, or leave the board."""
	if _game_board:
		var boxes = _game_board.get_boxes_of_type(preferred_thing_type_id)
		var valid_boxes: Array[Box] = []
		
		for box in boxes:
			if is_instance_valid(box) and box != target_box and box.has_things():
				valid_boxes.append(box)
		
		if not valid_boxes.is_empty():
			target_box = valid_boxes[randi() % valid_boxes.size()]
			_enter_state(State.SEEKING)
			return
	
	# No valid targets - leave
	_enter_state(State.LEAVING)


# =============================================================================
# TANTRUM
# =============================================================================
func _trigger_tantrum() -> void:
	"""Trigger tantrum explosion and spawn chaos particles."""
	SignalBus.publish("guy.tantrum", {"guy": self})
	
	SignalBus.publish("audio.sfx", {
		"sfx_id": "tantrum",
		"position": global_position
	})
	
	# Screen shake
	SignalBus.publish("ui.shake", {
		"intensity": 0.5,
		"duration": 0.3
	})
	
	# Spawn chaos particles
	var particle_count = guy_type.tantrum_particles if guy_type else 3
	for i in range(particle_count):
		var offset = Vector2(
			randf_range(-30, 30),
			randf_range(-30, 30)
		)
		SignalBus.publish("guy.spawn.particle", {
			"position": global_position + offset,
			"source_guy": self
		})
	
	# Drop any held thing
	if held_thing and is_instance_valid(held_thing):
		_drop_thing()
	
	# Despawn after brief delay for visual effect
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): _enter_state(State.INACTIVE))


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	if guy_type == null:
		return
	
	var draw_color = _base_color
	var draw_size = GUY_SIZE * _bounce_scale
	
	# Longing visual effect - pulsing opacity and color shift
	if is_longing:
		var pulse = sin(_pulse_timer * LONGING_PULSE_SPEED) * 0.5 + 0.5
		draw_color = draw_color.lerp(Color.RED, pulse * 0.5)
		draw_size *= 1.0 + pulse * 0.2
	
	# Draw body (simple rounded shape)
	var body_rect = Rect2(-Vector2(draw_size, draw_size) * 0.5, Vector2(draw_size, draw_size))
	
	# Main body
	draw_circle(Vector2.ZERO, draw_size * 0.5, draw_color)
	
	# Direction indicator (shows movement direction)
	if _current_velocity.length() > 10:
		var dir_indicator = _current_velocity.normalized() * draw_size * 0.3
		draw_circle(dir_indicator, draw_size * 0.15, draw_color.darkened(0.3))
	
	# Outline
	draw_arc(Vector2.ZERO, draw_size * 0.5, 0, TAU, 24, draw_color.darkened(0.4), 2.0, true)
	
	# Longing indicator (exclamation when upset)
	if is_longing and state == State.LONGING:
		var exclamation_pos = Vector2(0, -draw_size * 0.8)
		var font = ThemeDB.fallback_font
		draw_string(font, exclamation_pos, "!", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.YELLOW)
	
	# Carrying indicator
	if held_thing and is_instance_valid(held_thing):
		var carry_pos = Vector2(0, -draw_size * 0.6)
		draw_circle(carry_pos, 4, Color.WHITE)


# =============================================================================
# PUBLIC API
# =============================================================================
func get_state() -> State:
	return state


func get_patience_ratio() -> float:
	"""Returns 0.0 (just spawned) to 1.0 (about to tantrum)."""
	return clampf(patience_timer / PATIENCE_TANTRUM_THRESHOLD, 0.0, 1.0)


func is_carrying() -> bool:
	return held_thing != null and is_instance_valid(held_thing)