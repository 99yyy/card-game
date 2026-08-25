class_name Art
extends RefCounted

# 贴图加载工具（清单 §6）：load() + null fallback。
# 所有 PNG 已按 §7 归档到 assets/，本类只做加载与角色/花色映射，不碰游戏逻辑。

# 角色名（对应 §2.1 阵容顺序：剑客/女侠/夜客/舞姬/琴师/医仙）
const CHAR_NAMES := ["jianke", "nvxia", "yeke", "wuji", "qinshi", "yixian"]

static func load_tex(path: String) -> Texture2D:
	var t = load(path)
	if t is Texture2D:
		return t
	return null

# 每个角色采用的候选编号（0..3）。全队走动态姿势路线，坐姿/纯站桩候选不选，
# 避免横排站位时一坐一站不协调。用户可随时改这一行换候选。
const CHAR_PICKS := [3, 3, 1, 0, 3, 3]

# 座位 id → 角色立绘（其余候选保留供后续选人界面）
static func char_tex(pid: int) -> Texture2D:
	var idx: int = posmod(pid, CHAR_NAMES.size())
	return load_tex("res://assets/chars/char_%s_%d.png" % [CHAR_NAMES[idx], CHAR_PICKS[idx]])

# 座位 id → 待机动画帧序列（0=原图 + 8 帧生成）。没有动画资产时回退单帧静态图。
static var _frame_cache := {}
static func char_frames(pid: int) -> Array:
	var idx: int = posmod(pid, CHAR_NAMES.size())
	if _frame_cache.has(idx):
		return _frame_cache[idx]
	var frames: Array = []
	for i in 9:
		var t := load_tex("res://assets/chars/anim/%s_idle_%d.png" % [CHAR_NAMES[idx], i])
		if t == null:
			break
		frames.append(t)
	if frames.is_empty():
		var st := char_tex(pid)
		if st != null:
			frames.append(st)
	_frame_cache[idx] = frames
	return frames

# 表情动画帧（7 帧：0 原图 + 6 生成）；无资产返回空数组
static var _emote_cache := {}
static func emote_frames(pid: int, emote: int) -> Array:
	var idx: int = posmod(pid, CHAR_NAMES.size())
	var key := "%d_%d" % [idx, emote]
	if _emote_cache.has(key):
		return _emote_cache[key]
	var frames: Array = []
	for i in 7:
		var t := load_tex("res://assets/chars/emote/%s_e%d_%d.png" % [CHAR_NAMES[idx], emote, i])
		if t == null:
			break
		frames.append(t)
	_emote_cache[key] = frames
	return frames

# 坠崖帧（9 帧）
static var _fall_cache := {}
static func fall_frames(pid: int) -> Array:
	var idx: int = posmod(pid, CHAR_NAMES.size())
	if _fall_cache.has(idx):
		return _fall_cache[idx]
	var frames: Array = []
	for i in 9:
		var t := load_tex("res://assets/chars/fall/%s_fall_%d.png" % [CHAR_NAMES[idx], i])
		if t == null:
			break
		frames.append(t)
	_fall_cache[idx] = frames
	return frames

# 金钟罩护体特效帧（9 帧）
static var _bell_cache: Array = []
static func bell_frames() -> Array:
	if not _bell_cache.is_empty():
		return _bell_cache
	for i in 9:
		var t := load_tex("res://assets/fx/bell_%d.png" % i)
		if t == null:
			break
		_bell_cache.append(t)
	return _bell_cache

static func title_banner() -> Texture2D:
	return load_tex("res://assets/ui/title_banner.png")

static func card_tex(suit: int) -> Texture2D:
	match suit:
		Rules.Suit.DAO: return load_tex("res://assets/cards/card_dao.png")
		Rules.Suit.JIAN: return load_tex("res://assets/cards/card_jian.png")
		Rules.Suit.ZHANG: return load_tex("res://assets/cards/card_zhang.png")
		Rules.Suit.HUAJIN: return load_tex("res://assets/cards/card_huajin.png")
		Rules.SUIT_XINMO: return xinmo_tex()
	return null

static func card_back_tex() -> Texture2D:
	return load_tex("res://assets/cards/card_back.png")

