import { pdfService } from '@kit.PDFKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { util, taskpool } from '@kit.ArkTS';
import { ocrPdfPagesAsync } from './PDFOCRUtils';

interface ZipEntry {
  name: string;
  data: Uint8Array;
}

const PAGE_BREAK = '__PAGE_BREAK__';

function crc32(buf: Uint8Array): number {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    crc = crc ^ buf[i];
    for (let k = 0; k < 8; k++) {
      if ((crc & 1) === 1) {
        crc = (crc >>> 1) ^ 0xEDB88320;
      } else {
        crc = crc >>> 1;
      }
    }
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

function putU16(arr: number[], v: number): void {
  arr.push(v & 0xFF);
  arr.push((v >>> 8) & 0xFF);
}

function putU32(arr: number[], v: number): void {
  arr.push(v & 0xFF);
  arr.push((v >>> 8) & 0xFF);
  arr.push((v >>> 16) & 0xFF);
  arr.push((v >>> 24) & 0xFF);
}

function buildZipData(entries: ZipEntry[]): Uint8Array {
  const out: number[] = [];
  const central: number[] = [];
  const enc = new util.TextEncoder();
  for (const e of entries) {
    const nameBytes = enc.encodeInto(e.name);
    const crc = crc32(e.data);
    const offset = out.length;
    putU32(out, 0x04034b50);
    putU16(out, 20);
    putU16(out, 0x0800);
    putU16(out, 0);
    putU16(out, 0);
    putU16(out, 0);
    putU32(out, crc);
    putU32(out, e.data.length);
    putU32(out, e.data.length);
    putU16(out, nameBytes.length);
    putU16(out, 0);
    for (let i = 0; i < nameBytes.length; i++) {
      out.push(nameBytes[i]);
    }
    for (let i = 0; i < e.data.length; i++) {
      out.push(e.data[i]);
    }
    putU32(central, 0x02014b50);
    putU16(central, 20);
    putU16(central, 20);
    putU16(central, 0x0800);
    putU16(central, 0);
    putU16(central, 0);
    putU16(central, 0);
    putU32(central, crc);
    putU32(central, e.data.length);
    putU32(central, e.data.length);
    putU16(central, nameBytes.length);
    putU16(central, 0);
    putU16(central, 0);
    putU16(central, 0);
    putU16(central, 0);
    putU32(central, 0);
    putU32(central, offset);
    for (let i = 0; i < nameBytes.length; i++) {
      central.push(nameBytes[i]);
    }
  }
  const centralOffset = out.length;
  for (let i = 0; i < central.length; i++) {
    out.push(central[i]);
  }
  putU32(out, 0x06054b50);
  putU16(out, 0);
  putU16(out, 0);
  putU16(out, entries.length);
  putU16(out, entries.length);
  putU32(out, central.length);
  putU32(out, centralOffset);
  putU16(out, 0);
  const res = new Uint8Array(out.length);
  for (let i = 0; i < out.length; i++) {
    res[i] = out[i];
  }
  return res;
}

function xmlEscape(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function paraXml(text: string): string {
  return '<w:p><w:r><w:t xml:space="preserve">' + xmlEscape(text) + '</w:t></w:r></w:p>';
}

function pageBreakXml(): string {
  return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';
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

function buildDocumentXml(pages: string[]): string {
  let body = '';
  for (let p = 0; p < pages.length; p++) {
    const lines = pages[p].split('\n');
    for (const line of lines) {
      const t = line.trim();
      if (t.length > 0) {
        body += paraXml(t);
      }
    }
    if (p < pages.length - 1) {
      body += pageBreakXml();
    }
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' +
    body + '<w:sectPr/></w:body></w:document>';
}

@Concurrent
function runExtractPages(pdfPath: string): string {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    const res = doc.loadDocument(pdfPath, '');
    if (res !== pdfService.ParseResult.PARSE_SUCCESS) {
      return '[]';
    }
    const pages: string[] = [];
    const count = doc.getPageCount();
    for (let i = 0; i < count; i++) {
      const page = doc.getPage(i);
      pages.push(page.getTextContent());
    }
    return JSON.stringify(pages);
  } catch (err) {
    return '[]';
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

function hasText(pages: string[]): boolean {
  for (const p of pages) {
    if (p.replace(/\s+/g, '').length > 0) {
      return true;
    }
  }
  return false;
}

export async function pdfToDocxAsync(context: common.Context, pdfPath: string): Promise<string> {
  try {
    const task = new taskpool.Task(runExtractPages, pdfPath);
    const json = await taskpool.execute(task) as string;
    let pages: string[] = JSON.parse(json) as string[];
    if (!hasText(pages)) {
      pages = await ocrPdfPagesAsync(pdfPath);
    }
    if (pages.length === 0 || !hasText(pages)) {
      return '';
    }
    const enc = new util.TextEncoder();
    const entries: ZipEntry[] = [
      { name: '[Content_Types].xml', data: enc.encodeInto(CONTENT_TYPES) },
      { name: '_rels/.rels', data: enc.encodeInto(ROOT_RELS) },
      { name: 'word/document.xml', data: enc.encodeInto(buildDocumentXml(pages)) }
    ];
    const outPath = context.filesDir + '/word_' + Date.now() + '.docx';
    const bytes = buildZipData(entries);
    const file = await fileIo.open(outPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, bytes.buffer);
    } finally {
      await fileIo.close(file.fd);
    }
    return outPath;
  } catch (err) {
    console.error('pdfToDocx failed', JSON.stringify(err));
    return '';
  }
}

function xmlUnescape(s: string): string {
  return s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}

function parseDocumentXml(xml: string): string[] {
  const lines: string[] = [];
  const chunks = xml.split('</w:p>');
  for (const chunk of chunks) {
    const hasBreak = chunk.indexOf('w:type="page"') >= 0;
    const re = /<w:t[^>]*>([\s\S]*?)<\/w:t>/g;
    let m: RegExpExecArray | null = re.exec(chunk);
    let line = '';
    while (m !== null) {
      line += xmlUnescape(m[1]);
      m = re.exec(chunk);
    }
    if (line.length > 0) {
      lines.push(line);
    }
    if (hasBreak) {
      lines.push(PAGE_BREAK);
    }
  }
  return lines;
}

function wrapLine(line: string, perLine: number): string[] {
  const res: string[] = [];
  let cur = '';
  for (let i = 0; i < line.length; i++) {
    cur += line.charAt(i);
    if (cur.length >= perLine) {
      res.push(cur);
      cur = '';
    }
  }
  if (cur.length > 0) {
    res.push(cur);
  }
  return res;
}

function renderLinesToPdf(lines: string[], outPath: string, w: number, h: number): boolean {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    if (!doc.createDocument(w, h)) {
      return false;
    }
    const style = new pdfService.TextStyle();
    style.textSize = 12;
    style.textColor = 0xFF000000;
    style.fontInfo = new pdfService.FontInfo();
    style.fontInfo.fontName = 'HarmonyOS Sans';
    let pageIndex = 0;
    let y = h - 60;
    for (let i = 0; i < lines.length; i++) {
      const raw = lines[i];
      if (raw === PAGE_BREAK) {
        doc.insertBlankPage(pageIndex + 1, w, h);
        pageIndex++;
        y = h - 60;
        continue;
      }
      const chunks = wrapLine(raw, 38);
      for (let c = 0; c < chunks.length; c++) {
        if (y < 60) {
          doc.insertBlankPage(pageIndex + 1, w, h);
          pageIndex++;
          y = h - 60;
        }
        const page = doc.getPage(pageIndex);
        page.addTextObject(chunks[c], 50, y, style);
        y -= 18;
      }
    }
    return doc.saveDocument(outPath);
  } catch (err) {
    console.error('renderLinesToPdf failed', JSON.stringify(err));
    return false;
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

export async function docxToPdfAsync(context: common.Context, docxPath: string): Promise<string> {
  const unzipDir = context.filesDir + '/docx_unzip_' + Date.now();
  try {
    await fileIo.mkdir(unzipDir);
    await zlib.decompressFile(docxPath, unzipDir);
    const xmlPath = unzipDir + '/word/document.xml';
    let xml = '';
    const stat = await fileIo.stat(xmlPath);
    const src = await fileIo.open(xmlPath, fileIo.OpenMode.READ_ONLY);
    try {
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(src.fd, buf);
      const decoder = util.TextDecoder.create('utf-8');
      xml = decoder.decodeToString(new Uint8Array(buf));
    } finally {
      await fileIo.close(src.fd);
    }
    const lines = parseDocumentXml(xml);
    if (lines.length === 0) {
      return '';
    }
    const outPath = context.filesDir + '/fromword_' + Date.now() + '.pdf';
    const ok = renderLinesToPdf(lines, outPath, 595, 842);
    return ok ? outPath : '';
  } catch (err) {
    const e = err as BusinessError;
    console.error('docxToPdf failed', JSON.stringify(e));
    return '';
  }
}

export async function pickAndCopyDocx(context: common.Context): Promise<string> {
  try {
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    opts.fileSuffixFilters = ['.docx'];
    const pickerInst = new picker.DocumentViewPicker(context);
    const uris: Array<string> = await pickerInst.select(opts);
    if (!uris || uris.length === 0) {
      return '';
    }
    const dst = context.filesDir + '/import_' + Date.now() + '.docx';
    const src = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
    let srcFd = 0;
    let dstFd = 0;
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
      if (srcFd !== 0) {
        await fileIo.close(srcFd);
      }
      if (dstFd !== 0) {
        await fileIo.close(dstFd);
      }
    }
  } catch (err) {
    console.error('pickAndCopyDocx failed', JSON.stringify(err));
    return '';
  }
}
