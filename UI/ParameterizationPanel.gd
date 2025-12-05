extends CanvasLayer
class_name ParameterizationPanel
## ParameterizationPanel - Between-round upgrade selection screen
##
## Displays the upgrade tree, allows star spending, and previews changes.
## Features a relaxing background music transition per GDD.

# =============================================================================
# CONSTANTS
# =============================================================================
const CATEGORY_COLORS := {
	"boxes": Color("#FF69B4"),   # Pink
	"board": Color("#00FFFF"),   # Cyan
	"things": Color("#FFD700"),  # Gold
	"guys": Color("#7FFF00"),    # Lime
}

# =============================================================================
# STATE
# =============================================================================
var _is_showing := false
var _selected_upgrade_id := ""
var _parameterization_state: ParameterizationState = null

# =============================================================================
# NODE REFERENCES
# =============================================================================
var _root_control: Control
var _background: ColorRect
var _main_container: VBoxContainer
var _header_label: Label
var _stars_label: Label
var _upgrade_container: VBoxContainer
var _preview_panel: Panel
var _preview_label: Label
var _next_round_button: Button


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_create_ui()
	_connect_signals()
	visible = false
	
	# Get ParameterizationState singleton if available
	_parameterization_state = get_node_or_null("/root/ParameterizationState")


func _create_ui() -> void:
	"""Create the UI elements dynamically."""
	# Root control to hold everything
	_root_control = Control.new()
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root_control)
	
	# Semi-transparent background
	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color(0.1, 0.1, 0.15, 0.95)
	_root_control.add_child(_background)
	
	# Main vertical container
	_main_container = VBoxContainer.new()
	_main_container.set_anchors_preset(Control.PRESET_CENTER)
	_main_container.offset_left = -300
	_main_container.offset_right = 300
	_main_container.offset_top = -250
	_main_container.offset_bottom = 250
	_root_control.add_child(_main_container)
	
	# Header
	_header_label = Label.new()
	_header_label.text = "Round Complete!"
	_header_label.add_theme_font_size_override("font_size", 32)
	_header_label.add_theme_color_override("font_color", Color("#FF69B4"))
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_container.add_child(_header_label)
	
	# Stars display
	_stars_label = Label.new()
	_stars_label.text = "★ 0"
	_stars_label.add_theme_font_size_override("font_size", 24)
	_stars_label.add_theme_color_override("font_color", Color("#FFD700"))
	_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_container.add_child(_stars_label)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	_main_container.add_child(spacer1)
	
	# Scrollable upgrade container
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 300)
	_main_container.add_child(scroll)
	
	_upgrade_container = VBoxContainer.new()
	_upgrade_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_upgrade_container)
	
	# Preview panel (on the side)
	_preview_panel = Panel.new()
	_preview_panel.custom_minimum_size = Vector2(250, 100)
	_preview_panel.visible = false
	
	var preview_style = StyleBoxFlat.new()
	preview_style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	preview_style.border_color = Color("#00FFFF")
	preview_style.set_border_width_all(2)
	preview_style.set_corner_radius_all(8)
	_preview_panel.add_theme_stylebox_override("panel", preview_style)
	_main_container.add_child(_preview_panel)
	
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.position = Vector2(10, 10)
	_preview_label.size = Vector2(230, 80)
	_preview_panel.add_child(_preview_label)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	_main_container.add_child(spacer2)
	
	# Next round button
	_next_round_button = Button.new()
	_next_round_button.text = "Next Round →"
	_next_round_button.custom_minimum_size = Vector2(200, 40)
	_next_round_button.pressed.connect(_on_next_round_pressed)
	_main_container.add_child(_next_round_button)
	
	# Center the button
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_container.remove_child(_next_round_button)
	button_container.add_child(_next_round_button)
	_main_container.add_child(button_container)


func _connect_signals() -> void:
	SignalBus.round_parameterization_started.connect(_on_parameterization_started)
	SignalBus.stars_spent.connect(_on_stars_spent)
	SignalBus.upgrade_purchased.connect(_on_upgrade_purchased)


# =============================================================================
# DISPLAY
# =============================================================================
func show_panel() -> void:
	_is_showing = true
	visible = true
	
	_update_stars_display()
	_build_upgrade_tree()
	_clear_preview()
	
	# Transition to calm music
	SignalBus.publish("audio.tempo", {"new_bpm": AudioManager.BETWEEN_ROUNDS_BPM})


func hide_panel() -> void:
	_is_showing = false
	visible = false


func _update_stars_display() -> void:
	if _stars_label:
		_stars_label.text = "★ %d Available" % GameState.stars_available


