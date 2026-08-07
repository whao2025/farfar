import { pdfService } from '@kit.PDFKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { BusinessError } from '@kit.BasicServicesKit';

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

function isAllPageMarkers(text: string): boolean {
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
    let sb: string = '';
    const inited: boolean = await initOcrSafe();
    for (let i = 0; i < count; i++) {
      const page = doc.getPage(i);
      const pixelMap = page.getPagePixelMap();
      if (!pixelMap) {
        continue;
      }
      let value = '';
      try {
        if (inited) {
          const res = await textRecognition.recognizeText({ pixelMap: pixelMap });
          value = res.value ?? '';
        }
      } catch (err) {
        console.error('ocr recognizeText failed', JSON.stringify(err));
        value = '';
      } finally {
        pixelMap.release();
      }
      sb += value;
      if (value.trim().length > 0 && i < count - 1) {
        sb += '\n';
      }
    }
    await releaseOcrSafe();
    return sb.trim();
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

async function initOcrSafe(): Promise<boolean> {
  try {
    return await textRecognition.init();
  } catch (err) {
    console.error('ocr init failed', JSON.stringify(err));
    return false;
  }
}

async function releaseOcrSafe(): Promise<void> {
  try {
    await textRecognition.release();
  } catch (err) {
    console.error('ocr release failed', JSON.stringify(err));
  }
}