extends HBoxContainer

# 自己手牌面板（可多选，1..3 张）。纯渲染，回调外部。
# 修复：原版是零尺寸裸 Control 且每次 _rebuild 泄漏一个旧 HBox，
# 导致手牌整个不可见（"卡牌游戏没有卡牌"）。
# 现在本体就是 HBoxContainer，卡牌 2x 显示（128x192），选中上浮。

signal selection_changed(indices: Array)

const CARD_SIZE := Vector2(128, 192)   # 64x96 素材 2x 整数放大，像素干净

var _hand: Array = []
var _selected: Dictionary = {}
var _boxes: Array = []
var _hovered := -1
var _prev_count := 0        # 只有牌变多（新发牌）才播飞入动画，出牌后不重播

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	alignment = BoxContainer.ALIGNMENT_CENTER
	custom_minimum_size = Vector2(0, CARD_SIZE.y + 20)

func set_hand(cards: Array) -> void:
	var deal_anim := cards.size() > _prev_count
	_prev_count = cards.size()
	_hand = cards.duplicate()
	_selected = {}
	_hovered = -1
	_rebuild(deal_anim)
	selection_changed.emit([])

func _rebuild(deal_anim := false) -> void:
	for c in get_children():
		c.free()
	_boxes = []
	for i in _hand.size():
		var btn := Button.new()
		btn.custom_minimum_size = CARD_SIZE
		btn.toggle_mode = true
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_toggle.bind(i))
		btn.mouse_entered.connect(_on_hover.bind(i, true))
		btn.mouse_exited.connect(_on_hover.bind(i, false))
		var face := _card_visual(_hand[i])
		btn.add_child(face)
		add_child(btn)
		_boxes.append(btn)
		if deal_anim:
			# 发牌飞入：从下方错峰浮起
			face.position.y = 52
			face.modulate.a = 0.0
			var tw := face.create_tween().set_parallel(true)
			tw.tween_property(face, "position:y", 0.0, 0.26) \
				.set_delay(0.05 * i).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(face, "modulate:a", 1.0, 0.18).set_delay(0.05 * i)


func _on_hover(idx: int, entered: bool) -> void:
	_hovered = idx if entered else (-1 if _hovered == idx else _hovered)
	_animate_card(idx)


func _animate_card(idx: int) -> void:
	if idx < 0 or idx >= _boxes.size():
		return
	var b: Button = _boxes[idx]
	var face: Control = b.get_child(0)
	var target := 0.0
	if _selected.has(idx):
		target = -18.0
	elif _hovered == idx:
		target = -10.0
	var tw := face.create_tween()
	tw.tween_property(face, "position:y", target, 0.12).set_ease(Tween.EASE_OUT)

func _card_visual(suit: int) -> Control:
	var tex: Texture2D = Art.card_tex(suit)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	# fallback：文字色块
	var rect := ColorRect.new()
	rect.color = _suit_color(suit)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = _card_text(suit)
	l.add_theme_font_size_override("font_size", 32)
	l.set_anchors_preset(Control.PRESET_CENTER)
	rect.add_child(l)
	return rect

func _suit_color(suit: int) -> Color:
	match suit:
		Rules.Suit.DAO: return Color("#C94F4F")
		Rules.Suit.JIAN: return Color("#4F7FC9")
		Rules.Suit.ZHANG: return Color("#4FA86B")
	return Color("#C9A54F")

func _card_text(suit: int) -> String:
	match suit:
		Rules.Suit.DAO: return "刀"
		Rules.Suit.JIAN: return "剑"
		Rules.Suit.ZHANG: return "掌"
	return "化"

func _on_toggle(idx: int) -> void:
	if _boxes[idx].button_pressed:
		_selected[idx] = true
	else:
		_selected.erase(idx)
	if _selected.size() > Rules.MAX_PLAY_CARDS:
		var first: int = _selected.keys()[0]
		_selected.erase(first)
		_boxes[first].set_pressed_no_signal(false)
	_update_selection_visual()
	selection_changed.emit(selected_indices())

func _update_selection_visual() -> void:
	for i in _boxes.size():
		var b: Button = _boxes[i]
		b.modulate = Color(1.15, 1.12, 1.0) if _selected.has(i) else Color(1, 1, 1)
		_animate_card(i)

func selected_indices() -> Array:
	var out: Array = _selected.keys()
	out.sort()
	return out
