# 《绝顶》美术资源清单 · PixelLab 执行规格

> **给执行者**：用 PixelLab MCP 生成本清单资源。**严格按批次顺序执行，每批之间有确认点。**
> 本文件规定每个资源的用途、尺寸、生成方式、提示词与验收标准。
> 产出统一放 `/Users/wangming/Desktop/godot-1/assets/` 下按 §7 的目录结构归档。

---

## 0. 预算护栏（先读这个）

1. **开工第一件事：`get_balance` 查余额并报告。** 每批开工前再查一次，报告消耗。
2. **先锁风格，再批量。** 每一类先出候选给用户确认，风格锁定后才批量。风格没锁就批量 = 烧额度，返工全责。
3. **P0 全部完成并验收后才允许碰 P1；P2 本轮禁止生成**（动画类，等真人局验证玩法后再做）。
4. **额度向颜值倾斜**：六张立绘 + 背景用最高质量档、允许多候选挑优（立绘首张 3 候选、其余 2 候选、背景 2 候选）；
   牌面/图标/石板/UI 走便宜档一次出多张挑。**省要省在小件上，立绘和背景不省。**
5. 同一资源同一提示词最多重试 2 次，仍不行换提示词思路并记录原因。
6. **"好看"是验收项不是加分项**：用户对立绘/背景不满意就重出，直到满意或额度预警（余额低于开工时 40% 时暂停请示）。

---

## 1. 全局风格（每个提示词都要带的基调）

> **美术总方针（用户明确要求）：颜值优先，越好看越好。**
> 所有角色一律俊美：男角俊逸潇洒，女角明艳绝色。不要粗豪路线（无壮汉/莽汉/糙脸），
> 宁可多花一次生成，也不接受"能用但不好看"。P0 每张立绘允许出多候选挑最好的一张。

- **像素风格**：高细节像素立绘（pixel art portrait, detailed），干净轮廓、柔和光影、发丝与衣袂有流动感；**不要**照片感、不要 3D 渲染感
- **题材基调**：中国武侠、水墨意境 + 仙侠气质，华山绝顶、云海、残阳
- **主色调**：石青 / 黛灰 / 云白 / 暮橙，角色各占一个高辨识主色（见 §2.1 色卡）
- **人物审美基准**：修长比例（约 1:2.6 头身以上）、清晰精致的五官、边缘打一圈**暮色轮廓光**（rim light, warm dusk backlight）——这一条是"好看"的最大杠杆，每张立绘提示词必带
- **通用英文提示词后缀**：
  `wuxia style, elegant, graceful, beautiful character design, flowing robes and hair, warm rim light, detailed pixel art, clean silhouette, transparent background`
- **版权红线**：任何提示词**不得**出现 Liar's Bar / 动物面具 / 金庸古龙人物与武功名。
  角色是原创江湖人，不指向任何已有 IP。

---

## 2. P0 批（换皮必需，本轮目标）

### 2.1 角色立绘 × 6（唯一允许用高质量档的资源，颜值最高优先级）

**用途**：选人界面 + 对局中玩家面板头像区。**正面站姿立绘**（规则 §16：不需要 8 方向）。
**尺寸**：160×256（宽×高）生成，透明底——比原定 128×192 加大一档，脸部细节撑得起"好看"。
UI 里缩放显示，Godot Filter=Off 缩小不糊。

**流程**：先生成 1 号「白衣剑客」出 **3 个候选**给用户挑 → 选中的那张锁风格 →
其余五张全部带它做风格参考（reference image / 同参数复用），每张出 2 候选挑优。
六张必须同一画风、同一头身比例、同一暮色轮廓光。

阵容：三男三女，全员俊美，每人一个高辨识主色（远看靠颜色和剪影认人）：

