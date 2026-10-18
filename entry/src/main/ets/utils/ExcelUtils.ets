import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { BookkeepingRecord, RecordType } from '../model/RecordModel';

interface ZipEntry { name: string; data: Uint8Array; }

function crc32(buf: Uint8Array): number {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    crc = crc ^ buf[i];
    for (let k = 0; k < 8; k++) crc = ((crc & 1) === 1) ? ((crc >>> 1) ^ 0xEDB88320) : (crc >>> 1);
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}
function putU16(a: number[], v: number): void { a.push(v & 0xFF); a.push((v >>> 8) & 0xFF); }
function putU32(a: number[], v: number): void { a.push(v & 0xFF); a.push((v >>> 8) & 0xFF); a.push((v >>> 16) & 0xFF); a.push((v >>> 24) & 0xFF); }
function buildZip(entries: ZipEntry[]): Uint8Array {
  const out: number[] = []; const central: number[] = []; const enc = new util.TextEncoder();
  for (const e of entries) {
    const nb = enc.encodeInto(e.name); const crc = crc32(e.data); const offset = out.length;
    putU32(out, 0x04034b50); putU16(out, 20); putU16(out, 0x0800); putU16(out, 0); putU16(out, 0); putU16(out, 0);
    putU32(out, crc); putU32(out, e.data.length); putU32(out, e.data.length); putU16(out, nb.length); putU16(out, 0);
    for (let i = 0; i < nb.length; i++) out.push(nb[i]);
    for (let i = 0; i < e.data.length; i++) out.push(e.data[i]);
    putU32(central, 0x02014b50); putU16(central, 20); putU16(central, 20); putU16(central, 0x0800);
    putU16(central, 0); putU16(central, 0); putU16(central, 0); putU32(central, crc);
    putU32(central, e.data.length); putU32(central, e.data.length); putU16(central, nb.length);
    putU16(central, 0); putU16(central, 0); putU16(central, 0); putU16(central, 0);
    putU32(central, 0); putU32(central, offset);
    for (let i = 0; i < nb.length; i++) central.push(nb[i]);
  }
  const cdOffset = out.length;
  for (let i = 0; i < central.length; i++) out.push(central[i]);
  putU32(out, 0x06054b50); putU16(out, 0); putU16(out, 0); putU16(out, entries.length); putU16(out, entries.length);
  putU32(out, central.length); putU32(out, cdOffset); putU16(out, 0);
  const res = new Uint8Array(out.length);
  for (let i = 0; i < out.length; i++) res[i] = out[i];
  return res;
}
function xmlEscape(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
function colName(idx: number): string {
  let s = '';
  let n = idx + 1;
  while (n > 0) {
    const m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}
function cellXml(rowIdx: number, colIdx: number, value: string, numeric: boolean): string {
  const ref = colName(colIdx) + (rowIdx + 1).toString();
  if (value.length === 0) return '';
  if (numeric && /^-?\d+(\.\d+)?$/.test(value)) {
    return '<c r="' + ref + '"><v>' + value + '</v></c>';
  }
  return '<c r="' + ref + '" t="inlineStr"><is><t xml:space="preserve">' + xmlEscape(value) + '</t></is></c>';
}
const CONTENT_TYPES = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
  '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
  '<Default Extension="xml" ContentType="application/xml"/>' +
  '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
  '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
  '</Types>';
const ROOT_RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
  '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
  '</Relationships>';
const WORKBOOK = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
  '<sheets><sheet name="记账" sheetId="1" r:id="rId1"/></sheets></workbook>';
const WORKBOOK_RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
  '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
  '</Relationships>';
function sheetXml(rows: string[][]): string {
  let body = '';
  for (let r = 0; r < rows.length; r++) {
    let rowXml = '<row r="' + (r + 1) + '">';
    for (let c = 0; c < rows[r].length; c++) {
      const numeric = r > 0 && (c === 2 || c === 1);
      rowXml += cellXml(r, c, rows[r][c], numeric);
    }
    rowXml += '</row>';
    body += rowXml;
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' + body + '</sheetData></worksheet>';
}
function formatDate(ts: number): string {
  const d = new Date(ts);
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}
// 导出：已确认记账记录 -> xlsx（沙盒路径）
export async function exportRecordsToXlsx(context: common.Context, records: BookkeepingRecord[]): Promise<string> {
  try {
    const rows: string[][] = [['日期', '类型', '金额', '分类', '商户', '备注', '来源']];
    for (const r of records) {
      rows.push([formatDate(r.timestamp), r.type === 'income' ? '收入' : '支出',
        Math.abs(r.amount).toFixed(2), r.category, r.merchant ?? '', r.note, r.source]);
    }
    const enc = new util.TextEncoder();
    const entries: ZipEntry[] = [
      { name: '[Content_Types].xml', data: enc.encodeInto(CONTENT_TYPES) },
      { name: '_rels/.rels', data: enc.encodeInto(ROOT_RELS) },
      { name: 'xl/workbook.xml', data: enc.encodeInto(WORKBOOK) },
      { name: 'xl/_rels/workbook.xml.rels', data: enc.encodeInto(WORKBOOK_RELS) },
      { name: 'xl/worksheets/sheet1.xml', data: enc.encodeInto(sheetXml(rows)) }
    ];
    const outPath = context.filesDir + '/bookkeeping_' + Date.now() + '.xlsx';
    const bytes = buildZip(entries);
    const f = await fileIo.open(outPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try { await fileIo.write(f.fd, bytes.buffer); } finally { await fileIo.close(f.fd); }
    return outPath;
  } catch (err) {
    console.error('exportRecordsToXlsx failed', JSON.stringify(err));
    return '';
  }
}
function readFileText(path: string): string {
  const content = fileIo.readTextSync(path);
  return content;
}
function parseSharedStrings(xml: string): string[] {
  const out: string[] = [];
  const items = xml.split('</si>');
  for (const it of items) {
    const re = /<t[^>]*>([\s\S]*?)<\/t>/g;
    let m: RegExpExecArray | null = re.exec(it);
    let s = '';
    while (m !== null) { s += m[1]; m = re.exec(it); }
    if (s.length > 0 || it.indexOf('<si') < 0) {
      if (it.indexOf('<si') >= 0) out.push(xmlUnescape(s));
    }
  }
  return out;
}
function xmlUnescape(s: string): string {
  return s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}
function excelSerialToDate(serial: number): string {
  const ms = Date.UTC(1899, 11, 30) + Math.round(serial) * 86400000;
  const d = new Date(ms);
  return d.getUTCFullYear() + '-' + String(d.getUTCMonth() + 1).padStart(2, '0') + '-' + String(d.getUTCDate()).padStart(2, '0');
}
function parseSheetRows(xml: string, shared: string[]): string[][] {
  const rows: string[][] = [];
  const rowRe = /<row[^>]*>([\s\S]*?)<\/row>/g;
  let rm: RegExpExecArray | null = rowRe.exec(xml);
  while (rm !== null) {
    const cells: string[] = [];
    const cellRe = /<c([^>]*)>([\s\S]*?)<\/c>/g;
    let cm: RegExpExecArray | null = cellRe.exec(rm[1]);
    while (cm !== null) {
      const attrs = cm[1];
      const body = cm[2];
      const refM = attrs.match(/r="([A-Z]+)(\d+)"/);
      let col = cells.length;
      if (refM) {
        let v = 0;
        for (let i = 0; i < refM[1].length; i++) v = v * 26 + (refM[1].charCodeAt(i) - 64);
        col = v - 1;
      }
      let value = '';
      if (attrs.indexOf('t="s"') >= 0) {
        const vm = body.match(/<v>(\d+)<\/v>/);
        if (vm) {
          const idx = parseInt(vm[1], 10);
          value = idx < shared.length ? shared[idx] : '';
        }
      } else if (attrs.indexOf('t="inlineStr"') >= 0 || body.indexOf('<is>') >= 0) {
        const tre = /<t[^>]*>([\s\S]*?)<\/t>/g;
        let tm: RegExpExecArray | null = tre.exec(body);
        while (tm !== null) { value += xmlUnescape(tm[1]); tm = tre.exec(body); }
      } else {
        const vm = body.match(/<v>([\s\S]*?)<\/v>/);
        value = vm ? vm[1] : '';
      }
      while (cells.length < col) cells.push('');
      cells[col] = value.trim();
      cm = cellRe.exec(rm[1]);
    }
    if (cells.join('').trim().length > 0) rows.push(cells);
    rm = rowRe.exec(xml);
  }
  return rows;
}
const DATE_HEADERS = ['日期', '时间', 'date', 'time', '月份', '期间', '发放日期'];
const AMOUNT_HEADERS = ['金额', 'amount', '费用', 'money', '价格', '价税合计', '酬劳', '报酬', '工资', '薪', '劳务', '应发', '实发', '到账'];
const INCOME_HEADERS = ['收入', '入账', '进账', 'income', '收款'];
const EXPENSE_HEADERS = ['支出', '消费', '花销', 'expense', '付款'];
const MERCHANT_HEADERS = ['商户', '商家', 'merchant', '对方', '交易对象', '收款方', '店铺', '姓名', '学生', '人员', '员工', '客户'];
const NOTE_HEADERS = ['备注', '摘要', '说明', '商品', '描述', 'note', 'memo', '用途', '事由', '项目'];
const TYPE_HEADERS = ['类型', '收支', 'type', '方向'];
function findCol(header: string[], keys: string[]): number {
  for (let i = 0; i < header.length; i++) {
    const h = header[i].toLowerCase();
    for (const k of keys) {
      if (h.indexOf(k) >= 0) return i;
    }
  }
  return -1;
}
// xlsx 行 -> 供 AmountParser 解析的逐行文本（日期 类型 商户 备注 金额）
export function xlsxRowsToBookkeepingText(rows: string[][]): string {
  if (rows.length === 0) return '';
  let headerIdx = -1;
  for (let i = 0; i < Math.min(6, rows.length); i++) {
    if (findCol(rows[i], DATE_HEADERS) >= 0 || findCol(rows[i], AMOUNT_HEADERS) >= 0 ||
        findCol(rows[i], INCOME_HEADERS) >= 0 || findCol(rows[i], EXPENSE_HEADERS) >= 0) {
      headerIdx = i;
      break;
    }
  }
  const header = headerIdx >= 0 ? rows[headerIdx] : [];
  let dateCol = findCol(header, DATE_HEADERS);
  let amountCol = findCol(header, AMOUNT_HEADERS);
  let incomeCol = findCol(header, INCOME_HEADERS);
  let expenseCol = findCol(header, EXPENSE_HEADERS);
  if (incomeCol < 0 && expenseCol < 0 && amountCol >= 0 && findCol(header, ['金额']) === amountCol) {
    // 普通"金额"列保持单列处理
  }
  let merchantCol = findCol(header, MERCHANT_HEADERS);
  let noteCol = findCol(header, NOTE_HEADERS);
  let typeCol = findCol(header, TYPE_HEADERS);
  const start = headerIdx >= 0 ? headerIdx + 1 : 0;
  if (amountCol < 0) {
    // 无金额表头：仅当某列"有小数/货币符号"证据且不是编号/学号列时才猜测，否则视为非账单表
    let best = -1; let bestScore = 0;
    for (let c = 0; c < 16; c++) {
      const h = header.length > c ? header[c].toLowerCase() : '';
      if (/编号|序号|学号|工号|电话|手机|id/.test(h)) continue;
      let cnt = 0; let decimal = 0;
      for (let r = start; r < Math.min(rows.length, start + 30); r++) {
        const raw = (rows[r][c] ?? '').trim();
        const v = raw.replace(/[,¥￥\s]/g, '');
        if (/^-?\d+(\.\d+)?$/.test(v)) cnt++;
        if (v.indexOf('.') >= 0 || /[¥￥]/.test(raw)) decimal++;
      }
      const score = decimal * 3 + cnt;
      if (decimal > 0 && score > bestScore) { bestScore = score; best = c; }
    }
    amountCol = best;
  }
  let text = '';
  for (let r = start; r < rows.length; r++) {
    const row = rows[r];
    const joined = row.join(' ');
    if (/合计|总计|小计|余额|汇总|平均/.test(joined)) continue;
    let amountRaw = amountCol >= 0 ? (row[amountCol] ?? '') : '';
    let side = '';
    if (incomeCol >= 0) {
      const iv = (row[incomeCol] ?? '').replace(/[¥￥,\s]/g, '');
      if (/^-?\d+(\.\d+)?$/.test(iv) && parseFloat(iv) !== 0) {
        amountRaw = iv;
        side = '收入';
      }
    }
    if (expenseCol >= 0 && side.length === 0) {
      const ev = (row[expenseCol] ?? '').replace(/[¥￥,\s]/g, '');
      if (/^-?\d+(\.\d+)?$/.test(ev) && parseFloat(ev) !== 0) {
        amountRaw = ev;
        side = '支出';
      }
    }
    if (!/\d/.test(amountRaw)) continue;
    let date = dateCol >= 0 ? (row[dateCol] ?? '') : '';
    if (dateCol >= 0 && /^\d+(\.\d+)?$/.test(date)) date = excelSerialToDate(parseFloat(date));
    const merchant = merchantCol >= 0 ? (row[merchantCol] ?? '') : '';
    const note = noteCol >= 0 ? (row[noteCol] ?? '') : '';
    const type = side.length > 0 ? side : (typeCol >= 0 ? (row[typeCol] ?? '') : '');
    let line = '';
    if (date.length > 0) line += date + ' ';
    if (type.length > 0) line += type + ' ';
    if (merchant.length > 0) line += merchant + ' ';
    if (note.length > 0 && note !== merchant) line += note + ' ';
    line += amountRaw.replace(/[¥￥,]/g, '');
    text += line.trim() + '\n';
  }
  return text.trim();
}
function listSheetTargets(unzipDir: string): string[] {
  const out: string[] = [];
  try {
    const wb = readFileText(unzipDir + '/xl/workbook.xml');
    const rels = readFileText(unzipDir + '/xl/_rels/workbook.xml.rels');
    const relMap: Map<string, string> = new Map<string, string>();
    const relRe = /<Relationship[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"/g;
    let rm: RegExpExecArray | null = relRe.exec(rels);
    while (rm !== null) {
      relMap.set(rm[1], rm[2]);
      rm = relRe.exec(rels);
    }
    const sheetRe = /<sheet[^>]*r:id="([^"]+)"/g;
    let sm: RegExpExecArray | null = sheetRe.exec(wb);
    while (sm !== null) {
      const target = relMap.get(sm[1]);
      if (target) {
        const t = target.charAt(0) === '/' ? target.substring(1) : 'worksheets/' + target.replace(/^.*\//, '');
        out.push(target.charAt(0) === '/' ? target.replace(/^xl\//, '') : t);
      }
      sm = sheetRe.exec(wb);
    }
  } catch (e) {
    out.length = 0;
  }
  if (out.length === 0) out.push('worksheets/sheet1.xml');
  return out;
}

export interface TableData {
  headerRow: number;
  rows: string[][];
  cols: number;
}

function detectHeaderRow(rows: string[][]): number {
  let best = -1; let bestScore = 0;
  for (let i = 0; i < Math.min(10, rows.length); i++) {
    const row = rows[i];
    let nonEmpty = 0; let shortText = 0; let numeric = 0;
    const uniq: string[] = [];
    for (const cell of row) {
      const t = cell.trim();
      if (t.length === 0) continue;
      nonEmpty++;
      if (t.length <= 30) shortText++;
      if (/^-?\d+(\.\d+)?$/.test(t)) numeric++;
      if (uniq.indexOf(t) < 0) uniq.push(t);
    }
    if (nonEmpty < 2) continue;
    let score = nonEmpty * 2 + shortText + uniq.length;
    if (numeric === nonEmpty) score -= 8;
    if (i === 0) score += 2;
    if (score > bestScore) { bestScore = score; best = i; }
  }
  if (best < 0) best = 0;
  return best;
}

export async function readXlsxTable(context: common.Context): Promise<TableData | null> {
  const rows = await pickAndReadXlsxRows(context);
  if (rows.length === 0) return null;
  const headerRow = detectHeaderRow(rows);
  let cols = 0;
  for (const r of rows) {
    if (r.length > cols) cols = r.length;
  }
  if (cols === 0) return null;
  const norm: string[][] = [];
  for (const r of rows) {
    const line: string[] = [];
    for (let c = 0; c < cols; c++) line.push((r[c] ?? '').trim());
    norm.push(line);
  }
  return { headerRow: headerRow, rows: norm, cols: cols };
}

export async function pickAndReadXlsxRows(context: common.Context): Promise<string[][]> {
  const unzipDir = context.filesDir + '/xlsx_unzip_' + Date.now();
  try {
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    opts.fileSuffixFilters = ['.xlsx'];
    const uris: Array<string> = await new picker.DocumentViewPicker(context).select(opts);
    if (!uris || uris.length === 0) return [];
    const srcPath = context.filesDir + '/import_' + Date.now() + '.xlsx';
    const src = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
    let srcFd = 0; let dstFd = 0;
    try {
      srcFd = src.fd;
      const stat = await fileIo.stat(srcFd);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(srcFd, buf);
      const out = await fileIo.open(srcPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      dstFd = out.fd;
      await fileIo.write(dstFd, buf);
    } finally {
      if (srcFd !== 0) await fileIo.close(srcFd);
      if (dstFd !== 0) await fileIo.close(dstFd);
    }
    await fileIo.mkdir(unzipDir);
    await zlib.decompressFile(srcPath, unzipDir);
    const sharedPath = unzipDir + '/xl/sharedStrings.xml';
    let shared: string[] = [];
    try {
      shared = parseSharedStrings(readFileText(sharedPath));
    } catch (e) {
      shared = [];
    }
    // 读取 workbook 里所有 sheet，选择"数据最像账单"的一张（金额列命中优先、行数最多）
    const targets = listSheetTargets(unzipDir);
    let best: string[][] = [];
    let bestScore = -1;
    for (const t of targets) {
      try {
        const rows = parseSheetRows(readFileText(unzipDir + '/xl/' + t), shared);
        if (rows.length === 0) continue;
        let score = 0;
        for (let i = 0; i < Math.min(6, rows.length); i++) {
          if (findCol(rows[i], AMOUNT_HEADERS) >= 0 || findCol(rows[i], INCOME_HEADERS) >= 0 ||
              findCol(rows[i], EXPENSE_HEADERS) >= 0) {
            score += 50;
            break;
          }
        }
        score += Math.min(rows.length, 500);
        if (score > bestScore) { bestScore = score; best = rows; }
      } catch (e) {
        continue;
      }
    }
    if (best.length === 0 && targets.length === 0) {
      try { best = parseSheetRows(readFileText(unzipDir + '/xl/worksheets/sheet1.xml'), shared); } catch (e) {}
    }
    return best;
  } catch (err) {
    console.error('pickAndReadXlsxRows failed', JSON.stringify(err));
    return [];
  }
}
