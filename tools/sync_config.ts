/**
 * 导表产物拷贝链（docs/13 §5）：out/config/*.json → resources/config/
 * 数值唯一链路：tables/*.csv → npm run export → 本脚本 → res://resources/config/
 * 注意：导出 preset 需包含非资源文件过滤器 "*.json"，JSON 才会进 PCK（D13 真机导出时确认）
 */
import { cpSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = join(import.meta.dirname, '..');
const SRC = join(ROOT, 'out', 'config');
const DST = join(ROOT, 'resources', 'config');

mkdirSync(DST, { recursive: true });

let copied = 0;
for (const f of readdirSync(DST)) {
  if (f.endsWith('.json')) rmSync(join(DST, f)); // 清旧防残留改名表
}
for (const f of readdirSync(SRC)) {
  if (!f.endsWith('.json')) continue;
  cpSync(join(SRC, f), join(DST, f));
  copied++;
}
if (copied === 0) throw new Error('out/config 无 JSON——先跑 npm run export');
console.log(`导表回填完成：${copied} 张表 → resources/config/`);
