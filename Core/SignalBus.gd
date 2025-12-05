extends Node
## SignalBus - Central event hub for Messy
## 
## Follows the same pattern as Library Science: typed signals for compile-time
## safety plus a generic publish/subscribe system for flexibility.

# =============================================================================
# DEBUG FLAGS
# =============================================================================
const DEBUG_EVENTS := false
const DEBUG_SCORING := false

# =============================================================================
# GENERIC EVENT STREAM
# =============================================================================
signal event(event_name: String, payload: Dictionary)

# =============================================================================
# ROUND LIFECYCLE
# =============================================================================
signal round_setup_started(round_number: int)
signal round_active_started(round_number: int)
signal round_timer_tick(time_remaining: float, time_total: float)
signal round_ended(round_number: int, result: String)  # "victory" | "failure"
signal round_parameterization_started(round_number: int)
signal round_parameterization_ended(round_number: int)

# =============================================================================
# PLAYER ACTIONS
# =============================================================================
signal player_moved(position: Vector2)
signal player_thing_picked_up(thing: Node2D, stack_size: int)
signal player_thing_dropped(thing: Node2D, into_box: bool)
signal player_stack_changed(stack: Array)

# =============================================================================
# THINGS
# =============================================================================
signal thing_spawned(thing: Node2D, thing_type_id: String)
signal thing_picked_up(thing: Node2D, by_player: bool, by_guy: Node2D)
signal thing_dropped(thing: Node2D, position: Vector2)
signal thing_returned_to_box(thing: Node2D, box: Node2D)
signal thing_scattered(thing: Node2D, from_box: Node2D, by_guy: Node2D)

# =============================================================================
# BOXES
# =============================================================================
signal box_spawned(box: Node2D, thing_type_id: String)
signal box_thing_added(box: Node2D, thing: Node2D, count: int)
signal box_thing_removed(box: Node2D, thing: Node2D, count: int)
signal box_emptied(box: Node2D)  # Score penalty trigger
signal box_restocked(box: Node2D)  # Was empty, now has things

# =============================================================================
# GUYS
# =============================================================================
signal guy_spawned(guy: Node2D, guy_type_id: String)
signal guy_targeting_box(guy: Node2D, box: Node2D)
signal guy_reached_box(guy: Node2D, box: Node2D)
signal guy_took_thing(guy: Node2D, thing: Node2D, box: Node2D)
signal guy_dropped_thing(guy: Node2D, thing: Node2D, position: Vector2)
signal guy_entered_longing(guy: Node2D, duration: float)
signal guy_entered_tantrum(guy: Node2D)
signal guy_left_board(guy: Node2D)
signal guy_despawned(guy: Node2D)

# =============================================================================
# CHAOS & MESSINESS
# =============================================================================
signal chaos_particle_spawned(particle: Node2D, source_guy: Node2D)
signal chaos_particle_despawned(particle: Node2D)
signal chaos_level_changed(particle_count: int, messiness_ratio: float)
signal messiness_threshold_warning(current: float, threshold: float)
signal messiness_threshold_exceeded()  # Failure trigger

# =============================================================================
# SCORING
# =============================================================================
signal score_points_added(amount: int, reason: String, multiplier: float)
signal score_penalty_applied(amount: int, reason: String)
signal score_multiplier_changed(old_value: float, new_value: float)
signal score_round_tallied(round_score: int, stars_earned: int, breakdown: Dictionary)
signal score_total_updated(new_total: int)

# =============================================================================
# STAR ECONOMY & PARAMETERIZATION
# =============================================================================
signal stars_earned(amount: int, total: int)
signal stars_spent(amount: int, remaining: int, upgrade_id: String)
signal upgrade_purchased(upgrade_id: String, category: String)
signal upgrade_preview_requested(upgrade_id: String)

# =============================================================================
# UI & FEEDBACK
# =============================================================================
signal ui_popup_requested(message: String, position: Vector2, type: String)
signal ui_narrator_line(text: String, mood: String)
signal ui_screen_shake(intensity: float, duration: float)
signal ui_flash(color: Color, duration: float)
signal ui_panel_opened(panel_id: String)
signal ui_panel_closed(panel_id: String)

# =============================================================================
# AUDIO
# =============================================================================
signal audio_sfx_requested(sfx_id: String, position: Vector2)
signal audio_music_layer_add(layer_id: String)
signal audio_music_layer_remove(layer_id: String)
signal audio_music_tempo_change(new_bpm: float)

# =============================================================================
# GAME STATE
# =============================================================================
signal game_started()
signal game_paused()
signal game_resumed()
signal game_over(final_score: int, rounds_completed: int)
signal endless_mode_unlocked()

