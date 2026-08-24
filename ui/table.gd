extends Control

# 驱动层 + 协调器（§14）。持有 GameState，负责：
#   - 倒计时（铁律 5：时间在驱动层，内核无计时器）
#   - 机器人思考时间（走 _ui_rng，纯表现，见 P2）
#   - 事件动画队列逐个播放
#   - 阶段超时（SKILL_PICK 15s / SWAP_WINDOW 5s / PLAY 20s）
# UI 渲染组件（player_panel / hand_panel / cliff_bar）只接收 view 裁剪数据，不持有 gs。
#
# P3：除 gs.apply / gs.view_for / gs.phase / gs.current_player / gs.winner /
#     gs.force_resolve_skill_pick / gs.new_game 外，不触碰 gs 的任何成员。
#
# 布局（UI 重构版）：
#   上方：对手信息卡一排（立绘+技能+手牌数+石板+读条）
#   中央：舞台——旁白、上家声称、牌背/亮招
#   底部：我的区域——大立绘 | 大手牌（128x192） | 操作按钮
#   右上：事件流；右下：表情；居中弹层：报门户 / 改弦 / 结算

const HUMAN_ID := 0

# 机器人思考时长（表现层参数，放在 UI 不动内核 rules.gd）
# 用户反馈"节奏快了"：下限 1.5 → 2.5，上限 8 → 9
const BOT_THINK_MIN := 2.5
const BOT_THINK_MAX := 9.0

const SKILL_DESCS := [
	"首次踏空不坠崖，但此后退无可退（下一退必坠）",
	"偷看上家刚打出的一张牌，全场只知道你看了（×2）",
	"你的出招读条对全场显示假值，没人读得出你的犹豫",
	"被冤枉时，拆你的人多退一步（每 3 轮一次）",
	"发牌后改变本轮路数（×1，全场可见是你改的）",
	"探查自己一块未踏过的石板是实是虚，结果只有你知道（×1）",
]

var gs: GameState
var _event_queue: Array = []
var _event_elapsed := 0.0

var _view: Dictionary = {}
var _names: Dictionary = {}

var _turn_time_left := 0.0
var _skill_pick_left := 0.0
var _swap_left := 0.0

var _bot_think_time := 0.0
var _bot_think_elapsed := 0.0

# 藏拙伪读条（P1b，规格 §15.4）
var _fake_T := 0.0
var _fake_elapsed := 0.0
var _fake_owner := -1

var _skill_pick_bots: Array = []
var _hand_snapshot: Array = []

# P2：两个独立 RNG，内核 RNG 从驱动层全部清零
var _ui_rng := RandomNumberGenerator.new()
var _driver_rng := RandomNumberGenerator.new()

# 统计
var _stat_human_timeouts := 0
var _stat_human_plays := 0
var _stat_start_ms := 0

# 舞台亮招展示（REVEALED 时填充，ROUND_START 时清空）
var _reveal_cards: Array = []
var _reveal_honest := false
var _reveal_pid := -1
var _stage_sig := ""            # 舞台内容签名：变了才重建（否则每帧重建会杀掉动画）
var _flash_rect: ColorRect      # 全屏闪光（退步红 / 金钟罩金）

# ---- UI 节点 ----
var _round_label: Label
var _suit_card: TextureRect
var _suit_label: Label
var _alive_label: Label
var _opp_row: HBoxContainer
var _narration: Label
var _claim_label: Label
var _stage_cards: HBoxContainer
var _hand_panel: Control
var _play_button: Button
var _challenge_button: Button
var _skill_button: Button
var _my_panel: Control            # 底部区域里“我”的信息卡
var _bottom_zone: PanelContainer
var _emote_bar: HBoxContainer
var _event_log: RichTextLabel
var _skill_modal: CenterContainer
var _skill_pick_label: Label
var _skill_desc_label: Label
var _swap_modal: CenterContainer
var _over_modal: CenterContainer
var _game_over_label: Label
var _restart_button: Button
var _intro_modal: CenterContainer
var _intro_start_btn: Button
var _hud_nodes: Array = []      # 开局前隐藏的 HUD（顶栏/日志/表情/底区）

var _opp_panels: Dictionary = {}   # pid -> panel（不含自己）


func _ready() -> void:
	_ui_rng.randomize()
	_build_ui()
	_build_intro()
	# 先看玩法介绍，点「开始对局」才发牌（用户反馈：需要开场白）
	for n in _hud_nodes:
		n.visible = false
	_intro_modal.visible = true


# ============================================================
# UI 构建
# ============================================================

