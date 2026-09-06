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
// blend_premul_alpha: the fragment's colour IS the ring's own light; see THE OUTPUT below.
// cull_disabled: one plane draws both faces, and which one a fragment shows is decided
//   per fragment below, not by the primitive - see WHICH FACE.
render_mode cull_disabled, skip_vertex_transform, ambient_light_disabled, blend_premul_alpha;

// A GENERIC RING SYSTEM. Nothing here is Saturn: the texture supplies the radial
// structure and rings.tsv supplies every photometric number, so a different real or
// invented ring system is a new texture and a new table row.
//
// THE TEXTURE. One imported CompressedTexture2DArray of three width x 1 layers, built for
// Saturn by addons/tools/build_saturn_rings.py from Bjoern Joensson's radial ring profiles
// (https://bjj.mmedia.is/data/s_rings). Read that script's docstring for the derivation.
//
//   rgb  LINEAR SCATTERING STRENGTH - the ring's own light with the single-scattering
//        slab's geometry term DIVIDED OUT, so it is a property of the particles and not
//        of the angles the source's images happened to be taken at. Not source_color:
//        the values are already linear on both renderers.
//   a    1 - transmission at NORMAL incidence, from a stellar occultation, so
//        `tau = -ln(1 - a)` is the normal optical depth, identical in all three layers.
//
//   layer 0  the lit face at `back_phase`     |  layer 2  the unlit face
//   layer 1  the lit face at `forward_phase`  |
//
// THE MODEL. A plane-parallel single-scattering slab that is CLUMPY rather than uniform,
// which is the same physics _sun_occlusion.gdshaderinc applies to the sun's leg through the
// rings. With mu and mu0 the sines of the camera's and the sun's elevation above the ring
// plane, and `T(rate)` the layer's transmission at that rate through the beam:
//
//   lit    mu0/(mu+mu0) * (1 - T(1/mu + 1/mu0))
//   unlit  mu0/(mu0-mu) * (T(1/mu0) - T(1/mu))  + unlit_floor * mu0
//
// A real ring is not a uniform sheet: self-gravity wakes make optical depth vary across the
// beam, and a clumpy layer saturates more SLOWLY than a homogeneous one, because the thin
// lanes keep contributing after the dense parts have gone opaque. Taking tau as
// gamma-distributed about its mean with shape `clumping` gives
// `T = (1 + rate tau / clumping)^-clumping`, whose limit at large `clumping` is exactly
// exp(-rate tau). Saturn's is FITTED ON THE UNLIT PROFILE, which is the one that measures
// transmission, and comes out at 22.8 -- so the layer is nearly homogeneous, and the cell is
// here because that is a measurement rather than an assumption. Fitting it on the LIT
// profile instead is what it must not do: the lit fit's R2 moves 0.8733 to 0.8787 across the
// entire family, so it constrains nothing, and the 1.7 it happens to prefer let the dense B
// ring pass 15 % of the sun's light and rendered its unlit face nearly as bright as the C
// ring's, where every real unlit image has it far darker.
//
// What DOES set the bands' contrast is the reference geometry the build divides out, which
// is PINNED at the ring system's own maximum opening angle rather than fitted. Fitted, it
// wanted 33.5 degrees against Saturn's maximum of 26.7 -- a geometry that cannot occur -- so
// every render saturated harder than the reference had and washed the bands out: the B ring
// against the C ring fell to 3.52 at Saturn's widest and 2.05 at 12 degrees, where the source
// profile has 3.84. Pinned, the render reproduces the source exactly at that opening and
// flattens only below it, which is the real physics.
//
// This is what makes the rings answer to their opening angle. As the camera drops toward
// the plane the path through the layer lengthens without bound, so the optically thin
// rings brighten hard toward the saturated value while the B ring, already saturated,
// barely moves - the inversion that makes the C ring and the Cassini Division stand out
// in every low-opening image, and that a texture shipped at one geometry cannot express.
// Both faces saturate rather than diverge (a grazing ray's light comes from the layer's
// last little bit of depth), so nothing here needs a clamp.
//
// `unlit_floor` is the residual the model still cannot reach: measured, the densest B ring's
// unlit face is far brighter than transmission alone allows and flat over tau 1.8 to 3.6, so
// the term stands in for multiple scattering, light between self-gravity wakes, or the
// source's own image floor - the data cannot separate them. The build divides by the SAME
// constant, so the dense B ring renders at its published value there rather than as a ratio
// of two near-zeros. It rides
// mu0, as diffusely transmitted light must and as the single-scattering terms themselves do
// at small mu0: a floor that survives an equinox, which takes every other term to zero,
// makes the two faces of one ring disagree under geometry that is symmetric between them.
//
// PHASE carries the level, and the texture carries only the shape: the two lit profiles
// are published independently peak-normalized, so their relative brightness is not in
// the file and the phase function has to supply it. `forward_level` is the lit face's
// brightness at `forward_phase` relative to `back_phase`, interpolated as a straight
// line in magnitudes (an exponential in phase angle, which extrapolates monotonically
// past the second profile - the source's own note is that its high-phase end "should
// probably be even darker"). `opposition_surge` adds the narrow spike on top: the source
// states the rings drop "20-25%" from phase 0 to 6 degrees, which a smooth curve alone
// cannot do. Phase is per fragment, so a close camera gets the local opposition spot
// under it for free.
//
// BOTH faces take the same phase term, and that is physics rather than convenience: the
// phase angle is the sun-ring-observer angle, so a photon's scattering angle is 180 - phase
// WHICHEVER side the observer is on, and one phase function therefore serves both faces.
// What differs between them is the geometry term above, which the model already has. (This
// shader once gave the unlit face no phase term at all, on the reasoning that its light is
// forward-scattered where the lit face's is returned - true, and already accounted for by
// the phase angle itself being large there. The cost was an unlit face 1.8 to 2.8 times too
// bright at the phases it can actually be seen at, since a low phase angle on the unlit
// side is geometrically impossible: reaching one means standing near the sun's direction,
// and the sun is on the other side of the plane.) `unlit_level` is then only the ratio
// between the two published profiles' independent peak normalizations.
//
// WHICH FACE is decided per fragment, from the signs of the camera's and the sun's
// elevation, so a camera close to the plane correctly sees the lit face on one side of
// itself and the unlit face on the other. (The retired shader tested a flat per-primitive
// model-space elevation and needed IVRings to flip the plane every frame to keep the
// front face sunward; neither is needed now, and FRONT_FACING - unreliable on some GPUs
// as of Godot 4.2.2 - is still not used.)
//
// THE OUTPUT is premultiplied: rgb is the ring's own light over black sky and alpha is
// what it occludes, so the blend forms `light + (1 - alpha) * background` and rgb must
// never be scaled by alpha again. Alpha is the SLANT occlusion, `1 - (1-a)^(1/mu)`: a
// ring seen edge-on hides what is behind it however thin it is at normal incidence.
// Both are scaled together by the coverage terms, which is what makes a partly covered
// fragment composite correctly.
//
// SELF-LIT ON BOTH RENDERERS. The engine flips a double-sided primitive's normal, so an
// engine-lit ALBEDO renders N.L = 0 on whichever face is turned away and the unlit layer
// was unreachable - measured, the unlit face returned peak linear luma 0.00028 and zero
// lit pixels. It also arrives one stage too late to encode on a display-referred
// renderer. So the fragment computes its own radiance from sun_light_energy and hands
// the finished value to display_write(); ALBEDO stays zero.

