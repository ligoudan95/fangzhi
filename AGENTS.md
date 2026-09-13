# AGENTS.md — fangzhi 项目 AI 开发约定

> 《莽荒兽契》——中国古代玄幻捉宠放置游戏。TapTap 竖屏买断单机（九项决策见 `docs/01` §19，已定稿）。
> 客户端 **Godot 4.7.1**（GDScript，锁 minor 版本，docs/13）；`src/` 下 TS headless 引擎保留为**数值验收基准**，与 Godot 版做同种子对拍。

## 铁律（违反即返工）

1. **分层单向依赖**：`res://scripts/` 下 `infra → config → battle → logic → view`，只能向下引用
2. **Autoload 只 4 个**：`Config`、`Save`、`Event`、`Audio`（docs/13 §3）；不通过 `/root/节点名` 查找业务节点
3. **battle/ 与 logic/ 纯逻辑**：RefCounted，禁止 import Node/SceneTree/渲染——必须能 `--headless` 跑测试与数值模拟
4. **View 零业务逻辑**：状态由 Logic 推送；`battle.tscn` 只消费战斗事件队列 `Array[Dictionary]`
5. **所有数值走表**：`tables/*.csv → npm run export → out/config/*.json → 构建拷贝 → resources/config/`；禁止硬编码数值、禁止在编辑器手改 .tres 数值（docs/12 §11 红线）
6. **表结构变更走程序评审**；数据行增删策划自决；改表后 `npm run export` 必须全绿
7. **战斗引擎确定性**：同种子同输入必同结果；随机统一走 seeded RNG（mulberry32）；任何 battle/ 改动必须过确定性测试，并与 TS 基准同种子对拍一致——**确定性/对拍测试失败 = 阻塞级**
8. **随机流独立**：战斗/掉落/资质 roll 各自独立种子流；UI 演出、日志、调试查询不得消耗正式随机流
9. **存档只存实例**：ID、等级、roll 种子；不快照配置；`user://save/` JSON + 迁移链 + 原子写（docs/07 §4）
10. **美术表现定稿**：不使用 Spine/骨骼动画或对应插件；只用静态贴图、Tween、少量拆件、受限序列帧与粒子，并遵守同屏/帧数/图集预算（docs/10 §3/§11）

## 文档引用规则

- `docs/01-15` 是**设计规则与实现合同来源**（01-13 系统设计、14 台账、15 离线/存档合同）；`docs/16-24` 是**产品与流程档案**（FTUE/UX/经济/QA/合规/内容/设置/运营），各文档版本见 `docs/14 §2`；`docs/14` 只记录风险、完成度和证据，不改写设计规则
- 设计冲突时以 `docs/01` §19 九项决策为准；发现文档间矛盾 → 标出交用户裁决，不自选
- 引用格式：`docs/NN §章节`（例：`docs/13 §6 对拍机制`）

## 命名与代码规范

- 文件 `snake_case.gd` / `snake_case.ts`；类 `PascalCase`；每文件单类；信号命名 `on_事件`；常量全大写下划线
- **全类型标注**（battle/logic 层零无类型变量）
- **注释简体中文**：类顶职责概述 + 复杂逻辑简注，自解释不注；模块头 `## doc: NN-文档名 §x` 标注来源
- `class_name` 禁用 Godot 原生类名
- 配置 JSON 加载后只读；TS 侧沿用 `src/` 现有风格
- PowerShell 脚本一律 ASCII（PS 5.1 无 BOM UTF-8 按 ANSI 读）

## 常用命令

```bash
# ---- TS 数值基准 ----
npm run export     # 导表：tables/*.csv → 校验 → out/config/*.json + types.d.ts + report.md
npm test           # 15 项数值验收测试（战力锚点/伤害/捕捉/确定性/冒烟）
npm run demo       # 演示：关卡战斗 + 捕捉样例 + 战力表
npm run sync:godot # 导表 + 回填 resources/config/（改表后必跑）
npm run parity     # 导表 + 回填 + 生成 TS 对拍期望日志（out/parity/expected/）

# ---- 一键检查（TS 导表+测试 + dep_check + gdformat + gdlint + GdUnit4；缺工具自动跳过）----
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check_all.ps1

# ---- 分层依赖方向检查（单独跑）----
powershell -NoProfile -ExecutionPolicy Bypass -File tools\dep_check.ps1

# ---- 格式化检查与修复（需 pip install "gdtoolkit==4.*" 或 uvx）----
uvx --from "gdtoolkit==4.*" gdformat --check scripts tests
uvx --from "gdtoolkit==4.*" gdlint scripts tests
```