func _build_ui() -> void:
	# 背景
	var bg_tex: Texture2D = Art.bg_tex()
	if bg_tex != null:
		var bg := TextureRect.new()
		bg.texture = bg_tex
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	# ---- 顶栏（居中悬浮小条）----
	var top_center := CenterContainer.new()
	top_center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_center.offset_top = 8
	top_center.offset_bottom = 52
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_center)
	_hud_nodes.append(top_center)
	var top_panel := PanelContainer.new()
	top_panel.add_theme_stylebox_override("panel", _flat_style(Color(0.05, 0.06, 0.09, 0.78), 8, 14, 6))
	top_center.add_child(top_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	top_panel.add_child(top)
	_round_label = _mk_label(top, 18)
	var suit_box := HBoxContainer.new()
	suit_box.add_theme_constant_override("separation", 6)
	top.add_child(suit_box)
	_suit_label = _mk_label(suit_box, 18)
	_suit_card = TextureRect.new()
	_suit_card.custom_minimum_size = Vector2(21, 32)
	_suit_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_suit_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	suit_box.add_child(_suit_card)
	_alive_label = _mk_label(top, 18)

	# ---- 对手一排 ----
	_opp_row = HBoxContainer.new()
	_opp_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_opp_row.offset_top = 58
	_opp_row.offset_bottom = 210
	_opp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_opp_row.add_theme_constant_override("separation", 14)
	add_child(_opp_row)

	# ---- 中央舞台 ----
	var stage := VBoxContainer.new()
	stage.set_anchors_preset(Control.PRESET_CENTER_TOP)
	stage.anchor_left = 0.5
	stage.anchor_right = 0.5
	stage.offset_left = -400
	stage.offset_right = 400
	stage.offset_top = 236
	stage.offset_bottom = 470
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", 10)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	_narration = _mk_label(stage, 24)
	_narration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narration.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_narration.add_theme_constant_override("outline_size", 6)
	_claim_label = _mk_label(stage, 17)
	_claim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_claim_label.modulate = Color(1, 0.88, 0.55)
	_claim_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_claim_label.add_theme_constant_override("outline_size", 5)
	var stage_center := CenterContainer.new()
	stage.add_child(stage_center)
	_stage_cards = HBoxContainer.new()
	_stage_cards.add_theme_constant_override("separation", 8)
	stage_center.add_child(_stage_cards)

	# ---- 底部：我的区域 ----
	_bottom_zone = PanelContainer.new()
	_bottom_zone.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_zone.offset_top = -240
	_bottom_zone.add_theme_stylebox_override("panel", _flat_style(Color(0.03, 0.04, 0.07, 0.82), 0, 16, 10))
	add_child(_bottom_zone)
	_hud_nodes.append(_bottom_zone)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	_bottom_zone.add_child(bottom)

	# 我的信息卡（复用 player_panel）
	_my_panel = preload("res://ui/player_panel.gd").new()
	bottom.add_child(_my_panel)

	# 手牌（居中扩展）
	_hand_panel = preload("res://ui/hand_panel.gd").new()
	_hand_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_hand_panel)
	_hand_panel.selection_changed.connect(_on_selection_changed)

	# 操作按钮列
	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 10)
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(btn_col)
	_play_button = _mk_action_button(btn_col, "出招")
	_play_button.pressed.connect(_on_play)
	_challenge_button = _mk_action_button(btn_col, "拆招！")
	_challenge_button.pressed.connect(_on_challenge)
	_skill_button = _mk_action_button(btn_col, "技能")
	_skill_button.pressed.connect(_on_skill)

	# ---- 表情（右下，悬于底区上缘）----
	_emote_bar = HBoxContainer.new()
	_emote_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_emote_bar.offset_left = -420
	_emote_bar.offset_right = -12
	_emote_bar.offset_top = -282
	_emote_bar.offset_bottom = -248
	_emote_bar.alignment = BoxContainer.ALIGNMENT_END
	_emote_bar.add_theme_constant_override("separation", 6)
	add_child(_emote_bar)
	for i in Rules.EMOTES.size():
		var b := Button.new()
		b.text = Rules.EMOTES[i]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_on_emote.bind(i))
		_emote_bar.add_child(b)
	_hud_nodes.append(_emote_bar)

	# ---- 事件流（右上，半透明，不挡鼠标）----
	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	log_panel.offset_left = 8
	log_panel.offset_right = 264
	log_panel.offset_top = 58
	log_panel.offset_bottom = 200
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_theme_stylebox_override("panel", _flat_style(Color(0.03, 0.04, 0.07, 0.55), 8, 8, 6))
	add_child(log_panel)
	_hud_nodes.append(log_panel)
	_event_log = RichTextLabel.new()
	_event_log.scroll_following = true
	_event_log.add_theme_font_size_override("normal_font_size", 13)
	_event_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_child(_event_log)

	# ---- 全屏闪光层（演出用，在弹层之下）----
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 0, 0, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	# ---- 报门户弹层 ----
	_skill_modal = CenterContainer.new()
	_skill_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skill_modal.visible = false
	add_child(_skill_modal)
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", _flat_style(Color(0.04, 0.05, 0.08, 0.94), 12, 22, 18))
	_skill_modal.add_child(sp)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	sp.add_child(sv)
	_skill_pick_label = _mk_label(sv, 22)
	_skill_pick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	sv.add_child(srow)
	for i in Rules.ALL_SKILLS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(104, 118)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_pick_skill.bind(i))
		b.mouse_entered.connect(_on_skill_hover.bind(i))
		var bv := VBoxContainer.new()
		bv.set_anchors_preset(Control.PRESET_FULL_RECT)
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		bv.add_theme_constant_override("separation", 6)
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bv)
		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(48, 48)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon: Texture2D = Art.skill_icon_tex(i)
		if icon != null:
			ic.texture = icon
		var icc := CenterContainer.new()
		icc.add_child(ic)
		bv.add_child(icc)
		var nl := Label.new()
		nl.text = Rules.SKILL_NAMES[i]
		nl.add_theme_font_size_override("font_size", 16)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(nl)
		srow.add_child(b)
	_skill_desc_label = _mk_label(sv, 15)
	_skill_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skill_desc_label.modulate = Color(0.85, 0.82, 0.7)
	_skill_desc_label.text = "移到技能上查看说明；同名技能全场唯一，抢选冲突随机裁决"

	# ---- 改弦弹层 ----
	_swap_modal = CenterContainer.new()
	_swap_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_swap_modal.visible = false
	add_child(_swap_modal)
	var wp := PanelContainer.new()
	wp.add_theme_stylebox_override("panel", _flat_style(Color(0.04, 0.05, 0.08, 0.94), 12, 22, 18))
	_swap_modal.add_child(wp)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 12)
	wp.add_child(wv)
	var wl := _mk_label(wv, 20)
	wl.text = "改弦：把本轮路数改为——"
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 12)
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wv.add_child(wrow)
	for s in Rules.PLAYABLE_SUITS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(80, 120)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_swap_suit.bind(s))
		var tr := TextureRect.new()
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex: Texture2D = Art.card_tex(s)
		if tex != null:
			tr.texture = tex
		b.add_child(tr)
		wrow.add_child(b)
	var skipb := Button.new()
	skipb.text = "不改（跳过）"
	skipb.focus_mode = Control.FOCUS_NONE
	skipb.pressed.connect(_on_pass_window)
	wv.add_child(skipb)

	# ---- 结算弹层 ----
	_over_modal = CenterContainer.new()
	_over_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_modal.visible = false
	add_child(_over_modal)
	var op := PanelContainer.new()
	op.add_theme_stylebox_override("panel", _flat_style(Color(0.04, 0.05, 0.08, 0.94), 12, 30, 24))
	_over_modal.add_child(op)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 14)
	ov.alignment = BoxContainer.ALIGNMENT_CENTER
	op.add_child(ov)
	_game_over_label = _mk_label(ov, 30)
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_restart_button = Button.new()
	_restart_button.text = "再来一局"
	_restart_button.custom_minimum_size = Vector2(160, 48)
	_restart_button.add_theme_font_size_override("font_size", 20)
	_restart_button.pressed.connect(_new_game)
	ov.add_child(_restart_button)


