# 《莽荒兽契》Phase 0 工程

中国古代玄幻（莽荒）捉宠放置游戏。TapTap 竖屏买断单机（决策见 `docs/01-游戏整体框架设计.md` 第 19 章）。

本仓库当前为 **Phase 0 垂直切片**：导表管线 + headless 确定性战斗引擎 + 数值校验测试，全部可运行，不依赖游戏引擎（后续 Cocos 视图层按 `docs/07-技术架构.md` 接入本引擎）。

## 快速开始

```bash
npm run export   # 导表：tables/*.csv → 校验 → out/config/*.json + out/types.d.ts + out/report.md
npm test         # 15 项测试：战力锚点/伤害管线/捕捉蒙特卡洛/确定性/冒烟
npm run demo     # 演示：一场关卡战斗 + 捕捉公式样例 + 关卡战力表
```

环境要求：Node.js ≥ 23.6（原生 TS 直跑，零依赖）。

## 目录结构（对应 docs/07 §8）

```
docs/            设计文档 01-12（唯一需求来源，v0.1）
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

- [ ] 装备掉落 roll（DropRule 已有表，缺 roll 器与未鉴定封装）
- [ ] 村落生产 tick（Crop/Recipe 半成品表，体力心情模型）
- [ ] 存档结构与迁移链（SaveService）
- [ ] Cocos Creator 工程接入（View 层包装本引擎）
