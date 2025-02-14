# enums.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2025 Charlie Whitfield
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
class_name IVEnums
extends Object

## Global context enums and enum constants.

## Duplicated from Tree Saver plugin so we can have these in our classes
## without the plugin.
enum PersistMode {
	NO_PERSIST, ## Non-persist object.
	PERSIST_PROPERTIES_ONLY, ## Object will not be freed (Node only; must have stable NodePath).
	PERSIST_PROCEDURAL, ## Object will be freed and rebuilt on game load (Node or RefCounted).
}
const NO_PERSIST := PersistMode.NO_PERSIST
const PERSIST_PROPERTIES_ONLY := PersistMode.PERSIST_PROPERTIES_ONLY
const PERSIST_PROCEDURAL := PersistMode.PERSIST_PROCEDURAL


enum SBGClass {
	SBG_CLASS_ASTEROIDS,
	SBG_CLASS_COMETS,
	SBG_CLASS_ARTIFICIAL_SATELLITES, # TODO: Roadmap
	SBG_CLASS_OTHER,
}

enum GUISize {
	GUI_SMALL,
	GUI_MEDIUM,
	GUI_LARGE,
}

enum StarmapSize {
	STARMAP_8K,
	STARMAP_16K,
}

enum Confidence {
	CONFIDENCE_NO,
	CONFIDENCE_DOUBTFUL,
	CONFIDENCE_UNKNOWN,
	CONFIDENCE_PROBABLY,
	CONFIDENCE_YES,
}

enum NetworkState {
	NO_NETWORK,
	IS_SERVER,
	IS_CLIENT,
}

enum NetworkStopSync {
	BUILD_SYSTEM,
	SAVE,
	LOAD,
	NEW_PLAYER, # needs save to enter in-progress game
	EXIT,
	QUIT,
	DONT_SYNC,
}

# WIP - Not used yet
enum LazyType { # WIP - for rebuild of body/model lazy init system
	LAZY_NEVER, # default for stars and planets
	LAZY_OUT_OF_SYSTEM, # default for dwarf planets & major moons
	LAZY_MAX, # default for minor moons, instantiated asteroids & spacecraft
}

enum CameraFlags {
	UP_LOCKED = 1,
	UP_UNLOCKED = 1 << 1,
	
	TRACK_GROUND = 1 << 2,
	TRACK_ORBIT = 1 << 3,
	TRACK_ECLIPTIC = 1 << 4,
	TRACK_GALACIC = 1 << 5, # not implemented yet
	TRACK_SUPERGALACIC = 1 << 6, # not implemented yet
	
	# bits 32-63 should be safe to use for any extension project
	
	# combo masks
	ANY_UP_FLAGS = 1 << 0 | 1 << 1,
	ANY_TRACK_FLAGS = 1 << 2 | 1 << 3 | 1 << 4 | 1 << 5 | 1 << 6,
}

enum CameraDisabledFlags {
	DISABLED_TRACK_GROUND = 1 << 0,
	DISABLED_TRACK_ORBIT = 1 << 1,
	DISABLED_TRACK_ECLIPTIC = 1 << 2,
	DISABLED_TRACK_GALACIC = 1 << 3, # not implemented yet
	DISABLED_TRACK_SUPERGALACIC = 1 << 4, # not implemented yet
}

enum BodyFlags {
	
	IS_BARYCENTER = 1, # not implemented yet
	IS_STAR = 1 << 1,
	IS_PLANET = 1 << 2,
	IS_TRUE_PLANET = 1 << 3,
	IS_DWARF_PLANET = 1 << 4,
	IS_MOON = 1 << 5,
	IS_ASTEROID = 1 << 6,
	IS_COMET = 1 << 7,
	IS_SPACECRAFT = 1 << 8,
	
	# combos
	IS_PLANET_OR_MOON = 1 << 2 | 1 << 5,

	IS_PLANETARY_MASS_OBJECT = 1 << 9,
	SHOW_IN_NAV_PANEL = 1 << 10,
	
	NEVER_SLEEP = 1 << 11, # won't work correctly if ancestor node sleeps
	IS_TOP = 1 << 12, # non-orbiting stars; is in IVGlobal.top_bodies
	PROXY_STAR_SYSTEM = 1 << 13, # top star or barycenter of system
	IS_PRIMARY_STAR = 1 << 14,
	IS_STAR_ORBITING = 1 << 15,
	IS_TIDALLY_LOCKED = 1 << 16,
	IS_AXIS_LOCKED = 1 << 17,
	TUMBLES_CHAOTICALLY = 1 << 18,
	IS_NAVIGATOR_MOON = 1 << 19, # IVSelectionManager uses for cycling
	IS_PLANETARY_MASS_MOON = 1 << 20,
	IS_NON_PLANETARY_MASS_MOON = 1 << 21,
	
	DISPLAY_M_RADIUS = 1 << 22,
	HAS_ATMOSPHERE = 1 << 23,
	IS_GAS_GIANT = 1 << 24,
	NO_ORBIT = 1 << 25, # Hill Sphere is smaller than body radius
	NO_STABLE_ORBIT = 1 << 26, # Hill Sphere / 3 is smaller than body radius
	USE_CARDINAL_DIRECTIONS = 1 << 27,
	USE_PITCH_YAW = 1 << 28,
	
	EXISTS = 1 << 29, # always set by IVTableBodyBuilder
	DISABLE_MODEL_SPACE = 1 << 30,
	
#   Reserved to 1 << 45.
#
#	Higher bits safe for extension project.
#	Max bit shift is 1 << 63.
}
