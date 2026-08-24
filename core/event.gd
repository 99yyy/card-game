class_name Event
extends RefCounted

# 事件构造。UI 只能靠事件播动画（§8）。

static func skills_assigned(assignments: Dictionary, randomized: Array) -> Dictionary:
	return {"type": "SKILLS_ASSIGNED", "assignments": assignments, "randomized": randomized}

static func round_start(r: int, suit: int, starter: int) -> Dictionary:
	return {"type": "ROUND_START", "round": r, "suit": suit, "starter": starter}

static func dealt(counts: Dictionary) -> Dictionary:
	return {"type": "DEALT", "counts": counts}

static func suit_changed(by: int, frm: int, to: int) -> Dictionary:
	return {"type": "SUIT_CHANGED", "by": by, "from": frm, "to": to}

static func played(pid: int, count: int) -> Dictionary:
	return {"type": "PLAYED", "pid": pid, "count": count}

static func skill_used(pid: int, skill: int) -> Dictionary:
	return {"type": "SKILL_USED", "pid": pid, "skill": skill}

static func skipped(pid: int, reason: String) -> Dictionary:
	return {"type": "SKIPPED", "pid": pid, "reason": reason}

static func challenged(by: int, target: int) -> Dictionary:
	return {"type": "CHALLENGED", "by": by, "target": target}

static func revealed(pid: int, cards: Array, suit: int, honest: bool) -> Dictionary:
	return {"type": "REVEALED", "pid": pid, "cards": cards, "suit": suit, "honest": honest}

# 天道检验（边界 33，对应原版"唯一持牌者的牌自动亮开"）
static func heaven_check(pid: int) -> Dictionary:
	return {"type": "HEAVEN_CHECK", "pid": pid}

static func houfa_triggered(pid: int, victim: int) -> Dictionary:
	return {"type": "HOUFA_TRIGGERED", "pid": pid, "victim": victim}

static func retreat(pid: int, from_step: int, to_step: int) -> Dictionary:
	return {"type": "RETREAT", "pid": pid, "from_step": from_step, "to_step": to_step}

static func golden_bell(pid: int) -> Dictionary:
	return {"type": "GOLDEN_BELL", "pid": pid}

static func fall(pid: int) -> Dictionary:
	return {"type": "FALL", "pid": pid}

static func round_end(retreater: int) -> Dictionary:
	return {"type": "ROUND_END", "retreater": retreater}

static func game_over(winner: int) -> Dictionary:
	return {"type": "GAME_OVER", "winner": winner}

static func emote(pid: int, emote: int) -> Dictionary:
	return {"type": "EMOTE", "pid": pid, "emote": emote}
