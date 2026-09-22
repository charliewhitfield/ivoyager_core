# graphics_manager.gd
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
class_name IVGraphicsManager
extends Node

## Applies user graphics settings (antialiasing, shadow resolution, atmosphere
## quality and 3D render scale) to the rendering server, the main window viewport
## and the local shadow maps, and publishes the renderer's colour-space convention
## to shaders.
##
## Added by [IVCoreInitializer]. Settings [code]atmosphere_quality[/code],
## [code]render_scale[/code], [code]msaa_3d[/code], [code]fxaa[/code],
## [code]use_taa[/code] and [code]shadow_resolution[/code] are defined in
## [IVSettingsManager] and exposed in [IVOptionsPopup]; this node applies them at
## startup and re-applies them live on change. [member
## atmosphere_quality_settings], [member render_scale_settings], [member
## msaa_settings] and [member shadow_resolution_settings] are the enumerations
## backing the four dropdowns.[br][br]
##
## Renderer support differs: MSAA, atmosphere quality and render scale work in all
## renderers; FXAA is unavailable in the Compatibility renderer (including web
## exports); TAA is Forward+ only; and directional shadows on Compatibility depend
## on [member IVCoreSettings.apply_gl_compatibility_shadows] (see
## [IVDynamicLight]). Unsupported settings are skipped here and hidden by
## [IVOptionsPopup].[br][br]
##
## Render scale sets the main viewport's [member Viewport.scaling_3d_scale],
## upscaling with FSR 1 on Forward+ and bilinear elsewhere; the 2D GUI keeps the
## window's resolution. Which pixel decisions must follow the scaled buffer is in
## the settings summary of [code]VISUAL_MODEL.md[/code].[br][br]
##
## Atmosphere quality writes the [code]iv_atm_*[/code] shader globals that
## [code]shaders/_atmosphere.gdshaderinc[/code] reads. Both tiers are one shader
## program, so the change costs no compile and takes effect on the next frame; see
## [i]Atmospheres[/i] in [code]PHOTOMETRIC_MODEL.md[/code] for what Reduced gives
## up and [code]GRAPHICS_PROFILING.md[/code] for what it buys back.[br][br]
##
## It also writes the [code]iv_display_encode[/code] shader global once at startup:
## the Compatibility renderer is display-referred at both ends of a shader — a
## source_color texture arrives still encoded, and what a shader writes is taken
## as encoded too — so a shader must decode what it samples, do its colour
## arithmetic in linear, and encode what it writes. Every colour-handling shader
## does so through [code]shaders/_display.gdshaderinc[/code]; see that file for
## what the global means and what it does not cover.

## Enumeration backing the [code]atmosphere_quality[/code] dropdown in
## [IVOptionsPopup]. Mapped to the quadrature rule and ring tap cap in [method
## _apply_atmosphere_quality]. Insertion order must equal value order (the popup
## uses the setting value as the dropdown item index).
var atmosphere_quality_settings: Dictionary[StringName, int] = {
	ATMOSPHERE_NORMAL = 0,
	ATMOSPHERE_REDUCED = 1,
}

## Enumeration backing the [code]render_scale[/code] dropdown in
## [IVOptionsPopup]. Mapped to a 3D render scale in [method _apply_render_scale].
## Insertion order must equal value order (the popup uses the setting value as
## the dropdown item index).
var render_scale_settings: Dictionary[StringName, int] = {
	RENDER_SCALE_100 = 0,
	RENDER_SCALE_85 = 1,
	RENDER_SCALE_70 = 2,
	RENDER_SCALE_50 = 3,
}

## Enumeration backing the [code]msaa_3d[/code] dropdown in [IVOptionsPopup].
## Values match [enum Viewport.MSAA]. Insertion order must equal value order
## (the popup uses the setting value as the dropdown item index).
var msaa_settings: Dictionary[StringName, int] = {
	MSAA_DISABLED = 0,
	MSAA_2X = 1,
	MSAA_4X = 2,
	MSAA_8X = 3,
}

## Enumeration backing the [code]shadow_resolution[/code] dropdown in
## [IVOptionsPopup]. Mapped to a shadow atlas resolution in [method
## _apply_shadow_resolution]; Off switches the maps off through [member
## IVDynamicLight.shadow_maps_enabled] and frees the atlas. Insertion order must
## equal value order (the popup uses the setting value as the dropdown item index).
var shadow_resolution_settings: Dictionary[StringName, int] = {
	SHADOW_OFF = 0,
	SHADOW_2048 = 1,
	SHADOW_4096 = 2,
	SHADOW_8192 = 3,
}

