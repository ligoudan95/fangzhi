// PreToolUse hook：AskUserQuestion 强制走人工确认通道
// 背景：yolo 权限模式下 AskUserQuestion 会被权限层自动放行（5ms 内合成答复），
// 子代理/主代理拿到的不是用户本意——本 hook 在权限层强制 decision=ask，
// 无论何种权限模式，问题必须呈现给用户本人，不答复则一直挂起（冻结）。
// stdin：事件载荷 JSON（本脚本不依赖其内容，读掉即可）；stdout：严格 schema，多余键会导致校验失败。

let raw = '';
try { raw = require('fs').readFileSync(0, 'utf8'); } catch (e) { /* stdin 无数据或已关闭，忽略 */ }

process.stdout.write(JSON.stringify({
	hookSpecificOutput: {
		hookEventName: 'PreToolUse',
		permissionDecision: 'ask'
	}
}));
process.exit(0);
