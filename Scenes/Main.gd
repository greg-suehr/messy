extends Node2D
class_name Main
## Main - Root scene controller for Messy
##
## Initializes all systems, manages scene structure, and handles
## high-level game flow. This is the entry point for the game.

# =============================================================================
# SCENE REFERENCES
# ==========
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
var stack_ui  # StackUI - The new stack display
var post_round_panel: PostRoundPanel
var parameterization_panel: ParameterizationPanel
var screen_effects: ScreenEffects


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	print("game ready")
	_create_systems()
	print("created systems")
	_wire_dependencies()
	_connect_signals()
	
	# Start the game after a brief delay for setup
	await get_tree().create_timer(0.5).timeout
	print("starting game")
	_start_game()


func _create_systems() -> void:
	"""Instantiate all game systems."""
	
	# Create game board (visual play area)
	game_board = GameBoard.new()
	game_board.name = "GameBoard"
	add_child(game_board)
	
	# Create chaos particle system
	chaos_system = ChaosParticleSystem.new()
	chaos_system.name = "ChaosParticleSystem"
	add_child(chaos_system)
	
	# Create spawners
	box_spawner = BoxSpawner.new()
	box_spawner.name = "BoxSpawner"
	add_child(box_spawner)
	
	guy_spawner = GuySpawner.new()
	guy_spawner.name = "GuySpawner"
	add_child(guy_spawner)
	
	# Create player controller
	player_controller = PlayerController.new()
	player_controller.name = "Player"
	add_child(player_controller)
	
	# Create camera for player
	var camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.enabled = true
	camera.zoom = Vector2(1.5, 1.5)
	player_controller.add_child(camera)
	
	# Create round manager
	round_manager = RoundManager.new()
	round_manager.name = "RoundManager"
	add_child(round_manager)
	
	# Create UI layers
	game_hud = GameHUD.new()
	game_hud.name = "GameHUD"
	game_hud.layer = 10
	add_child(game_hud)
	
	# Create Stack UI (new component)
	#stack_ui = _create_stack_ui()
	#stack_ui.name = "StackUI"
	#add_child(stack_ui)
	
	post_round_panel = PostRoundPanel.new()
	post_round_panel.name = "PostRoundPanel"
	post_round_panel.layer = 20
	add_child(post_round_panel)
	
	parameterization_panel = ParameterizationPanel.new()
	parameterization_panel.name = "ParameterizationPanel"
	parameterization_panel.layer = 20
	add_child(parameterization_panel)
	
	screen_effects = ScreenEffects.new()
	screen_effects.name = "ScreenEffects"
	screen_effects.layer = 30
	add_child(screen_effects)


func _create_stack_ui():
	"""Create the StackUI instance. Returns the node."""
	# Try to load as a script if it exists
	var script_path = "res://UI/StackUI.gd"
	if ResourceLoader.exists(script_path):
		var script = load(script_path)
		var ui = CanvasLayer.new()
		ui.set_script(script)
		return ui
	else:
		# Fallback: create inline (this shouldn't happen in production)
		push_warning("StackUI.gd not found at expected path, creating placeholder")
		var ui = CanvasLayer.new()
		ui.layer = 15
		return ui


func _wire_dependencies() -> void:
	"""Connect systems to each other."""
	
	# Set up round manager with all dependencies
	round_manager.set_dependencies(
		game_board,
		player_controller,
		box_spawner,
		guy_spawner,
		chaos_system
	)
	
	# Connect player to game board
	if player_controller and game_board:
		player_controller.set_game_board(game_board)
	
	# Connect player to stack UI
	if player_controller and stack_ui:
		player_controller.set_stack_ui(stack_ui)
	
	# Connect screen effects to camera
	var camera = player_controller.get_node_or_null("Camera2D")
	if camera:
		screen_effects.set_camera(camera)


func _connect_signals() -> void:
	"""Connect to high-level game signals."""
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.endless_mode_unlocked.connect(_on_endless_unlocked)


# =============================================================================
# GAME FLOW
# =============================================================================
func _start_game() -> void:
	"""Begin a new game."""
	print("Starting Messy!")
	round_manager.start_game()


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
					round_manager._end_round("victory")
			KEY_F3:
				# Debug: Spawn a guy immediately
				if guy_spawner:
					guy_spawner._try_spawn_guy()
			KEY_F4:
				# Debug: Trigger a tantrum
				_debug_trigger_tantrum()
			KEY_F5:
				# Debug: Add stars
				GameState.stars_available += 3
				GameState.stars_earned += 3
			KEY_F6:
				# Debug: Print stack info
				_print_stack_debug()


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
	print("Active Guys: %d" % guy_spawner.get_active_guy_count())
	print("Boxes: %d" % box_spawner.get_box_count())
	print("========================")


func _print_stack_debug() -> void:
	print("=== STACK DEBUG ===")
	print("Stack size: %d / %d" % [player_controller.get_stack_size(), PlayerController.MAX_STACK_SIZE])
	print("Near box: %s" % player_controller.is_near_box())
	var nearest = player_controller.get_nearest_box()
	if nearest:
		print("Nearest box type: %s" % nearest.thing_type_id)
	print("Stack contents:")
	for i in range(player_controller.thing_stack.size()):
		var thing = player_controller.thing_stack[i]
		if is_instance_valid(thing):
			print("  [%d] %s" % [i, thing.thing_type_id])
	print("===================")


func _debug_trigger_tantrum() -> void:
	"""Force a guy to have a tantrum for testing."""
	if guy_spawner and not guy_spawner.active_guys.is_empty():
		var guy = guy_spawner.active_guys[0]
		if is_instance_valid(guy):
			guy._enter_state(Guy.State.TANTRUM)
