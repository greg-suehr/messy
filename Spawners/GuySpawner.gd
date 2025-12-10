extends Node
class_name GuySpawner
## GuySpawner - Manages spawning Guys (chaos agents) during active rounds
##
## Guys spawn in a central spawn zone on the game board with a fade-in effect.
## The spawner handles timing, type selection based on unlocked GuyTypes, 
## and target assignment.

# =============================================================================
# CONFIGURATION
# =============================================================================
@export var guy_scene: PackedScene

# Spawn rate escalation
const BASE_SPAWN_INTERVAL := 3.0  # Seconds between spawns at start
const MIN_SPAWN_INTERVAL := 0.8   # Fastest spawn rate
const ESCALATION_RATE := 0.95     # Multiply interval by this each spawn

# Spawn zone configuration (percentage of board size)
const SPAWN_ZONE_SIZE_RATIO := 0.6  # 60% of board is spawn zone
const SPAWN_ZONE_MARGIN := 32.0     # Minimum margin from spawn zone edge

# =============================================================================
# STATE
# =============================================================================
var is_spawning: bool = false
var spawn_timer: float = 0.0
var current_spawn_interval: float = BASE_SPAWN_INTERVAL
var guys_spawned_this_round: int = 0
var max_concurrent_guys: int = 15

var active_guys: Array[Guy] = []
var _game_board: GameBoard = null
var _box_spawner: BoxSpawner = null

# Spawn zone bounds (calculated from board size)
var _spawn_zone_rect: Rect2 = Rect2()


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	SignalBus.round_active_started.connect(_on_round_started)
	SignalBus.round_ended.connect(_on_round_ended)
	SignalBus.guy_despawned.connect(_on_guy_despawned)
	SignalBus.game_paused.connect(_on_game_paused)
	SignalBus.game_resumed.connect(_on_game_resumed)
	SignalBus.round_setup_started.connect(_on_round_setup)


func set_game_board(board: GameBoard) -> void:
	_game_board = board
	_calculate_spawn_zone()


func set_box_spawner(spawner: BoxSpawner) -> void:
	_box_spawner = spawner


# =============================================================================
# SPAWN ZONE CALCULATION
# =============================================================================
func _calculate_spawn_zone() -> void:
	"""Calculate the central spawn zone based on current board size."""
	if not _game_board:
		_spawn_zone_rect = Rect2(-64, -64, 128, 128)  # Default fallback
		return
	
	var board_pixel_size = _game_board.get_board_pixel_size()
	var spawn_size = board_pixel_size * SPAWN_ZONE_SIZE_RATIO
	
	# Center the spawn zone on the board
	var spawn_position = -spawn_size * 0.5
	_spawn_zone_rect = Rect2(spawn_position, spawn_size)


func get_spawn_zone_position() -> Vector2:
	"""Get a random position within the central spawn zone."""
	return Vector2(
		randf_range(
			_spawn_zone_rect.position.x + SPAWN_ZONE_MARGIN,
			_spawn_zone_rect.end.x - SPAWN_ZONE_MARGIN
		),
		randf_range(
			_spawn_zone_rect.position.y + SPAWN_ZONE_MARGIN,
			_spawn_zone_rect.end.y - SPAWN_ZONE_MARGIN
		)
	)


# =============================================================================
# SPAWNING LOGIC
# =============================================================================
func _process(delta: float) -> void:
	if not is_spawning:
		return
	
	if GameState.is_paused:
		return
	
	spawn_timer += delta
	
	if spawn_timer >= current_spawn_interval:
		spawn_timer = 0.0
		_try_spawn_guy()
		
		# Escalate spawn rate
		current_spawn_interval = maxf(
			current_spawn_interval * ESCALATION_RATE,
			MIN_SPAWN_INTERVAL
		)


func _try_spawn_guy() -> void:
	"""Attempt to spawn a new guy if under the limit."""
	# Clean up invalid references
	_cleanup_inactive_guys()
	
	if active_guys.size() >= max_concurrent_guys:
		return
	
	# Select guy type based on round and weights
	var guy_type = GuyTypes.get_random_unlocked_type(GameState.current_round)
	if guy_type == null:
		guy_type = GuyTypes.get_type("normal")
	
	# Select target box
	var target_box = _select_target_box(guy_type)
	if target_box == null:
		# No valid target - skip this spawn
		return
	
	_spawn_guy(guy_type, target_box)


func _spawn_guy(guy_type: GuyTypes.GuyType, target_box: Box) -> Guy:
	"""Spawn a guy of the specified type targeting a box."""
	var guy: Guy
	
	if guy_scene:
		guy = guy_scene.instantiate() as Guy
	else:
		guy = Guy.new()
	
	guy.guy_type_id = guy_type.id
	
	# Position in central spawn zone (not outside board anymore)
	var spawn_pos = get_spawn_zone_position()
	guy.global_position = spawn_pos
	
	# Calculate exit position (random edge of board)
	var exit_pos = _get_random_exit_position()
	
	# Add to scene tree
	if _game_board:
		_game_board.add_child(guy)
	else:
		get_parent().add_child(guy)
	
	# Initialize the guy with target info
	guy.initialize(target_box.thing_type_id, target_box, exit_pos)
	
	active_guys.append(guy)
	guys_spawned_this_round += 1
	
	# Audio feedback
	SignalBus.publish("audio.sfx", {
		"sfx_id": "guy_spawn",
		"position": spawn_pos
	})
	
	return guy


