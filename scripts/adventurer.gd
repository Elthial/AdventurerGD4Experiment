extends Node2D

## Adventurer state machine for Danmachi prototype.
## Each adventurer can travel, fulfil a need, progress through the dungeon or escape.

class_name Adventurer

enum AdventurerState { TRAVEL, NEED, DUNGEON, ESCAPE }

var state : AdventurerState = AdventurerState.TRAVEL
var target_position : Vector2 = Vector2.ZERO
var speed : float = 100.0

# Need handling
var need_type : String = ""
var need_timer : float = 0.0

# Dungeon run instance
var dungeon_run : DungeonRun = null

# Encapsulated stats and needs
var stats : AdventurerStats = AdventurerStats.new()

const NEED_DURATIONS = {
        "heal": 6.0,
        "eat": 3.0,
        "sleep": 5.0,
        "entertain": 4.0
}

## Name of this adventurer. Set by the spawner for debugging.
## Use a unique property name (adname) instead of 'name' because Node2D
## already defines a 'name' property.  Redeclaring 'name' would cause
## runtime errors.  'adname' stores the adventurer's display name for
## debugging and UI purposes.
var adname : String = "Adventurer"

## Additional needs for the adventurer are stored in the stats object.

## Pending need and duration used when navigating to a service location.
var pending_need_type : String = ""
var pending_need_duration : float = 0.0

## Position of the familia home base (HQ). Used when returning from dungeon.
var home_base_pos : Vector2 = Vector2.ZERO
var dungeon_pos : Vector2 = Vector2.ZERO

## References to world locations supplied by the spawner (CityScene).  The
## adventurer uses these positions to travel when satisfying needs.  Set
## these after instantiation.
var inn_pos : Vector2 = Vector2.ZERO
var healer_pos : Vector2 = Vector2.ZERO
var blacksmith_pos : Vector2 = Vector2.ZERO

## Signal emitted whenever the adventurer outputs debug information.  The
## CityScene listens to this signal and appends messages to its console.
signal debug_output(message : String)


## Timer used to throttle debug output to the console.
var _debug_timer : float = 0.0

func _ready() -> void:
	# Ensure our sprite is centered on the node
	pass

func set_travel(destination : Vector2) -> void:
	state = AdventurerState.TRAVEL
	target_position = destination

func set_need(type : String, duration : float) -> void:
	state = AdventurerState.NEED
	need_type = type
	need_timer = duration

func start_dungeon_run(run : DungeonRun) -> void:
		state = AdventurerState.DUNGEON
		dungeon_run = run
		# Lock the adventurer to the dungeon entrance
		position = dungeon_pos
		target_position = dungeon_pos

func _physics_process(delta : float) -> void:
        # Update needs and check if any require satisfaction.
        stats.decay(delta, state)

        if state == AdventurerState.TRAVEL and pending_need_type == "" and need_type == "":
                var low_need := stats.get_low_need()
                if low_need != "":
                        _seek_need(low_need, NEED_DURATIONS[low_need])

	# Debug output roughly once per second
	_debug_timer += delta
	if _debug_timer > 1.0:
		_debug_timer = 0.0
		# Convert state enum to string for readability
		var state_str := ""
		match state:
			AdventurerState.TRAVEL:
				state_str = "TRAVEL"
			AdventurerState.NEED:
				state_str = "NEED"
			AdventurerState.DUNGEON:
				state_str = "DUNGEON"
			AdventurerState.ESCAPE:
				state_str = "ESCAPE"
			_:
				state_str = str(state)
		
                var msg := "%s | Pos: %s | State: %s | HP: %.1f | Hunger: %.0f | Sleep: %.0f | Boredom: %.0f" % [adname, position.round(), state_str, stats.hp, stats.hunger, stats.sleepiness, stats.boredom]
		print(msg)
		emit_signal("debug_output", msg)

	match state:
		AdventurerState.TRAVEL:
			_update_travel(delta)
		AdventurerState.NEED:
			_update_need(delta)
		AdventurerState.DUNGEON:
			_update_dungeon(delta)
		AdventurerState.ESCAPE:
			_update_escape(delta)

func _update_travel(delta : float) -> void:
		var dir : Vector2 = target_position - position
		var distance : float = dir.length()
		if distance > 5.0:
				dir = dir.normalized()
				position += dir * speed * delta
		else:
				_arrive_at_destination()

func _arrive_at_destination() -> void:
	# Called when the adventurer reaches its travel destination.  If a
	# pending need has been set (via _seek_need), transition into the
	# NEED state using the pending type and duration.  Otherwise fall
	# back to a default short rest.
	if pending_need_type != "":
		set_need(pending_need_type, pending_need_duration)
		pending_need_type = ""
		pending_need_duration = 0.0
	else:
		# Default: rest for 2 seconds to demonstrate need fulfilment
		set_need("sleep", 2.0)

func _update_need(delta : float) -> void:
	if need_timer > 0.0:
		need_timer -= delta
	else:
		_finish_need()

func _finish_need() -> void:
        stats.restore_need(need_type)
        need_type = ""
        # After finishing a need we'll return to travel state and await new orders
        state = AdventurerState.TRAVEL

func _update_dungeon(delta : float) -> void:
	if dungeon_run:
		# Remain fixed at the dungeon position during the run
		position = dungeon_pos
		dungeon_run.update(delta, self)
		# If the dungeon_run requests exiting, change state
		if dungeon_run.exiting:
			state = AdventurerState.ESCAPE

func _update_escape(delta : float) -> void:
	if dungeon_run:
		# Stay locked to the dungeon until the escape finishes
		position = dungeon_pos
		dungeon_run.update_escape(delta, self)
		if dungeon_run.finished:
			# Finished returning from the dungeon
			dungeon_run = null
			# Set the state back to travel and head home
			state = AdventurerState.TRAVEL
			set_travel(home_base_pos)

## Internal helper used to initiate travelling to satisfy a need.  The
## destination and duration depend on the need type.  This sets
## pending_need_type and pending_need_duration, then calls set_travel() to
## move the adventurer.  The actual need will be processed in
## _arrive_at_destination().
func _seek_need(type : String, duration : float) -> void:
	var dest : Vector2 = position
	match type:
		"sleep":
			dest = home_base_pos
		"eat":
			dest = inn_pos
		"entertain":
			dest = blacksmith_pos
		"heal":
			dest = healer_pos
		_:
			dest = home_base_pos
	pending_need_type = type
	pending_need_duration = duration
	set_travel(dest)
