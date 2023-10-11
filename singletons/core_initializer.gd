# core_initializer.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2023 Charlie Whitfield
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
extends Node

# This node is added as singleton 'IVCoreInitializer'.
#
# Modify properties or dictionary classes using res://ivoyager_override.cfg.
# Alternatively, you can modify values here using an initializer script. (Note,
# your initializer must be added somehow. You can either add it using
# res://ivoyager_override.cfg or make it an autoload.)
#
# For an example initializer script, see Planetarium:
# https://github.com/ivoyager/planetarium/blob/master/planetarium/preinitializer.gd.
#
# DON'T modify values here after program start!
#
# By itself, ivoyager_core will run but it lacks a GUI (the default IVTopGUI
# has no child GUIs). You can either build on the existing IVTopGUI or provide
# your own by setting 'top_gui' or 'top_gui_path' here.
#
# For a game that needs a splash screen at startup, add the splash screen to
# 'gui_nodes' here and set IVCoreSettings.skip_splash_screen = false.


signal init_step_finished() # for internal use only


# *************** PROJECT VARS - MODIFY THESE TO EXTEND !!!! ******************


var allow_project_build := true
var init_delay := 5 # frames


# init_sequence can be modified even after started (eg, by a preinitializer).
var init_sequence: Array[Array] = [
	# [object, method, wait_for_signal]
#	[self, "_init_extensions", false],
	[self, "_instantiate_preinitializers", false],
	[self, "_do_presets", false],
	[self, "_instantiate_initializers", false],
	[self, "_set_simulator_universe", false],
	[self, "_set_simulator_top_gui", false],
	[self, "_instantiate_and_index_program_objects", false],
	[self, "_init_program_objects", true],
	[self, "_add_program_nodes", true],
	[self, "_finish", false]
]

# Presets safely remove whole systems. (Note: We can add more of these if users
# want to develop and test them.)

var remove_save_load_system := false

# All nodes instatiated here are added to 'universe' or 'top_gui'. Use
# ivoyager_override.cfg or a preinitializer script to set either or both of
# these. Otherwise, IVCoreInitializer will assign default nodes from
# ivoyager_core (or for universe, by tree search for 'Universe').
# Whatever is assigned will be accessible from IVGlobal.program[&"Universe"]
# and IVGlobal.program[&"TopGUI"], irrespective of node names.

var universe: Node3D
var top_gui: Control
var universe_path: String # assign here if using ivoyager_override.cfg
var top_gui_path: String # assign here if using ivoyager_override.cfg
var add_top_gui_to_universe := true # if true, happens in add_program_nodes()

# You can replace any class below with a subclass of the original. In some
# cases, you can replace with a base Godot class (e.g., Node3D) or erase
# unneeded systems, but you will have to investigate dependencies.
#
# Dictionary values below can be any one of three things:
#   - A GDScript class_name global.
#   - A path to a Script resource (*.gd for now).
#   - Where applicable, a path to a scene (*.tscn, *.scn).
#
# (We want to support GDExtension classes in the future. Please tell us if you
# want to help with that!)

var preinitializers := {
	# RefCounted classes. IVCoreInitializer instances these first. External
	# projects can add script paths here using 'res://ivoyager_override.cfg'.
	# A reference is kept in dictionary 'IVGlobal.program' (erase it if you
	# want to de-reference your preinitializer so it will free itself).
}

var initializers := {
	# RefCounted classes. IVCoreInitializer instances these after
	# 'preinitializers'. These classes typically erase themselves from
	# dictionary 'IVGlobal.program' after init, thereby freeing themselves.
	# Path to RefCounted class ok.
	LogInitializer = IVLogInitializer,
	AssetInitializer = IVAssetInitializer,
	SharedResourceInitializer = IVSharedResourceInitializer,
	WikiInitializer = IVWikiInitializer,
	TranslationImporter = IVTranslationImporter,
	TableInitializer = IVTableInitializer,
}

