# 13-Godot 4.7 引擎开发方案

> **版本**：v0.1　**日期**：2026-09-08
> **性质**：引擎选型变更方案——客户端引擎由 Cocos Creator 3.8（07 文档原案）改为 **Godot 4.7.1 stable**
> **依据**：决策 #1（TapTap 竖屏买断单机）、#3（纯单机）、#9（竖屏）；07/10/11/12 文档的分层架构、演出、音频、导表规范继续有效，涉及引擎绑定的部分以本文档为准

---

## 1. 为什么换 Godot 4.7.1

| 维度 | Godot 4.7.1 | 说明 |
|------|------|------|
| 成本 | MIT 开源、**零分成零订阅** | 买断制单机 + 独立开发的成本最优解 |
| 平台覆盖 | Android / iOS / Windows / macOS / Linux / Web 一键导出 | TapTap 双端首发，未来 Steam 版与 Web 试玩版**同一工程直接导出**（Cocos 需维护双技术栈） |
| 2D 能力 | 场景树 + Control 节点天然适合 UI 密集的竖屏放置游戏 | 自定义 UI 组件（掉宝结算屏/装备对比浮窗）无第三方依赖 |
| 编辑器 | 轻量（<200MB）、纯文本场景（.tscn）可 Git diff | 策划也能看懂场景改动，协作友好 |
| 生态 | Spine 官方 GDExtension、ResourceLoader 分包成熟 | 对接 10 文档骨骼动画规范 |

**代价与对策**：国内 TapTap 渠道无官方 SDK 一键集成（见 §9，纯买断几乎不需要）；社区资源少于 Cocos——用导表驱动数据（12 文档）降低引擎侧复杂度来对冲。

## 2. 版本与语言选型

| 项 | 选型 | 理由 |
|------|------|------|
| 引擎版本 | Godot **4.7.1** stable（锁定 minor 版本，团队统一） | .tscn/.tres 格式跨 minor 不保证兼容，锁版本防协作冲突 |
| 脚本语言 | **GDScript**（主） | 全平台导出无死角（含 Web 备用）；与 TS 逻辑层结构一一对应，移植路径直 |
| C# | 不采用 | iOS AOT 包体与导出链路复杂度高；本项目无重计算需求，收益不抵风险 |
| 渲染器 | **Compatibility（OpenGL）** | 2D 游戏最优、低端安卓机友好、Web 导出可用；不用 Vulkan Mobile |
| TS 代码（Phase 0） | **保留为数值验收基准** | 见 §6 引擎对拍机制——这是确定性引擎设计的直接红利 |

## 3. 架构分层（沿用 07 文档，映射到 Godot）

```
res://
├─ scripts/
│   ├─ infra/        # 时间服务/音频总线/事件总线/日志（Autoload 单例）
│   ├─ config/       # ConfigService：启动加载 res://resources/config/*.json
│   ├─ battle/       # 确定性战斗引擎（GDScript 重写，纯逻辑不依赖节点）
│   ├─ logic/        # 灵宠/村落/任务/装备/经济/境界（Node 无关的 RefCounted 类）
│   └─ view/         # UI 场景与演出（Control 节点，单向数据流：Logic 推送状态）
├─ scenes/
│   ├─ main.tscn         # 主场景（村落单屏 + 任务侧栏）
│   ├─ battle.tscn       # 战斗演出（按事件队列播放，支持 1x/2x/跳过）
│   └─ ui/               # 掉宝开箱结算屏、装备对比浮窗等组件
├─ resources/
│   ├─ config/           # 导表产物 JSON（构建时由 tools/export 回填，勿手改）
│   └— themes/           # 石板浮雕 UI 主题（10 文档 §5）
├─ assets/               # spine/ fx/ audio/（命名规范见 10 文档 §9）
└— tests/                # gdUnit4 单测 + 引擎对拍
```

**关键约束（继承 07 文档并强化）**：
1. `battle/` 与 `logic/` 为纯 GDScript 类（`RefCounted`），不 import 节点——可在无渲染的 headless 模式跑测试与数值模拟
2. View 层零业务逻辑；`battle.tscn` 只消费战斗事件队列（`Array[Dictionary]`）
3. Autoload 仅 4 个：`Config`、`Save`、`Event`、`Audio`——保持场景树干净

## 4. 竖屏适配（决策 #9）

| 项 | 配置 |
|------|------|
| 项目分辨率 | 1080 × 1920（竖屏基准） |
| Stretch Mode | `canvas_items` + Aspect `expand`（异形屏安全，UI 不裁切） |
| 安全区 | 上下 80px SafeArea 容器（10 文档 §5）；`DisplayServer.get_display_safe_area()` 动态取 |
| 手势 | 村落单屏禁横向滚动；二级页用 `NavigationStack` 式推拉门 |

## 5. 数据管线衔接（12 文档）

```
tables/*.csv ──npm run export──→ out/config/*.json ──构建脚本拷贝──→ res://resources/config/
```

- Godot 侧 `ConfigService` 用 `FileAccess.get_file_as_string()` + `JSON.parse_string()` 启动加载（首包表先行，荒域表懒加载）
- **禁止**在 Godot 编辑器内手改 .tres 数值——所有数值走表（12 文档红线）；.tres 只用于主题、动画、粒子等表现资源
- `out/types.d.ts` 对应生成一份 `config_types.gd`（导表工具 Phase 0 余项补上），GDScript 侧获得类型提示

