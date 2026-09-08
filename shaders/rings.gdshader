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
// THE MODEL, ITS DERIVATION AND THE MEASUREMENTS BEHIND EVERY CHOICE IN IT ARE IN
// PHOTOMETRIC_MODEL.md's *Rings* section. Read it before changing a term here, and put a
// finding there rather than in this header - two copies of one fact leave the code copy to
// go stale, and it is the copy nobody re-reads. What follows is what a caller, a table
// author or a maintainer of this file has to know to use it correctly.
//
// THE TEXTURE. One imported CompressedTexture2DArray of three width x 1 layers, built for
// Saturn by addons/tools/build_saturn_rings.py from Bjoern Joensson's radial ring profiles
// (https://bjj.mmedia.is/data/s_rings).
//
//   rgb  LINEAR SCATTERING STRENGTH, which is NOT radiance: the observing geometry of the
//        source images is divided out, so what the file holds is a property of the
//        particles and the geometry term below is what puts it back at the angles being
//        rendered. Not source_color - the values are already linear on both renderers.
//   a    1 - transmission at NORMAL incidence, from a stellar occultation, so
//        `tau = -ln(1 - a)` is the normal optical depth, identical in all three layers.
//
//   layer 0  the lit face at `back_phase`     |  layer 2  the unlit face
//   layer 1  the lit face at `forward_phase`  |
//
// THE GEOMETRY TERM, with mu and mu0 the sines of the camera's and the sun's elevation
// above the ring plane and `T(rate)` the layer's transmission at that rate through the
// beam:
//
//   lit    mu0/(mu+mu0) * (1 - T(1/mu + 1/mu0))
//   unlit  mu0/(mu0-mu) * (T(1/mu0) - T(1/mu))
//
// `T(rate) = (1 + rate tau / clumping)^-clumping` takes optical depth as gamma-distributed
// across the beam, self-gravity wakes being what makes it vary, with the homogeneous slab
// as the large-`clumping` limit. Both faces saturate rather than diverge, so nothing here
// needs a clamp. This is what makes the rings answer to their opening angle: as the camera
// drops toward the plane the optically thin rings brighten toward the saturated value while
// an already-saturated one barely moves.
//
// WHICH TABLE CELLS ARE DERIVED. `clumping` and `unlit_level` must match what the build
// printed - the texture's strength was divided by the first and both faces are put on one
// scattering strength by the second - and `scattering_scale`, `opposition_surge` and
// `opposition_width` are fitted together with the level, so moving one alone breaks the
// anchor. `back_phase` and `forward_phase` are the source profiles' own phase angles.
// `forward_level` and `forward_reddening` are the two judgment cells. Every default below
// is Saturn's shipped value.
//
// PHASE carries the level and the texture carries only the shape, the three profiles being
// published independently peak-normalized. It is evaluated per fragment, so a close camera
// gets the local opposition spot under it. BOTH faces take the same phase term, which is
// physics rather than convenience - a photon's scattering angle is 180 - phase whichever
// side the observer is on - and what differs between them is the geometry term above.
//
// WHICH FACE is decided per fragment from the signs of the two elevations, so a camera
// close to the plane correctly sees the lit face on one side of itself and the unlit face
// on the other. FRONT_FACING, unreliable on some GPUs as of Godot 4.2.2, is not used.
//
// THE OUTPUT IS PREMULTIPLIED: rgb is the ring's own light over black sky and alpha is what
// it occludes, so the blend forms `light + (1 - alpha) * background` and RGB MUST NEVER BE
// SCALED BY ALPHA AGAIN. Alpha is the SLANT occlusion, `1 - (1-a)^(1/mu)`: a ring seen
// edge-on hides what is behind it however thin it is at normal incidence. Both are scaled
// together by COVERAGE, which is what makes a partly covered fragment composite correctly.
//
// SELF-LIT ON BOTH RENDERERS, AND THE FRAGMENT MUST ZERO SPECULAR AS WELL AS ALBEDO. The
// engine flips a double-sided primitive's normal, so an engine-lit ALBEDO renders N.L = 0
// on whichever face is turned away; and a spatial shader that sets neither ALBEDO nor
// SPECULAR gets Godot's defaults, whose F0 = 0.04 lobe the engine then adds on top of
// EMISSION - unshadowed, since the occlusion here multiplies only our own term, and
// Fresnel-amplified toward 1.0 at exactly the grazing angles a ring is seen at.
//
// GOING EDGE-ON BREAKS IN TWO PLACES and no single term fixes both. What a covered pixel is
// WORTH is COVERAGE: the share of that pixel's own APERTURE on the ring plane that lands on
// the ring, the pixel's box convolved with the camera's point spread function
// (`iv_psf_sigma`, the same Gaussian that images every star and every sunlit rim) on BOTH
// screen axes, integrated between the annulus' two chord crossings. The same aperture sets
// the texture filter's width and where it is read, on both axes for the same reason - at an
// ansa the view ray runs tangent, so the across axis carries the whole of the pixel's
// radial spread. Whether the pixel is DRAWN AT ALL is the rasterizer's: without MSAA a
// fragment exists only where the primitive covers a pixel CENTRE, so vertex() TILTS the
// plane about the camera's own ground line until its projected minor axis reaches
// MIN_SCREEN_THICKNESS and fragment() divides the light by exactly the factor it was
// thickened. A rigid tilt magnifies the image by ONE number, which is what makes that
// exact; it is also what pays for the outward EXPANSION the aperture's reach needs, since
// magnifying shrinks the footprint, and it is capped at face on because a ring is thin on
// screen from distance as well as from foreshortening.
//
// PAST THE SIZE AT WHICH A PLANE CAN BE RASTERIZED AT ALL, the rings hand their light to
// body_psf.gdshader's quad, and `plane_light_fraction` is this end of that crossfade. It
// scales COVERAGE, which is what a fragment holding only part of a ring already means, so
// the light and the occlusion fade together and the pair carries the ring's light exactly
// once at every distance. IVRings publishes the other end.
//
// THE PLANE PASSES THROUGH ITS OWN PLANET, and the part inside must not draw: every ray
// that reaches it meets the globe first. The coverage term cannot tell, its aperture
// reaching most of a plane radius at a grazing view, so such a fragment would gather real
// ring light from outside the globe and draw it across the planet's face.