| # | 角色 | 主色 | 提示词要点（英文生成，附中文意图） |
|---|---|---|---|
| 1 | 白衣剑客（先做，锁风格） | 云白 | strikingly handsome young swordsman, long flowing black hair, pristine white robe, slender jian sword, serene confident gaze — 白衣胜雪、执剑而立的俊美剑客 |
| 2 | 红衣女侠 | 朱红 | stunningly beautiful swordswoman, crimson robe with gold trim, high ponytail with red ribbon, fierce elegant eyes — 红衣金纹、英气逼人的绝色女侠 |
| 3 | 玄衣夜客 | 玄黑 | elegant mysterious swordsman in black, silver hair, half-veiled face, moonlight-cold aura — 黑衣银发、冷峻神秘的夜行客 |
| 4 | 紫绡舞姬 | 藕紫 | graceful beautiful dancer-assassin, violet silk sleeves flowing like water, hidden blades, enchanting smile — 紫绡广袖、笑里藏刀的舞姬 |
| 5 | 青衫琴师 | 青碧 | refined handsome musician in azure scholar robe, guqin on back, gentle smile, jade hairpin — 青衫玉簪、背琴含笑的琴师 |
| 6 | 白纱医仙 | 月白+青 | ethereal beautiful healer, white gauze veil, pale green sash, herbs pouch, serene otherworldly beauty — 白纱轻覆、清冷出尘的医仙 |

**验收**：
- 用户看第一眼的反应必须是"好看"，达不到就换候选或重出，这是硬标准
- 六张并排是同一个游戏的人物；主色互不撞；深色背景上剪影清晰
- 五官在 UI 实际显示尺寸（约 96px 高）下仍精致可辨；无 IP 痕迹

### 2.2 招式牌 × 5（牌面 4 + 牌背 1）

**用途**：手牌区与亮招展示。**尺寸**：64×96，透明底（牌背可不透明）。
**风格**：统一的牌框 + 中央一个图案，图案要在 64px 宽内一眼可辨。先做「刀」锁牌框风格。

| 牌 | 中央图案提示词要点 |
|---|---|
| 刀 | single broad dao blade, edge highlight — 一柄厚背单刀 |
| 剑 | straight double-edged jian sword, vertical — 一柄竖置长剑 |
| 掌 | open palm print with faint qi ripple — 掌印带一圈气劲 |
| 化劲 | swirling taiji-like spiral of soft energy, gold accent — 金色柔劲漩涡（**不要画太极鱼图形本体**，用抽象漩涡） |
| 牌背 | dark card back, cloud pattern border, faint mountain silhouette — 云纹边框暗色牌背 |

**验收**：四张牌面在 UI 缩到 48px 宽时仍能瞬间分辨；配色与 §15.3 现有色块色相一致（刀红/剑蓝/掌绿/化劲金），方便玩家从色块版无缝过渡。

### 2.3 石板 × 2 态 + 豁口 × 1

**用途**：六格石板条（cliff_bar 换皮）。**尺寸**：单块 48×32，透明底。

| 资源 | 提示词要点 |
|---|---|
| 石板·完好 | weathered stone slab tile, top-down slight angle, moss edge — 青苔石板 |
| 石板·当前站位 | 同上 + subtle warm glow rim — 完好版加一圈暖光描边（也可程序叠加，若程序做则跳过） |
| 豁口 | broken gap in stone ledge, dark void below, cracked edges — 断裂豁口、下方深渊 |

**验收**：三态并排一眼可分；豁口在 32px 高下仍明显“是个洞”。

### 2.4 背景 × 1

**用途**：对局主背景。**尺寸**：1280×720（或 640×360 生成后 2x 邻近放大，更省额度且更像素味）。
**提示词要点**：mountain summit platform at dusk, sea of clouds below, distant peaks, lone pine tree,
warm sunset sky, wide empty stone platform in foreground for characters —
前景要留一条**空旷的平台横带**（下 1/3），人物和石板条要叠在上面，**中间不要有抢眼元素**。

**画质加码**：背景是"好看"的第二杠杆，允许出 2 候选挑优。提示词加：
`breathtaking, golden hour glow on cloud sea, soft light rays, painterly pixel art` —— 要云海被残阳染金的那种画面感。

**验收**：把 6 张立绘叠上去，人物轮廓不糊、轮廓光方向与背景光源一致；平台带无杂物；单独看背景本身就想截图。

### 2.5 技能图标 × 6

**用途**：头像旁常驻技能标识。**尺寸**：32×32，透明底。先做「金钟罩」锁风格。

