import { pdfService } from '@kit.PDFKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { runOcrSession } from './OcrLock';
import { mergeUniqueLines } from './BookOcr';

const OCR_SCALE = 2;
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
async function recognizePageHiRes(page: pdfService.PdfPage, config: textRecognition.TextRecognitionConfiguration): Promise<string> {
  const w = page.getWidth();
  const h = page.getHeight();
  if (w <= 0 || h <= 0) {
    return '';
  }
  const s = calcSafeScale(w, h);
  const color = renderPage(page, w, h, s, false);
  if (color) {
    try {
      const res = await textRecognition.recognizeText({ pixelMap: color }, config);
      const value = res.value ?? '';
      if (value.trim().length > 0) {
        return value;
      }
      const gray = renderPage(page, w, h, s, true);
      if (gray) {
        try {
          const res2 = await textRecognition.recognizeText({ pixelMap: gray }, config);
          return mergeUniqueLines(value, res2.value ?? '');
        } finally {
          gray.release();
        }
      }
      return '';
    } catch (err) {
      console.error('ocr recognizeText failed', JSON.stringify(err));
      return '';
    } finally {
      color.release();
    }
  }
  return '';
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

