extends Node
class_name GuySpawner
## GuySpawner - Manages spawning Guys (chaos agents) during active rounds
##
## Guys spawn at escalating rates as rounds progress. The spawner handles
## timing, type selection based on unlocked GuyTypes, and target assignment.

# =============================================================================
# CONFIGURATION
# =============================================================================
@export var guy_scene: PackedScene

# Spawn rate escalation
const BASE_SPAWN_INTERVAL := 3.0  # Seconds between spawns at start
const MIN_SPAWN_INTERVAL := 0.8   # Fastest spawn rate
const ESCALATION_RATE := 0.95     # Multiply interval by this each spawn

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


func set_game_board(board: GameBoard) -> void:
	_game_board = board


func set_box_spawner(spawner: BoxSpawner) -> void:
	_box_spawner = spawner


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
	
	# Position at spawn point (outside board)
	var spawn_pos = _get_spawn_position_for_box(target_box)
	guy.global_position = spawn_pos
	
	# Calculate exit position (opposite side of board)
	var exit_pos = _get_exit_position_from_spawn(spawn_pos)
	
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


func _get_spawn_position_for_box(target_box: Box) -> Vector2:
	"""Get a spawn position that makes sense for approaching the target box."""
	if not _game_board:
		return Vector2(-200, 0)
	
	var box_pos = target_box.global_position
	var _board_center = _game_board.get_board_center()
	
	# Determine which edge the box is on
	var half_size = _game_board.get_board_pixel_size() * 0.5
	var spawn_margin = GameBoard.TILE_SIZE * 3
	
	# Spawn from the edge opposite to where the box is
	if abs(box_pos.y - (-half_size.y)) < GameBoard.TILE_SIZE:  # Box on north
		return Vector2(box_pos.x + randf_range(-50, 50), half_size.y + spawn_margin)
	elif abs(box_pos.y - half_size.y) < GameBoard.TILE_SIZE:  # Box on south
		return Vector2(box_pos.x + randf_range(-50, 50), -half_size.y - spawn_margin)
	elif abs(box_pos.x - half_size.x) < GameBoard.TILE_SIZE:  # Box on east
		return Vector2(-half_size.x - spawn_margin, box_pos.y + randf_range(-50, 50))
	else:  # Box on west
		return Vector2(half_size.x + spawn_margin, box_pos.y + randf_range(-50, 50))


func _get_exit_position_from_spawn(spawn_pos: Vector2) -> Vector2:
	"""Get an exit position on the opposite side from spawn."""
	if not _game_board:
		return -spawn_pos
	
	var half_size = _game_board.get_board_pixel_size() * 0.5
	var exit_margin = GameBoard.TILE_SIZE * 3
	
	# Exit on opposite side from spawn
	if spawn_pos.y > half_size.y:  # Spawned south
		return Vector2(spawn_pos.x, -half_size.y - exit_margin)
	elif spawn_pos.y < -half_size.y:  # Spawned north
		return Vector2(spawn_pos.x, half_size.y + exit_margin)
	elif spawn_pos.x > half_size.x:  # Spawned east
		return Vector2(-half_size.x - exit_margin, spawn_pos.y)
	else:  # Spawned west
		return Vector2(half_size.x + exit_margin, spawn_pos.y)


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
func _on_round_started(_round_number: int) -> void:
	reset_for_round()
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
