import { pdfService } from '@kit.PDFKit';
import { taskpool } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export interface EditTextOp {
  op: 'addText';
  page: number;
  text: string;
  x: number;
  y: number;
  size: number;
  color: number;
}

export interface EditImageOp {
  op: 'addImage';
  page: number;
  imagePath: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface EditHighlightOp {
  op: 'addHighlight';
  page: number;
  x: number;
  y: number;
  width: number;
  height: number;
  color: number;
}

export interface EditTextAnnotOp {
  op: 'addTextAnnot';
  page: number;
  x: number;
  y: number;
  content: string;
  color: number;
}

export interface EditInsertBlankOp {
  op: 'insertBlankPage';
  index: number;
  width: number;
  height: number;
}

export interface EditDeletePageOp {
  op: 'deletePage';
  index: number;
}

export interface EditMergeOp {
  op: 'mergePages';
  srcPath: string;
  srcStart: number;
  srcCount: number;
  dstIndex: number;
}

export interface EditRewriteTextOp {
  op: 'rewriteText';
  page: number;
  index: number;
  newText: string;
  newSize: number;
  batchId?: string;
}

export interface TextBlockInfo {
  index: number;
  id: string;
  text: string;
  size: number;
  x: number;
  y: number;
  width: number;
  height: number;
  fontName?: string;
}

export type EditOp = EditTextOp | EditImageOp | EditHighlightOp | EditTextAnnotOp
  | EditInsertBlankOp | EditDeletePageOp | EditMergeOp | EditRewriteTextOp;

export interface EditResult {
  success: boolean;
  error?: string;
  newPageCount?: number;
}

@Concurrent
function runEditOps(srcPath: string, outPath: string, newDoc: boolean,
  opsKind: number[], opsPage: number[], opsX: number[], opsY: number[], opsW: number[], opsH: number[],
  opsText: string[], opsNum: number[], opsCounts: number[]): string {
  const OP_ADD_TEXT = 1;
  const OP_ADD_IMAGE = 2;
  const OP_ADD_HIGHLIGHT = 3;
  const OP_ADD_TEXT_ANNOT = 4;
  const OP_INSERT_BLANK = 5;
  const OP_DELETE_PAGE = 6;
  const OP_MERGE = 7;
  const OP_REWRITE_TEXT = 8;
  let doc: pdfService.PdfDocument | null = null;
  const rwPages: number[] = [];
  const rwRefs: Array<pdfService.TextObject> = [];
  const rwXs: number[] = [];
  const rwYs: number[] = [];
  const rwTexts: string[] = [];
  const rwSizes: number[] = [];
  try {
    doc = new pdfService.PdfDocument();
    if (newDoc) {
      const ok = doc.createDocument(595, 842);
      if (!ok) {
        return 'createDocument failed';
      }
    } else {
      const result = doc.loadDocument(srcPath, '');
      if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
        return `loadDocument failed: ${result}`;
      }
    }

    for (let i = 0; i < opsKind.length; i++) {
      const kind = opsKind[i];
      const pageIndex = opsPage[i];
      if (kind === OP_ADD_TEXT) {
        if (pageIndex >= doc.getPageCount()) {
          continue;
        }
        const page = doc.getPage(pageIndex);
        const style: pdfService.TextStyle = new pdfService.TextStyle();
        style.textSize = opsNum[i];
        style.textColor = opsX[i];
        style.fontInfo = new pdfService.FontInfo();
        style.fontInfo.fontName = 'HarmonyOS Sans';
        page.addTextObject(opsText[i], opsY[i], opsW[i], style);
      } else if (kind === OP_ADD_IMAGE) {
        if (pageIndex >= doc.getPageCount()) {
          continue;
        }
        const page = doc.getPage(pageIndex);
        page.addImageObject(opsText[i], opsX[i], opsY[i], opsW[i], opsH[i]);
      } else if (kind === OP_ADD_HIGHLIGHT) {
        if (pageIndex >= doc.getPageCount()) {
          continue;
        }
        const page = doc.getPage(pageIndex);
        const info = new pdfService.HighlightAnnotationInfo();
        info.type = pdfService.AnnotationType.HIGHLIGHT;
        info.uniqueId = 'hl' + Date.now().toString() + i.toString();
        info.color = opsNum[i];
        const pts: pdfService.PdfPoint[] = [];
        const p1 = new pdfService.PdfPoint();
        p1.x = opsX[i];
        p1.y = opsY[i] + opsH[i];
        pts.push(p1);
        const p2 = new pdfService.PdfPoint();
        p2.x = opsX[i] + opsW[i];
        p2.y = opsY[i] + opsH[i];
        pts.push(p2);
        const p3 = new pdfService.PdfPoint();
        p3.x = opsX[i];
        p3.y = opsY[i];
        pts.push(p3);
        const p4 = new pdfService.PdfPoint();
        p4.x = opsX[i] + opsW[i];
        p4.y = opsY[i];
        pts.push(p4);
        info.quadPoints = pts;
        page.addAnnotation(info);
      } else if (kind === OP_ADD_TEXT_ANNOT) {
        if (pageIndex >= doc.getPageCount()) {
          continue;
        }
        const page = doc.getPage(pageIndex);
        const info = new pdfService.TextAnnotationInfo();
        info.type = pdfService.AnnotationType.TEXT;
        info.uniqueId = 'ta' + Date.now().toString() + i.toString();
        info.content = opsText[i];
        info.color = opsNum[i];
        info.x = opsX[i];
        info.y = opsY[i];
        info.iconName = 'Comment';
        info.state = pdfService.TextAnnotationState.UNMARKED;
        page.addAnnotation(info);
      } else if (kind === OP_INSERT_BLANK) {
        doc.insertBlankPage(opsPage[i], opsX[i], opsY[i]);
      } else if (kind === OP_DELETE_PAGE) {
        doc.deletePage(opsPage[i], 1);
      } else if (kind === OP_MERGE) {
        const src = new pdfService.PdfDocument();
        try {
          const result = src.loadDocument(opsText[i], '');
          if (result === pdfService.ParseResult.PARSE_SUCCESS) {
            const srcTotal = src.getPageCount();
            let count = opsCounts[i];
            if (count <= 0 || count > srcTotal) {
              count = srcTotal;
            }
            for (let j = 0; j < count; j++) {
              doc.insertPageFromDocument(src, opsNum[i] + j, 1, opsX[i] + j);
            }
          }
        } finally {
          src.releaseDocument();
        }
      } else if (kind === OP_REWRITE_TEXT) {
        if (pageIndex >= doc.getPageCount()) {
          continue;
        }
        const page = doc.getPage(pageIndex);
        const objs = page.getGraphicsObjects();
        let cnt = 0;
        let target: pdfService.TextObject | null = null;
        for (const obj of objs) {
          if (obj.type === pdfService.GraphicsObjectType.OBJECT_TEXT) {
            if (cnt === opsX[i]) {
              target = obj as pdfService.TextObject;
              break;
            }
            cnt++;
          }
        }
        if (target) {
          rwPages.push(pageIndex);
          rwRefs.push(target);
          rwXs.push(target.x);
          rwYs.push(target.y);
          rwTexts.push(opsText[i]);
          rwSizes.push(opsNum[i]);
        }
      }
    }

    for (let j = 0; j < rwRefs.length; j++) {
      const p = doc.getPage(rwPages[j]);
      p.deleteGraphicsObject(rwRefs[j]);
    }
    for (let j = 0; j < rwRefs.length; j++) {
      const p = doc.getPage(rwPages[j]);
      const style: pdfService.TextStyle = new pdfService.TextStyle();
      style.textSize = rwSizes[j];
      if (rwRefs[j].fontInfo) {
        style.fontInfo = rwRefs[j].fontInfo;
      } else {
        style.fontInfo = new pdfService.FontInfo();
        style.fontInfo.fontName = 'HarmonyOS Sans';
      }
      p.addTextObject(rwTexts[j], rwXs[j], rwYs[j], style);
    }

    const saved = doc.saveDocument(outPath);
    if (!saved) {
      return 'saveDocument failed';
    }
    return 'ok';
  } catch (err) {
    return `error: ${JSON.stringify(err)}`;
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

export async function applyEditsAsync(srcPath: string, outPath: string, ops: EditOp[], newDoc: boolean): Promise<EditResult> {
  const kinds: number[] = [];
  const pages: number[] = [];
  const xs: number[] = [];
  const ys: number[] = [];
  const ws: number[] = [];
  const hs: number[] = [];
  const texts: string[] = [];
  const nums: number[] = [];
  const counts: number[] = [];
  for (const op of ops) {
    if (op.op === 'addText') {
      // addTextObject(text, x, y, style) 参数错位存储：ys=op.x、ws=op.y、xs=op.color(→textColor)、nums=op.size(→textSize)
      kinds.push(1); pages.push(op.page); xs.push(op.color); ys.push(op.x); ws.push(op.y); hs.push(0); texts.push(op.text); nums.push(op.size); counts.push(1);
    } else if (op.op === 'addImage') {
      kinds.push(2); pages.push(op.page); xs.push(op.x); ys.push(op.y); ws.push(op.width); hs.push(op.height); texts.push(op.imagePath); nums.push(0); counts.push(1);
    } else if (op.op === 'addHighlight') {
      kinds.push(3); pages.push(op.page); xs.push(op.x); ys.push(op.y); ws.push(op.width); hs.push(op.height); texts.push(''); nums.push(op.color); counts.push(1);
    } else if (op.op === 'addTextAnnot') {
      kinds.push(4); pages.push(op.page); xs.push(op.x); ys.push(op.y); ws.push(0); hs.push(0); texts.push(op.content); nums.push(op.color); counts.push(1);
    } else if (op.op === 'insertBlankPage') {
      kinds.push(5); pages.push(op.index); xs.push(op.width); ys.push(op.height); ws.push(0); hs.push(0); texts.push(''); nums.push(0); counts.push(1);
    } else if (op.op === 'deletePage') {
      kinds.push(6); pages.push(op.index); xs.push(0); ys.push(0); ws.push(0); hs.push(0); texts.push(''); nums.push(0); counts.push(1);
    } else if (op.op === 'mergePages') {
      kinds.push(7); pages.push(op.dstIndex); xs.push(op.dstIndex); ys.push(0); ws.push(0); hs.push(0); texts.push(op.srcPath); nums.push(op.srcStart); counts.push(op.srcCount);
    } else if (op.op === 'rewriteText') {
      kinds.push(8); pages.push(op.page); xs.push(op.index); ys.push(0); ws.push(0); hs.push(0); texts.push(op.newText); nums.push(op.newSize); counts.push(1);
    }
  }
  const task = new taskpool.Task(runEditOps, srcPath, outPath, newDoc, kinds, pages, xs, ys, ws, hs, texts, nums, counts);
  try {
    const result = await taskpool.execute(task) as string;
    if (result === 'ok') {
      return { success: true };
    }
    return { success: false, error: result };
  } catch (err) {
    const e = err as BusinessError;
    return { success: false, error: `taskpool: ${e.code}: ${e.message}` };
  }
}

export async function extractTextAsync(srcPath: string): Promise<string> {
  const task = new taskpool.Task(runExtractText, srcPath);
  try {
    const text = await taskpool.execute(task) as string;
    return text;
  } catch (err) {
    const e = err as BusinessError;
    console.error('extractText failed', JSON.stringify(e));
    return '';
  }
}

export interface TextObjectResult {
  ok: boolean;
  blocks: Array<TextBlockInfo>;
}

export interface PageSizeResult {
  ok: boolean;
  width: number;
  height: number;
}

export async function getPageSizeAsync(srcPath: string, pageIndex: number): Promise<PageSizeResult> {
  const task = new taskpool.Task(runGetPageSize, srcPath, pageIndex);
  try {
    const json = await taskpool.execute(task) as string;
    if (!json) {
      return { ok: false, width: 0, height: 0 };
    }
    const parsed = JSON.parse(json) as PageSizeData;
    return { ok: parsed.ok, width: parsed.width, height: parsed.height };
  } catch (err) {
    const e = err as BusinessError;
    console.error('getPageSize failed', JSON.stringify(e));
    return { ok: false, width: 0, height: 0 };
  }
}

interface PageSizeData {
  ok: boolean;
  width: number;
  height: number;
}

@Concurrent
function runGetPageSize(srcPath: string, pageIndex: number): string {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    const result = doc.loadDocument(srcPath, '');
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      const failed: PageSizeData = { ok: false, width: 0, height: 0 };
      return JSON.stringify(failed);
    }
    const count = doc.getPageCount();
    if (pageIndex < 0 || pageIndex >= count) {
      const failed: PageSizeData = { ok: false, width: 0, height: 0 };
      return JSON.stringify(failed);
    }
    const page = doc.getPage(pageIndex);
    const width = page.getWidth ? page.getWidth() : 595;
    const height = page.getHeight ? page.getHeight() : 842;
    const data: PageSizeData = { ok: true, width: width, height: height };
    return JSON.stringify(data);
  } catch (err) {
    console.error('runGetPageSize failed', JSON.stringify(err));
    const failed: PageSizeData = { ok: false, width: 0, height: 0 };
    return JSON.stringify(failed);
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

export async function listTextObjectsAsync(srcPath: string, pageIndex: number): Promise<TextObjectResult> {
  const task = new taskpool.Task(runListTextObjects, srcPath, pageIndex);
  try {
    const json = await taskpool.execute(task) as string;
    if (!json) {
      return { ok: false, blocks: [] };
    }
    const parsed = JSON.parse(json) as TextBlockListData;
    if (!parsed.ok) {
      return { ok: false, blocks: [] };
    }
    const blocks: Array<TextBlockInfo> = [];
    for (let i = 0; i < parsed.texts.length; i++) {
      const font = parsed.fonts[i];
      blocks.push({
        index: i,
        id: `${pageIndex}_${i}`,
        text: parsed.texts[i],
        size: parsed.sizes[i],
        x: parsed.xs[i],
        y: parsed.ys[i],
        width: parsed.ws[i],
        height: parsed.hs[i],
        fontName: font && font.length > 0 ? font : undefined
      } as TextBlockInfo);
    }
    return { ok: true, blocks: blocks };
  } catch (err) {
    const e = err as BusinessError;
    console.error('listTextObjects failed', JSON.stringify(e));
    return { ok: false, blocks: [] };
  }
}

interface TextBlockListData {
  ok: boolean;
  texts: string[];
  sizes: number[];
  xs: number[];
  ys: number[];
  ws: number[];
  hs: number[];
  fonts: string[];
}

@Concurrent
function runListTextObjects(srcPath: string, pageIndex: number): string {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    const result = doc.loadDocument(srcPath, '');
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      const failed: TextBlockListData = { ok: false, texts: [], sizes: [], xs: [], ys: [], ws: [], hs: [], fonts: [] };
      return JSON.stringify(failed);
    }
    const page = doc.getPage(pageIndex);
    const pageW = page.getWidth ? page.getWidth() : 595;
    const pageH = page.getHeight ? page.getHeight() : 842;
    const objs = page.getGraphicsObjects();
    const texts: string[] = [];
    const sizes: number[] = [];
    const xs: number[] = [];
    const ys: number[] = [];
    const ws: number[] = [];
    const hs: number[] = [];
    const fonts: string[] = [];
    for (const obj of objs) {
      if (obj.type === pdfService.GraphicsObjectType.OBJECT_TEXT) {
        const t = obj as pdfService.TextObject;
        texts.push(t.text);
        const size = t.textSize > 0 ? t.textSize : 12;
        sizes.push(size);
        const rects: Array<pdfService.PdfRect> = t.charRects;
        if (rects && rects.length > 0) {
          // PdfRect 各字段为「距对应页面边缘的距离」（doc 语义，P0 真机核验点）：
          // left=距左缘、right=距右缘、top=距上缘、bottom=距下缘。
          // 包围盒 = 取各方向距离的最小值，再换算为「距左下原点」的 x/y/w/h。
          let minL = Number.MAX_VALUE;
          let minR = Number.MAX_VALUE;
          let minT = Number.MAX_VALUE;
          let minB = Number.MAX_VALUE;
          for (const r of rects) {
            if (r.left < minL) {
              minL = r.left;
            }
            if (r.right < minR) {
              minR = r.right;
            }
            if (r.top < minT) {
              minT = r.top;
            }
            if (r.bottom < minB) {
              minB = r.bottom;
            }
          }
          xs.push(minL);
          ys.push(minB);
          ws.push(pageW - minR - minL);
          hs.push(pageH - minT - minB);
        } else {
          // 无 charRects 兜底：按字号估宽（每字符 ~0.72 字号宽），y 为基线距底
          const len = t.text.length > 0 ? t.text.length : 1;
          xs.push(t.x);
          ys.push(t.y);
          ws.push(len * (size * 0.72));
          hs.push(size * 1.2);
        }
        fonts.push(t.fontInfo && t.fontInfo.fontName ? t.fontInfo.fontName : '');
      }
    }
    const data: TextBlockListData = {
      ok: true, texts: texts, sizes: sizes, xs: xs, ys: ys, ws: ws, hs: hs, fonts: fonts
    };
    return JSON.stringify(data);
  } catch (err) {
    console.error('runListTextObjects failed', JSON.stringify(err));
    const failed: TextBlockListData = { ok: false, texts: [], sizes: [], xs: [], ys: [], ws: [], hs: [], fonts: [] };
    return JSON.stringify(failed);
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}

@Concurrent
function runExtractText(srcPath: string): string {
  let doc: pdfService.PdfDocument | null = null;
  try {
    doc = new pdfService.PdfDocument();
    const result = doc.loadDocument(srcPath, '');
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      return '';
    }
    let sb: string = '';
    const count = doc.getPageCount();
    for (let i = 0; i < count; i++) {
      const page = doc.getPage(i);
      sb += `\n--- 第 ${i + 1} 页 ---\n`;
      sb += page.getTextContent();
    }
    return sb;
  } catch (err) {
    console.error('runExtractText failed', JSON.stringify(err));
    return '';
  } finally {
    if (doc) {
      doc.releaseDocument();
    }
  }
}
