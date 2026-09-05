// rings.gdshader
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
shader_type spatial;
// skip_vertex_transform: for the farwarp vertex remap; see _farwarp.gdshaderinc.
// ambient_light_disabled: ambient is rebuilt as emission; see _sun_occlusion.gdshaderinc.
// blend_premul_alpha: the texture is premultiplied; see THE TEXTURE below.
render_mode cull_disabled, skip_vertex_transform, ambient_light_disabled, blend_premul_alpha;

// THE TEXTURE. One imported CompressedTexture2DArray of three width x 1 layers, built by
// addons/tools/build_saturn_rings.py from Bjoern Joensson's radial ring profiles
// (https://bjj.mmedia.is/data/s_rings). Read that script's docstring for what the file
// holds and why; the two properties this shader depends on are:
//
//   rgb  LINEAR radiance, PREMULTIPLIED -- the ring's own light over black sky, which is
//        what Joensson measured in the Voyager frames. So it composites as
//        `radiance + transmission * background` (blend_premul_alpha) and must NOT be
//        multiplied by alpha again; and the sampler is NOT source_color, because the
//        values are already linear on both renderers.
//   a    1 - transparency: the fraction of the background this radius occludes at normal
//        incidence, from the Voyager stellar occultation optical depth.
//
// The three layers are the same rings at three geometries -- backscatter (lit side near
// the sun's direction), forward scatter (lit side, phase 139 deg) and the unlit side --
// so alpha is identical in all three and one fetch answers the unlit branch completely.
//
// Mipmaps come from the import and are averaged in linear light, so a distant ring is the
// correct radial average of the rings it stands for. The LOD is computed here rather than
// left to the hardware because the discard below would leave a partly-killed quad's
// derivatives undefined -- the same reason dFdx()/dFdy() run before the fork.
//
// Colour and level: the tint, the phase mix and the boosts below are OUR appearance model,
// not Joensson's data. He states that the rings dim and redden as phase angle rises, and
// gives the unlit side a flat colour, which is baked into layer 2 as the only colour he
// publishes for it.
//
// Adjusted to match https://bjj.mmedia.is/3dtest/saturn/saturn_montage.jpg
// on the lit side. Those are rendered (not real) so we still need ground truth
// comparisons to Cassini images (lit and unlit sides).
//
// IVRings flips the plane to keep the front face on the sun-facing side so the
// lit/unlit-side test below (the sign of camera_model_elevation) stays correct;
// see IVRings._process. FRONT_FACING would be simpler but is unreliable (wrong
// on some GPUs as of Godot 4.2.2), hence the model-space test.

#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_photometry.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"

const float DFDR_MULTIPLIER = 1.0; // smaller for more detail & more aliasing
const float PHASE_EXPONENT = 6.0; // larger narrows the low phase-angle effect

// set by rings.gd once
uniform sampler2DArray rings_textures : filter_linear_mipmap, repeat_disable;
uniform float texture_width; // texels across one layer
uniform float texture_start; // texture's inner edge, as a fraction of the plane's radius
uniform float texture_end; // texture's outer edge, same units (> texture_start)
uniform float inner_margin; // discard inside this; includes render margin (< texture_start)
uniform float outer_margin; // discard outside this; includes render margin (> texture_end)

// set by rings.gd every frame
uniform vec3 illumination_position;

// exposed visual settings
uniform float forwardscatter_redshift = 1.05;
uniform float unlitside_boost = 3.0; // general brightening
uniform float litside_phase_boost = 3.0; // low phase-angle brightening
uniform float unlitside_phase_boost = 2.0;

// varyings
varying vec3 illumination_direction;
varying flat float camera_model_elevation; // >0.0 for lit side
varying vec3 v_world_position; // true world position; VERTEX is farwarp-remapped


void vertex() {
	illumination_direction = normalize((VIEW_MATRIX * vec4(illumination_position, 1.0)).xyz);
	camera_model_elevation = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).y;
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Farwarp remap under skip_vertex_transform. NORMAL is transformed identically to the engine
	// default (farwarp_lit_vertex), so ring lighting is unchanged; only the depth is compressed.
	farwarp_lit_vertex(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL);
}


