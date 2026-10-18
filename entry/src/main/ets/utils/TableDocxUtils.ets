import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { TableData } from './ExcelUtils';

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
function charWidth(ch: string): number {
  const code = ch.charCodeAt(0);
  if ((code >= 0x4e00 && code <= 0x9fff) || (code >= 0x3000 && code <= 0x303f) || (code >= 0xff00 && code <= 0xffef)) return 2;
  return 1;
}
function textWidth(t: string): number {
  let w = 0;
  for (let i = 0; i < t.length; i++) w += charWidth(t.charAt(i));
  return w;
}
const CONTENT_TYPES = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
  '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
  '<Default Extension="xml" ContentType="application/xml"/>' +
  '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
  '</Types>';
const ROOT_RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
  '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
  '</Relationships>';

function cellXml(text: string, widthTwip: number, isHeader: boolean): string {
  let tcPr = '<w:tcPr><w:tcW w:w="' + widthTwip + '" w:type="dxa"/>';
  if (isHeader) tcPr += '<w:shd w:val="clear" w:color="auto" w:fill="E7E6E6"/>';
  tcPr += '<w:tcMar><w:top w:w="40" w:type="dxa"/><w:left w:w="80" w:type="dxa"/><w:bottom w:w="40" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tcMar>';
  tcPr += '</w:tcPr>';
  let rPr = '<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Microsoft YaHei"/><w:sz w:val="18"/><w:szCs w:val="18"/>';
  if (isHeader) rPr += '<w:b/>';
  rPr += '</w:rPr>';
  const runs = text.split('\n');
  let para = '';
  for (const line of runs) {
    para += '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>' +
      '<w:r>' + rPr + '<w:t xml:space="preserve">' + xmlEscape(line) + '</w:t></w:r></w:p>';
  }
  if (runs.length === 0) para = '<w:p/>';
  return '<w:tc>' + tcPr + para + '</w:tc>';
}

function buildTableXml(table: TableData): string {
  const rows = table.rows;
  const cols = table.cols;
  const header = (table.headerRow >= 0 && table.headerRow < rows.length) ? rows[table.headerRow] : rows[0];
  const dataRows: string[][] = [];
  for (let i = 0; i < rows.length; i++) {
    if (i === table.headerRow) continue;
    let empty = true;
    for (const c of rows[i]) { if (c.length > 0) { empty = false; break; } }
    if (!empty) dataRows.push(rows[i]);
  }
  const usable = 9638; // A4 宽 - 左右页边距(1134*2) 单位 twip
  const weights: number[] = [];
  let total = 0;
  for (let c = 0; c < cols; c++) {
    let w = textWidth(header[c] ?? '');
    for (const r of dataRows) {
      const cw = textWidth(r[c] ?? '');
      if (cw > w) w = cw;
    }
    const weight = Math.max(4, Math.min(w, 40));
    weights.push(weight);
    total += weight;
  }
  const widthTwip: number[] = [];
  for (const w of weights) widthTwip.push(Math.max(500, Math.round(usable * w / total)));
  // 修正总宽
  let sum = 0;
  for (const w of widthTwip) sum += w;
  if (sum > usable) {
    for (let i = 0; i < widthTwip.length; i++) widthTwip[i] = Math.floor(widthTwip[i] * usable / sum);
  }
  let grid = '<w:tblGrid>';
  for (const w of widthTwip) grid += '<w:gridCol w:w="' + w + '"/>';
  grid += '</w:tblGrid>';
  const tblPr = '<w:tblPr><w:tblW w:w="' + usable + '" w:type="dxa"/>' +
    '<w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="808080"/>' +
    '<w:left w:val="single" w:sz="4" w:space="0" w:color="808080"/>' +
    '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="808080"/>' +
    '<w:right w:val="single" w:sz="4" w:space="0" w:color="808080"/>' +
    '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="808080"/>' +
    '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="808080"/></w:tblBorders>' +
    '<w:tblLayout w:type="fixed"/></w:tblPr>';
  let headerRowXml = '<w:tr><w:trPr><w:tblHeader/></w:trPr>';
  for (let c = 0; c < cols; c++) headerRowXml += cellXml(header[c] ?? '', widthTwip[c], true);
  headerRowXml += '</w:tr>';
  let bodyRows = '';
  for (const row of dataRows) {
    let tr = '<w:tr>';
    for (let c = 0; c < cols; c++) tr += cellXml(row[c] ?? '', widthTwip[c], false);
    tr += '</w:tr>';
    bodyRows += tr;
  }
  return '<w:tbl>' + tblPr + grid + headerRowXml + bodyRows + '</w:tbl>';
}

export async function tableToDocxAsync(context: common.Context, table: TableData): Promise<string> {
  try {
    const tableXml = buildTableXml(table);
    const sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>';
    const docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' +
      tableXml + '<w:p/>' + sect + '</w:body></w:document>';
    const enc = new util.TextEncoder();
    const entries: ZipEntry[] = [
      { name: '[Content_Types].xml', data: enc.encodeInto(CONTENT_TYPES) },
      { name: '_rels/.rels', data: enc.encodeInto(ROOT_RELS) },
      { name: 'word/document.xml', data: enc.encodeInto(docXml) }
    ];
    const outPath = context.filesDir + '/excel_table_' + Date.now() + '.docx';
    const bytes = buildZip(entries);
    const f = await fileIo.open(outPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try { await fileIo.write(f.fd, bytes.buffer); } finally { await fileIo.close(f.fd); }
    return outPath;
  } catch (err) {
    console.error('tableToDocx failed', JSON.stringify(err));
    return '';
  }
}
