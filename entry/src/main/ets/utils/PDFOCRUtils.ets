import { pdfService } from '@kit.PDFKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { runOcrSession } from './OcrLock';
import { mergeUniqueLines } from './BookOcr';

// 扫描件 OCR：3 倍高清渲染（上限 4096px），配合彩色/灰度双路与行级合并提升准确率
const OCR_SCALE = 3;
const OCR_MAX_DIM = 4096;

export interface OCRLineInfo {
  text: string;
  top: number;
  left: number;
  width: number;
  height: number;
}

export interface OCRPageResult {
  ok: boolean;
  lines: OCRLineInfo[];
  value: string;
}

/**
 * 识别图片型/扫描型 PDF 的文本。优先文字型提取，失败时逐页 OCR（端侧，不联网）。
 */
export async function extractTextWithOCRFallback(pdfPath: string, textOnly: string): Promise<string> {
  const trimmed = textOnly.trim();
  if (trimmed.length > 0 && !isAllPageMarkers(trimmed)) {
    return trimmed;
  }
  return ocrPdfAsync(pdfPath);
}

export function isAllPageMarkers(text: string): boolean {
  const lines = text.split('\n').map(l => l.trim()).filter(l => l.length > 0);
  if (lines.length === 0) {
    return false;
  }
  return lines.every(l => /^---\s*第\s*\d+\s*页\s*---$/.test(l));
}


