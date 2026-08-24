// 内核移植验证：关键边界 + 300 局随机 + 视图机密 + 可复现性
import { test } from "node:test";
import assert from "node:assert/strict";
import * as R from "../src/core/rules.js";
import { Rng } from "../src/core/rng.js";
import { Game } from "../src/core/game.js";
import { botDecide } from "../src/core/bot.js";

const DAO = R.Suit.DAO, ZHANG = R.Suit.ZHANG;

function startPlay(n, seed) {
  const g = new Game(seed, true);
  g.newGame(Array.from({ length: n }, (_, i) => "P" + i), Array(n).fill(true));
  g.phase = R.Phase.PLAY;
  g.roundNumber = 5;
  g.currentSuit = DAO;
  g.currentPlayer = 0;
  g.roundStarter = 0;
  for (const p of g.players) { p.hand = [DAO, DAO, DAO, DAO, DAO]; p.hollowIndex = 6; }
  return g;
}
const has = (evs, t) => evs.some(e => e.type === t);
const find = (evs, t) => evs.find(e => e.type === t);

test("边界1: 首位不能拆招", () => {
  const g = startPlay(3, 1);
  assert.ok(!g.viewFor(0).legal_actions.some(a => a.type === "CHALLENGE"));
});

test("边界8/10: 豁口必坠；金钟罩+后发制人=1步金钟罩2步坠", () => {
  const g = startPlay(3, 10);
  g.players[0].skill = R.Skill.HOUFA; g.players[0].houfaReadyRound = 0;
  g.players[1].skill = R.Skill.JINZHONGZHAO;
  g.players[1].hollowIndex = 1; g.players[1].stepsTaken = 0;
  g.players[0].hand = [DAO];
  g.apply({ type: "PLAY", pid: 0, indices: [0] });
  const evs = g.apply({ type: "CHALLENGE", pid: 1 });
  assert.ok(has(evs, "GOLDEN_BELL"));
  assert.ok(has(evs, "FALL"));
  assert.equal(evs.filter(e => e.type === "RETREAT").length, 1);
});

test("边界21: 上家=最近真正出过招的人", () => {
  const g = startPlay(3, 21);
  g.players[1].hand = [];
  g.apply({ type: "PLAY", pid: 0, indices: [0] });
  assert.equal(g.currentPlayer, 2);           // P1 空手被跳过
  assert.equal(g.lastPlayerWhoPlayed, 0);
});

test("边界26(v0.9): 技能可重复，全员各取所愿", () => {
  const g = new Game(26, true);
  g.newGame(["a","b","c","d"], [true,true,true,true]);
  let evs = [];
  for (let i = 0; i < 4; i++) evs = evs.concat(g.apply({ type: "PICK_SKILL", pid: i, skill: R.Skill.JINZHONGZHAO }));
  for (const p of g.players) assert.equal(p.skill, R.Skill.JINZHONGZHAO);
  assert.equal(find(evs, "SKILLS_ASSIGNED").randomized.length, 0);
});

test("边界34(v0.9): 自由选皮囊可重复、全场可见、开局后锁定", () => {
  const g = new Game(340, true);
  g.newGame(["a","b","c"], [true,true,true]);
  g.apply({ type: "PICK_CHAR", pid: 0, char_id: 5 });
  g.apply({ type: "PICK_CHAR", pid: 1, char_id: 5 });
  assert.equal(g.players[0].charId, 5);
  assert.equal(g.players[1].charId, 5);
  assert.equal(g.viewFor(2).players[0].char_id, 5);
  const bad = g.apply({ type: "PICK_CHAR", pid: 0, char_id: 9 });
  assert.equal(bad[0].type, "REJECTED");
  for (let i = 0; i < 3; i++) g.apply({ type: "PICK_SKILL", pid: i, skill: i });
  const late = g.apply({ type: "PICK_CHAR", pid: 0, char_id: 1 });
  assert.equal(late[0].type, "REJECTED");
});

test("边界27: 冤枉人后由拆招者(退步者)开始下一轮", () => {
  const g = startPlay(3, 27);
  g.players[0].hand = [DAO];
  g.players[1].hollowIndex = 6;
  g.apply({ type: "PLAY", pid: 0, indices: [0] });
  g.apply({ type: "CHALLENGE", pid: 1 });
  assert.equal(g.roundStarter, 1);
});

test("边界29: 只有最近一手可拆，旧手进弃牌堆", () => {
  const g = startPlay(3, 29);
  g.apply({ type: "PLAY", pid: 0, indices: [0, 1] });
  g.apply({ type: "PLAY", pid: 1, indices: [0] });
  assert.equal(g.discardCount, 2);
  assert.equal(g.lastPlayedCards.length, 1);
});

