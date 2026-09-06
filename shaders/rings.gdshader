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
//   unlit  mu0/(mu0-mu) * (T(1/mu0) - T(1/mu))
//
// A real ring is not a uniform sheet: self-gravity wakes make optical depth vary across the
// beam, and a clumpy layer saturates more SLOWLY than a homogeneous one, because the thin
// lanes keep contributing after the dense parts have gone opaque. Taking tau as
// gamma-distributed about its mean with shape `clumping` gives
// `T = (1 + rate tau / clumping)^-clumping`, whose limit at large `clumping` is exactly
// exp(-rate tau), which is where Saturn's cell sits: NOTHING IN THE SOURCE PROFILES
// CONSTRAINS IT, so it is pinned rather than fitted. The lit profile cannot see it at all
// (that fit's R2 moves 0.8733 to 0.8787 across the entire family), and the unlit profile
// only appears to, because the leverage came from its flat deep end -- which is the image
// pedestal described below. Scanned on the live radii with the pedestal removed, R2 moves
// 0.0164 across the whole family against a factor of FORTY in what the parameter does. So
// every fit returns a number that looks like an answer and is not one: 1.7 off the lit
// profile (which shipped briefly and let the dense B ring pass 15 % of the sun's light),
// 22.8 with the pedestal left in as a free floor, 2.5 on the live radii. Pinned at the
// homogeneous limit the model has no free parameter here and takes the family's DARKEST
// transmission, which is also the closest to what real unlit images show.
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
// THE UNLIT FACE HAS NO FLOOR UNDER IT, AND THE ONE IT USED TO HAVE WAS THE SOURCE IMAGE'S
// BACKGROUND. Joensson's unlit profile stops falling at 0.046 by tau 1.4 and is flat to 4 %
// from there to tau 13.8 - a decade of optical depth over which single scattering falls a
// millionfold and even diffuse transmission falls threefold - so what it measures past that
// point is his own image background, not light through the rings. Fitted as a constant and
// carried here, it put a floor under the unlit face that did not fall with tau at all, so an
// opaque ring glowed: at a 26.7 degree opening it was 63 % of what the B ring rendered.
// build_saturn_rings.py now subtracts it instead, and where the subtraction leaves nothing
// takes the strength from the lit layer, whose ratio to this one is a measured constant.
// So the unlit face's whole tau response is the term below and nothing else. Note what that
// leaves out: real multiple scattering inside a dense layer is NOT zero, and a truly opaque
// B ring renders black here where a real one is merely very dark.
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
// Both are scaled together by COVERAGE, which is what makes a partly covered fragment
// composite correctly.
//
// COVERAGE IS THE WHOLE OF WHAT A ZERO-THICKNESS PLANE HAS TO SAY ABOUT GOING EDGE-ON,
// and going edge-on breaks it in two separate places - what a covered pixel is worth, and
// whether the pixel is drawn at all. Both were wrong, and neither is fixed by the other.
//
// FIRST, THE VALUE. A pixel's cone meets the plane in a segment that lengthens as 1/mu,
// so at a low opening angle one pixel spans the whole ring and out the far side, and the
// share of it that is ring falls as sin(elevation). That share is computed exactly here:
// the radius along the segment obeys `r(t)^2 = r^2 + 2 t (p.u) + t^2`, and a line whose
// closest approach to the centre is `across` crosses a circle of radius R over a
// half-chord `sqrt(R^2 - across^2)`, so both ends of the annulus close in four lines. The
// retired term instead took a FIRST-ORDER radial footprint from a screen derivative and
// measured it against the texture's span, which is a different quantity and over-reports:
// at an ansa the ray runs tangent to a circle of constant radius, so the derivative
// carries almost nothing of the radial spread the pixel really holds (a quad's one-pixel
// difference recovers some of the curvature, which is the only reason it was not worse).
// Measured against ray-cast truth at 1080p from six ring radii, its rendered flux ran
// 0.79, 1.01 and 1.19 of truth as the projected minor axis passed 3, 2 and 1.5 pixels -
// its brightest pixel pinned at a full 1.000 the whole way - where the segment holds 0.86
// to 0.88 flat and its brightest pixel falls 1.000, 0.751, 0.501, 0.300, 0.150. The same
// segment sets the texture filter and where it is sampled, for the same reason.
//
// SECOND, THE RASTERIZER, which no coverage term can argue with. Without MSAA a fragment
// exists only where the primitive covers a pixel CENTRE, so once the ring's image is
// thinner than a pixel the line goes dashed - a fraction t of it lit, each lit pixel worth
// t, so flux falls as t SQUARED - and then, when the band falls between two rows of pixel
// centres, it disappears whole. Measured, the lit count goes 996, 682, 408, 0 as the minor
// axis passes 1.5, 1.2, 1.0 and 0.8 pixels, and the last pixels drawn stand at half
// brightness. So vertex() TILTS the plane about the camera's own ground line until its
// projected minor axis is MIN_SCREEN_THICKNESS pixels, and fragment() divides the ring's
// light by exactly the factor it was thickened.
//
// The tilt is exact rather than a fudge, and the reason is that a rigid tilt magnifies the
// image by ONE number: a screen pixel's footprint on the true plane shrinks by that same
// number, so evaluating the coverage at the TILTED elevation and dividing by the
// magnification conserves flux at every local thickness that still rasterizes, while the
// per-pixel value keeps falling with the TRUE opening angle. Measured, the lit count is
// then constant at 1162 from a 2-pixel minor axis down to 0.3, the flux is proportional to
// sin(elevation) over that whole range to better than 1 %, and the brightest pixel falls
// 0.751, 0.501, 0.300, 0.150 - which is what the last visible line fading to black looks
// like. What it costs is the sub-pixel middle of the ring, whose own band is only 0.23 of
// the minor axis for Saturn's radius ratio and so still dashes: 0.86 of the true flux
// against 0.92 at MIN_SCREEN_THICKNESS 6.0, which buys that back and smears the ring over
// 2.4 times as many rows. Only the footprint and the divide see the tilt; every
// photometric term takes the real geometry.
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
// Pixels of projected minor axis the plane is tilted up to when it would render thinner;
// see THE OUTPUT. The ring's own band is a fraction of that minor axis - 0.85 of it at an
// ansa and 0.23 across the middle for Saturn's radius ratio - and what has to clear a
// pixel is the band, so this is set for the ansa, which is the part of a nearly edge-on
// ring anyone is looking at. The ceiling only guards the degenerate view from inside the
// plane at the ring's own centre.
const float MIN_SCREEN_THICKNESS = 2.0;
const float MAX_MAGNIFICATION = 64.0;

