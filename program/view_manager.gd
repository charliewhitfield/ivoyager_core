# view_manager.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
# I, Voyager is a registered trademark of Charlie Whitfield in the US
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************************
class_name IVViewManager
extends Node

## Builds [IVView] instances from table data (default views), and provides API
## for user-created views that are persisted via gamesave or cache.
##
## [method get_view_description] says in words what the user sees now.

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"gamesave_views",
]

const AUTOMATION_USER_METHODS: Array[StringName] = [
	&"set_table_view",
	&"has_table_view",
	&"set_view",
	&"has_view",
	&"get_names_in_collection",
	&"get_view_description",
]
const AUTOMATION_USER_PROPERTIES: Array[StringName] = [
	&"table_views",
	&"cached_views",
	&"gamesave_views",
]


## If not &"", set this view on simulator start.
var set_view_on_start := &"VIEW_HOME"
## Cache file path.
var file_path := IVCoreSettings.cache_dir.path_join("views.ivbinary")


## Built once at init from [code]views.tsv[/code]; read only!
var table_views: Dictionary[StringName, IVView]
## Views persisted via gamesave; keys are
## [code]"<view_name>.<collection_name>"[/code]. Read only!
var gamesave_views: Dictionary[StringName, IVView] = {}
## Views persisted via the cache file at [member file_path]; keys are
## [code]"<view_name>.<collection_name>"[/code]. Read only!
var cached_views: Dictionary[StringName, IVView] = {}

var _missing_or_bad_cache_file := true
var _file_mutex := Mutex.new() # serializes [method _write_cache_file] across worker threads



func _init() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVStateManager.core_init_program_objects_instantiated.connect(_on_program_objects_instantiated)
	IVStateManager.about_to_start_simulator.connect(_on_about_to_start_simulator)


## Applies the named built-in [IVView] (from [member table_views]) to the
## simulator. This is the standard "apply a named view" entry point — the same
## call the GUI's default view buttons make (see [IVViewButton]). Prefer it over
## driving [IVCameraHandler] directly when the goal is to frame the camera on a
## body. No-op if [param view_name] is unknown; check [method has_table_view]
## first when the name is not statically known.
func set_table_view(view_name: StringName, is_camera_instant_move := false) -> void:
	if !table_views.has(view_name):
		return
	var view: IVView = table_views[view_name]
	view.set_state(is_camera_instant_move)


## Returns true if [param view_name] is a known built-in view.
func has_table_view(view_name: StringName) -> bool:
	return table_views.has(view_name)


## Returns the [IVView] for [param view_name] from [member table_views], or
## [code]null[/code] if not found.
func get_table_view_object(view_name: StringName) -> IVView:
	return table_views.get(view_name)


## Returns the [member IVView.flags] of [param view_name] from
## [member table_views], or 0 if not found.
func get_table_view_flags(view_name: StringName) -> int:
	if table_views.has(view_name):
		return table_views[view_name].flags
	return 0


## Captures the simulator's current state into a new (or existing) [IVView]
## and persists it. Stored in [member cached_views] when [param is_cached] is
## true (then written to disk), otherwise in [member gamesave_views].
func save_view(view_name: String, collection_name: String, is_cached: bool, flags: int,
		allow_threaded_cache_write := true) -> void:
	print("Save view '%s'; collection '%s', cached = %s" % [view_name, collection_name, is_cached])
	
	var key := view_name + "." + collection_name
	var view := get_view_object(view_name, collection_name, is_cached)
	if view:
		view.reset()
	else:
		view = IVView.create()
	view.save_state(flags)
	if is_cached:
		cached_views[key] = view
		_write_cache(allow_threaded_cache_write)
	else:
		gamesave_views[key] = view


## Applies a previously saved view to the simulator. No-op if the view does
## not exist.
func set_view(view_name: String, collection_name: String, is_cached: bool,
		is_camera_instant_move := false) -> void:
	var key := view_name + "." + collection_name
	var view: IVView
	if is_cached:
		view = cached_views.get(key)
	else:
		view = gamesave_views.get(key)
	if !view:
		return
	view.set_state(is_camera_instant_move)


## Persists [param view] (without re-capturing simulator state). Useful when
## the [IVView] was constructed externally.
func save_view_object(view: IVView, view_name: String, collection_name: String, is_cached: bool,
		allow_threaded_cache_write := true) -> void:
	var key := view_name + "." + collection_name
	if is_cached:
		cached_views[key] = view
		_write_cache(allow_threaded_cache_write)
	else:
		gamesave_views[key] = view


## Returns the [IVView] for the given key, or [code]null[/code] if not found.
func get_view_object(view_name: String, collection_name: String, is_cached: bool) -> IVView:
	var key := view_name + "." + collection_name
	if is_cached:
		return cached_views.get(key)
	return gamesave_views.get(key)


## Returns the [member IVView.flags] of the named view, or 0 if not found.
func get_view_flags(view_name: String, collection_name: String, is_cached: bool) -> int:
	var key := view_name + "." + collection_name
	var view: IVView = cached_views.get(key) if is_cached else gamesave_views.get(key)
	if view:
		return view.flags
	return 0


