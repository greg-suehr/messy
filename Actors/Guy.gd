extends CharacterBody2D
class_name Guy
## Guy - A chaos agent that takes Things from Boxes and scatters them
##
## Guys spawn, navigate to a target Box, take a Thing, drop it somewhere
## on the board, then leave. If they can't find their Thing, they have a Tantrum.

# =============================================================================
# EXPORTS
# =============================================================================
@export var guy_type_id: String = "normal"
@export var size: float = 32.0

# =============================================================================
# STATE MACHINE
# =============================================================================
enum State {
	SPAWNING,
	SEEKING_BOX,
	AT_BOX,
	CARRYING,
	DROPPING,
	LONGING,
	TANTRUM,
	LEAVING,
	DESPAWNED
}

var state: State = State.SPAWNING

# =============================================================================
# STATE
# =============================================================================
var guy_type: GuyTypes.GuyType
var target_box: Box = null
var carried_thing: Thing = null
var preferred_thing_type: String = ""

# Timers
var _longing_timer: float = 0.0
var _tantrum_timer: float = 0.0
var _spawn_timer: float = 0.0
var _action_delay: float = 0.0

# Movement
var _move_target: Vector2 = Vector2.ZERO
var _exit_position: Vector2 = Vector2.ZERO

# Visual
var _base_color: Color
var _wobble_offset: float = 0.0
var _scale_pulse: float = 1.0


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_setup_type()
	_setup_collision()
	_enter_state(State.SPAWNING)


func _setup_type() -> void:
	guy_type = GuyTypes.get_type(guy_type_id)
	if guy_type == null:
		push_error("Guy: Invalid type_id '%s'" % guy_type_id)
		guy_type = GuyTypes.get_type("normal")
	
	_base_color = guy_type.color


func _setup_collision() -> void:
	collision_layer = 8  # guys layer
	collision_mask = 16  # walls layer
	
	# Add collision shape if not present
	if get_node_or_null("CollisionShape2D") == null:
		var shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = size * 0.4
		shape.shape = circle
		add_child(shape)


# =============================================================================
# SETUP
# =============================================================================
func initialize(thing_type_id: String, box: Box, exit_pos: Vector2) -> void:
	"""Set up this Guy with a target Thing type and Box."""
	preferred_thing_type = thing_type_id
	target_box = box
	_exit_position = exit_pos
	_move_target = box.global_position
	
	SignalBus.publish("guy.spawned", {
		"guy": self,
		"guy_type_id": guy_type_id
	})


# =============================================================================
# STATE MACHINE
# =============================================================================
func _enter_state(new_state: State) -> void:
	state = new_state
	
	match state:
		State.SPAWNING:
			_spawn_timer = 0.5  # Brief spawn animation
			_scale_pulse = 0.0
		
		State.SEEKING_BOX:
			if target_box:
				_move_target = target_box.global_position
				SignalBus.publish("guy.targeting", {
					"guy": self,
					"box": target_box
				})
		
		State.AT_BOX:
			_action_delay = 0.5  # Brief pause before taking thing
			SignalBus.publish("guy.reached_box", {
				"guy": self,
				"box": target_box
			})
		
		State.CARRYING:
			_action_delay = 0.3
			# Pick random drop position
			_move_target = _get_random_board_position()
		
		State.DROPPING:
			_action_delay = 0.3
		
		State.LONGING:
			_longing_timer = guy_type.longing_duration
			SignalBus.publish("guy.longing", {
				"guy": self,
				"duration": _longing_timer
			})
		
		State.TANTRUM:
			_tantrum_timer = 0.5
			SignalBus.publish("guy.tantrum", {"guy": self})
			SignalBus.publish("ui.shake", {"intensity": 0.5, "duration": 0.3})
			SignalBus.publish("audio.sfx", {"sfx_id": "tantrum", "position": global_position})
		
		State.LEAVING:
			_move_target = _exit_position
			SignalBus.publish("guy.left", {"guy": self})
		
		State.DESPAWNED:
			SignalBus.publish("guy.despawned", {"guy": self})
			queue_free()
	
	queue_redraw()


func _process_state(delta: float) -> void:
	match state:
		State.SPAWNING:
			_spawn_timer -= delta
			_scale_pulse = lerpf(_scale_pulse, 1.0, delta * 4.0)
			if _spawn_timer <= 0:
				_enter_state(State.SEEKING_BOX)
		
		State.SEEKING_BOX:
			_move_toward_target(delta)
			if global_position.distance_to(_move_target) < 16:
				_enter_state(State.AT_BOX)
		
		State.AT_BOX:
			_action_delay -= delta
			if _action_delay <= 0:
				_try_take_thing()
		
		State.CARRYING:
			_move_toward_target(delta)
			if global_position.distance_to(_move_target) < 16:
				_enter_state(State.DROPPING)
		
		State.DROPPING:
			_action_delay -= delta
			if _action_delay <= 0:
				_drop_thing()
		
		State.LONGING:
			_longing_timer -= delta
			# Pacing animation
			_wobble_offset = sin(Time.get_ticks_msec() * 0.01) * 8
			if _longing_timer <= 0:
				_enter_state(State.TANTRUM)
		
		State.TANTRUM:
			_tantrum_timer -= delta
			if _tantrum_timer <= 0:
				_spawn_chaos_particles()
				_enter_state(State.DESPAWNED)
		
		State.LEAVING:
			_move_toward_target(delta)
			if global_position.distance_to(_move_target) < 16:
				_enter_state(State.DESPAWNED)