void fragment() {

	float r = length(UV * 2.0 - vec2(1.0));

	// dFdx() & dFdy() must be before the 'if' fork to avoid edge artifacts!
	float texel_position = texture_width * (r - texture_start) / (texture_end - texture_start);
	float footprint = length(vec2(dFdx(texel_position), dFdy(texel_position))); // texels per pixel

	if (r < inner_margin || r > outer_margin) {
		discard; // out of rings area

	} else {

		float lod = log2(max(footprint * DFDR_MULTIPLIER, 1.0));
		float u = texel_position / texture_width;

		// The texture holds the rings and nothing else, so its two ends are where the
		// data stops and not where the rings do (the innermost C ring and the F ring
		// region are both faintly occupied at the boundary sample). Fade the last texel
		// out over this fragment's own footprint: at a distance that is one texel of
		// anti-aliasing, and close up it is the half-texel step clamp-to-edge would
		// otherwise smear across the whole render margin.
		float texels_inside = min(texel_position, texture_width - texel_position);
		float edge = clamp(texels_inside / max(footprint, 1.0) + 0.5, 0.0, 1.0);

		// phase effects (phase_mix = 1.0 corresponds to phase angle = 0.0)
		float phase_mix = dot(illumination_direction, VIEW) / 2.0 + 0.5;
		phase_mix = pow(phase_mix, PHASE_EXPONENT);

		// The sampled rgb is premultiplied linear radiance and the boosts are linear
		// coefficients, so everything here is a straight multiply; the encode for a
		// display-referred renderer happens once, at the end.
		vec4 ring;

		if (camera_model_elevation > 0.0) {
			// lit side
			vec4 backscatter = textureLod(rings_textures, vec3(u, 0.5, 0.0), lod);
			vec4 forwardscatter = textureLod(rings_textures, vec3(u, 0.5, 1.0), lod);
			forwardscatter.r *= forwardscatter_redshift;
			// Alpha is the same in both layers, so the mix leaves it exactly alone.
			ring = mix(forwardscatter, backscatter, phase_mix);
			ring.rgb *= litside_phase_boost * phase_mix + 1.0;
		} else {
			// unlit side
			ring = textureLod(rings_textures, vec3(u, 0.5, 2.0), lod);
			ring.rgb *= unlitside_boost * (unlitside_phase_boost * phase_mix + 1.0);
		}

		// Coverage scales the premultiplied radiance and the occlusion together, which is
		// what makes a partly covered fragment composite correctly.
		ring *= edge;

		// debug lod mapping
		//ring.rgb = vec3(lod / 8.0, lod / 8.0, 1.0 - lod / 8.0);

		ALBEDO = ring.rgb;
		ALPHA = ring.a;

		// Rebuilt ambient (engine ambient is disabled; see render_mode). Added
		// before the shadow so occlusion removes sunlight, not starlight. The
		// feed already carries exposure; see the include.
		EMISSION += ALBEDO * ambient_light;

		// Planet (and moon) shadows on the rings; the ring term itself stays
		// disabled here (rings don't shadow themselves; also its fwidth() must
		// not run in this non-uniform branch).
		if (occluder_count > 0) {
			float sun_visible = sun_occlusion_visible_fraction(v_world_position);
			if (compat_albedo_shadow) {
				ALBEDO *= sun_visible;
				// AO is ambient-only on this renderer, so the albedo multiply stands in
				// for it -- and the SPECULAR lobe needs the same shadow, or an eclipsed
				// body keeps its full sunlit sheen, which a dark-adapted exposure
				// amplifies into a solid white disc (measured: Mimas in Saturn's shadow).
				// F0 scales as SPECULAR^2, so the square root carries the fraction onto
				// specular energy.
				SPECULAR *= sqrt(sun_visible);
			} else {
				AO = sun_visible;
				AO_LIGHT_AFFECT = 1.0; // attenuates direct light, not just ambient
			}
		}

		if (iv_display_encode >= 0.5) {
			// A premultiplied fragment's colour IS its whole term, so there is nothing to
			// restate against what lies behind (see display_mix's hazard note): the ring's
			// finished radiance goes through display_write() and the blend's own
			// (1 - alpha) attenuation of the background is left to the hardware. Self-lit,
			// because an engine-lit ALBEDO arrives one stage too late to encode -- on the
			// engine's own convention, which lights only the sunlit face (the unlit face is
			// ambient alone), and the existing model-space side test says which this is.
			// Lambert, not the engine's Burley: with the legacy Compatibility boost
			// overrides retired, the end-to-end measurement puts a Lambert restatement at
			// 0.99x of Forward+'s ring face and a Burley one at 1.23x -- at this
			// near-equinox grazing incidence the engine's own shading sits close to
			// Lambert here, whatever it does on a sphere.
			float diffuse_factor = camera_model_elevation > 0.0
					? max(dot(normalize(NORMAL), illumination_direction), 0.0) : 0.0;
			vec3 ring_radiance = ALBEDO * (diffuse_factor * sun_light_energy) + EMISSION;
			ALBEDO = vec3(0.0);
			EMISSION = display_write(ring_radiance);
		} else {
			ALBEDO = display_write_albedo(ALBEDO);
			EMISSION = display_write(EMISSION);
		}
	}
}
