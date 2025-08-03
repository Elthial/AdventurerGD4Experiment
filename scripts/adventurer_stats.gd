extends Resource

## AdventurerStats encapsulates HP, needs and related logic.
## It manages decay, threshold checks and restoration when needs are fulfilled.
class_name AdventurerStats

var hp : float = 100.0
var max_hp : float = 100.0
var stamina : float = 100.0
var morale : float = 100.0

var hunger : float = 100.0
var sleepiness : float = 100.0
var boredom : float = 100.0

const NEED_THRESHOLD : float = 30.0
const HEALTH_THRESHOLD : float = 50.0

## Applies decay to needs each frame. The caller provides the current state
## so the decay rate can vary for travel and dungeon activities.
func decay(delta : float, state : int) -> void:
        var base_decay := delta * 2.0
        sleepiness -= base_decay * 0.5
        var hunger_multiplier := 1.0
        if state == Adventurer.AdventurerState.TRAVEL or state == Adventurer.AdventurerState.DUNGEON:
                hunger_multiplier = 2.0
        hunger -= base_decay * hunger_multiplier
        var boredom_multiplier := 1.5
        if state == Adventurer.AdventurerState.DUNGEON:
                boredom_multiplier = 0.5
        boredom -= base_decay * boredom_multiplier
        _clamp_values()

## Returns the highest priority need that should be satisfied.
func get_low_need() -> String:
        if hp <= HEALTH_THRESHOLD:
                return "heal"
        elif hunger <= NEED_THRESHOLD:
                return "eat"
        elif sleepiness <= NEED_THRESHOLD:
                return "sleep"
        elif boredom <= NEED_THRESHOLD:
                return "entertain"
        return ""

## Restores stats after finishing a need.
func restore_need(type : String) -> void:
        match type:
                "sleep":
                        stamina = 100.0
                        sleepiness = 100.0
                "eat":
                        stamina = 100.0
                        hunger = 100.0
                "entertain":
                        morale = 100.0
                        boredom = 100.0
                "heal":
                        hp = max_hp
        _clamp_values()

## Ensures needs and HP remain in valid ranges.
func _clamp_values() -> void:
        hunger = clamp(hunger, 0.0, 100.0)
        sleepiness = clamp(sleepiness, 0.0, 100.0)
        boredom = clamp(boredom, 0.0, 100.0)
        hp = clamp(hp, 0.0, max_hp)
