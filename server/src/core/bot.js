// 机器人 —— core/bot.gd 的移植。只接收 viewFor(pid) 的裁剪视图（铁律 3 活体测试）。
import * as R from "./rules.js";

export function botDecide(view, rng) {
  const me = view.you;
  const legal = view.legal_actions;
  const has = t => legal.some(a => a.type === t);

  if (view.phase === R.Phase.SKILL_PICK)
    return { type: "PICK_SKILL", pid: me.id, skill: rng.randiRange(0, R.ALL_SKILLS.length - 1) };

  if (view.phase === R.Phase.SWAP_WINDOW) {
    if (rng.randf() < 0.5) {
      const options = R.PLAYABLE_SUITS.filter(s => s !== view.current_suit);
      return { type: "USE_GAIXIAN", pid: me.id, suit: options[rng.randiRange(0, options.length - 1)] };
    }
    return { type: "PASS_WINDOW" };
  }

  if (has("CHALLENGE")) {
    let p = 0.15;
    const cnt = view.last_played_count;
    if (cnt === 3) p += 0.25;
    else if (cnt === 2) p += 0.10;
    let mine = 0;
    for (const c of me.hand) if (c === view.current_suit || c === R.Suit.HUAJIN) mine++;
    if (mine >= 5) p += 0.30;
    if (me.steps_taken >= 3) p *= 0.40;
    const up = view.players[view.last_player_who_played];
    if (view.skills_enabled && up.skill === R.Skill.HOUFA && view.round_number >= up.houfa_ready_round)
      p *= 0.30;
    if (up.steps_taken >= 4) p += 0.15;
    if (rng.randf() < Math.min(p, 0.95)) return { type: "CHALLENGE", pid: me.id };
  }

  const truths = [];
  for (let i = 0; i < me.hand.length; i++)
    if (me.hand[i] === view.current_suit || me.hand[i] === R.Suit.HUAJIN) truths.push(i);
  if (truths.length >= 1) {
    const r = rng.randf();
    let n = r < 0.60 ? 1 : r < 0.90 ? 2 : 3;
    n = Math.min(n, truths.length);
    return { type: "PLAY", pid: me.id, indices: truths.slice(0, n) };
  }
  return { type: "PLAY", pid: me.id, indices: [rng.randiRange(0, me.hand.length - 1)] };
}
