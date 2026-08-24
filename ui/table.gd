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

const NC := preload("res://ui/net_client.gd")

# 触屏设备：加大点击目标（手机横屏优化）
var _touch := false

# 本座位号：单机恒 0；联机 = 服务端分配的 seat
var my_id := 0
var online := false
var net = null                        # NetClient（preload 见 NC）
var _rgame = null                     # NetClient.RemoteGame
var _game_started_online := false

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

var gs  # GameState（单机）或 NetClient.RemoteGame（联机影子，见 net_client.gd）
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
var _swap_suit_btns: Array = []        # 改弦的三张路数牌按钮（当前路数要禁用）
var _probe_modal: CenterContainer      # 辨虚实：选石板
var _probe_row: HBoxContainer
var _listen_modal: CenterContainer     # 听劲：选看哪张
var _listen_row: HBoxContainer
var _over_modal: CenterContainer
var _game_over_label: Label
var _restart_button: Button
var _intro_modal: CenterContainer
var _intro_start_btn: Button
var _name_edit: LineEdit
var _room_edit: LineEdit
var _menu_err: Label
var _http: HTTPRequest
var _lobby_modal: CenterContainer
var _lobby_code_label: Label
var _lobby_seats_row: HBoxContainer
var _lobby_status: Label
var _btn_addbot: Button
var _btn_rmbot: Button
var _btn_start_online: Button
var _hud_nodes: Array = []      # 开局前隐藏的 HUD（顶栏/日志/表情/底区）

var _opp_panels: Dictionary = {}   # pid -> panel（不含自己）
var _lobby_prev_seats := 0         # 入座动画：检测新落座
var _char_btns: Array = []         # 报门户选皮囊按钮（高亮当前选择）


func _ready() -> void:
	_ui_rng.randomize()
	_touch = DisplayServer.is_touchscreen_available()
	_build_ui()
	_build_intro()
	_build_lobby()
	_build_skill_target_modals()
	_build_orientation_overlay()
	get_viewport().size_changed.connect(_check_orientation)
	_check_orientation()
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
		# 云海慢漂移：极缓的缩放往复，让静态背景"活"起来
		bg.resized.connect(func(): bg.pivot_offset = bg.size / 2.0)
		var drift := bg.create_tween().set_loops()
		drift.tween_property(bg, "scale", Vector2(1.05, 1.05), 16.0) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		drift.tween_property(bg, "scale", Vector2.ONE, 16.0) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

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
		if _touch:
			b.custom_minimum_size = Vector2(60, 44)
		b.add_theme_font_size_override("font_size", 17 if _touch else 14)
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
	# 选皮囊行：六位侠士自由挑，可与他人重复（v0.9）
	var chint := _mk_label(sv, 14)
	chint.text = "选个皮囊 ——"
	chint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chint.modulate = Color(0.8, 0.78, 0.68)
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 8)
	sv.add_child(crow)
	for ci in 6:
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(76, 108)
		cb.flat = true
		cb.focus_mode = Control.FOCUS_NONE
		cb.pressed.connect(_on_pick_char.bind(ci))
		var ctr := TextureRect.new()
		ctr.set_anchors_preset(Control.PRESET_FULL_RECT)
		ctr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ctr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ctr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ctex := Art.load_tex("res://assets/chars/char_%s_%d.png" % [Art.CHAR_NAMES[ci], Art.CHAR_PICKS[ci]])
		if ctex != null:
			ctr.texture = ctex
		cb.add_child(ctr)
		crow.add_child(cb)
		_char_btns.append(cb)
	var shint := _mk_label(sv, 14)
	shint.text = "再选一门技能 ——"
	shint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shint.modulate = Color(0.8, 0.78, 0.68)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	sv.add_child(srow)
	for i in Rules.ALL_SKILLS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(118, 138) if _touch else Vector2(104, 118)
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
	_skill_desc_label.text = "移到技能上查看说明；技能可与他人重复，各选各的"

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
		b.custom_minimum_size = Vector2(80, 132)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_swap_suit.bind(s))
		var bv := VBoxContainer.new()
		bv.set_anchors_preset(Control.PRESET_FULL_RECT)
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		bv.add_theme_constant_override("separation", 2)
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bv)
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(80, 120)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex: Texture2D = Art.card_tex(s)
		if tex != null:
			tr.texture = tex
		bv.add_child(tr)
		var tag := Label.new()
		tag.add_theme_font_size_override("font_size", 11)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(tag)
		wrow.add_child(b)
		_swap_suit_btns.append({"btn": b, "tex": tr, "tag": tag, "suit": s})
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
	_restart_button.pressed.connect(_on_restart)
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

	var banner_wrap := Control.new()
	banner_wrap.custom_minimum_size = Vector2(480, 150)
	var banner := TextureRect.new()
	var btex: Texture2D = Art.title_banner()
	if btex != null:
		banner.texture = btex
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner_wrap.add_child(banner)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 44)
	title.text = "绝　顶"
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.modulate = Color(1, 0.88, 0.55)
	banner_wrap.add_child(title)
	var bwc := CenterContainer.new()
	bwc.add_child(banner_wrap)
	v.add_child(bwc)
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

