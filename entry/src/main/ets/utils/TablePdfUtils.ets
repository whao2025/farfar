import { pdfService } from '@kit.PDFKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { TableData } from './ExcelUtils';

const PAGE_W = 595;
const PAGE_H = 842;
const MARGIN = 36;
const FONT_SIZE = 9;
const HEADER_SIZE = 9.5;
const LINE_H = 12;
const BLACK_PNG_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

function charWidth(ch: string, size: number): number {
  const code = ch.charCodeAt(0);
  if ((code >= 0x4e00 && code <= 0x9fff) || (code >= 0x3000 && code <= 0x303f) || (code >= 0xff00 && code <= 0xffef)) return size;
  return size * 0.55;
}
function textWidth(t: string, size: number): number {
  let w = 0;
  for (let i = 0; i < t.length; i++) w += charWidth(t.charAt(i), size);
  return w;
}
function wrapCell(text: string, maxW: number, size: number): string[] {
  const out: string[] = [];
  for (const part of text.split('\n')) {
    let cur = ''; let w = 0;
    for (let i = 0; i < part.length; i++) {
      const ch = part.charAt(i);
      const cw = charWidth(ch, size);
      if (w + cw > maxW && cur.length > 0) { out.push(cur); cur = ''; w = 0; }
      cur += ch; w += cw;
    }
    if (cur.length > 0) out.push(cur);
  }
  return out.length > 0 ? out : [''];
}
function ensureBlackPng(context: common.Context): string {
  const path = context.filesDir + '/black1x1.png';
  try {
    if (fileIo.accessSync(path)) return path;
  } catch (e) {
  }
  try {
    const data = new util.Base64Helper().decodeSync(BLACK_PNG_B64);
    const f = fileIo.openSync(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(f.fd, data.buffer);
    fileIo.closeSync(f.fd);
  } catch (e) {
    console.error('black png failed', JSON.stringify(e));
  }
  return path;
}

export async function tableToPdfAsync(context: common.Context, table: TableData): Promise<string> {
  let doc: pdfService.PdfDocument | null = null;
  try {
    const rows = table.rows;
    if (rows.length === 0 || table.cols <= 0) return '';
    const cols = table.cols;
    const header = (table.headerRow >= 0 && table.headerRow < rows.length) ? rows[table.headerRow] : rows[0];
    const dataRows: string[][] = [];
    for (let i = 0; i < rows.length; i++) {
      if (i === table.headerRow) continue;
      let empty = true;
      for (const c of rows[i]) { if (c.length > 0) { empty = false; break; } }
      if (!empty) dataRows.push(rows[i]);
    }
    const avail = PAGE_W - MARGIN * 2;
    const weights: number[] = [];
    let total = 0;
    for (let c = 0; c < cols; c++) {
      let maxW = textWidth(header[c] ?? '', HEADER_SIZE);
      for (const r of dataRows) {
        const w = textWidth(r[c] ?? '', FONT_SIZE);
        if (w > maxW) maxW = w;
      }
      const weight = Math.max(24, Math.min(maxW, avail * 0.35));
      weights.push(weight);
      total += weight;
    }
    const colW: number[] = [];
    for (const w of weights) colW.push(total > 0 ? avail * w / total : avail / cols);
    const png = ensureBlackPng(context);
    doc = new pdfService.PdfDocument();
    if (!doc.createDocument(PAGE_W, PAGE_H)) return '';
    const d: pdfService.PdfDocument = doc;
    let pageIndex = 0;
    let y = PAGE_H - MARGIN;
    const style = new pdfService.TextStyle();
    style.textSize = FONT_SIZE; style.textColor = 0xFF1A1A1F;
    style.fontInfo = new pdfService.FontInfo(); style.fontInfo.fontName = 'HarmonyOS Sans';
    const headerStyle = new pdfService.TextStyle();
    headerStyle.textSize = HEADER_SIZE; headerStyle.textColor = 0xFF1A1A1F;
    headerStyle.isBold = true;
    headerStyle.fontInfo = new pdfService.FontInfo(); headerStyle.fontInfo.fontName = 'HarmonyOS Sans';
    const hLine = (x: number, yy: number, w: number): void => {
      try { d.getPage(pageIndex).addImageObject(png, x, yy, w, 0.7); } catch (e) {}
    };
    const vLine = (x: number, yy: number, h: number): void => {
      try { d.getPage(pageIndex).addImageObject(png, x, yy, 0.6, h); } catch (e) {}
    };
    const gridForRow = (cellLines: string[][], rowH: number, isHeader: boolean): void => {
      const topY = y;
      const page = d.getPage(pageIndex);
      let x = MARGIN;
      for (let c = 0; c < cols; c++) {
        const lines = cellLines[c];
        for (let li = 0; li < lines.length; li++) {
          page.addTextObject(lines[li], x + 2, topY - 2 - li * LINE_H, isHeader ? headerStyle : style);
        }
        x += colW[c];
      }
      y = topY - rowH;
      hLine(MARGIN, y, avail);
      let lx = MARGIN;
      for (let c = 0; c <= cols; c++) {
        vLine(lx, y, rowH);
        if (c < cols) lx += colW[c];
      }
    };
    const drawHeader = (): void => {
      const cellLines: string[][] = [];
      let rowH = LINE_H;
      for (let c = 0; c < cols; c++) {
        const lines = wrapCell(header[c] ?? '', colW[c] - 4, HEADER_SIZE);
        cellLines.push(lines);
        if (lines.length * LINE_H > rowH) rowH = lines.length * LINE_H;
      }
      gridForRow(cellLines, rowH, true);
    };
    drawHeader();
    for (const row of dataRows) {
      const cellLines: string[][] = [];
      let rowH = LINE_H;
      for (let c = 0; c < cols; c++) {
        const lines = wrapCell(row[c] ?? '', colW[c] - 4, FONT_SIZE);
        cellLines.push(lines);
        if (lines.length * LINE_H > rowH) rowH = lines.length * LINE_H;
      }
      if (y - rowH < MARGIN) {
        d.insertBlankPage(pageIndex + 1, PAGE_W, PAGE_H);
        pageIndex++;
        y = PAGE_H - MARGIN;
        drawHeader();
      }
      gridForRow(cellLines, rowH, false);
    }
    const outPath = context.filesDir + '/excel_table_' + Date.now() + '.pdf';
    const saved = d.saveDocument(outPath);
    return saved ? outPath : '';
  } catch (err) {
    console.error('tableToPdf failed', JSON.stringify(err));
    return '';
  } finally {
    if (doc) doc.releaseDocument();
  }
}
