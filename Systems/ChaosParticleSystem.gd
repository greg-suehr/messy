extends Node2D
class_name ChaosParticleSystem
## ChaosParticleSystem - Manages chaos particles spawned by Guy tantrums
##
## Chaos particles accumulate on the board and contribute to the 
## messiness level. Too many particles triggers round failure.

# =============================================================================
# CONSTANTS
# =============================================================================
const PARTICLE_LIFETIME := 30.0  # Seconds before auto-despawn
const PARTICLE_SIZE := 8.0
const PARTICLE_COLORS := [
	Color("#FF69B4"),  # Hot pink
	Color("#00FFFF"),  # Cyan
	Color("#7FFF00"),  # Lime
	Color("#FFD700"),  # Gold
	Color("#FF7F50"),  # Coral
]

# =============================================================================
# STATE
# =============================================================================
var active_particles: Array = []  # Array of particle data dictionaries


# =============================================================================
# INITIALIZATION
# =============================================================================
func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	# Use subscribe pattern to get the full payload with position
	SignalBus.subscribe("chaos.particle.spawned", _on_chaos_spawn_event, self)


# =============================================================================
# PARTICLE MANAGEMENT
# =============================================================================
func spawn_particle(particle_position: Vector2, source_guy: Node2D = null) -> void:
	"""Spawn a new chaos particle at the given position."""
	var particle = {
		"position": particle_position,
		"velocity": Vector2(randf_range(-50, 50), randf_range(-50, 50)),
		"color": PARTICLE_COLORS[randi() % PARTICLE_COLORS.size()],
		"lifetime": PARTICLE_LIFETIME,
		"size": PARTICLE_SIZE * randf_range(0.5, 1.5),
		"rotation": randf() * TAU,
		"rotation_speed": randf_range(-2, 2),
	}
	
	active_particles.append(particle)
	
	# Notify game state
	SignalBus.publish("chaos.particle.spawned", {
		"particle": particle,
		"source_guy": source_guy,
		"position": particle_position
	})
	
	_update_chaos_level()
	queue_redraw()


func despawn_particle(index: int) -> void:
	"""Remove a particle by index."""
	if index >= 0 and index < active_particles.size():
		var particle = active_particles[index]
		active_particles.remove_at(index)
		
		SignalBus.publish("chaos.particle.despawned", {
			"particle": particle
		})
		
		_update_chaos_level()
		queue_redraw()


func clear_all_particles() -> void:
	"""Remove all particles."""
	active_particles.clear()
	_update_chaos_level()
	queue_redraw()


func _update_chaos_level() -> void:
	"""Notify game state of current chaos level."""
	var messiness = GameState.get_messiness_ratio()
	
	SignalBus.publish("chaos.level.changed", {
		"particle_count": active_particles.size(),
		"messiness_ratio": messiness
	})


# =============================================================================
# UPDATE
# =============================================================================
func _process(delta: float) -> void:
	if GameState.is_paused:
		return
	
	var particles_to_remove: Array[int] = []
	
	for i in range(active_particles.size()):
		var particle = active_particles[i]
		
		# Update lifetime
		particle.lifetime -= delta
		if particle.lifetime <= 0:
			particles_to_remove.append(i)
			continue
		
		# Update position with gentle drift
		particle.position += particle.velocity * delta
		particle.velocity *= 0.99  # Slow down over time
		
		# Update rotation
		particle.rotation += particle.rotation_speed * delta
	
	# Remove expired particles (reverse order to maintain indices)
	for i in range(particles_to_remove.size() - 1, -1, -1):
		despawn_particle(particles_to_remove[i])
	
	if not active_particles.is_empty():
		queue_redraw()


# =============================================================================
# DRAWING
# =============================================================================
func _draw() -> void:
	for particle in active_particles:
		var pos = particle.position
		var size = particle.size
		var color = particle.color
		var particle_rotation = particle.rotation
		
		# Fade out as lifetime decreases
		if particle.lifetime < 5.0:
			color.a = particle.lifetime / 5.0
		
		# Draw as rotated square/confetti
		var points: PackedVector2Array = []
		for j in range(4):
			var angle = particle_rotation + (j * PI / 2)
			points.append(pos + Vector2(cos(angle), sin(angle)) * size)
		
		draw_colored_polygon(points, color)


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_chaos_spawn_event(payload: Dictionary) -> void:
	"""Handle chaos particle spawn from SignalBus publish."""
	var particle_position = payload.get("position", Vector2.ZERO)
	var source_guy = payload.get("source_guy", null)
	spawn_particle(particle_position, source_guy)


# =============================================================================
# PUBLIC API
# =============================================================================
func get_particle_count() -> int:
	return active_particles.size()


func get_particles_near(particle_position: Vector2, radius: float) -> Array:
	var nearby: Array = []
	var radius_sq = radius * radius
	
	for particle in active_particles:
		if particle_position.distance_squared_to(particle.position) <= radius_sq:
			nearby.append(particle)
	
	return nearby
