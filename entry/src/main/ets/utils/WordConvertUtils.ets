import { pdfService } from '@kit.PDFKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { util, taskpool } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { ocrPdfPagesAsync } from './PDFOCRUtils';

interface ZipEntry { name: string; data: Uint8Array; }
interface RunInfo { t: string; x: number; y: number; size: number; font: string; color: number; }
interface PageInfo { w: number; h: number; runs: RunInfo[]; hasImage: boolean; }
interface ParaModel { align: string; isHeading: boolean; runs: RunInfo[]; }
interface LineModel { y: number; x1: number; x2: number; size: number; runs: RunInfo[]; }
interface ImagePart { name: string; data: Uint8Array; widthPt: number; heightPt: number; }
interface DocxRun { t: string; size: number; bold: boolean; italic: boolean; color: number; }
interface DocxPara { align: string; runs: DocxRun[]; isBreak: boolean; }

const TWIP_PER_PT = 20;
const EMU_PER_PT = 12700;
const LIST_START = /^([•◦▪▫●○■□‣⁃∙·\-–—*]|\(?\d{1,3}[.)]|\(?[a-zA-Z][.)]|[①-⑳])/;

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
function buildZipData(entries: ZipEntry[]): Uint8Array {
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
function hexColor(c: number, fallback: string): string {
  if (!c || c <= 0) return fallback;
  let s = (c & 0xFFFFFF).toString(16).toUpperCase();
  while (s.length < 6) s = '0' + s;
  return s;
}
function estimateWidth(text: string, size: number): number {
  let w = 0;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    w += (code >= 0x4e00 && code <= 0x9fff) || (code >= 0x3000 && code <= 0x303f) || (code >= 0xff00 && code <= 0xffef) ? size : size * 0.55;
  }
  return w;
}
function isPageNumberLine(text: string): boolean {
  const t = text.trim();
  return /^[-—\s]*\d{1,4}[-—\s]*$/.test(t) || /^第\s*\d{1,4}\s*页/.test(t) || /^page\s*\d+$/i.test(t);
}
function medianSize(runs: RunInfo[]): number {
  if (runs.length === 0) return 10;
  const sizes: number[] = [];
  for (const r of runs) sizes.push(Math.round(r.size * 2) / 2);
  sizes.sort((a: number, b: number) => a - b);
  return sizes[Math.floor(sizes.length / 2)];
}
function buildLines(page: PageInfo, bodySize: number): LineModel[] {
  const runs: RunInfo[] = [];
  for (const r of page.runs) {
    if ((r.y > page.h - 26 || r.y < 26) && isPageNumberLine(r.t)) continue;
    runs.push(r);
  }
  runs.sort((a: RunInfo, b: RunInfo) => Math.abs(a.y - b.y) > 1.5 ? b.y - a.y : a.x - b.x);
  const lines: LineModel[] = [];
  for (const r of runs) {
    const tol = Math.max(2, Math.min(r.size, bodySize * 1.6) * 0.45);
    let line: LineModel | null = null;
    if (lines.length > 0 && Math.abs(lines[lines.length - 1].y - r.y) <= tol) line = lines[lines.length - 1];
    if (line === null) { line = { y: r.y, x1: r.x, x2: r.x, size: r.size, runs: [] }; lines.push(line); }
    line.runs.push(r);
    line.x1 = Math.min(line.x1, r.x);
    line.x2 = Math.max(line.x2, r.x + estimateWidth(r.t, r.size));
    if (r.size > line.size) line.size = r.size;
  }
  for (const l of lines) l.runs.sort((a: RunInfo, b: RunInfo) => a.x - b.x);
  return lines;
}
function mergeLineText(line: LineModel): string {
  let text = ''; let prevEnd = -1;
  for (const r of line.runs) {
    if (prevEnd >= 0 && r.x - prevEnd > Math.max(1.5, r.size * 0.22) && text.length > 0) {
      const last = text.charAt(text.length - 1); const first = r.t.charAt(0);
      const cl = last.charCodeAt(0) >= 0x4e00 && last.charCodeAt(0) <= 0x9fff;
      const cf = first.charCodeAt(0) >= 0x4e00 && first.charCodeAt(0) <= 0x9fff;
      if (cl || cf || last !== ' ') text += ' ';
    }
    text += r.t; prevEnd = r.x + estimateWidth(r.t, r.size);
  }
  return text.replace(/\s{2,}/g, ' ').trim();
}
function paraAlign(line: LineModel, pageW: number): string {
  const center = (line.x1 + line.x2) / 2; const width = line.x2 - line.x1;
  if (width < pageW * 0.82 && Math.abs(center - pageW / 2) < pageW * 0.06 && width > pageW * 0.12) return 'center';
  if (line.x1 > pageW * 0.22) return 'right';
  return 'left';
}
function buildParagraphs(lines: LineModel[], pageW: number, bodySize: number): ParaModel[] {
  const paras: ParaModel[] = [];
  let current: ParaModel | null = null; let prevLine: LineModel | null = null;
  for (const line of lines) {
    const text = mergeLineText(line);
    if (text.length === 0) continue;
    const isHeading = line.size >= bodySize * 1.25;
    const startsList = LIST_START.test(text);
    let newPara = current === null;
    if (!newPara && prevLine !== null && current !== null) {
      const gap = prevLine.y - line.y; const indentDiff = Math.abs(line.x1 - prevLine.x1);
      const prevShort = (prevLine.x2 - prevLine.x1) < (pageW * 0.72);
      if (isHeading !== current.isHeading || gap > line.size * 1.75 || indentDiff > line.size * 1.2 ||
          (prevShort && gap > line.size * 1.05) || startsList) newPara = true;
    }
    if (newPara) { current = { align: paraAlign(line, pageW), isHeading: isHeading, runs: [] }; paras.push(current); }
    if (current !== null) for (const r of line.runs) current.runs.push(r);
    prevLine = line;
  }
  return paras;
}
function orderColumns(lines: LineModel[], pageW: number): LineModel[] {
  let best = -1; let bestScore = 0;
  for (let x = Math.round(pageW * 0.3); x <= pageW * 0.7; x += 4) {
    let left = 0; let right = 0; let cross = 0;
    for (const l of lines) {
      if (l.x2 < x - 2) left++; else if (l.x1 > x + 2) right++; else cross++;
    }
    if (left >= 2 && right >= 2 && cross <= Math.max(1, Math.floor(lines.length * 0.15))) {
      const score = Math.min(left, right) * 10 - cross;
      if (score > bestScore) { bestScore = score; best = x; }
    }
  }
  if (best < 0) return lines;
  const out: LineModel[] = []; let bandLeft: LineModel[] = []; let bandRight: LineModel[] = [];
  const flush = (): void => { for (const l of bandLeft) out.push(l); for (const l of bandRight) out.push(l); bandLeft = []; bandRight = []; };
  for (const l of lines) {
    if (l.x1 <= best && l.x2 >= best) { flush(); out.push(l); }
    else if (l.x2 < best) bandLeft.push(l); else bandRight.push(l);
  }
  flush();
  return out;
}
function runsToParagraphXml(para: ParaModel): string {
  let pPr = '<w:pPr><w:spacing w:before="0" w:after="80" w:line="240" w:lineRule="auto"/>';
  if (para.align === 'center') pPr += '<w:jc w:val="center"/>';
  else if (para.align === 'right') pPr += '<w:jc w:val="right"/>';
  pPr += '</w:pPr>';
  let runsXml = '';
  for (const r of para.runs) {
    const sz = Math.max(2, Math.round(r.size * 2));
    const bold = para.isHeading || /bold|black|heavy|hei/i.test(r.font);
    const italic = /italic|oblique/i.test(r.font);
    let rPr = '<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Microsoft YaHei"/>';
    rPr += '<w:sz w:val="' + sz + '"/><w:szCs w:val="' + sz + '"/>';
    if (bold) rPr += '<w:b/>';
    if (italic) rPr += '<w:i/>';
    rPr += '<w:color w:val="' + hexColor(r.color, '1A1A1F') + '"/></w:rPr>';
    runsXml += '<w:r>' + rPr + '<w:t xml:space="preserve">' + xmlEscape(r.t) + '</w:t></w:r>';
  }
  return '<w:p>' + pPr + runsXml + '</w:p>';
}
function imageParagraphXml(relId: string, widthPt: number, heightPt: number, picId: number): string {
  const cx = Math.round(widthPt * EMU_PER_PT); const cy = Math.round(heightPt * EMU_PER_PT);
  return '<w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">' +
    '<wp:extent cx="' + cx + '" cy="' + cy + '"/><wp:docPr id="' + picId + '" name="Picture ' + picId + '"/>' +
    '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">' +
    '<pic:pic><pic:nvPicPr><pic:cNvPr id="' + picId + '" name="image' + picId + '.png"/><pic:cNvPicPr/></pic:nvPicPr>' +
    '<pic:blipFill><a:blip r:embed="' + relId + '"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>' +
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="' + cx + '" cy="' + cy + '"/></a:xfrm>' +
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>' +
    '</wp:inline></w:drawing></w:r></w:p>';
}
function xmlUnescape(s: string): string {
  return s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}
