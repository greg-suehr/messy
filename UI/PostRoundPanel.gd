extends CanvasLayer
class_name PostRoundPanel
## PostRoundPanel - Score display after round completion
##
## Shows animated score tally, star rewards, and narrator comment.
## Implements the "slam" effect for each score factor.

# =============================================================================
# CONSTANTS
# =============================================================================
const TALLY_DELAY := 0.3  # Seconds between score line reveals
const SLAM_DURATION := 0.15
const STAR_REVEAL_DELAY := 0.5

const COLOR_POSITIVE := Color("#7FFF00")
const COLOR_NEGATIVE := Color("#FF6B6B")
const COLOR_NEUTRAL := Color("#FFFFFF")

# =============================================================================
# STATE
# =============================================================================
var _is_showing := false
var _round_score := 0
var _stars_earned := 0
var _breakdown: Dictionary = {}
var _result: String = ""

# =============================================================================
# UI NODES
# =============================================================================
var _root_control: Control
var _background: ColorRect
var _main_container: VBoxContainer
var _title_label: Label
var _score_container: VBoxContainer
var _stars_container: HBoxContainer
var _narrator_label: Label
var _continue_label: Label


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_create_ui()
	_connect_signals()
	visible = false


func _create_ui() -> void:
	"""Create the UI elements dynamically."""
	# Root control
	_root_control = Control.new()
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root_control)
	
	# Semi-transparent background
	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color(0.05, 0.05, 0.1, 0.9)
	_root_control.add_child(_background)
	
	# Main container
	_main_container = VBoxContainer.new()
	_main_container.set_anchors_preset(Control.PRESET_CENTER)
	_main_container.offset_left = -250
	_main_container.offset_right = 250
	_main_container.offset_top = -200
	_main_container.offset_bottom = 200
	_root_control.add_child(_main_container)
	
	# Title
	_title_label = Label.new()
	_title_label.text = "Round Complete!"
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color("#FF69B4"))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_container.add_child(_title_label)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 30)
	_main_container.add_child(spacer1)
	
	# Score breakdown container
	_score_container = VBoxContainer.new()
	_score_container.add_theme_constant_override("separation", 8)
	_main_container.add_child(_score_container)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	_main_container.add_child(spacer2)
	
	# Stars container
	_stars_container = HBoxContainer.new()
	_stars_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_stars_container.add_theme_constant_override("separation", 10)
	_main_container.add_child(_stars_container)
	
	# Spacer
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 20)
	_main_container.add_child(spacer3)
	
	# Narrator comment
	_narrator_label = Label.new()
	_narrator_label.text = ""
	_narrator_label.add_theme_font_size_override("font_size", 18)
	_narrator_label.add_theme_color_override("font_color", Color("#AAAAAA"))
	_narrator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narrator_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_container.add_child(_narrator_label)
	
	# Spacer
	var spacer4 = Control.new()
	spacer4.custom_minimum_size = Vector2(0, 30)
	_main_container.add_child(spacer4)
	
	# Continue prompt
	_continue_label = Label.new()
	_continue_label.text = "Press any key to continue..."
	_continue_label.add_theme_font_size_override("font_size", 14)
	_continue_label.add_theme_color_override("font_color", Color("#666666"))
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_container.add_child(_continue_label)


func _connect_signals() -> void:
	SignalBus.score_round_tallied.connect(_on_score_tallied)
	SignalBus.round_ended.connect(_on_round_ended)


# =============================================================================
# DISPLAY
# =============================================================================
func show_results(round_score: int, stars: int, breakdown: Dictionary, result: String) -> void:
	_round_score = round_score
	_stars_earned = stars
	_breakdown = breakdown
	_result = result
	_is_showing = true
	visible = true
	
	# Update title based on result
	if result == "failure":
		_title_label.text = "Round Failed!"
		_title_label.add_theme_color_override("font_color", COLOR_NEGATIVE)
	else:
		_title_label.text = "Round Complete!"
		_title_label.add_theme_color_override("font_color", Color("#FF69B4"))
	
	# Start tally animation
	_animate_tally()


