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
	return null

static func card_back_tex() -> Texture2D:
	return load_tex("res://assets/cards/card_back.png")

static func stone_ok_tex() -> Texture2D:
	return load_tex("res://assets/stones/stone_ok.png")

static func stone_current_tex() -> Texture2D:
	return load_tex("res://assets/stones/stone_current.png")

static func stone_gap_tex() -> Texture2D:
	return load_tex("res://assets/stones/stone_gap.png")

static func bg_tex() -> Texture2D:
	return load_tex("res://assets/bg/bg_summit_a.png")

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

static func panel_tex() -> Texture2D:
	return load_tex("res://assets/ui/panel_dark.png")

static func btn_normal_tex() -> Texture2D:
	return load_tex("res://assets/ui/btn_normal.png")

static func btn_pressed_tex() -> Texture2D:
	return load_tex("res://assets/ui/btn_pressed.png")