func _build_intro() -> void:
	# 右上角「？玩法」常驻按钮（对局中也能随时打开，打开时游戏暂停）
	var help := Button.new()
	help.text = "？玩法"
	help.focus_mode = Control.FOCUS_NONE
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help.offset_left = -84
	help.offset_right = -8
	help.offset_top = 10
	help.offset_bottom = 42
	help.pressed.connect(func(): _intro_modal.visible = true; _refresh_intro_button())
	add_child(help)

	_intro_modal = CenterContainer.new()
	_intro_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_modal.visible = false
	add_child(_intro_modal)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat_style(Color(0.03, 0.04, 0.07, 0.96), 12, 34, 26))
	_intro_modal.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(760, 0)
	p.add_child(v)

	var title := _mk_label(v, 34)
	title.text = "绝　顶"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(1, 0.88, 0.55)
	var subtitle := _mk_label(v, 15)
	subtitle.text = "华山之巅，群雄论招。诈与被诈，一步之间。"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.8, 0.78, 0.7)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(760, 0)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 16)
	rt.text = """[b][color=#e8c08c]怎么玩[/color][/b]
[color=#e8c08c]①[/color] 每轮定一个[b]路数[/b]（刀 / 剑 / 掌），每人发 5 张招式牌。
[color=#e8c08c]②[/color] 轮到你，二选一：
　　[b]出招[/b] —— 盖着打出 1~3 张，宣称"皆是本轮路数"。[color=#ff9a7a]可以撒谎。[/color]（化劲是百搭，算任何路数）
　　[b]拆招[/b] —— 掀开[b]上家[/b]刚打出的牌：他真在撒谎 → [color=#ff9a7a]他退一步[/color]；牌是真的 → [color=#ff9a7a]你冤枉了人，你退一步[/color]。
　　若其他人手牌都已出尽，你打出的每一手都会[b]自动亮招[/b]——[color=#ff9a7a]谎言无处可藏[/color]。
[color=#e8c08c]③[/color] 每人背后六块石板，[b]其中一块是虚的[/b]，位置无人知晓。退到虚石 → 坠崖出局。退得越多越危险（1/6 → 1/5 → … → 必坠）。
[color=#e8c08c]④[/color] 最后还站在崖顶的人赢。

[b][color=#e8c08c]盘外招[/color][/b]　开局各选一门技能，人人不同、全场公开：
金钟罩·免死一次　听劲·偷看上家一张　藏拙·读条造假　后发制人·冤枉我者多退一步　改弦·改路数　辨虚实·探一块石板"""
	v.add_child(rt)

	_intro_start_btn = Button.new()
	_intro_start_btn.text = "开始对局"
	_intro_start_btn.custom_minimum_size = Vector2(200, 52)
	_intro_start_btn.add_theme_font_size_override("font_size", 22)
	_intro_start_btn.pressed.connect(_on_intro_start)
	var bc := CenterContainer.new()
	bc.add_child(_intro_start_btn)
	v.add_child(bc)