func get_view_edited_default(view_name: String, collection_name: String, is_cached: bool
		) -> StringName:
	var key := view_name + "." + collection_name
	var view: IVView = cached_views.get(key) if is_cached else gamesave_views.get(key)
	if view:
		return view.edited_default
	return &""


func set_view_edited_default(view_name: String, collection_name: String, is_cached: bool,
		edited_default: StringName) -> void:
	var key := view_name + "." + collection_name
	var view: IVView = cached_views.get(key) if is_cached else gamesave_views.get(key)
	if view:
		view.edited_default = edited_default


## Returns true if the named view exists in the chosen store.
func has_view(view_name: String, collection_name: String, is_cached: bool) -> bool:
	var key := view_name + "." + collection_name
	if is_cached:
		return cached_views.has(key)
	return gamesave_views.has(key)


## Removes the named view from the chosen store. No-op if the view doesn't
## exist.
func remove_view(view_name: String, collection_name: String, is_cached: bool) -> void:
	# OK if doesn't exist
	var key := view_name + "." + collection_name
	if is_cached:
		if cached_views.has(key):
			cached_views.erase(key)
			_write_cache()
	else:
		gamesave_views.erase(key)


## Returns the [code]view_name[/code]s of every view in [param collection_name]
## within the chosen store.
func get_names_in_collection(collection_name: String, is_cached: bool) -> Array[String]:
	var group: Array[String] = []
	var suffix := "." + collection_name
	var dict := cached_views if is_cached else gamesave_views
	for key: String in dict:
		if key.ends_with(suffix):
			group.append(key.trim_suffix(suffix))
	return group


## Returns what the user sees now as text in the user's language, a line each:
## the selection, the camera's distance and tracking, the bodies in view,
## largest first, and the date, time and speed. For an assistant and a screen
## reader alike.
func get_view_description() -> String:
	var lines := PackedStringArray()
	var top_ui: Node = IVGlobal.program.get(&"TopUI")
	if top_ui and &"selection_manager" in top_ui:
		var selection_manager: IVSelectionManager = top_ui.get(&"selection_manager")
		if selection_manager and selection_manager.has_selection():
			lines.append("%s: %s" % [tr(&"LABEL_SELECTION"), selection_manager.get_gui_name()])
	var camera_3d := get_viewport().get_camera_3d()
	if camera_3d is IVCamera:
		var camera: IVCamera = camera_3d
		lines.append(_describe_camera(camera))
		lines.append(_describe_bodies_in_view(camera))
	lines.append(_describe_time())
	return "\n".join(lines)


## Whether an automation client may use [param member] now: a view applies only
## to a started simulator.
func is_automation_available(member: StringName) -> bool:
	if member == &"set_table_view" or member == &"set_view" or member == &"get_view_description":
		return IVStateManager.started
	return true



func _describe_camera(camera: IVCamera) -> String:
	const TRACK_GROUND := IVCamera.CameraFlags.CAMERAFLAGS_TRACK_GROUND
	const TRACK_ORBIT := IVCamera.CameraFlags.CAMERAFLAGS_TRACK_ORBIT
	const TRACK_ECLIPTIC := IVCamera.CameraFlags.CAMERAFLAGS_TRACK_ECLIPTIC
	var text := tr(&"LABEL_CAMERA") + ": "
	var target := camera.target
	if target:
		var distance := camera.global_position.distance_to(target.global_position)
		text += tr(&"TXT_DISTANCE_FROM_CONSTRUCTOR") % [
				IVQFormat.dynamic_unit(distance, &"length_m_km_au", 3), tr(target.name)]
	var tracking := &""
	if camera.flags & TRACK_GROUND:
		tracking = &"BUTTON_GROUND"
	elif camera.flags & TRACK_ORBIT:
		tracking = &"BUTTON_ORBIT"
	elif camera.flags & TRACK_ECLIPTIC:
		tracking = &"BUTTON_ECLIPTIC"
	if tracking:
		text += "; %s: %s" % [tr(&"LABEL_CAMERA_TRACKING"), tr(tracking)]
	return text


func _describe_bodies_in_view(camera: IVCamera) -> String:
	const MAX_NAMED := 8
	const MIN_PERCENT_FRACTION := 0.01
	var planes := camera.get_frustum()
	planes.remove_at(1) # the far plane: farwarp draws bodies beyond it
	var view_angle := deg_to_rad(camera.fov)
	var camera_position := camera.global_position
	var in_view: Array[Array] = [] # see _is_hidden()
	for body: IVBody in IVBody.bodies.values():
		var center := body.global_position
		var is_outside := false
		for plane in planes:
			if plane.distance_to(center) > body.mean_radius:
				is_outside = true
				break
		if is_outside:
			continue
		var offset := center - camera_position
		var distance := offset.length()
		var angular_radius := PI / 2.0
		if distance > body.mean_radius:
			angular_radius = asin(body.mean_radius / distance)
		in_view.append([2.0 * angular_radius / view_angle, body, offset / distance,
				angular_radius, distance])
	in_view.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var names := PackedStringArray()
	var n_visible := 0
	for entry in in_view:
		if _is_hidden(entry, in_view):
			continue
		n_visible += 1
		if n_visible > MAX_NAMED:
			continue
		var fraction: float = entry[0]
		var body: IVBody = entry[1]
		var body_name := tr(body.name)
		if fraction >= MIN_PERCENT_FRACTION:
			var percent := roundi(minf(fraction, 1.0) * 100.0)
			body_name += " (%s)" % (tr(&"TXT_PERCENT_OF_VIEW_CONSTRUCTOR") % percent)
		names.append(body_name)
	if n_visible > MAX_NAMED:
		names.append(tr(&"TXT_AND_MORE_CONSTRUCTOR") % (n_visible - MAX_NAMED))
	return "%s: %s" % [tr(&"LABEL_IN_VIEW"), ", ".join(names)]