var program_refcounteds := {
	# RefCounted classes. IVCoreInitializer instances one of each and adds to
	# dictionary IVGlobal.program. No save/load persistence.
	# Path to RefCounted class ok.
	
	# need first!
	SettingsManager = IVSettingsManager, # 1st so IVGlobal.settings are valid
	
	# builders (generators, often from table or binary data)
	EnvironmentBuilder = IVEnvironmentBuilder,
	SystemBuilder = IVSystemBuilder,
	BodyBuilder = IVBodyBuilder,
	SBGBuilder = IVSBGBuilder,
	OrbitBuilder = IVOrbitBuilder,
	SelectionBuilder = IVSelectionBuilder,
	CompositionBuilder = IVCompositionBuilder, # remove or subclass
	SaveBuilder = IVSaveBuilder, # ok to remove if you don't need game save
	
	# finishers (modify something on entering tree)
	BodyFinisher = IVBodyFinisher,
	SBGFinisher = IVSBGFinisher,
	
	# managers
	IOManager = IVIOManager,
	InputMapManager = IVInputMapManager,
	FontManager = IVFontManager, # ok to replace
	ThemeManager = IVThemeManager, # after IVFontManager; ok to replace
	MainMenuManager = IVMainMenuManager,
	SleepManager = IVSleepManager,
	WikiManager = IVWikiManager,
	ModelManager = IVModelManager,
	
	# tools and resources
	ViewDefaults = IVViewDefaults,
}

var program_nodes := {
	# IVCoreInitializer instances one of each and adds as child to Universe
	# (before/"below" TopGUI) and to dictionary IVGlobal.program.
	# Use PERSIST_MODE = PERSIST_PROPERTIES_ONLY if there is data to persist.
	# Path to scene or Node class ok.
	Scheduler = IVScheduler,
	ViewManager = IVViewManager,
	FragmentIdentifier = IVFragmentIdentifier, # safe to remove
	
	# Nodes below are ordered for input handling (last is first). We mainly
	# need to intercept cntr-something actions (quit, full-screen, etc.) before
	# CameraHandler. Universe children can be reordered after
	# 'project_nodes_added' signal using API below.
	CameraHandler = IVCameraHandler, # remove or replace if not using IVCamera
	Timekeeper = IVTimekeeper,
	WindowManager = IVWindowManager,
	SBGHUDsState = IVSBGHUDsState, # (likely to have input in future)
	BodyHUDsState = IVBodyHUDsState,
	InputHandler = IVInputHandler,
	SaveManager = IVSaveManager, # remove if you don't need game saves
	StateManager = IVStateManager,
}

var gui_nodes := {
	# IVCoreInitializer instances one of each and adds as child to TopGUI (or
	# substitute Control set in 'top_gui') and to dictionary IVGlobal.program.
	# Order determines visual 'on top' and input event handling: last added
	# is on top and 1st handled. TopGUI children can be reordered after
	# 'project_nodes_added' signal using API below.
	# Use PERSIST_MODE = PERSIST_PROPERTIES_ONLY for save/load persistence.
	# Path to scene or Node class ok.
	WorldController = IVWorldController, # Control ok
	MouseTargetLabel = IVMouseTargetLabel, # safe to replace or remove
	GameGUI = null, # assign here if convenient (above MouseTargetLabel, below SplashScreen)
	SplashScreen = null, # assign here if convenient (below popups)
	MainMenuPopup = IVMainMenuPopup, # safe to replace or remove
	LoadDialog = IVLoadDialog, # safe to replace or remove
	SaveDialog = IVSaveDialog, # safe to replace or remove
	OptionsPopup = IVOptionsPopup, # safe to replace or remove
	HotkeysPopup = IVHotkeysPopup, # safe to replace or remove
	Confirmation = IVConfirmation, # safe to replace or remove
	MainProgBar = IVMainProgBar, # safe to replace or remove
}

var procedural_objects := {
	# Nodes and references NOT instantiated by IVCoreInitializer. These class
	# scripts plus all above can be accessed from IVGlobal.procedural_classes (keys
	# have underscores). 
	# tree_nodes
	# Path to scene, Node class, or RefCounted class ok.
	Body = IVBody, # many dependencies, best to subclass
	Camera = IVCamera, # replaceable, but look for dependencies
	BodyLabel = IVBodyLabel, # replace w/ Node3D
	BodyOrbit = IVBodyOrbit, # replace w/ Node3D
	SBGOrbits = IVSBGOrbits, # replace w/ Node3D
	SBGPoints = IVSBGPoints, # replace w/ Node3D
	LagrangePoint = IVLagrangePoint, # replace w/ subclass
	ModelSpace = IVModelSpace, # replace w/ Node3D
	RotatingSpace = IVRotatingSpace, # replace w/ subclass
	Rings = IVRings, # replace w/ Node3D
	SpheroidModel = IVSpheroidModel, # replace w/ Node3D
	SelectionManager = IVSelectionManager, # replace w/ Node3D
	# tree_refs
	SmallBodiesGroup = IVSmallBodiesGroup,
	Orbit = IVOrbit,
	Selection = IVSelection,
	View = IVView,
	Composition = IVComposition, # replaceable, but look for dependencies	
}