#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"

const float DFDR_MULTIPLIER = 1.0; // smaller for more detail & more aliasing
// A grazing ray's optical path is tau/mu, and mu reaches zero at the plane. Nothing
// diverges there (every term saturates), but the ratio has to stay finite: at this floor
// tau/mu tops out around 1e5, which exp() answers with a clean zero.
const float MIN_MU = 1e-4;
// Alpha 1.0 means the occultation saw nothing through, which is a floor on tau and not a
// measurement of it. The source's own deepest MEASURED value is 5.55, so capping
// transmission here keeps the derived tau in the range the data actually covers.
const float MIN_TRANSMISSION = 0.001;

// set by rings.gd once
uniform sampler2DArray rings_textures : filter_linear_mipmap, repeat_disable;
uniform float texture_width; // texels across one layer
uniform float texture_start; // texture's inner edge, as a fraction of the plane's radius
uniform float texture_end; // texture's outer edge, same units (> texture_start)
uniform float inner_margin; // discard inside this; includes render margin (< texture_start)
uniform float outer_margin; // discard outside this; includes render margin (> texture_end)

// photometry, all from rings.tsv; see the header
uniform float back_phase = 0.0; // radians; phase angle of texture layer 0
uniform float forward_phase = 2.4260765; // radians; phase angle of texture layer 1
uniform float forward_level = 0.25; // lit brightness at forward_phase, relative to back_phase
uniform float forward_reddening = 1.05; // red multiplier at forward_phase
uniform float unlit_level = 2.121; // texture layer 2's level, relative to layer 0
uniform float unlit_floor = 0.1168; // see the header; must match the build's value
uniform float clumping = 22.77; // the layer's optical-depth spread; must match the build
uniform float opposition_surge = 0.25; // fractional brightening added at zero phase
uniform float opposition_width = 0.0349066; // radians; e-folding width of that surge
uniform float scattering_scale = 0.486; // overall level; the profiles are peak-normalized

