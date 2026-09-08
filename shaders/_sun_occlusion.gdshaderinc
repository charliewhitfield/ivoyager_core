// _sun_occlusion.gdshaderinc
// This file is part of I, Voyager
// https://ivoyager.dev
// *****************************************************************************
// Copyright 2019-2026 Charlie Whitfield
// I, Voyager is a registered trademark of Charlie Whitfield in the US
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// *****************************************************************************

// Analytic sun occlusion for lit materials: the fraction of direct sunlight
// reaching a fragment, computed per-fragment from true-space geometry uniforms
// instead of shadow maps. Shadow maps can't serve astronomical-scale casters:
// their world-space texel footprint (tens to hundreds of km) is far coarser
// than real occluder structure (Saturn's ring profile, eclipse penumbrae), and
// under farwarp the caster geometry warps in light space while the receiver
// warps in camera space, so map shadows across the warp boundary are wrong by
// construction. Analytic terms use true positions only, so they are exact at
// any zoom and farwarp-immune.
//
// Two occluder kinds: a ring plane with a 1D radial opacity profile (ring
// shadows, with slant path and physical penumbra), and oblate spheroids as sky
// discs with exact disc-overlap (eclipses, transits; penumbra/antumbra fall
// out of the disc math). IVSunOcclusionManager carries GDScript mirrors of the
// ring transmission and the spheroid disc overlap for the CPU's own occlusion
// queries; keep those in sync. What is NOT mirrored is each function's
// degenerate-case guard, which answers to its own consumer - see
// sun_occlusion_spheroid_fraction below.
//
// A receiving shader declares 'render_mode ambient_light_disabled', includes
// this file (which declares the shared uniform interface below), captures the
// TRUE world position in vertex() BEFORE the farwarp remap overwrites VERTEX,
// then in fragment():
//
//     EMISSION += ALBEDO * ambient_light; // rebuilt ambient; BEFORE the shadow
//     if (ring_texture_outer > 0.0 || occluder_count > 0) {
//         float sun_visible = sun_occlusion_visible_fraction(v_world_position);
//         if (compat_albedo_shadow) {
//             ALBEDO *= sun_visible;
//         } else {
//             AO = sun_visible;
//             AO_LIGHT_AFFECT = 1.0; // attenuates direct light, not just ambient
//         }
//     }
//
// The AO path needs no custom light(); it rides the engine's own PBR and shadow
// path. It does NOT work with the Compatibility renderer, where ao
// never reaches direct light (gles3 scene.glsl applies it to ambient only) -
// hence the compat_albedo_shadow albedo-multiply fallback (specular stays
// unshadowed there; accepted).
//
// The occlusion must remove DIRECT sunlight only, never ambient starlight. But
// AO multiplies engine ambient regardless of AO_LIGHT_AFFECT, the compat
// albedo multiply darkens everything albedo touches, and engine ambient can't
// be compensated exactly from a shader (with a sky present it includes
// sky-derived irradiance and reflection terms). So receivers opt OUT of engine
// ambient entirely (ambient_light_disabled) and rebuild diffuse ambient as
// emission from the manager-fed ambient_light uniform, which the occlusion
// then physically cannot touch: shadowed regions and the sun-less night side
// settle at the same ambient level. The manager feeds ambient_light even when
// IVCoreSettings.apply_analytic_shadows is off (the shadow terms are what that
// setting disables), so night sides never go black.
//
// NOTE FOR FUTURE MULTISTAR SUPPORT: this model assumes ONE star. The manager
// feeds a single sun_direction / sun_angular_radius and one occluder set, and
// the fragment applies a single sun_visible fraction through AO (or the compat
// albedo multiply) - both of which scale ALL direct light uniformly. Two stars
// cannot share that: a fragment eclipsed from star A but still lit by star B
// must keep B's light, which one AO value cannot express. Per-star shadows need
// per-light attenuation - a custom light() that evaluates each star's occlusion
// (viable again now that the METER scale-sensitivity that once ruled it out is
// resolved), or additive per-star passes. The occlusion math (sun_occlusion_*
// here and the IVSunOcclusionManager CPU mirrors) is already sun-parameterized,
// so it is reusable per star; only the application is single-sun.