#include "_display.gdshaderinc"
#include "_farwarp.gdshaderinc"
#include "_sun_occlusion.gdshaderinc"

// Global sharpness knob on the texture filter's width: below 1.0, more detail and more
// aliasing.
const float FILTER_WIDTH_MULTIPLIER = 1.0;
// A grazing ray's optical path is tau/mu, and mu reaches zero at the plane. Nothing
// diverges there (every term saturates), but the ratio has to stay finite: at this floor
// tau/mu tops out around 1e5, which exp() answers with a clean zero.
const float MIN_MU = 1e-4;
// Alpha 1.0 means the occultation saw nothing through, which is a floor on tau and not a
// measurement of it, so transmission is capped to keep the derived tau finite and close to
// the deepest the source really measures (Saturn's is 5.55 against the 6.91 this admits).
const float MIN_TRANSMISSION = 0.001;
// Pixels of projected minor axis the plane is tilted up to when it would render thinner;
// see THE APERTURE. The ring's own band is a fraction of that minor axis - 0.85 of it at
// an ansa and 0.23 across the middle for Saturn's radius ratio - and what has to clear a
// pixel is the band, so this is set for the ansa, which is the part of a nearly edge-on
// ring anyone is looking at. The ceiling only guards the degenerate view from inside the
// plane at the ring's own centre.
const float MIN_SCREEN_THICKNESS = 3.5;
const float MAX_MAGNIFICATION = 64.0;
// How far out the aperture is drawn, in its own sigmas, and how far the plane may be
// expanded to hold that, in plane radii. Six sigma is where a Gaussian stops being
// representable at the WORST exposure this camera reaches - a ring metered and then left
// at the dark-adapted rest, about 15 stops, where one 8-bit code is 1e-7 of the peak. It
// agrees with the star field's own cut: psf_visible_size() at that intensity is 5.6 px
// across against the 6.9 this draws. Beyond it the truncation costs nothing measurable.
const float APERTURE_REACH = 6.0;
const float MAX_PLANE_EXTENT = 8.0;
// Variance of a one-pixel box, in px^2. The aperture is that box convolved with the
// camera's Gaussian, taken as a single Gaussian of the summed variance: within 0.002 of
// the true convolution at the shipped psf sigma and 0.044 at the smallest one offered,
// which is a difference between two reconstruction filters rather than an error.
const float PIXEL_BOX_VARIANCE = 0.0833333;
const float SQRT_3 = 1.7320508;
const float SQRT_2 = 1.4142136;
// The aperture's OTHER screen axis, integrated by Gauss-Hermite in units of its own sigma.
// Five nodes rather than three because what it has to resolve is a square root: the chord
// through a circle has infinite slope at the tangency, so the correction never becomes
// smooth however small the sigma is. Measured against convolved ray casts, the drawn
// shape's aspect at 700 plane radii runs 2.28, 1.50, 1.18, 1.04 at one, three, five and
// seven nodes against a true 0.69, and the whole-frame rms close in runs 0.0175, 0.0063,
// 0.0043 - so five is where both stop paying.
const int APERTURE_NODES = 5;
const float APERTURE_OFFSETS[5] = {-2.8569700, -1.3556262, 0.0, 1.3556262, 2.8569700};
const float APERTURE_WEIGHTS[5] = {0.0112574, 0.2220759, 0.5333333, 0.2220759, 0.0112574};

