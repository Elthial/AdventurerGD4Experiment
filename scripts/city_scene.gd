extends Node2D

## CityScene spawns adventurers and assigns them tasks.  For the MVP it
## demonstrates the TravelTo and dungeon state transitions.

@onready var adv_container = $"CityScene#Adventurers"
@onready var map_sprite = $"CityScene#Map"

# Preload the dot texture used for icons
var DotTexture : Texture2D = preload("res://assets/dot.png")

# Define key locations on the map.  Coordinates are in pixel space relative to
# the 1024x1024 map texture.  These were chosen to roughly align with
# distinct districts and landmarks visible on the map.  Feel free to tweak
# them later.
const HQ_POS : Vector2 = Vector2(180, 770)
const DUNGEON_POS : Vector2 = Vector2(512, 512)
const HEALER_POS : Vector2 = Vector2(700, 300)
const BLACKSMITH_POS : Vector2 = Vector2(820, 650)
const INN_POS : Vector2 = Vector2(300, 300)

# Colours for the different service icons.  These will modulate the dot
# texture to produce distinct coloured markers on the map.
const ICON_COLOURS = {
    "hq": Color(0.0, 1.0, 0.0),          # green
    "dungeon": Color(0.8, 0.2, 0.8),    # purple
    "healer": Color(0.2, 0.6, 1.0),     # blue
    "blacksmith": Color(1.0, 0.6, 0.0), # orange
    "inn": Color(1.0, 0.8, 0.0)         # yellow
}

# Preload scenes and runs
var AdventurerScene : PackedScene = preload("res://scenes/adventurer.tscn")

## Helper that creates a coloured dot at a given position on the map.  Uses
## the preloaded DotTexture and modulates its colour.  The icons are added
## directly under CityScene so they appear above the map but below
## adventurers.
func _create_icon(pos : Vector2, colour : Color) -> void:
    var icon := Sprite2D.new()
    icon.texture = DotTexture
    icon.modulate = colour
    # Centre the icon on the map by offsetting by half its size
    icon.offset = Vector2.ZERO
    icon.position = pos
    add_child(icon)

func _ready() -> void:
    # Centre the map on the screen so that the entire image is visible.
    # We set its position to the centre of the viewport.  Because the
    # Sprite2D is centred by default, this will align the map nicely.
    if map_sprite:
        map_sprite.position = get_viewport_rect().size * 0.5

    # Create service icons on the map.  Colours are defined in ICON_COLOURS.
    _create_icon(HQ_POS, ICON_COLOURS["hq"])
    _create_icon(DUNGEON_POS, ICON_COLOURS["dungeon"])
    _create_icon(HEALER_POS, ICON_COLOURS["healer"])
    _create_icon(BLACKSMITH_POS, ICON_COLOURS["blacksmith"])
    _create_icon(INN_POS, ICON_COLOURS["inn"])

    # Spawn an adventurer at the HQ.  Give them a name and set their home
    # base so they know where to return after a dungeon run.
    var adv := AdventurerScene.instantiate()
    adv.global_position = HQ_POS
    # Assign a display name to the adventurer.  Use the 'adname' property
    # rather than 'name' because Node2D already defines a 'name' property.
    adv.adname = "Bell"  # placeholder name
    adv.home_base_pos = HQ_POS
    adv_container.add_child(adv)

    # Prepare a simple dungeon run description.  Additional levels can be
    # appended to this array to make runs longer and more challenging.
    var level_data := [
        {"travel_time": 10.0, "spawn_probability": 0.3, "monster_damage": 5.0},
        {"travel_time": 12.0, "spawn_probability": 0.5, "monster_damage": 8.0}
    ]
    var run := DungeonRun.new(level_data)

    # Kick off the dungeon cycle asynchronously.  The adventurer will travel
    # to the dungeon, run it, and then return home.  Because this is an
    # asynchronous function we don't need to await it here unless we want to
    # wait for completion.
    run_dungeon_cycle(adv, run)

func _process(delta : float) -> void:
    # Additional game logic and UI updates would go here.
    pass

## Coroutine that handles an adventurer travelling to the dungeon, running it
## and then returning home.  It waits until the adventurer reaches the
## destination before starting the dungeon run, and waits until the run is
## complete before sending the adventurer back to HQ.  This function runs
## asynchronously and does not block the main thread.
@warning_ignore("unused_parameter")
func run_dungeon_cycle(adv : Adventurer, run : DungeonRun) -> void:
    # Travel to the dungeon entrance
    adv.set_travel(DUNGEON_POS)
    # Wait until the adventurer is close to the dungeon
    while adv.global_position.distance_to(DUNGEON_POS) > 5.0:
        await get_tree().process_frame
    # Start the dungeon run
    adv.start_dungeon_run(run)
    # Wait while the adventurer is inside the dungeon or escaping
    while adv.state == Adventurer.AdventurerState.DUNGEON or adv.state == Adventurer.AdventurerState.ESCAPE:
        await get_tree().process_frame
    # Travel back home
    adv.set_travel(HQ_POS)
    while adv.global_position.distance_to(HQ_POS) > 5.0:
        await get_tree().process_frame
    # At this point the adventurer has completed the cycle.  Additional
    # behaviour (such as assigning a new task) could be triggered here.

