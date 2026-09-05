# rings.gd
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
class_name IVRings
extends MeshInstance3D

## Visual planetary rings of an [IVBody] instance.
##
## The rings cast no shadow-map shadows in either direction: ring shadows on
## bodies and body shadows on the rings are both analytic, fed per frame by
## [IVSunOcclusionManager] using this node's geometry and profile data (see
## [code]shaders/_sun_occlusion.gdshaderinc[/code]).[br][br]
##
## All properties are set from data table rings.tsv.[br][br]
##
## Uses rings.gdshader. See comments in the shader file for graphics issues
## and commentary.[br][br]
##
## Not persisted. [IVBodyFinisher] adds when [IVBody] is added to the tree.[br][br]

## How far outside the ring system the plane extends and the shader still draws, as a
## fraction of the ring span. Pure geometry: the texture's own radial extent is derived
## from the data it holds (see [member texture_inner_radius]), not from this.
const RENDER_MARGIN := 0.01


# All built from table rings.tsv.
## Asset file prefix used to locate ring textures.
var file_prefix: String
## Inner edge of the ring system, in simulator units.
var inner_radius: float
## Outer edge of the ring system, in simulator units.
var outer_radius: float
## Name of the [IVBody] star casting light through the rings.
var illuminating_star: StringName

## Radius of the ring texture's inner edge, in simulator units: half a texel inside
## [member inner_radius], which is the radius of its first texel's centre. The shadow
## profile texture spans [member texture_inner_radius] to [member texture_outer_radius].
## Read-only!
var texture_inner_radius: float
## Radius of the ring texture's outer edge, half a texel outside [member outer_radius].
## Read-only!
var texture_outer_radius: float


var _rings_material := ShaderMaterial.new()
var _texture_array: TextureLayered # backscatter/forwardscatter/unlitside layers
var _texture_start: float
var _texture_end: float
var _inner_margin: float
var _outer_margin: float
var _body: IVBody
var _illuminating_star: IVBody


func _init(body: IVBody) -> void:
	# threadsafe
	name = &"Rings"
	_body = body
	var row := IVTableData.db_find_in_array(&"rings", &"bodies", body.name)
	assert(row != -1, "Could not find row in rings.tsv for %s" % body.name)
	IVTableData.db_build_object(self, &"rings", row)
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	_texture_array = asset_preloader.get_rings_texture_array(name)
	cast_shadow = SHADOW_CASTING_SETTING_OFF # ring shadows are analytic; see class doc
	mesh = IVGlobal.resources[&"plane_mesh"] # shared subdivided 2x2 plane (farwarp needs subdivision)
	rotation.x = PI / 2.0 # z up astronomy


func _ready() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)

	_illuminating_star = IVBody.bodies.get(illuminating_star)
	assert(_illuminating_star, "Could not find illuminating star '%s'" % illuminating_star)
	
	# Distances in sim scale. The texture's texels are the source's own radial samples,
	# the first centred on inner_radius and the last on outer_radius, so its edges sit
	# half a texel outside both -- derived from the width, never a shared constant.
	var ring_span := outer_radius - inner_radius
	var texel_span := ring_span / float(_texture_array.get_width() - 1)
	texture_inner_radius = inner_radius - 0.5 * texel_span
	texture_outer_radius = outer_radius + 0.5 * texel_span
	var plane_radius := outer_radius + RENDER_MARGIN * ring_span # edge of plane

	# normalized distances from center of 2x2 plane
	_texture_start = texture_inner_radius / plane_radius
	_texture_end = texture_outer_radius / plane_radius
	_inner_margin = (inner_radius - RENDER_MARGIN * ring_span) / plane_radius # render boundary
	_outer_margin = 1.0 # render boundary; the plane's own inscribed circle

	scale = Vector3(plane_radius, 1.0, plane_radius)
	visibility_range_end = outer_radius * IVCoreSettings.radius_multiplier_visibility_range_end
	if IVCoreSettings.apply_farwarp:
		# Frustum culling tests the true-scale AABB against the far plane, but the farwarp
		# vertex remap keeps the ring on-screen even when that test fails; make it always pass.
		var extent := IVCoreSettings.max_camera_distance
		custom_aabb = AABB(-Vector3.ONE * extent, 2.0 * Vector3.ONE * extent)

	_rings_material.shader = IVGlobal.resources[&"rings_shader"]
	_rings_material.set_shader_parameter(&"rings_textures", _texture_array)
	_rings_material.set_shader_parameter(&"texture_width", float(_texture_array.get_width()))
	_rings_material.set_shader_parameter(&"texture_start", _texture_start)
	_rings_material.set_shader_parameter(&"texture_end", _texture_end)
	_rings_material.set_shader_parameter(&"inner_margin", _inner_margin)
	_rings_material.set_shader_parameter(&"outer_margin", _outer_margin)
	set_surface_override_material(0, _rings_material)
	


func _process(_delta: float) -> void:
	if !visible or !_illuminating_star: # null after _clear_procedural, before free
		return

	# rings.gdshader expects the front face toward the sun (its lit-side test is
	# the camera's model-space elevation), so flip as needed.
	var illumination_position := _illuminating_star.global_position
	var cos_illumination_angle := global_basis.y.dot(illumination_position.normalized())
	if cos_illumination_angle < 0.0:
		rotation.x *= -1

	_rings_material.set_shader_parameter(&"illumination_position", illumination_position)


func _clear_procedural() -> void:
	_body = null
	_illuminating_star = null
