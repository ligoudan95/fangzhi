# MEMORY — fangzhi 项目记忆

> 由 Team Lead 维护：阶段性关键事实与决策追加到「近期关键记录」（新条目放最上面）；过时条目及时清理。每日明细见 `logs/YYYY-MM-DD.md`。

## 近期关键记录

### 2026-09-08（深夜）· D11-14 完成：演出闭环 + Android/CI，docs/13 §13 自动化部分收官
- D11-12：battle.tscn 主场景（BattlePlayback 文本回放 1x/2x/跳过/重播同种子/关卡选择），配置→战斗→结果 headless 全链通过
- D13-14：export_presets.cfg（Android arm64、*.json 进包、minSdk26）；CI 五 job（lint/test 转强制 + android-apk artifact）；测试 28/28、check_all 七步全绿
- 待人工：真机竖屏验证（README「下一步」清单）；本机缺 Java/Android SDK
- Phase 0 余项（掉落 roll/村落 tick/存档链）为下一阶段主线

### 2026-09-08（晚）· D6-10 战斗引擎移植完成，对拍全绿
- 移植：scripts/battle/rng.gd（BattleRng mulberry32，32 位运算用 _mul32 16位拆分防 int64 溢出）、engine.gd（Battle：clash/calc_damage/compute_capture_rate 纯函数 + 完整回合流程/eff/Buff/AI 决策/替补/DOT/嘲讽/蓄势/引爆/捕捉）、battle_setup.gd（BattleSetup：表加载/组 cfg/make_pet_input/group_inputs）
- 对拍设施：tools/parity/seeds.json（100 种子入 Git）+ tools/parity/gen_parity.ts（`npm run parity` 生成期望日志）+ tests/parity_runner.gd（SceneTree 脚本逐行 diff）；场景：关卡4 标准 3v3 / 关卡6 Boss / 捕捉战（tryCapture 覆盖捕捉率日志）
- **PARITY OK 一次通过**：100 种子 × 3 场景逐行全等；GdUnit4 22 项全绿（TS 15 项断言全部平移 + RNG 黄金值等加强项）；check_all 七步全绿（新增第 7 步对拍）；CI 加 parity 阻塞 job
- 对拍关键坑（已注释在代码）：TS `pickByStrategy` 是惰性调用——RNG 消耗顺序必须 `rng()>0.2` 判断在前；GDScript Array.find 返回索引；resize 填 null 需 fill(0)；`mk.call()` 返回 Variant 需显式类型
- 下一步：D11-12 battle.tscn 最简演出 → D13-14 APK 真机 + CI 收紧

### 2026-09-08（下午）· Godot D1-2 + D3-5 完成，check_all 全绿
- D1-2：scripts/ 五层骨架（infra/config/battle/logic/view）+ Autoload 四件套（Event/Config/Save/Audio，注册顺序 Event→Config→Save→Audio→_mcp_game_helper）+ default_bus_layout.tres 五总线 + tools/sync_config.ts（npm run sync:godot：导表→回填 resources/config/）
- D3-5：ConfigService.gd（11 表加载，get_table/get_rows/get_g，幂等）+ stats.gd（BattleStats：break_mult/compute_stats/power_of，与 TS 逐行对齐）+ GdUnit4 8 项测试全绿
- **对拍已成立**：tests/battle_stats_test.gd 黄金值测试——15/40/80/120 级六维+战力与 TS 实算逐项全等（1253/3308/9233/27583）；公式改动需双侧同步更新黄金值
- GDScript 对拍坑（已记入代码注释）：int/int 整除必须写 /1000.0；`:=` 从 Variant 推断在 4.7 是错误级告警；Godot 4.7 拒绝 --remote-debug 端口 0；GdUnit -s 模式前必须 `--import` 建类缓存（check_all 已内置）
- 下一步：D6-10 battle 移植（mulberry32/伤害公式/Buff/AI）+ parity_runner.gd

### 2026-09-08（上午）
- 仓库自 `github.com/ligoudan95/fangzhi.git` 克隆；本机直连 GitHub 超时，走本地代理 `127.0.0.1:7897`
- TS 数值基准全绿：11 张表导出、校验 V-101~501 全过、15/15 测试通过（Node v24.11.1）
- Godot 骨架修正（D1-2 前置）：工程名 fangzhi、竖屏 1080×1920 + portrait、渲染改 gl_compatibility（docs/13 §2）、.gitignore 双份合并、`tables/` 加 `.gdignore`（数值链路不许引擎直接碰表）
- 从 feitu 移植开发设施：addons/gdUnit4 6.2.1 + godot_ai 4.0.0（MCP 已配 `.zcode/config.json`）、五角色子代理 + team-lead 命令 + hooks、CI（TS + lint + GdUnit4 三 job）、tools/dep_check.ps1 + check_all.ps1（适配五层）、AGENTS.md
- 注意：hooks 在用户级 `C:\Users\A\.zcode\cli\config.json` 全局注册，当前指向 feitu 路径（两项目 hook 内容相同、与项目无关，全局生效即可）
- 下一步：D1-2 收尾（scripts/ 五层目录 + Autoload 四件套 Config/Save/Event/Audio + 五总线 bus 布局）→ D3-5（ConfigService.gd + stats.gd 移植 + 锚点测试）
