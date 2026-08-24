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
var _idle_tween: Tween
var _frames: Array = []
var _frames_pid := -1
var _frame_i := 0
var _frame_dir := 1
var _frame_t := 0.0
const FRAME_DT := 0.13
# 一次性动画（表情/坠崖）：播完自动回待机
var _once_frames: Array = []
var _once_i := 0
var _once_t := 0.0
var _once_hold := false        # 播完停在最后一帧（坠崖用）
var _fx_rect: TextureRect      # 金钟罩护体覆盖层
var _fx_frames: Array = []
var _fx_i := 0
var _fx_t := 0.0

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

	var holder := Control.new()
	holder.custom_minimum_size = PORTRAIT_SIZE
	h.add_child(holder)
	_avatar = TextureRect.new()
	_avatar.custom_minimum_size = PORTRAIT_SIZE
	_avatar.size = PORTRAIT_SIZE
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar.pivot_offset = PORTRAIT_SIZE / 2.0
	holder.add_child(_avatar)
	# 待机呼吸：轻微起伏 + 极小摆动，相位随机避免全场同步机械感
	var phase := randf() * 1.2
	_idle_tween = _avatar.create_tween().set_loops()
	var idle := _idle_tween
	idle.tween_interval(phase)
	idle.tween_property(_avatar, "position:y", -2.0, 0.9 + randf() * 0.4) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	idle.tween_property(_avatar, "position:y", 0.0, 0.9 + randf() * 0.4) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

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
	# 一次性动画优先（表情/坠崖）
	if not _once_frames.is_empty():
		_once_t += delta
		if _once_t >= 0.11:
			_once_t = 0.0
			_once_i += 1
			if _once_i >= _once_frames.size():
				if _once_hold:
					_once_i = _once_frames.size() - 1   # 停格
				else:
					_once_frames = []
					_once_i = 0
			if not _once_frames.is_empty():
				_avatar.texture = _once_frames[_once_i]
		if not _once_frames.is_empty():
			pass
		# 播特效层
		_tick_fx(delta)
		return
	_tick_fx(delta)
	# 待机帧动画：乒乓播放（0..8..0），首尾无缝
	if _frames.size() > 1:
		_frame_t += delta
		if _frame_t >= FRAME_DT:
			_frame_t = 0.0
			_frame_i += _frame_dir
			if _frame_i >= _frames.size() - 1:
				_frame_i = _frames.size() - 1
				_frame_dir = -1
			elif _frame_i <= 0:
				_frame_i = 0
				_frame_dir = 1
			_avatar.texture = _frames[_frame_i]

