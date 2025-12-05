extends CanvasLayer
class_name GameHUD
## GameHUD - In-game overlay during active rounds
##
## Shows timer (fading), stack indicator, and pop-up notifications
## for game events. Implements the "bubblegum hyperpop chaos" visual style.

# =============================================================================
# CONSTANTS
# =============================================================================
const TIMER_FADE_DURATION := 5.0
const POPUP_DURATION := 1.5
const POPUP_RISE_SPEED := 30.0

const COLOR_WARNING := Color("#FF6B6B")
const COLOR_SUCCESS := Color("#7FFF00")
const COLOR_INFO := Color("#00FFFF")

# =============================================================================
# STATE
# =============================================================================
var _timer_alpha: float = 1.0
var _timer_fade_active: bool = false
var _time_remaining: float = 0.0
var _time_total: float = 0.0
var _current_stack_size: int = 0
var _current_multiplier: float = 1.0

# =============================================================================
# UI NODES
# =============================================================================
var _root_control: Control
var _timer_label: Label
var _stack_container: HBoxContainer
var _multiplier_label: Label
var _popup_container: Control


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_create_ui()
	_connect_signals()
	visible = false


func _create_ui() -> void:
	"""Create the HUD UI elements dynamically."""
	# Root control
	_root_control = Control.new()
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_control)
	
	# Timer label (top center, fades after a few seconds)
	_timer_label = Label.new()
	_timer_label.text = "2:00"
	_timer_label.add_theme_font_size_override("font_size", 32)
	_timer_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.offset_top = 20
	_timer_label.offset_left = -50
	_timer_label.offset_right = 50
	_root_control.add_child(_timer_label)
	
	# Stack indicator (bottom center)
	_stack_container = HBoxContainer.new()
	_stack_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stack_container.offset_bottom = -20
	_stack_container.offset_left = -100
	_stack_container.offset_right = 100
	_stack_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_stack_container.add_theme_constant_override("separation", 5)
	_root_control.add_child(_stack_container)
	
	# Multiplier label (top right)
	_multiplier_label = Label.new()
	_multiplier_label.text = "x1.0"
	_multiplier_label.add_theme_font_size_override("font_size", 24)
	_multiplier_label.add_theme_color_override("font_color", Color("#7FFF00"))
	_multiplier_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_multiplier_label.offset_top = 20
	_multiplier_label.offset_right = -20
	_multiplier_label.offset_left = -80
	_multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root_control.add_child(_multiplier_label)
	
	# Popup container (for floating text)
	_popup_container = Control.new()
	_popup_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(_popup_container)


func _connect_signals() -> void:
	SignalBus.round_active_started.connect(_on_round_started)
	SignalBus.round_ended.connect(_on_round_ended)
	SignalBus.round_timer_tick.connect(_on_timer_tick)
	SignalBus.player_stack_changed.connect(_on_stack_changed)
	SignalBus.score_multiplier_changed.connect(_on_multiplier_changed)
	SignalBus.ui_popup_requested.connect(_on_popup_requested)
	SignalBus.box_emptied.connect(_on_box_emptied)
	SignalBus.guy_entered_tantrum.connect(_on_guy_tantrum)


# =============================================================================
# UPDATE
# =============================================================================
func _process(delta: float) -> void:
	if not visible:
		return
	
	# Handle timer fading
	if _timer_fade_active and _timer_alpha > 0:
		_timer_alpha = maxf(0, _timer_alpha - delta / 3.0)
		_timer_label.modulate.a = _timer_alpha


# =============================================================================
# DISPLAY UPDATES
# =============================================================================
func _update_timer_display() -> void:
	@warning_ignore("integer_division")
	var minutes = int(_time_remaining) / 60
	var seconds = int(_time_remaining) % 60
	_timer_label.text = "%d:%02d" % [minutes, seconds]
	
	# Color based on time remaining
	if _time_remaining < 10:
		_timer_label.add_theme_color_override("font_color", COLOR_WARNING)
	elif _time_remaining < 30:
		_timer_label.add_theme_color_override("font_color", Color("#FFFF00"))
	else:
		_timer_label.add_theme_color_override("font_color", Color("#FFFFFF"))


func _update_stack_display(stack: Array) -> void:
	# Clear existing
	for child in _stack_container.get_children():
		child.queue_free()
	
	_current_stack_size = stack.size()
	
	# Show stack slots (max 5)
	for i in range(5):
		var slot = ColorRect.new()
		slot.custom_minimum_size = Vector2(24, 24)
		
		if i < stack.size():
			# Filled slot - get color from thing
			var thing = stack[i]
			if is_instance_valid(thing) and thing.thing_type:
				slot.color = thing.thing_type.color
			else:
				slot.color = Color("#FFFFFF")
		else:
			# Empty slot
			slot.color = Color(0.3, 0.3, 0.3, 0.5)
		
		_stack_container.add_child(slot)


func _update_multiplier_display() -> void:
	_multiplier_label.text = "x%.1f" % _current_multiplier
	
	if _current_multiplier >= 1.5:
		_multiplier_label.add_theme_color_override("font_color", COLOR_SUCCESS)
	elif _current_multiplier >= 1.0:
		_multiplier_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	else:
		_multiplier_label.add_theme_color_override("font_color", COLOR_WARNING)


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_round_started(_round_number: int) -> void:
	visible = true
	_timer_alpha = 1.0
	_timer_fade_active = false
	_timer_label.modulate.a = 1.0
	_update_stack_display([])


func _on_round_ended(_round_number: int, _result: String) -> void:
	visible = false


func _on_timer_tick(time_remaining: float, time_total: float) -> void:
	_time_remaining = time_remaining
	_time_total = time_total
	_update_timer_display()
	
	# Start fading timer after initial period
	if time_remaining < time_total - TIMER_FADE_DURATION and not _timer_fade_active:
		_timer_fade_active = true


func _on_stack_changed(stack: Array) -> void:
	_update_stack_display(stack)


func _on_multiplier_changed(_old_value: float, new_value: float) -> void:
	_current_multiplier = new_value
	_update_multiplier_display()


func _on_popup_requested(message: String, position: Vector2, type: String) -> void:
	var color = COLOR_INFO
	match type:
		"warning": color = COLOR_WARNING
		"success": color = COLOR_SUCCESS
	
	# Convert world position to screen position
	var screen_pos = position
	var camera = get_viewport().get_camera_2d()
	
	# TODO: fix (Vector2 vs Vector2i) typing issues, clear up camera system
	# if camera:
	#	screen_pos = (position - camera.get_screen_center_position()) * camera.zoom + get_viewport().size / 2
	
	# Create popup label
	var label = Label.new()
	label.text = message
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 16)
	label.position = screen_pos
	label.z_index = 100
	_popup_container.add_child(label)
	
	# Animate and remove
	var tween = create_tween()
	tween.tween_property(label, "position:y", screen_pos.y - 40, POPUP_DURATION)
	tween.parallel().tween_property(label, "modulate:a", 0.0, POPUP_DURATION)
	tween.tween_callback(label.queue_free)


func _on_box_emptied(box: Node2D) -> void:
	if is_instance_valid(box):
		SignalBus.publish("ui.popup", {
			"message": "Box Empty!",
			"position": box.global_position + Vector2(0, -30),
			"type": "warning"
		})


func _on_guy_tantrum(guy: Node2D) -> void:
	if is_instance_valid(guy):
		SignalBus.publish("ui.popup", {
			"message": "TANTRUM!",
			"position": guy.global_position + Vector2(0, -30),
			"type": "warning"
		})