# Whether a nearer body's disc covers all of [param entry]'s. Each entry of
# [param in_view], largest first, is [fraction of the view's height, body,
# direction from the camera, angular radius, distance].
func _is_hidden(entry: Array, in_view: Array[Array]) -> bool:
	const MIN_DISC_FRACTION := 0.001
	var direction: Vector3 = entry[2]
	var angular_radius: float = entry[3]
	var distance: float = entry[4]
	for disc in in_view:
		var disc_fraction: float = disc[0]
		if disc_fraction < MIN_DISC_FRACTION:
			return false
		var disc_distance: float = disc[4]
		if disc_distance >= distance:
			continue
		var disc_direction: Vector3 = disc[2]
		var disc_angular_radius: float = disc[3]
		if direction.angle_to(disc_direction) + angular_radius < disc_angular_radius:
			return true
	return false


func _describe_time() -> String:
	var timekeeper: IVTimekeeper = IVGlobal.program[&"Timekeeper"]
	var speed_manager: IVSpeedManager = IVGlobal.program[&"SpeedManager"]
	var date := IVGlobal.date
	var clock := IVGlobal.clock
	var text := "%s: %d-%02d-%02d %02d:%02d %s; %s%s" % [tr(&"LABEL_TIME"), date[0], date[1],
			date[2], clock[0], clock[1], "TT" if timekeeper.terrestrial_time_clock else "UT",
			"-" if speed_manager.reversed_time else "", tr(speed_manager.get_speed_name())]
	if IVStateManager.paused_by_user:
		text += "; " + tr(&"TXT_PAUSED").to_lower()
	return text


func _clear_procedural() -> void:
	gamesave_views.clear()


func _on_program_objects_instantiated() -> void:
	# table read
	var table_view_builder: IVTableViewBuilder = IVGlobal.program[&"TableViewBuilder"]
	table_views = table_view_builder.build_all()
	# caching
	DirAccess.make_dir_recursive_absolute(IVCoreSettings.cache_dir)
	_read_cache()
	if _missing_or_bad_cache_file:
		_write_cache()


func _on_about_to_start_simulator(is_new_game: bool) -> void:
	if is_new_game and set_view_on_start:
		set_table_view(set_view_on_start, true)


# This replicates some IVCacheHandler code, but it's really hard to generalize
# that class to handle objects.

func _read_cache() -> void:
	# Populate cached_views once at project init on main thread.
	var file := FileAccess.open(file_path, FileAccess.READ)
	if !file:
		prints("Creating new cache file", file_path)
		return
	
	# May have old cache file, so treat with care...
	var file_var: Variant = file.get_var() # untyped for safety
	if typeof(file_var) != TYPE_DICTIONARY:
		prints("Overwriting obsolete cache file", file_path)
		return
	var file_dict: Dictionary = file_var
	if file_dict.get_typed_key_builtin() != TYPE_STRING_NAME:
		prints("Overwriting obsolete cache file", file_path)
		return
	var bad_cache_data := false
	for key: StringName in file_dict:
		var data: Variant = file_dict[key] # untyped; set_data_from_cache() validates
		var view := IVView.create()
		if !view.set_data_from_cache(data): # may be prior version or corrupt
			bad_cache_data = true
			continue
		cached_views[key] = view
	if !bad_cache_data:
		_missing_or_bad_cache_file = false


func _write_cache(allow_threaded_cache_write := true) -> void:
	# Unless this is app exit, no one is waiting for this and we can do the
	# file write on thread. At app exit, we want the main thread to wait.
	# [member _file_mutex] in [method _write_cache_file] serializes
	# writer-vs-writer if multiple worker tasks queue up.
	var dict: Dictionary[StringName, Array] = {}
	for key in cached_views:
		var view: IVView = cached_views[key]
		var data := view.get_data_for_cache()
		dict[key] = data
	if allow_threaded_cache_write:
		WorkerThreadPool.add_task(_write_cache_file.bind(dict))
	else:
		_write_cache_file(dict)


func _write_cache_file(dict: Dictionary[StringName, Array]) -> void:
	_file_mutex.lock()
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	var err := FileAccess.get_open_error()
	if err != OK:
		push_error("Could not open file for write: ", file_path)
		_file_mutex.unlock()
		return
	file.store_var(dict)
	_file_mutex.unlock()
