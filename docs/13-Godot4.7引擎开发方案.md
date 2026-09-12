# 13-Godot 4.7 引擎开发方案

> **版本**：v0.3　**日期**：2026-09-12
> **性质**：客户端 **Godot 4.7.1 stable** 定稿方案（原 Cocos Creator 3.8 方案已废止）
> **依据**：决策 #1（TapTap 竖屏买断单机）、#3（纯单机）、#9（竖屏）；07/10/11/12 文档的分层架构、演出、音频、导表规范继续有效，涉及引擎绑定的部分以本文档为准
> **美术表现定稿**：不使用 Spine/骨骼动画或对应插件；统一使用静态贴图、Tween、受限序列帧和少量粒子（详见 10 §3~§11）

---

## 1. 为什么换 Godot 4.7.1

| 维度 | Godot 4.7.1 | 说明 |
|------|------|------|
| 成本 | MIT 开源、**零分成零订阅** | 买断制单机 + 独立开发的成本最优解 |
| 平台覆盖 | Android / iOS / Windows / macOS / Linux / Web 一键导出 | TapTap 双端首发，未来 Steam 版与 Web 试玩版**同一工程直接导出**（Cocos 需维护双技术栈） |
| 2D 能力 | 场景树 + Control 节点天然适合 UI 密集的竖屏放置游戏 | 自定义 UI 组件（掉宝结算屏/装备对比浮窗）无第三方依赖 |
| 编辑器 | 轻量（<200MB）、纯文本场景（.tscn）可 Git diff | 策划也能看懂场景改动，协作友好 |
| 2D 表现 | `Sprite2D` / `AnimatedSprite2D` / Tween / `AnimationPlayer` / `GPUParticles2D` 均为内置能力 | 对接 10 文档静态贴图与轻量序列帧规范，无第三方动画运行时 |

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
│   └— themes/           # 石板浮雕 UI 主题（10 文档 §7）
├─ assets/               # art/ frames/ fx/ ui/ audio/（命名规范见 10 文档 §10）
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
| 安全区 | 上下 80px SafeArea 容器（10 文档 §7）；`DisplayServer.get_display_safe_area()` 动态取 |
| 手势 | 村落单屏禁横向滚动；二级页用 `NavigationStack` 式推拉门 |

## 5. 数据管线衔接（12 文档）

```
tables/*.csv ──npm run export──→ out/config/*.json ──构建脚本拷贝──→ res://resources/config/
```

- Godot 侧 `ConfigService` 用 `FileAccess.get_file_as_string()` + `JSON.parse_string()` 加载；全部首发配置随基础包安装，启动先加载核心表，其余配置按场景从本地包延迟载入内存
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
- TS 版暂不退役；是否归档须以连续 4 周对拍记录和覆盖审计另行决策，不能由历史“全绿”描述替代
- GdUnit4 已有 TS 基准对应断言；覆盖范围以测试清单为准，不代表 `docs/03` 全部战斗规则已实现

## 7. 静态贴图与序列帧表现（10 文档 §3~§11）

- 角色主体使用 `Sprite2D` 静态透明贴图；位置、缩放、旋转、透明度和颜色反馈统一由 Tween 驱动
- 轮廓变化明显的主推宠可用 `AnimatedSprite2D` / `SpriteFrames`：常规 4~8 帧，关键最多 12 帧；普通角色不得依赖序列帧才能接入玩法
- 多轨关键演出使用 `AnimationPlayer`；VFX 由五行通用模板组合，伤害数字、命中特效和飞行图标统一池化
- 同屏活动序列帧节点硬上限 6、活动粒子硬上限 120；运行时角色纹理按实际显示尺寸降采样，禁止 4096² 常驻总图集
- 表现随机使用事件序号哈希或独立视觉随机流，不得消耗 battle/掉落/资质的正式随机流

## 8. 音频（11 文档）

Godot AudioBus 直接映射五总线：`BGM / Amb / SFX_Battle / SFX_Work / UI`（bus 布局文件 `default_bus_layout.tres` 入库）。掉宝音效优先级抢占用 `AudioServer.set_bus_mute_effect` + 自研优先级调度（Infra/Audio 内实现，规格见 11 §7）。BGM 懒加载：`.ogg` 走 `ResourceLoader.load_threaded_request`。