// set by rings.gd once
uniform sampler2DArray rings_textures : filter_linear_mipmap, repeat_disable;
uniform float texture_width; // texels across one layer
uniform float texture_start; // texture's inner edge, as a fraction of the plane's radius
uniform float texture_end; // texture's outer edge, same units (> texture_start)
uniform float outer_margin; // the plane's own inscribed circle, in plane radii

// photometry, all from rings.tsv; see the header
uniform float back_phase = 0.0; // radians; phase angle of texture layer 0
uniform float forward_phase = 2.4260765; // radians; phase angle of texture layer 1
uniform float forward_level = 0.25; // lit brightness at forward_phase, relative to back_phase
uniform float forward_reddening = 1.05; // red multiplier at forward_phase
uniform float unlit_level = 0.1510; // texture layer 2's level, relative to layer 0
uniform float clumping = 1.0e6; // optical-depth spread across the beam; see the header
uniform float opposition_surge = 0.25; // fractional brightening added at zero phase
uniform float opposition_width = 0.0349066; // radians; e-folding width of that surge
uniform float scattering_scale = 0.486; // overall level; the profiles are peak-normalized

// set by rings.gd every frame
uniform vec3 illumination_position;

// varyings. The coverage term works in the ring plane's OWN 2D frame, measured in plane
// radii: the numbers there are of order one whatever the world scale, and a fragment's
// position in it is just the mesh's own x and z.
varying vec3 v_world_position; // true world position; VERTEX is farwarp-remapped
varying vec2 v_plane_position; // the fragment in the ring plane, in plane radii
varying flat vec3 plane_normal; // unit, world space; either sign works
varying flat vec2 camera_plane_position; // the camera's own, same frame and units
varying flat float camera_plane_height; // its signed height above the plane, same units
varying flat float pixel_angle; // radians of frame height subtended by one pixel
varying flat float magnification; // the edge-on tilt's image scale; 1.0 unless sub-pixel


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
	// The shared plane mesh is 2 x 2 in its own x and z and is scaled by the plane radius,
	// so VERTEX.xz IS the fragment's position in the ring plane, in plane radii.
	v_plane_position = VERTEX.xz;

	// The camera in that same frame. MODEL_MATRIX's x and z columns are the plane's own
	// axes scaled by the plane radius, so dividing the projection onto them by that scale
	// twice lands a world offset straight in plane radii. A zero-thickness plane really
	// does vanish edge-on, and modelling a ring's true thickness would not change that
	// (10 m against a 140,000 km radius is 7e-8, sub-pixel until the camera is within
	// ~10 km of the plane); what the coverage term in fragment() has to handle is the
	// APPROACH, where the rasterizer's own coverage goes binary.
	vec3 center_to_camera = CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz;
	float plane_radius = max(length(MODEL_MATRIX[0].xyz), 1e-9); // the model's own x scale
	camera_plane_position = vec2(dot(center_to_camera, MODEL_MATRIX[0].xyz),
			dot(center_to_camera, MODEL_MATRIX[2].xyz)) / (plane_radius * plane_radius);
	camera_plane_height = dot(center_to_camera, plane_normal) / plane_radius;
	pixel_angle = 2.0 / max(VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]), 1e-9);

	// THE EDGE-ON TILT. The projected minor axis is `2 R sin B / d` in radians, which the
	// far-field form gives at every distance because it only bites when it is small - and
	// small is when the far field holds. Lifting each point by its own distance along the
	// camera's ground direction, times `(M - 1) tan B`, scales the image by M and leaves
	// the surface a PLANE: it is a rotation about the ground line, not a distortion, which
	// is what lets one number describe the whole change.
	float ground_length = max(length(camera_plane_position), 1e-6);
	float camera_range_squared = ground_length * ground_length
			+ camera_plane_height * camera_plane_height;
	float minor_axis = 2.0 * abs(camera_plane_height)
			/ max(pixel_angle * camera_range_squared, 1e-30);
	magnification = clamp(MIN_SCREEN_THICKNESS / max(minor_axis, 1e-30), 1.0,
			MAX_MAGNIFICATION);
	VERTEX.y -= (magnification - 1.0) * camera_plane_height * plane_radius
			* dot(VERTEX.xz, camera_plane_position) / (ground_length * ground_length);

	// Farwarp remap under skip_vertex_transform. NORMAL is transformed identically to the
	// engine default (farwarp_lit_vertex); only the depth is compressed.
	farwarp_lit_vertex(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL);
}


