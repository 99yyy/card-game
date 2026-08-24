class_name NetClient
extends RefCounted

# 联机层：WebSocket 客户端 + RemoteGame（服务端视图的本地影子）。
# 铁律 3 的联机形态：客户端只拿得到服务端裁剪后的 view，别的什么都没有。

const SERVER_HTTP := "https://jueding-server.99yyy.workers.dev"
const SERVER_WS := "wss://jueding-server.99yyy.workers.dev"

var ws := WebSocketPeer.new()
var connected := false
var my_seat := -1
var token := ""
var room := ""
var lobby: Dictionary = {}          # 最近一次 lobby 广播
var inbox: Array = []               # 待处理消息（table.gd 每帧取走）
var close_reason := ""

static func save_token(room_code: String, tok: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://session.cfg")
	cfg.set_value("session", "room", room_code)
	cfg.set_value("session", "token", tok)
	cfg.save("user://session.cfg")

static func load_token(room_code: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		return ""
	if str(cfg.get_value("session", "room", "")) != room_code:
		return ""
	return str(cfg.get_value("session", "token", ""))

func connect_room(room_code: String, player_name: String) -> void:
	room = room_code
	var tok := load_token(room_code)     # 重连令牌（§11.2 保证 3）
	var url := "%s/ws?room=%s&name=%s&token=%s" % [
		SERVER_WS, room_code, player_name.uri_encode(), tok.uri_encode()]
	ws.connect_to_url(url)

func poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		connected = true
		while ws.get_available_packet_count() > 0:
			var txt := ws.get_packet().get_string_from_utf8()
			var m = JSON.parse_string(txt)
			if m == null:
				continue
			m = _intify(m)   # JSON 数字全是 float；协议里全是整数，统一转回
			match m.get("t", ""):
				"joined":
					my_seat = int(m.seat)
					token = str(m.token)
					save_token(room, token)
				"lobby":
					lobby = m
			inbox.append(m)
	elif st == WebSocketPeer.STATE_CLOSED:
		if connected or close_reason == "":
			close_reason = ws.get_close_reason()
			if close_reason == "":
				match ws.get_close_code():
					4001: close_reason = "in_progress"
					4002: close_reason = "room_full"
					_: close_reason = "closed"
		connected = false

# 递归把整数值的 float 转回 int（JSON 陷阱：1 会变成 1.0，
# 而 GDScript 字典里 1.0 和 1 是不同的键、match 也不相等）
static func _intify(v):
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) else v
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[_intify(k)] = _intify(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_intify(x))
			return a
	return v

func send(obj: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(obj))

func send_action(a: Dictionary) -> void:
	send({"t": "action", "action": a})

func close() -> void:
	ws.close()


# 服务端视图的本地影子 —— 对 table.gd 模仿 GameState 的只读表面
class RemoteGame:
	extends RefCounted
	var view: Dictionary = {}
	var phase: int = -1
	var current_player: int = -1
	var winner: int = -1
	var net: NetClient

	func _init(n: NetClient) -> void:
		net = n

	func update(v: Dictionary) -> void:
		view = v
		phase = int(v.get("phase", -1))
		current_player = int(v.get("current_player", -1))
		winner = int(v.get("winner", -1))

	func view_for(_pid: int) -> Dictionary:
		return view

	func apply(a: Dictionary) -> Array:
		net.send_action(a)      # 事件由服务端推回，本地不产生
		return []

	func force_resolve_skill_pick() -> Array:
		return []               # 服务端计时收尾，客户端无此职责
