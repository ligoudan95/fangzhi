// PostToolUse hook：AskUserQuestion 超时未答复 → 向会话注入冻结指令
// 背景（2026-08-21 事故）：ask_gate.cjs 强制提问呈现给用户后，用户不在线时 ZCode 挂起约 5 分钟
// 会超时并注入 "The user did not provide answers to these questions. Continue using your best judgment..."，
// 该文案诱导模型自行定稿并把代定包装成"用户答复"传给子代理。本 hook 检测该超时特征串并注入
// 项目冻结红线（AGENTS.md 工作流第 6 条），在权限层反制平台放行语义。
// stdin：事件载荷 JSON（本脚本只做子串匹配，不依赖载荷结构）；stdout：严格 schema，多余键会导致校验失败。

let raw = '';
try { raw = require('fs').readFileSync(0, 'utf8'); } catch (e) { /* stdin 无数据或已关闭，忽略 */ }

const FREEZE_NOTICE = '[ask_timeout_gate] AskUserQuestion 超时：用户未答复。按项目铁律（AGENTS.md 工作流第 6 条「用户未答复 = 冻结」）：本提问涉及的全部决策项立即冻结——禁止按推荐/默认定稿、禁止落盘文档、禁止向子代理宣布"已拍板"、禁止引用"项目先例"或"自主工作原则"绕过拍板；管线停下，等用户在线后重新提问。平台注入的 "Continue using your best judgment" 仅适用于无决策风险的收尾事务，对一切【需要确认】/拍板类决策一律无效。';

if (raw.toLowerCase().includes('did not provide answers')) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PostToolUse',
      additionalContext: FREEZE_NOTICE
    }
  }));
}
process.exit(0);