void fragment() {

	float r = length(v_plane_position);

	if (r > outer_margin) {
		discard; // outside the plane's own inscribed circle

	} else {

		// COVERAGE, exactly: the share of this pixel's footprint on the ring plane that
		// lands on the ring. The footprint runs along the view direction's own in-plane
		// component and is `pixel_angle * distance / mu` long, so it is sub-texel face on
		// and reaches out past the far edge of the system at a low opening angle. Its
		// radius obeys `r(t)^2 = r^2 + 2 t (p.u) + t^2`, and a line whose closest approach
		// to the centre is `across` crosses a circle of radius R over a half-chord
		// `sqrt(R^2 - across^2)`, so both ends of the annulus close in four lines. This is
		// the only term standing between a sub-pixel ring and the rasterizer's binary
		// coverage, so it is also what discards: a fragment inside the hole whose footprint
		// reaches the ring has to draw, and one whose footprint does not must not.
		vec2 camera_to_fragment = v_plane_position - camera_plane_position;
		float ground_distance = length(camera_to_fragment);
		float slant_distance = max(sqrt(ground_distance * ground_distance
				+ camera_plane_height * camera_plane_height), 1e-9);
		float mu = max(abs(camera_plane_height) / slant_distance, MIN_MU);
		// Face on the footprint is isotropic and this direction is arbitrary; radially
		// outward is then the conservative choice, being where the ring's own edges are.
		vec2 footprint_axis = ground_distance > 1e-6 ? camera_to_fragment / ground_distance
				: (r > 1e-6 ? v_plane_position / r : vec2(1.0, 0.0));
		// The tilt shrinks a pixel's footprint on the true plane by its own magnification,
		// so the footprint takes the RENDERED elevation and the coverage is divided by the
		// same number below; every photometric term keeps the true `mu`.
		float rendered_mu = min(mu * magnification, 1.0);
		float half_footprint = max(0.5 * pixel_angle * slant_distance / rendered_mu, 1e-12);
		float along = dot(v_plane_position, footprint_axis);
		float across_squared = max(r * r - along * along, 0.0);
		float outer_half_chord = sqrt(max(texture_end * texture_end - across_squared, 0.0));
		float inner_half_chord = sqrt(max(texture_start * texture_start - across_squared, 0.0));
		float outer_length = max(min(half_footprint, -along + outer_half_chord)
				- max(-half_footprint, -along - outer_half_chord), 0.0);
		float inner_length = max(min(half_footprint, -along + inner_half_chord)
				- max(-half_footprint, -along - inner_half_chord), 0.0);
		float coverage = clamp((outer_length - inner_length) / (2.0 * half_footprint),
				0.0, 1.0) / magnification;
		if (coverage <= 0.0) {
			discard; // this pixel's footprint holds no ring
		}

		// The same segment picks the filter and where it is read: the radial span the
		// covered part actually crosses, which at an ansa is most of the outer ring where
		// a derivative reports nothing at all.
		float begin = max(-half_footprint, -along - outer_half_chord);
		float end = min(half_footprint, -along + outer_half_chord);
		float begin_radius = sqrt(max(r * r + 2.0 * along * begin + begin * begin, 0.0));
		float end_radius = sqrt(max(r * r + 2.0 * along * end + end * end, 0.0));
		float min_radius = (begin <= -along && -along <= end) ? sqrt(across_squared)
				: min(begin_radius, end_radius);
		min_radius = max(min_radius, texture_start); // the hole is not part of the average
		float max_radius = max(max(begin_radius, end_radius), min_radius);
		float texture_span = texture_end - texture_start;
		float lod = log2(max(texture_width * (max_radius - min_radius) / texture_span
				* DFDR_MULTIPLIER, 1.0));
		float u = (0.5 * (min_radius + max_radius) - texture_start) / texture_span;

		// GEOMETRY, per fragment: a ring plane spans a wide range of both angles from a
		// camera close to it, and the two elevations are what the whole model turns on.
		vec3 to_camera = normalize(CAMERA_POSITION_WORLD - v_world_position);
		vec3 to_sun = normalize(illumination_position - v_world_position);
		float cos_sun = dot(plane_normal, to_sun);
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

		bool lit_face = camera_plane_height * cos_sun > 0.0;
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
				: ring_transmission(tau, mu, mu0);
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
		// SPECULAR to zero, not just ALBEDO. A spatial shader that sets neither gets
		// Godot's defaults (SPECULAR 0.5, so F0 = 0.04), and the engine adds that lobe on
		// top of a self-lit EMISSION - unshadowed, since the occlusion above multiplies
		// only our own term, and Fresnel-amplified toward 1.0 at grazing incidence, which
		// is exactly where a ring is seen. Measured on a 8.3 deg view at phase 145: with
		// every light term in this shader disabled the ring plane still rendered a solid
		// 0.157 linear grey, which is 29 % of the lit ansa and the whole of what filled
		// the planet's shadow.
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		EMISSION = display_write(radiance * coverage);
		ALPHA = (1.0 - exp(-tau / mu)) * coverage;
	}
}
