// _photometry.gdshaderinc
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

// Disc photometry for a solid body: how a body's brightness falls from the subsolar
// point toward the limb and the terminator. Shared by the surface shaders so the law
// cannot drift between the equirect and cubemap paths; see PHOTOMETRIC_MODEL.md.
//
// The problem it solves: the engine's diffuse gives radiance proportional to mu0
// (cos incidence), and an airless regolith body does NOT do that. At full phase such a
// body is nearly FLAT across its disc - the full Moon reads as a disc, not as a lit
// ball - so a cos falloff renders half the projected disc about 1.4x too dark and its
// outer quarter about 2x too dark.
//
// The law is Lunar-Lambert (McEwen 1991; ISIS 'lunarlambert'), a one-parameter blend
// of Lommel-Seeliger and Lambert:
//
//   I = A * [ 2L * mu0 / (mu + mu0) + (1 - L) * mu0 ]
//
// L = 0 is Lambert exactly and L = 1 is Lommel-Seeliger, which is uniform across the
// disc at zero phase. Chosen over Minnaert (mu0^k * mu^(k-1)) because its RADIANCE is
// bounded everywhere - Minnaert's diverges at the limb and needs a clamp that has no
// physical meaning - and because L is the parameter planetary photometry publishes.
//
// Applied as a factor on ALBEDO rather than in a light() override: the engine's diffuse
// already supplies the leading mu0, so dividing it out leaves
//
//   ALBEDO *= 2L / (mu + mu0) + (1 - L)
//
// which keeps the specular lobe, AO / AO_LIGHT_AFFECT and the shadow path intact. It is
// an exact no-op at L = 0 AND at the subsolar-subobserver point (mu = mu0 = 1), so
// metering - which keys that point - is untouched and no shipped map level changes.

// A CLOUD DECK wants the other direction. Venus, Titan and the giants are limb-DARKENED
// relative to Lambert, and the law for that is Minnaert:
//
//   I = A * mu0^k * mu^(k-1)          Lambert = k = 1
//
// which in the same albedo-factor form (the engine again supplying the leading mu0) is
//
//   ALBEDO *= (mu0 * mu)^(k - 1)
//
// For k > 1 the exponent is positive, so the factor is bounded by 1, never negative, and
// still exactly 1.0 at mu = mu0 = 1. Only k < 1 diverges at the limb, and that direction
// is Lunar-Lambert's job, so this clamps k up to 1.0 rather than pretending to serve it.
//
// The two laws are complementary and meet at Lambert (L = 0 is k = 1). A NEGATIVE
// lunar_lambert would look like a way to get here from one parameter and is not: at zero
// phase its radiance is L + (1 - L)*t, which passes through zero at t = |L|/(1 + |L|) and
// puts a hard black ring around the limb - 2.8 % of the disc area at L = -0.2, 11 % at
// L = -0.5 - instead of darkening it.

// Guards the intermediate factor only. The factor diverges at the limb while the
// radiance it produces does not: the engine's own mu0 multiply cancels the divergence,
// leaving a bound of 2L. The clamp keeps ALBEDO finite where the body is already
// sub-pixel, and never binds anywhere the surface is resolved.
const float LUNAR_LAMBERT_FACTOR_MAX = 64.0;


// All three vectors in the SAME space (the shaders pass view space) and unit length.
// Pass the MACROSCOPIC normal, not the normal-mapped one: this is a law about the
// body's disc, and per-texel relief is the normal map's job. Returns 1.0 at el = 0.
float lunar_lambert_albedo_factor(vec3 macro_normal, vec3 sun_dir, vec3 view_dir, float el) {
	if (el <= 0.0) {
		return 1.0;
	}
	float mu0 = max(dot(macro_normal, sun_dir), 0.0);
	float mu = max(dot(macro_normal, view_dir), 0.0);
	float factor = 2.0 * el / max(mu + mu0, 1e-4) + (1.0 - el);
	return min(factor, LUNAR_LAMBERT_FACTOR_MAX);
}


// See the Minnaert block above. Same space and unit-length requirements as
// lunar_lambert_albedo_factor, same macroscopic normal, and returns 1.0 at k = 1.
float minnaert_albedo_factor(vec3 macro_normal, vec3 sun_dir, vec3 view_dir, float k) {
	if (k <= 1.0) {
		return 1.0;
	}
	float mu0 = max(dot(macro_normal, sun_dir), 0.0);
	float mu = max(dot(macro_normal, view_dir), 0.0);
	return pow(mu0 * mu, k - 1.0);
}