# 花色角标颜色（与顶栏路数配色一致）
static func suit_color(suit: int) -> Color:
	match suit:
		Rules.Suit.DAO: return Color(1.0, 0.62, 0.52)
		Rules.Suit.JIAN: return Color(0.62, 0.8, 1.0)
		Rules.Suit.ZHANG: return Color(0.6, 1.0, 0.72)
		Rules.SUIT_XINMO: return Color(0.85, 0.6, 1.0)
	return Color(1.0, 0.88, 0.55)   # 化劲

# 卡面左上角的花色汉字角标。刀/剑卡面同为剑形兵器容易认错（用户实测反馈），
# 文字通道做冗余辨识，色弱玩家也稳。suit 越界返回 null。
static func suit_chip(suit: int) -> Control:
	if suit < 0 or suit >= Rules.SUIT_NAMES.size():
		return null
	var col := suit_color(suit)
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.05, 0.78)
	sb.border_color = Color(col.r, col.g, col.b, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", sb)
	chip.position = Vector2(5, 5)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = Rules.SUIT_NAMES[suit].substr(0, 1)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col)
	chip.add_child(l)
	return chip

static func stone_ok_tex() -> Texture2D:
	return load_tex("res://assets/stones/stone_ok.png")

static func stone_current_tex() -> Texture2D:
	return load_tex("res://assets/stones/stone_current.png")

static func stone_gap_tex() -> Texture2D:
	return load_tex("res://assets/stones/stone_gap.png")

# 背景按玩法切换：论招用华山余晖，心魔紫雾夜、暗器暮色、递毒绿瘴各一张
static func bg_tex(mode: int = 0) -> Texture2D:
	var path := "res://assets/bg/bg_summit_a.png"
	match mode:
		Rules.Mode.XINMO: path = "res://assets/bg/bg_xinmo.png"
		Rules.Mode.ANQI: path = "res://assets/bg/bg_anqi.png"
		Rules.Mode.DIDU: path = "res://assets/bg/bg_didu.png"
	var t := load_tex(path)
	if t == null:
		t = load_tex("res://assets/bg/bg_summit_a.png")
	return t

static func skill_icon_tex(skill: int) -> Texture2D:
	var name := ""
	match skill:
		Rules.Skill.JINZHONGZHAO: name = "jinzhongzhao"
		Rules.Skill.TINGJIN: name = "tingjin"
		Rules.Skill.CANGZHUO: name = "cangzhuo"
		Rules.Skill.HOUFA: name = "houfa"
		Rules.Skill.GAIXIAN: name = "gaixian"
		Rules.Skill.BIANXUSHI: name = "bianxushi"
		_: return null
	return load_tex("res://assets/icons/skill_%s.png" % name)

# ---------- 多玩法资产 ----------
static func xinmo_tex() -> Texture2D:
	return load_tex("res://assets/cards/card_xinmo.png")

static func poison_tex(kind: int) -> Texture2D:
	return load_tex("res://assets/cards/poison_%d.png" % kind)

static func poison_texes() -> Array:
	var out := []
	for k in 5:
		out.append(poison_tex(k))
	return out

static func poison_box_tex() -> Texture2D:
	return load_tex("res://assets/cards/poison_box.png")

static func dice_tex(face: int) -> Texture2D:
	return load_tex("res://assets/icons/dice_%d.png" % face)

# 玩法模式图标（顺序对应 Rules.Mode：论招/心魔/暗器/递毒）
const MODE_ICON_NAMES := ["lunzhao", "xinmo", "anqi", "didu"]
static func mode_icon_tex(mode: int) -> Texture2D:
	if mode < 0 or mode >= MODE_ICON_NAMES.size():
		return null
	return load_tex("res://assets/icons/mode_%s.png" % MODE_ICON_NAMES[mode])

# 暗器模式：骰盅
static func dice_cup_tex() -> Texture2D:
	return load_tex("res://assets/icons/dice_cup.png")

# 结算弹层的登顶画
static func victory_tex() -> Texture2D:
	return load_tex("res://assets/ui/victory_art.png")

static func panel_tex() -> Texture2D:
	return load_tex("res://assets/ui/panel_dark.png")

static func btn_normal_tex() -> Texture2D:
	return load_tex("res://assets/ui/btn_normal.png")

static func btn_pressed_tex() -> Texture2D:
	return load_tex("res://assets/ui/btn_pressed.png")
