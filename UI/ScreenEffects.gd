extends CanvasLayer
class_name ScreenEffects
## ScreenEffects - Visual feedback system for chaos and events
##
## Implements screen shake, desaturation, vignette, and flash effects
## that increase with messiness level per the GDD.
## Uses a ColorRect child for overlay drawing since CanvasLayer cannot draw.

# =============================================================================
# CONSTANTS
# =============================================================================
const SHAKE_DECAY := 5.0
const FLASH_FADE_SPEED := 4.0

# =============================================================================
# STATE
# =============================================================================
var _shake_intensity := 0.0
var _shake_offset := Vector2.ZERO
var _desaturation := 0.0
var _vignette_intensity := 0.0
var _flash_color := Color.TRANSPARENT
var _flash_alpha := 0.0

# References
var _camera: Camera2D = null
var _original_camera_offset := Vector2.ZERO
var _overlay: ColorRect = null


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_create_overlay()
	_connect_signals()


func _create_overlay() -> void:
	"""Create a full-screen ColorRect for overlay effects."""
	_overlay = ColorRect.new()
	_overlay.name = "EffectsOverlay"
	_overlay.color = Color.TRANSPARENT
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Make it fill the entire screen
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.size = get_viewport().get_visible_rect().size
	
	add_child(_overlay)
	
	# Listen for viewport size changes
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	if _overlay:
		_overlay.size = get_viewport().get_visible_rect().size


func _connect_signals() -> void:
	SignalBus.ui_screen_shake.connect(_on_shake_requested)
	SignalBus.ui_flash.connect(_on_flash_requested)
	SignalBus.chaos_level_changed.connect(_on_chaos_changed)
	SignalBus.round_ended.connect(_on_round_ended)
	SignalBus.round_active_started.connect(_on_round_started)


func set_camera(camera: Camera2D) -> void:
	_camera = camera
	if _camera:
		_original_camera_offset = _camera.offset


# =============================================================================
# UPDATE
# =============================================================================
func _process(delta: float) -> void:
	_process_shake(delta)
	_process_flash(delta)
	_update_overlay()


func _process_shake(delta: float) -> void:
	if _shake_intensity > 0:
		# Generate random offset
		_shake_offset = Vector2(
			randf_range(-1, 1) * _shake_intensity * 10,
			randf_range(-1, 1) * _shake_intensity * 10
		)
		
		# Apply to camera
		if _camera:
			_camera.offset = _original_camera_offset + _shake_offset
		
		# Decay
		_shake_intensity = maxf(0, _shake_intensity - SHAKE_DECAY * delta)
	else:
		_shake_offset = Vector2.ZERO
		if _camera:
			_camera.offset = _original_camera_offset


func _process_flash(delta: float) -> void:
	if _flash_alpha > 0:
		_flash_alpha = maxf(0, _flash_alpha - FLASH_FADE_SPEED * delta)


func _update_overlay() -> void:
	"""Update the overlay ColorRect based on current effects."""
	if not _overlay:
		return
	
	# Combine flash and other effects into overlay color
	var overlay_color = Color.TRANSPARENT
	
	# Flash effect (takes priority)
	if _flash_alpha > 0:
		overlay_color = _flash_color
		overlay_color.a = _flash_alpha
	# Desaturation/vignette approximation (simpler than shader)
	elif _desaturation > 0 or _vignette_intensity > 0:
		# Use a semi-transparent gray for desaturation effect
		var desat_alpha = _desaturation * 0.3
		var vignette_alpha = _vignette_intensity * 0.2
		overlay_color = Color(0.2, 0.2, 0.2, maxf(desat_alpha, vignette_alpha))
	
	_overlay.color = overlay_color


# =============================================================================
# EFFECTS
# =============================================================================
func shake(intensity: float, duration: float = 0.0) -> void:
	"""Trigger screen shake effect."""
	_shake_intensity = maxf(_shake_intensity, intensity)
	
	if duration > 0:
		var tween = create_tween()
		tween.tween_property(self, "_shake_intensity", 0.0, duration)


func flash(color: Color, _duration: float = 0.1) -> void:
	"""Trigger screen flash effect."""
	_flash_color = color
	_flash_alpha = 1.0
	
	# Flash fades automatically in _process


func set_desaturation(amount: float) -> void:
	"""Set screen desaturation (0.0 = full color, 1.0 = grayscale)."""
	_desaturation = clampf(amount, 0.0, 1.0)


func set_vignette(intensity: float) -> void:
	"""Set vignette effect intensity."""
	_vignette_intensity = clampf(intensity, 0.0, 1.0)


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_shake_requested(intensity: float, duration: float) -> void:
	shake(intensity, duration)


func _on_flash_requested(color: Color, duration: float) -> void:
	flash(color, duration)


func _on_chaos_changed(_particle_count: int, messiness_ratio: float) -> void:
	"""Update visual effects based on chaos level."""
	# Desaturation increases with messiness
	set_desaturation(messiness_ratio * 0.5)
	
	# Vignette creeps in as things get messy
	set_vignette(messiness_ratio * 0.3)
	
	# Mild constant shake at high chaos
	if messiness_ratio > 0.7:
		_shake_intensity = maxf(_shake_intensity, (messiness_ratio - 0.7) * 0.3)


func _on_round_ended(_round_number: int, result: String) -> void:
	# Victory flash or failure effect
	if result == "victory":
		flash(Color(1, 1, 1, 0.5), 0.2)
	else:
		flash(Color(1, 0.3, 0.3, 0.3), 0.3)
	
	# Reset effects
	var tween = create_tween()
	tween.tween_property(self, "_desaturation", 0.0, 0.5)
	tween.parallel().tween_property(self, "_vignette_intensity", 0.0, 0.5)


func _on_round_started(_round_number: int) -> void:
	# Reset all effects
	_shake_intensity = 0.0
	_desaturation = 0.0
	_vignette_intensity = 0.0
	_flash_alpha = 0.0
	_update_overlay()


# =============================================================================
# PUBLIC API
# =============================================================================
func get_current_effects() -> Dictionary:
	return {
		"shake_intensity": _shake_intensity,
		"desaturation": _desaturation,
		"vignette": _vignette_intensity,
		"flash_alpha": _flash_alpha
	}