| 技能 | 图案提示词要点 |
|---|---|
| 金钟罩 | golden bell dome shield — 金色钟形罩 |
| 听劲 | ear with sound ripple lines — 耳与声波 |
| 藏拙 | face half-hidden behind sleeve/fan — 袖掩半面 |
| 后发制人 | counter arrow bouncing back — 反弹回击箭头 |
| 改弦 | two crossed arrows swapping — 交换双箭头 |
| 辨虚实 | eye over cracked stone — 眼观石纹 |

**验收**：32px 下六个互不混淆；带 1px 深色描边保证在任何底色上可读。

### 2.6 UI 面板 × 3

**用途**：顶栏底板、操作区底板、通用按钮（常态/按下 2 态）。
**尺寸**：面板生成 9-patch 友好的 96×96 圆角石纹/木纹方块（Godot 里用 NinePatchRect 拉伸）；按钮 96×32 两态。
**提示词要点**：dark wooden plank panel with subtle stone corner, chinese lacquer feel — 深木纹+石角。

---

## 3. P1 批（P0 验收后才开工）

| 资源 | 规格 |
|---|---|
| 表情图标 × 6（冷笑/抱拳/拂袖/摇头/抚须/请） | 32×32 静态图标，风格同技能图标 |
| 立绘的「出局置灰/坠崖剪影」态 × 1 通用 | 可程序做（调色+下移），先试程序方案，不行再生成 |
| 选人界面立绘展示框 × 1 | 简约描金边框，衬托立绘，96×96 九宫格 |
| 标题字图「绝顶」× 1 | 256×128，书法感像素字，仅两个大字可以生成（不是字库） |
| 房间等待厅背景 × 1 | 复用对局背景加雾化即可，先试程序方案 |

---

## 4. P2 批（本轮禁止 —— 等真人局验证玩法之后）

退步后退动画 / 石板塌陷动画 / 坠崖动画 / 表情小动画 / 亮招翻牌动画 / 技能发动特效。
（规则 §16 动画优先级表对应的全部内容。v0.1 用 Godot Tween：位移、震屏、闪白就够。）

---

## 5. 字体（不用 PixelLab）

**中文像素字体不要生成**——中文几千字形，字库生成不适用于 CJK。
用开源**缝合像素字体（Fusion Pixel Font）**，OFL 1.1 协议可免费商用：
GitHub `TakWolf/fusion-pixel-font`，下载 `fusion-pixel-12px-proportional-zh_hans.otf`，
放 `assets/fonts/`，Godot 里设为主题默认字体，关闭字体抗锯齿保持像素感。

---

## 6. Godot 接入要求（生成完必须做）

1. 所有 PNG 导入设置：**Filter = Off**（Nearest），关 mipmap——否则像素糊掉。
2. `project.godot` 增加 `rendering/textures/canvas_textures/default_texture_filter=0`。
3. 替换点：`player_panel.gd` 头像区、`hand_panel.gd` 牌面、`cliff_bar.gd` 石板三态、
   `table.gd` 背景与面板。**只换贴图，不改任何逻辑；改完重跑全部测试仍须全绿。**
4. 色块渲染保留为 fallback：贴图加载失败时回退色块（一个 `if texture == null` 的事）。

---

## 7. 归档结构与命名

```
assets/
├── chars/      char_daoshi.png  char_sengren.png  char_nvxia.png
│               char_biaoshi.png char_shusheng.png char_manghan.png
├── cards/      card_dao.png card_jian.png card_zhang.png card_huajin.png card_back.png
├── stones/     stone_ok.png stone_current.png stone_gap.png
├── bg/         bg_summit.png
├── icons/      skill_jinzhongzhao.png skill_tingjin.png skill_cangzhuo.png
│               skill_houfa.png skill_gaixian.png skill_bianxushi.png
├── ui/         panel_dark.png btn_normal.png btn_pressed.png
└── fonts/      fusion-pixel-12px-proportional-zh_hans.otf
```

---

## 8. 交付报告要求

- 每批完成后报告：生成了什么、各用了几次生成额度、余额还剩多少
- P0 全部资源接入 Godot 后截一张对局全景图
- 未按提示词出图而改了思路的，逐条说明原因
