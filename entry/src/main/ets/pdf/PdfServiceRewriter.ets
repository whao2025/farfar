import { pdfService } from '@kit.PDFKit';
import { taskpool } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { PDFRewriter, TextEdit, RewriteResult } from './PDFRewriter';

@Concurrent
function runRewrite(srcPath: string, outPath: string,
  pageArr: number[], blockArr: number[], textArr: string[], sizeArr: number[]): string {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    const loadResult = doc.loadDocument(srcPath, '');
    if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
      return 'loadDocument failed: ' + loadResult;
    }
    const pendingPages: number[] = [];
    const pendingRefs: Array<pdfService.TextObject> = [];
    const pendingXs: number[] = [];
    const pendingYs: number[] = [];
    const pendingTexts: string[] = [];
    const pendingSizes: number[] = [];

    for (let i = 0; i < pageArr.length; i++) {
      const pageIndex = pageArr[i];
      if (pageIndex >= doc.getPageCount()) {
        continue;
      }
      const page = doc.getPage(pageIndex);
      const objs = page.getGraphicsObjects();
      let cnt = 0;
      let target: pdfService.TextObject | null = null;
      for (const obj of objs) {
        if (obj.type === pdfService.GraphicsObjectType.OBJECT_TEXT) {
          if (cnt === blockArr[i]) {
            target = obj as pdfService.TextObject;
            break;
          }
          cnt++;
        }
      }
      if (target) {
        pendingPages.push(pageIndex);
        pendingRefs.push(target);
        pendingXs.push(target.x);
        pendingYs.push(target.y);
        pendingTexts.push(textArr[i]);
        pendingSizes.push(sizeArr[i]);
      }
    }

    for (let j = 0; j < pendingRefs.length; j++) {
      const p = doc.getPage(pendingPages[j]);
      p.deleteGraphicsObject(pendingRefs[j]);
    }
    for (let j = 0; j < pendingRefs.length; j++) {
      const p = doc.getPage(pendingPages[j]);
      const style: pdfService.TextStyle = new pdfService.TextStyle();
      style.textSize = pendingSizes[j];
      if (pendingRefs[j].fontInfo) {
        style.fontInfo = pendingRefs[j].fontInfo;
      } else {
        style.fontInfo = new pdfService.FontInfo();
        style.fontInfo.fontName = 'HarmonyOS Sans';
      }
      p.addTextObject(pendingTexts[j], pendingXs[j], pendingYs[j], style);
    }

    const saved = doc.saveDocument(outPath);
    if (!saved) {
      return 'saveDocument failed';
    }
    return 'ok';
  } catch (err) {
    return 'error: ' + JSON.stringify(err);
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

export class PdfServiceRewriter implements PDFRewriter {
  async rewrite(srcPath: string, outPath: string, edits: TextEdit[]): Promise<RewriteResult> {
    const pageArr: number[] = [];
    const blockArr: number[] = [];
    const textArr: string[] = [];
    const sizeArr: number[] = [];
    for (const e of edits) {
      pageArr.push(e.pageIndex);
      blockArr.push(e.blockIndex);
      textArr.push(e.newText);
      sizeArr.push(e.newSize);
    }
    const task = new taskpool.Task(runRewrite, srcPath, outPath, pageArr, blockArr, textArr, sizeArr);
    try {
      const result = await taskpool.execute(task) as string;
      if (result === 'ok') {
        return { ok: true };
      }
      return { ok: false, error: result };
    } catch (err) {
      const e = err as BusinessError;
      return { ok: false, error: 'taskpool: ' + e.code + ': ' + e.message };
    }
  }
}

export function createPDFRewriter(): PDFRewriter {
  return new PdfServiceRewriter();
}