## 9. TapTap 渠道接入

| 能力 | 方案 |
|------|------|
| 分发与买断 | **无需 SDK**——玩家在 TapTap 商店购买下载，商店负责付费与更新（决策 #2 买断制红利） |
| 数据统计 | 首发不接入，保证完整离线；远期可选且必须经隐私评审，不得成为玩法或奖励条件 |
| 版本更新 | 商店整包更新（无热更需求，纯单机决策 #3）；游戏内"检查更新"只跳商店页 |
| 云存档 | 不做（纯单机）；手动导出/导入存档文件满足分享需求（07 §4） |

## 10. 存档（沿用 07 §4 / 12 §8）

`user://save/` 下 JSON + 迁移链；原子写（临时文件 + rename）；3 手动位 + 1 自动位。迁移函数链与表版本解耦的规范不变。

## 11. 导出与包体

| 平台 | 格式 | 目标 |
|------|------|------|
| Android | AAB（TapTap 提交）+ APK（测试） | 完整首发基础包目标 ≤ 400MB；minSdk 26 / arm64-v8a 为主 |
| iOS | IPA | 同预算；Bitcode 无关（Godot 不需要） |
| Windows/macOS | 桌面版（远期 Steam，决策 #1 备选） | 同工程直接导出，UI 已竖屏——以"竖屏窗口"形式发布，需单独做横屏评估 |

- 导出模板：仅使用官方 stable 模板；美术表现不附带第三方动画运行时或原生扩展
- 首发基础包包含完整首发玩法、配置、美术与音频，安装后无需网络即可游玩；运行时按场景从本地包懒加载资源
- PCK 按需下载只作为远期可选 DLC 方案，不得成为首发荒域或音频依赖

## 12. 测试策略（07 §9 的 Godot 落地）

| 层 | 工具 |
|------|------|
| 单元测试 | **gdUnit4**（GDScript 断言库，CI 可 headless 跑） |
| 引擎对拍 | §6 机制，TS 侧 `npm run parity` 生成期望日志 |
| 数值验收 | 02 文档锚点在 GDScript 侧重跑（战力曲线/捕捉分布） |
| 真机 | 竖屏安全区 + 异形屏 + 动态减弱 + 性能预算（10 §12 checklist） |

## 13. 迁移步骤（Phase 0 → Godot 工程）

1. **D1-2（待当次验收）**：工程骨架、目录、Autoload 四件套、竖屏项目设置与 bus 布局已入库
2. **D3-5（待当次验收）**：`ConfigService`、`stats.gd` 与对应测试已入库；`config_types.gd` 生成仍为 Phase 0 余项
3. **D6-10（待当次验收）**：TS 基准覆盖范围的 rng/伤害/基础 Buff/AI/捕捉与 100 种子 × 3 场景对拍设施已入库；不代表 `docs/03` 全量规则完成
4. **D11-12（待当次验收）**：`battle.tscn` 最简文本回放已入库；正式结构化事件与视觉战斗仍为 Phase 0 余项
5. **D13-14（部分完成）**：Android preset 与 gdUnit4/对拍 CI 已配置；APK job 仍非阻断，真机竖屏与安全区未验收

统一状态、证据和阻塞关系见 `docs/14 §3-4`。

## 14. 风险与备选

| 风险 | 缓解 |
|------|------|
| 大尺寸静态贴图造成显存峰值 | 源图与运行时图分离；按实际显示尺寸降采样；大型背景线程加载，离开页面释放 |
| 序列帧数量膨胀 | 普通角色静态主体即可接入；只为主推宠和关键 VFX 增配，严格执行 10 §11 帧数/同屏预算 |
| GDScript 性能（大数据量表解析） | 启动一次解析后缓存 Dictionary；表 ≤ 百 KB 级无压力 |
| iOS 导出链（需 Mac） | 团队无 Mac 则外包签名打包；工程侧保持 iOS preset 就绪 |
| 团队 Godot 经验不足 | 导表驱动减少引擎侧代码；.tscn 文本化降低协作门槛；对拍机制兜底正确性 |

---

*引擎变更不触碰九项已定决策（19 章）——平台（TapTap 竖屏买断单机）不变，仅客户端实现栈更换。07 文档中分层/存档/测试/包体章节继续有效。*
