extends PanelContainer

# 对手信息卡（上方一排）。纯渲染，只接收 view 裁剪数据。
# 内容：立绘、名字+思考文案、技能图标+次数/CD、手牌数（迷你牌背）、六格石板条、读条。

const PORTRAIT_SIZE := Vector2(72, 96)     # 128x170 立绘按高度等比缩入
const MINI_BACK := Vector2(18, 27)

var _name_label: Label
var _avatar: TextureRect
var _skill_icon: TextureRect
var _skill_label: Label
var _hand_row: HBoxContainer
var _cliff: Control
var _timer_bar: ProgressBar
var _own_timer_label: Label
var _emote_label: Label
var _emote_left := 0.0
var _was_current := false
var _sb_normal: StyleBoxFlat
var _sb_current: StyleBoxFlat

func _ready() -> void:
	custom_minimum_size = Vector2(236, 0)
	_sb_normal = StyleBoxFlat.new()
	_sb_normal.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	_sb_normal.set_corner_radius_all(8)
	_sb_normal.content_margin_left = 10
	_sb_normal.content_margin_right = 10
	_sb_normal.content_margin_top = 8
	_sb_normal.content_margin_bottom = 8
	# 当前行动者：金边 + 底色微亮（切换时带缩放呼吸）
	_sb_current = _sb_normal.duplicate()
	_sb_current.bg_color = Color(0.09, 0.09, 0.11, 0.85)
	_sb_current.border_color = Color(0.95, 0.78, 0.4, 0.9)
	_sb_current.set_border_width_all(2)
	add_theme_stylebox_override("panel", _sb_normal)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	add_child(h)

	_avatar = TextureRect.new()
	_avatar.custom_minimum_size = PORTRAIT_SIZE
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(_avatar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 15)
	col.add_child(_name_label)

	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 4)
	col.add_child(skill_row)
	_skill_icon = TextureRect.new()
	_skill_icon.custom_minimum_size = Vector2(20, 20)
	_skill_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skill_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	skill_row.add_child(_skill_icon)
	_skill_label = Label.new()
	_skill_label.add_theme_font_size_override("font_size", 12)
	_skill_label.modulate = Color(0.85, 0.82, 0.7)
	skill_row.add_child(_skill_label)

	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", 3)
	col.add_child(_hand_row)

	_cliff = preload("res://ui/cliff_bar.gd").new()
	_cliff.slab_size = Vector2(24, 16)
	col.add_child(_cliff)

	_timer_bar = ProgressBar.new()
	_timer_bar.max_value = 1.0
	_timer_bar.custom_minimum_size = Vector2(0, 6)
	_timer_bar.show_percentage = false
	_timer_bar.visible = false
	col.add_child(_timer_bar)

	_own_timer_label = Label.new()
	_own_timer_label.add_theme_font_size_override("font_size", 12)
	_own_timer_label.modulate = Color(0.6, 0.9, 1.0)
	_own_timer_label.visible = false
	col.add_child(_own_timer_label)

	# 表情气泡（浮在面板上方）
	_emote_label = Label.new()
	_emote_label.add_theme_font_size_override("font_size", 20)
	_emote_label.modulate = Color(1, 0.9, 0.5)
	_emote_label.position = Vector2(80, -26)
	_emote_label.visible = false
	add_child(_emote_label)

func _process(delta: float) -> void:
	if _emote_left > 0.0:
		_emote_left -= delta
		if _emote_left <= 0.0:
			_emote_label.visible = false

func flash_emote(text: String) -> void:
	_emote_label.text = "「" + text + "」"
	_emote_label.visible = true
	_emote_left = 2.0
	_emote_label.scale = Vector2(0.4, 0.4)
	var tw := _emote_label.create_tween()
	tw.tween_property(_emote_label, "scale", Vector2.ONE, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


# 坠崖时的摇晃演出（table 在 FALL 事件时调用）
func shake() -> void:
	pivot_offset = size / 2.0
	var tw := create_tween()
	tw.tween_property(self, "rotation", 0.05, 0.07)
	tw.tween_property(self, "rotation", -0.04, 0.09)
	tw.tween_property(self, "rotation", 0.02, 0.08)
	tw.tween_property(self, "rotation", 0.0, 0.10)

func set_data(d: Dictionary, is_me: bool, is_current: bool) -> void:
	var tex: Texture2D = Art.char_tex(d.id)
	if tex != null:
		_avatar.texture = tex

	var thinking: bool = d.get("thinking", false)
	var nm: String = d.name
	if is_me:
		nm += "（我）"
	_name_label.text = nm + ("  " + str(d.get("thinking_text", "…按剑不发")) if thinking else "")
	_name_label.modulate = Color(1, 0.85, 0.3) if is_current else Color(1, 1, 1)

	var icon: Texture2D = Art.skill_icon_tex(d.skill)
	_skill_icon.visible = icon != null and d.skill != Rules.Skill.NONE
	if icon != null:
		_skill_icon.texture = icon
	if d.skill == Rules.Skill.NONE:
		_skill_label.text = "报门户中…"
	else:
		var uses := ""
		if d.skill_uses_left == Rules.UNLIMITED:
			uses = "常驻"
		elif d.skill_uses_left == 0:
			uses = "已用尽"
		else:
			uses = "×%d" % d.skill_uses_left
		var cd := ""
		if d.skill == Rules.Skill.HOUFA:
			cd = "（冷却至第%d轮）" % d.houfa_ready_round if d.get("houfa_cooling", false) else ""
		_skill_label.text = "%s %s%s" % [Rules.SKILL_NAMES[d.skill], uses, cd]

	# 手牌数：迷你牌背 × N
	for c in _hand_row.get_children():
		c.free()
	var back: Texture2D = Art.card_back_tex()
	var n: int = d.hand_count
	for i in mini(n, 5):
		var tr := TextureRect.new()
		tr.custom_minimum_size = MINI_BACK
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if back != null:
			tr.texture = back
		_hand_row.add_child(tr)
	var cnt := Label.new()
	cnt.text = "×%d" % n if n > 0 else "手牌已空"
	cnt.add_theme_font_size_override("font_size", 12)
	_hand_row.add_child(cnt)

	_cliff.set_state(d.steps_taken, d.has_gap, d.alive)

	_timer_bar.visible = thinking
	if thinking:
		_timer_bar.value = d.get("timer_frac", 0.0)

	var own: int = d.get("own_timer", -1)
	_own_timer_label.visible = own >= 0
	if own >= 0:
		_own_timer_label.text = "剩 %d 秒" % own

	modulate = Color(0.4, 0.4, 0.4) if not d.alive else Color(1, 1, 1)

	# 轮到谁：金边亮起 + 轻微放大呼吸（只在切换瞬间起 tween，set_data 每帧都会被调）
	if is_current != _was_current:
		_was_current = is_current
		add_theme_stylebox_override("panel", _sb_current if is_current else _sb_normal)
		pivot_offset = size / 2.0
		var tw := create_tween()
		tw.tween_property(self, "scale",
			Vector2(1.045, 1.045) if is_current else Vector2.ONE, 0.16) \
			.set_ease(Tween.EASE_OUT)