# =============================================================================
# SUBSCRIPTION SYSTEM (matches Library Science pattern)
# =============================================================================
var _subscriptions: Dictionary = {}

## Publish an event with optional payload, bridging to typed signals
func publish(event_name: String, payload := {}) -> void:
	emit_signal("event", event_name, payload)
	
	if DEBUG_EVENTS:
		print("[SIGNAL] %s: %s" % [event_name, payload])
	
	# Bridge to typed signals
	match event_name:
		# Round lifecycle
		"round.setup.started":
			round_setup_started.emit(payload.get("round_number", 0))
		"round.active.started":
			round_active_started.emit(payload.get("round_number", 0))
		"round.timer.tick":
			round_timer_tick.emit(
				payload.get("time_remaining", 0.0),
				payload.get("time_total", 0.0))
		"round.ended":
			round_ended.emit(
				payload.get("round_number", 0),
				payload.get("result", ""))
		"round.param.started":
			round_parameterization_started.emit(payload.get("round_number", 0))
		"round.param.ended":
			round_parameterization_ended.emit(payload.get("round_number", 0))
		
		# Player
		"player.moved":
			player_moved.emit(payload.get("position", Vector2.ZERO))
		"player.thing.picked_up":
			player_thing_picked_up.emit(
				payload.get("thing", null),
				payload.get("stack_size", 0))
		"player.thing.dropped":
			player_thing_dropped.emit(
				payload.get("thing", null),
				payload.get("into_box", false))
		"player.stack.changed":
			player_stack_changed.emit(payload.get("stack", []))
		
		# Things
		"thing.spawned":
			thing_spawned.emit(
				payload.get("thing", null),
				payload.get("thing_type_id", ""))
		"thing.picked_up":
			thing_picked_up.emit(
				payload.get("thing", null),
				payload.get("by_player", false),
				payload.get("by_guy", null))
		"thing.dropped":
			thing_dropped.emit(
				payload.get("thing", null),
				payload.get("position", Vector2.ZERO))
		"thing.returned":
			thing_returned_to_box.emit(
				payload.get("thing", null),
				payload.get("box", null))
		"thing.scattered":
			thing_scattered.emit(
				payload.get("thing", null),
				payload.get("from_box", null),
				payload.get("by_guy", null))
		
		# Boxes
		"box.spawned":
			box_spawned.emit(
				payload.get("box", null),
				payload.get("thing_type_id", ""))
		"box.thing.added":
			box_thing_added.emit(
				payload.get("box", null),
				payload.get("thing", null),
				payload.get("count", 0))
		"box.thing.removed":
			box_thing_removed.emit(
				payload.get("box", null),
				payload.get("thing", null),
				payload.get("count", 0))
		"box.emptied":
			box_emptied.emit(payload.get("box", null))
		"box.restocked":
			box_restocked.emit(payload.get("box", null))
		
		# Guys
		"guy.spawned":
			guy_spawned.emit(
				payload.get("guy", null),
				payload.get("guy_type_id", ""))
		"guy.targeting":
			guy_targeting_box.emit(
				payload.get("guy", null),
				payload.get("box", null))
		"guy.reached_box":
			guy_reached_box.emit(
				payload.get("guy", null),
				payload.get("box", null))
		"guy.took_thing":
			guy_took_thing.emit(
				payload.get("guy", null),
				payload.get("thing", null),
				payload.get("box", null))
		"guy.dropped_thing":
			guy_dropped_thing.emit(
				payload.get("guy", null),
				payload.get("thing", null),
				payload.get("position", Vector2.ZERO))
		"guy.longing":
			guy_entered_longing.emit(
				payload.get("guy", null),
				payload.get("duration", 0.0))
		"guy.tantrum":
			guy_entered_tantrum.emit(payload.get("guy", null))
		"guy.left":
			guy_left_board.emit(payload.get("guy", null))
		"guy.despawned":
			guy_despawned.emit(payload.get("guy", null))
		
		# Chaos
		"chaos.particle.spawned":
			chaos_particle_spawned.emit(
				payload.get("particle", null),
				payload.get("source_guy", null))
		"chaos.particle.despawned":
			chaos_particle_despawned.emit(payload.get("particle", null))
		"chaos.level.changed":
			chaos_level_changed.emit(
				payload.get("particle_count", 0),
				payload.get("messiness_ratio", 0.0))
		"chaos.warning":
			messiness_threshold_warning.emit(
				payload.get("current", 0.0),
				payload.get("threshold", 0.0))
		"chaos.exceeded":
			messiness_threshold_exceeded.emit()
		
		# Scoring
		"score.points.added":
			if DEBUG_SCORING:
				print("[SCORE] +%d (%s) x%.1f" % [
					payload.get("amount", 0),
					payload.get("reason", ""),
					payload.get("multiplier", 1.0)])
			score_points_added.emit(
				payload.get("amount", 0),
				payload.get("reason", ""),
				payload.get("multiplier", 1.0))
		"score.penalty":
			if DEBUG_SCORING:
				print("[SCORE] -%d (%s)" % [
					payload.get("amount", 0),
					payload.get("reason", "")])
			score_penalty_applied.emit(
				payload.get("amount", 0),
				payload.get("reason", ""))
		"score.multiplier.changed":
			score_multiplier_changed.emit(
				payload.get("old_value", 1.0),
				payload.get("new_value", 1.0))
		"score.round.tallied":
			score_round_tallied.emit(
				payload.get("round_score", 0),
				payload.get("stars_earned", 0),
				payload.get("breakdown", {}))
		"score.total.updated":
			score_total_updated.emit(payload.get("new_total", 0))
		
		# Stars
		"stars.earned":
			stars_earned.emit(
				payload.get("amount", 0),
				payload.get("total", 0))
		"stars.spent":
			stars_spent.emit(
				payload.get("amount", 0),
				payload.get("remaining", 0),
				payload.get("upgrade_id", ""))
		"upgrade.purchased":
			upgrade_purchased.emit(
				payload.get("upgrade_id", ""),
				payload.get("category", ""))
		"upgrade.preview":
			upgrade_preview_requested.emit(payload.get("upgrade_id", ""))
		
		# UI
		"ui.popup":
			ui_popup_requested.emit(
				payload.get("message", ""),
				payload.get("position", Vector2.ZERO),
				payload.get("type", "info"))
		"ui.narrator":
			ui_narrator_line.emit(
				payload.get("text", ""),
				payload.get("mood", "neutral"))
		"ui.shake":
			ui_screen_shake.emit(
				payload.get("intensity", 1.0),
				payload.get("duration", 0.2))
		"ui.flash":
			ui_flash.emit(
				payload.get("color", Color.WHITE),
				payload.get("duration", 0.1))
		"ui.panel.opened":
			ui_panel_opened.emit(payload.get("panel_id", ""))
		"ui.panel.closed":
			ui_panel_closed.emit(payload.get("panel_id", ""))
		
		# Audio
		"audio.sfx":
			audio_sfx_requested.emit(
				payload.get("sfx_id", ""),
				payload.get("position", Vector2.ZERO))
		"audio.layer.add":
			audio_music_layer_add.emit(payload.get("layer_id", ""))
		"audio.layer.remove":
			audio_music_layer_remove.emit(payload.get("layer_id", ""))
		"audio.tempo":
			audio_music_tempo_change.emit(payload.get("new_bpm", 120.0))
		
		# Game state
		"game.started":
			game_started.emit()
		"game.paused":
			game_paused.emit()
		"game.resumed":
			game_resumed.emit()
		"game.over":
			game_over.emit(
				payload.get("final_score", 0),
				payload.get("rounds_completed", 0))
		"game.endless.unlocked":
			endless_mode_unlocked.emit()
	
	# Call dynamic subscriptions
	if _subscriptions.has(event_name):
		var subscribers = _subscriptions[event_name]
		for i in range(subscribers.size() - 1, -1, -1):
			var sub = subscribers[i]
			if not is_instance_valid(sub.subscriber):
				subscribers.remove_at(i)
				continue
			sub.callback.call(payload)


## Subscribe to events dynamically
func subscribe(event_name: String, callback: Callable, subscriber: Object = null) -> void:
	if not _subscriptions.has(event_name):
		_subscriptions[event_name] = []
	
	_subscriptions[event_name].append({
		"callback": callback,
		"subscriber": subscriber if subscriber else null
	})


## Unsubscribe a specific callback
func unsubscribe(event_name: String, callback: Callable) -> void:
	if not _subscriptions.has(event_name):
		return
	
	var subscribers = _subscriptions[event_name]
	for i in range(subscribers.size() - 1, -1, -1):
		if subscribers[i].callback == callback:
			subscribers.remove_at(i)
			break
	
	if subscribers.is_empty():
		_subscriptions.erase(event_name)


## Unsubscribe all callbacks from a subscriber
func unsubscribe_all(subscriber: Object) -> void:
	for event_name in _subscriptions.keys():
		var subscribers = _subscriptions[event_name]
		for i in range(subscribers.size() - 1, -1, -1):
			if subscribers[i].subscriber == subscriber:
				subscribers.remove_at(i)
		
		if subscribers.is_empty():
			_subscriptions.erase(event_name)