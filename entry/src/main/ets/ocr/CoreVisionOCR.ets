import { pdfService } from '@kit.PDFKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { OCRResult, OCRPage, TextBlock, TextLine, OCROptions, OCRProgress } from './OCRTypes';
import { OCRService } from './OCRService';

const MAX_RETRY = 2;
const DEFAULT_FONT_SIZE = 12;

export class CoreVisionOCR implements OCRService {
  private inited: boolean = false;

  async recognize(pdfPath: string, options?: OCROptions, onProgress?: (p: OCRProgress) => void): Promise<OCRResult> {
    let doc: pdfService.PdfDocument | null = null;
    try {
      doc = new pdfService.PdfDocument();
      const loadResult = doc.loadDocument(pdfPath, '');
      if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        console.error('CoreVisionOCR loadDocument failed', loadResult);
        return { pages: [] };
      }
      const total = doc.getPageCount();
      this.inited = await this.initSafe();
      if (!this.inited) {
        console.error('CoreVisionOCR init failed');
        return { pages: [] };
      }
      const pages: OCRPage[] = [];
      for (let i = 0; i < total; i++) {
        if (options?.startPage !== undefined && i < options.startPage) {
          continue;
        }
        if (options?.endPage !== undefined && i > options.endPage) {
          continue;
        }
        const page = doc.getPage(i);
        const blocks = await this.recognizePage(page);
        pages.push({ index: i, width: this.pageWidthOf(page), height: this.pageHeightOf(page), blocks: blocks });
        if (onProgress) {
          onProgress({ pageIndex: i, total: total, percent: total > 0 ? Math.round(((i + 1) / total) * 100) : 0 });
        }
      }
      return { pages: pages };
    } catch (err) {
      const e = err as BusinessError;
      console.error('CoreVisionOCR.recognize failed', JSON.stringify(e));
      return { pages: [] };
    } finally {
      await this.releaseSafe();
      if (doc) {
        doc.releaseDocument();
      }
    }
  }

  private pageWidthOf(page: pdfService.PdfPage): number {
    try {
      return page.getWidth ? page.getWidth() : 595;
    } catch (err) {
      return 595;
    }
  }

  private pageHeightOf(page: pdfService.PdfPage): number {
    try {
      return page.getHeight ? page.getHeight() : 842;
    } catch (err) {
      return 842;
    }
  }

  private async recognizePage(page: pdfService.PdfPage): Promise<TextBlock[]> {
    for (let attempt = 0; attempt < MAX_RETRY; attempt++) {
      const pixelMap = page.getPagePixelMap();
      if (!pixelMap) {
        return [];
      }
      try {
        const res = await textRecognition.recognizeText({ pixelMap: pixelMap });
        return this.parseResult(res, page);
      } catch (err) {
        console.error('recognizeText failed attempt=' + attempt, JSON.stringify(err));
      } finally {
        pixelMap.release();
      }
    }
    return [];
  }

  private parseResult(res: textRecognition.TextRecognitionResult, page: pdfService.PdfPage): TextBlock[] {
    const blocks: TextBlock[] = [];
    const pageH = this.pageHeightOf(page);
    const raw = res.blocks;
    for (let i = 0; i < raw.length; i++) {
      const b = raw[i];
      const lines: TextLine[] = [];
      let minX = Number.MAX_VALUE;
      let minY = Number.MAX_VALUE;
      let maxX = -Number.MAX_VALUE;
      let maxY = -Number.MAX_VALUE;
      for (let j = 0; j < b.lines.length; j++) {
        const ln = b.lines[j];
        const pts = ln.cornerPoints;
        if (pts.length >= 2) {
          for (let k = 0; k < pts.length; k++) {
            const p = pts[k];
            if (p.x < minX) {
              minX = p.x;
            }
            if (p.y < minY) {
              minY = p.y;
            }
            if (p.x > maxX) {
              maxX = p.x;
            }
            if (p.y > maxY) {
              maxY = p.y;
            }
          }
        }
        lines.push({
          text: ln.value,
          x: pts.length >= 2 ? pts[0].x : 0,
          y: pts.length >= 2 ? pts[0].y : 0,
          width: pts.length >= 2 ? (maxX - minX) : 0,
          height: pts.length >= 2 ? (maxY - minY) : 0
        });
      }
      if (minX === Number.MAX_VALUE) {
        minX = 0;
      }
      if (minY === Number.MAX_VALUE) {
        minY = 0;
      }
      if (maxX === -Number.MAX_VALUE) {
        maxX = 0;
      }
      if (maxY === -Number.MAX_VALUE) {
        maxY = 0;
      }
      blocks.push({
        id: 'b' + i,
        text: b.value,
        x: minX,
        y: pageH - maxY,
        width: maxX - minX,
        height: maxY - minY,
        fontSize: DEFAULT_FONT_SIZE,
        fontName: undefined,
        confidence: 1,
        lines: lines
      });
    }
    return blocks;
  }

  private async initSafe(): Promise<boolean> {
    try {
      return await textRecognition.init();
    } catch (err) {
      console.error('CoreVisionOCR init failed', JSON.stringify(err));
      return false;
    }
  }

  private async releaseSafe(): Promise<void> {
    try {
      await textRecognition.release();
    } catch (err) {
      console.error('CoreVisionOCR release failed', JSON.stringify(err));
    }
  }
}