环境要点：

- Node.js ≥ 23.6（原生 TS 直跑，零依赖）
- GdUnit4 / Godot 命令行：需 `GODOT_BIN` 环境变量或 PATH 中的 godot；本机编辑器在仓库同级 `Godot_v4.7.1-stable_win64.exe/` 目录（check_all 自动探测）
- **godot-ai MCP**（`.zcode/config.json` 已配）：编辑器打开本工程后，AI 可经 MCP 驱动编辑器（跑测试/读控制台/操作场景树）。`.tscn` 修改优先走 MCP
- 本机直连 GitHub 超时，代理 `127.0.0.1:7897` 可用

## 测试策略（docs/13 §12）

| 层 | 手段 | 说明 |
|---|---|---|
| TS 数值基准 | `npm test`（15 项） | 战力锚点 ±15%、伤害管线、捕捉蒙特卡洛、确定性、冒烟——**改数值/公式必跑** |
| GDScript 单测 | GdUnit4（`tests/`，`GdUnitCmdTool.gd` 入口） | TS 断言口径逐项平移；battle/logic 层必单测 |
| 引擎对拍 | `npm run parity` + `tests/parity_runner.gd`（种子清单 `tools/parity/seeds.json`，100 种子 × 9 场景逐行 diff） | TS 与 GDScript 同种子跑，任何不一致 = 移植 bug；check_all 第 7 步强制 |
| 数值验收 | `npm run export` → `out/report.md` | 平衡报表 V-401 全过 |
| View/UI | 人工试玩 | 竖屏 1080×1920、上下 80px SafeArea、异形屏、动态减弱与性能预算（docs/10 §12） |

## 目录结构速查

```
docs/            设计规则 01-15 + 台账 14 + 产品流程档案 16-24
tables/          策划数据源 CSV（.gdignore：引擎不可直接读）
tools/export/    导表工具    tools/dep_check.ps1 check_all.ps1 检查脚本
src/battle/      TS 确定性战斗引擎（数值验收基准，勿退役）
tests/           TS 数值测试 + GdUnit4 GDScript 测试（D3 起）
scripts/         GDScript：infra/ config/ battle/ logic/ view/（D1-2 起）
scenes/          .tscn 场景（main / battle / ui）
resources/       config/（导表产物拷贝，勿手改） themes/
addons/          gdUnit4 / godot_ai
out/             导出产物（gitignore）
.zcode/          子代理五角色 + team-lead 命令 + hooks + memory
```

## 工作流

多角色管线用 `/team-lead` 启动：planner（策划案）→ architect（程序方案）→ programmer（编码+自查）→ docs-updater（文档同步）→ git-admin（提交）；每步等用户审核。方案已定位的单点修复可走轻量路径直接 @programmer。

提交格式：里程碑 `P<阶段>-<任务>: 描述 (docs/NN §x)`，例 `P0-D6: battle 移植 mulberry32 与伤害公式 (docs/13 §13)`；杂项 `fix:`/`chore:`/`docs:` 前缀。

## 当前状态（随进度更新）