test("边界30/机密: view 任何层级不含五机密", () => {
  const g = new Game(30, true);
  g.newGame(["a","b","c"], [true,true,true]);
  g.players[1].probeResult["3"] = true;
  g.players[1].listenResult["2"] = 0;
  for (let pid = 0; pid < 3; pid++) {
    const s = JSON.stringify(g.viewFor(pid));
    assert.ok(!s.includes("hollowIndex") && !s.includes("hollow_index"), "泄 hollow");
    assert.ok(!s.includes("lastPlayedCards") && !s.includes("last_played_cards"), "泄牌面");
    const v = g.viewFor(pid);
    for (const op of v.players) {
      assert.ok(!("hand" in op));
      assert.ok(!("probe_result" in op) && !("listen_result" in op));
    }
  }
});

test("边界33: 天道检验三分支", () => {
  // a. 虚招被拆穿
  let g = startPlay(3, 331);
  g.players[0].hand = [ZHANG, ZHANG];
  g.players[1].hand = []; g.players[2].hand = [];
  let evs = g.apply({ type: "PLAY", pid: 0, indices: [0] });
  assert.ok(has(evs, "HEAVEN_CHECK"));
  assert.equal(g.players[0].stepsTaken, 1);
  assert.ok(has(evs, "ROUND_END"));
  // b/c. 真招继续；真招出尽平安收轮
  g = startPlay(3, 332);
  g.players[0].hand = [DAO, DAO];
  g.players[1].hand = []; g.players[2].hand = [];
  evs = g.apply({ type: "PLAY", pid: 0, indices: [0] });
  assert.ok(has(evs, "HEAVEN_CHECK"));
  assert.equal(g.players[0].stepsTaken, 0);
  assert.ok(!has(evs, "ROUND_END"));
  assert.equal(g.currentPlayer, 0);
  evs = g.apply({ type: "PLAY", pid: 0, indices: [0] });
  assert.equal(find(evs, "ROUND_END").retreater, -1);
  // d. 不触发后发制人
  g = startPlay(3, 333);
  g.players[0].skill = R.Skill.HOUFA;
  g.players[0].hand = [ZHANG];
  g.players[1].hand = []; g.players[2].hand = [];
  evs = g.apply({ type: "PLAY", pid: 0, indices: [0] });
  assert.ok(!has(evs, "HOUFA_TRIGGERED"));
});

function runFullGame(seed, n) {
  const g = new Game(seed, true);
  g.newGame(Array.from({ length: n }, (_, i) => "P" + i), Array(n).fill(true));
  const rng = new Rng(seed ^ 0x9E3779B9);
  const events = [];
  let guard = 0;
  while (g.phase !== R.Phase.GAME_OVER && guard++ < 200000) {
    if (g.phase === R.Phase.SKILL_PICK) {
      for (const p of g.players)
        if (p.pendingSkillPick === R.Skill.NONE)
          events.push(...g.apply({ type: "PICK_SKILL", pid: p.id, skill: rng.randiRange(0, 5) }));
      continue;
    }
    if (g.phase === R.Phase.SWAP_WINDOW) {
      const holder = g.players.find(p => p.alive && p.skill === R.Skill.GAIXIAN && p.skillUsesLeft > 0);
      const act = holder ? botDecide(g.viewFor(holder.id), rng) : { type: "PASS_WINDOW" };
      events.push(...g.apply(holder && act.type !== "PASS_WINDOW" ? act : { type: "PASS_WINDOW" }));
      continue;
    }
    const pid = g.currentPlayer;
    events.push(...g.apply(botDecide(g.viewFor(pid), rng)));
  }
  return { g, events };
}

test("300 局全机器人：必终局、恰一胜者", () => {
  let totalRounds = 0;
  for (let seed = 1; seed <= 300; seed++) {
    const n = 2 + (seed % 3);
    const { g, events } = runFullGame(seed, n);
    assert.equal(g.phase, R.Phase.GAME_OVER, `seed ${seed} 未终局`);
    assert.equal(events.filter(e => e.type === "GAME_OVER").length, 1, `seed ${seed}`);
    assert.ok(g.winner >= 0 && g.winner < n);
    totalRounds += g.roundNumber;
  }
  console.log(`  平均轮数 ${(totalRounds / 300).toFixed(2)}`);
});

test("可复现：同 seed 事件序列完全一致", () => {
  const a = runFullGame(12345, 4);
  const b = runFullGame(12345, 4);
  assert.equal(JSON.stringify(a.events), JSON.stringify(b.events));
});

test("退步概率符合 §5（1/6→1/1，2 万采样）", () => {
  for (let step = 1; step <= 6; step++) {
    let died = 0, reached = 0;
    for (let s = 0; s < 20000; s++) {
      const g = new Game(s + step * 100000, false);
      g.newGame(["a","b"], [true,true]);
      const p = g.players[0];
      if (p.hollowIndex < step) continue;
      reached++;
      if (p.hollowIndex === step) died++;
    }
    const expect = 1 / (7 - step);
    const rate = died / reached;
    assert.ok(Math.abs(rate - expect) < 0.02, `第${step}步: ${rate.toFixed(3)} vs ${expect.toFixed(3)}`);
  }
});