func _on_intro_start() -> void:
	_intro_modal.visible = false
	if gs == null:
		for n in _hud_nodes:
			n.visible = true
		_new_game()


func _refresh_intro_button() -> void:
	_intro_start_btn.text = "开始对局" if gs == null else "继续对局"


func _mk_label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _mk_action_button(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	# 清晰的描边按钮（木纹贴图在暗底上几乎不可见，弃用）
	var sb_n := _flat_style(Color(0.16, 0.13, 0.09, 0.95), 6, 10, 6)
	sb_n.border_color = Color(0.78, 0.64, 0.35)
	sb_n.set_border_width_all(2)
	var sb_h := _flat_style(Color(0.24, 0.19, 0.12, 0.95), 6, 10, 6)
	sb_h.border_color = Color(1.0, 0.85, 0.5)
	sb_h.set_border_width_all(2)
	var sb_d := _flat_style(Color(0.10, 0.10, 0.12, 0.6), 6, 10, 6)
	sb_d.border_color = Color(0.4, 0.4, 0.4, 0.5)
	sb_d.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", sb_n)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_stylebox_override("disabled", sb_d)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	parent.add_child(b)
	return b


func _flat_style(col: Color, radius: int, margin_h: int, margin_v: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


# ============================================================
# 开局
# ============================================================

func _new_game() -> void:
	var names := ["你"]
	var bots := [false]
	for i in range(1, 4):          # 1 真人 + 3 机器人 = 4 人局
		names.append("机器人%d" % i)
		bots.append(true)
	var seed: int = int(Time.get_unix_time_from_system()) & 0x7fffffff
	gs = GameState.new(seed, true)
	gs.new_game(names, bots)
	_driver_rng.seed = hash(str(seed) + "driver")

	_event_queue.clear()
	_event_elapsed = 0.0
	_bot_think_elapsed = 0.0
	_bot_think_time = 0.0
	_fake_T = 0.0
	_fake_elapsed = 0.0
	_fake_owner = -1
	_turn_time_left = Rules.PLAY_TIMEOUT_SEC
	_skill_pick_left = Rules.SKILL_PICK_SEC
	_swap_left = Rules.SWAP_WINDOW_SEC
	_hand_snapshot = []
	_reveal_cards = []
	_reveal_pid = -1
	_stat_human_timeouts = 0
	_stat_human_plays = 0
	_stat_start_ms = Time.get_ticks_msec()

	_names = {}
	_skill_pick_bots = []
	for i in names.size():
		_names[i] = names[i]
		if bots[i]:
			_skill_pick_bots.append(i)

	_over_modal.visible = false
	_event_log.clear()
	_narration.text = "群雄齐聚绝顶，各报门户——"
	_claim_label.text = ""

	# 对手面板（自己不在上排）
	for pid in _opp_panels:
		_opp_panels[pid].queue_free()
	_opp_panels = {}
	for i in range(1, names.size()):
		var panel = preload("res://ui/player_panel.gd").new()
		_opp_row.add_child(panel)
		_opp_panels[i] = panel

	_log_event_text("开局：%d 人局，报门户选技能（15 秒）" % names.size())
	_refresh()


# ============================================================
# 驱动（逻辑与重构前一致）
# ============================================================

func _process(delta: float) -> void:
	if gs == null:
		return
	if _intro_modal.visible:
		return          # 看玩法时整局暂停（倒计时、机器人、事件队列全部冻结）
	if not _event_queue.is_empty():
		_event_elapsed += delta
		if _event_elapsed >= _delay_for(_event_queue[0]):
			_event_elapsed = 0.0
			var e: Dictionary = _event_queue.pop_front()
			_on_event_popped(e)
			_refresh()
		return

	_view = gs.view_for(HUMAN_ID)
	_update_fake_timer(delta)

	match gs.phase:
		Rules.Phase.GAME_OVER:
			_show_game_over()
		Rules.Phase.SKILL_PICK:
			_tick_skill_pick(delta)
		Rules.Phase.SWAP_WINDOW:
			_tick_swap(delta)
		Rules.Phase.PLAY:
			_tick_play(delta)
	_refresh()


func _tick_skill_pick(delta: float) -> void:
	_skill_pick_left -= delta
	if not _skill_pick_bots.is_empty():
		var pid: int = _skill_pick_bots.pop_front()
		var s: int = _driver_rng.randi_range(0, Rules.ALL_SKILLS.size() - 1)
		_apply(Action.pick_skill(pid, s))
		return
	if _view.you.alive and _view.you.pending_skill_pick == Rules.Skill.NONE:
		if _skill_pick_left <= 0.0:
			_apply_events(gs.force_resolve_skill_pick())
			return


func _tick_swap(delta: float) -> void:
	_swap_left -= delta
	var swap_pid := -1
	for p in _view.players:
		if p.alive and p.skill == Rules.Skill.GAIXIAN and p.skill_uses_left > 0:
			swap_pid = p.id
			break
	if swap_pid == -1:
		_apply(Action.pass_window())
		return
	if _view.players[swap_pid].is_bot:
		if _driver_rng.randf() < 0.5:
			# 修复：机器人改弦不再可能改成原路数（原版会出现「由刀改为刀」）
			var options: Array = []
			for s in Rules.PLAYABLE_SUITS:
				if s != _view.current_suit:
					options.append(s)
			_apply(Action.use_gaixian(swap_pid, options[_driver_rng.randi_range(0, options.size() - 1)]))
		else:
			_apply(Action.pass_window())
		return
	if _swap_left <= 0.0:
		_apply(Action.pass_window())


func _tick_play(delta: float) -> void:
	var pid: int = gs.current_player
	if pid < 0:
		return
	if _view.players[pid].is_bot:
		if _bot_think_elapsed == 0.0:
			_bot_think_time = _ui_rng.randf_range(BOT_THINK_MIN, BOT_THINK_MAX)
		_bot_think_elapsed += delta
		if _bot_think_elapsed >= _bot_think_time:
			_bot_think_elapsed = 0.0
			_apply(Bot.decide(gs.view_for(pid), _driver_rng))
	else:
		_turn_time_left -= delta
		if _turn_time_left <= 0.0:
			_turn_time_left = Rules.PLAY_TIMEOUT_SEC
			_stat_human_timeouts += 1
			var hand: Array = _view.you.hand
			if hand.size() > 0:
				var idx: int = _driver_rng.randi_range(0, hand.size() - 1)
				_apply(Action.play(HUMAN_ID, [idx]))


func _apply(a: Dictionary) -> void:
	var events := gs.apply(a)
	if a.get("type", "") == "PLAY" and a.get("pid", -1) == HUMAN_ID and not _has_type(events, "REJECTED"):
		_stat_human_plays += 1
	_apply_events(events)


func _apply_events(events: Array) -> void:
	match gs.phase:
		Rules.Phase.PLAY:
			_turn_time_left = Rules.PLAY_TIMEOUT_SEC
			_bot_think_elapsed = 0.0
			_bot_think_time = 0.0
		Rules.Phase.SWAP_WINDOW:
			_swap_left = Rules.SWAP_WINDOW_SEC
		Rules.Phase.SKILL_PICK:
			pass
	_event_queue.append_array(events)


# 演出：全屏闪光 + 玩家面板弹跳
func _flash(col: Color, a: float) -> void:
	_flash_rect.color = Color(col.r, col.g, col.b, a)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.55)

func _punch(pid: int) -> void:
	var panel: Control = _my_panel if pid == HUMAN_ID else _opp_panels.get(pid)
	if panel == null:
		return
	panel.pivot_offset = panel.size / 2.0
	var tw := create_tween()
	tw.tween_property(panel, "scale", Vector2(1.09, 1.09), 0.1)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22)


