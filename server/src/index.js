// Worker 入口：建房 + 路由到房间 DO。
// 同码必同房（保证 1）：idFromName("room:" + 房号) —— 平台保证的确定性寻址。
import { Room } from "./room.js";
export { Room };

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

    if (url.pathname === "/create" && req.method === "POST") {
      // 六位房号；查占用避免撞进已开局的房（最多试 8 次）
      for (let i = 0; i < 8; i++) {
        const code = String(Math.floor(100000 + Math.random() * 900000));
        const stub = env.ROOM.get(env.ROOM.idFromName("room:" + code));
        const occ = await stub.fetch("https://do/occupancy?room=" + code).then(r => r.json());
        if (occ.seats === 0) return Response.json({ room: code }, { headers: CORS });
      }
      return Response.json({ error: "try_again" }, { status: 503, headers: CORS });
    }

    if (url.pathname === "/ws") {
      const code = url.searchParams.get("room") || "";
      if (!/^\d{6}$/.test(code))
        return Response.json({ error: "no_such_room" }, { status: 400, headers: CORS });
      const stub = env.ROOM.get(env.ROOM.idFromName("room:" + code));
      return stub.fetch(req);
    }

    if (url.pathname === "/health") return Response.json({ ok: true }, { headers: CORS });
    return new Response("绝顶 · game server", { headers: CORS });
  },
};
