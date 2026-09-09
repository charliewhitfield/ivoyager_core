# stars_visual.gd
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
class_name IVStarsVisual
extends MeshInstance3D

## Catalog star field drawn as farwarp-remapped point sprites.
##
## Builds one [constant Mesh.PRIMITIVE_POINTS] surface from magnitude-binned star
## binaries (produced by [code]addons/tools/build_star_binaries.py[/code] from the
## Hipparcos and Tycho-2 catalogues) on [signal IVStateManager.core_initialized].
## Each vertex is a star at its true ecliptic position (internal units); a
## [code]CUSTOM0[/code] channel carries raw (V magnitude, B-V), which the
## [code]stars[/code] shader converts to point size, brightness and color. The
## shader's per-vertex farwarp remap (shared with the small-body points) keeps
## distant stars inside the camera far plane and behind every simulation visual at
## any zoom.[br][br]
##
## Authored as a fixed node under [code]Universe[/code] (no PERSIST_MODE), so it
## rides the [IVCamera] origin shift automatically, builds once, and survives
## system rebuilds. No-ops with a warning if no binaries resolve (e.g. when
## ivoyager_assets is absent).[br][br]
##
## Note: Godot Editor shows a scene warning for missing mesh. The mesh is built
## procedurally, so you can ignore the warning.


## Magnitude-bin upper edges; must match the bins written by
## [code]addons/tools/build_star_binaries.py[/code]. Each bin file holds stars up to its edge.
const BINARY_FILE_MAGNITUDES: Array[String] = ["2.0", "2.5", "3.0", "3.5", "4.0", "4.5", "5.0",
		"5.5", "6.0", "6.5", "7.0", "7.5", "8.0", "8.5", "9.0", "9.5", "10.0", "10.5", "11.0",
		"11.5", "12.0", "12.5", "13.0", "99.9"]

const _ARRAY_FLAGS := Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
const _BINARY_MAGIC := 0x54535649 # b"IVST", little-endian
const _BINARY_VERSION := 2

## Path prefix for the star binaries. The loader appends
## [code].<magnitude>.ivbinary[/code] for each bin in [member BINARY_FILE_MAGNITUDES].
@export var stars_binary_path := "res://addons/ivoyager_assets/starmaps/stars"

## Loads magnitude bins up to and including this V-magnitude cutoff. Lower it (or
## remove bin files from the asset directory) to trade completeness for size. A
## project that renders at a fixed fov can drop every bin that fov cannot show;
## the ivoyager_assets README tabulates where each bin becomes invisible.
@export var magnitude_cutoff := 99.9

# The tuning surface for IVPSFSettings, the camera every source images through -- this
# field and every in-scene body's PSF quad alike, so an edit here moves both. Values
# write through on change (and on build, once the settings object exists); the live
# material updates from the settings object's 'changed' signal, not from these setters.
# See stars.gdshader for each uniform's role. Each range runs from one visibly wrong
# extreme to the other, so dragging a slider end to end shows what the uniform does;
# the shipped value sits well inside.
@export_group("Point Spread Function")
## 0.1 = sub-pixel specks that scintillate; 1.5 = fat blurry discs.
@export_range(0.1, 1.5, 0.05, "or_greater") var psf_sigma := 0.5:
	set(value):
		psf_sigma = value
		if _psf_settings:
			_psf_settings.psf_sigma = value
## 0 = only the very brightest stars remain; 14 = every star saturates to white.
@export_range(0.0, 14.0, 0.1) var intensity_faint_mag := 6.5:
	set(value):
		intensity_faint_mag = value
		if _psf_settings:
			_psf_settings.intensity_faint_mag = value
## 0.05 = every star the same brightness; 2.0 = only a handful survive, the rest go black.
@export_range(0.05, 2.0, 0.05) var intensity_gamma := 1.0:
	set(value):
		intensity_gamma = value
		if _psf_settings:
			_psf_settings.intensity_gamma = value
## 0 = no stars at all; 1.5 = the field washes out to saturated blobs.
@export_range(0.0, 1.5, 0.01, "or_greater") var intensity_scale := 0.5:
	set(value):
		intensity_scale = value
		if _psf_settings:
			_psf_settings.intensity_scale = value
