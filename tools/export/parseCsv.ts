/** 标准 CSV 解析：支持引号包裹字段与转义引号（12文档 §1 表格规范）。 */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let inQuotes = false;
  let quotedFieldClosed = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
          quotedFieldClosed = true;
        }
      } else {
        field += ch;
      }
    } else if (quotedFieldClosed) {
      if (ch === ',') {
        row.push(field);
        field = '';
        quotedFieldClosed = false;
      } else if (ch === '\n') {
        row.push(field);
        field = '';
        quotedFieldClosed = false;
        rows.push(row);
        row = [];
      } else if (ch !== '\r') {
        throw new Error(`CSV 引号字段结束后存在非法字符（偏移 ${i}）`);
      }
    } else if (ch === '"') {
      if (field.length > 0) throw new Error(`CSV 未转义引号（偏移 ${i}）`);
      inQuotes = true;
    } else if (ch === ',') {
      row.push(field);
      field = '';
    } else if (ch === '\n') {
      row.push(field);
      field = '';
      rows.push(row);
      row = [];
    } else if (ch !== '\r') {
      field += ch;
    }
  }

  if (inQuotes) throw new Error('CSV 引号字段未闭合');
  if (field.length > 0 || row.length > 0 || quotedFieldClosed) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter(current => !(current.length === 1 && current[0].trim() === ''));
}
