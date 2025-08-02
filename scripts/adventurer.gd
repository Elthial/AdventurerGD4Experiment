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

# Adventurer stats
var hp : float = 100.0
var max_hp : float = 100.0
var stamina : float = 100.0
var morale : float = 100.0

## Name of this adventurer. Set by the spawner for debugging.
## Use a unique property name (adname) instead of 'name' because Node2D
## already defines a 'name' property.  Redeclaring 'name' would cause
## runtime errors.  'adname' stores the adventurer's display name for
## debugging and UI purposes.
var adname : String = "Adventurer"

## Position of the familia home base (HQ). Used when returning from dungeon.
var home_base_pos : Vector2 = Vector2.ZERO

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

func _physics_process(delta : float) -> void:
    # Print debug information roughly once per second
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
        # Print the adventurer's display name (adname) instead of the Node2D
        # built-in name property to avoid conflicts.
        print("%s | Pos: %s | State: %s | HP: %.1f" % [adname, global_position, state_str, hp])

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
    var dir : Vector2 = target_position - global_position
    var distance : float = dir.length()
    if distance > 5.0:
        dir = dir.normalized()
        global_position += dir * speed * delta
    else:
        _arrive_at_destination()

func _arrive_at_destination() -> void:
    # Placeholder for arrival logic. In a full game this would trigger a callback
    # to CityScene or another controller to decide the next state.
    # For the prototype we'll just idle.
    state = AdventurerState.NEED
    # default: rest for 2 seconds to demonstrate need fulfilment
    need_type = "sleep"
    need_timer = 2.0

func _update_need(delta : float) -> void:
    if need_timer > 0.0:
        need_timer -= delta
    else:
        _finish_need()

func _finish_need() -> void:
    # Restore stats depending on the need fulfilled
    match need_type:
        "sleep":
            hp = max_hp
            stamina = 100.0
        "eat":
            stamina = 100.0
        "entertain":
            morale = 100.0
    need_type = ""
    # After finishing a need we'll return to travel state and await new orders
    state = AdventurerState.TRAVEL

func _update_dungeon(delta : float) -> void:
    if dungeon_run:
        dungeon_run.update(delta, self)
        # If the dungeon_run requests exiting, change state
        if dungeon_run.exiting:
            state = AdventurerState.ESCAPE

func _update_escape(delta : float) -> void:
    if dungeon_run:
        dungeon_run.update_escape(delta, self)
        if dungeon_run.finished:
            # Finished returning from the dungeon
            dungeon_run = null
            # Set the state back to travel and head home
            state = AdventurerState.TRAVEL
            set_travel(home_base_pos)

