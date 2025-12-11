extends CharacterBody2D
class_name OldGuy
## Guy - A chaos agent that takes Things from Boxes and scatters them
##
## Guys spawn, navigate to a target Box, take a Thing, drop it somewhere
## on the board, then leave. If they can't find their Thing, they have a Tantrum.
##
## VISUAL STYLE: Abstract geometric entities - no faces, no cuteness.
## Angular, glitchy, aggressive. Think digital parasites.

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

# Visual - HARDENED
var _base_color: Color
var _glitch_offset: Vector2 = Vector2.ZERO
var _scale_pulse: float = 1.0
var _rotation_offset: float = 0.0
var _distortion_phase: float = 0.0
var _spike_count: int = 5
var _inner_rotation: float = 0.0


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_setup_type()
	_setup_collision()
	_spike_count = randi_range(4, 7)  # Each guy gets random spike count
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
			_spawn_timer = 0.3  # Faster, more aggressive spawn
			_scale_pulse = 0.0
		
		State.SEEKING_BOX:
			if target_box:
				_move_target = target_box.global_position
				SignalBus.publish("guy.targeting", {
					"guy": self,
					"box": target_box
				})
		
		State.AT_BOX:
			_action_delay = 0.3  # Quick grab
			SignalBus.publish("guy.reached_box", {
				"guy": self,
				"box": target_box
			})
		
		State.CARRYING:
			_action_delay = 0.2
			_move_target = _get_random_board_position()
		
		State.DROPPING:
			_action_delay = 0.2
		
		State.LONGING:
			_longing_timer = guy_type.longing_duration
			SignalBus.publish("guy.longing", {
				"guy": self,
				"duration": _longing_timer
			})
		
		State.TANTRUM:
			_tantrum_timer = 0.4
			SignalBus.publish("guy.tantrum", {"guy": self})
			SignalBus.publish("ui.shake", {"intensity": 0.7, "duration": 0.4})
			SignalBus.publish("audio.sfx", {"sfx_id": "tantrum", "position": global_position})
		
		State.LEAVING:
			_move_target = _exit_position
			SignalBus.publish("guy.left", {"guy": self})
		
		State.DESPAWNED:
			SignalBus.publish("guy.despawned", {"guy": self})
			queue_free()
	
	queue_redraw()


func _process_state(delta: float) -> void:
	# Update visual distortion continuously
	_distortion_phase += delta * 8.0
	_inner_rotation += delta * 2.0
	
	match state:
		State.SPAWNING:
			_spawn_timer -= delta
			_scale_pulse = lerpf(_scale_pulse, 1.0, delta * 6.0)
			_rotation_offset = sin(_distortion_phase * 3.0) * 0.3
			if _spawn_timer <= 0:
				_enter_state(State.SEEKING_BOX)
		
		State.SEEKING_BOX:
			_move_toward_target(delta)
			_rotation_offset = sin(_distortion_phase) * 0.1
			if global_position.distance_to(_move_target) < 16:
				_enter_state(State.AT_BOX)
		
		State.AT_BOX:
			_action_delay -= delta
			_scale_pulse = 1.0 + sin(_distortion_phase * 4.0) * 0.1
			if _action_delay <= 0:
				_try_take_thing()
		
		State.CARRYING:
			_move_toward_target(delta)
			_rotation_offset = sin(_distortion_phase * 1.5) * 0.15
			if global_position.distance_to(_move_target) < 16:
				_enter_state(State.DROPPING)
		
		State.DROPPING:
			_action_delay -= delta
			if _action_delay <= 0:
				_drop_thing()
		
		State.LONGING:
			_longing_timer -= delta
			# Aggressive glitch effect - digital corruption
			_glitch_offset = Vector2(
				randf_range(-4, 4) if randf() > 0.7 else 0,
				randf_range(-4, 4) if randf() > 0.7 else 0
			)
			_rotation_offset = sin(_distortion_phase * 6.0) * 0.4
			_scale_pulse = 1.0 + sin(_distortion_phase * 3.0) * 0.15
			if _longing_timer <= 0:
				_enter_state(State.TANTRUM)
		
		State.TANTRUM:
			_tantrum_timer -= delta
			# Maximum glitch during tantrum
			_glitch_offset = Vector2(randf_range(-8, 8), randf_range(-8, 8))
			_rotation_offset = randf_range(-0.5, 0.5)
			_scale_pulse = randf_range(0.8, 1.4)
			if _tantrum_timer <= 0:
				_spawn_chaos_particles()
				_enter_state(State.DESPAWNED)
		
		State.LEAVING:
			_move_toward_target(delta)
			_rotation_offset *= 0.95  # Calm down as leaving
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
	
	if carried_thing:
		carried_thing.global_position = global_position + Vector2(0, -size * 0.5)


