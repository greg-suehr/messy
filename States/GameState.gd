extends Node
## GameState - Central state management for Messy
##
## Tracks round progression, scoring, star economy, and game phase.
## All state changes emit signals through SignalBus.

# =============================================================================
# CONSTANTS
# =============================================================================
const MAX_ROUNDS := 15
const MIN_ROUNDS := 12
const STARS_PER_ROUND := 3
const MAX_POSSIBLE_STARS := MAX_ROUNDS * STARS_PER_ROUND  # 45

# Scoring constants
const POINTS_PER_THING_RETURNED := 10
const PENALTY_PER_TANTRUM := 5
const PENALTY_PER_EMPTY_BOX := 25

# Multiplier thresholds (based on chaos particle count)
const MULTIPLIER_HIGH := 1.5      # < 3 particles
const MULTIPLIER_MED := 1.2       # 3-6 particles  
const MULTIPLIER_LOW := 0.8       # > 6 particles
const CHAOS_THRESHOLD_HIGH := 3
const CHAOS_THRESHOLD_MED := 6

# Star thresholds
const STAR_1_THRESHOLD := 0.0     # Survive round
const STAR_2_THRESHOLD := 0.8     # 80% boxes stocked
const STAR_3_TANTRUM_MAX := 3     # Max tantrums for 3 stars
const STAR_3_MULTIPLIER_MIN := 1.2

# Failure threshold
const MESSINESS_FAILURE_THRESHOLD := 0.9

# =============================================================================
# ENUMS
# =============================================================================
enum GamePhase {
	TITLE,
	SETUP,        # Brief pre-round setup (boxes spawning, things fading in)
	ACTIVE,       # Main gameplay
	RESOLUTION,   # Round ended, showing score
	PARAMETERIZATION,  # Between-round upgrade screen
	GAME_OVER,
	ENDLESS
}

# =============================================================================
# STATE
# =============================================================================
var phase: GamePhase = GamePhase.TITLE
var current_round: int = 0
var is_endless_mode: bool = false
var is_paused: bool = false

# Round state (reset each round)
var round_time_remaining: float = 0.0
var round_time_total: float = 120.0  # Default 2 minutes
var round_score: int = 0
var round_things_returned: int = 0
var round_tantrums: int = 0
var round_empty_box_events: int = 0
var round_boxes_stocked_ratio: float = 1.0
var current_chaos_particles: int = 0
var current_multiplier: float = 1.0

# Persistent state
var total_score: int = 0
var stars_earned: int = 0
var stars_available: int = 0  # Unspent stars
var rounds_completed: int = 0

# Purchased upgrades (persists across rounds)
var purchased_upgrades: Array[String] = []

# Round parameters (modified by upgrades)
var param_box_count: int = 1
var param_thing_types: int = 1
var param_guy_types: int = 1
var param_board_size: Vector2i = Vector2i(8, 8)
var param_guy_spawn_rate: float = 3.0  # Seconds between spawns
var param_round_duration: float = 120.0


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	# Listen for game events that affect state
	SignalBus.thing_returned_to_box.connect(_on_thing_returned)
	SignalBus.guy_entered_tantrum.connect(_on_guy_tantrum)
	SignalBus.box_emptied.connect(_on_box_emptied)
	SignalBus.chaos_particle_spawned.connect(_on_chaos_particle_spawned)
	SignalBus.chaos_particle_despawned.connect(_on_chaos_particle_despawned)
	SignalBus.stars_spent.connect(_on_stars_spent)
	SignalBus.upgrade_purchased.connect(_on_upgrade_purchased)


# =============================================================================
# PHASE MANAGEMENT
# =============================================================================
func start_game() -> void:
	_reset_game_state()
	phase = GamePhase.SETUP
	current_round = 1
	SignalBus.publish("game.started")
	start_round_setup()


func start_round_setup() -> void:
	phase = GamePhase.SETUP
	_reset_round_state()
	SignalBus.publish("round.setup.started", {"round_number": current_round})


func start_round_active() -> void:
	phase = GamePhase.ACTIVE
	round_time_remaining = param_round_duration
	round_time_total = param_round_duration
	SignalBus.publish("round.active.started", {"round_number": current_round})


