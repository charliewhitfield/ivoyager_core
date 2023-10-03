# universe.gd
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
class_name IVUniverse
extends Node3D

# *****************************************************************************
#
#          Developers! Look in these files to get started:
#             res://addons/ivoyager_core/singletons/core_initializer.gd
#             res://addons/ivoyager_core/singletons/core_settings.gd
#             res://ivoyager_override.cfg
#
# *****************************************************************************
#
# 'Universe' is the main scene and simulator root node in our Planetarium and
# Project Template projects (https://github.com/ivoyager). To change this, see
# notes in ivoyager_core/singletons/core_initializer.gd.
#
# We use origin shifting to prevent 'imprecision shakes' caused by vast scale
# differences, e.g, when viewing a small body at 1e9 km from the sun. To do
# so, the IVCamera adjusts the translation of this node (or substitute root
# node) every frame.
#
# 'persist' dictionary is not used by ivoyager code but is available for
# game save persistence in extension projects. It can hold Godot built-ins,
# nested containers or other 'persist objects'. For details on save/load
# persistence, see ivoyager_core/program/save_builder.gd.
#
# if IVCoreSettings.pause_only_stops_time == true, then PAUSE_MODE_PROCESS is
# set in this node and TopGUI so IVCamera can still move, visuals work (some
# are responsve to camera) and user can interact with the world. In this mode,
# only IVTimekeeper pauses to stop time. (This is set by IVStateManager.)

const PERSIST_MODE := IVEnums.PERSIST_PROPERTIES_ONLY # don't free on load
const PERSIST_PROPERTIES := [&"persist"]

var persist := {}

