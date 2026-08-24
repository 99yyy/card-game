# 绝顶

> 华山之巅，群雄论招。诈与被诈，一步之间。

## 🎮 立即游玩

**[▶ 点这里直接玩（浏览器打开即玩，无需安装）](https://99yyy.github.io/card-game/)**

联机方法：输入名号 → 创建联机房 → 把石匾上的六位房号发给朋友 → 朋友输房号加入（2–4 人，人不够可补机器人）。

---

一款武侠题材的多人诈唬卡牌游戏。玩法骨架复刻《骗子酒馆》Liar's Deck 模式（规则 1:1），
叠加原创「盘外招」技能层（六选一、全场公开、可整体关闭）。

## 玩法一句话

每轮定路数（刀/剑/掌），轮流盖牌出招、可以撒谎；下家可"拆招"掀牌——撒谎者退一步，
冤枉人者也退一步。每人背后六块石板有一块是虚的，退到虚石坠崖出局，最后站着的人赢。

## 目录

| 路径 | 内容 |
|---|---|
| `core/` | 游戏内核（GDScript，纯逻辑无 UI，33 条边界规则全测试覆盖） |
| `ui/` | Godot 客户端（单机热座版：1 真人 + 3 机器人） |
| `server/` | Cloudflare Worker + Durable Object 联机服务（JS 内核移植版） |
| `tests/` | 内核测试套件（`--headless` 运行） |
| `assets/` | 像素美术（PixelLab 生成） |
| `docs/` | 规则草案（唯一规则权威）、实现规格 |

## 本地运行（单机版）

需要 [Godot 4.7](https://godotengine.org/)：

```bash
godot --path .
```

跑测试：

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

## 联机服务端

```bash
cd server
node --test test/        # 内核测试
npx wrangler dev --local # 本地起服
npx wrangler deploy      # 部署 Cloudflare
```

## 状态

- ✅ 单机热座版（完整规则 + 技能 + 演出）
- ✅ 联机服务端（Cloudflare Workers + Durable Objects，房间/等待厅/断线托管）
- ✅ Web 版已上线 [GitHub Pages](https://99yyy.github.io/card-game/)，联机全链路可玩

## 版权说明

玩法机制不受版权保护；题材使用公有领域素材（华山、真实武术流派术语）。
像素字体使用 [缝合像素字体](https://github.com/TakWolf/fusion-pixel-font)（OFL 1.1）。