func end_round(result: String) -> void:
	phase = GamePhase.RESOLUTION
	
	var stars = _calculate_stars()
	var breakdown = _calculate_score_breakdown()
	
	stars_earned += stars
	stars_available += stars
	total_score += round_score
	
	if result == "victory":
		rounds_completed += 1
	
	SignalBus.publish("round.ended", {
		"round_number": current_round,
		"result": result
	})
	
	SignalBus.publish("score.round.tallied", {
		"round_score": round_score,
		"stars_earned": stars,
		"breakdown": breakdown
	})
	
	SignalBus.publish("stars.earned", {
		"amount": stars,
		"total": stars_earned
	})


func start_parameterization() -> void:
	phase = GamePhase.PARAMETERIZATION
	SignalBus.publish("round.param.started", {"round_number": current_round})


func end_parameterization() -> void:
	SignalBus.publish("round.param.ended", {"round_number": current_round})
	current_round += 1
	
	if current_round > MAX_ROUNDS:
		_enter_game_over()
	else:
		start_round_setup()


func _enter_game_over() -> void:
	phase = GamePhase.GAME_OVER
	SignalBus.publish("game.over", {
		"final_score": total_score,
		"rounds_completed": rounds_completed
	})
	
	if rounds_completed >= MIN_ROUNDS:
		SignalBus.publish("game.endless.unlocked")


func pause_game() -> void:
	if phase == GamePhase.ACTIVE:
		is_paused = true
		SignalBus.publish("game.paused")


func resume_game() -> void:
	if is_paused:
		is_paused = false
		SignalBus.publish("game.resumed")


# =============================================================================
# ROUND TIMER
# =============================================================================
func _process(delta: float) -> void:
	if phase != GamePhase.ACTIVE or is_paused:
		return
	
	round_time_remaining -= delta
	
	SignalBus.publish("round.timer.tick", {
		"time_remaining": round_time_remaining,
		"time_total": round_time_total
	})
	
	if round_time_remaining <= 0:
		end_round("victory")


# =============================================================================
# SCORING
# =============================================================================
func add_score(amount: int, reason: String) -> void:
	var final_amount = int(amount * current_multiplier)
	round_score += final_amount
	
	SignalBus.publish("score.points.added", {
		"amount": final_amount,
		"reason": reason,
		"multiplier": current_multiplier
	})
	
	SignalBus.publish("score.total.updated", {
		"new_total": total_score + round_score
	})


func apply_penalty(amount: int, reason: String) -> void:
	round_score = max(0, round_score - amount)
	
	SignalBus.publish("score.penalty", {
		"amount": amount,
		"reason": reason
	})


func update_multiplier() -> void:
	var old_multiplier = current_multiplier
	
	if current_chaos_particles < CHAOS_THRESHOLD_HIGH:
		current_multiplier = MULTIPLIER_HIGH
	elif current_chaos_particles <= CHAOS_THRESHOLD_MED:
		current_multiplier = MULTIPLIER_MED
	else:
		current_multiplier = MULTIPLIER_LOW
	
	if current_multiplier != old_multiplier:
		SignalBus.publish("score.multiplier.changed", {
			"old_value": old_multiplier,
			"new_value": current_multiplier
		})


func _calculate_stars() -> int:
	var stars = 0
	
	# Star 1: Survived the round
	stars += 1
	
	# Star 2: 80%+ boxes stocked throughout
	if round_boxes_stocked_ratio >= STAR_2_THRESHOLD:
		stars += 1
	
	# Star 3: < 3 tantrums AND maintained good multiplier
	if round_tantrums < STAR_3_TANTRUM_MAX and current_multiplier >= STAR_3_MULTIPLIER_MIN:
		stars += 1
	
	return stars


func _calculate_score_breakdown() -> Dictionary:
	return {
		"things_returned": round_things_returned,
		"things_score": round_things_returned * POINTS_PER_THING_RETURNED,
		"tantrums": round_tantrums,
		"tantrum_penalty": round_tantrums * PENALTY_PER_TANTRUM,
		"empty_boxes": round_empty_box_events,
		"empty_box_penalty": round_empty_box_events * PENALTY_PER_EMPTY_BOX,
		"final_multiplier": current_multiplier,
		"chaos_particles": current_chaos_particles,
		"raw_score": round_things_returned * POINTS_PER_THING_RETURNED,
		"final_score": round_score
	}


# =============================================================================
# CHAOS & MESSINESS
# =============================================================================
func get_messiness_ratio() -> float:
	# Messiness based on chaos particle count relative to board area
	var board_area = param_board_size.x * param_board_size.y
	var max_particles = board_area * 0.5  # 50% coverage = max messiness
	return clampf(float(current_chaos_particles) / max_particles, 0.0, 1.0)


