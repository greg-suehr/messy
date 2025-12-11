extends CanvasItem
class_name StackUI
## StackUI - Visual display of the player's Thing stack
##
## Displays the player's held Things as a "pancake stack" on the right side
## of the screen. Things are rendered with a perspective transform to look
## like they're stacked flat, viewed from the side.

# =============================================================================
# CONSTANTS
# =============================================================================
const STACK_MARGIN_RIGHT := 60  # Distance from right edge of screen
const STACK_MARGIN_BOTTOM := 100  # Distance from bottom of screen
const THING_SPACING := 18  # Vertical space between stacked things
const THING_WIDTH := 48.0  # Width of each thing representation
const THING_HEIGHT := 12.0  # Height when flattened (pancake effect)
const SQUISH_FACTOR := 0.25  # How much to squish vertically (0.25 = 25% of original height)

# Visual styling
const STACK_BG_COLOR := Color(0.1, 0.1, 0.15, 0.7)
const STACK_BORDER_COLOR := Color(0.3, 0.3, 0.4, 0.8)
const STACK_LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const HIGHLIGHT_TOP_COLOR := Color(1.0, 1.0, 0.5, 0.4)
const HIGHLIGHT_BOTTOM_COLOR := Color(0.5, 1.0, 1.0, 0.4)

# Animation
const PULSE_SPEED := 3.0
const BOUNCE_DURATION := 0.15
const BOUNCE_SCALE := 1.2

# =============================================================================
# STATE
# =============================================================================
var _stack_data: Array = []  # Array of {thing_type_id, color, shape}
var _viewport_size: Vector2 = Vector2(1280, 720)
var _pulse_timer: float = 0.0
var _bounce_indices: Dictionary = {}  # index -> remaining bounce time
var _is_visible: bool = false

# Control display
var _show_near_box_hint: bool = false
var _near_box_type_id: String = ""

# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_connect_signals()
	_update_viewport_size()


func _connect_signals() -> void:
	SignalBus.player_stack_changed.connect(_on_stack_changed)
	SignalBus.round_active_started.connect(_on_round_started)
	SignalBus.round_ended.connect(_on_round_ended)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_update_viewport_size()


func _update_viewport_size() -> void:
	_viewport_size = get_viewport().get_visible_rect().size


# =============================================================================
# PROCESS
# =============================================================================
func _process(delta: float) -> void:
	if not _is_visible:
		return
	
	_pulse_timer += delta * PULSE_SPEED
	if _pulse_timer > TAU:
		_pulse_timer -= TAU
	
	# Update bounce animations
	var indices_to_remove: Array = []
	for idx in _bounce_indices.keys():
		_bounce_indices[idx] -= delta
		if _bounce_indices[idx] <= 0:
			indices_to_remove.append(idx)
	for idx in indices_to_remove:
		_bounce_indices.erase(idx)
	
	queue_redraw()


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	if not _is_visible or _stack_data.is_empty():
		_draw_empty_stack_hint()
		return
	
	var base_pos = _get_stack_base_position()
	
	# Draw background panel
	_draw_stack_background(base_pos)
	
	# Draw each thing in the stack (bottom to top)
	for i in range(_stack_data.size()):
		var thing_data = _stack_data[i]
		var y_offset = -i * THING_SPACING
		var thing_pos = base_pos + Vector2(0, y_offset)
		
		# Check for bounce animation
		var scale = 1.0
		if _bounce_indices.has(i):
			var bounce_progress = _bounce_indices[i] / BOUNCE_DURATION
			scale = 1.0 + (BOUNCE_SCALE - 1.0) * bounce_progress
		
		_draw_stacked_thing(thing_pos, thing_data, i, scale)
	
	# Draw control hints
	_draw_control_hints(base_pos)
	
	# Draw stack count
	_draw_stack_count(base_pos)


func _draw_empty_stack_hint() -> void:
	if not _is_visible:
		return
	
	var base_pos = _get_stack_base_position()
	var hint_rect = Rect2(
		base_pos.x - THING_WIDTH * 0.5 - 10,
		base_pos.y - 40,
		THING_WIDTH + 20,
		50
	)
	
	# Subtle background
	var bg_color = STACK_BG_COLOR
	bg_color.a = 0.4
	draw_rect(hint_rect, bg_color)
	draw_rect(hint_rect, STACK_BORDER_COLOR, false, 1.0)
	
	# Empty hint text
	var font = ThemeDB.fallback_font
	var text = "[SPACE] Pick up"
	var text_pos = base_pos + Vector2(-30, -15)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, STACK_LABEL_COLOR)


func _draw_stack_background(base_pos: Vector2) -> void:
	var stack_height = _stack_data.size() * THING_SPACING + 30
	var bg_rect = Rect2(
		base_pos.x - THING_WIDTH * 0.5 - 15,
		base_pos.y - stack_height - 10,
		THING_WIDTH + 30,
		stack_height + 50
	)
	
	draw_rect(bg_rect, STACK_BG_COLOR)
	draw_rect(bg_rect, STACK_BORDER_COLOR, false, 2.0)