[b][color=#e8c08c]盘外招[/color][/b]　开局自选皮囊与技能（技能可与他人重复），全场公开：
金钟罩·免死一次　听劲·偷看上家一张　藏拙·读条造假　后发制人·冤枉我者多退一步　改弦·改路数　辨虚实·探一块石板"""
	v.add_child(rt)

	_intro_start_btn = Button.new()
	_intro_start_btn.text = "单机练习"
	_intro_start_btn.custom_minimum_size = Vector2(170, 50)
	_intro_start_btn.add_theme_font_size_override("font_size", 20)
	_intro_start_btn.pressed.connect(_on_intro_start)

	# 联机区：昵称 + 建房 / 房号加入
	var net_row := HBoxContainer.new()
	net_row.alignment = BoxContainer.ALIGNMENT_CENTER
	net_row.add_theme_constant_override("separation", 10)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "你的名号"
	_name_edit.max_length = 8
	_name_edit.custom_minimum_size = Vector2(140, 44)
	net_row.add_child(_name_edit)
	net_row.add_child(_intro_start_btn)
	var create_btn := Button.new()
	create_btn.text = "创建联机房"
	create_btn.custom_minimum_size = Vector2(150, 50)
	create_btn.add_theme_font_size_override("font_size", 20)
	create_btn.pressed.connect(_on_create_room)
	net_row.add_child(create_btn)
	_room_edit = LineEdit.new()
	_room_edit.placeholder_text = "六位房号"
	_room_edit.max_length = 6
	_room_edit.custom_minimum_size = Vector2(110, 44)
	net_row.add_child(_room_edit)
	var join_btn := Button.new()
	join_btn.text = "加入"
	join_btn.custom_minimum_size = Vector2(90, 50)
	join_btn.add_theme_font_size_override("font_size", 20)
	join_btn.pressed.connect(_on_join_room)
	net_row.add_child(join_btn)
	v.add_child(net_row)
	_menu_err = _mk_label(v, 14)
	_menu_err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_err.modulate = Color(1, 0.5, 0.4)

	_http = HTTPRequest.new()
	_http.timeout = 10.0        # Web 端曾出现请求悬挂：超时后可重试，而不是永久卡死
	add_child(_http)
	_http.request_completed.connect(_on_create_done)


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
	b.custom_minimum_size = Vector2(200, 68) if _touch else Vector2(150, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 24 if _touch else 20)
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


# 弹层弹出动画：只在 false→true 的上升沿播放（visible 由 _refresh 每帧写）
func _set_modal(n: Control, want: bool) -> void:
	if n.visible == want:
		return
	if want:
		n.visible = true
		n.pivot_offset = n.size / 2.0
		n.scale = Vector2(0.94, 0.94)
		n.modulate.a = 0.0
		var tw := n.create_tween().set_parallel(true)
		tw.tween_property(n, "scale", Vector2.ONE, 0.18) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(n, "modulate:a", 1.0, 0.14)
	else:
		n.visible = false
		n.scale = Vector2.ONE
		n.modulate.a = 1.0


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

	_build_panels(names.size(), 0)

	_log_event_text("开局：%d 人局，报门户选技能（15 秒）" % names.size())
	_refresh()


# ============================================================
# 驱动（逻辑与重构前一致）
# ============================================================

func _process(delta: float) -> void:
	if online and net != null:
		net.poll()
		_drain_net()
	if gs == null:
		return
	if _intro_modal.visible and not online:
		return          # 单机看玩法可暂停；联机服务端不等人
	if not _event_queue.is_empty():
		_event_elapsed += delta
		if _event_elapsed >= _delay_for(_event_queue[0]):
			_event_elapsed = 0.0
			var e: Dictionary = _event_queue.pop_front()
			_on_event_popped(e)
			_refresh()
		return

	_view = gs.view_for(my_id)
	_update_fake_timer(delta)

	if online:
		# 服务端驱动：本地只递减展示用倒计时
		_turn_time_left = maxf(_turn_time_left - delta, 0.0)
		_skill_pick_left = _turn_time_left
		if gs.phase == Rules.Phase.GAME_OVER:
			_show_game_over()
	else:
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
				_apply(Action.play(my_id, [idx]))


func _apply(a: Dictionary) -> void:
	var events: Array = gs.apply(a)
	if a.get("type", "") == "PLAY" and a.get("pid", -1) == my_id and not _has_type(events, "REJECTED"):
		_stat_human_plays += 1
	_apply_events(events)


func _apply_events(events: Array) -> void:
	if online:
		_event_queue.append_array(events)
		return
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
# 机器人看戏：亮招后当事机器人有概率发表情（真招得意冷笑 / 虚招被拆摇头）
func _maybe_bot_emote(e: Dictionary) -> void:
	var pid := int(e.pid)
	if pid < 0 or pid >= _view.players.size():
		return
	if not bool(_view.players[pid].is_bot):
		return
	if _ui_rng.randf() < 0.4:
		var emote := 0 if bool(e.honest) else 3    # 冷笑 / 摇头
		_apply(Action.emote(pid, emote))


func _react(pid: int, kind: String) -> void:
	var panel: Control = _my_panel if pid == my_id else _opp_panels.get(pid)
	if panel != null and panel.has_method("react"):
		panel.react(kind)


func _flash(col: Color, a: float) -> void:
	_flash_rect.color = Color(col.r, col.g, col.b, a)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.55)

func _punch(pid: int) -> void:
	var panel: Control = _my_panel if pid == my_id else _opp_panels.get(pid)
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
	_narration.modulate.a = 0.25
	var twn := _narration.create_tween()
	twn.tween_property(_narration, "modulate:a", 1.0, 0.22)

	match e.type:
		"ROUND_START":
			_reveal_cards = []
			_reveal_pid = -1
		"PLAYED":
			_react(int(e.pid), "play")
		"CHALLENGED":
			_react(int(e.by), "challenge")
			_react(int(e.target), "flinch")
		"HEAVEN_CHECK":
			_react(int(e.pid), "flinch")
		"REVEALED":
			_reveal_cards = e.cards.duplicate()
			_reveal_honest = e.honest
			_reveal_pid = e.pid
			if not online:
				_maybe_bot_emote(e)
		"RETREAT":
			_flash(Color(0.9, 0.1, 0.1), 0.22)
			_punch(int(e.pid))
			_react(int(e.pid), "retreat")
		"FALL":
			_flash(Color(0.75, 0.0, 0.0), 0.45)
			_punch(int(e.pid))
			var fp: Control = _my_panel if int(e.pid) == my_id else _opp_panels.get(int(e.pid))
			if fp != null and fp.has_method("shake"):
				fp.shake()
				fp.play_fall_anim()             # 逐帧挣扎 + 程序旋转跌落叠加
			_react(int(e.pid), "fall")
		"GOLDEN_BELL":
			_flash(Color(1.0, 0.82, 0.3), 0.35)
			_punch(int(e.pid))
			_react(int(e.pid), "bell")
			var bp: Control = _my_panel if int(e.pid) == my_id else _opp_panels.get(int(e.pid))
			if bp != null and bp.has_method("play_bell_fx"):
				bp.play_bell_fx()
		"HOUFA_TRIGGERED":
			_flash(Color(0.4, 0.5, 1.0), 0.25)
		"EMOTE":
			# 全场可见：事件由服务端广播给所有人；自己的面板也要弹（修：原来漏了自己）
			var ep: Control = _my_panel if int(e.pid) == my_id else _opp_panels.get(int(e.pid))
			if ep != null:
				ep.flash_emote(Rules.EMOTES[e.emote])
				if ep.has_method("play_emote_anim"):
					ep.play_emote_anim(int(e.emote))
		"SKILL_USED":
			# 私有结果提示（只有自己的视图里才有）
			if int(e.pid) == my_id:
				var v: Dictionary = gs.view_for(my_id)
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
		_apply(Action.play(my_id, indices))


func _on_challenge() -> void:
	_apply(Action.challenge(my_id))


func _on_skill() -> void:
	var you: Dictionary = _view.you
	match you.skill:
		Rules.Skill.TINGJIN:
			if _view.last_player_who_played != -1 and _view.last_played_count > 0:
				if _view.last_played_count == 1:
					_apply(Action.use_tingjin(my_id, 0))   # 只有一张，没得选
				else:
					_show_listen_modal()                    # 规则 §3.3②：挑一张看
		Rules.Skill.BIANXUSHI:
			_show_probe_modal()                             # 规则 §3.3⑥：任选未踏过的石板
		_:
			pass


func _on_pass_window() -> void:
	_apply(Action.pass_window())


func _on_swap_suit(s: int) -> void:
	_apply(Action.use_gaixian(my_id, s))


func _on_pick_char(ci: int) -> void:
	if gs != null and gs.phase == Rules.Phase.SKILL_PICK:
		_apply(Action.pick_char(my_id, ci))
		for i in _char_btns.size():
			_char_btns[i].modulate = Color(1, 0.85, 0.4) if i == ci else Color(1, 1, 1)
			_char_btns[i].scale = Vector2(1.06, 1.06) if i == ci else Vector2.ONE


func _on_pick_skill(s: int) -> void:
	if gs.phase == Rules.Phase.SKILL_PICK and _view.you.pending_skill_pick == Rules.Skill.NONE:
		_apply(Action.pick_skill(my_id, s))


func _on_skill_hover(s: int) -> void:
	_skill_desc_label.text = "%s：%s" % [Rules.SKILL_NAMES[s], SKILL_DESCS[s]]


func _on_emote(i: int) -> void:
	if _view.get("you", {}).get("alive", false):
		_apply(Action.emote(my_id, i))


func _on_selection_changed(indices: Array) -> void:
	var is_human_turn: bool = gs != null and gs.phase == Rules.Phase.PLAY \
		and int(_view.get("current_player", -1)) == my_id
	_play_button.disabled = not is_human_turn or indices.size() < 1 or indices.size() > Rules.MAX_PLAY_CARDS


# ============================================================
# 刷新
# ============================================================

func _refresh() -> void:
	if gs == null:
		return
	_view = gs.view_for(my_id)

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
			elif online:
				d["timer_frac"] = clampf(1.0 - _turn_time_left / _phase_limit(), 0.0, 1.0)
			elif d.is_bot:
				d["timer_frac"] = clampf(_bot_think_elapsed / maxf(_bot_think_time, 0.01), 0.0, 1.0)
			else:
				d["timer_frac"] = clampf(1.0 - _turn_time_left / Rules.PLAY_TIMEOUT_SEC, 0.0, 1.0)
			if i == my_id:
				d["own_timer"] = int(ceil(_turn_time_left))
		if i == my_id:
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
			# 逐张"翻牌"：横向 0→1 展开，错峰
			for i in _reveal_cards.size():
				var card := _mk_stage_card(Art.card_tex(_reveal_cards[i]), _reveal_cards[i])
				card.pivot_offset = Vector2(48, 72)
				card.scale = Vector2(0.0, 1.0)
				_stage_cards.add_child(card)
				var tw := card.create_tween()
				tw.tween_interval(0.13 * i)
				tw.tween_property(card, "scale", Vector2.ONE, 0.16) \
					.set_ease(Tween.EASE_OUT)
		elif _view.last_played_count > 0 and _view.last_player_who_played >= 0:
			# 牌背弹入：缩放 + 淡入错峰
			for i in _view.last_played_count:
				var back := _mk_stage_card(Art.card_back_tex(), -1)
				back.pivot_offset = Vector2(48, 72)
				back.scale = Vector2(0.55, 0.55)
				back.modulate.a = 0.0
				_stage_cards.add_child(back)
				var tw := back.create_tween().set_parallel(true)
				tw.tween_property(back, "scale", Vector2.ONE, 0.2) \
					.set_delay(0.06 * i).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				tw.tween_property(back, "modulate:a", 1.0, 0.15).set_delay(0.06 * i)

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
		and int(_view.current_player) == my_id and _view.you.hand.size() > 0
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
	if gs.phase != Rules.Phase.PLAY or int(_view.current_player) != my_id:
		_probe_modal.visible = false
		_listen_modal.visible = false
	var picking: bool = gs.phase == Rules.Phase.SKILL_PICK \
		and _view.you.pending_skill_pick == Rules.Skill.NONE and _view.you.alive
	_set_modal(_skill_modal, picking)
	if picking:
		_skill_pick_label.text = "报门户 —— 选一门技能（剩 %d 秒）" % int(maxf(_skill_pick_left, 0.0))
	var swap_open: bool = gs.phase == Rules.Phase.SWAP_WINDOW \
		and _view.you.alive and _view.you.skill == Rules.Skill.GAIXIAN and _view.you.skill_uses_left > 0
	_set_modal(_swap_modal, swap_open)
	if swap_open:
		for it in _swap_suit_btns:
			var is_cur: bool = int(it.suit) == int(_view.current_suit)
			it.btn.disabled = is_cur
			it.tex.modulate = Color(0.4, 0.4, 0.4) if is_cur else Color(1, 1, 1)
			it.tag.text = "（现路数）" if is_cur else ""

	if gs.phase == Rules.Phase.GAME_OVER:
		_set_modal(_over_modal, true)
		_game_over_label.text = "🏆 %s 独立绝顶！" % _names.get(int(gs.winner), "?")
		if online:
			var is_host: bool = net != null and not net.lobby.is_empty() \
				and int(net.lobby.get("host", -1)) == my_id
			_restart_button.text = "再来一局" if is_host else "等待房主再开"
			_restart_button.disabled = not is_host
		else:
			_restart_button.text = "再来一局"
			_restart_button.disabled = false


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


# ============================================================
# 联机（等待厅 / 网络泵）—— 规则草案 §11.2 客户端侧
# ============================================================

func _build_panels(n: int, me: int) -> void:
	for pid in _opp_panels:
		_opp_panels[pid].queue_free()
	_opp_panels = {}
	for i in n:
		if i == me:
			continue
		var panel = preload("res://ui/player_panel.gd").new()
		_opp_row.add_child(panel)
		_opp_panels[i] = panel


func _phase_limit() -> float:
	match int(gs.phase):
		Rules.Phase.SKILL_PICK: return Rules.SKILL_PICK_SEC
		Rules.Phase.SWAP_WINDOW: return Rules.SWAP_WINDOW_SEC
	return Rules.PLAY_TIMEOUT_SEC


func _player_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "侠客"


func _build_lobby() -> void:
	_lobby_modal = CenterContainer.new()
	_lobby_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby_modal.visible = false
	add_child(_lobby_modal)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat_style(Color(0.03, 0.04, 0.07, 0.95), 12, 30, 22))
	_lobby_modal.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)

	# 石匾 + 房号
	var plaque_wrap := Control.new()
	plaque_wrap.custom_minimum_size = Vector2(384, 144)
	var plaque := TextureRect.new()
	var ptex: Texture2D = Art.load_tex("res://assets/ui/plaque_room.png")
	if ptex != null:
		plaque.texture = ptex
	plaque.set_anchors_preset(Control.PRESET_FULL_RECT)
	plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plaque.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plaque_wrap.add_child(plaque)
	_lobby_code_label = Label.new()
	_lobby_code_label.add_theme_font_size_override("font_size", 44)
	_lobby_code_label.modulate = Color(1, 0.87, 0.55)
	_lobby_code_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plaque_wrap.add_child(_lobby_code_label)
	var pc := CenterContainer.new()
	pc.add_child(plaque_wrap)
	v.add_child(pc)
	var copy_btn := Button.new()
	copy_btn.text = "复制房号，发给朋友"
	copy_btn.focus_mode = Control.FOCUS_NONE
	copy_btn.pressed.connect(_copy_room_code)
	var cbc := CenterContainer.new()
	cbc.add_child(copy_btn)
	v.add_child(cbc)

	_lobby_seats_row = HBoxContainer.new()
	_lobby_seats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_lobby_seats_row.add_theme_constant_override("separation", 18)
	v.add_child(_lobby_seats_row)

	_lobby_status = _mk_label(v, 15)
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_status.modulate = Color(0.85, 0.82, 0.7)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 10)
	v.add_child(btns)
	_btn_addbot = Button.new()
	_btn_addbot.text = "＋机器人"
	_btn_addbot.pressed.connect(_send_add_bot)
	btns.add_child(_btn_addbot)
	_btn_rmbot = Button.new()
	_btn_rmbot.text = "－机器人"
	_btn_rmbot.pressed.connect(_send_remove_bot)
	btns.add_child(_btn_rmbot)
	_btn_start_online = Button.new()
	_btn_start_online.text = "开始对局"
	_btn_start_online.custom_minimum_size = Vector2(150, 46)
	_btn_start_online.add_theme_font_size_override("font_size", 20)
	_btn_start_online.pressed.connect(_send_start)
	btns.add_child(_btn_start_online)
	var leave := Button.new()
	leave.text = "离开"
	leave.pressed.connect(_leave_room)
	btns.add_child(leave)


func _on_create_room() -> void:
	_menu_err.text = "建房中…"
	var err := _http.request(NC.SERVER_HTTP + "/create", [], HTTPClient.METHOD_POST, "")
	if err != OK:
		_menu_err.text = "网络请求失败，请重试"


func _on_create_done(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		_menu_err.text = "建房失败（%d），请重试" % code
		return
	var m = JSON.parse_string(body.get_string_from_utf8())
	if m == null or not m.has("room"):
		_menu_err.text = "建房失败，请重试"
		return
	_connect_room(str(m.room))


func _on_join_room() -> void:
	var code := _room_edit.text.strip_edges()
	if not code.is_valid_int() or code.length() != 6:
		_menu_err.text = "房号是 6 位数字"
		return
	_connect_room(code)


func _connect_room(code: String) -> void:
	online = true
	_game_started_online = false
	_rgame = null
	net = NC.new()
	net.connect_room(code, _player_name())
	_menu_err.text = ""
	_intro_modal.visible = false
	_lobby_modal.visible = true
	_lobby_code_label.text = code
	_lobby_status.text = "连接中…"


func _leave_room() -> void:
	if net != null:
		net.close()
	net = null
	online = false
	gs = null
	_game_started_online = false
	_lobby_modal.visible = false
	_over_modal.visible = false
	for n2 in _hud_nodes:
		n2.visible = false
	_intro_modal.visible = true
	_refresh_intro_button()


func _on_restart() -> void:
	if online:
		if net != null:
			net.send({"t": "rematch"})
	else:
		_new_game()


func _show_menu_error(reason: String) -> void:
	match reason:
		"room_full": _menu_err.text = "房间已满（4 人）"
		"in_progress": _menu_err.text = "该房间对局已开始"
		"no_such_room": _menu_err.text = "房号不存在"
		_: _menu_err.text = "连接断开：" + reason


func _drain_net() -> void:
	if net == null:
		return
	if not net.connected and net.close_reason != "" and not _game_started_online:
		var reason: String = net.close_reason
		net = null
		online = false
		_lobby_modal.visible = false
		_intro_modal.visible = true
		_show_menu_error(reason)
		return
	while not net.inbox.is_empty():
		var m: Dictionary = net.inbox.pop_front()
		match str(m.get("t", "")):
			"lobby":
				if str(m.get("mode", "")) == "lobby" and _game_started_online:
					# 房主点了再来一局 → 全员回等待厅
					_game_started_online = false
					gs = null
					_over_modal.visible = false
					for n2 in _hud_nodes:
						n2.visible = false
					_lobby_modal.visible = true
				_refresh_lobby()
			"game":
				_on_net_game(m)
			"rejected":
				_narration.text = "⚠ 动作被拒绝：" + str(m.get("reason", ""))


func _on_net_game(m: Dictionary) -> void:
	if _rgame == null:
		_rgame = NC.RemoteGame.new(net)
	_rgame.update(m.view)
	if not _game_started_online:
		_game_started_online = true
		my_id = net.my_seat
		gs = _rgame
		_intro_modal.visible = false
		_lobby_modal.visible = false
		for n2 in _hud_nodes:
			n2.visible = true
		_event_log.clear()
		_names = {}
		for pl in m.view.players:
			_names[int(pl.id)] = str(pl.name)
		_build_panels(m.view.players.size(), my_id)
		_hand_snapshot = []
		_stage_sig = "!"
		_reveal_cards = []
		_narration.text = "群雄已至，对局开始——"
		_stat_start_ms = Time.get_ticks_msec()
	var dl := float(m.get("turn_deadline", 0))
	var nowms := float(m.get("server_now", 0))
	_turn_time_left = maxf((dl - nowms) / 1000.0, 0.0)
	var evs: Array = m.get("events", [])
	if not evs.is_empty():
		_apply_events(evs)


func _refresh_lobby() -> void:
	if net == null or net.lobby.is_empty():
		return
	var L: Dictionary = net.lobby
	_lobby_code_label.text = str(L.get("room", net.room))
	var seats: Array = L.get("seats", [])
	var is_host: bool = int(L.get("host", -1)) == net.my_seat
	var prev_count := _lobby_prev_seats
	_lobby_prev_seats = seats.size()
	for c in _lobby_seats_row.get_children():
		c.free()
	var cushion: Texture2D = Art.load_tex("res://assets/ui/seat_empty.png")
	for i in Rules.MAX_PLAYERS:
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 4)
		box.custom_minimum_size = Vector2(120, 0)
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(96, 128)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var nm := Label.new()
		nm.add_theme_font_size_override("font_size", 14)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i < seats.size():
			var st: Dictionary = seats[i]
			slot.texture = Art.char_tex(i)
			if i >= prev_count:
				# 新入座：从上方落下 + 弹跳（全场都会看到，lobby 广播驱动）
				slot.position.y = -34
				slot.modulate.a = 0.0
				var tw := slot.create_tween().set_parallel(true)
				tw.tween_property(slot, "position:y", 0.0, 0.3) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
				tw.tween_property(slot, "modulate:a", 1.0, 0.18)
			var tags := ""
			if int(L.get("host", -1)) == i:
				tags += "「房主」"
			if bool(st.get("is_bot", false)):
				tags += "〔机器人〕"
			elif not bool(st.get("connected", true)):
				tags += "〔离线〕"
			nm.text = str(st.get("name", "?")) + tags
			if int(st.get("seat", -1)) == net.my_seat:
				nm.modulate = Color(1, 0.87, 0.5)
		else:
			slot.texture = cushion
			slot.modulate = Color(0.75, 0.75, 0.8)
			nm.text = "虚位以待"
			nm.modulate = Color(0.6, 0.6, 0.6)
		box.add_child(slot)
		box.add_child(nm)
		_lobby_seats_row.add_child(box)
	_btn_addbot.visible = is_host and seats.size() < Rules.MAX_PLAYERS
	_btn_rmbot.visible = is_host and seats.any(func(x): return bool(x.get("is_bot", false)))
	_btn_start_online.visible = is_host
	_btn_start_online.disabled = not bool(L.get("can_start", false))
	if str(L.get("mode", "")) == "over":
		_lobby_status.text = "对局已结束"
	elif is_host:
		_lobby_status.text = "把房号发给朋友；人不够可以补机器人（至少 %d 人）" % Rules.MIN_PLAYERS if not bool(L.get("can_start", false)) else "人齐了，随时可以开始"
	else:
		_lobby_status.text = "等待房主开局…"


func _send_add_bot() -> void:
	if net != null:
		net.send({"t": "add_bot"})

func _send_remove_bot() -> void:
	if net != null:
		net.send({"t": "remove_bot"})

func _send_start() -> void:
	if net != null:
		net.send({"t": "start"})

func _copy_room_code() -> void:
	DisplayServer.clipboard_set(_lobby_code_label.text)


# ============================================================
# 技能目标选择弹层（辨虚实选石板 / 听劲选牌）
# ============================================================

func _build_skill_target_modals() -> void:
	# 辨虚实
	_probe_modal = CenterContainer.new()
	_probe_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_probe_modal.visible = false
	add_child(_probe_modal)
	var pp := PanelContainer.new()
	pp.add_theme_stylebox_override("panel", _flat_style(Color(0.04, 0.05, 0.08, 0.95), 12, 24, 18))
	_probe_modal.add_child(pp)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	pp.add_child(pv)
	var pt := _mk_label(pv, 20)
	pt.text = "辨虚实 —— 探查自己身后哪块石板？"
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ph := _mk_label(pv, 13)
	ph.text = "已踏过的不能选；结果只有你自己知道（×1）"
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.modulate = Color(0.8, 0.78, 0.68)
	_probe_row = HBoxContainer.new()
	_probe_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_probe_row.add_theme_constant_override("separation", 10)
	pv.add_child(_probe_row)
	var pcancel := Button.new()
	pcancel.text = "再想想"
	pcancel.focus_mode = Control.FOCUS_NONE
	pcancel.pressed.connect(func(): _probe_modal.visible = false)
	var pcc := CenterContainer.new()
	pcc.add_child(pcancel)
	pv.add_child(pcc)

	# 听劲
	_listen_modal = CenterContainer.new()
	_listen_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_listen_modal.visible = false
	add_child(_listen_modal)
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", _flat_style(Color(0.04, 0.05, 0.08, 0.95), 12, 24, 18))
	_listen_modal.add_child(lp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	lp.add_child(lv)
	var lt := _mk_label(lv, 20)
	lt.text = "听劲 —— 窥探上家哪一张？"
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lh := _mk_label(lv, 13)
	lh.text = "全场只知道你看了，不知道你看到什么"
	lh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lh.modulate = Color(0.8, 0.78, 0.68)
	_listen_row = HBoxContainer.new()
	_listen_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_listen_row.add_theme_constant_override("separation", 10)
	lv.add_child(_listen_row)
	var lcancel := Button.new()
	lcancel.text = "再想想"
	lcancel.focus_mode = Control.FOCUS_NONE
	lcancel.pressed.connect(func(): _listen_modal.visible = false)
	var lcc := CenterContainer.new()
	lcc.add_child(lcancel)
	lv.add_child(lcc)


func _show_probe_modal() -> void:
	for c in _probe_row.get_children():
		c.free()
	var stepped: int = _view.you.steps_taken
	var probed: Dictionary = _view.you.probe_result
	for st in range(1, Rules.STONES + 1):
		var b := Button.new()
		b.custom_minimum_size = Vector2(72, 84)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = st <= stepped or probed.has(str(st))
		b.pressed.connect(_on_probe_pick.bind(st))
		var bv := VBoxContainer.new()
		bv.set_anchors_preset(Control.PRESET_FULL_RECT)
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		bv.add_theme_constant_override("separation", 4)
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bv)
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(48, 32)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex: Texture2D = Art.stone_ok_tex()
		if tex != null:
			tr.texture = tex
		if b.disabled:
			tr.modulate = Color(0.4, 0.4, 0.4)
		var tc := CenterContainer.new()
		tc.add_child(tr)
		bv.add_child(tc)
		var nl := Label.new()
		var mark := ""
		if probed.has(str(st)):
			mark = "（虚!）" if bool(probed[str(st)]) else "（实）"
		elif st <= stepped:
			mark = "（已踏）"
		nl.text = "第%d块%s" % [st, mark]
		nl.add_theme_font_size_override("font_size", 12)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(nl)
		_probe_row.add_child(b)
	_set_modal(_probe_modal, true)


func _on_probe_pick(stone: int) -> void:
	_probe_modal.visible = false
	_apply(Action.use_bianxushi(my_id, stone))


func _show_listen_modal() -> void:
	for c in _listen_row.get_children():
		c.free()
	var back: Texture2D = Art.card_back_tex()
	for pos in _view.last_played_count:
		var b := Button.new()
		b.custom_minimum_size = Vector2(80, 130)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_listen_pick.bind(pos))
		var bv := VBoxContainer.new()
		bv.set_anchors_preset(Control.PRESET_FULL_RECT)
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		bv.add_theme_constant_override("separation", 4)
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bv)
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(64, 96)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if back != null:
			tr.texture = back
		var tc := CenterContainer.new()
		tc.add_child(tr)
		bv.add_child(tc)
		var nl := Label.new()
		nl.text = "第 %d 张" % (pos + 1)
		nl.add_theme_font_size_override("font_size", 12)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(nl)
		_listen_row.add_child(b)
	_set_modal(_listen_modal, true)


func _on_listen_pick(pos: int) -> void:
	_listen_modal.visible = false
	_apply(Action.use_tingjin(my_id, pos))


# ============================================================
# 手机竖屏提示（横屏优化的一部分：竖屏没法排开牌桌）
# ============================================================

var _orient_overlay: Control

func _build_orientation_overlay() -> void:
	_orient_overlay = Control.new()
	_orient_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_orient_overlay.visible = false
	_orient_overlay.z_index = 100
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_orient_overlay.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	_orient_overlay.add_child(v)
	var l := Label.new()
	l.text = "请把手机横过来\n\n绝顶之上，须得横刀立马"
	l.add_theme_font_size_override("font_size", 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	add_child(_orient_overlay)


func _check_orientation() -> void:
	if _orient_overlay == null:
		return
	var sz := get_viewport().get_visible_rect().size
	_orient_overlay.visible = _touch and sz.y > sz.x