# ***************************** PRIVATE VARS **********************************

var _program: Dictionary = IVGlobal.program
var _procedural_classes: Dictionary = IVGlobal.procedural_classes


# ****************************** PROJECT BUILD ********************************


func _enter_tree() -> void:
	var config: ConfigFile = IVFiles.get_config_with_override("res://addons/ivoyager_core/core.cfg",
			"res://ivoyager_override.cfg", "core_initializer")
	IVFiles.init_from_config(self, config, "core_initializer")


func _ready() -> void:
	var init_countdown := init_delay
	while init_countdown > 0:
		await get_tree().process_frame
		init_countdown -= 1
	build_project() # after all other singletons _ready()


# **************************** PUBLIC FUNCTIONS *******************************
# These should be called only by extension init file!

func reindex_universe_child(node_name: StringName, new_index: int) -> void:
	# Call at 'project_nodes_added' signal.
	var node: Node = _program[node_name]
	universe.move_child(node, new_index)


func reindex_top_gui_child(node_name: StringName, new_index: int) -> void:
	# Call at 'project_nodes_added' signal.
	var node: Node = _program[node_name]
	top_gui.move_child(node, new_index)


func move_universe_child_to_sibling(node_name: StringName, sibling_name: StringName,
		before_sibling: bool) -> void:
	# Call at 'project_nodes_added' signal.
	var node: Node = _program[node_name]
	var sibling: Node = _program[sibling_name]
	var sibling_index := sibling.get_index()
	universe.move_child(node, sibling_index if before_sibling else sibling_index + 1)


func move_top_gui_child_to_sibling(node_name: StringName, sibling_name: StringName,
		before_sibling: bool) -> void:
	# Call at 'project_nodes_added' signal.
	var node: Node = _program[node_name]
	var sibling: Node = _program[sibling_name]
	var sibling_index := sibling.get_index()
	top_gui.move_child(node, sibling_index if before_sibling else sibling_index + 1)


func build_project(override := false) -> void:
	# Call directly only if extension set allow_project_build = false.
	if !override and !allow_project_build:
		return
	# Build loop is designed so that array 'init_sequence' can be modified even
	# during loop execution -- in particular, by an extention instantiated in
	# the first step. Otherwise, it could be modified by an autoload singleton.
	var init_index := 0
	while init_index < init_sequence.size():
		var init_array: Array = init_sequence[init_index]
		var object: Object = init_array[0]
		var method: String = init_array[1]
		var wait_for_signal: bool = init_array[2]
		object.call(method)
		if wait_for_signal:
			await self.init_step_finished
		init_index += 1


# ************************ 'init_sequence' FUNCTIONS **************************

func _instantiate_preinitializers() -> void:
	for key: StringName in preinitializers:
		if !preinitializers[key]:
			continue
		assert(!_program.has(key))
		var preinitializer: RefCounted = IVFiles.make_object_or_scene(preinitializers[key])
		_program[key] = preinitializer
	IVGlobal.preinitializers_inited.emit()


func _do_presets() -> void:
	if remove_save_load_system:
		IVCoreSettings.enable_save_load = false
		program_refcounteds.erase("SaveBuilder")
		program_nodes.erase("SaveManager")
		gui_nodes.erase("SaveDialog")
		gui_nodes.erase("LoadDialog")


func _instantiate_initializers() -> void:
	for key: StringName in initializers:
		if !initializers[key]:
			continue
		assert(!_program.has(key))
		var initializer: RefCounted = IVFiles.make_object_or_scene(initializers[key])
		_program[key] = initializer
	IVGlobal.initializers_inited.emit()


