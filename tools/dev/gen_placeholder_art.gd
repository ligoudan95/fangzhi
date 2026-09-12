## doc: 10 §4.2/§10.3（程序化占位美术生成，正式资产到位后替换）
## 生成：12 只灵宠 battle_idle 贴图（元素色圆角体+肚皮+眼+元素徽记）+ 三层背景。
## 运行：godot --headless --path . -s res://tools/dev/gen_placeholder_art.gd
extends SceneTree

const ELEMENT_COLORS := {
	1: Color("#E8B33C"), 2: Color("#6FBF4F"), 3: Color("#4F86E8"),
	4: Color("#E8543C"), 5: Color("#C79A4B"), 6: Color("#7A4FD4"), 7: Color("#F5E7B8"),
}
const PETS := [
	[1001, 5, "rock"], [1002, 2, "flower"], [1003, 2, "vine"], [1004, 2, "leaf"],
	[1005, 4, "feather"], [1006, 4, "lava"], [1007, 1, "spark"], [1008, 1, "moon"],
	[1009, 3, "ice"], [1010, 3, "snow"], [1011, 5, "shell"], [1012, 5, "ear"],
]


func _initialize() -> void:
	_gen_pets()
	_gen_backgrounds()
	quit(0)


func _gen_pets() -> void:
	for pet in PETS:
		var img := Image.create(240, 300, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var body: Color = ELEMENT_COLORS[int(pet[1])]
		var darker := body.darkened(0.35)
		var lighter := body.lightened(0.25)
		# 身体：圆角矩形（手绘像素圆角）
		_fill_round_rect(img, Rect2i(30, 60, 180, 200), body, 24)
		# 肚皮
		_fill_round_rect(img, Rect2i(60, 140, 120, 100), lighter, 16)
		# 耳朵（顶部两个三角近似）
		_fill_rect(img, Rect2i(45, 30, 30, 40), body)
		_fill_rect(img, Rect2i(165, 30, 30, 40), body)
		# 眼睛
		_fill_rect(img, Rect2i(80, 100, 14, 20), Color(0.1, 0.08, 0.06))
		_fill_rect(img, Rect2i(146, 100, 14, 20), Color(0.1, 0.08, 0.06))
		# 高光
		_fill_rect(img, Rect2i(83, 103, 5, 7), Color.WHITE)
		_fill_rect(img, Rect2i(149, 103, 5, 7), Color.WHITE)
		# 嘴
		_fill_rect(img, Rect2i(112, 135, 16, 4), darker)
		# 元素徽记（胸腹中央 24×24 像素图案）
		_draw_sigil(img, int(pet[2]), Vector2i(108, 168), darker)
		# 底部阴影
		_fill_ellipse_row(img, Rect2i(50, 268, 140, 12), Color(0, 0, 0, 0.35))
		var dir := "res://art/pets/pet_%d" % int(pet[0])
		DirAccess.make_dir_recursive_absolute(dir)
		img.save_png("%s/battle_idle.png" % dir)
	print("PETS-ART: 12 生成完成")


func _gen_backgrounds() -> void:
	DirAccess.make_dir_recursive_absolute("res://art/scenes")
	# 远景：黑风林夜空渐变+山脊
	var far := Image.create(1080, 1920, false, Image.FORMAT_RGBA8)
	for y in 1920:
		var t := float(y) / 1920.0
		var c := Color(0.08, 0.13, 0.10).lerp(Color(0.05, 0.09, 0.07), t)
		for x in 1080:
			far.set_pixel(x, y, c)
	_draw_ridge(far, 1250, 90, Color(0.10, 0.18, 0.13))
	_draw_ridge(far, 1450, 130, Color(0.08, 0.15, 0.11))
	far.save_png("res://art/scenes/bg_far.png")
	# 中景：树影（透明 PNG）
	var mid := Image.create(1080, 1920, false, Image.FORMAT_RGBA8)
	mid.fill(Color(0, 0, 0, 0))
	for i in 14:
		var tx := 60 + i * 75 + (i % 3) * 20
		var th := 380 + (i * 137) % 220
		_draw_tree(mid, tx, 1150, th, Color(0.06, 0.14, 0.09, 0.9))
	mid.save_png("res://art/scenes/bg_mid.png")
	# 近景：地面
	var near := Image.create(1080, 1920, false, Image.FORMAT_RGBA8)
	near.fill(Color(0, 0, 0, 0))
	for y in range(1500, 1920):
		var t := float(y - 1500) / 420.0
		var c := Color(0.13, 0.11, 0.08).lerp(Color(0.08, 0.07, 0.05), t)
		for x in 1080:
			near.set_pixel(x, y, c)
	for i in 24:
		var gx := (i * 197) % 1000 + 40
		var gy := 1520 + (i * 83) % 360
		_fill_rect(near, Rect2i(gx, gy, 8, 5), Color(0.16, 0.14, 0.10))
	near.save_png("res://art/scenes/bg_near.png")
	print("BG-ART: 3 层生成完成")


func _fill_rect(img: Image, rect: Rect2i, c: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if Rect2i(Vector2i.ZERO, img.get_size()).has_point(Vector2i(x, y)):
				img.set_pixel(x, y, c)


func _fill_round_rect(img: Image, rect: Rect2i, c: Color, radius: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var dx := maxi(absi(x - rect.get_center().x) - (rect.size.x / 2 - radius), 0)
			var dy := maxi(absi(y - rect.get_center().y) - (rect.size.y / 2 - radius), 0)
			if dx * dx + dy * dy <= radius * radius:
				img.set_pixel(x, y, c)


func _fill_ellipse_row(img: Image, rect: Rect2i, c: Color) -> void:
	var cx := rect.get_center().x
	for y in range(rect.position.y, rect.end.y):
		var half := int(float(rect.size.x) / 2.0 * sqrt(1.0 - pow(float(y - rect.position.y) / rect.size.y - 0.5, 2.0) * 4.0))
		for x in range(cx - half, cx + half):
			img.set_pixel(x, y, c)


func _draw_sigil(img: Image, kind: int, at: Vector2i, c: Color) -> void:
	match kind:
		"rock":
			_fill_rect(img, Rect2i(at.x - 10, at.y - 8, 20, 16), c)
		"flower":
			for d in [Vector2i(0, -8), Vector2i(0, 8), Vector2i(-8, 0), Vector2i(8, 0)]:
				_fill_rect(img, Rect2i(at.x + d.x - 4, at.y + d.y - 4, 8, 8), c)
		"vine":
			_fill_rect(img, Rect2i(at.x - 2, at.y - 10, 4, 20), c)
			_fill_rect(img, Rect2i(at.x - 8, at.y - 4, 8, 4), c)
			_fill_rect(img, Rect2i(at.x + 2, at.y + 2, 8, 4), c)
		"leaf":
			for i in 8:
				_fill_rect(img, Rect2i(at.x - 10 + i, at.y - 8 + i, 12 - i, 3), c)
		"feather":
			for i in 10:
				_fill_rect(img, Rect2i(at.x - 6 + i, at.y - 10 + i, 3, 10), c)
		"lava":
			_fill_rect(img, Rect2i(at.x - 9, at.y - 6, 18, 12), c)
			_fill_rect(img, Rect2i(at.x - 4, at.y - 10, 8, 20), c)
		"spark":
			_fill_rect(img, Rect2i(at.x - 2, at.y - 10, 4, 20), c)
			_fill_rect(img, Rect2i(at.x - 10, at.y - 2, 20, 4), c)
		"moon":
			for y in 16:
				for x in 16:
					var d := sqrt(pow(x - 8, 2) + pow(y - 8, 2))
					if d <= 8 and not (x - 3) * (x - 3) + (y - 3) * (y - 3) <= 25:
						img.set_pixel(at.x - 8 + x, at.y - 8 + y, c)
		"ice":
			for i in [-8, 0, 8]:
				_fill_rect(img, Rect2i(at.x + i - 2, at.y - 8, 4, 16), c)
		"snow":
			_fill_rect(img, Rect2i(at.x - 8, at.y - 2, 16, 4), c)
			_fill_rect(img, Rect2i(at.x - 2, at.y - 8, 4, 16), c)
			_fill_rect(img, Rect2i(at.x - 6, at.y - 6, 4, 4), c)
			_fill_rect(img, Rect2i(at.x + 2, at.y + 2, 4, 4), c)
		"shell":
			for i in 6:
				_fill_rect(img, Rect2i(at.x - 9 + i * 3, at.y - 6 + absi(3 - i) * 2, 3, 12 - absi(3 - i) * 4), c)
		"ear":
			_fill_rect(img, Rect2i(at.x - 10, at.y - 10, 6, 6), c)
			_fill_rect(img, Rect2i(at.x + 4, at.y - 10, 6, 6), c)
			_fill_rect(img, Rect2i(at.x - 6, at.y + 2, 12, 8), c)
		_:
			_fill_rect(img, Rect2i(at.x - 8, at.y - 8, 16, 16), c)


func _draw_ridge(img: Image, base_y: int, amp: int, c: Color) -> void:
	for x in 1080:
		var h := base_y + int(sin(float(x) / 130.0) * float(amp)) + int(sin(float(x) / 47.0) * float(amp / 3))
		for y in range(h, 1920):
			img.set_pixel(x, y, c)


func _draw_tree(img: Image, x: int, base: int, height: int, c: Color) -> void:
	var w := height / 4
	for y in range(base - height, base):
		var t := float(base - y) / float(height)
		var half := int(float(w) / 2.0 * t)
		for tx in range(x - half, x + half):
			if Rect2i(Vector2i.ZERO, img.get_size()).has_point(Vector2i(tx, y)):
				img.set_pixel(tx, y, c)