// Fed per frame by the manager (or IVRings during the experiment); defaults
// keep every term a no-op until fed.
uniform sampler2D ring_alpha_r8 : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float ring_alpha_width = 1.0;
uniform vec3 ring_center;
uniform vec3 ring_normal = vec3(0.0, 0.0, 1.0);
uniform float ring_texture_inner = 0.0;
uniform float ring_texture_outer = 0.0; // <= 0.0 disables the ring term
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0); // unit, toward the sun
uniform float sun_angular_radius = 0.0;
// The star's rendered light energy: what the engine multiplies a lit ALBEDO by, so a shader
// that must reproduce that multiply itself renders on the same footing as the surface beneath
// it. Only a shader that composites its own result needs it (see rings.gdshader).
uniform float sun_light_energy = 1.0;
uniform vec4 occluder_data_a[6]; // xyz = center (world), w = equatorial radius
uniform vec4 occluder_data_b[6]; // xyz = pole axis (unit), w = polar radius
// xyz = the sun direction under this occluder's own pole stretch (unit), w = that stretch.
// Both are constant over a frame, and evaluating them per fragment costs a normalize and a
// divide on every lit pixel of every shader that includes this file.
uniform vec4 occluder_data_c[6];
uniform int occluder_count = 0; // 0 disables the spheroid term
uniform bool compat_albedo_shadow = false; // see header: AO is ambient-only in gl_compatibility
uniform vec3 ambient_light = vec3(0.0); // scene ambient (color x energy), rebuilt as emission; see header

// Compensating-camera exposure (IVExposureManager) reaches receivers through their
// inputs, never as a shader-side factor: direct light carries it in light_energy,
// ambient_light carries it in the fed value (the manager scales the Environment ambient
// each frame - which is also what compensates StandardMaterial3D craft models), and
// emission maps carry it in the iv_emission_luminance_scale global (declared by the surface
// shaders that use it). Multiplying exposure into any of those terms again would expose
// the scene twice.


// Visible fraction of the sun's disc given an occluding disc: exact two-circle
// (lens) overlap in the planar small-angle approximation, with exact
// containment tests - so totality, annularity and partial phases all behave.
// All args in radians.
float sun_occlusion_disc_fraction(float sun_ang_radius, float occluder_ang_radius,
		float separation) {
	float a = max(sun_ang_radius, 1e-7);
	float b = occluder_ang_radius;
	float c = separation;
	if (c >= a + b) {
		return 1.0; // no overlap
	}
	if (c <= b - a) {
		return 0.0; // total: occluder covers the sun disc
	}
	if (c <= a - b) {
		return 1.0 - (b * b) / (a * a); // annular/transit: occluder inside the sun disc
	}
	if (b > 20.0 * a) {
		// A much larger occluder disc (e.g. Saturn seen from its rings, ~1700x
		// the sun disc): its edge is locally straight across the small sun
		// disc, and the exact lens formula below cancels catastrophically (an
		// a^2-scale result from b^2-scale terms - float32 noise sparkles along
		// the penumbra). Use the stable straight-edge chord fraction instead.
		float x = clamp((c - b) / a, -1.0, 1.0); // sun-center distance past the edge, in sun radii
		return 0.5 + (x * sqrt(1.0 - x * x) + asin(x)) / 3.14159265358979;
	}
	float a2 = a * a;
	float b2 = b * b;
	float c2 = c * c;
	float lens = a2 * acos(clamp((c2 + a2 - b2) / (2.0 * c * a), -1.0, 1.0))
			+ b2 * acos(clamp((c2 + b2 - a2) / (2.0 * c * b), -1.0, 1.0))
			- 0.5 * sqrt(max((a + b - c) * (c + a - b) * (c - a + b) * (c + a + b), 0.0));
	return 1.0 - lens / (3.14159265358979 * a2);
}


// Visible fraction of the sun's disc past occluder [param index] of the uniform set, given
// the sine and cosine of the sun's own angular radius (loop-invariant, so the caller holds
// them). Oblateness matters: Saturn's flattening is visible in its shadow on the rings.
// Where the point lies at or inside the occluder's figure this answers ZERO - the harmless
// answer for a can't-happen case, and the manager excludes a body from its own occluder
// list, so only a ring plane can reach it (see sun_occlusion_inside_occluder).
float sun_occlusion_spheroid_fraction(vec3 world_position, float sin_sun, float cos_sun,
		int index) {
	vec4 occluder_a = occluder_data_a[index];
	vec4 occluder_c = occluder_data_c[index];
	float equatorial_radius = occluder_a.w;
	vec3 pole = occluder_data_b[index].xyz;
	// Space is stretched along the pole so the spheroid becomes a sphere of the equatorial
	// radius; the manager applies the same affine map to the sun ray. (The sun disc
	// distorts by ~flattening x angular radius - negligible.)
	vec3 offset = occluder_a.xyz - world_position;
	vec3 offset_stretched = offset + occluder_c.w * dot(offset, pole) * pole;
	float dist_squared = dot(offset_stretched, offset_stretched);
	if (dist_squared <= equatorial_radius * equatorial_radius) {
		return 0.0;
	}
	float dist = sqrt(dist_squared);
	float cos_separation = dot(offset_stretched / dist, occluder_c.xyz);
	// The two discs miss whenever `separation >= sun + occluder`, which is this comparison
	// of cosines - and they nearly always do, so it is taken before the inverse trig that
	// only an actual overlap needs. It subsumes the not-sunward case, and is exact where
	// treating that case separately was not.
	float sin_occluder = equatorial_radius / dist;
	float cos_occluder = sqrt(max(1.0 - sin_occluder * sin_occluder, 0.0));
	if (cos_separation <= cos_sun * cos_occluder - sin_sun * sin_occluder) {
		return 1.0;
	}
	return sun_occlusion_disc_fraction(sun_angular_radius, asin(sin_occluder),
			acos(clamp(cos_separation, -1.0, 1.0)));
}


