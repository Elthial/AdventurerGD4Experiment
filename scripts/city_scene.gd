extends Node2D

## CityScene spawns adventurers and assigns them tasks.  For the MVP it
## demonstrates the TravelTo and dungeon state transitions.

@onready var adv_container = $"CityScene#Adventurers"
@onready var map_sprite = $"CityScene#Map"

## Nodes created in code for UI and scaling
var map_container : Node2D
var top_bar : Control
var console_label : RichTextLabel
var tooltip_label : Label

## Zoom parameters
var min_zoom : float = 1.0
var max_zoom : float = 1.0
var current_zoom : float = 1.0

## Game time variables
var game_time_seconds : float = 0.0
var day_counter : int = 1
var money : int = 0

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
## Creates a small icon at a given map position.  This uses an Area2D
## with a circular collision shape so that mouse hover events can be
## detected.  When the mouse enters the icon area, the tooltip is
## displayed with the location's name.
func _create_location_icon(name : String, pos : Vector2, colour : Color) -> void:
    # Area2D to detect mouse hover
    var area := Area2D.new()
    area.position = pos
    # Sprite to display the dot
    var sprite := Sprite2D.new()
    sprite.texture = DotTexture
    sprite.modulate = colour
    area.add_child(sprite)
    # Collision shape for hover detection
    var shape := CircleShape2D.new()
    shape.radius = DotTexture.get_width() * 0.5
    var coll := CollisionShape2D.new()
    coll.shape = shape
    area.add_child(coll)
    # Connect signals for tooltip
    area.connect("mouse_entered", Callable(self, "_on_icon_mouse_entered").bind(name))
    area.connect("mouse_exited", Callable(self, "_on_icon_mouse_exited"))
    # Add to map container so it scales with the map
    map_container.add_child(area)

func _ready() -> void:
    # Create a container for the map and its overlays (adventurers and icons).
    map_container = Node2D.new()
    add_child(map_container)
    # Reparent the map sprite and adventurer container into the map container
    if map_sprite:
        map_sprite.get_parent().remove_child(map_sprite)
        map_container.add_child(map_sprite)
    if adv_container:
        adv_container.get_parent().remove_child(adv_container)
        map_container.add_child(adv_container)

    # Compute the minimum zoom so that the map fits entirely within the viewport.
    var view_size := get_viewport_rect().size
    var map_size := map_sprite.texture.get_size()
    min_zoom = min(view_size.x / map_size.x, view_size.y / map_size.y)
    max_zoom = 1.0
    current_zoom = min_zoom
    _update_map_zoom()

    # Create UI elements: top bar, tooltip and console.
    _create_top_bar()
    _create_tooltip()
    _create_console()

    # Create service icons with tooltips and add them to the map container.
    _create_location_icon("HQ", HQ_POS, ICON_COLOURS["hq"])
    _create_location_icon("Dungeon", DUNGEON_POS, ICON_COLOURS["dungeon"])
    _create_location_icon("Healer", HEALER_POS, ICON_COLOURS["healer"])
    _create_location_icon("Blacksmith", BLACKSMITH_POS, ICON_COLOURS["blacksmith"])
    _create_location_icon("Inn", INN_POS, ICON_COLOURS["inn"])

    # Spawn an adventurer at the HQ.  Set its home and service locations.
    var adv : Adventurer = AdventurerScene.instantiate()
    adv.global_position = HQ_POS
    adv.adname = "Bell"  # placeholder name
    adv.home_base_pos = HQ_POS
    adv.inn_pos = INN_POS
    adv.healer_pos = HEALER_POS
    adv.blacksmith_pos = BLACKSMITH_POS
    adv_container.add_child(adv)
    # Connect the adventurer's debug output signal to our console handler.
    adv.connect("debug_output", Callable(self, "_on_adventurer_debug"))

    # Prepare a simple dungeon run description.  Additional levels can be appended.
    var level_data := [
        {"travel_time": 10.0, "spawn_probability": 0.3, "monster_damage": 5.0},
        {"travel_time": 12.0, "spawn_probability": 0.5, "monster_damage": 8.0}
    ]
    var run := DungeonRun.new(level_data)
    # Kick off the dungeon cycle.  We don't await it here.
    run_dungeon_cycle(adv, run)

func _process(delta : float) -> void:
    # Advance in-game time.  Five minutes of real time equals 24 hours in game.
    # There are 300 seconds in five minutes.  Each second corresponds to 24/300 hours.
    var hours_per_second := 24.0 / 300.0
    game_time_seconds += delta * 3600.0 * hours_per_second
    # Increment day counter and wrap hours
    if game_time_seconds >= 86400.0:
        game_time_seconds -= 86400.0
        day_counter += 1
    # Update the top bar status label
    _update_status_label()

    # Additional game logic and UI updates would go here.

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

