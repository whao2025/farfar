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
const DATE_HEADERS = ['日期', '时间', 'date', 'time'];
const AMOUNT_HEADERS = ['金额', 'amount', '支出', '收入', '费用', 'money', '价格', '价税合计'];
const MERCHANT_HEADERS = ['商户', '商家', 'merchant', '对方', '交易对象', '收款方', '店铺'];
const NOTE_HEADERS = ['备注', '摘要', '说明', '商品', '描述', 'note', 'memo', '用途'];
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
    if (findCol(rows[i], DATE_HEADERS) >= 0 || findCol(rows[i], AMOUNT_HEADERS) >= 0) {
      headerIdx = i;
      break;
    }
  }
  const header = headerIdx >= 0 ? rows[headerIdx] : [];
  let dateCol = findCol(header, DATE_HEADERS);
  let amountCol = findCol(header, AMOUNT_HEADERS);
  let merchantCol = findCol(header, MERCHANT_HEADERS);
  let noteCol = findCol(header, NOTE_HEADERS);
  let typeCol = findCol(header, TYPE_HEADERS);
  const start = headerIdx >= 0 ? headerIdx + 1 : 0;
  if (amountCol < 0) {
    // 无表头：猜金额列（数值最多的列）
    let best = -1; let bestCount = 0;
    for (let c = 0; c < 12; c++) {
      let cnt = 0;
      for (let r = start; r < Math.min(rows.length, start + 20); r++) {
        const v = (rows[r][c] ?? '').replace(/[,¥￥\s]/g, '');
        if (/^-?\d+(\.\d+)?$/.test(v)) cnt++;
      }
      if (cnt > bestCount) { bestCount = cnt; best = c; }
    }
    amountCol = best;
  }
  let text = '';
  for (let r = start; r < rows.length; r++) {
    const row = rows[r];
    const amountRaw = amountCol >= 0 ? (row[amountCol] ?? '') : '';
    if (!/\d/.test(amountRaw)) continue;
    const joined = row.join(' ');
    if (/合计|总计|小计|余额|汇总/.test(joined)) continue;
    let date = dateCol >= 0 ? (row[dateCol] ?? '') : '';
    if (dateCol >= 0 && /^\d+(\.\d+)?$/.test(date)) date = excelSerialToDate(parseFloat(date));
    const merchant = merchantCol >= 0 ? (row[merchantCol] ?? '') : '';
    const note = noteCol >= 0 ? (row[noteCol] ?? '') : '';
    const type = typeCol >= 0 ? (row[typeCol] ?? '') : '';
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
export async function pickAndReadXlsxRows(context: common.Context): Promise<string[][]> {
  const unzipDir = context.filesDir + '/xlsx_unzip_' + Date.now();
  try {
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    opts.fileSuffixFilters = ['.xlsx', '.xls'];
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
    const sheetXmlText = readFileText(unzipDir + '/xl/worksheets/sheet1.xml');
    return parseSheetRows(sheetXmlText, shared);
  } catch (err) {
    console.error('pickAndReadXlsxRows failed', JSON.stringify(err));
    return [];
  }
}