func check_messiness_threshold() -> void:
	var messiness = get_messiness_ratio()
	
	SignalBus.publish("chaos.level.changed", {
		"particle_count": current_chaos_particles,
		"messiness_ratio": messiness
	})
	
	if messiness >= MESSINESS_FAILURE_THRESHOLD:
		SignalBus.publish("chaos.exceeded")
		end_round("failure")
	elif messiness >= MESSINESS_FAILURE_THRESHOLD - 0.1:
		SignalBus.publish("chaos.warning", {
			"current": messiness,
			"threshold": MESSINESS_FAILURE_THRESHOLD
		})


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_thing_returned(_thing: Node2D, _box: Node2D) -> void:
	round_things_returned += 1
	add_score(POINTS_PER_THING_RETURNED, "thing_returned")


func _on_guy_tantrum(_guy: Node2D) -> void:
	round_tantrums += 1
	apply_penalty(PENALTY_PER_TANTRUM, "tantrum")


func _on_box_emptied(_box: Node2D) -> void:
	round_empty_box_events += 1
	apply_penalty(PENALTY_PER_EMPTY_BOX, "empty_box")


func _on_chaos_particle_spawned(_particle: Node2D, _source: Node2D) -> void:
	current_chaos_particles += 1
	update_multiplier()
	check_messiness_threshold()


func _on_chaos_particle_despawned(_particle: Node2D) -> void:
	current_chaos_particles = max(0, current_chaos_particles - 1)
	update_multiplier()
	check_messiness_threshold()


func _on_stars_spent(amount: int, _remaining: int, _upgrade_id: String) -> void:
	stars_available -= amount


func _on_upgrade_purchased(upgrade_id: String, _category: String) -> void:
	if upgrade_id not in purchased_upgrades:
		purchased_upgrades.append(upgrade_id)


# =============================================================================
# STATE RESET
# =============================================================================
func _reset_round_state() -> void:
	round_time_remaining = param_round_duration
	round_time_total = param_round_duration
	round_score = 0
	round_things_returned = 0
	round_tantrums = 0
	round_empty_box_events = 0
	round_boxes_stocked_ratio = 1.0
	current_chaos_particles = 0
	current_multiplier = 1.0


func _reset_game_state() -> void:
	current_round = 0
	is_endless_mode = false
	is_paused = false
	total_score = 0
	stars_earned = 0
	stars_available = 0
	rounds_completed = 0
	purchased_upgrades.clear()
	
	# Reset parameters to defaults
	param_box_count = 1
	param_thing_types = 1
	param_guy_types = 1
	param_board_size = Vector2i(8, 8)
	param_guy_spawn_rate = 3.0
	param_round_duration = 120.0
	
	_reset_round_state()


# =============================================================================
# SAVE/LOAD (for later implementation)
# =============================================================================
func get_save_data() -> Dictionary:
	return {
		"current_round": current_round,
		"total_score": total_score,
		"stars_earned": stars_earned,
		"stars_available": stars_available,
		"rounds_completed": rounds_completed,
		"purchased_upgrades": purchased_upgrades,
		"params": {
			"box_count": param_box_count,
			"thing_types": param_thing_types,
			"guy_types": param_guy_types,
			"board_size": {"x": param_board_size.x, "y": param_board_size.y},
			"guy_spawn_rate": param_guy_spawn_rate,
			"round_duration": param_round_duration
		}
	}


func load_save_data(data: Dictionary) -> void:
	current_round = data.get("current_round", 1)
	total_score = data.get("total_score", 0)
	stars_earned = data.get("stars_earned", 0)
	stars_available = data.get("stars_available", 0)
	rounds_completed = data.get("rounds_completed", 0)
	purchased_upgrades = data.get("purchased_upgrades", [])
	
	var params = data.get("params", {})
	param_box_count = params.get("box_count", 1)
	param_thing_types = params.get("thing_types", 1)
	param_guy_types = params.get("guy_types", 1)
	var board = params.get("board_size", {"x": 8, "y": 8})
	param_board_size = Vector2i(board.x, board.y)
	param_guy_spawn_rate = params.get("guy_spawn_rate", 3.0)
	param_round_duration = params.get("round_duration", 120.0)