## Updates the scale and position of the map container based on the current
## zoom level.  This ensures the map fills the viewport appropriately.
func _update_map_zoom() -> void:
    if not map_sprite or not map_container:
        return
    # Apply uniform scale to the container
    map_container.scale = Vector2(current_zoom, current_zoom)
    # Compute scaled map size and center it within the viewport
    var view_size := get_viewport_rect().size
    var map_size := map_sprite.texture.get_size() * current_zoom
    # Position container so that the map is centered
    map_container.position = view_size * 0.5 - map_size * 0.5

## Creates the top bar UI displaying familia name, log placeholder, in-game time and money.
func _create_top_bar() -> void:
    top_bar = PanelContainer.new()
    top_bar.name = "TopBar"
    top_bar.anchor_left = 0.0
    top_bar.anchor_top = 0.0
    top_bar.anchor_right = 1.0
    top_bar.anchor_bottom = 0.0
    top_bar.offset_left = 0.0
    top_bar.offset_top = 0.0
    top_bar.offset_right = 0.0
    top_bar.offset_bottom = 40.0
    add_child(top_bar)
    var hbox := HBoxContainer.new()
    hbox.name = "HBoxContainer"
    hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hbox.anchor_left = 0
    hbox.anchor_right = 1
    hbox.offset_right = 0
    top_bar.add_child(hbox)
    # Left section: familia name and log placeholder
    var left_label := Label.new()
    left_label.text = "Hestia Familia"
    left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hbox.add_child(left_label)
    # Right section: status label (time and money)
    var status_label := Label.new()
    status_label.name = "StatusLabel"
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hbox.add_child(status_label)

## Creates a tooltip label used to display location names when hovering icons.
func _create_tooltip() -> void:
    tooltip_label = Label.new()
    tooltip_label.visible = false
    tooltip_label.modulate = Color(1,1,1,1)
    tooltip_label.add_theme_color_override("font_color", Color(1,1,1))
    tooltip_label.add_theme_stylebox_override("normal", StyleBoxFlat.new())
    tooltip_label.get_theme_stylebox("normal").bg_color = Color(0,0,0,0.7)
    tooltip_label.get_theme_stylebox("normal").content_margin_left = 4
    tooltip_label.get_theme_stylebox("normal").content_margin_right = 4
    tooltip_label.get_theme_stylebox("normal").content_margin_top = 2
    tooltip_label.get_theme_stylebox("normal").content_margin_bottom = 2
    tooltip_label.z_index = 1000
    add_child(tooltip_label)

## Creates a console (RichTextLabel) anchored to the bottom of the screen to
## display debug messages from adventurers.
func _create_console() -> void:
    console_label = RichTextLabel.new()
    console_label.name = "Console"
    console_label.anchor_left = 0.0
    console_label.anchor_right = 1.0
    console_label.anchor_top = 0.75
    console_label.anchor_bottom = 1.0
    console_label.offset_left = 0.0
    console_label.offset_right = 0.0
    console_label.offset_top = 0.0
    console_label.offset_bottom = 0.0
    console_label.scroll_active = true
    console_label.fit_content = false
    console_label.autowrap = true
    console_label.set_v_scroll_bar(true)
    add_child(console_label)

## Handler for mouse entering a location icon.  Shows the tooltip with the name.
func _on_icon_mouse_entered(name : String) -> void:
    if tooltip_label:
        tooltip_label.text = name
        tooltip_label.visible = true

## Handler for mouse exiting a location icon.  Hides the tooltip.
func _on_icon_mouse_exited() -> void:
    if tooltip_label:
        tooltip_label.visible = false

## Called when an adventurer emits a debug message.  Append to the console.
func _on_adventurer_debug(msg : String) -> void:
    if console_label:
        console_label.append_text(msg + "\n")
        # Keep console scrolled to the bottom
        console_label.scroll_to_line(console_label.get_line_count())

## Updates the right-hand status label in the top bar with in-game time and money.
func _update_status_label() -> void:
    if not top_bar:
        return
    var status_label : Label = top_bar.get_node("HBoxContainer/StatusLabel")
    # Compute hours and minutes from game_time_seconds
    var hours := int(game_time_seconds / 3600.0)
    var minutes := int((game_time_seconds % 3600.0) / 60.0)
    var time_str := "Day %s %02d:%02d" % [day_counter, hours, minutes]
    status_label.text = "%s   |   %d G" % [time_str, money]

## Input handler to manage zoom and tooltip positioning.
func _unhandled_input(event: InputEvent) -> void:
    # Mouse wheel zoom
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed:
            if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
                current_zoom = clamp(current_zoom + 0.1, min_zoom, max_zoom)
                _update_map_zoom()
            elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                current_zoom = clamp(current_zoom - 0.1, min_zoom, max_zoom)
                _update_map_zoom()
    # Update tooltip position
    if event is InputEventMouseMotion and tooltip_label and tooltip_label.visible:
        var mm := event as InputEventMouseMotion
        tooltip_label.position = mm.position + Vector2(10, -10)

