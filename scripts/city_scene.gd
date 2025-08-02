extends Node2D

## CityScene spawns adventurers and assigns them tasks.  For the MVP it
## demonstrates the TravelTo and dungeon state transitions.

@onready var adv_container = $Adventurers
@onready var map_sprite = $Map

# Preload scenes and runs
var AdventurerScene : PackedScene = preload("res://scenes/adventurer.tscn")

func _ready() -> void:
	# Spawn a test adventurer at a fixed position
	var adv = AdventurerScene.instantiate()
	adv.global_position = Vector2(200, 300)
	adv_container.add_child(adv)
	# Assign a simple dungeon run after a short delay
	await get_tree().create_timer(1.0).timeout
	var level_data = [
		{"travel_time": 10.0, "spawn_probability": 0.3, "monster_damage": 5.0},
		{"travel_time": 12.0, "spawn_probability": 0.5, "monster_damage": 8.0}
	]
	var run = DungeonRun.new(level_data)
	adv.start_dungeon_run(run)

func _process(delta : float) -> void:
	# Additional game logic and UI updates would go here.
	pass
