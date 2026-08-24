extends HBoxContainer

# 六格石板条。纯渲染，只接收数据，不持有 GameState。
# 视觉语言：已踏过=变暗，当前站位=高亮，未踏=正常，豁口=gap 贴图（红光）。
# slab_size 由外部指定，保证不溢出所属面板（修复：原 48px 固定尺寸溢出 150px 面板）。

var slab_size := Vector2(30, 20)
var _slabs: Array = []

func _ready() -> void:
	add_theme_constant_override("separation", 2)
	for i in Rules.STONES:
		var tr := TextureRect.new()
		tr.custom_minimum_size = slab_size
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(tr)
		_slabs.append(tr)

func set_state(steps: int, has_gap: bool, alive: bool) -> void:
	var ok: Texture2D = Art.stone_ok_tex()
	var cur: Texture2D = Art.stone_current_tex()
	var gap: Texture2D = Art.stone_gap_tex()
	for i in _slabs.size():
		var tr: TextureRect = _slabs[i]
		if not alive:
			tr.texture = gap if i == steps - 1 or (i == steps and steps < Rules.STONES) else ok
			tr.modulate = Color(0.35, 0.35, 0.35)
			continue
		if i < steps:
			tr.texture = ok
			tr.modulate = Color(0.45, 0.45, 0.5)          # 已踏过，变暗
		elif i == steps and has_gap:
			tr.texture = gap if gap != null else ok
			tr.modulate = Color(1.6, 0.7, 0.7)             # 豁口，红光警示
		elif i == steps:
			tr.texture = cur if cur != null else ok
			tr.modulate = Color(1.35, 1.3, 1.1)            # 当前站位，高亮
		else:
			tr.texture = ok
			tr.modulate = Color(1, 1, 1)
