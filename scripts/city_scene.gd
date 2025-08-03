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

## UI layer used to display controls.  A CanvasLayer ensures that UI
## elements are drawn on top of the game world and that Control anchors
## work relative to the viewport.
var ui_layer : CanvasLayer

## Zoom parameters
var min_zoom : float = 1.0
var max_zoom : float = 1.0
var current_zoom : float = 1.0

## Panning state.  When the user holds the left mouse button and drags,
## we move the map container by the drag delta.  These variables track
## whether we are currently panning and store the last mouse position.
var is_panning : bool = false
var pan_last_pos : Vector2 = Vector2.ZERO

## Game time variables
var game_time_seconds : float = 0.0
var day_counter : int = 1
var money : int = 0

# Preload the dot texture used for icons
var DotTexture : Texture2D = preload("res://assets/dot.png")

# Preload unique icons for each location.  These textures are the same
# dimensions as the dot and provide distinct symbols for HQ, dungeon,
# healer, blacksmith and inn.  If any of these textures are missing,
# the code will fall back to the DotTexture.
var HqIcon : Texture2D = preload("res://assets/hq_icon.png")
var DungeonIcon : Texture2D = preload("res://assets/dungeon_icon.png")
var HealerIcon : Texture2D = preload("res://assets/healer_icon.png")
var BlacksmithIcon : Texture2D = preload("res://assets/blacksmith_icon.png")
var InnIcon : Texture2D = preload("res://assets/inn_icon.png")

# Define key locations on the map.  Coordinates are in pixel space
# relative to the top‑left corner of the 1024×1024 map texture.
# These values correspond to approximate positions of landmarks on
# the Orario map.  Feel free to tweak them later if they need
# adjustment.
const HQ_POS         : Vector2 = Vector2(180, 770)
const DUNGEON_POS    : Vector2 = Vector2(512, 512)
const HEALER_POS     : Vector2 = Vector2(700, 300)
const BLACKSMITH_POS : Vector2 = Vector2(820, 650)
const INN_POS        : Vector2 = Vector2(300, 300)

## Size of the map texture, initialised in _ready().  We use @onready
## because map_sprite is available only after the scene tree is ready.
@onready var map_size : Vector2 = map_sprite.texture.get_size()

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

## Helper to create a location icon at a given position on the map.  Each
## icon is represented as an Area2D with a Sprite2D using the provided
## texture.  A circular collision shape enables mouse hover detection.
func _create_location_icon(location_name : String, pos : Vector2, tex : Texture2D) -> void:
	# Area2D to detect mouse hover
	var area := Area2D.new()
	# Place the icon at the given position.  The map coordinate system
	# now uses the natural top‑left origin, so no conversion is required.
	area.position = pos
	# Sprite to display the icon
	var sprite := Sprite2D.new()
	sprite.texture = tex if tex != null else DotTexture
	area.add_child(sprite)
	# Collision shape based on the texture size
	var shape := CircleShape2D.new()
	var base_tex : Texture2D = tex if tex != null else DotTexture
	shape.radius = base_tex.get_width() * 0.5
	var coll := CollisionShape2D.new()
	coll.shape = shape
	area.add_child(coll)
	# Connect signals for tooltip
	area.connect("mouse_entered", Callable(self, "_on_icon_mouse_entered").bind(location_name))
	area.connect("mouse_exited", Callable(self, "_on_icon_mouse_exited"))
	# Add to map container so it scales with the map
	map_container.add_child(area)