# 每个事件在旁白上停留多久：重头戏停久一点，杂事快速过
func _delay_for(e: Dictionary) -> float:
	match e.get("type", ""):
		"REVEALED", "GOLDEN_BELL", "FALL", "HOUFA_TRIGGERED", "GAME_OVER":
			return 2.4
		"CHALLENGED", "HEAVEN_CHECK":
			return 1.8
		"ROUND_START", "ROUND_END", "SKILLS_ASSIGNED", "SUIT_CHANGED":
			return 1.5
		"DEALT", "SKIPPED", "EMOTE":
			return 0.7
	return 1.2


# ---------- 藏拙伪读条（P1b，规格 §15.4）----------
func _update_fake_timer(delta: float) -> void:
	if gs.phase != Rules.Phase.PLAY:
		_fake_owner = -1
		return
	var cp: int = gs.current_player
	if cp >= 0 and _is_cangzhuo(cp, _view):
		if _fake_owner != cp:
			_fake_owner = cp
			_fake_T = _ui_rng.randf_range(Rules.CANGZHUO_FAKE_MIN, Rules.CANGZHUO_FAKE_MAX)
			_fake_elapsed = 0.0
		_fake_elapsed += delta
	else:
		_fake_owner = -1


func _fake_timer_frac() -> float:
	return clampf(_fake_elapsed / maxf(_fake_T, 0.01), 0.0, 1.0)