// set by rings.gd once
uniform sampler2DArray rings_textures : filter_linear_mipmap, repeat_disable;
uniform float texture_width; // texels across one layer
uniform float texture_start; // texture's inner edge, as a fraction of the plane's radius
uniform float texture_end; // texture's outer edge, same units (> texture_start)

// The camera's PSF width in px, IVPSFSettings.psf_sigma - the same global the body surface
// shaders image a sunlit rim with (see _photometry.gdshaderinc). Unset it reads 0.0, which
// leaves the aperture the pixel box alone; that is the pre-2026-09-06 behaviour and is why
// nothing here needs a fallback.
global uniform float iv_psf_sigma;

// photometry, all from rings.tsv; see the header
uniform float back_phase = 0.0; // radians; phase angle of texture layer 0
uniform float forward_phase = 2.4260765; // radians; phase angle of texture layer 1
uniform float forward_level = 0.25; // lit brightness at forward_phase, relative to back_phase
uniform float forward_reddening = 1.05; // red multiplier at forward_phase
uniform float unlit_level = 0.1085; // texture layer 2's level, relative to layer 0
uniform float clumping = 1.0e6; // optical-depth spread across the beam; see the header
uniform float opposition_surge = 0.515; // fractional brightening added at zero phase
uniform float opposition_width = 0.0154113; // radians; e-folding width of that surge
uniform float scattering_scale = 0.545; // overall level; the profiles are peak-normalized

// set by rings.gd every frame
uniform vec3 illumination_position;
// The share of the ring's own light this plane draws; body_psf.gdshader's quad carries the
// rest. 1.0 until the ring's projected image is a few pixels across - see the header.
uniform float plane_light_fraction = 1.0;

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
varying flat float plane_extent; // how far the plane is drawn, in plane radii; >= 1.0


// erfc, in Numerical Recipes' Chebyshev form. Its error is FRACTIONAL and below 1.2e-7
// everywhere, which is what the aperture needs: it is read out to six sigma, where an
// absolute-error approximation (Abramowitz & Stegun 26.2.17, the obvious choice) is 3.6e-3
// out and a difference of two tails is then noise. The exp(-z*z) factor is what carries
// that; do not simplify it away.
float ring_erfc(float x) {
	float z = abs(x);
	float t = 2.0 / (2.0 + z);
	float poly = -1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418
			+ t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587
			+ t * (-0.82215223 + t * 0.17087277))))))));
	float value = t * exp(-z * z + poly);
	return x >= 0.0 ? value : 2.0 - value;
}


