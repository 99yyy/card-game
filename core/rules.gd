class_name Rules
extends RefCounted

# ---------- 花色 ----------
enum Suit { DAO = 0, JIAN = 1, ZHANG = 2, HUAJIN = 3 }   # 刀 / 剑 / 掌 / 化劲(百搭)
const SUIT_NAMES := ["刀", "剑", "掌", "化劲", "心魔"]
const PLAYABLE_SUITS := [Suit.DAO, Suit.JIAN, Suit.ZHANG]   # 化劲不能当本轮路数

const DECK_COUNTS := { Suit.DAO: 6, Suit.JIAN: 6, Suit.ZHANG: 6, Suit.HUAJIN: 2 }  # 共 20，忠实复刻原版
const DECK_SIZE := 20
const HAND_SIZE := 5
const MIN_PLAYERS := 2   # 原版支持 2 人，天道检验（边界 33）保证 1v1 成立
const MAX_PLAYERS := 4   # 20 / 5，4 人局牌全发完，算牌精确（原版手感）
const STONES := 6
const MAX_PLAY_CARDS := 3

# ---------- 技能 ----------
enum Skill {
	NONE         = -1,
	JINZHONGZHAO =  0,   # 金钟罩   被动 1 次
	TINGJIN      =  1,   # 听劲     主动 2 次
	CANGZHUO     =  2,   # 藏拙     被动 常驻（纯视图层）
	HOUFA        =  3,   # 后发制人 被动 每 3 轮 1 次
	GAIXIAN      =  4,   # 改弦     主动 1 次
	BIANXUSHI    =  5,   # 辨虚实   主动 1 次
}
const ALL_SKILLS := [0, 1, 2, 3, 4, 5]
const SKILL_NAMES := ["金钟罩", "听劲", "藏拙", "后发制人", "改弦", "辨虚实"]
const UNLIMITED := -1
const SKILL_USES := {
	Skill.JINZHONGZHAO: 1,
	Skill.TINGJIN:      2,
	Skill.CANGZHUO:     UNLIMITED,
	Skill.HOUFA:        UNLIMITED,
	Skill.GAIXIAN:      1,
	Skill.BIANXUSHI:    1,
}
const HOUFA_COOLDOWN_ROUNDS := 3
const HOUFA_TOTAL_STEPS := 2        # 被后发制人反噬时，拆招者共退 2 步

# ---------- 阶段 ----------
enum Phase { SKILL_PICK = 0, SWAP_WINDOW = 1, PLAY = 2, REVEAL = 3, GAME_OVER = 4 }

# ---------- 时间（内核禁止引用，仅 UI 读，见铁律 5）----------
const PLAY_TIMEOUT_SEC   := 30.0
const SKILL_PICK_SEC     := 15.0
const SWAP_WINDOW_SEC    := 5.0
const CANGZHUO_FAKE_MIN  := 3.0
const CANGZHUO_FAKE_MAX  := 18.0
const BOT_THINK_MIN_SEC  := 1.5
const BOT_THINK_MAX_SEC  := 8.0

# ---------- 玩法模式（v1.0 多玩法）----------
enum Mode { LUNZHAO = 0, XINMO = 1, ANQI = 2, DIDU = 3 }
const MODE_NAMES := ["论招", "心魔", "暗器", "递毒"]
const MODE_DESCS := [
	"经典：盖牌虚报，拆招定生死",
	"论招变体：牌堆混入一张心魔——拆它者，连坐全场",
	"大话骰：暗器囊里藏几枚，牛皮越吹越大",
	"五毒：盖盒递毒，信、不信，还是转赠祸水？",
]

# 心魔（论招变体）：占用花色值 4，只能单出、永远为真
const SUIT_XINMO := 4

# 暗器（大话骰）
const DICE_START := 5                # 开局每人 5 枚
const DICE_FACE_NAMES := ["飞刀", "柳叶镖", "毒针", "铁蒺藜", "袖箭", "无影针"]
const DICE_WILD := 5                 # 无影针 = 百搭，不可被叫价
const DICE_BIDDABLE := [0, 1, 2, 3, 4]

# 递毒（五毒）
const POISON_NAMES := ["蛇", "蝎", "蜈蚣", "蟾蜍", "蜘蛛"]
const POISON_PER_KIND := 8           # 每种 8 张，共 40，全部发完
const POISON_DEATH := 4              # 同种集满 4 只毒发出局

# ---------- 表情 ----------
const EMOTES := ["冷笑", "抱拳", "拂袖", "摇头", "抚须", "请"]

# ---------- 工具 ----------
static func build_deck_xinmo() -> Array:
	# 心魔变体：6/6/6/化劲1/心魔1，仍 20 张
	var d := []
	for suit in [Suit.DAO, Suit.JIAN, Suit.ZHANG]:
		for i in 6:
			d.append(suit)
	d.append(Suit.HUAJIN)
	d.append(SUIT_XINMO)
	return d

static func build_deck() -> Array:
	var d := []
	# 按枚举固定顺序遍历，避免 Dictionary 键遍历顺序不稳定（坑 4）
	for suit in [Suit.DAO, Suit.JIAN, Suit.ZHANG, Suit.HUAJIN]:
		for i in DECK_COUNTS[suit]:
			d.append(suit)
	return d   # 长度必须 == DECK_SIZE

static func is_truthful(card: int, declared_suit: int) -> bool:
	return card == declared_suit or card == Suit.HUAJIN or card == SUIT_XINMO
