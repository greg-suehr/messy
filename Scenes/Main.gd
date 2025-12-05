extends Node2D
class_name Main
## Main - Root scene controller for Messy
##
## Initializes all systems, manages scene structure, and handles
## high-level game flow. This is the entry point for the game.

# =============================================================================
# SCENE REFERENCES
# =============================================================================
var game_board: GameBoard
var round_manager: RoundManager
var chaos_system: ChaosParticleSystem

# Spawners
var box_spawner: BoxSpawner
var guy_spawner: GuySpawner

# Controller
var player_controller: PlayerController

# UI layers
var game_hud: GameHUD
var post_round_panel: PostRoundPanel
var parameterization_panel: ParameterizationPanel
var screen_effects: ScreenEffects


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	print("Messy: Initializing...")
	_setup_systems()
	_wire_dependencies()
	_connect_signals()
	
	# Start the game after a brief delay for setup
	await get_tree().create_timer(0.5).timeout
	print("Messy: Starting game!")
	_start_game()


func _setup_systems() -> void:
	"""Get or create all game systems."""
	
	# Try to get existing nodes from scene, or create them
	game_board = _get_or_create("GameBoard", GameBoard)
	chaos_system = _get_or_create("ChaosParticleSystem", ChaosParticleSystem)
	box_spawner = _get_or_create("BoxSpawner", BoxSpawner)
	guy_spawner = _get_or_create("GuySpawner", GuySpawner)
	round_manager = _get_or_create("RoundManager", RoundManager)
	
	# Player controller needs special handling as it's a CharacterBody2D
	player_controller = get_node_or_null("PlayerController") as PlayerController
	if player_controller == null:
		player_controller = PlayerController.new()
		player_controller.name = "PlayerController"
		add_child(player_controller)
	
	# Create camera for player if it doesn't have one
	if player_controller.get_node_or_null("Camera2D") == null:
		var camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.enabled = true
		camera.zoom = Vector2(1.5, 1.5)
		player_controller.add_child(camera)
	
	# UI layers - create dynamically with proper scripts
	game_hud = _get_or_create_canvas_layer("GameHUD", GameHUD, 10)
	post_round_panel = _get_or_create_canvas_layer("PostRoundPanel", PostRoundPanel, 20)
	parameterization_panel = _get_or_create_canvas_layer("ParameterizationPanel", ParameterizationPanel, 20)
	screen_effects = _get_or_create_canvas_layer("ScreenEffects", ScreenEffects, 30)
	
	print("Messy: All systems initialized")


func _get_or_create(node_name: String, node_class) -> Node:
	"""Get an existing node or create a new one."""
	var existing = get_node_or_null(node_name)
	if existing != null:
		return existing
	
	var new_node = node_class.new()
	new_node.name = node_name
	add_child(new_node)
	return new_node


func _get_or_create_canvas_layer(node_name: String, node_class, layer: int) -> CanvasLayer:
	"""Get or create a CanvasLayer node."""
	var existing = get_node_or_null(node_name)
	if existing != null:
		# If existing node doesn't have the right script, replace it
		match node_name:
			"GameHUD":
				if not existing is GameHUD:
					existing.queue_free()
					var new_game_hud = GameHUD.new()
					new_game_hud.name = node_name
					new_game_hud.layer = layer
					add_child(new_game_hud)
					return new_game_hud
				return existing
			"PostRoundPanel":
				if not existing is PostRoundPanel:
					existing.queue_free()
					var new_post_panel = PostRoundPanel.new()
					new_post_panel.name = node_name
					new_post_panel.layer = layer
					add_child(new_post_panel)
					return new_post_panel
				return existing
			"ParameterizationPanel":
				if not existing is ParameterizationPanel:
					existing.queue_free()
					var new_param_panel = ParameterizationPanel.new()
					new_param_panel.name = node_name
					new_param_panel.layer = layer
					add_child(new_param_panel)
					return new_param_panel
				return existing
			"ScreenEffects":
				if not existing is ScreenEffects:
					existing.queue_free()
					var new_effects = ScreenEffects.new()
					new_effects.name = node_name
					new_effects.layer = layer
					add_child(new_effects)
					return new_effects
				return existing
	
	var new_node = node_class.new()
	new_node.name = node_name
	new_node.layer = layer
	add_child(new_node)
	return new_node


func _wire_dependencies() -> void:
	"""Connect systems to each other."""
	
	# Set up round manager with all dependencies
	if round_manager and round_manager.has_method("set_dependencies"):
		round_manager.set_dependencies(
			game_board,
			player_controller,
			box_spawner,
			guy_spawner,
			chaos_system
		)
	
	# Connect screen effects to camera
	if screen_effects and player_controller:
		var camera = player_controller.get_node_or_null("Camera2D")
		if camera and screen_effects.has_method("set_camera"):
			screen_effects.set_camera(camera)
	
	print("Messy: Dependencies wired")


func _connect_signals() -> void:
	"""Connect to high-level game signals."""
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.endless_mode_unlocked.connect(_on_endless_unlocked)


# =============================================================================
# GAME FLOW
# =============================================================================
func _start_game() -> void:
	"""Begin a new game."""
	if round_manager and round_manager.has_method("start_game"):
		round_manager.start_game()
	else:
		# Fallback if round_manager doesn't have the method
		GameState.start_game()


func _on_game_over(final_score: int, rounds_completed: int) -> void:
	"""Handle game completion."""
	print("Game Over! Final Score: %d, Rounds: %d" % [final_score, rounds_completed])
	# TODO: Show game over screen


func _on_endless_unlocked() -> void:
	"""Handle endless mode unlock."""
	print("Endless Mode Unlocked!")
	# TODO: Enable endless mode in menu


# =============================================================================
# DEBUG
# =============================================================================
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				# Debug: Print game state
				_print_debug_state()
			KEY_F2:
				# Debug: Skip to next round
				if GameState.phase == GameState.GamePhase.ACTIVE:
					if round_manager and round_manager.has_method("_end_round"):
						round_manager._end_round("victory")
			KEY_F3:
				# Debug: Spawn a guy immediately
				if guy_spawner and guy_spawner.has_method("_try_spawn_guy"):
					guy_spawner._try_spawn_guy()
			KEY_F4:
				# Debug: Trigger a tantrum
				_debug_trigger_tantrum()
			KEY_F5:
				# Debug: Add stars
				GameState.stars_available += 3
				GameState.stars_earned += 3


func _print_debug_state() -> void:
	print("=== MESSY DEBUG STATE ===")
	print("Phase: %s" % GameState.GamePhase.keys()[GameState.phase])
	print("Round: %d" % GameState.current_round)
	print("Score: %d (Total: %d)" % [GameState.round_score, GameState.total_score])
	print("Stars: %d available / %d earned" % [GameState.stars_available, GameState.stars_earned])
	print("Chaos Particles: %d (%.1f%% messy)" % [
		GameState.current_chaos_particles,
		GameState.get_messiness_ratio() * 100
	])
	print("Multiplier: x%.1f" % GameState.current_multiplier)
	if guy_spawner:
		print("Active Guys: %d" % guy_spawner.get_active_guy_count())
	if box_spawner:
		print("Boxes: %d" % box_spawner.get_box_count())
	print("========================")


func _debug_trigger_tantrum() -> void:
	"""Force a guy to have a tantrum for testing."""
	if guy_spawner and not guy_spawner.active_guys.is_empty():
		var guy = guy_spawner.active_guys[0]
		if is_instance_valid(guy):
			guy._enter_state(Guy.State.TANTRUM)