func _is_cangzhuo(pid: int, v: Dictionary) -> bool:
	if pid < 0 or pid >= v.players.size():
		return false
	return v.skills_enabled and int(v.players[pid].skill) == Rules.Skill.CANGZHUO


# ============================================================
# 事件消费（旁白 + 日志 + 舞台状态）
# ============================================================

func _on_event_popped(e: Dictionary) -> void:
	var txt := _event_text(e)
	_log_event_text(txt)
	_narration.text = txt

	match e.type:
		"ROUND_START":
			_reveal_cards = []
			_reveal_pid = -1
		"REVEALED":
			_reveal_cards = e.cards.duplicate()
			_reveal_honest = e.honest
			_reveal_pid = e.pid
		"RETREAT":
			_flash(Color(0.9, 0.1, 0.1), 0.22)
			_punch(int(e.pid))
		"FALL":
			_flash(Color(0.75, 0.0, 0.0), 0.45)
			_punch(int(e.pid))
		"GOLDEN_BELL":
			_flash(Color(1.0, 0.82, 0.3), 0.35)
			_punch(int(e.pid))
		"HOUFA_TRIGGERED":
			_flash(Color(0.4, 0.5, 1.0), 0.25)
		"EMOTE":
			if _opp_panels.has(int(e.pid)):
				_opp_panels[int(e.pid)].flash_emote(Rules.EMOTES[e.emote])
		"SKILL_USED":
			# 私有结果提示（只有自己的视图里才有）
			if int(e.pid) == HUMAN_ID:
				var v := gs.view_for(HUMAN_ID)
				if int(e.skill) == Rules.Skill.TINGJIN:
					var key := str(v.round_number)
					if v.you.listen_result.has(key):
						var suit: int = v.you.listen_result[key]
						_narration.text = "你听劲窥得一式：【%s】" % Rules.SUIT_NAMES[suit]
						_log_event_text("（仅你可见）听劲结果：【%s】" % Rules.SUIT_NAMES[suit])
				elif int(e.skill) == Rules.Skill.BIANXUSHI:
					for k in v.you.probe_result:
						var hollow: bool = v.you.probe_result[k]
						var word := "虚！！" if hollow else "实"
						_narration.text = "你辨得第 %s 块石板：%s" % [k, word]
						_log_event_text("（仅你可见）辨虚实：第 %s 块是%s" % [k, word])


# ============================================================
# 输入回调
# ============================================================

func _on_play() -> void:
	var indices: Array = _hand_panel.selected_indices()
	if indices.size() >= 1 and indices.size() <= Rules.MAX_PLAY_CARDS:
		_apply(Action.play(HUMAN_ID, indices))


func _on_challenge() -> void:
	_apply(Action.challenge(HUMAN_ID))


func _on_skill() -> void:
	var you: Dictionary = _view.you
	match you.skill:
		Rules.Skill.TINGJIN:
			if _view.last_player_who_played != -1 and _view.last_played_count > 0:
				_apply(Action.use_tingjin(HUMAN_ID, 0))
		Rules.Skill.BIANXUSHI:
			if you.steps_taken < Rules.STONES:
				_apply(Action.use_bianxushi(HUMAN_ID, you.steps_taken + 1))
		_:
			pass


func _on_pass_window() -> void:
	_apply(Action.pass_window())


func _on_swap_suit(s: int) -> void:
	_apply(Action.use_gaixian(HUMAN_ID, s))


func _on_pick_skill(s: int) -> void:
	if gs.phase == Rules.Phase.SKILL_PICK and _view.you.pending_skill_pick == Rules.Skill.NONE:
		_apply(Action.pick_skill(HUMAN_ID, s))


func _on_skill_hover(s: int) -> void:
	_skill_desc_label.text = "%s：%s" % [Rules.SKILL_NAMES[s], SKILL_DESCS[s]]


func _on_emote(i: int) -> void:
	if _view.get("you", {}).get("alive", false):
		_apply(Action.emote(HUMAN_ID, i))


func _on_selection_changed(indices: Array) -> void:
	var is_human_turn: bool = gs != null and gs.phase == Rules.Phase.PLAY \
		and int(_view.get("current_player", -1)) == HUMAN_ID
	_play_button.disabled = not is_human_turn or indices.size() < 1 or indices.size() > Rules.MAX_PLAY_CARDS


# ============================================================
# 刷新
# ============================================================

