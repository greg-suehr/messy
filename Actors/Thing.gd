extends Area2D
class_name Thing
## Thing - A collectible resource that belongs in a Box
##
## Things are scattered by Guys and must be returned to matching Boxes
## by the player. Each Thing has a type that determines its color and shape.

# =============================================================================
# EXPORTS
# =============================================================================
@export var thing_type_id: String = "cyan_triangle"
@export var size: float = 24.0

# =============================================================================
# STATE
# =============================================================================
var thing_type: ThingTypes.ThingType
var is_in_box: bool = false
var is_held_by_player: bool = false
var is_held_by_guy: bool = false
var current_box: Node2D = null

# Visual
var _base_color: Color
var _pulse_tween: Tween


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_setup_type()
	_setup_collision()
	_setup_visuals()


func _setup_type() -> void:
	thing_type = ThingTypes.get_type(thing_type_id)
	if thing_type == null:
		push_error("Thing: Invalid type_id '%s'" % thing_type_id)
		thing_type = ThingTypes.get_type("cyan_triangle")
	
	_base_color = thing_type.color


func _setup_collision() -> void:
	collision_layer = 2  # things layer
	collision_mask = 0   # Things don't detect others
	
	# Add collision shape if not present
	if get_node_or_null("CollisionShape2D") == null:
		var shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = size * 0.5
		shape.shape = circle
		add_child(shape)


func _setup_visuals() -> void:
	queue_redraw()


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	if thing_type == null:
		return
	
	var vertices = ThingTypes.get_shape_vertices(thing_type.shape)
	var scaled_vertices: PackedVector2Array = []
	
	for v in vertices:
		scaled_vertices.append(v * size * 0.5)
	
	# Draw fill
	var fill_color = _base_color
	if is_held_by_player:
		fill_color = fill_color.lightened(0.3)
	elif is_held_by_guy:
		fill_color = fill_color.darkened(0.2)
	
	draw_colored_polygon(scaled_vertices, fill_color)
	
	# Draw outline
	var outline_color = fill_color.darkened(0.3)
	for i in range(scaled_vertices.size()):
		var from = scaled_vertices[i]
		var to = scaled_vertices[(i + 1) % scaled_vertices.size()]
		draw_line(from, to, outline_color, 2.0, true)


# =============================================================================
# STATE CHANGES
# =============================================================================
func pick_up_by_player() -> void:
	if is_held_by_guy:
		return
	
	is_held_by_player = true
	is_in_box = false
	
	if current_box:
		current_box = null
	
	# Disable collision while held
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	_start_held_pulse()
	queue_redraw()
	
	SignalBus.publish("thing.picked_up", {
		"thing": self,
		"by_player": true,
		"by_guy": null
	})


func pick_up_by_guy(guy: Node2D) -> void:
	if is_held_by_player:
		return
	
	is_held_by_guy = true
	is_in_box = false
	
	if current_box:
		current_box = null
	
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	queue_redraw()
	
	SignalBus.publish("thing.picked_up", {
		"thing": self,
		"by_player": false,
		"by_guy": guy
	})


func drop_at(pos: Vector2) -> void:
	global_position = pos
	is_held_by_player = false
	is_held_by_guy = false
	
	# Re-enable collision
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	
	_stop_held_pulse()
	queue_redraw()
	
	SignalBus.publish("thing.dropped", {
		"thing": self,
		"position": pos
	})


func place_in_box(box: Node2D) -> void:
	current_box = box
	is_in_box = true
	is_held_by_player = false
	is_held_by_guy = false
	
	# Position at box center
	global_position = box.global_position
	
	# Disable collision while in box
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	_stop_held_pulse()
	queue_redraw()
	
	SignalBus.publish("thing.returned", {
		"thing": self,
		"box": box
	})


func scatter_from_box(by_guy: Node2D, scatter_position: Vector2) -> void:
	var from_box = current_box
	current_box = null
	is_in_box = false
	
	global_position = scatter_position
	
	# Re-enable collision
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	
	queue_redraw()
	
	SignalBus.publish("thing.scattered", {
		"thing": self,
		"from_box": from_box,
		"by_guy": by_guy
	})


# =============================================================================
# VISUAL EFFECTS
# =============================================================================
func _start_held_pulse() -> void:
	_stop_held_pulse()
	
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.3)
	_pulse_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.3)


func _stop_held_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	scale = Vector2.ONE


# =============================================================================
# UTILITY
# =============================================================================
func matches_box(box: Node2D) -> bool:
	if box.has_method("get_thing_type_id"):
		return box.get_thing_type_id() == thing_type_id
	return false


func get_score_value() -> int:
	return thing_type.base_score if thing_type else GameState.POINTS_PER_THING_RETURNED