// set by rings.gd every frame
uniform vec3 illumination_position;

// varyings
varying vec3 v_world_position; // true world position; VERTEX is farwarp-remapped
varying flat vec3 plane_normal; // unit, world space; either sign works
varying flat float plane_screen_thickness; // the whole ring system's minor axis, in pixels


// The layer's transmission at [param rate] through the beam, for optical depth
// [param tau] gamma-distributed about its mean with shape `clumping`. The large-clumping
// branch is the homogeneous limit and is taken explicitly: `1.0 + rate * tau / clumping`
// loses every bit of the quotient once clumping is large enough.
float ring_beam_transmission(float tau, float rate) {
	if (clumping > 1e4) {
		return exp(-rate * tau);
	}
	return pow(1.0 + rate * tau / clumping, -clumping);
}


// The slab's lit face: what a unit scattering strength emits toward a camera at elevation
// sine [param mu] under a sun at elevation sine [param mu0]. Monotone in tau, saturating
// at mu0/(mu+mu0) - which is what the metering candidate anchors on.
float ring_reflection(float tau, float mu, float mu0) {
	return mu0 / (mu + mu0) * (1.0 - ring_beam_transmission(tau, 1.0 / mu + 1.0 / mu0));
}


// The same slab's unlit face: light scattered once and emerging through the far side.
// `mu0/(mu0-mu)` is `b/(b-a)` in the two rates, so the whole term is written over that
// difference - and the 0/0 at mu == mu0 has to be taken as a limit, which is the
// transmission's own derivative there.
float ring_transmission(float tau, float mu, float mu0) {
	float a = 1.0 / mu0;
	float b = 1.0 / mu;
	float d = b - a;
	if (abs(d) < 1e-4 * max(a, b)) {
		if (clumping > 1e4) {
			return b * tau * exp(-a * tau);
		}
		return b * tau * pow(1.0 + a * tau / clumping, -clumping - 1.0);
	}
	return b * (ring_beam_transmission(tau, a) - ring_beam_transmission(tau, b)) / d;
}