func hide_results() -> void:
	_is_showing = false
	visible = false
	
	# Clear score container for next time
	for child in _score_container.get_children():
		child.queue_free()
	for child in _stars_container.get_children():
		child.queue_free()


func _animate_tally() -> void:
	"""Animate the score breakdown reveal."""
	# Clear previous
	for child in _score_container.get_children():
		child.queue_free()
	for child in _stars_container.get_children():
		child.queue_free()
	
	# Things returned
	await get_tree().create_timer(TALLY_DELAY).timeout
	_add_score_line("Things Returned", _breakdown.get("things_returned", 0), 
		_breakdown.get("things_score", 0), COLOR_POSITIVE)
	
	# Tantrum penalty
	if _breakdown.get("tantrums", 0) > 0:
		await get_tree().create_timer(TALLY_DELAY).timeout
		_add_score_line("Tantrums", _breakdown.get("tantrums", 0),
			-_breakdown.get("tantrum_penalty", 0), COLOR_NEGATIVE)
	
	# Empty box penalty
	if _breakdown.get("empty_boxes", 0) > 0:
		await get_tree().create_timer(TALLY_DELAY).timeout
		_add_score_line("Empty Boxes", _breakdown.get("empty_boxes", 0),
			-_breakdown.get("empty_box_penalty", 0), COLOR_NEGATIVE)
	
	# Multiplier
	await get_tree().create_timer(TALLY_DELAY).timeout
	var mult = _breakdown.get("final_multiplier", 1.0)
	var mult_color = COLOR_POSITIVE if mult >= 1.0 else COLOR_NEGATIVE
	_add_score_line("Multiplier", "x%.1f" % mult, 0, mult_color, true)
	
	# Final score
	await get_tree().create_timer(TALLY_DELAY * 2).timeout
	_add_final_score(_round_score)
	
	# Stars
	await get_tree().create_timer(STAR_REVEAL_DELAY).timeout
	_reveal_stars(_stars_earned)
	
	# Narrator comment
	await get_tree().create_timer(STAR_REVEAL_DELAY).timeout
	_show_narrator_comment()


func _add_score_line(label_text: String, count, points: int, color: Color, is_multiplier: bool = false) -> void:
	"""Display a score line with slam animation."""
	SignalBus.publish("audio.sfx", {"sfx_id": "score_slam", "position": Vector2.ZERO})
	SignalBus.publish("ui.shake", {"intensity": 0.2, "duration": SLAM_DURATION})
	
	var line = HBoxContainer.new()
	line.add_theme_constant_override("separation", 20)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLOR_NEUTRAL)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	
	var count_label = Label.new()
	count_label.text = str(count) if not is_multiplier else str(count)
	count_label.add_theme_font_size_override("font_size", 18)
	count_label.add_theme_color_override("font_color", color)
	line.add_child(count_label)
	
	if not is_multiplier and points != 0:
		var points_label = Label.new()
		var prefix = "+" if points > 0 else ""
		points_label.text = "%s%d" % [prefix, points]
		points_label.add_theme_font_size_override("font_size", 18)
		points_label.add_theme_color_override("font_color", color)
		line.add_child(points_label)
	
	_score_container.add_child(line)
	
	# Slam animation
	line.modulate.a = 0
	line.scale = Vector2(1.2, 1.2)
	var tween = create_tween()
	tween.tween_property(line, "modulate:a", 1.0, SLAM_DURATION)
	tween.parallel().tween_property(line, "scale", Vector2.ONE, SLAM_DURATION)