// THE SAME TWO LAWS' RESPONSE TO ISOTROPIC ILLUMINATION, which is a different integral and
// emphatically not the same factor. A BRDF's beam factor answers "how bright at THIS
// incidence angle"; skylight, and the diffuse half of a two-stream, have no single incidence
// angle, so what they get is the BRDF integrated over the whole incident hemisphere. Using
// the beam factor for diffuse light applies mu0^(k-1) to light that has no mu0, which on a
// limb-darkened body collapses the diffuse term toward the terminator exactly where it is
// supposed to be taking over -- rendered, that put a flat shelf a couple of degrees wide in
// Venus's terminator gradient, bracketed by steep gradients, which is a Mach band.
//
// Both are FULL responses, not albedo factors: the emission path they feed has no engine
// N.L to supply a leading mu0. Both reduce to exactly 1.0 at Lambert.
//
// Minnaert, f_r proportional to mu0^(k-1) mu^(k-1):
//     int over the hemisphere of mu0^k dw  =>  2/(k+1) mu^(k-1)
float minnaert_isotropic_response(vec3 macro_normal, vec3 view_dir, float k) {
	if (k <= 1.0) {
		return 1.0;
	}
	float mu = max(dot(macro_normal, view_dir), 1.0e-4);
	return 2.0 / (k + 1.0) * pow(mu, k - 1.0);
}


// Lunar-Lambert, f_r proportional to 2L/(mu + mu0) + (1 - L):
//     int_0^1 mu0/(mu + mu0) dmu0 = 1 - mu ln(1 + 1/mu)   =>  4L(1 - mu ln(1 + 1/mu)) + (1 - L)
// Bounded without a clamp, unlike the beam factor: it runs from 1 + 0.227 L at the
// sub-observer point to 1 + 3L at the limb, where the beam factor diverges.
float lunar_lambert_isotropic_response(vec3 macro_normal, vec3 view_dir, float el) {
	if (el <= 0.0) {
		return 1.0;
	}
	float mu = max(dot(macro_normal, view_dir), 1.0e-4);
	return 4.0 * el * (1.0 - mu * log(1.0 + 1.0 / mu)) + (1.0 - el);
}


// THE LIMB IS A SAMPLING EDGE, and one shading sample per pixel cannot resolve it. Each
// pixel along a body's silhouette holds a sliver of surface at grazing incidence, and the
// shader answers for that whole sliver from ONE point, whose interpolated (and normal-mapped)
// normal extrapolates past where the geometry actually turns away -- so a fragment that
// should be edge-on can report a lit mu0, at full physical-light radiance. What that renders
// is speckle: isolated full-brightness pixels scattered along a backlit rim, reshuffling as
// the camera moves, and dashes running off the tips of a crescent once its width drops below
// a pixel. Both are the same defect, and glow finds every one of them.
//
// So fade a shell's radiance over the last LIMB_FADE_PX of its silhouette, where the light
// being removed was never physical. A fixed PIXEL width is what makes that self-scaling:
// most of a crescent tip on a body a few px across, an edge softening finer than the
// camera's own PSF on one that fills the screen.
//
// It needs no radius, no camera distance and no CPU feed -- so it serves every body, whether
// or not that body has an IVBodyPSF quad to feed angular_radius. mu = dot(macroscopic normal,
// VIEW) is the silhouette's own implicit function, exactly zero at tangency at any distance
// and any oblateness, and a screen gradient converts it to pixels: for a sphere mu =
// sqrt(2x/R) at x px inside a limb of pixel radius R, so mu / |grad mu| = 2x whatever R is.
// A normal that extrapolates to negative mu falls out of the same expression as fully faded.
//
// HAZARD: screen derivatives, so call this under UNIFORM control flow -- the rule the ring
// shadow's fwidth() carries (see _sun_occlusion.gdshaderinc). Form it where mu is formed,
// never inside a branch that some lanes of a 2x2 quad skip.
//
// An OPAQUE shell applies it to radiance (and to SPECULAR as its square root, F0 scaling as
// SPECULAR^2). It cannot use ALPHA, which would move it to the transparent pass and stop it
// writing depth. Its light is therefore removed rather than replaced by what stands behind:
// right against sky, where every one of these artifacts lives, and a ~1 px dark fringe in the
// rarer case of a lit body transiting a brighter one. A TRANSLUCENT shell has no such
// constraint and applies it to ALPHA, where partial coverage is what alpha already means.
const float LIMB_FADE_PX = 1.5;


// See above: pass dot(macroscopic normal, VIEW), multiply radiance (or alpha) by the result.
// 1.0 everywhere but the last LIMB_FADE_PX of the silhouette.
float limb_fade_factor(float mu) {
	// The guard is for the disc's interior, where mu is flat and its gradient underflows to
	// zero; the ratio there is meant to be enormous, not indeterminate.
	float gradient = length(vec2(dFdx(mu), dFdy(mu)));
	return smoothstep(0.0, LIMB_FADE_PX, 0.5 * mu / max(gradient, 1.0e-8));
}


