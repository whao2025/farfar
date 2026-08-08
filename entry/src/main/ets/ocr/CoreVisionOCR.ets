import { pdfService } from '@kit.PDFKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { OCRResult, OCRPage, TextBlock, TextLine, OCROptions, OCRProgress } from './OCRTypes';
import { OCRService } from './OCRService';
import { runOcrSession } from '../utils/OcrLock';

const MAX_RETRY = 2;
const DEFAULT_FONT_SIZE = 12;
const UPSCALE = 2;
const CACHE_DIR = 'ocr_cache';

export class CoreVisionOCR implements OCRService {
  private inited: boolean = false;
  private context: common.Context | null = null;

  configure(context?: common.Context): void {
    this.context = context ?? null;
  }

  async recognize(pdfPath: string, options?: OCROptions, onProgress?: (p: OCRProgress) => void): Promise<OCRResult> {
    const cachePath = await this.resolveCachePath(pdfPath, options);
    if (cachePath.length > 0) {
      const hit = await this.readCache(cachePath);
      if (hit) {
        return hit;
      }
    }
    const result = await runOcrSession(async () => this.doRecognize(pdfPath, options, onProgress));
    if (cachePath.length > 0 && result.pages.length > 0) {
      await this.writeCache(cachePath, result);
    }
    return result;
  }

  private async doRecognize(pdfPath: string, options?: OCROptions, onProgress?: (p: OCRProgress) => void): Promise<OCRResult> {
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
        const up = await this.upscalePixelMap(pixelMap);
        const merged: TextBlock[] = [];
        if (up) {
          try {
            const upRes = await textRecognition.recognizeText({ pixelMap: up });
            const upBlocks = this.parseResult(upRes, page, UPSCALE);
            merged.push(...upBlocks);
          } catch (err) {
            console.error('recognizeText upscaled failed attempt=' + attempt, JSON.stringify(err));
          } finally {
            up.release();
          }
        }
        try {
          const res = await textRecognition.recognizeText({ pixelMap: pixelMap });
          const blocks = this.parseResult(res, page, 1);
          merged.push(...blocks);
        } catch (err) {
          console.error('recognizeText failed attempt=' + attempt, JSON.stringify(err));
        }
        if (merged.length === 0) {
          continue;
        }
        return this.mergeBlocks(merged);
      } finally {
        pixelMap.release();
      }
    }
    return [];
  }

  private async upscalePixelMap(pm: image.PixelMap): Promise<image.PixelMap | null> {
    try {
      return await pm.createScaledPixelMap(UPSCALE, UPSCALE);
    } catch (err) {
      console.error('upscale failed', JSON.stringify(err));
      return null;
    }
  }

  private mergeBlocks(all: TextBlock[]): TextBlock[] {
    const seen = new Set<string>();
    const out: TextBlock[] = [];
    for (const b of all) {
      const key = b.text.trim() + '_' + Math.round(b.x) + '_' + Math.round(b.y);
      if (!seen.has(key)) {
        seen.add(key);
        out.push(b);
      }
    }
    return out;
  }

  private parseResult(res: textRecognition.TextRecognitionResult, page: pdfService.PdfPage, scale: number): TextBlock[] {
    const blocks: TextBlock[] = [];
    const pageH = this.pageHeightOf(page);
    const raw = res.blocks;
    const div = scale > 0 ? scale : 1;
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
          x: pts.length >= 2 ? pts[0].x / div : 0,
          y: pts.length >= 2 ? pts[0].y / div : 0,
          width: pts.length >= 2 ? (maxX - minX) / div : 0,
          height: pts.length >= 2 ? (maxY - minY) / div : 0
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
        x: minX / div,
        y: pageH - maxY / div,
        width: (maxX - minX) / div,
        height: (maxY - minY) / div,
        fontSize: DEFAULT_FONT_SIZE,
        fontName: undefined,
        confidence: 1,
        lines: lines
      });
    }
    return blocks;
  }

  private async resolveCachePath(pdfPath: string, options?: OCROptions): Promise<string> {
    if (!this.context) {
      return '';
    }
    try {
      const st = await fileIo.stat(pdfPath);
      const dir = this.context.filesDir + '/' + CACHE_DIR;
      await this.ensureDir(dir);
      const start = options?.startPage ?? 0;
      const end = options?.endPage ?? 'all';
      const name = st.size + '_' + st.mtime + '_p' + start + '-' + end + '.json';
      return dir + '/' + this.sanitize(name);
    } catch (err) {
      console.error('resolveCachePath failed', JSON.stringify(err));
      return '';
    }
  }

  private sanitize(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_');
  }

  private async ensureDir(dir: string): Promise<void> {
    try {
      await fileIo.mkdir(dir);
    } catch (err) {
      // 目录已存在时忽略
    }
  }

  private async readCache(path: string): Promise<OCRResult | null> {
    try {
      const text = await fileIo.readText(path);
      if (!text) {
        return null;
      }
      const parsed = JSON.parse(text) as OCRResult;
      return parsed;
    } catch (err) {
      return null;
    }
  }

  private async writeCache(path: string, result: OCRResult): Promise<void> {
    try {
      const text = JSON.stringify(result);
      const encoder = new util.TextEncoder();
      const buf = encoder.encodeInto(text).buffer;
      const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, buf);
      } finally {
        await fileIo.close(file.fd);
      }
    } catch (err) {
      console.error('writeCache failed', JSON.stringify(err));
    }
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
