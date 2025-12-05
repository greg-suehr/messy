extends Node
class_name RoundManager
## RoundManager - Orchestrates round flow and game progression
##
## Manages the lifecycle of rounds: setup -> active -> resolution -> parameterization.
## Coordinates between spawners, game board, and UI systems.

# =============================================================================
# CONSTANTS
# =============================================================================
const SETUP_DURATION := 3.0  # Seconds for setup phase animations
const RESOLUTION_DURATION := 5.0  # Minimum time to show score

# =============================================================================
# STATE
# =============================================================================
var is_running: bool = false
var _setup_timer: float = 0.0
var _resolution_timer: float = 0.0

# References (set by main scene)
var game_board: GameBoard
var player_controller: PlayerController
var box_spawner: BoxSpawner
var guy_spawner: GuySpawner
var chaos_system: ChaosParticleSystem


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.round_setup_started.connect(_on_setup_started)
	SignalBus.round_active_started.connect(_on_active_started)
	SignalBus.round_ended.connect(_on_round_ended)
	SignalBus.round_parameterization_ended.connect(_on_parameterization_ended)
	SignalBus.messiness_threshold_exceeded.connect(_on_messiness_exceeded)


# =============================================================================
# ROUND LIFECYCLE
# =============================================================================
func start_game() -> void:
	"""Begin a new game."""
	is_running = true
	GameState.start_game()


func _begin_round_setup() -> void:
	"""Initialize a new round."""
	# Clear previous round's entities
	if chaos_system:
		chaos_system.clear_all_particles()
	
	if guy_spawner:
		guy_spawner.reset_for_round()
	
	if player_controller:
		player_controller.reset_for_round()
	
	# Apply any queued board size changes
	if game_board:
		game_board.set_board_size(GameState.param_board_size)
	
	# Setup timer for phase transition
	_setup_timer = SETUP_DURATION
	
	# BoxSpawner will handle box creation via signal


func _begin_round_active() -> void:
	"""Start the active gameplay phase."""
	GameState.start_round_active()
	
	# Guy spawner starts via signal


func _end_round(result: String) -> void:
	"""End the current round."""
	GameState.end_round(result)
	
	# Stop spawning
	if guy_spawner:
		guy_spawner.stop_spawning()
	
	# Deactivate player
	if player_controller:
		player_controller.is_active = false
	
	_resolution_timer = RESOLUTION_DURATION


func _begin_parameterization() -> void:
	"""Start the between-rounds upgrade screen."""
	GameState.start_parameterization()


func _end_parameterization() -> void:
	"""Finish parameterization and move to next round."""
	GameState.end_parameterization()


# =============================================================================
# PROCESS
# =============================================================================
func _process(delta: float) -> void:
	if not is_running:
		return
	
	match GameState.phase:
		GameState.GamePhase.SETUP:
			_process_setup(delta)
		
		GameState.GamePhase.RESOLUTION:
			_process_resolution(delta)


func _process_setup(delta: float) -> void:
	"""Handle setup phase timing."""
	_setup_timer -= delta
	
	if _setup_timer <= 0:
		_begin_round_active()


func _process_resolution(delta: float) -> void:
	"""Handle resolution phase timing (wait for UI)."""
	_resolution_timer -= delta
	
	# Resolution phase ends when UI signals continue
	# or timer runs out (fallback)


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_game_started() -> void:
	is_running = true


func _on_setup_started(_round_number: int) -> void:
	_begin_round_setup()


func _on_active_started(_round_number: int) -> void:
	# Active phase running - nothing to do here
	pass


func _on_round_ended(_round_number: int, _result: String) -> void:
	_resolution_timer = RESOLUTION_DURATION


func _on_parameterization_ended(_round_number: int) -> void:
	# GameState handles advancing to next round
	pass


func _on_messiness_exceeded() -> void:
	"""Called when chaos particles exceed threshold - round failure."""
	if GameState.phase == GameState.GamePhase.ACTIVE:
		_end_round("failure")


# =============================================================================
# PUBLIC API - Called by UI
# =============================================================================
func request_continue_to_parameterization() -> void:
	"""Called by UI when player clicks continue after seeing score."""
	if GameState.phase == GameState.GamePhase.RESOLUTION:
		_begin_parameterization()


func request_start_next_round() -> void:
	"""Called by UI when player finishes parameterization."""
	if GameState.phase == GameState.GamePhase.PARAMETERIZATION:
		_end_parameterization()


func request_retry_round() -> void:
	"""Called by UI to retry the current round."""
	if GameState.phase == GameState.GamePhase.RESOLUTION:
		# Reset round state but don't advance round number
		GameState._reset_round_state()
		GameState.start_round_setup()


# =============================================================================
# DEPENDENCY INJECTION
# =============================================================================
func set_dependencies(
	board: GameBoard,
	player: PlayerController,
	boxes: BoxSpawner,
	guys: GuySpawner,
	chaos: ChaosParticleSystem
) -> void:
	"""Set up references to other systems."""
	game_board = board
	player_controller = player
	box_spawner = boxes
	guy_spawner = guys
	chaos_system = chaos
	
	# Wire up cross-references
	if player_controller and game_board:
		player_controller.set_game_board(game_board)
	
	if box_spawner and game_board:
		box_spawner.set_game_board(game_board)
	
	if guy_spawner:
		if game_board:
			guy_spawner.set_game_board(game_board)
		if box_spawner:
			guy_spawner.set_box_spawner(box_spawner)
	
	#if chaos_system and game_board:
	#	chaos_system.set_game_board(game_board)
