extends Node

## DungeonRun handles the progress and escape logic for an adventurer.
## Each level is defined by travel_time (seconds to cross), spawn_probability
## (chance per second for a monster spawn) and monster_damage (damage dealt
## by a monster hit).  Progress is represented as a value from 0.0 to 1.0.

class_name DungeonRun

var levels : Array = []
var current_level_index : int = 0
var progress : float = 0.0
var exiting : bool = false
var finished : bool = false

# Internal timers for spawn checks
var spawn_timer : float = 0.0

func _init(level_data : Array = []) -> void:
	levels = level_data
	current_level_index = 0
	progress = 0.0
	exiting = false
	finished = false

func update(delta : float, adventurer : Object) -> void:
	if finished:
		return
	# Check if we need to exit early due to low HP
	if adventurer.hp < adventurer.max_hp * 0.3:
		exiting = true
	var level = levels[current_level_index]
	# Advance progress deeper into the level
	progress += delta / level.travel_time
	spawn_timer += delta
	if spawn_timer >= 1.0:
		spawn_timer = 0.0
		# spawn monsters based on probability
		var roll = randf()
		if roll < level.spawn_probability:
			# Apply damage from spawned monsters
			adventurer.hp -= level.monster_damage
	# If we reach the end of the level
	if progress >= 1.0:
		progress = 0.0
		current_level_index += 1
		if current_level_index >= levels.size():
			# No more levels; automatically exit
			exiting = true
			current_level_index = levels.size() - 1

func update_escape(delta : float, adventurer : Object) -> void:
	if finished:
		return
	var level = levels[current_level_index]
	progress -= delta / level.travel_time
	spawn_timer += delta
	if spawn_timer >= 1.5:
		spawn_timer = 0.0
		var roll = randf()
		if roll < level.spawn_probability * 0.5:
			adventurer.hp -= level.monster_damage
	if progress <= 0.0:
		# Move up a level
		current_level_index -= 1
		if current_level_index < 0:
			# Escaped to surface
			finished = true
			return
		progress = 1.0