func _get_random_board_position() -> Vector2:
	var board_size = GameState.param_board_size * 32
	var _center = Vector2(board_size) * 0.5
	
	return Vector2(
		randf_range(64, board_size.x - 64),
		randf_range(64, board_size.y - 64)
	)


# =============================================================================
# DRAWING - HARDENED VISUALS
# =============================================================================
func _draw() -> void:
	if guy_type == null:
		return
	
	var draw_scale = _scale_pulse
	var base_radius = size * 0.5 * draw_scale
	
	# Apply glitch offset
	var center = _glitch_offset
	
	# === CORE SHAPE: Spiky angular form, no face ===
	var body_color = _base_color
	var core_color = _base_color.darkened(0.4)
	var accent_color = _base_color.lightened(0.2)
	
	# State-based color modifications
	match state:
		State.TANTRUM:
			# Strobe between colors
			if fmod(_distortion_phase, 0.2) < 0.1:
				body_color = Color.WHITE
				accent_color = _base_color
			else:
				body_color = _base_color.lightened(0.4)
		State.LONGING:
			# Desaturated, unstable
			body_color = body_color.lerp(Color(0.3, 0.3, 0.3), 0.4)
			core_color = core_color.lerp(Color(0.2, 0.2, 0.2), 0.4)
		State.SPAWNING:
			body_color.a = _scale_pulse
			core_color.a = _scale_pulse
	
	# === Draw outer spiky shell ===
	var outer_points: PackedVector2Array = []
	for i in range(_spike_count * 2):
		var angle = (float(i) / float(_spike_count * 2)) * TAU + _rotation_offset
		var radius = base_radius if i % 2 == 0 else base_radius * 0.5
		# Add slight irregularity
		if state == State.LONGING or state == State.TANTRUM:
			radius += randf_range(-3, 3)
		outer_points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	
	draw_colored_polygon(outer_points, body_color)
	
	# === Draw inner rotating core ===
	var inner_radius = base_radius * 0.35
	var inner_points: PackedVector2Array = []
	var inner_spike_count = 4
	for i in range(inner_spike_count * 2):
		var angle = (float(i) / float(inner_spike_count * 2)) * TAU + _inner_rotation
		var radius = inner_radius if i % 2 == 0 else inner_radius * 0.4
		inner_points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	
	draw_colored_polygon(inner_points, core_color)
	
	# === Draw harsh outline ===
	for i in range(outer_points.size()):
		var from = outer_points[i]
		var to = outer_points[(i + 1) % outer_points.size()]
		var line_color = accent_color if i % 2 == 0 else body_color.darkened(0.3)
		draw_line(from, to, line_color, 2.0, true)
	
	# === State indicators (no faces!) ===
	match state:
		State.LONGING:
			# Draw unstable scan lines
			for j in range(3):
				var y_offset = center.y - base_radius + (j * base_radius * 0.7)
				var line_alpha = 0.3 + sin(_distortion_phase + j) * 0.2
				var scan_color = Color(1, 1, 1, line_alpha)
				draw_line(
					center + Vector2(-base_radius, y_offset),
					center + Vector2(base_radius, y_offset),
					scan_color, 1.0
				)
		
		State.TANTRUM:
			# Draw glitch rectangles
			for j in range(4):
				var rect_offset = Vector2(randf_range(-base_radius, base_radius), randf_range(-base_radius, base_radius))
				var rect_size = Vector2(randf_range(4, 12), randf_range(2, 6))
				var rect_color = [Color.WHITE, _base_color, Color.BLACK][randi() % 3]
				rect_color.a = 0.7
				draw_rect(Rect2(center + rect_offset, rect_size), rect_color)
		
		State.CARRYING:
			# Pulsing energy ring
			var ring_radius = base_radius * 1.2 + sin(_distortion_phase * 2) * 4
			draw_arc(center, ring_radius, 0, TAU, 16, accent_color, 1.5, true)
	
	# === Draw direction indicator (angular, not cute) ===
	if _move_target != Vector2.ZERO and state in [State.SEEKING_BOX, State.CARRYING, State.LEAVING]:
		var dir = global_position.direction_to(_move_target)
		var indicator_base = center + dir * base_radius * 0.8
		var indicator_tip = center + dir * base_radius * 1.3
		var perp = dir.rotated(PI / 2) * 4
		
		# Draw arrow head
		draw_line(indicator_base - perp, indicator_tip, accent_color, 2.0)
		draw_line(indicator_base + perp, indicator_tip, accent_color, 2.0)


# =============================================================================
# UTILITY
# =============================================================================
func is_active() -> bool:
	return state not in [State.DESPAWNED, State.TANTRUM]


func can_be_interrupted() -> bool:
	return state in [State.SEEKING_BOX, State.AT_BOX, State.LONGING]