// The camera's aperture width in PIXELS: its own point spread function widened by the
// pixel's box. See THE APERTURE.
float ring_aperture_sigma() {
	float sigma = max(iv_psf_sigma, 0.0);
	return sqrt(sigma * sigma + PIXEL_BOX_VARIANCE);
}


// The share of the aperture lying between [param low] and [param high], both measured
// from the fragment along the footprint axis. Clamping to +-[param limit] is the
// truncation at APERTURE_REACH sigma: the weight then reaches exactly zero where the
// plane's own rim is, continuously, so there is no edge to fade. Written as a difference
// of erfc rather than of Phi so that neither tail is formed as 1 - (1 - tiny).
float ring_aperture_weight(float low, float high, float sigma, float limit) {
	float scale = 1.0 / (sigma * SQRT_2);
	return 0.5 * (ring_erfc(clamp(low, -limit, limit) * scale)
			- ring_erfc(clamp(high, -limit, limit) * scale));
}


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

	// The camera in the ring plane's own frame. MODEL_MATRIX's x and z columns are the
	// plane's own axes scaled by the plane radius, so dividing the projection onto them by
	// that scale twice lands a world offset straight in plane radii. A zero-thickness
	// plane really does vanish edge-on, and modelling a ring's true thickness would not
	// change that (10 m against a 140,000 km radius is 7e-8, sub-pixel until the camera is
	// within ~10 km of the plane); what the coverage term in fragment() has to handle is
	// the APPROACH, where the rasterizer's own coverage goes binary.
	vec3 center_to_camera = CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz;
	float plane_radius = max(length(MODEL_MATRIX[0].xyz), 1e-9); // the model's own x scale
	camera_plane_position = vec2(dot(center_to_camera, MODEL_MATRIX[0].xyz),
			dot(center_to_camera, MODEL_MATRIX[2].xyz)) / (plane_radius * plane_radius);
	camera_plane_height = dot(center_to_camera, plane_normal) / plane_radius;
	pixel_angle = 2.0 / max(VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]), 1e-9);

	// THE EDGE-ON TILT, and THE OUTWARD EXPANSION, which are one calculation because the
	// tilt is what makes the expansion affordable. The projected minor axis is
	// `2 R sin B / d` in radians, which the far-field form gives at every distance because
	// it only bites when it is small - and small is when the far field holds.
	float ground_length = max(length(camera_plane_position), 1e-6);
	float camera_range_squared = ground_length * ground_length
			+ camera_plane_height * camera_plane_height;
	float minor_axis = 2.0 * abs(camera_plane_height)
			/ max(pixel_angle * camera_range_squared, 1e-30);

	// The aperture's reach is APERTURE_REACH sigmas of the fragment's own footprint, and
	// the footprint is largest where the plane is farthest - its own far rim. Sizing on
	// that point is what guarantees no fragment's aperture is ever cut, because a nearer
	// one reaches less far. Note the reach here is the numerator only: it still has to be
	// divided by the elevation the tilt renders at, which is what the two lines below do.
	float far_ground = ground_length + 1.0;
	float far_slant = sqrt(far_ground * far_ground
			+ camera_plane_height * camera_plane_height);
	float far_mu = max(abs(camera_plane_height) / far_slant, MIN_MU);
	float reach = APERTURE_REACH * ring_aperture_sigma() * pixel_angle * far_slant;

	// So the tilt has two jobs. MIN_SCREEN_THICKNESS keeps the ring's own image on pixel
	// centres; MAX_PLANE_EXTENT keeps the plane affordable, and tilting is how - the reach
	// is measured in footprints, magnifying shrinks the footprint, and both are exactly
	// flux-neutral. Untilted, a camera at its floor against a hairline ring would want a
	// plane twenty times the ring's radius.
	//
	// AND IT IS CAPPED AT FACE ON, because a ring is thin on screen for two different
	// reasons and the tilt only answers one of them. Foreshortening is what it is for;
	// DISTANCE is not, and the minor axis alone cannot tell them apart. The projected
	// ellipse's own aspect is `major / minor` = `range / height`, so magnifying past that
	// makes the ring TALLER than it is wide - measured at 4000 plane radii, a 0.50 px ring
	// held 3.5 px tall, a dash across the ring's own long axis. The cap is
	// `1 / sin(elevation)`, so it diverges at grazing and is inert wherever the tilt is
	// really answering foreshortening; it bites only on a ring that is small in BOTH
	// directions.
	magnification = clamp(min(max(MIN_SCREEN_THICKNESS / max(minor_axis, 1e-30),
			reach / (far_mu * max(MAX_PLANE_EXTENT - texture_end, 1e-6))),
			sqrt(camera_range_squared) / max(abs(camera_plane_height), 1e-30)),
			1.0, MAX_MAGNIFICATION);
	plane_extent = min(texture_end + reach / min(far_mu * magnification, 1.0),
			MAX_PLANE_EXTENT);

	// The shared plane mesh is 2 x 2 in its own x and z and is scaled by the plane radius,
	// so VERTEX.xz IS the fragment's position in the ring plane, in plane radii - and
	// scaling it here is the expansion itself, leaving texture_start and texture_end
	// meaning what they always did.
	VERTEX.xz *= plane_extent;
	v_plane_position = VERTEX.xz;
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Lifting each point by its own distance along the camera's ground direction, times
	// `(M - 1) tan B`, scales the image by M and leaves the surface a PLANE: it is a
	// rotation about the ground line, not a distortion, which is what lets one number
	// describe the whole change. It runs after v_world_position, which keeps the true
	// geometry every photometric term needs.
	VERTEX.y -= (magnification - 1.0) * camera_plane_height * plane_radius
			* dot(VERTEX.xz, camera_plane_position) / (ground_length * ground_length);

	// Farwarp remap under skip_vertex_transform. NORMAL is transformed identically to the
	// engine default (farwarp_lit_vertex); only the depth is compressed.
	farwarp_lit_vertex(MODELVIEW_MATRIX, MODELVIEW_NORMAL_MATRIX, VERTEX, NORMAL);
}


