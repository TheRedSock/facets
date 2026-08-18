class_name LapidarySheetComposer
extends RefCounted
## Pure-CPU montage builder for the Lapidary evaluation sheets.
## Lays rendered tiles onto a labeled grid: optional header line, optional
## column captions, optional row captions, and a dark gutter strip with a
## label under each tile. Text uses an embedded 5x7 bitmap font drawn at 2x
## via Image.set_pixel (A-Z 0-9 . - / : % and space; '_' is drawn as '-').
## No scene tree, no font assets.

const BG_COLOR := Color8(26, 26, 30) # #1a1a1e
const GUTTER_COLOR := Color8(15, 15, 18)
const TEXT_COLOR := Color8(216, 216, 222)
const CAPTION_COLOR := Color8(148, 148, 160)
const PAD := 8
const LABEL_H := 20
const HEADER_H := 26
const GLYPH_W := 5
const GLYPH_H := 7

# 7 rows per glyph, top to bottom; bit 4 (MSB of 5) = leftmost pixel.
const FONT := {
	"A": [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
	"B": [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
	"C": [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
	"D": [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110],
	"E": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
	"F": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
	"G": [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01110],
	"H": [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
	"I": [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
	"J": [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100],
	"K": [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
	"L": [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
	"M": [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
	"N": [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001],
	"O": [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
	"P": [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
	"Q": [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
	"R": [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
	"S": [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
	"T": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
	"U": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
	"V": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
	"W": [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010],
	"X": [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001],
	"Y": [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
	"Z": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
	"0": [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
	"1": [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
	"2": [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
	"3": [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110],
	"4": [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
	"5": [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
	"6": [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
	"7": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
	"8": [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
	"9": [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100],
	".": [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b01100, 0b01100],
	"-": [0b00000, 0b00000, 0b00000, 0b01110, 0b00000, 0b00000, 0b00000],
	"/": [0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000],
	":": [0b00000, 0b01100, 0b01100, 0b00000, 0b01100, 0b01100, 0b00000],
	"%": [0b11001, 0b11010, 0b00010, 0b00100, 0b01000, 0b01011, 0b10011],
	" ": [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000],
}


## tiles: Array of {image: Image, label: String}, laid out row-major.
## row_labels caption grid rows on the left; col_labels caption columns above.
static func compose(tiles: Array, columns: int, tile_labels := true, header := "",
		row_labels: Array = [], col_labels: Array = []) -> Image:
	assert(columns > 0 and not tiles.is_empty())
	@warning_ignore("integer_division")
	var rows := (tiles.size() + columns - 1) / columns
	var cell_w := 1
	var cell_h := 1
	for t: Dictionary in tiles:
		var timg: Image = t["image"]
		cell_w = maxi(cell_w, timg.get_width())
		cell_h = maxi(cell_h, timg.get_height())
	var label_h := LABEL_H if tile_labels else 0
	var header_h := HEADER_H if not header.is_empty() else 0
	var caption_h := LABEL_H if not col_labels.is_empty() else 0
	var row_label_w := 0
	for rl in row_labels:
		row_label_w = maxi(row_label_w, text_width(str(rl), 2) + PAD * 2)
	var grid_x := PAD + row_label_w
	var grid_y := PAD + header_h + caption_h
	var sheet := Image.create_empty(grid_x + columns * (cell_w + PAD),
		grid_y + rows * (cell_h + label_h + PAD), false, Image.FORMAT_RGBA8)
	sheet.fill(BG_COLOR)

	if not header.is_empty():
		draw_text(sheet, PAD, PAD, header, TEXT_COLOR, 2)
	for c in mini(col_labels.size(), columns):
		_draw_centered(sheet, grid_x + c * (cell_w + PAD), PAD + header_h + 2,
			cell_w, str(col_labels[c]), CAPTION_COLOR, 2)

	for i in tiles.size():
		@warning_ignore("integer_division")
		var r := i / columns
		var c := i % columns
		var x := grid_x + c * (cell_w + PAD)
		var y := grid_y + r * (cell_h + label_h + PAD)
		var td: Dictionary = tiles[i]
		var img: Image = td["image"]
		if img.get_format() != Image.FORMAT_RGBA8:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGBA8)
		@warning_ignore("integer_division")
		var dst := Vector2i(x + (cell_w - img.get_width()) / 2, y + (cell_h - img.get_height()) / 2)
		sheet.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), dst)
		if tile_labels:
			sheet.fill_rect(Rect2i(x, y + cell_h, cell_w, label_h), GUTTER_COLOR)
			_draw_centered(sheet, x, y + cell_h + 3, cell_w, str(td.get("label", "")), TEXT_COLOR, 2)

	for r in mini(row_labels.size(), rows):
		@warning_ignore("integer_division")
		var ty := grid_y + r * (cell_h + label_h + PAD) + (cell_h - GLYPH_H * 2) / 2
		draw_text(sheet, PAD, ty, str(row_labels[r]), CAPTION_COLOR, 2)
	return sheet


static func text_width(text: String, scale := 2) -> int:
	return text.length() * (GLYPH_W + 1) * scale


static func draw_text(img: Image, x: int, y: int, text: String, color: Color, scale := 2) -> void:
	var cx := x
	for ch in text.to_upper().replace("_", "-"):
		var glyph: Array = FONT.get(ch, FONT[" "])
		for gr in GLYPH_H:
			var bits: int = glyph[gr]
			if bits == 0:
				continue
			for gc in GLYPH_W:
				if (bits & (1 << (GLYPH_W - 1 - gc))) == 0:
					continue
				for sy in scale:
					for sx in scale:
						var px := cx + gc * scale + sx
						var py := y + gr * scale + sy
						if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
							img.set_pixel(px, py, color)
		cx += (GLYPH_W + 1) * scale


static func _draw_centered(img: Image, x: int, y: int, w: int, text: String,
		color: Color, scale: int) -> void:
	var s := scale
	if text_width(text, s) > w and s > 1:
		s = 1
	if text_width(text, s) > w:
		@warning_ignore("integer_division")
		text = text.substr(0, maxi(1, w / ((GLYPH_W + 1) * s)))
	@warning_ignore("integer_division")
	draw_text(img, x + maxi(0, (w - text_width(text, s)) / 2), y, text, color, s)
