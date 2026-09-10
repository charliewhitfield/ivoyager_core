# binary_asteroids_builder.gd
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
class_name IVBinaryAsteroidsBuilder
extends RefCounted

## Builds an [IVSmallBodiesGroup] instance from asteroid binary data.
##
## Binary asteroid data is in ivoyager_assets and is created by
## [code]addons/tools/build_asteroid_binaries.py[/code], whose module docstring
## specifies the format and cites its AstDyS and JPL sources.[br][br]
##
## Files predating that script carry no magic number and are skipped, so an
## asset set older than this loader yields an empty group rather than an error.

const VPRINT = false # print verbose asteroid summary on load
const DPRINT = false

const BINARY_EXTENSION := "ivbinary"
const BINARY_FILE_MAGNITUDES: Array[String] = ["11.0", "11.5", "12.0", "12.5", "13.0", "13.5",
		"14.0", "14.5", "15.0", "15.5", "16.0", "16.5", "17.0", "17.5", "18.0", "18.5", "99.9"]

const _BINARY_MAGIC := 0x53415649 # b"IVAS", little-endian
const _BINARY_VERSION := 1
const _FLAG_LIBRATION := 1 # block D present: Lagrange point libration parameters



func build_sbg_from_binaries(sbg: IVSmallBodiesGroup, binary_dir: String, mag_cutoff: float
		) -> void:
	var n_legacy := 0
	for mag_str in BINARY_FILE_MAGNITUDES:
		if mag_str.to_float() > mag_cutoff:
			break
		if _load_asteroids_group_binary(sbg, binary_dir, mag_str):
			n_legacy += 1
	if n_legacy:
		push_warning("Skipped %s pre-'IVAS' asteroid binaries in '%s'; rebuild them with "
				% [n_legacy, binary_dir] + "addons/tools/build_asteroid_binaries.py")
	assert(!VPRINT or sbg.vprint_load("asteroids"))


## Appends one binary's asteroids to [param sbg]. Returns true only when the file
## exists but predates this format, which the caller reports once per directory.
func _load_asteroids_group_binary(sbg: IVSmallBodiesGroup, binary_dir: String, mag_str: String
		) -> bool:
	var lp_integer := sbg.lp_integer
	var binary_name: String = sbg.sbg_alias + "." + mag_str + "." + BINARY_EXTENSION
	var path: String = binary_dir.path_join(binary_name)
	var binary := FileAccess.open(path, FileAccess.READ)
	if !binary: # skip quietly if file doesn't exist
		return false
	assert(!DPRINT or IVDebug.dprint("Reading binary %s" % path))

	if binary.get_32() != _BINARY_MAGIC:
		binary.close()
		return true
	var version := binary.get_32()
	if version != _BINARY_VERSION:
		push_warning("IVBinaryAsteroidsBuilder: unexpected version %s in '%s'" % [version, path])
	var size := binary.get_32()
	var flags := binary.get_32()
	assert(size > 0, "Empty asteroid binary %s" % path)
	assert((flags & _FLAG_LIBRATION != 0) == (lp_integer != -1),
			"Libration data presence disagrees with 'lp_integer' in %s" % path)

	var e_i_lan_ap := binary.get_buffer(size * 16).to_float32_array()
	var a_m0_n := binary.get_buffer(size * 12).to_float32_array()
	var s_g_mag := binary.get_buffer(size * 12).to_float32_array()
	var da_d_f_th0 := PackedFloat32Array()
	if lp_integer != -1:
		da_d_f_th0 = binary.get_buffer(size * 16).to_float32_array()
	var names_size := binary.get_32()
	var names := binary.get_buffer(names_size).get_string_from_utf8().split("\n")
	binary.close()
	assert(names.size() == size, "Name count disagrees with asteroid count in %s" % path)

	# apply scale if needed
	const scale_multiplier := IVUnits.METER
	if scale_multiplier != 1.0:
		var index := 0
		while index < size:
			a_m0_n[index * 3] *= scale_multiplier # a only
			if lp_integer != -1:
				da_d_f_th0[index * 4] *= scale_multiplier # da only
			index += 1

	sbg.append_data(names, e_i_lan_ap, a_m0_n, s_g_mag, da_d_f_th0)
	return false
