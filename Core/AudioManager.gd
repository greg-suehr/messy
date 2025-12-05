extends Node
## AudioManager - Dynamic audio system for Messy
##
## Handles the layered music system with tempo changes based on chaos level,
## plus positional SFX for game events.

# =============================================================================
# CONSTANTS
# =============================================================================
const BASE_BPM := 125.0
const MAX_BPM := 160.0
const BETWEEN_ROUNDS_BPM := 85.0

# Layer IDs (from GDD)
const LAYER_AMBIENT := "ambient_pad"
const LAYER_KICK := "kick_drum"
const LAYER_CHIME := "chime_melody"
const LAYER_BASS := "synth_bass"
const LAYER_PLUCKY := "plucky_stabs"
const LAYER_GLITCH := "glitch_texture"

# =============================================================================
# STATE
# =============================================================================
var _current_bpm := BASE_BPM
var _target_bpm := BASE_BPM
var _active_layers: Array[String] = []
var _music_players: Dictionary = {}  # layer_id -> AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_size := 8

# Chaos level thresholds for layer activation
var _layer_thresholds: Dictionary = {
	LAYER_AMBIENT: 0,     # Always on
	LAYER_KICK: 0,        # Always on (base layer)
	LAYER_CHIME: 1,       # First guy spawns
	LAYER_BASS: 1,        # First guy spawns
	LAYER_PLUCKY: 2,      # 2+ guys on board
	LAYER_GLITCH: 3,      # 3+ chaos particles
}

# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_setup_sfx_pool()
	_connect_signals()


func _setup_sfx_pool() -> void:
	for i in range(_sfx_pool_size):
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_pool.append(player)


func _connect_signals() -> void:
	SignalBus.audio_sfx_requested.connect(_on_sfx_requested)
	SignalBus.audio_music_layer_add.connect(_on_layer_add)
	SignalBus.audio_music_layer_remove.connect(_on_layer_remove)
	SignalBus.audio_music_tempo_change.connect(_on_tempo_change)
	
	# Automatic layer management based on game events
	SignalBus.round_active_started.connect(_on_round_started)
	SignalBus.round_ended.connect(_on_round_ended)
	SignalBus.guy_spawned.connect(_on_guy_spawned)
	SignalBus.chaos_level_changed.connect(_on_chaos_changed)
	SignalBus.round_parameterization_started.connect(_on_parameterization_started)


# =============================================================================
# MUSIC LAYER MANAGEMENT
# =============================================================================
func add_layer(layer_id: String) -> void:
	if layer_id in _active_layers:
		return
	
	_active_layers.append(layer_id)
	
	if _music_players.has(layer_id):
		var player = _music_players[layer_id]
		# Fade in
		var tween = create_tween()
		tween.tween_property(player, "volume_db", 0.0, 0.5).from(-40.0)
		player.play()


func remove_layer(layer_id: String) -> void:
	if layer_id not in _active_layers:
		return
	
	_active_layers.erase(layer_id)
	
	if _music_players.has(layer_id):
		var player = _music_players[layer_id]
		# Fade out
		var tween = create_tween()
		tween.tween_property(player, "volume_db", -40.0, 0.3)
		tween.tween_callback(player.stop)


func set_all_layers_active(layers: Array[String]) -> void:
	# Remove layers not in new set
	for layer in _active_layers.duplicate():
		if layer not in layers:
			remove_layer(layer)
	
	# Add new layers
	for layer in layers:
		add_layer(layer)


# =============================================================================
# TEMPO MANAGEMENT
# =============================================================================
func set_tempo(bpm: float, immediate := false) -> void:
	_target_bpm = clampf(bpm, BETWEEN_ROUNDS_BPM, MAX_BPM)
	
	if immediate:
		_current_bpm = _target_bpm
		_apply_tempo()


func _process(delta: float) -> void:
	# Smoothly interpolate toward target BPM
	if abs(_current_bpm - _target_bpm) > 0.5:
		_current_bpm = lerpf(_current_bpm, _target_bpm, delta * 2.0)
		_apply_tempo()


func _apply_tempo() -> void:
	# Adjust pitch scale of all music layers based on BPM ratio
	var pitch_scale = _current_bpm / BASE_BPM
	
	for player in _music_players.values():
		player.pitch_scale = pitch_scale


# =============================================================================
# SFX PLAYBACK
# =============================================================================
func play_sfx(sfx_id: String, _position := Vector2.ZERO) -> void:
	var stream = _get_sfx_stream(sfx_id)
	if stream == null:
		return
	
	var player = _get_available_sfx_player()
	if player == null:
		return
	
	player.stream = stream
	player.play()


func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	# All busy - return oldest (it will be interrupted)
	return _sfx_pool[0]


func _get_sfx_stream(sfx_id: String) -> AudioStream:
	# TODO: Load from resources
	# For now, return null (no audio files yet)
	var path = "res://assets/audio/sfx_%s.wav" % sfx_id
	if ResourceLoader.exists(path):
		return load(path)
	return null


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_sfx_requested(sfx_id: String, position: Vector2) -> void:
	play_sfx(sfx_id, position)


func _on_layer_add(layer_id: String) -> void:
	add_layer(layer_id)


func _on_layer_remove(layer_id: String) -> void:
	remove_layer(layer_id)


func _on_tempo_change(new_bpm: float) -> void:
	set_tempo(new_bpm)


func _on_round_started(_round_number: int) -> void:
	# Start with base layers
	set_tempo(BASE_BPM, true)
	set_all_layers_active([LAYER_AMBIENT, LAYER_KICK])


func _on_round_ended(_round_number: int, _result: String) -> void:
	# Keep ambient, fade others
	set_all_layers_active([LAYER_AMBIENT])
	set_tempo(BETWEEN_ROUNDS_BPM)


func _on_parameterization_started(_round_number: int) -> void:
	set_all_layers_active([LAYER_AMBIENT])
	set_tempo(BETWEEN_ROUNDS_BPM)


func _on_guy_spawned(_guy: Node2D, _guy_type_id: String) -> void:
	# Add melodic layers when guys spawn
	if LAYER_CHIME not in _active_layers:
		add_layer(LAYER_CHIME)
		add_layer(LAYER_BASS)


func _on_chaos_changed(particle_count: int, messiness_ratio: float) -> void:
	# Add complexity layers based on chaos
	if particle_count >= 3 and LAYER_GLITCH not in _active_layers:
		add_layer(LAYER_GLITCH)
	elif particle_count < 2 and LAYER_GLITCH in _active_layers:
		remove_layer(LAYER_GLITCH)
	
	# Increase tempo with messiness
	var tempo_range = MAX_BPM - BASE_BPM
	var new_bpm = BASE_BPM + (messiness_ratio * tempo_range)
	set_tempo(new_bpm)


# =============================================================================
# MUSIC INITIALIZATION (call when audio files are ready)
# =============================================================================
func initialize_music_layers(layer_streams: Dictionary) -> void:
	"""
	Initialize music players with audio streams.
	layer_streams: Dictionary mapping layer_id -> AudioStream
	"""
	for layer_id in layer_streams.keys():
		var stream = layer_streams[layer_id]
		var player = AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "Music"
		player.volume_db = -40.0  # Start silent
		add_child(player)
		_music_players[layer_id] = player