// SUPERSAMPLING THE SUN ANGLE ACROSS ONE PIXEL, at the rim and nowhere else, which is the only
// thing that removes the points and broken dashes along a body's limb when the sun stands just
// above it.
//
// THE DEFECT. With the sun within a radius or so of the limb, the whole lit crescent is a
// sliver narrower than a pixel: at 175 deg phase it is 0.55 px on a Jupiter 145 px across. One
// shading sample per pixel then decides the whole sliver by where its centre happened to land,
// and the rim renders as a dotted chain. It is the SHADING rate that is short, not coverage, so
// MSAA cannot touch it -- MSAA resolves coverage and shades a fragment once. Rendering the same
// view at 2x2 and downsampling makes the rim a clean continuous line, which is the measurement
// that identified this and the standard this has to meet.
//
// WHY THE OBVIOUS CHEAP VERSION IS WRONG, recorded because it shipped once and had to come back
// out. Estimating the pixel's mean from mu0 and its screen gradient assumes mu0 ramps LINEARLY
// across the pixel. Near a limb it does not -- it goes as the square root of the distance inside
// the silhouette -- and the error is worst exactly where the fix is needed. At 180 deg phase the
// gradient is large all along the rim, so a linear estimate reports a lit fraction on a night
// side that has no sunlight at all, and reports a different one per pixel: the original speckle,
// straight back.
//
// WHAT THIS DOES INSTEAD. A spheroid's visible surface has an exact parameterization along the
// screen-radial direction: at surface angle t from the sub-observer point the normal is
// cos(t) * view + sin(t) * radial, so mu0 is exactly A cos(t) + B sin(t) for two dot products
// fixed per fragment. No linearization anywhere. Samples are taken across the pixel's own radial
// extent, and t > 90 deg is DROPPED rather than counted -- past the silhouette is sky, not lit
// surface, and counting it is the other half of what went wrong before. At 180 deg phase every
// sample returns exactly zero, so the speckle cannot come back; where the sliver is resolved the
// mean equals the centre sample and this is a no-op. Measured on the 175 deg case, the
// along-arc variation that makes the dashes falls from 6e7 to 7.
//
// The pixel's radial extent comes from mu's own screen gradient, as in limb_fade_factor: the
// surface angle per screen pixel is |grad mu| / sin(t). So this needs no radius, no camera
// distance and no CPU feed either.
//
// COST is confined to the rim by LIMB_INCIDENCE_REACH_PX, and there is no texture work in it --
// the loop is arithmetic on two dot products.
//
// HAZARD: screen derivatives, so call under UNIFORM control flow (see limb_fade_factor).
const int LIMB_INCIDENCE_SAMPLES = 8;
// One pixel, not more. Widening is what the atmosphere ring needs, because there the light has
// no neighbouring fragment to land in; here every pixel along the rim already exists and now
// carries its own correct mean, so a wider filter only spreads the sliver over more pixels than
// it occupies and over-delivers against the supersampled reference.
const float LIMB_INCIDENCE_FILTER_PX = 1.0; // pixel widths the mean is taken over
const float LIMB_INCIDENCE_REACH_PX = 6.0;  // px inside the silhouette past which the centre IS the mean
const float LIMB_HALF_PI = 1.5707963;
// How far the ALBEDO rescale may carry the mean above the centre sample before the rest is
// handed to emission. A cap is needed because the ratio diverges as the centre sample goes to
// zero, which is precisely the pixel whose sliver the centre missed.
const float LIMB_INCIDENCE_ALBEDO_MAX = 4.0;

// Returns the mean of max(mu0, 0) over the ON-BODY part of this fragment's radial footprint.
// Pass the MACROSCOPIC normal and mu = dot(macro_normal, view_dir), all in one space.
float limb_mean_incidence(vec3 macro_normal, vec3 view_dir, vec3 sun_dir, float mu) {
	float centre = max(dot(macro_normal, sun_dir), 0.0);
	float gradient = length(vec2(dFdx(mu), dFdy(mu)));
	float sin_t = sqrt(max(1.0 - mu * mu, 0.0));
	if (gradient <= 0.0 || sin_t < 1.0e-4 || 0.5 * mu / gradient > LIMB_INCIDENCE_REACH_PX) {
		return centre; // resolved, or degenerate at the sub-observer point where mu is flat
	}
	vec3 radial = normalize(macro_normal - mu * view_dir); // outward, in the (normal, view) plane
	float along_view = dot(view_dir, sun_dir);
	float along_radial = dot(radial, sun_dir);
	float t = acos(clamp(mu, -1.0, 1.0));
	float step_t = gradient / sin_t; // surface angle per screen pixel, radially
	float sum = 0.0;
	float weight_sum = 0.0;
	for (int i = 0; i < LIMB_INCIDENCE_SAMPLES; i++) {
		float offset = (float(i) + 0.5) * (2.0 / float(LIMB_INCIDENCE_SAMPLES)) - 1.0;
		float weight = 1.0 - abs(offset); // tent
		weight_sum += weight;
		float sample_t = t + offset * 0.5 * LIMB_INCIDENCE_FILTER_PX * step_t;
		if (sample_t > LIMB_HALF_PI) {
			continue; // beyond the silhouette: sky, contributing no surface light
		}
		sum += weight * max(along_view * cos(sample_t) + along_radial * sin(sample_t), 0.0);
	}
	// Normalized by the FULL tent, so the part of the filter hanging past the silhouette
	// counts as the zero it is. That makes the result coverage-weighted, which is what keeps
	// the rim from over-delivering where the sliver fills only a fraction of the pixel.
	return weight_sum > 0.0 ? sum / weight_sum : centre;
}