func _draw_stacked_thing(pos: Vector2, thing_data: Dictionary, index: int, scale: float = 1.0) -> void:
	"""Draw a single thing in the stack with pancake perspective."""
	var color: Color = thing_data.get("color", Color.WHITE)
	var shape: String = thing_data.get("shape", "square")
	
	# Get base vertices for the shape
	var vertices = ThingTypes.get_shape_vertices(shape)
	
	# Transform vertices for pancake effect (squish Y, keep X)
	var transformed: PackedVector2Array = []
	for v in vertices:
		var tv = Vector2(
			v.x * THING_WIDTH * 0.5 * scale,
			v.y * THING_WIDTH * 0.5 * SQUISH_FACTOR * scale
		)
		transformed.append(pos + tv)
	
	# Highlight for top/bottom of stack
	var is_top = (index == _stack_data.size() - 1)
	var is_bottom = (index == 0)
	
	# Draw shadow/depth effect (offset copy behind)
	var shadow_offset = Vector2(0, THING_HEIGHT * 0.3)
	var shadow_vertices: PackedVector2Array = []
	for tv in transformed:
		shadow_vertices.append(tv + shadow_offset)
	var shadow_color = color.darkened(0.5)
	shadow_color.a = 0.6
	draw_colored_polygon(shadow_vertices, shadow_color)
	
	# Draw main shape
	draw_colored_polygon(transformed, color)
	
	# Draw outline
	var outline_color = color.darkened(0.3)
	for i in range(transformed.size()):
		var from = transformed[i]
		var to = transformed[(i + 1) % transformed.size()]
		draw_line(from, to, outline_color, 2.0, true)
	
	# Draw highlight indicator for top/bottom
	if is_top:
		var pulse = sin(_pulse_timer) * 0.3 + 0.7
		var highlight = HIGHLIGHT_TOP_COLOR
		highlight.a *= pulse
		var indicator_pos = pos + Vector2(THING_WIDTH * 0.4, 0)
		draw_circle(indicator_pos, 4, highlight)
		
	if is_bottom and _stack_data.size() > 1:
		var pulse = cos(_pulse_timer) * 0.3 + 0.7
		var highlight = HIGHLIGHT_BOTTOM_COLOR
		highlight.a *= pulse
		var indicator_pos = pos + Vector2(-THING_WIDTH * 0.4, 0)
		draw_circle(indicator_pos, 4, highlight)


func _draw_control_hints(base_pos: Vector2) -> void:
	"""Draw the E/Q control hints."""
	var font = ThemeDB.fallback_font
	var hint_y = base_pos.y + 25
	
	if _stack_data.is_empty():
		return
	
	# Top hint (E key)
	var top_hint = "[E] Drop Top"
	var top_color = STACK_LABEL_COLOR
	if _show_near_box_hint:
		top_color = Color.GREEN.lightened(0.3)
	draw_string(font, Vector2(base_pos.x - 35, hint_y), top_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, top_color)
	
	# Bottom hint (Q key) - only show if stack has more than 1
	if _stack_data.size() > 1:
		var bottom_hint = "[Q] Drop Bottom"
		var bottom_color = STACK_LABEL_COLOR
		if _show_near_box_hint:
			bottom_color = Color.CYAN.lightened(0.3)
		draw_string(font, Vector2(base_pos.x - 40, hint_y + 14), bottom_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, bottom_color)
	
	# Near box indicator
	if _show_near_box_hint and not _near_box_type_id.is_empty():
		var box_hint = "Near Box!"
		draw_string(font, Vector2(base_pos.x - 25, hint_y + 30), box_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.YELLOW)


func _draw_stack_count(base_pos: Vector2) -> void:
	"""Draw the stack count indicator."""
	var font = ThemeDB.fallback_font
	var count_text = "%d/%d" % [_stack_data.size(), PlayerController.MAX_STACK_SIZE]
	var count_pos = Vector2(base_pos.x - 15, base_pos.y - (_stack_data.size() * THING_SPACING) - 20)
	
	var count_color = STACK_LABEL_COLOR
	if _stack_data.size() >= PlayerController.MAX_STACK_SIZE:
		count_color = Color.ORANGE
	
	draw_string(font, count_pos, count_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, count_color)


func _get_stack_base_position() -> Vector2:
	"""Get the base position for the stack (bottom-right of screen)."""
	return Vector2(
		_viewport_size.x - STACK_MARGIN_RIGHT,
		_viewport_size.y - STACK_MARGIN_BOTTOM
	)


# =============================================================================
# PUBLIC API
# =============================================================================
func set_near_box_hint(is_near: bool, box_type_id: String = "") -> void:
	"""Called by PlayerController to show/hide the near-box hint."""
	_show_near_box_hint = is_near
	_near_box_type_id = box_type_id
	queue_redraw()


func trigger_bounce(index: int) -> void:
	"""Trigger a bounce animation on a specific stack item."""
	_bounce_indices[index] = BOUNCE_DURATION


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_stack_changed(stack: Array) -> void:
	"""Update the visual stack when the player's stack changes."""
	var old_size = _stack_data.size()
	_stack_data.clear()
	
	for thing in stack:
		if is_instance_valid(thing) and thing is Thing:
			var thing_type = ThingTypes.get_type(thing.thing_type_id)
			if thing_type:
				_stack_data.append({
					"thing_type_id": thing.thing_type_id,
					"color": thing_type.color,
					"shape": thing_type.shape
				})
	
	# Trigger bounce on new items
	if _stack_data.size() > old_size:
		trigger_bounce(_stack_data.size() - 1)
	
	queue_redraw()


func _on_round_started(_round_number: int) -> void:
	_is_visible = true
	_stack_data.clear()
	queue_redraw()


func _on_round_ended(_round_number: int, _result: String) -> void:
	_is_visible = false
	queue_redraw()