func _physics_process(delta: float) -> void:
	_process_state(delta)
	queue_redraw()


# =============================================================================
# ACTIONS
# =============================================================================
func _try_take_thing() -> void:
	if target_box == null:
		_enter_state(State.LONGING)
		return
	
	if target_box.has_things():
		var thing = target_box.remove_thing(self)
		if thing:
			carried_thing = thing
			thing.pick_up_by_guy(self)
			
			SignalBus.publish("guy.took_thing", {
				"guy": self,
				"thing": thing,
				"box": target_box
			})
			
			_enter_state(State.CARRYING)
			return
	
	# Box is empty - enter longing state
	_enter_state(State.LONGING)


func _drop_thing() -> void:
	if carried_thing:
		var drop_pos = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		carried_thing.drop_at(drop_pos)
		
		SignalBus.publish("guy.dropped_thing", {
			"guy": self,
			"thing": carried_thing,
			"position": drop_pos
		})
		
		carried_thing = null
	
	_enter_state(State.LEAVING)


func _spawn_chaos_particles() -> void:
	var particle_count = guy_type.tantrum_particles
	
	for i in range(particle_count):
		# Emit signal for particle spawning (handled by a particle system)
		var angle = randf() * TAU
		var distance = randf_range(30, 80)
		var particle_pos = global_position + Vector2(cos(angle), sin(angle)) * distance
		
		SignalBus.publish("guy.spawn.particle", {
			"source_guy": self,
			"position": particle_pos
		})


# =============================================================================
# MOVEMENT
# =============================================================================
func _move_toward_target(_delta: float) -> void:
	var direction = global_position.direction_to(_move_target)
	velocity = direction * guy_type.move_speed
	move_and_slide()
	
	# Update carried thing position
	if carried_thing:
		carried_thing.global_position = global_position + Vector2(0, -size * 0.5)


func _get_random_board_position() -> Vector2:
	# Get board bounds from GameState
	var board_size = GameState.param_board_size * 32  # Assuming 32px tiles
	var _center = Vector2(board_size) * 0.5
	
	return Vector2(
		randf_range(64, board_size.x - 64),
		randf_range(64, board_size.y - 64)
	)


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	if guy_type == null:
		return
	
	var draw_scale = _scale_pulse
	var base_size = size * 0.5 * draw_scale
	
	# Wobble offset for longing state
	var wobble = Vector2(_wobble_offset, 0) if state == State.LONGING else Vector2.ZERO
	
	# Main body (rounded blob)
	var body_color = _base_color
	if state == State.TANTRUM:
		body_color = body_color.lightened(sin(Time.get_ticks_msec() * 0.05) * 0.3)
	elif state == State.LONGING:
		body_color = body_color.darkened(0.2)
	
	# Draw body as circle
	draw_circle(wobble, base_size, body_color)
	
	# Draw outline
	var outline_color = body_color.darkened(0.3)
	draw_arc(wobble, base_size, 0, TAU, 32, outline_color, 2.0, true)
	
	# Eyes
	var eye_offset = base_size * 0.3
	var eye_size = base_size * 0.2
	var eye_color = Color.WHITE
	
	if state == State.TANTRUM:
		# X eyes for tantrum
		var x_size = eye_size * 0.7
		draw_line(wobble + Vector2(-eye_offset - x_size, -x_size), wobble + Vector2(-eye_offset + x_size, x_size), Color.BLACK, 2.0)
		draw_line(wobble + Vector2(-eye_offset - x_size, x_size), wobble + Vector2(-eye_offset + x_size, -x_size), Color.BLACK, 2.0)
		draw_line(wobble + Vector2(eye_offset - x_size, -x_size), wobble + Vector2(eye_offset + x_size, x_size), Color.BLACK, 2.0)
		draw_line(wobble + Vector2(eye_offset - x_size, x_size), wobble + Vector2(eye_offset + x_size, -x_size), Color.BLACK, 2.0)
	else:
		# Normal eyes
		draw_circle(wobble + Vector2(-eye_offset, -eye_size), eye_size, eye_color)
		draw_circle(wobble + Vector2(eye_offset, -eye_size), eye_size, eye_color)
		
		# Pupils - look toward target
		var look_dir = Vector2.ZERO
		if _move_target != Vector2.ZERO:
			look_dir = global_position.direction_to(_move_target) * eye_size * 0.4
		
		draw_circle(wobble + Vector2(-eye_offset, -eye_size) + look_dir, eye_size * 0.5, Color.BLACK)
		draw_circle(wobble + Vector2(eye_offset, -eye_size) + look_dir, eye_size * 0.5, Color.BLACK)
	
	# Mouth
	if state == State.LONGING:
		# Wavy worried mouth
		var mouth_y = base_size * 0.3
		draw_arc(wobble + Vector2(0, mouth_y), base_size * 0.3, PI * 0.2, PI * 0.8, 8, Color.BLACK, 2.0)
	elif state == State.TANTRUM:
		# Open scream
		draw_circle(wobble + Vector2(0, base_size * 0.2), base_size * 0.25, Color.BLACK)
	else:
		# Happy smile
		var mouth_y = base_size * 0.2
		draw_arc(wobble + Vector2(0, mouth_y), base_size * 0.3, 0, PI, 8, Color.BLACK, 2.0)


# =============================================================================
# UTILITY
# =============================================================================
func is_active() -> bool:
	return state not in [State.DESPAWNED, State.TANTRUM]


func can_be_interrupted() -> bool:
	return state in [State.SEEKING_BOX, State.AT_BOX, State.LONGING]