func flash_emote(text: String) -> void:
	_emote_label.text = "「" + text + "」"
	_emote_label.visible = true
	_emote_left = 2.0
	_emote_label.scale = Vector2(0.4, 0.4)
	var tw := _emote_label.create_tween()
	tw.tween_property(_emote_label, "scale", Vector2.ONE, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


# 事件反应动画（table 在事件弹出时调用）
func react(kind: String) -> void:
	match kind:
		"play":     # 出招：向前探身一顿
			var tw := _avatar.create_tween()
			tw.tween_property(_avatar, "position:x", 7.0, 0.09).set_ease(Tween.EASE_OUT)
			tw.tween_property(_avatar, "position:x", 0.0, 0.22).set_ease(Tween.EASE_IN_OUT)
		"challenge":  # 拆招断喝：猛地前倾 + 放大
			var tw2 := _avatar.create_tween().set_parallel(true)
			tw2.tween_property(_avatar, "scale", Vector2(1.12, 1.12), 0.1).set_ease(Tween.EASE_OUT)
			tw2.tween_property(_avatar, "position:x", 9.0, 0.1)
			tw2.chain().tween_property(_avatar, "scale", Vector2.ONE, 0.25)
			tw2.parallel().tween_property(_avatar, "position:x", 0.0, 0.25)
		"flinch":   # 被拆/被指认：缩一下再回弹
			var tw3 := _avatar.create_tween()
			tw3.tween_property(_avatar, "scale", Vector2(0.9, 0.9), 0.08)
			tw3.tween_property(_avatar, "scale", Vector2.ONE, 0.3) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		"retreat":  # 退步：向后一跳
			var tw4 := _avatar.create_tween()
			tw4.tween_property(_avatar, "position:x", -10.0, 0.12).set_ease(Tween.EASE_OUT)
			tw4.tween_property(_avatar, "position:y", -6.0, 0.08)
			tw4.tween_property(_avatar, "position:y", 0.0, 0.1)
			tw4.tween_property(_avatar, "position:x", 0.0, 0.3)
		"fall":     # 坠崖：旋转跌出面板
			var tw5 := _avatar.create_tween().set_parallel(true)
			tw5.tween_property(_avatar, "rotation", 0.9, 0.7).set_ease(Tween.EASE_IN)
			tw5.tween_property(_avatar, "position:y", 70.0, 0.7).set_ease(Tween.EASE_IN)
			tw5.tween_property(_avatar, "modulate:a", 0.25, 0.7)
		"bell":     # 金钟罩：金光一闪
			var tw6 := _avatar.create_tween()
			tw6.tween_property(_avatar, "modulate", Color(1.8, 1.5, 0.7), 0.12)
			tw6.tween_property(_avatar, "modulate", Color(1, 1, 1), 0.5)


func _tick_fx(delta: float) -> void:
	if _fx_frames.is_empty() or _fx_rect == null:
		return
	_fx_t += delta
	if _fx_t >= 0.11:
		_fx_t = 0.0
		_fx_i += 1
		if _fx_i >= _fx_frames.size() * 2:    # 播两轮
			_fx_frames = []
			_fx_rect.visible = false
			return
		_fx_rect.texture = _fx_frames[_fx_i % _fx_frames.size()]


# 播放一次性帧动画：表情（播完回待机）
func play_emote_anim(pid: int, emote: int) -> void:
	var f: Array = Art.emote_frames(pid, emote)
	if f.size() > 1:
		_once_frames = f
		_once_i = 0
		_once_t = 0.0
		_once_hold = false
		_avatar.texture = f[0]


# 坠崖帧动画：播完停在最后一帧（配合旋转跌落）
func play_fall_anim(pid: int) -> void:
	var f: Array = Art.fall_frames(pid)
	if f.size() > 1:
		_once_frames = f
		_once_i = 0
		_once_t = 0.0
		_once_hold = true
		_avatar.texture = f[0]


# 金钟罩护体：金钟特效覆盖在立绘上播两轮
func play_bell_fx() -> void:
	var f: Array = Art.bell_frames()
	if f.is_empty():
		return
	if _fx_rect == null:
		_fx_rect = TextureRect.new()
		_fx_rect.custom_minimum_size = PORTRAIT_SIZE
		_fx_rect.size = PORTRAIT_SIZE
		_fx_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_fx_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_avatar.get_parent().add_child(_fx_rect)
	_fx_rect.visible = true
	_fx_rect.modulate = Color(1, 1, 1, 0.75)
	_fx_frames = f
	_fx_i = 0
	_fx_t = 0.0
	_fx_rect.texture = f[0]


# 坠崖时的摇晃演出（table 在 FALL 事件时调用）
func shake() -> void:
	pivot_offset = size / 2.0
	var tw := create_tween()
	tw.tween_property(self, "rotation", 0.05, 0.07)
	tw.tween_property(self, "rotation", -0.04, 0.09)
	tw.tween_property(self, "rotation", 0.02, 0.08)
	tw.tween_property(self, "rotation", 0.0, 0.10)

func set_data(d: Dictionary, is_me: bool, is_current: bool) -> void:
	if _frames_pid != int(d.id):
		_frames_pid = int(d.id)
		_frames = Art.char_frames(_frames_pid)
		_frame_i = 0
		_frame_dir = 1
		if not _frames.is_empty():
			_avatar.texture = _frames[0]
		if _frames.size() > 1 and _idle_tween != null:
			_idle_tween.kill()          # 有真帧动画就停掉位移呼吸，避免双重晃动

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