func _add_final_score(score: int) -> void:
	"""Display the final score with emphasis."""
	SignalBus.publish("audio.sfx", {"sfx_id": "score_final", "position": Vector2.ZERO})
	SignalBus.publish("ui.shake", {"intensity": 0.4, "duration": 0.2})
	
	var separator = HSeparator.new()
	_score_container.add_child(separator)
	
	var line = HBoxContainer.new()
	
	var label = Label.new()
	label.text = "TOTAL SCORE"
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color("#FFD700"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	
	var score_label = Label.new()
	score_label.text = str(score)
	score_label.add_theme_font_size_override("font_size", 24)
	score_label.add_theme_color_override("font_color", Color("#FFD700"))
	line.add_child(score_label)
	
	_score_container.add_child(line)
	
	# Big slam animation
	line.modulate.a = 0
	line.scale = Vector2(1.5, 1.5)
	var tween = create_tween()
	tween.tween_property(line, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(line, "scale", Vector2.ONE, 0.2)


func _reveal_stars(count: int) -> void:
	"""Animate star reveal."""
	for i in range(3):
		var star = Label.new()
		star.text = "★" if i < count else "☆"
		star.add_theme_font_size_override("font_size", 48)
		star.add_theme_color_override("font_color", Color("#FFD700") if i < count else Color("#444444"))
		star.modulate.a = 0
		_stars_container.add_child(star)
		
		await get_tree().create_timer(0.2).timeout
		
		if i < count:
			SignalBus.publish("audio.sfx", {"sfx_id": "star_earn", "position": Vector2.ZERO})
		
		var tween = create_tween()
		tween.tween_property(star, "modulate:a", 1.0, 0.2)
		if i < count:
			star.scale = Vector2(1.5, 1.5)
			tween.parallel().tween_property(star, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT)


func _show_narrator_comment() -> void:
	"""Display narrator's reaction to performance."""
	var comment = _get_narrator_comment()
	_narrator_label.text = "\"" + comment + "\""
	
	var mood = "neutral"
	if _stars_earned >= 3:
		mood = "happy"
	elif _stars_earned == 0 or _result == "failure":
		mood = "worried"
	
	SignalBus.publish("ui.narrator", {
		"text": comment,
		"mood": mood
	})


func _get_narrator_comment() -> String:
	"""Get appropriate narrator comment based on performance."""
	if _result == "failure":
		var failure_comments = [
			"Oh no! Things got too messy...",
			"That was... a lot of chaos.",
			"Deep breaths. We can try again!",
			"The mess won this time. But you'll get it!",
		]
		return failure_comments[randi() % failure_comments.size()]
	
	if _stars_earned == 3:
		var perfect_comments = [
			"Magnificent! Everything in its place!",
			"Three stars! You're a natural!",
			"That was BEAUTIFUL organization!",
			"Chef's kiss! Perfection!",
		]
		return perfect_comments[randi() % perfect_comments.size()]
	
	if _stars_earned == 2:
		var good_comments = [
			"Nice work! Almost perfect!",
			"Two stars! Getting there!",
			"Good job keeping things mostly tidy!",
			"Not bad at all!",
		]
		return good_comments[randi() % good_comments.size()]
	
	# 1 star
	var ok_comments = [
		"You survived! That counts!",
		"One star is still a star!",
		"Room for improvement, but you made it!",
		"Phew! Just barely!",
	]
	return ok_comments[randi() % ok_comments.size()]


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_round_ended(_round_number: int, result: String) -> void:
	_result = result


func _on_score_tallied(round_score: int, stars_earned: int, breakdown: Dictionary) -> void:
	show_results(round_score, stars_earned, breakdown, _result)


# =============================================================================
# INPUT
# =============================================================================
func _input(event: InputEvent) -> void:
	if not _is_showing:
		return
	
	# Continue on any key/click
	if event is InputEventKey and event.pressed:
		_request_continue()
	elif event is InputEventMouseButton and event.pressed:
		_request_continue()


func _request_continue() -> void:
	"""Signal that player wants to continue."""
	hide_results()
	
	# Find RoundManager and request continuation
	var round_manager = get_node_or_null("/root/Main/RoundManager")
	if round_manager and round_manager.has_method("request_continue_to_parameterization"):
		round_manager.request_continue_to_parameterization()
	else:
		# Fallback: directly start parameterization
		GameState.start_parameterization()
