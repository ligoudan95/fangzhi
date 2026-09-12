# 《莽荒兽契》Phase 0 工程

中国古代玄幻（莽荒）捉宠放置游戏。TapTap 竖屏买断单机（决策见 `docs/01-游戏整体框架设计.md` 第 19 章）。

本仓库当前处于 **Phase 0 垂直切片开发中**：TS 导表管线与 headless 战斗基准已落地，Godot 已接入确定性战斗基线和最简文本回放；正式视觉战斗、掉落 roll、村落生产、完整存档迁移、时间服务与真机验收仍未完成。客户端引擎已定为 **Godot 4.7.1**（`docs/13-Godot4.7引擎开发方案.md`），TS 引擎继续作为数值验收基准，与 Godot 版做同种子对拍。

美术表现已于 2026-09-12 定稿：**不使用 Spine/骨骼动画**，统一采用静态岩彩贴图、Tween、少量拆件、受限序列帧和粒子；完整资产、演出与性能规范见 `docs/10-美术设计规范.md` v0.2。

## 快速开始

```bash
npm run export   # 导表：tables/*.csv → 校验 → out/config/*.json + out/types.d.ts + out/report.md
npm test         # 15 项测试：战力锚点/伤害管线/捕捉蒙特卡洛/确定性/冒烟
npm run demo     # 演示：一场关卡战斗 + 捕捉公式样例 + 关卡战力表
```

环境要求：Node.js ≥ 23.6（原生 TS 直跑，零依赖）。

## 目录结构（对应 docs/07 §8）

```
docs/            设计规则 01-15 + 台账 14 + 产品流程档案 16-24（版本矩阵见 docs/14 §2）
tables/          策划数据源：11 张 CSV（四行表头规范见 docs/12 §1）
tools/export/    导表工具：CSV 解析 + 校验(V-101~501) + JSON/d.ts + 平衡报表(V-401)
src/battle/      确定性战斗引擎：公式/状态/AI/捕捉（docs/03，可 headless）
src/config/      配置加载（ConfigService 的 headless 版）
tests/           数值验收测试（docs/02 锚点 + docs/12 校验规则）
out/             导出产物（JSON 配置 / types.d.ts / report.md 平衡报表）——勿手改
```

## 数值口径（docs/02）

| 锚点 | 目标 | 实算（out/report.md） |
|------|------|------|
| 15 级战力 | 1250 | 1253（+0.2%） |
| 40 级战力 | 3300 | 3308（+0.2%） |
| 80 级战力 | 9200 | 9233（+0.4%） |
| 120 级战力 | 27600 | 27583（−0.1%） |
| 玉葫芦收冰冻玄兽 | 33% | 33.0% ✅ |

## 协作红线（docs/12 §11）

1. 所有数值走表（`tables/`），禁止硬编码；改表后必须 `npm run export` 全绿
2. 表结构变更走程序评审；数据行增删策划自决
3. 战斗引擎任何改动必须保持确定性测试通过（同种子同结果）

## 下一步（Phase 0 余项 → Phase 1）

- [x] 正式视觉演出第一阶段（docs/10 §8，M6）：双端结构化战斗事件（12 类 + 对拍摘要）、`battle.tscn` 2×3 站位 + Tween 动势 + 池化伤害数字 + 震屏、动态 SafeArea、AAB 导出 preset、AudioService 最小实装——占位为元素色块，正式资产到位后替换
- [x] 装备掉落闭环（M3，docs/08 §12）：EquipBase/AffixPool/EquipQuality 三表 + 双端 resolver + 保底/鉴定幂等 + 掉落对拍区段
- [x] 存档与离线底层（M4，docs/15）：SaveService 信封/checksum/迁移/恢复 + UtcTimeSlicer 双端镜像 + GameStateFactory
- [x] 村落作物生产闭环（M4 尾项，docs/26 评审）：ItemBase/StorageRule/SeasonWeather 三表 + Crop 扩展（7 作物全量）；双端 settle_crops（跨季分段/离线上限/软容量溢出衰减）+ `[farm]` 对拍区段；矿场/配方/派遣属 Phase B
- [x] 设置页（docs/23，M6）：五总线音量即时生效 + 总静音 + 减少动态（已接入震屏/闪烁开关）+ 粒子/字号档位持久化；`user://settings.json` 原子写
- [x] FTUE 数据+推进器（M6，docs/16 §2/§4）：MainQuest 第一章扩至 10 节点（首件装备/鉴定/上阵三宠新 goalType 3/4/6）+ 双端 QuestTracker（剧情跳过/目标事件/跨章连锁/幂等）；视图接线与首小时 E2E 随后
- [ ] `config_types.gd` 与 `docs/fields.md` 生成链验收（并发实现已落工作树，仍需导表/漂移检查）
- [x] Godot 工程骨架 D1-2（docs/13 §13）：五层目录 + Autoload 四件套 + 五总线 + `npm run sync:godot` 导表回填链
- [x] stats.gd 移植 + 锚点测试 D3-5：`ConfigService.gd`、成长公式与对应 GdUnit4 测试已入库；当前运行结果以本次 CI/本地检查记录为准
- [x] battle 基线移植 + 对拍设施 D6-10：mulberry32、伤害公式、基础 Buff/AI/捕捉及 100 种子 × 3 场景对拍脚本已入库；这是 TS 基准覆盖范围，不代表 `docs/03` 全量规则完成
- [x] 最简演出 D11-12：`scenes/battle.tscn` 已接入 BattlePlayback 文本回放及 1x/2x/跳过/重播/关卡选择；不等同于正式视觉战斗
- [x] D13-14 自动化配置部分：`export_presets.cfg` 已配置 Android arm64、`*.json` 进包、ETC2/ASTC 压缩；minSdk 跟随模板默认（26 覆盖需 Gradle 构建，暂未启用）；CI 已配置 ts/lint/test/parity 强制 job 和非阻断 `android-apk` job
- [ ] **真机竖屏验证（D13-14 人工项）**：CI 五 job 已全绿、`fangzhi-debug-apk` artifact 已产出（run `34686413389`，30.8MB）——从 Actions 下载 artifact 装机，核对竖屏锁定、上下安全区、基础交互、关卡切换和同种子重播；通过后移除 `android-apk.continue-on-error`

统一风险、证据、Owner、验收与阻塞关系见 `docs/14-风险与完成度台账.md`。未在台账中满足验收条件的条目不得对外表述为“Phase 0 全部完成”“战斗全量完成”或“CI 全绿”。