func _ready() -> void:
        randomize()
        # Create a canvas layer for UI elements.  Control nodes added to this
        # layer will anchor relative to the viewport instead of the game world.
        ui_layer = CanvasLayer.new()
        add_child(ui_layer)

	# Create a container for the map and its overlays (adventurers and icons).
	map_container = Node2D.new()
	add_child(map_container)
	# Reparent the map sprite and adventurer container into the map container
	if map_sprite:
		# Remove the map sprite from its parent and add it into the map container.
		# We no longer flip the map horizontally; the coordinate system
		# uses the top‑left origin.
		map_sprite.get_parent().remove_child(map_sprite)
		map_container.add_child(map_sprite)
	if adv_container:
		adv_container.get_parent().remove_child(adv_container)
		map_container.add_child(adv_container)

	# Create UI elements: top bar, tooltip and console.  They must be
	# created before computing the map zoom so that their sizes are taken
	# into account when calculating the available area.
	_create_top_bar()
	_create_tooltip()
	_create_console()

	# Compute the minimum zoom using a “cover” approach so that the map
	# completely fills the available portion of the viewport.  We reserve
	# a fixed fraction (25%) of the screen for the console and subtract
	# the top bar height.  Using max() ensures that whichever ratio is
	# larger (width or height) determines the zoom, akin to CSS
	# object-fit: cover【853882587653309†L1341-L1346】.
	var view_size : Vector2 = get_viewport_rect().size
	var map_tex_size : Vector2 = map_sprite.texture.get_size()
	var top_height : float = top_bar.get_rect().size.y
	var console_ratio : float = 0.25
	var console_height : float = view_size.y * console_ratio
	var available_height : float = view_size.y - top_height - console_height
	if available_height < 1.0:
		available_height = 1.0
	# Use max() to scale the map so it covers the available area without
	# leaving blank space.
	min_zoom = max(view_size.x / map_tex_size.x, available_height / map_tex_size.y)
	# Allow zooming in up to 4× the minimum zoom.
	max_zoom = min_zoom * 4.0
	current_zoom = min_zoom
	_update_map_zoom()

	# Create service icons with tooltips and add them to the map container.
	_create_location_icon("HQ", HQ_POS, HqIcon)
	_create_location_icon("Dungeon", DUNGEON_POS, DungeonIcon)
	_create_location_icon("Healer", HEALER_POS, HealerIcon)
	_create_location_icon("Blacksmith", BLACKSMITH_POS, BlacksmithIcon)
	_create_location_icon("Inn", INN_POS, InnIcon)

	# Spawn an adventurer at the HQ.  Set its home and service locations.
	var adv : Adventurer = AdventurerScene.instantiate()
	adv.global_position = HQ_POS
	adv.adname = "Bell"  # placeholder name
	adv.home_base_pos = HQ_POS
	adv.dungeon_pos = DUNGEON_POS
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
        # Award a random amount of gold after exiting the dungeon
        var reward := randi_range(100, 1000)
        money += reward
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
	# Compute the available region for the map by subtracting the top bar
	# height and the console portion from the viewport.
	var view_size : Vector2 = get_viewport_rect().size
	var top_height : float = 0.0
	if top_bar:
		top_height = top_bar.get_rect().size.y
	var console_ratio : float = 0.25
	var console_height : float = view_size.y * console_ratio
	var available_size : Vector2 = Vector2(view_size.x, view_size.y - top_height - console_height)
	var map_scaled_size : Vector2 = map_sprite.texture.get_size() * current_zoom
	# Compute the top-left origin of the map area (below top bar)
	var origin : Vector2 = Vector2(0, top_height)
	# Center the scaled map within the available area
	var offset : Vector2 = (available_size - map_scaled_size) * 0.5
	map_container.position = origin + offset
	# Clamp the map position within the available area after centering.
	_clamp_map_position()

## Clamp the map container position to ensure that no grey background is
## exposed.  The map should always cover the entire available area,
## regardless of zoom or panning.  We compute the minimum and maximum
## allowed positions based on the available viewport size and the scaled
## map dimensions.
func _clamp_map_position() -> void:
	if not map_sprite or not map_container:
		return
	var view_size : Vector2 = get_viewport_rect().size
	var top_height : float = top_bar.get_rect().size.y if top_bar else 0.0
	var console_ratio : float = 0.25
	var console_height : float = view_size.y * console_ratio
	var available_origin : Vector2 = Vector2(0.0, top_height)
	var available_size : Vector2 = Vector2(view_size.x, view_size.y - top_height - console_height)
	var map_scaled_size : Vector2 = map_sprite.texture.get_size() * current_zoom
	var min_pos : Vector2 = available_origin + available_size - map_scaled_size
	var max_pos : Vector2 = available_origin
	map_container.position.x = clamp(map_container.position.x, min_pos.x, max_pos.x)
	map_container.position.y = clamp(map_container.position.y, min_pos.y, max_pos.y)