@Concurrent
function runExtractLayout(pdfPath: string): string {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    if (doc.loadDocument(pdfPath, '') !== pdfService.ParseResult.PARSE_SUCCESS) return '[]';
    const pages: PageInfo[] = [];
    const count = doc.getPageCount();
    for (let i = 0; i < count; i++) {
      const page = doc.getPage(i);
      const w = page.getWidth(); const h = page.getHeight();
      const runs: RunInfo[] = []; let hasImage = false;
      for (const obj of page.getGraphicsObjects()) {
        if (obj.type === pdfService.GraphicsObjectType.OBJECT_TEXT) {
          const t = obj as pdfService.TextObject;
          if (t.text.length === 0) continue;
          runs.push({ t: t.text, x: t.x, y: t.y, size: t.textSize > 0 ? t.textSize : 10,
            font: (t.fontInfo && t.fontInfo.fontName) ? t.fontInfo.fontName : '', color: t.fillColor });
        } else if (obj.type === pdfService.GraphicsObjectType.OBJECT_IMAGE) hasImage = true;
      }
      pages.push({ w: w, h: h, runs: runs, hasImage: hasImage });
    }
    return JSON.stringify(pages);
  } catch (err) { console.error('extract layout failed', JSON.stringify(err)); return '[]'; }
  finally { if (doc) doc.releaseDocument(); }
}
async function renderPagePng(pdfPath: string, pageIndex: number): Promise<Uint8Array | null> {
  let doc: pdfService.PdfDocument | null = null; let pm: image.PixelMap | null = null; let packer: image.ImagePacker | null = null;
  try {
    doc = new pdfService.PdfDocument();
    if (doc.loadDocument(pdfPath, '') !== pdfService.ParseResult.PARSE_SUCCESS) return null;
    const page = doc.getPage(pageIndex); const w = page.getWidth(); const h = page.getHeight();
    if (w <= 0 || h <= 0) return null;
    const scale = Math.min(1.8, 2400 / Math.max(w, h));
    const matrix = new pdfService.PdfMatrix(); matrix.x = 0; matrix.y = 0; matrix.width = w; matrix.height = h; matrix.rotate = 0;
    pm = page.getAreaPixelMap(matrix, Math.round(w * scale), Math.round(h * scale), false, false);
    packer = image.createImagePacker();
    const data = await packer.packToData(pm, { format: 'image/png', quality: 85 });
    return new Uint8Array(data);
  } catch (err) { console.error('render page png failed', JSON.stringify(err)); return null; }
  finally {
    if (packer) { try { await packer.release(); } catch (e) {} }
    if (pm) { try { pm.release(); } catch (e) {} }
    if (doc) doc.releaseDocument();
  }
}
function buildDocumentXml(parasPerPage: ParaModel[][], imageParas: Map<number, string>, pageW: number, pageH: number): string {
  let body = '';
  for (let p = 0; p < parasPerPage.length; p++) {
    const paras = parasPerPage[p];
    const img = imageParas.get(p);
    if (img) body += img;
    for (const para of paras) body += runsToParagraphXml(para);
    if (p < parasPerPage.length - 1) body += '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';
  }
  const sect = '<w:sectPr><w:pgSz w:w="' + Math.round(pageW * TWIP_PER_PT) + '" w:h="' + Math.round(pageH * TWIP_PER_PT) + '"/>' +
    '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" ' +
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ' +
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" ' +
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ' +
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>' + body + sect + '</w:body></w:document>';
}
function buildDocxEntries(parasPerPage: ParaModel[][], imageParas: Map<number, string>, images: ImagePart[], pageW: number, pageH: number): ZipEntry[] {
  const enc = new util.TextEncoder();
  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>' +
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
  let docRels = '';
  const entries: ZipEntry[] = [];
  for (let i = 0; i < images.length; i++) {
    docRels += '<Relationship Id="rIdImg' + i + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/' + images[i].name + '"/>';
    entries.push({ name: 'word/media/' + images[i].name, data: images[i].data });
  }
  entries.push({ name: '[Content_Types].xml', data: enc.encodeInto(contentTypes) });
  entries.push({ name: '_rels/.rels', data: enc.encodeInto(rootRels) });
  entries.push({ name: 'word/document.xml', data: enc.encodeInto(buildDocumentXml(parasPerPage, imageParas, pageW, pageH)) });
  if (docRels.length > 0) {
    entries.push({ name: 'word/_rels/document.xml.rels', data: enc.encodeInto('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + docRels + '</Relationships>') });
  }
  return entries;
}
export async function pdfToDocxAsync(context: common.Context, pdfPath: string): Promise<string> {
  try {
    const task = new taskpool.Task(runExtractLayout, pdfPath);
    const json = await taskpool.execute(task) as string;
    const pages: PageInfo[] = JSON.parse(json) as PageInfo[];
    let needOcr = false;
    for (const p of pages) { if (p.runs.length === 0) { needOcr = true; break; } }
    const ocrPages: string[] = needOcr ? await ocrPdfPagesAsync(pdfPath) : [];
    const parasPerPage: ParaModel[][] = [];
    const imageParas: Map<number, string> = new Map<number, string>();
    const images: ImagePart[] = [];
    let picId = 1;
    for (let i = 0; i < pages.length; i++) {
      const page = pages[i];
      const bodySize = medianSize(page.runs);
      if (page.runs.length === 0 || (page.hasImage && page.runs.length < 3)) {
        const png = await renderPagePng(pdfPath, i);
        if (png) {
          const name = 'page' + i + '.png';
          images.push({ name: name, data: png, widthPt: page.w, heightPt: page.h });
          imageParas.set(i, imageParagraphXml('rIdImg' + (images.length - 1), page.w, page.h, picId++));
        }
        const paras: ParaModel[] = [];
        const ocrText = ocrPages.length > i ? ocrPages[i] : '';
        if (ocrText.trim().length > 0) {
          for (const line of ocrText.split('\n')) {
            const t = line.trim();
            if (t.length === 0) continue;
            const run: RunInfo = { t: t, x: 0, y: 0, size: 11, font: '', color: 0 };
            paras.push({ align: 'left', isHeading: false, runs: [run] });
          }
        }
        parasPerPage.push(paras);
      } else {
        let lines = buildLines(page, bodySize);
        lines = orderColumns(lines, page.w);
        parasPerPage.push(buildParagraphs(lines, page.w, bodySize));
      }
    }
    const pageW = pages.length > 0 ? pages[0].w : 595;
    const pageH = pages.length > 0 ? pages[0].h : 842;
    const entries = buildDocxEntries(parasPerPage, imageParas, images, pageW, pageH);
    const outPath = context.filesDir + '/word_' + Date.now() + '.docx';
    const bytes = buildZipData(entries);
    const f = await fileIo.open(outPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try { await fileIo.write(f.fd, bytes.buffer); } finally { await fileIo.close(f.fd); }
    return outPath;
  } catch (err) { console.error('pdfToDocx failed', JSON.stringify(err)); return ''; }
}
function wrapText(text: string, maxWidth: number, size: number): string[] {
  const lines: string[] = []; let cur = ''; let w = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i); const cw = estimateWidth(ch, size);
    if (w + cw > maxWidth && cur.length > 0) { lines.push(cur); cur = ''; w = 0; }
    cur += ch; w += cw;
  }
  if (cur.length > 0) lines.push(cur);
  return lines;
}
function parseDocxParagraphs(xml: string): DocxPara[] {
  const paras: DocxPara[] = [];
  for (const chunk of xml.split('</w:p>')) {
    if (chunk.indexOf('<w:t') < 0 && chunk.indexOf('w:type="page"') < 0) continue;
    const isBreak = chunk.indexOf('w:type="page"') >= 0;
    let align = 'left';
    const jc = chunk.match(/<w:jc w:val="(\w+)"/);
    if (jc) align = jc[1];
    const runs: DocxRun[] = [];
    const runRe = /<w:r[ >]([\s\S]*?)<\/w:r>/g;
    let rm: RegExpExecArray | null = runRe.exec(chunk);
    while (rm !== null) {
      const body = rm[1];
      const tRe = /<w:t[^>]*>([\s\S]*?)<\/w:t>/g;
      let tm: RegExpExecArray | null = tRe.exec(body);
      let text = '';
      while (tm !== null) { text += xmlUnescape(tm[1]); tm = tRe.exec(body); }
      if (text.length > 0) {
        const szM = body.match(/<w:sz w:val="(\d+)"/);
        const size = szM ? parseInt(szM[1], 10) / 2 : 11;
        const colorM = body.match(/<w:color w:val="([0-9A-Fa-f]{6})"/);
        runs.push({ t: text, size: size, bold: body.indexOf('<w:b/>') >= 0 || body.indexOf('<w:b ') >= 0,
          italic: body.indexOf('<w:i/>') >= 0 || body.indexOf('<w:i ') >= 0,
          color: colorM ? parseInt('FF' + colorM[1], 16) : 0xFF1A1A1F });
      }
      rm = runRe.exec(chunk);
    }
    if (runs.length > 0 || isBreak) paras.push({ align: align, runs: runs, isBreak: isBreak });
  }
  return paras;
}
function renderDocxToPdf(paras: DocxPara[], outPath: string, w: number, h: number): boolean {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    if (!doc.createDocument(w, h)) return false;
    let pageIndex = 0; let y = h - 64;
    const margin = 56; const bodyWidth = w - margin * 2;
    for (const para of paras) {
      if (para.isBreak) { doc.insertBlankPage(pageIndex + 1, w, h); pageIndex++; y = h - 64; continue; }
      let text = ''; let runSize = 0; let bold = false; let color = 0xFF1A1A1F;
      for (const r of para.runs) {
        text += r.t;
        if (r.size > runSize) runSize = r.size;
        if (r.bold) bold = true;
        if (r.color !== 0xFF1A1A1F) color = r.color;
      }
      if (runSize <= 0) runSize = 11;
      const lineHeight = Math.max(14, runSize * 1.65);
      for (const line of wrapText(text, bodyWidth, runSize)) {
        if (y < 56) { doc.insertBlankPage(pageIndex + 1, w, h); pageIndex++; y = h - 64; }
        const style = new pdfService.TextStyle();
        style.textSize = runSize; style.textColor = color; style.isBold = bold;
        style.fontInfo = new pdfService.FontInfo(); style.fontInfo.fontName = 'HarmonyOS Sans';
        let x = margin;
        if (para.align === 'center' || para.align === 'both') x = Math.max(margin, (w - estimateWidth(line, runSize)) / 2);
        doc.getPage(pageIndex).addTextObject(line, x, y, style);
        y -= lineHeight;
      }
      y -= 2;
    }
    return doc.saveDocument(outPath);
  } catch (err) { console.error('renderDocxToPdf failed', JSON.stringify(err)); return false; }
  finally { if (doc) doc.releaseDocument(); }
}
export async function docxToPdfAsync(context: common.Context, docxPath: string): Promise<string> {
  const unzipDir = context.filesDir + '/docx_unzip_' + Date.now();
  try {
    await fileIo.mkdir(unzipDir);
    await zlib.decompressFile(docxPath, unzipDir);
    const xmlPath = unzipDir + '/word/document.xml';
    const stat = await fileIo.stat(xmlPath);
    const src = await fileIo.open(xmlPath, fileIo.OpenMode.READ_ONLY);
    let xml = '';
    try {
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(src.fd, buf);
      xml = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
    } finally { await fileIo.close(src.fd); }
    const paras = parseDocxParagraphs(xml);
    if (paras.length === 0) return '';
    const outPath = context.filesDir + '/fromword_' + Date.now() + '.pdf';
    return renderDocxToPdf(paras, outPath, 595, 842) ? outPath : '';
  } catch (err) { console.error('docxToPdf failed', JSON.stringify(err)); return ''; }
}
export async function pickAndCopyDocx(context: common.Context): Promise<string> {
  try {
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    opts.fileSuffixFilters = ['.docx'];
    const uris: Array<string> = await new picker.DocumentViewPicker(context).select(opts);
    if (!uris || uris.length === 0) return '';
    const dst = context.filesDir + '/import_' + Date.now() + '.docx';
    const src = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
    let srcFd = 0; let dstFd = 0;
    try {
      srcFd = src.fd;
      const stat = await fileIo.stat(srcFd);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(srcFd, buf);
      const out = await fileIo.open(dst, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      dstFd = out.fd;
      await fileIo.write(dstFd, buf);
      return dst;
    } finally {
      if (srcFd !== 0) await fileIo.close(srcFd);
      if (dstFd !== 0) await fileIo.close(dstFd);
    }
  } catch (err) { console.error('pickAndCopyDocx failed', JSON.stringify(err)); return ''; }
}
