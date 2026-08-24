class_name Action
extends RefCounted

# 动作构造。校验与推进在 GameState 里（§7.2 用同一份 _is_legal）。

static func pick_skill(pid: int, skill: int) -> Dictionary:
	return {"type": "PICK_SKILL", "pid": pid, "skill": skill}

static func use_gaixian(pid: int, suit: int) -> Dictionary:
	return {"type": "USE_GAIXIAN", "pid": pid, "suit": suit}

static func use_tingjin(pid: int, card_pos: int) -> Dictionary:
	return {"type": "USE_TINGJIN", "pid": pid, "card_pos": card_pos}

static func use_bianxushi(pid: int, stone: int) -> Dictionary:
	return {"type": "USE_BIANXUSHI", "pid": pid, "stone": stone}

static func play(pid: int, indices: Array) -> Dictionary:
	return {"type": "PLAY", "pid": pid, "indices": indices}

static func challenge(pid: int) -> Dictionary:
	return {"type": "CHALLENGE", "pid": pid}

static func emote(pid: int, emote: int) -> Dictionary:
	return {"type": "EMOTE", "pid": pid, "emote": emote}

# 驱动层推进 SWAP_WINDOW 的内部动作（§14）。不是玩家动作，不进 legal_actions。
static func pass_window() -> Dictionary:
	return {"type": "PASS_WINDOW"}