// True where [param world_position] lies inside one of the occluding spheroids, by the
// same pole stretch the shadow term uses - so the figure tested is exactly the one that
// casts the shadow. A ring plane runs through its planet and is the only receiver with
// interior fragments; rings.gdshader discards them with this.
bool sun_occlusion_inside_occluder(vec3 world_position) {
	for (int i = 0; i < occluder_count; i++) {
		vec3 offset = occluder_data_a[i].xyz - world_position;
		float equatorial_radius = occluder_data_a[i].w;
		vec3 pole = occluder_data_b[i].xyz;
		vec3 stretched = offset + occluder_data_c[i].w * dot(offset, pole) * pole;
		if (dot(stretched, stretched) < equatorial_radius * equatorial_radius) {
			return true;
		}
	}
	return false;
}


// Transmission through an annular ring layer, modeled as a 1D radial opacity
// profile in a thin plane. [param ring_alpha] spans radius [param texture_inner]
// to [param texture_outer] (the padded texture range, not the physical ring
// edges) and must have mipmaps: the sampled LOD matches the penumbra footprint
// from [param sun_ang_radius] (floored at the screen footprint, so sub-pixel
// ringlet shadows filter instead of aliasing into dashes), which is how the
// shadow edge gets its physically correct softness. All positions/lengths share
// one frame and unit (world space in practice); [param sun_dir] and
// [param plane_normal] are unit vectors, either normal sign works.
float sun_occlusion_ring_transmission(vec3 world_position, vec3 sun_dir,
		vec3 plane_center, vec3 plane_normal, float texture_inner,
		float texture_outer, float sun_ang_radius,
		sampler2D ring_alpha, float alpha_width) {
	// Degenerate geometry falls through branchless (clamped cosine, then the
	// range test below): fwidth() needs texture_u defined in every quad lane,
	// so no early return may precede it.
	float cos_slant = dot(plane_normal, sun_dir);
	float abs_cos = max(abs(cos_slant), 1e-4);
	float signed_cos = (cos_slant >= 0.0) ? abs_cos : -abs_cos;
	float ray_length = dot(plane_normal, plane_center - world_position) / signed_cos;
	vec3 plane_hit = world_position + sun_dir * ray_length - plane_center;
	float texture_u = (length(plane_hit) - texture_inner)
			/ (texture_outer - texture_inner);
	float screen_texels = fwidth(texture_u) * alpha_width;
	if (ray_length <= 0.0 || texture_u <= 0.0 || texture_u >= 1.0) {
		return 1.0; // ring plane not sunward, or outside the profile range
	}
	// The sun's angular size smears the shadow over a penumbra footprint: sample
	// the mip level whose texel size matches it.
	float penumbra_width = 2.0 * sun_ang_radius * ray_length;
	float texel_size = (texture_outer - texture_inner) / alpha_width;
	float filter_texels = max(penumbra_width / texel_size, screen_texels);
	float lod = log2(max(filter_texels, 1.0));
	float alpha = textureLod(ring_alpha, vec2(texture_u, 0.5), lod).r;
	// A slanted path through the ring layer scales optical depth by 1/cos.
	return pow(1.0 - alpha, 1.0 / abs_cos);
}


// Total sun-visible fraction for a fragment at TRUE (un-farwarped) world
// position, from the uniform interface above: ring transmission (when enabled)
// x product of spheroid occluder fractions (independent-occlusion
// approximation). Call under uniform control flow (the ring term uses fwidth).
float sun_occlusion_visible_fraction(vec3 world_position) {
	float visible = 1.0;
	if (ring_texture_outer > 0.0) {
		visible = sun_occlusion_ring_transmission(world_position, sun_direction, ring_center,
				ring_normal, ring_texture_inner, ring_texture_outer, sun_angular_radius,
				ring_alpha_r8, ring_alpha_width);
	}
	float sin_sun = sin(sun_angular_radius);
	float cos_sun = cos(sun_angular_radius);
	for (int i = 0; i < occluder_count; i++) {
		visible *= sun_occlusion_spheroid_fraction(world_position, sin_sun, cos_sun, i);
	}
	return visible;
}