func _select_target_box(guy_type: GuyTypes.GuyType) -> Box:
	"""Select a box for the guy to target based on behavior."""
	if _box_spawner == null or _box_spawner.spawned_boxes.is_empty():
		return null
	
	var candidates: Array[Box] = []
	
	# Filter based on guy behavior
	if guy_type.prefers_empty_boxes:
		# Scavenger: prefer boxes that are already empty or low
		for box in _box_spawner.spawned_boxes:
			if is_instance_valid(box):
				if box.is_empty or box.get_thing_count() <= 2:
					candidates.append(box)
	
	# Default behavior: prefer boxes with things
	if candidates.is_empty():
		for box in _box_spawner.spawned_boxes:
			if is_instance_valid(box) and box.has_things():
				candidates.append(box)
	
	# Fallback: any box
	if candidates.is_empty():
		for box in _box_spawner.spawned_boxes:
			if is_instance_valid(box):
				candidates.append(box)
	
	if candidates.is_empty():
		return null
	
	return candidates[randi() % candidates.size()]


func _get_random_exit_position() -> Vector2:
	"""Get a random exit position outside the board."""
	if not _game_board:
		return Vector2(300, 0)
	
	var half_size = _game_board.get_board_pixel_size() * 0.5
	var exit_margin = GameBoard.TILE_SIZE * 3
	
	# Pick random edge
	var edge = randi() % 4
	match edge:
		0:  # North
			return Vector2(randf_range(-half_size.x, half_size.x), -half_size.y - exit_margin)
		1:  # South
			return Vector2(randf_range(-half_size.x, half_size.x), half_size.y + exit_margin)
		2:  # East
			return Vector2(half_size.x + exit_margin, randf_range(-half_size.y, half_size.y))
		_:  # West
			return Vector2(-half_size.x - exit_margin, randf_range(-half_size.y, half_size.y))


# =============================================================================
# CLEANUP
# =============================================================================
func _cleanup_inactive_guys() -> void:
	"""Remove invalid guy references from tracking array."""
	for i in range(active_guys.size() - 1, -1, -1):
		if not is_instance_valid(active_guys[i]):
			active_guys.remove_at(i)


func clear_all_guys() -> void:
	"""Remove all active guys."""
	for guy in active_guys:
		if is_instance_valid(guy):
			guy.queue_free()
	active_guys.clear()


# =============================================================================
# ROUND MANAGEMENT
# =============================================================================
func start_spawning() -> void:
	"""Begin spawning guys."""
	is_spawning = true
	spawn_timer = 0.0
	guys_spawned_this_round = 0
	current_spawn_interval = GameState.param_guy_spawn_rate


func stop_spawning() -> void:
	"""Stop spawning new guys."""
	is_spawning = false


func reset_for_round() -> void:
	"""Reset spawner state for a new round."""
	stop_spawning()
	clear_all_guys()
	guys_spawned_this_round = 0
	current_spawn_interval = GameState.param_guy_spawn_rate


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_round_setup(_round_number: int) -> void:
	# Recalculate spawn zone when board size might have changed
	_calculate_spawn_zone()


func _on_round_started(_round_number: int) -> void:
	reset_for_round()
	_calculate_spawn_zone()
	# Delay first spawn slightly for setup phase feel
	spawn_timer = -1.5
	start_spawning()


func _on_round_ended(_round_number: int, _result: String) -> void:
	stop_spawning()
	# Don't clear guys immediately - let them animate out


func _on_guy_despawned(guy: Node2D) -> void:
	if guy is Guy and guy in active_guys:
		active_guys.erase(guy)


func _on_game_paused() -> void:
	# Spawning handled by is_paused check in _process
	pass


func _on_game_resumed() -> void:
	pass


# =============================================================================
# PUBLIC API
# =============================================================================
func get_active_guy_count() -> int:
	_cleanup_inactive_guys()
	return active_guys.size()


func get_guys_spawned_this_round() -> int:
	return guys_spawned_this_round


func get_current_spawn_rate() -> float:
	"""Returns guys per minute at current rate."""
	if current_spawn_interval <= 0:
		return 0.0
	return 60.0 / current_spawn_interval


func get_active_guys() -> Array[Guy]:
	"""Get array of active guys for boids calculations."""
	_cleanup_inactive_guys()
	return active_guys


func get_spawn_zone() -> Rect2:
	"""Get the current spawn zone rectangle."""
	return _spawn_zone_rect