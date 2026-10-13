class_name QR
## Petit encodeur de QR code (mode octet, correction L, versions 1 à 6),
## suffisant pour une adresse du type http://192.168.1.42:8080.
## Adapté de l'algorithme de Project Nayuki (licence MIT).

# version -> [nombre total de codewords, codewords de correction par bloc, nombre de blocs]
const TABLE_L := {
	1: [26, 7, 1], 2: [44, 10, 1], 3: [70, 15, 1],
	4: [100, 20, 1], 5: [134, 26, 1], 6: [172, 18, 2],
}
const ALIGN := {1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34]}
const FORMAT_BITS_L := 1


## Retourne la matrice (Array de lignes de bool, true = module sombre), ou [] si trop long.
## force_mask >= 0 impose un masque (tests) ; sinon le meilleur est choisi.
static func encode(text: String, force_mask := -1) -> Array:
	var data := text.to_utf8_buffer()
	var version := 0
	for v in range(1, 7):
		var cap: int = TABLE_L[v][0] - TABLE_L[v][1] * TABLE_L[v][2]
		if 4 + 8 + data.size() * 8 <= cap * 8:
			version = v
			break
	if version == 0:
		return []
	var codewords := _add_ecc_and_interleave(_data_codewords(data, version), version)
	var size := version * 4 + 17
	var best: Array = []
	var best_score := -1
	var masks := [force_mask] if force_mask >= 0 else range(8)
	for mask in masks:
		var m := _empty(size)
		var f := _empty(size)
		_draw_function_patterns(m, f, version)
		_draw_codewords(m, f, codewords)
		_apply_mask(m, f, mask)
		_draw_format(m, f, mask)
		var score := _penalty(m)
		if best_score < 0 or score < best_score:
			best_score = score
			best = m
	return best


## Image prête à afficher, avec la marge blanche réglementaire de 4 modules.
static func to_image(matrix: Array, scale := 6, dark := Color.BLACK, light := Color.WHITE) -> Image:
	var n := matrix.size()
	var px := (n + 8) * scale
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(light)
	for y in n:
		for x in n:
			if matrix[y][x]:
				img.fill_rect(Rect2i((x + 4) * scale, (y + 4) * scale, scale, scale), dark)
	return img


# ---------------------------------------------------------------- données