## The fov at which [member fov_compensation] neither brightens nor dims the field. Away
## from the camera's actual fov the whole field shifts: 10 = far too dim, 120 = blown out.
@export_range(10.0, 120.0, 0.5) var fov_reference_deg := 50.0:
	set(value):
		fov_reference_deg = value
		if _psf_settings:
			_psf_settings.fov_reference_deg = value
## 0 = stars hold brightness as you zoom (they swamp or fade against the background);
## 2 = double-compensated, so zooming in blows the field out.
@export_range(0.0, 2.0, 0.05) var fov_compensation := 1.0:
	set(value):
		fov_compensation = value
		if _psf_settings:
			_psf_settings.fov_compensation = value
## Amplitude of the [code]r^-2[/code] glare wing every star carries outside its Gaussian
## core, at 1 px and unit intensity; 0 turns it off. See [member IVPSFSettings.glare_scale].
@export_range(0.0, 0.05, 0.001, "or_greater") var glare_scale := 0.0126:
	set(value):
		glare_scale = value
		if _psf_settings:
			_psf_settings.glare_scale = value
## How fast the glare widens with flux: its outer radius grows as
## [code]intensity^(glare_gamma / 2)[/code]. See [member IVPSFSettings.glare_gamma].
@export_range(0.0, 1.0, 0.005) var glare_gamma := 0.286:
	set(value):
		glare_gamma = value
		if _psf_settings:
			_psf_settings.glare_gamma = value
## Largest glare radius in px at the reference viewport height.
## See [member IVPSFSettings.glare_max_px].
@export_range(16.0, 1024.0, 1.0, "or_greater") var glare_max_px := 384.0:
	set(value):
		glare_max_px = value
		if _psf_settings:
			_psf_settings.glare_max_px = value
## 0 = a white field; 1 = each star's physical blackbody color; 2.5 = a candy-colored sky.
## Unlike the sliders above, this changes no star's brightness or size.
@export_range(0.0, 2.5, 0.05) var color_saturation := 1.0:
	set(value):
		color_saturation = value
		if _psf_settings:
			_psf_settings.color_saturation = value

var _shader_material: ShaderMaterial
var _psf_settings: IVPSFSettings



func _ready() -> void:
	# A fixed scene node's _ready() precedes core init, so the stars shader isn't
	# registered yet; build on core_initialized (resources populated and frozen).
	if IVStateManager.initialized_core:
		_build()
	else:
		IVStateManager.core_initialized.connect(_build, CONNECT_ONE_SHOT)


func _build() -> void:
	var vertices := PackedVector3Array()
	var magnitudes_colors := PackedFloat32Array() # (V_mag, B-V) per vertex -> CUSTOM0
	var max_distance := 0.0
	for magnitude_str in BINARY_FILE_MAGNITUDES:
		if magnitude_str.to_float() > magnitude_cutoff:
			break
		max_distance = maxf(max_distance,
				_append_binary(magnitude_str, vertices, magnitudes_colors))
	if vertices.is_empty():
		push_warning("IVStarsVisual: no star binaries found at '%s.*.ivbinary'" % stars_binary_path)
		return

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = IVGlobal.resources[&"stars_shader"]
	material_override = _shader_material
	_psf_settings = IVGlobal.program[&"PSFSettings"]
	_push_psf_settings()
	_psf_settings.changed.connect(_apply_psf_uniforms)
	_apply_psf_uniforms() # _push_psf_settings emits nothing if every export is a default
	cast_shadow = SHADOW_CASTING_SETTING_OFF

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_CUSTOM0] = magnitudes_colors
	var points_mesh := ArrayMesh.new()
	points_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays, [], {}, _ARRAY_FLAGS)
	# Frustum culling tests this AABB against the far plane, but farwarp-remapped
	# points stay on-screen even when the true-scale test fails; size the AABB so
	# it always contains the camera (as IVSBGPositionsVisual does for its points).
	var half_extent := maxf(max_distance, IVCoreSettings.max_camera_distance)
	var half_aabb := half_extent * Vector3.ONE
	points_mesh.custom_aabb = AABB(-half_aabb, 2.0 * half_aabb)
	sorting_use_aabb_center = false # f32 collapses that AABB's centre; sort by the node origin
	mesh = points_mesh


