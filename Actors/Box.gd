extends Area2D
class_name Box
## Box - A container that holds Things of a specific type
##
## Boxes are positioned on the edges of the game board. Guys target them
## to take Things, and the player must return scattered Things to matching Boxes.

# =============================================================================
# EXPORTS
# =============================================================================
@export var thing_type_id: String = "cyan_triangle"
@export var size: Vector2 = Vector2(48, 48)

# =============================================================================
# STATE
# =============================================================================
var thing_type: ThingTypes.ThingType
var things_inside: Array[Thing] = []
var is_empty: bool = true
var was_emptied_this_round: bool = false

# Visual
var _base_color: Color
var _glow_intensity: float = 0.0


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_setup_type()
	_setup_collision()
	_setup_visuals()
	_connect_signals()


func _setup_type() -> void:
	thing_type = ThingTypes.get_type(thing_type_id)
	if thing_type == null:
		push_error("Box: Invalid thing_type_id '%s'" % thing_type_id)
		thing_type = ThingTypes.get_type("cyan_triangle")
	
	_base_color = thing_type.color


func _setup_collision() -> void:
	collision_layer = 4  # boxes layer
	collision_mask = 2   # Detect things
	
	# Add collision shape if not present
	if get_node_or_null("CollisionShape2D") == null:
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		add_child(shape)


func _setup_visuals() -> void:
	queue_redraw()


func _connect_signals() -> void:
	area_entered.connect(_on_area_entered)


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	if thing_type == null:
		return
	
	var half_size = size * 0.5
	var rect = Rect2(-half_size, size)
	
	# Background fill - dim when empty, bright when stocked
	var bg_color = _base_color
	if is_empty:
		bg_color = bg_color.darkened(0.6)
		bg_color.a = 0.5
	else:
		bg_color = bg_color.darkened(0.3)
		bg_color.a = 0.8
	
	# Glow effect when receiving things
	if _glow_intensity > 0:
		var glow_color = _base_color.lightened(0.5)
		glow_color.a = _glow_intensity * 0.5
		draw_rect(rect.grow(4), glow_color)
	
	draw_rect(rect, bg_color)
	
	# Border
	var border_color = _base_color if not is_empty else _base_color.darkened(0.4)
	draw_rect(rect, border_color, false, 3.0)
	
	# Draw thing type symbol in center
	var symbol_size = min(size.x, size.y) * 0.4
	var vertices = ThingTypes.get_shape_vertices(thing_type.shape)
	var scaled_vertices: PackedVector2Array = []
	
	for v in vertices:
		scaled_vertices.append(v * symbol_size * 0.5)
	
	var symbol_color = _base_color
	if is_empty:
		symbol_color.a = 0.3
	
	draw_colored_polygon(scaled_vertices, symbol_color)
	
	# Count indicator (small number in corner)
	if things_inside.size() > 0:
		var font = ThemeDB.fallback_font
		var count_text = str(things_inside.size())
		var text_pos = half_size - Vector2(12, 8)
		draw_string(font, text_pos, count_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color.WHITE)


# =============================================================================
# THING MANAGEMENT
# =============================================================================
func add_thing(thing: Thing) -> void:
	if thing in things_inside:
		return
	
	things_inside.append(thing)
	thing.place_in_box(self)
	
	var was_empty = is_empty
	is_empty = false
	
	# Trigger restock event if was empty
	if was_empty:
		SignalBus.publish("box.restocked", {"box": self})
	
	SignalBus.publish("box.thing.added", {
		"box": self,
		"thing": thing,
		"count": things_inside.size()
	})
	
	# Visual feedback
	_flash_glow()
	queue_redraw()
	
	# Audio feedback
	SignalBus.publish("audio.sfx", {
		"sfx_id": "box_drop",
		"position": global_position
	})


func remove_thing(by_guy: Node2D = null) -> Thing:
	if things_inside.is_empty():
		return null
	
	var thing = things_inside.pop_back()
	
	# Calculate scatter position (random offset from box)
	var scatter_offset = Vector2(
		randf_range(-80, 80),
		randf_range(-80, 80)
	)
	var scatter_pos = global_position + scatter_offset
	
	thing.scatter_from_box(by_guy, scatter_pos)
	
	SignalBus.publish("box.thing.removed", {
		"box": self,
		"thing": thing,
		"count": things_inside.size()
	})
	
	# Check if now empty
	if things_inside.is_empty():
		is_empty = true
		was_emptied_this_round = true
		SignalBus.publish("box.emptied", {"box": self})
	
	queue_redraw()
	return thing


func has_things() -> bool:
	return not things_inside.is_empty()


func get_thing_count() -> int:
	return things_inside.size()


func get_thing_type_id() -> String:
	return thing_type_id


# =============================================================================
# COLLISION DETECTION
# =============================================================================
func _on_area_entered(area: Area2D) -> void:
	# Auto-collect things dropped nearby (only if they match)
	if area is Thing:
		var thing = area as Thing
		if thing.matches_box(self) and not thing.is_held_by_player and not thing.is_held_by_guy:
			# Thing was dropped near box - auto-collect
			add_thing(thing)


# =============================================================================
# VISUAL EFFECTS
# =============================================================================
func _flash_glow() -> void:
	var tween = create_tween()
	tween.tween_property(self, "_glow_intensity", 1.0, 0.1)
	tween.tween_property(self, "_glow_intensity", 0.0, 0.3)
	tween.tween_callback(queue_redraw)


func _process(_delta: float) -> void:
	# Redraw during glow animation
	if _glow_intensity > 0:
		queue_redraw()


# =============================================================================
# ROUND MANAGEMENT
# =============================================================================
func reset_for_round() -> void:
	was_emptied_this_round = false


func spawn_initial_things(count: int, thing_scene: PackedScene) -> void:
	"""Spawn initial things in this box at round start."""
	for i in range(count):
		var thing = thing_scene.instantiate() as Thing
		thing.thing_type_id = thing_type_id
		get_parent().add_child(thing)
		add_thing(thing)