func _set_simulator_universe() -> void:
	# Simulator root node 'universe' is assigned in one of three ways:
	# 1. External project assigns property 'universe' or 'universe_path' via
	#    preinitializer script or res://ivoyager_override.cfg.
	# 2. This method finds an existing tree node named 'Universe'.
	# 3. This method intantiates IVUniverse (tree_nodes/universe.gd).
	#
	# Note: We don't add Universe to the scene tree here. That must be done
	# elsewhere if it isn't already in the tree.
	# 
	# Note2: ivoyager_core always gets this node via IVGlobal.program.Universe,
	# never by node name. The actual node name doesn't matter.
	if universe:
		return
	if universe_path:
		universe = IVFiles.make_object_or_scene(universe_path)
		assert(universe)
		return
	var scenetree_root := get_tree().get_root()
	universe = scenetree_root.find_child(&"Universe", true, false)
	if universe:
		return
	universe = IVFiles.make_object_or_scene(IVUniverse)
	universe.name = &"Universe"


func _set_simulator_top_gui() -> void:
	# 'top_gui' is assigned in one of two ways:
	# 1. External project assigns property 'top_gui' or 'top_gui_path' via
	#    preinitializer script or res://ivoyager_override.cfg.
	# 2. This method intantiates IVTopGUI (tree_nodes/top_gui.gd).
	#
	# Method add_program_nodes() will add TopGUI to Universe if
	# add_top_gui_to_universe == true. Otherwise, external project must add it
	# somewhere if it isn't already in the tree.
	#
	# Note: ivoyager_core always gets this node via IVGlobal.program.TopGUI,
	# never by node name. The actual node name doesn't matter.
	if top_gui:
		return
	if top_gui_path:
		top_gui = IVFiles.make_object_or_scene(top_gui_path)
		assert(top_gui)
		return
	top_gui = IVFiles.make_object_or_scene(IVTopGUI)
	top_gui.name = &"TopGUI"


func _instantiate_and_index_program_objects() -> void:
	_program[&"Global"] = IVGlobal
	_program[&"CoreSettings"] = IVCoreSettings
	_program[&"Universe"] = universe
	_program[&"TopGUI"] = top_gui
	# Don't add CoreInitializer: it should never be accessed after init!
	for dict: Dictionary in [program_refcounteds, program_nodes, gui_nodes]:
		for key: StringName in dict:
			if !dict[key]:
				continue
			assert(!_program.has(key))
			var object: Object = IVFiles.make_object_or_scene(dict[key])
			_program[key] = object
			if object is Node:
				@warning_ignore("unsafe_property_access")
				object.name = key
	for key: StringName in procedural_objects:
		if !procedural_objects[key]:
			continue
		assert(!_procedural_classes.has(key))
		if procedural_objects[key] is Resource:
			_procedural_classes[key] = procedural_objects[key]
		else:
			var path: String = procedural_objects[key]
			_procedural_classes[key] = IVFiles.get_script_or_packedscene(path)
	IVGlobal.project_objects_instantiated.emit()


func _init_program_objects() -> void:
	if universe.has_method(&"_ivcore_init"):
		@warning_ignore("unsafe_method_access")
		universe._ivcore_init()
	if top_gui.has_method(&"_ivcore_init"):
		@warning_ignore("unsafe_method_access")
		top_gui._ivcore_init()
	for dict: Dictionary in [preinitializers, initializers, program_refcounteds, program_nodes, gui_nodes]:
		for key: StringName in dict:
			if !dict[key]:
				continue
			var object: Object = _program.get(key)
			if object and object.has_method(&"_ivcore_init"):
				@warning_ignore("unsafe_method_access")
				object._ivcore_init()
	IVGlobal.project_inited.emit()
	await get_tree().process_frame
	init_step_finished.emit()


func _add_program_nodes() -> void:
	# TopGUI added after program_nodes, so gui_nodes will recieve input first
	# and then program_nodes.
	for key: StringName in program_nodes:
		if !program_nodes[key]:
			continue
		var node: Node = _program[key]
		universe.add_child(node)
	if add_top_gui_to_universe:
		universe.add_child(top_gui)
	for key: StringName in gui_nodes:
		if !gui_nodes[key]:
			continue
		var node: Node = _program[key]
		top_gui.add_child(node)
	IVGlobal.project_nodes_added.emit()
	await get_tree().process_frame
	init_step_finished.emit()


func _finish() -> void:
	IVGlobal.project_builder_finished.emit()