func _build_upgrade_tree() -> void:
	"""Build the upgrade selection UI."""
	if not _upgrade_container:
		return
	
	# Clear existing
	for child in _upgrade_container.get_children():
		child.queue_free()
	
	if not _parameterization_state:
		var no_state_label = Label.new()
		no_state_label.text = "(Upgrades unavailable)"
		_upgrade_container.add_child(no_state_label)
		return
	
	# Group upgrades by category
	var categories = ["boxes", "things", "board", "guys"]
	
	for category in categories:
		var category_label = Label.new()
		category_label.text = category.capitalize()
		category_label.add_theme_color_override("font_color", CATEGORY_COLORS.get(category, Color.WHITE))
		category_label.add_theme_font_size_override("font_size", 20)
		_upgrade_container.add_child(category_label)
		
		var upgrades = _parameterization_state.get_upgrades_by_category(category)
		
		for upgrade in upgrades:
			var button = _create_upgrade_button(upgrade)
			_upgrade_container.add_child(button)
		
		# Spacer
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		_upgrade_container.add_child(spacer)


func _create_upgrade_button(upgrade: ParameterizationState.Upgrade) -> Button:
	"""Create a button for an upgrade option."""
	var button = Button.new()
	button.text = "%s (★%d)" % [upgrade.display_name, upgrade.cost]
	button.custom_minimum_size = Vector2(250, 32)
	
	# Visual state
	if upgrade.purchased:
		button.disabled = true
		button.modulate = Color(0.5, 0.5, 0.5)
		button.text = "✓ " + upgrade.display_name
	elif not _parameterization_state.is_upgrade_available(
		upgrade.id, GameState.current_round, GameState.stars_available
	):
		button.disabled = true
		button.modulate = Color(0.7, 0.7, 0.7)
	
	# Connect signals
	button.pressed.connect(_on_upgrade_button_pressed.bind(upgrade.id))
	button.mouse_entered.connect(_on_upgrade_hover.bind(upgrade.id))
	button.mouse_exited.connect(_on_upgrade_unhover)
	
	return button


# =============================================================================
# PREVIEW
# =============================================================================
func _show_preview(upgrade_id: String) -> void:
	if not _parameterization_state or not _preview_panel:
		return
	
	var preview = _parameterization_state.get_upgrade_preview(upgrade_id)
	if preview.is_empty():
		_clear_preview()
		return
	
	_preview_panel.visible = true
	
	var text = "%s\n\n%s\n\n" % [preview.get("name", ""), preview.get("description", "")]
	
	var changes = preview.get("changes", [])
	for change in changes:
		text += "%s: %s → %s\n" % [
			change.get("stat", ""),
			str(change.get("current", "")),
			str(change.get("new", ""))
		]
	
	if preview.has("score_potential_change"):
		text += "\nScore Potential: +%d" % preview.get("score_potential_change", 0)
	
	if _preview_label:
		_preview_label.text = text


func _clear_preview() -> void:
	if _preview_panel:
		_preview_panel.visible = false
	_selected_upgrade_id = ""


# =============================================================================
# PURCHASE
# =============================================================================
func _attempt_purchase(upgrade_id: String) -> void:
	if not _parameterization_state:
		return
	
	if _parameterization_state.purchase_upgrade(upgrade_id):
		SignalBus.publish("audio.sfx", {"sfx_id": "purchase", "position": Vector2.ZERO})
		_update_stars_display()
		_build_upgrade_tree()
		_clear_preview()
	else:
		SignalBus.publish("audio.sfx", {"sfx_id": "error", "position": Vector2.ZERO})


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_parameterization_started(_round_number: int) -> void:
	show_panel()


func _on_stars_spent(_amount: int, _remaining: int, _upgrade_id: String) -> void:
	_update_stars_display()


func _on_upgrade_purchased(_upgrade_id: String, _category: String) -> void:
	_build_upgrade_tree()


func _on_upgrade_button_pressed(upgrade_id: String) -> void:
	_attempt_purchase(upgrade_id)


func _on_upgrade_hover(upgrade_id: String) -> void:
	_show_preview(upgrade_id)


func _on_upgrade_unhover() -> void:
	_clear_preview()


func _on_next_round_pressed() -> void:
	hide_panel()
	
	var round_manager = get_node_or_null("/root/Main/RoundManager")
	if round_manager and round_manager.has_method("request_start_next_round"):
		round_manager.request_start_next_round()
	else:
		# Fallback: directly call GameState
		GameState.end_parameterization()


# =============================================================================
# INPUT
# =============================================================================
func _input(event: InputEvent) -> void:
	if not _is_showing:
		return
	
	# Quick continue with Enter/Space
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_SPACE]:
			_on_next_round_pressed()