func _refresh() -> void:
	if gs == null:
		return
	_view = gs.view_for(HUMAN_ID)

	# 顶栏
	_round_label.text = "第 %d 轮" % _view.round_number
	if _view.round_number <= 0 or _view.current_suit < 0:
		_suit_label.text = "路数 ——"
		_suit_card.visible = false
	else:
		var changed := ""
		if _view.suit_changed_by != -1:
			changed = "（%s 改弦）" % _names[_view.suit_changed_by]
		_suit_label.text = "本轮论【%s】%s" % [Rules.SUIT_NAMES[_view.current_suit], changed]
		var tex: Texture2D = Art.card_tex(_view.current_suit)
		_suit_card.visible = tex != null
		if tex != null:
			_suit_card.texture = tex
	_alive_label.text = "余 %d 人" % _view.alive_count

	# 面板数据（P1：读条对所有人显示）
	for i in _view.players.size():
		var d: Dictionary = (_view.players[i] as Dictionary).duplicate()
		var is_current: bool = i == int(_view.current_player)
		d["thinking"] = false
		d["timer_frac"] = 0.0
		d["thinking_text"] = "…按剑不发"
		d["own_timer"] = -1
		d["houfa_cooling"] = d.skill == Rules.Skill.HOUFA and _view.round_number < d.houfa_ready_round
		if gs.phase == Rules.Phase.PLAY and is_current and d.alive:
			d["thinking"] = true
			if _is_cangzhuo(i, _view):
				d["timer_frac"] = _fake_timer_frac()
				if _fake_timer_frac() >= 1.0:
					d["thinking_text"] = "仍在沉吟"
			elif d.is_bot:
				d["timer_frac"] = clampf(_bot_think_elapsed / maxf(_bot_think_time, 0.01), 0.0, 1.0)
			else:
				d["timer_frac"] = clampf(1.0 - _turn_time_left / Rules.PLAY_TIMEOUT_SEC, 0.0, 1.0)
			if i == HUMAN_ID:
				d["own_timer"] = int(ceil(_turn_time_left))
		if i == HUMAN_ID:
			_my_panel.set_data(d, true, is_current)
		elif _opp_panels.has(i):
			_opp_panels[i].set_data(d, false, is_current)

	# 舞台：亮招 > 牌背 > 空。内容签名没变就不重建（重建会杀掉翻牌动画）
	var sig := ""
	if not _reveal_cards.is_empty():
		sig = "R%s|%d" % [str(_reveal_cards), _reveal_pid]
		_claim_label.text = "%s 的招亮出真章 —— %s" % [_names[_reveal_pid], "句句是真" if _reveal_honest else "虚招被识破！"]
	elif _view.last_played_count > 0 and _view.last_player_who_played >= 0:
		sig = "B%d|%d" % [_view.last_played_count, _view.last_player_who_played]
		_claim_label.text = "%s 押下 %d 式，声称皆是【%s】" % [
			_names[_view.last_player_who_played], _view.last_played_count, Rules.SUIT_NAMES[_view.current_suit]]
	else:
		_claim_label.text = "本轮尚未有人出招" if gs.phase == Rules.Phase.PLAY else ""
	if sig != _stage_sig:
		_stage_sig = sig
		for c in _stage_cards.get_children():
			c.free()
		if not _reveal_cards.is_empty():
			# 逐张翻出：错峰淡入，学原版亮牌瞬间的节奏
			for i in _reveal_cards.size():
				var card := _mk_stage_card(Art.card_tex(_reveal_cards[i]), _reveal_cards[i])
				card.modulate.a = 0.0
				_stage_cards.add_child(card)
				var tw := create_tween()
				tw.tween_interval(0.15 * i)
				tw.tween_property(card, "modulate:a", 1.0, 0.18)
		elif _view.last_played_count > 0 and _view.last_player_who_played >= 0:
			for i in _view.last_played_count:
				_stage_cards.add_child(_mk_stage_card(Art.card_back_tex(), -1))

	# 手牌（仅内容变化时重建，保留选中态）
	var hand: Array = _view.you.hand
	if str(hand) != str(_hand_snapshot):
		_hand_snapshot = hand.duplicate()
		_hand_panel.set_hand(hand)
	var in_play: bool = gs.phase == Rules.Phase.PLAY or gs.phase == Rules.Phase.SWAP_WINDOW
	_bottom_zone.visible = _view.you.alive and gs.phase != Rules.Phase.SKILL_PICK
	_emote_bar.visible = _view.you.alive and gs.phase != Rules.Phase.SKILL_PICK

	# 按钮态
	var is_human_turn: bool = gs.phase == Rules.Phase.PLAY \
		and int(_view.current_player) == HUMAN_ID and _view.you.hand.size() > 0
	_play_button.disabled = not is_human_turn or _hand_panel.selected_indices().size() < 1
	_challenge_button.disabled = not (is_human_turn and _has_type(_view.legal_actions, "CHALLENGE"))
	var sk: int = _view.you.skill
	var can_skill := is_human_turn and _has_skill_action(_view.legal_actions)
	_skill_button.visible = can_skill
	if can_skill:
		if sk == Rules.Skill.TINGJIN:
			_skill_button.text = "听劲 ×%d" % _view.you.skill_uses_left
		elif sk == Rules.Skill.BIANXUSHI:
			_skill_button.text = "辨虚实"
		else:
			_skill_button.text = Rules.SKILL_NAMES[sk] if sk != Rules.Skill.NONE else "技能"

	# 弹层
	var picking: bool = gs.phase == Rules.Phase.SKILL_PICK \
		and _view.you.pending_skill_pick == Rules.Skill.NONE and _view.you.alive
	_skill_modal.visible = picking
	if picking:
		_skill_pick_label.text = "报门户 —— 选一门技能（剩 %d 秒）" % int(maxf(_skill_pick_left, 0.0))
	_swap_modal.visible = gs.phase == Rules.Phase.SWAP_WINDOW \
		and _view.you.alive and _view.you.skill == Rules.Skill.GAIXIAN and _view.you.skill_uses_left > 0

	if gs.phase == Rules.Phase.GAME_OVER:
		_over_modal.visible = true
		_game_over_label.text = "🏆 %s 独立绝顶！" % _names[gs.winner]