export async function ocrPdfPagesAsync(pdfPath: string): Promise<string[]> {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    const result = doc.loadDocument(pdfPath, '');
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      return [];
    }
    const count = doc.getPageCount();
    const pdf: pdfService.PdfDocument = doc;
    return await runOcrSession(async () => {
      const pages: string[] = [];
      const config: textRecognition.TextRecognitionConfiguration = {
        isDirectionDetectionSupported: true
      };
      for (let i = 0; i < count; i++) {
        const page = pdf.getPage(i);
        pages.push(await recognizePageHiRes(page, config));
      }
      return pages;
    });
  } catch (err) {
    console.error('ocrPdfPages failed', JSON.stringify(err));
    return [];
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

export async function ocrPdfAsync(pdfPath: string): Promise<string> {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    const result = doc.loadDocument(pdfPath, '');
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      console.error('ocrPdf loadDocument failed', result);
      return '';
    }
    const count = doc.getPageCount();
    const pdf: pdfService.PdfDocument = doc;
    return await runOcrSession(async () => {
      let sb: string = '';
      const config: textRecognition.TextRecognitionConfiguration = {
        isDirectionDetectionSupported: true
      };
      for (let i = 0; i < count; i++) {
        const page = pdf.getPage(i);
        const text = await recognizePageHiRes(page, config);
        if (text.trim().length > 0) {
          sb += text;
          if (i < count - 1) {
            sb += '\n';
          }
        }
      }
      return sb.trim();
    });
  } catch (err) {
    const e = err as BusinessError;
    console.error('ocrPdf failed', JSON.stringify(e));
    return '';
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

/**
 * 高清渲染页面后识别。优先彩色高清，空白时退灰度重试，两路结果并集去重。
 */
const NOISE_ONLY_SYMBOLS = '|_-=~^\u0060\u00b7\u2022\u25cf\u25cb\u25a0\u25a1\u25c6\u25c7\u203b\u2192\u2190\u2191\u2193\u2500\u2502\u250c\u2510\u2514\u2518';
const MEANINGFUL_PUNCT = '.,:;%\u00a5\u00a3$/-()[]\u3001\u3002\uff0c\uff1a\uff1b\uff05\uffe5';

function isNoiseLine(line: string): boolean {
  const compact = line.replace(/\s+/g, '');
  if (compact.length === 0) {
    return true;
  }
  let meaningful = 0;
  let symbolOnly = true;
  for (let i = 0; i < compact.length; i++) {
    const ch = compact.charAt(i);
    const code = ch.charCodeAt(0);
    const isCjk = code >= 0x4e00 && code <= 0x9fff;
    const isAlnum = (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
    if (isCjk || isAlnum) {
      meaningful++;
      symbolOnly = false;
    } else if (MEANINGFUL_PUNCT.indexOf(ch) >= 0) {
      meaningful++;
      symbolOnly = false;
    }
  }
  // 纯噪声符号行（如 "|||", "----", "· ·"）
  if (symbolOnly && compact.length <= 8) {
    return true;
  }
  // 有意义的字符占比过低（如 "| | | 3"）且行很短的，视为噪声
  if (compact.length <= 12 && meaningful / compact.length < 0.45) {
    return true;
  }
  return false;
}

function normalizeOcrText(text: string): string {
  let t = text.replace(/\uFFFD/g, '');
  t = t.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '');
  t = t.replace(/\u200B/g, '').replace(/\uFEFF/g, '');
  // 中文/全角之间误插的空格去掉（OCR 常见问题）
  for (let i = 0; i < 3; i++) {
    t = t.replace(/([\u4e00-\u9fa5\u3000-\u303f\uff00-\uffef])\s+([\u4e00-\u9fa5\u3000-\u303f\uff00-\uffef])/g, '$1$2');
  }
  // 数字之间的空格去掉（"3 8" -> "38"）
  for (let i = 0; i < 2; i++) {
    t = t.replace(/([0-9])\s+([0-9])/g, '$1$2');
  }
  // 重复噪声符号压缩（"||||||" -> "||"），但不影响正常文字
  t = t.replace(/([^\u4e00-\u9fa5A-Za-z0-9])\1{3,}/g, '$1$1');
  t = t.replace(/[ \t]{2,}/g, ' ');
  const rawLines = t.split('\n');
  const kept: string[] = [];
  let prev = '';
  for (const rawLine of rawLines) {
    const line = rawLine.trim();
    if (line.length === 0) {
      if (kept.length > 0 && kept[kept.length - 1] !== '') {
        kept.push('');
      }
      continue;
    }
    if (isNoiseLine(line)) {
      continue;
    }
    if (line === prev) {
      continue;
    }
    kept.push(line);
    prev = line;
  }
  while (kept.length > 0 && kept[kept.length - 1] === '') {
    kept.pop();
  }
  return kept.join('\n').trim();
}

async function recognizeOnce(page: pdfService.PdfPage, w: number, h: number, scale: number,
  isGray: boolean, config: textRecognition.TextRecognitionConfiguration): Promise<string> {
  const pm = renderPage(page, w, h, scale, isGray);
  if (!pm) {
    return '';
  }
  try {
    const res = await textRecognition.recognizeText({ pixelMap: pm }, config);
    return res.value ?? '';
  } catch (err) {
    console.error('ocr recognizeText failed', JSON.stringify(err));
    return '';
  } finally {
    pm.release();
  }
}

/**
 * 多路 OCR：彩色高清为主；文字过短（空白页/低对比）时自动再跑灰度并做行级合并。
 * 目标：清晰扫描件字符级准确率 ≥99%，低质扫描尽量 90%+。
 */
async function recognizePageHiRes(page: pdfService.PdfPage, config: textRecognition.TextRecognitionConfiguration): Promise<string> {
  const w = page.getWidth();
  const h = page.getHeight();
  if (w <= 0 || h <= 0) {
    return '';
  }
  const scale = calcSafeScale(w, h);
  const colorText = await recognizeOnce(page, w, h, scale, false, config);
  if (colorText.trim().length >= 30) {
    return normalizeOcrText(colorText);
  }
  const grayText = await recognizeOnce(page, w, h, scale, true, config);
  if (grayText.trim().length === 0) {
    return normalizeOcrText(colorText);
  }
  return normalizeOcrText(mergeUniqueLines(colorText, grayText));
}

function calcSafeScale(w: number, h: number): number {
  const dim = Math.max(w, h);
  const cap = OCR_MAX_DIM / dim;
  return Math.max(0.5, Math.min(OCR_SCALE, cap));
}

function renderPage(
  page: pdfService.PdfPage,
  w: number,
  h: number,
  scale: number,
  isGray: boolean
): image.PixelMap | null {
  try {
    const matrix = new pdfService.PdfMatrix();
    matrix.x = 0;
    matrix.y = 0;
    matrix.width = w;
    matrix.height = h;
    matrix.rotate = 0;
    return page.getAreaPixelMap(matrix, Math.max(1, Math.round(w * scale)), Math.max(1, Math.round(h * scale)), isGray, false);
  } catch (err) {
    const e = err as BusinessError;
    console.error('renderPageHiRes failed', e.code, e.message);
    return null;
  }
}