- **风险整改 M0-M6 第一阶段完成（2026-09-12）**：M0 口径治理 + 台账、M1 战斗缺陷修复、M2 导表/CI 门禁、M3 装备掉落闭环、M4 存档/时间底层、M5 产品档案 docs/16-24、M6 演出第一阶段（结构化事件 + 2×3 站位 + SafeArea + AAB + Audio 最小实装 + 设置页 docs/23）
- **P1-P6 MVP 包完成（2026-09-13）**：灵宠个体化（资质/性格/突破）、村落场景+派遣、内容扩量（3 域 18 关/4 章 32 节点）、装备强化+套装、图鉴收集+幸运、经济模拟器；`check_all` 全绿
- **Phase B 村落经营收口（2026-09-13，docs/26 §4 全项）**：建筑效果 effectKind 1-4 全消费（田位/矿位/生产队列/仓库倍率/图腾离线上限/议事堂门）+ 配方生产（锻造/药庐）+ 矿场开采 + 派遣体力心情离线恢复；修复 GD lambda 按值捕获致矿场产出丢失 bug；对拍扩至 **9 场景**（`[farm]/[mine]/[beast]/[recipe]/[build]`）；115 项 GdUnit / 87 项 TS
- **config_types/fields.md 生成链验收关闭（2026-09-13）**：幂等零漂移 + CI 漂移阻断 + 加载/schema 测试全绿（R-P1-06）
- **实机画面验证批次（2026-09-13）**：浮层互斥/页签与弹窗视觉规范（岩彩暖色+金边）/全局 9:16 窗口适配（window_fit，最大化转最大 9:16）/战斗站位居中修复/伤害数字错层；引擎截帧 + 视觉模型复核闭环（tools/dev/ui_flow_capture.gd 等探针）
- **养成→战力闭环打通（2026-09-13，四包连续）**：①灵宠上阵与成长（party/收服自动入队/修为喂养/等级帽=突破门槛/突破激活/真实资质+性格入战斗）②装备穿戴与战力管线（穿戴/强化+持久化掉落流 roll/主属性+词条×强化倍率/套装 2+3 件叠加/statMods+natureMods 双通道）③离线开屏结算报告（elapsed 补结算+存档+领取面板+pendingReports 审计）④派遣完整链（矿层绑宠/效率快照乘算/派遣扣体力与休息分流）；桌面性能探针 169.9fps（perf_probe.gd，远超 ≥55fps 档）；139 项 GdUnit / 95 项 TS / 100 种子 × 9 场景全绿
- **进度骨干修复（2026-09-13 包A）**：玩家境界系统（docs/02 §2.2 公式落 GlobalConst，realm_progress 双端；修为扣减推进/十境封顶）+ unlockRealm 三门禁（建筑/配方/矿层）+ 借兽补位（阵伍不足 3 演示兽补空位，修捕捉后单宠卡死）+ 捕捉野性等级跟随敌方 + **修复存档 generation 死锁**（已有档开新游戏 force 覆盖）+ FTUE 全程自动回归测试（ftue_progression_test：捕捉→补位队 10/10 胜 stage2→门禁→凝血解锁全链）；144 GdUnit / 99 TS / 100×9 全绿
- **战斗套装机制 + 体验打磨（2026-09-13 包B/C）**：套装特殊机制 10 键全接入引擎（dmg_first/dmg_fire/dmg_frozen/detonate_splash/cd_reduce/rage_crit/rage_double/heal/shield_heal/freeze_chance，双端镜像；对拍扩至 **10 场景**）；自动保存（战斗结束/离线领取/喂养/突破落档 auto 槽）+ ESC 轻量返回栈（顶层弹窗逐层关闭、战斗中跳过演出）；150 GdUnit / 99 TS 全绿
- **数值待拍板清单**：灵宠喂养成本（PET_FEED_XIU_*，临时 50/10）、强化失败惩罚（现仅耗材料不掉级）、城防 effectKind 5 战斗公式、修炼/巡猎结算器是否入阶段
- **占位声明**：战斗立绘为元素色块占位，正式美术/音频资产为外部交付门禁（docs/14）
- **剩余阻塞**：真机竖屏验收（唯一剩余人工项，需推送后取新 CI run 的 APK artifact）；城防（effectKind 5）战斗消费待 docs/05 §9 数值细则
- **D13-14 部分完成**：Android APK + AAB preset 与五个 CI job 已配置；`android-apk` 仍为 `continue-on-error`，真机竖屏、安全区和基础交互尚待人工验收
- **美术表现 v0.2 已定稿（2026-09-12）**：静态岩彩贴图为主，不使用 Spine/骨骼动画；Tween + 少量拆件 + 受限序列帧/粒子，见 docs/10 §3~§12
- 开发设施已从 feitu 移植（2026-09-08）：gdUnit4 + godot_ai(4.0.2) + 子代理管线 + CI + 检查脚本
