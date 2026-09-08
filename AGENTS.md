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

## 文档引用规则

- `docs/01-13` 是**唯一需求来源**（v0.1）；写代码前先读对应文档，禁止凭记忆写规则
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
| 引擎对拍 | `npm run parity` + `tests/parity_runner.gd`（种子清单 `tools/parity/seeds.json`，100 种子 × 3 场景逐行 diff） | TS 与 GDScript 同种子跑，任何不一致 = 移植 bug；check_all 第 7 步强制 |
| 数值验收 | `npm run export` → `out/report.md` | 平衡报表 V-401 全过 |
| View/UI | 人工试玩 | 竖屏 1080×1920、上下 80px SafeArea、异形屏清单（docs/10 §10） |

## 目录结构速查

```
docs/            设计文档 01-13（唯一需求来源）
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

- **Phase 0 垂直切片（TS）已完成并全绿**：导表管线 + 确定性战斗引擎 + 15 项数值验收测试
- **Godot 接入（docs/13 §13）D1-12 全部完成**：骨架/数据层/成长公式/战斗引擎移植 + 对拍（100 种子 × 3 场景逐行全等）；D11-12 演出闭环——`scenes/battle.tscn` 主场景（BattlePlayback 文本回放，1x/2x/跳过/重播同种子/关卡选择）
- **D13-14**：`export_presets.cfg` Android（arm64-v8a、`include_filter=*.json` 保配置进包、minSdk 26）；CI 五 job（ts/lint/test/parity 强制 + android-apk artifact 非阻断）；**待人工**：真机竖屏验证（清单见 README「下一步」），本机出包需补 Android SDK + keystore
- **Phase 0 余项**：装备掉落 roll、村落生产 tick、存档迁移链（README「下一步」）
- 开发设施已从 feitu 移植（2026-09-08）：gdUnit4 + godot_ai(4.0.2) + 子代理管线 + CI + 检查脚本