static func _data_codewords(data: PackedByteArray, version: int) -> PackedByteArray:
	var bits: Array[int] = []
	_append_bits(bits, 0x4, 4)            # mode octet
	_append_bits(bits, data.size(), 8)    # longueur (versions 1 à 9)
	for b in data:
		_append_bits(bits, b, 8)
	var capacity_bits: int = (TABLE_L[version][0] - TABLE_L[version][1] * TABLE_L[version][2]) * 8
	_append_bits(bits, 0, min(4, capacity_bits - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad := 0xEC
	while bits.size() < capacity_bits:
		_append_bits(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var out := PackedByteArray()
	out.resize(bits.size() / 8)
	for i in bits.size():
		out[i >> 3] |= bits[i] << (7 - (i & 7))
	return out


static func _append_bits(bits: Array[int], value: int, length: int) -> void:
	for i in range(length - 1, -1, -1):
		bits.append((value >> i) & 1)


static func _add_ecc_and_interleave(data: PackedByteArray, version: int) -> PackedByteArray:
	var total: int = TABLE_L[version][0]
	var ec_len: int = TABLE_L[version][1]
	var num_blocks: int = TABLE_L[version][2]
	var short_len := total / num_blocks
	var num_short := num_blocks - total % num_blocks
	var divisor := _rs_divisor(ec_len)
	var blocks: Array = []
	var k := 0
	for i in num_blocks:
		var dlen := short_len - ec_len + (0 if i < num_short else 1)
		var dat := data.slice(k, k + dlen)
		k += dlen
		var ecc := _rs_remainder(dat, divisor)
		if i < num_short:
			dat.append(0)  # place vide pour aligner les blocs courts
		dat.append_array(ecc)
		blocks.append(dat)
	var result := PackedByteArray()
	for i in (blocks[0] as PackedByteArray).size():
		for j in blocks.size():
			if i != short_len - ec_len or j >= num_short:
				result.append(blocks[j][i])
	return result


static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


static func _rs_divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 0x02)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(divisor.size())
	for b in data:
		var factor := b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i in result.size():
			result[i] ^= _gf_mul(divisor[i], factor)
	return result


# ---------------------------------------------------------------- dessin

static func _empty(size: int) -> Array:
	var m: Array = []
	for y in size:
		var row: Array = []
		row.resize(size)
		row.fill(false)
		m.append(row)
	return m


static func _set_fn(m: Array, f: Array, x: int, y: int, dark: bool) -> void:
	m[y][x] = dark
	f[y][x] = true


static func _draw_function_patterns(m: Array, f: Array, version: int) -> void:
	var size := m.size()
	for i in size:
		_set_fn(m, f, 6, i, i % 2 == 0)
		_set_fn(m, f, i, 6, i % 2 == 0)
	_draw_finder(m, f, 3, 3)
	_draw_finder(m, f, size - 4, 3)
	_draw_finder(m, f, 3, size - 4)
	var pos: Array = ALIGN[version]
	for i in pos.size():
		for j in pos.size():
			if (i == 0 and j == 0) or (i == 0 and j == pos.size() - 1) or (i == pos.size() - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_fn(m, f, pos[i] + dx, pos[j] + dy, max(abs(dx), abs(dy)) != 1)
	_draw_format(m, f, 0)  # réserve les zones de format


static func _draw_finder(m: Array, f: Array, cx: int, cy: int) -> void:
	var size := m.size()
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and x < size and y >= 0 and y < size:
				var d: int = max(abs(dx), abs(dy))
				_set_fn(m, f, x, y, d != 2 and d != 4)


static func _draw_format(m: Array, f: Array, mask: int) -> void:
	var size := m.size()
	var data := (FORMAT_BITS_L << 3) | mask
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	var bit := func(i: int) -> bool: return ((bits >> i) & 1) != 0
	for i in range(0, 6):
		_set_fn(m, f, 8, i, bit.call(i))
	_set_fn(m, f, 8, 7, bit.call(6))
	_set_fn(m, f, 8, 8, bit.call(7))
	_set_fn(m, f, 7, 8, bit.call(8))
	for i in range(9, 15):
		_set_fn(m, f, 14 - i, 8, bit.call(i))
	for i in range(0, 8):
		_set_fn(m, f, size - 1 - i, 8, bit.call(i))
	for i in range(8, 15):
		_set_fn(m, f, 8, size - 15 + i, bit.call(i))
	_set_fn(m, f, 8, size - 8, true)


static func _draw_codewords(m: Array, f: Array, data: PackedByteArray) -> void:
	var size := m.size()
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if not f[y][x] and i < data.size() * 8:
					m[y][x] = ((data[i >> 3] >> (7 - (i & 7))) & 1) != 0
					i += 1
		right -= 2


static func _apply_mask(m: Array, f: Array, mask: int) -> void:
	var size := m.size()
	for y in size:
		for x in size:
			if f[y][x]:
				continue
			var inv := false
			match mask:
				0: inv = (x + y) % 2 == 0
				1: inv = y % 2 == 0
				2: inv = x % 3 == 0
				3: inv = (x + y) % 3 == 0
				4: inv = (x / 3 + y / 2) % 2 == 0
				5: inv = x * y % 2 + x * y % 3 == 0
				6: inv = (x * y % 2 + x * y % 3) % 2 == 0
				7: inv = ((x + y) % 2 + x * y % 3) % 2 == 0
			if inv:
				m[y][x] = not m[y][x]


## Pénalités simplifiées (règles 1, 2 et 4 de la norme) pour choisir un masque lisible.
static func _penalty(m: Array) -> int:
	var size := m.size()
	var score := 0
	for horizontal in [true, false]:
		for a in size:
			var run := 1
			for b in range(1, size):
				var cur: bool = m[a][b] if horizontal else m[b][a]
				var prev: bool = m[a][b - 1] if horizontal else m[b - 1][a]
				if cur == prev:
					run += 1
					if run == 5:
						score += 3
					elif run > 5:
						score += 1
				else:
					run = 1
	var dark := 0
	for y in size:
		for x in size:
			if m[y][x]:
				dark += 1
			if x < size - 1 and y < size - 1:
				var c: bool = m[y][x]
				if c == m[y][x + 1] and c == m[y + 1][x] and c == m[y + 1][x + 1]:
					score += 3
	var total := size * size
	var k := int(ceil(abs(dark * 20 - total * 10) / float(total))) - 1
	score += max(k, 0) * 10
	return score
