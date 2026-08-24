// 《绝顶》规则常量 —— 与 core/rules.gd 逐项对齐（v0.8：忠实复刻原版）
export const Suit = { DAO: 0, JIAN: 1, ZHANG: 2, HUAJIN: 3 };
export const SUIT_NAMES = ["刀", "剑", "掌", "化劲"];
export const PLAYABLE_SUITS = [0, 1, 2];

export const DECK_COUNTS = { 0: 6, 1: 6, 2: 6, 3: 2 };   // 共 20
export const DECK_SIZE = 20;
export const HAND_SIZE = 5;
export const MIN_PLAYERS = 2;
export const MAX_PLAYERS = 4;
export const STONES = 6;
export const MAX_PLAY_CARDS = 3;

export const Skill = {
  NONE: -1, JINZHONGZHAO: 0, TINGJIN: 1, CANGZHUO: 2, HOUFA: 3, GAIXIAN: 4, BIANXUSHI: 5,
};
export const ALL_SKILLS = [0, 1, 2, 3, 4, 5];
export const SKILL_NAMES = ["金钟罩", "听劲", "藏拙", "后发制人", "改弦", "辨虚实"];
export const UNLIMITED = -1;
export const SKILL_USES = { 0: 1, 1: 2, 2: UNLIMITED, 3: UNLIMITED, 4: 1, 5: 1 };
export const HOUFA_COOLDOWN_ROUNDS = 3;
export const HOUFA_TOTAL_STEPS = 2;

export const Phase = { SKILL_PICK: 0, SWAP_WINDOW: 1, PLAY: 2, REVEAL: 3, GAME_OVER: 4 };

// 服务端计时（毫秒）
export const PLAY_TIMEOUT_MS = 30000;
export const SKILL_PICK_MS = 15000;
export const SWAP_WINDOW_MS = 5000;
export const BOT_THINK_MIN_MS = 2500;
export const BOT_THINK_MAX_MS = 9000;

export const EMOTES = ["冷笑", "抱拳", "拂袖", "摇头", "抚须", "请"];

export function buildDeck() {
  const d = [];
  for (const suit of [Suit.DAO, Suit.JIAN, Suit.ZHANG, Suit.HUAJIN])
    for (let i = 0; i < DECK_COUNTS[suit]; i++) d.push(suit);
  return d;
}

export function isTruthful(card, declaredSuit) {
  return card === declaredSuit || card === Suit.HUAJIN;
}