func _mk_stage_card(tex: Texture2D, suit: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(96, 144)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(tr)
	else:
		var rect := ColorRect.new()
		rect.color = Color("#3A3F4A") if suit < 0 else Color("#C9A54F")
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_child(rect)
	return box


func _show_game_over() -> void:
	if _over_modal.visible:
		return
	var secs := (Time.get_ticks_msec() - _stat_start_ms) / 1000.0
	var rate := 0.0
	if _stat_human_plays > 0:
		rate = float(_stat_human_timeouts) / float(_stat_human_plays)
	print("=== 一局结束 ===")
	print("  轮数 %d，时长 %.1f 分钟" % [_view.round_number, secs / 60.0])
	print("  真人出招 %d 次，超时 %d 次，超时率 %.1f%%" % [_stat_human_plays, _stat_human_timeouts, rate * 100.0])


# ============================================================
# 事件文本
# ============================================================

func _has_type(arr: Array, t: String) -> bool:
	for a in arr:
		if a.get("type", "") == t:
			return true
	return false


func _has_skill_action(legal: Array) -> bool:
	for a in legal:
		var t: String = a.get("type", "")
		if t == "USE_TINGJIN" or t == "USE_BIANXUSHI":
			return true
	return false


func _nm(pid: int) -> String:
	return _names.get(int(pid), "P%d" % int(pid))


func _event_text(e: Dictionary) -> String:
	match e.type:
		"REJECTED": return "⚠ 非法动作被拒：%s" % e.reason
		"SKILLS_ASSIGNED": return "各家门户已报——技能揭晓"
		"ROUND_START": return "—— 第 %d 轮 · 论【%s】，%s 先出 ——" % [e.round, Rules.SUIT_NAMES[e.suit], _nm(e.starter)]
		"DEALT": return "发牌完成"
		"SUIT_CHANGED": return "%s 改弦！路数由【%s】改为【%s】" % [_nm(e.by), Rules.SUIT_NAMES[e["from"]], Rules.SUIT_NAMES[e.to]]
		"PLAYED": return "%s 押下 %d 式" % [_nm(e.pid), e.count]
		"SKILL_USED": return "%s 发动【%s】" % [_nm(e.pid), Rules.SKILL_NAMES[e.skill]]
		"SKIPPED": return "%s 招已出尽，过" % _nm(e.pid)
		"CHALLENGED": return "%s 断喝一声：拆 %s 的招！" % [_nm(e.by), _nm(e.target)]
		"HEAVEN_CHECK": return "已无人可拆 %s 的招——天道代拆，自动亮招！" % _nm(e.pid)
		"REVEALED": return "%s 亮出真章：%s —— %s" % [_nm(e.pid), _cards_text(e.cards), "句句是真" if e.honest else "虚招！"]
		"HOUFA_TRIGGERED": return "%s 后发制人，反噬 %s！" % [_nm(e.pid), _nm(e.victim)]
		"RETREAT": return "%s 退了一步（第 %d 格）" % [_nm(e.pid), e.to_step]
		"GOLDEN_BELL": return "%s 金钟罩护体！石板碎裂，身后只余豁口" % _nm(e.pid)
		"FALL": return "%s 一脚踏空，坠入云海！" % _nm(e.pid)
		"ROUND_END": return "—— 本轮终了 ——"
		"GAME_OVER": return "🏆 %s 独立绝顶！" % _nm(e.winner)
		"EMOTE": return "%s：「%s」" % [_nm(e.pid), Rules.EMOTES[e.emote]]
	return str(e)


func _cards_text(cards: Array) -> String:
	var parts := []
	for c in cards:
		parts.append("【%s】" % Rules.SUIT_NAMES[c])
	return "".join(parts)


func _log_event_text(s: String) -> void:
	_event_log.append_text(s + "\n")