void vertex() {
	plane_normal = normalize(MODEL_NORMAL_MATRIX * vec3(0.0, 1.0, 0.0));
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// A zero-thickness plane really does vanish edge-on, and modelling a ring's true
	// thickness would not change that: 10 m against a 140,000 km radius is 7e-8, sub-pixel
	// until the camera is within ~10 km of the plane. What has to be handled is the
	// APPROACH - the rasterizer's coverage goes binary once the whole system projects
	// thinner than a pixel, so a bright sliver would dash and snap off instead of fading
	// (measured on the retired shader: 260 lit pixels at a 0.2 deg opening, 1 at 0.0 deg).
	// This is that fade's measure and it is a rendering boundary, not physics: the minor
	// axis of the projected annulus, in pixels. The far-field form (2 R sin B / d) is used
	// at every distance because it only bites when it is small, which is when the far
	// field holds.
	vec3 center_to_camera = CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz;
	float camera_distance = max(length(center_to_camera), 1e-6);
	float plane_radius = length(MODEL_MATRIX[0].xyz); // the model's own x scale
	float focal_pixels = 0.5 * VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]);
	plane_screen_thickness = 2.0 * plane_radius * focal_pixels
			* abs(dot(plane_normal, center_to_camera)) / (camera_distance * camera_distance);

	// Farwarp remap under skip_vertex_transform. NORMAL is transformed identically to the
	// engine default (farwarp_lit_vertex); only the depth is compressed.
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

		// COVERAGE. Two terms, both areal, both scaling radiance and occlusion together.
		// The texture holds the rings and nothing else, so its two ends are where the data
		// stops and not where the rings do; this fragment's share of it is the overlap of
		// its own radial footprint with the texture's span, which is a half-texel step
		// close up and a full anti-aliasing fade at a distance. Then the edge-on fade from
		// vertex(), which is the only thing standing between a sub-pixel ring and the
		// rasterizer's binary coverage.
		float half_footprint = 0.5 * max(footprint, 1e-4);
		float inside = min(texel_position + half_footprint, texture_width)
				- max(texel_position - half_footprint, 0.0);
		float coverage = clamp(inside / (2.0 * half_footprint), 0.0, 1.0)
				* clamp(plane_screen_thickness, 0.0, 1.0);

		// GEOMETRY, per fragment: a ring plane spans a wide range of both angles from a
		// camera close to it, and the two elevations are what the whole model turns on.
		vec3 to_camera = normalize(CAMERA_POSITION_WORLD - v_world_position);
		vec3 to_sun = normalize(illumination_position - v_world_position);
		float cos_view = dot(plane_normal, to_camera);
		float cos_sun = dot(plane_normal, to_sun);
		float mu = max(abs(cos_view), MIN_MU);
		float mu0 = max(abs(cos_sun), MIN_MU);

		// PHASE. Level as a straight line in magnitudes between the two lit profiles'
		// own phase angles, plus the narrow opposition surge; shape as the mix between
		// them the source describes ("with increasing phase angle their appearance
		// gradually changes to the appearance of the forward scattering profile").
		float phase = acos(clamp(dot(to_sun, to_camera), -1.0, 1.0));
		float phase_span = max(forward_phase - back_phase, 1e-4);
		float phase_fraction = (phase - back_phase) / phase_span;
		float level = pow(max(forward_level, 1e-6), phase_fraction)
				* (1.0 + opposition_surge * exp(-phase / max(opposition_width, 1e-6)));
		float shape_mix = clamp(phase_fraction, 0.0, 1.0);

		bool lit_face = cos_view * cos_sun > 0.0;
		vec4 texel;
		if (lit_face) {
			vec4 back = textureLod(rings_textures, vec3(u, 0.5, 0.0), lod);
			vec4 forward = textureLod(rings_textures, vec3(u, 0.5, 1.0), lod);
			forward.r *= forward_reddening;
			// Alpha is the same in both layers, so the mix leaves it exactly alone.
			texel = mix(back, forward, shape_mix);
		} else {
			texel = textureLod(rings_textures, vec3(u, 0.5, 2.0), lod);
			texel.rgb *= unlit_level;
		}
		texel.rgb *= level; // one phase function, both faces; see the header

		float tau = -log(max(1.0 - texel.a, MIN_TRANSMISSION));
		float geometry = lit_face ? ring_reflection(tau, mu, mu0)
				: ring_transmission(tau, mu, mu0) + unlit_floor * mu0;
		vec3 scattering = texel.rgb * scattering_scale;

		// Rebuilt ambient (engine ambient is disabled; see render_mode), computed as the
		// same slab lit from straight overhead by a uniform sky - so it carries no phase
		// term and does not vanish on the unlit face, where the sun's own term nearly
		// does. Added before the shadow, so occlusion removes sunlight and not starlight.
		// The feed already carries exposure; see the include.
		float sky = 1.0 / (mu + 1.0) * (1.0 - exp(-tau * (1.0 / mu + 1.0)));
		vec3 radiance = scattering * (sky * ambient_light);

		// Planet (and moon) shadows on the rings; the ring term itself stays disabled here
		// (rings don't shadow themselves; also its fwidth() must not run in a non-uniform
		// branch). Self-lit, so the shadow multiplies the sun's term directly - no AO, and
		// no albedo stand-in on the display-referred renderer.
		float sun_visible = 1.0;
		if (occluder_count > 0) {
			sun_visible = sun_occlusion_visible_fraction(v_world_position);
		}
		radiance += scattering * (geometry * sun_light_energy * sun_visible);

		// debug lod mapping
		//radiance = vec3(lod / 8.0, lod / 8.0, 1.0 - lod / 8.0);

		// A premultiplied fragment's colour IS its whole term, so there is nothing to
		// restate against what lies behind (see display_mix's hazard note): the ring's
		// finished radiance goes through display_write() and the blend's own (1 - alpha)
		// attenuation of the background is left to the hardware.
		ALBEDO = vec3(0.0);
		EMISSION = display_write(radiance * coverage);
		ALPHA = (1.0 - exp(-tau / mu)) * coverage;
	}
}