void fragment() {

	float r = length(v_plane_position);

	if (r > plane_extent) {
		discard; // outside the drawn plane's own inscribed circle

	} else if (sun_occlusion_inside_occluder(v_world_position)) {
		// INSIDE THE PLANET, which the plane runs through: every ray that reaches this
		// fragment meets the globe first, so it is not a place the ring can be seen from.
		// The coverage term cannot tell - its aperture reaches most of a plane radius at a
		// grazing view, so a fragment buried in the planet still gathers real ring light
		// from outside it and draws it over the planet's face. The sun term's own occluder
		// is that same figure, so asking costs one dot product.
		discard;

	} else {

		// COVERAGE, exactly: the share of this pixel's APERTURE on the ring plane that
		// lands on the ring. The footprint runs along the view direction's own in-plane
		// component and is `pixel_angle * distance / mu` long per pixel, so it is
		// sub-texel face on and reaches out past the far edge of the system at a low
		// opening angle. The ring's radius along it obeys `r(t)^2 = r^2 + 2 t (p.u) + t^2`,
		// and a line whose closest approach to the centre is `across` crosses a circle of
		// radius R over a half-chord `sqrt(R^2 - across^2)`, so both ends of the annulus
		// close in four lines and the aperture is integrated between them. This is the only
		// term standing between a sub-pixel ring and the rasterizer's binary coverage, so
		// it is also what discards: a fragment whose aperture reaches the ring has to draw,
		// and one whose aperture does not must not.
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
		float footprint = max(pixel_angle * slant_distance / rendered_mu, 1e-12);
		float aperture_sigma = ring_aperture_sigma() * footprint;
		float limit = APERTURE_REACH * aperture_sigma;
		float along = dot(v_plane_position, footprint_axis);
		float across = sqrt(max(r * r - along * along, 0.0));
		// The aperture's other screen axis. A pixel measured PERPENDICULAR to the view
		// direction is unforeshortened, so this is the pixel's own size and carries none
		// of the tilt's factor.
		float across_sigma = ring_aperture_sigma() * pixel_angle * slant_distance;
		float coverage = 0.0;
		for (int node = 0; node < APERTURE_NODES; node++) {
			float shifted = abs(across + APERTURE_OFFSETS[node] * across_sigma);
			float outer_half_chord = sqrt(max(texture_end * texture_end - shifted * shifted,
					0.0));
			float weight = ring_aperture_weight(-along - outer_half_chord,
					-along + outer_half_chord, aperture_sigma, limit);
			// The hole is only in the way where the ray's own line crosses it, which is a
			// large part of a face-on ring and skips two erfc calls there.
			if (shifted < texture_start) {
				float inner_half_chord = sqrt(texture_start * texture_start
						- shifted * shifted);
				weight -= ring_aperture_weight(-along - inner_half_chord,
						-along + inner_half_chord, aperture_sigma, limit);
			}
			coverage += APERTURE_WEIGHTS[node] * weight;
		}
		coverage = clamp(coverage, 0.0, 1.0) * plane_light_fraction / magnification;
		if (coverage <= 0.0) {
			discard; // no ring in this pixel's aperture, or the point source has it all
		}
		float outer_half_chord = sqrt(max(texture_end * texture_end - across * across, 0.0));

		// The same segment picks the filter and where it is read: the radial span the
		// covered part actually crosses. What the filter has to match is the aperture's own
		// width, so the box here is the one of equal variance - `sqrt(3) sigma`, which is
		// exactly half the pixel footprint again when there is no PSF.
		float filter_half = SQRT_3 * aperture_sigma;
		float begin = clamp(-along - outer_half_chord, -filter_half, filter_half);
		float end = clamp(-along + outer_half_chord, -filter_half, filter_half);
		float begin_radius = sqrt(max(r * r + 2.0 * along * begin + begin * begin, 0.0));
		float end_radius = sqrt(max(r * r + 2.0 * along * end + end * end, 0.0));
		float min_radius = (begin <= -along && -along <= end) ? across
				: min(begin_radius, end_radius);
		min_radius = max(min_radius, texture_start); // the hole is not part of the average
		float max_radius = max(max(begin_radius, end_radius), min_radius);
		float read_radius = 0.5 * (min_radius + max_radius);
		// The across axis, which the segment cannot see and which at an ansa is the radial
		// direction itself. Shifting the ray across moves its whole closest approach with
		// it, so `dR/dc = c/R` projects that extent onto the radius; the two combine as
		// VARIANCES, summing their supports being what over-widens the far field.
		float across_width = 2.0 * SQRT_3 * across_sigma
				* min(across / max(read_radius, 1e-12), 1.0);
		float radial_width = sqrt((max_radius - min_radius) * (max_radius - min_radius)
				+ across_width * across_width);
		float texture_span = texture_end - texture_start;
		float lod = log2(max(texture_width * radial_width / texture_span
				* FILTER_WIDTH_MULTIPLIER, 1.0));
		float u = (read_radius - texture_start) / texture_span;

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
		float sky = ring_reflection(tau, mu, 1.0);
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

		// A premultiplied fragment's colour IS its whole term, so there is nothing to
		// restate against what lies behind (see display_mix's hazard note): the ring's
		// finished radiance goes through display_write() and the blend's own (1 - alpha)
		// attenuation of the background is left to the hardware.
		// SPECULAR to zero, not just ALBEDO; see the header.
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		EMISSION = display_write(radiance * coverage);
		ALPHA = (1.0 - exp(-tau / mu)) * coverage;
	}
}