# Seeds the shared settings from this node's authored exports. The property setters
# cannot: they fire during scene load, before IVCoreInitializer has built the settings
# object, so their write-through no-ops and the authored values would never arrive.
func _push_psf_settings() -> void:
	_psf_settings.psf_sigma = psf_sigma
	_psf_settings.intensity_faint_mag = intensity_faint_mag
	_psf_settings.intensity_gamma = intensity_gamma
	_psf_settings.intensity_scale = intensity_scale
	_psf_settings.fov_reference_deg = fov_reference_deg
	_psf_settings.fov_compensation = fov_compensation
	_psf_settings.color_saturation = color_saturation
	_psf_settings.glare_scale = glare_scale
	_psf_settings.glare_gamma = glare_gamma
	_psf_settings.glare_max_px = glare_max_px


func _apply_psf_uniforms() -> void:
	_psf_settings.apply_to(_shader_material)


# Appends one magnitude bin's stars to [param vertices] (internal units) and
# [param magnitudes_colors] (CUSTOM0 float pairs), returning the bin's own farthest
# star distance for the AABB. A missing file is skipped silently (missing bin = no
# items, as with the asteroid binaries) -- which is what lets a project ship only
# the bins its own fov can show.
#
# The file is the packed v2 format; build_star_binaries.py's docstring is its
# specification, and the quantization constants ride in the header rather than
# being duplicated here so a rebuild cannot silently disagree with this decode.
func _append_binary(magnitude_str: String, vertices: PackedVector3Array,
		magnitudes_colors: PackedFloat32Array) -> float:
	var path := stars_binary_path + "." + magnitude_str + ".ivbinary"
	var file := FileAccess.open(path, FileAccess.READ)
	if !file:
		return 0.0
	if file.get_32() != _BINARY_MAGIC:
		push_warning("IVStarsVisual: bad magic in '%s'" % path)
		return 0.0
	var version := file.get_32()
	if version != _BINARY_VERSION:
		push_warning("IVStarsVisual: unexpected version %s in '%s'" % [version, path])
		return 0.0
	var count := file.get_32()
	var parallax_count := file.get_32()
	var shell_pc := file.get_float()
	var max_distance_pc := file.get_float()
	var parallax_scale := file.get_float()
	var magnitude_min := file.get_float()
	var magnitude_step := file.get_float()
	var b_v_min := file.get_float()
	var b_v_step := file.get_float()
	if count == 0:
		return 0.0
	# Two uint32 per star, bulk-read as one int32 array so the decode below is integer
	# masks on a packed buffer rather than a FileAccess call per field.
	var words := file.get_buffer(count * 8).to_int32_array()
	var parallax_codes := file.get_buffer(parallax_count * 2)
	file.close()

	# Direction components are quantized over +/-1 and deliberately left unnormalized
	# (see build_star_binaries.py); folding the 1/32767 into the distance is what keeps
	# the loop to one Vector3 multiply. The parallax stars come first in the file, so
	# the index alone says which distance a star takes.
	const PARSEC := IVUnits.PARSEC
	var shell_scale := shell_pc * PARSEC / 32767.0
	var parallax_numerator := 1000.0 * parallax_scale * PARSEC / 32767.0
	var base := vertices.size()
	var base_custom := magnitudes_colors.size()
	vertices.resize(base + count)
	magnitudes_colors.resize(base_custom + count * 2)
	var i := 0
	while i < count:
		var word_0 := words[i * 2]
		var word_1 := words[i * 2 + 1]
		var distance_scale := shell_scale
		if i < parallax_count:
			distance_scale = parallax_numerator / float(parallax_codes.decode_u16(i * 2))
		vertices[base + i] = Vector3(
				float((word_0 & 0xFFFF) - 32768),
				float(((word_0 >> 16) & 0xFFFF) - 32768),
				float((word_1 & 0xFFFF) - 32768)) * distance_scale
		magnitudes_colors[base_custom + i * 2] = (magnitude_min
				+ magnitude_step * float((word_1 >> 16) & 0xFF))
		magnitudes_colors[base_custom + i * 2 + 1] = (b_v_min
				+ b_v_step * float((word_1 >> 24) & 0xFF))
		i += 1
	return max_distance_pc * PARSEC