## Creates the top bar UI displaying familia name, log placeholder, in-game time and money.
func _create_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.name = "TopBar"
	# Anchor the top bar to the top of the viewport.  It spans the full
	# width and has a fixed height (40 pixels).  Offsets on bottom
	# define the height in pixels.
	top_bar.anchor_left = 0.0
	top_bar.anchor_top = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_bottom = 0.0
	top_bar.offset_left = 0.0
	top_bar.offset_top = 0.0
	top_bar.offset_right = 0.0
	top_bar.offset_bottom = 40.0
	ui_layer.add_child(top_bar)
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
	# Configure tooltip styling: white text on semi-transparent dark background
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0, 0, 0, 0.7)
	tooltip_style.content_margin_left = 4
	tooltip_style.content_margin_right = 4
	tooltip_style.content_margin_top = 2
	tooltip_style.content_margin_bottom = 2
	tooltip_label.add_theme_stylebox_override("normal", tooltip_style)
	tooltip_label.add_theme_color_override("font_color", Color(1, 1, 1))
	tooltip_label.z_index = 1000
	ui_layer.add_child(tooltip_label)

## Creates a console (RichTextLabel) anchored to the bottom of the screen to
## display debug messages from adventurers.
func _create_console() -> void:
	# Create a PanelContainer to hold the console and provide a dark background
	var console_container := PanelContainer.new()
	console_container.name = "ConsoleContainer"
	# Anchor it to occupy the bottom quarter of the viewport
	console_container.anchor_left = 0.0
	console_container.anchor_right = 1.0
	console_container.anchor_top = 0.75
	console_container.anchor_bottom = 1.0
	console_container.offset_left = 0.0
	console_container.offset_right = 0.0
	console_container.offset_top = 0.0
	console_container.offset_bottom = 0.0
	var console_style := StyleBoxFlat.new()
	console_style.bg_color = Color(0, 0, 0, 0.8)
	console_container.add_theme_stylebox_override("panel", console_style)
	ui_layer.add_child(console_container)

	# RichTextLabel for displaying logs
	console_label = RichTextLabel.new()
	console_label.name = "Console"
	console_label.anchor_left = 0.0
	console_label.anchor_right = 1.0
	console_label.anchor_top = 0.0
	console_label.anchor_bottom = 1.0
	console_label.offset_left = 8.0
	console_label.offset_right = -8.0
	console_label.offset_top = 4.0
	console_label.offset_bottom = -4.0
	console_label.scroll_active = true
	console_label.fit_content = false
	# Use white text colour for readability
	console_label.add_theme_color_override("default_color", Color(1, 1, 1))
	console_container.add_child(console_label)

## Handler for mouse entering a location icon.  Shows the tooltip with the name.
func _on_icon_mouse_entered(tooltip_name : String) -> void:
	if tooltip_label:
		tooltip_label.text = tooltip_name
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
	# Use integer division and remainder for minutes to avoid using % on floats
	var minutes := int(game_time_seconds / 60.0) % 60
	var time_str := "Day %s %02d:%02d" % [day_counter, hours, minutes]
	status_label.text = "%s   |   %d G" % [time_str, money]

## Input handler to manage zoom, panning and tooltip positioning.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Handle zoom in/out using the mouse wheel.  When zooming we keep
		# the point under the cursor stationary relative to the world by
		# computing its local coordinate before scaling and repositioning
		# the map accordingly【130249362971839†L119-L144】.
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var mouse_pos : Vector2 = mb.position
			var local_before : Vector2 = (mouse_pos - map_container.position) / current_zoom
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				current_zoom = clamp(current_zoom + 0.1, min_zoom, max_zoom)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				current_zoom = clamp(current_zoom - 0.1, min_zoom, max_zoom)
			map_container.scale = Vector2(current_zoom, current_zoom)
			map_container.position = mouse_pos - local_before * current_zoom
			_clamp_map_position()
		# Handle start and end of panning when left mouse button is pressed.
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				is_panning = true
				pan_last_pos = mb.position
			else:
				is_panning = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# When panning, move the map by the mouse motion's relative movement
		# and clamp the position to keep the map within bounds.
		if is_panning:
			map_container.position += mm.relative
			_clamp_map_position()
		# Update the tooltip position if visible.
		if tooltip_label and tooltip_label.visible:
			tooltip_label.position = mm.position + Vector2(10, -10)