## 6. 引擎对拍机制（Phase 0 资产复用的核心）

确定性引擎（07 §5）让 TS 版与 GDScript 版可以**同种子对拍**：

```
① CI 用同一组种子（种子清单入 Git）跑 TS 引擎 → out/parity/expected/*.log
② Godot headless（godot --headless --script tests/parity_runner.gd）跑同一批种子
③ 逐行 diff 两份日志；任何不一致 = 移植 bug 或公式漂移
```

- 对拍范围：公式数值（伤害/捕捉/资质 roll）、状态效果时序、AI 决策顺序
- TS 版退役时机：对拍连续 4 周全绿后，GDScript 版成为唯一真源，TS 版转归档
- 现有 15 项测试的断言口径全部平移到 gdUnit4

## 7. Spine 动画（10 文档 §7）

- 使用 Esoteric 官方 **spine-godot 4.x GDExtension**（版本随 4.7 兼容线锁定）
- 四类基础骨架（四足/飞行/爬行/人形）的骨骼件直接复用 10 文档规范
- 村落场景同屏 Spine ≤ 8 个（07 文档内存目标不变）；打工三件套动作用 AnimationTracker 复用轨道

## 8. 音频（11 文档）

Godot AudioBus 直接映射五总线：`BGM / Amb / SFX_Battle / SFX_Work / UI`（bus 布局文件 `default_bus_layout.tres` 入库）。掉宝音效优先级抢占用 `AudioServer.set_bus_mute_effect` + 自研优先级调度（Infra/Audio 内实现，规格见 11 §7）。BGM 懒加载：`.ogg` 走 `ResourceLoader.load_threaded_request`。

## 9. TapTap 渠道接入

| 能力 | 方案 |
|------|------|
| 分发与买断 | **无需 SDK**——玩家在 TapTap 商店购买下载，商店负责付费与更新（决策 #2 买断制红利） |
| 数据统计（可选） | TapTD（TapTap 分析）Android/iOS SDK，经 GDExtension/Plugin 封装；仅埋点：留存/关卡流失/掉宝参与 |
| 版本更新 | 商店整包更新（无热更需求，纯单机决策 #3）；游戏内"检查更新"只跳商店页 |
| 云存档 | 不做（纯单机）；手动导出/导入存档文件满足分享需求（07 §4） |

## 10. 存档（沿用 07 §4 / 12 §8）

`user://save/` 下 JSON + 迁移链；原子写（临时文件 + rename）；3 手动位 + 1 自动位。迁移函数链与表版本解耦的规范不变。

## 11. 导出与包体

| 平台 | 格式 | 目标 |
|------|------|------|
| Android | AAB（TapTap 提交）+ APK（测试） | 首包 ≤ 150MB；minSdk 26 / arm64-v8a 为主 |
| iOS | IPA | 同预算；Bitcode 无关（Godot 不需要） |
| Windows/macOS | 桌面版（远期 Steam，决策 #1 备选） | 同工程直接导出，UI 已竖屏——以"竖屏窗口"形式发布，需单独做横屏评估 |

- 导出模板：官方 stable 模板 + spine GDExtension 一起打包
- PCK 分包：基础包（UI+石岭村+12 宠）/ 荒域包 / 音频包——`ProjectSettings` + 自建 loader，对应 07 §7 分包策略

## 12. 测试策略（07 §9 的 Godot 落地）

| 层 | 工具 |
|------|------|
| 单元测试 | **gdUnit4**（GDScript 断言库，CI 可 headless 跑） |
| 引擎对拍 | §6 机制，TS 侧 `npm run parity` 生成期望日志 |
| 数值验收 | 02 文档锚点在 GDScript 侧重跑（战力曲线/捕捉分布） |
| 真机 | 竖屏安全区 + 异形屏清单（10 §10 checklist 不变） |

## 13. 迁移步骤（Phase 0 → Godot 工程）

1. **D1-2**：`godot --headless` 建工程骨架：目录结构、Autoload 四件套、竖屏项目设置、bus 布局
2. **D3-5**：`ConfigService` 读 `resources/config/*.json`；`stats.gd`（成长公式）移植 + 锚点测试过
3. **D6-10**：`battle/` 移植（rng→mulberry32 gd 版、calcDamage、BuffSystem、AI）；对拍脚本上线，种子清单 100 个起
4. **D11-12**：`battle.tscn` 最简演出（事件队列→文本演出即可）打通"配置→战斗→结果"全链
5. **D13-14**：导出 Android APK 真机竖屏验证；gdUnit4 接入 CI

## 14. 风险与备选

| 风险 | 缓解 |
|------|------|
| spine-godot 与 4.7 兼容滞后 | 锁 spine 运行时版本；最坏降级帧动画（10 §7 备选不变） |
| GDScript 性能（大数据量表解析） | 启动一次解析后缓存 Dictionary；表 ≤ 百 KB 级无压力 |
| iOS 导出链（需 Mac） | 团队无 Mac 则外包签名打包；工程侧保持 iOS preset 就绪 |
| 团队 Godot 经验不足 | 导表驱动减少引擎侧代码；.tscn 文本化降低协作门槛；对拍机制兜底正确性 |

---

*引擎变更不触碰九项已定决策（19 章）——平台（TapTap 竖屏买断单机）不变，仅客户端实现栈更换。07 文档中分层/存档/测试/包体章节继续有效。*