@onready var _window := get_tree().get_root()


func _ready() -> void:
	IVSettingsManager.changed.connect(_settings_listener)
	# The renderer cannot change without a restart, so this is written once and never again.
	RenderingServer.global_shader_parameter_set(&"iv_display_encode",
			1.0 if IVGlobal.is_gl_compatibility else 0.0)
	_apply_atmosphere_quality()
	_apply_render_scale()
	_apply_msaa()
	_apply_fxaa()
	_apply_taa()
	_apply_shadow_resolution()


func _apply_atmosphere_quality() -> void:
	var setting: int = IVSettingsManager.get_setting(&"atmosphere_quality")
	# The packed table in _atmosphere.gdshaderinc holds the 6-node rule at 0 and the 4-node
	# rule at 6. Normal below is also where a stale cached index past the end lands.
	var gl_first := 0
	var gl_nodes := 6
	var ring_max_taps := 8
	match setting:
		1:
			gl_first = 6
			gl_nodes = 4
			ring_max_taps = 2
	RenderingServer.global_shader_parameter_set(&"iv_atm_gl_first", gl_first)
	RenderingServer.global_shader_parameter_set(&"iv_atm_gl_nodes", gl_nodes)
	RenderingServer.global_shader_parameter_set(&"iv_atm_ring_max_taps", ring_max_taps)


func _apply_render_scale() -> void:
	var setting: int = IVSettingsManager.get_setting(&"render_scale")
	var render_scale := 1.0 # also the scale for a stale cached index past the end
	match setting:
		1:
			render_scale = 0.85
		2:
			render_scale = 0.7
		3:
			render_scale = 0.5
	# Only Forward+ has FSR 1. The engine would fall back to bilinear elsewhere anyway,
	# but with a warning.
	var is_forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	_window.scaling_3d_mode = (Viewport.SCALING_3D_MODE_FSR if is_forward_plus
			else Viewport.SCALING_3D_MODE_BILINEAR)
	_window.scaling_3d_scale = render_scale


func _apply_msaa() -> void:
	var setting: int = IVSettingsManager.get_setting(&"msaa_3d")
	match setting:
		1:
			_window.msaa_3d = Viewport.MSAA_2X
		2:
			_window.msaa_3d = Viewport.MSAA_4X
		3:
			_window.msaa_3d = Viewport.MSAA_8X
		_:
			_window.msaa_3d = Viewport.MSAA_DISABLED


func _apply_fxaa() -> void:
	if IVGlobal.is_gl_compatibility:
		return # FXAA unsupported in the Compatibility renderer (incl. web)
	var enable_fxaa: bool = IVSettingsManager.get_setting(&"fxaa")
	_window.screen_space_aa = (Viewport.SCREEN_SPACE_AA_FXAA if enable_fxaa
			else Viewport.SCREEN_SPACE_AA_DISABLED)


func _apply_taa() -> void:
	if IVGlobal.is_gl_compatibility:
		return # TAA is Forward+ only
	var enable_taa: bool = IVSettingsManager.get_setting(&"use_taa")
	_window.use_taa = enable_taa


func _apply_shadow_resolution() -> void:
	if IVGlobal.is_gl_compatibility and not IVCoreSettings.apply_gl_compatibility_shadows:
		return # single unshadowed light on Compatibility; no shadow map to size
	var setting: int = IVSettingsManager.get_setting(&"shadow_resolution")
	IVDynamicLight.shadow_maps_enabled = setting != 0
	var size := 8192 # also the size for a stale cached index past the end
	match setting:
		0:
			# Godot frees an atlas only when its size changes, not when the last map goes,
			# so Off parks it at the engine's minimum, a size no option uses.
			size = 256
		1:
			size = 2048
		2:
			size = 4096
	RenderingServer.directional_shadow_atlas_set_size(size, false)


func _settings_listener(setting: StringName, _value: Variant) -> void:
	match setting:
		&"atmosphere_quality":
			_apply_atmosphere_quality()
		&"render_scale":
			_apply_render_scale()
		&"msaa_3d":
			_apply_msaa()
		&"fxaa":
			_apply_fxaa()
		&"use_taa":
			_apply_taa()
		&"shadow_resolution":
			_apply_shadow_resolution()
