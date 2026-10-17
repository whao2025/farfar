import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { GlassTokens } from '../theme/GlassTokens';
import { FontMatcher } from '../layout/FontMatcher';
import { GlassToolbar } from '../components/GlassToolbar';
import { GlassButton } from '../components/GlassButton';
import { applyEditsAsync, EditOp, EditTextOp, EditImageOp, EditHighlightOp, EditTextAnnotOp, EditInsertBlankOp, EditDeletePageOp, EditMergeOp, EditRewriteTextOp, TextBlockInfo, TextObjectResult, listTextObjectsAsync, getPageSizeAsync } from '../utils/PDFEditUtils';
import { saveSandboxFile } from '../utils/PickerSaveUtils';
import { pickAndCopyPDF } from '../utils/PDFImportUtils';
import { addEditedFile } from '../utils/ImportLibrary';
import { PdfEditToolItem } from '../components/PdfEditToolItem';
import { RewriteSelectDialog } from '../components/RewriteSelectDialog';
import { RewriteEditDialog } from '../components/RewriteEditDialog';
import { RewriteUndoDialog, RewriteUndoEntry } from '../components/RewriteUndoDialog';
import { OCRService, createOCRService } from '../ocr/OCRService';
import { TextBlock, OCRResult, OCRProgress } from '../ocr/OCRTypes';

interface EditPageParams {
  filePath?: string;
  newDoc?: boolean;
}

interface PdfCoord {
  x: number;
  y: number;
}

const HIGHLIGHT_COLORS: number[] = [0xFFC300, 0xE0342C, 0x3B4C9B, 0x4E9E5F, 0xA79BC8, 0xCC5500];
const HIGHLIGHT_WIDTHS: number[] = [100, 150, 200, 300, 400];

@Entry
@Component
struct PDFEditPage {
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  @StorageProp('darkMode') dark: boolean = false;
  @State filePath: string = '';
  @State isNewDoc: boolean = false;
  @State pageCount: number = 0;
  @State currentPage: number = 0;
  @State loadResult: pdfService.ParseResult = pdfService.ParseResult.PARSE_ERROR_FORMAT
  @State saving: boolean = false;
  @State statusMsg: string = '';
  @State rewriteBlocks: Array<TextBlockInfo> = [];
  @State selectedIds: string[] = [];
  @State batchId: string = '';
  @State activedTool: number = -1;
  @State canUndo: boolean = false;
  @State rewritePanelOpen: boolean = false;
  @State rewriteInput: string = '';
  @State rewriteSizeExpanded: boolean = false;
  @State rewritePreviewTick: number = 0;
  @State rewritePreviews: Array<string> = [];
  private rewriteSize: string = '';
  @State showSelectDialog: boolean = false;
  @State showEditDialog: boolean = false;
  @State showUndoDialog: boolean = false;
  @State editText: string = '';
  @State editSizeText: string = '';
  @State editErrorMsg: string = '';
  @State undoEntries: Array<RewriteUndoEntry> = [];
  @State undoChecked: boolean[] = [];
  private undoBatchOps: EditRewriteTextOp[] = [];
  private undoBatchOpIndexes: number[] = [];
  private toastTimer: number = -1;
  @State highlightColor: number = 0xFFC300;
  @State highlightWidth: number = 200;
  @State overlayW: number = 0;
  @State overlayH: number = 0;
  @State pdfPageW: number = 595;
  @State pdfPageH: number = 842;
  @State selectedOpIndex: number = -1;
  @State opsCount: number = 0;
  @State objTick: number = 0;
  @State ocrMode: boolean = false;
  @State ocrBusy: boolean = false;
  @State ocrProgress: number = 0;
  @State ocrBlocks: TextBlock[] = [];
  private rewriteSelected: number = -1;
  private ops: EditOp[] = [];
  private ocrService: OCRService = createOCRService();
  private touchStartX: number = -1;
  private touchStartY: number = -1;
  private touchStartT: number = 0;
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private scrollParam: pdfViewManager.ScrollParam | null = null;

  private pushOp(op: EditOp): void {
    this.ops.push(op);
    this.opsCount = this.ops.length;
    this.canUndo = true;
    this.selectedOpIndex = -1;
  }

  private clearOps(): void {
    this.ops = [];
    this.opsCount = 0;
    this.canUndo = false;
    this.selectedOpIndex = -1;
  }

  private undoLastOp(): void {
    if (this.ops.length === 0) {
      this.canUndo = false;
      return;
    }
    const last = this.ops[this.ops.length - 1];
    const lastBatch = last.op === 'rewriteText' ? (last as EditRewriteTextOp).batchId : '';
    if (lastBatch && lastBatch.length > 0) {
      this.openBatchUndo(lastBatch);
      return;
    }
    const op = this.ops.pop();
    if (op && op.op === 'rewriteText') {
      const idx = this.rewriteBlocks.findIndex((b) => b.index === op.index);
      if (idx >= 0 && idx < this.rewritePreviews.length) {
        const arr: Array<string> = this.rewritePreviews.slice();
        arr[idx] = '';
        this.rewritePreviews = arr;
      }
      this.rewritePreviewTick = this.rewritePreviewTick + 1;
      this.statusMsg = '已撤回改字修改';
    } else {
      this.statusMsg = op ? '已撤回上一步操作' : '';
    }
    this.opsCount = this.ops.length;
    this.canUndo = this.ops.length > 0;
    this.selectedOpIndex = -1;
  }

  private openBatchUndo(batchId: string): void {
    const idxs: number[] = [];
    for (let i = 0; i < this.ops.length; i++) {
      const o = this.ops[i];
      if (o.op === 'rewriteText' && (o as EditRewriteTextOp).batchId === batchId) {
        idxs.push(i);
      }
    }
    if (idxs.length === 0) {
      return;
    }
    const entries: Array<RewriteUndoEntry> = [];
    for (let i = 0; i < idxs.length; i++) {
      const o = this.ops[idxs[i]] as EditRewriteTextOp;
      entries.push({
        page: o.page,
        newText: o.newText,
        origText: this.origTextOf(o.index)
      });
    }
    this.undoBatchOpIndexes = idxs;
    this.undoEntries = entries;
    this.undoChecked = new Array<boolean>(idxs.length).fill(true);
    this.showUndoDialog = true;
  }

  private origTextOf(blockIndex: number): string {
    const b = this.rewriteBlocks.find((x) => x.index === blockIndex);
    return b ? b.text : '';
  }

  private onToggleUndo(idx: number): void {
    const arr: boolean[] = this.undoChecked.slice();
    arr[idx] = !arr[idx];
    this.undoChecked = arr;
  }

  private onUndoSelectAll(): void {
    this.undoChecked = new Array<boolean>(this.undoEntries.length).fill(true);
  }

  private onUndoSelectNone(): void {
    this.undoChecked = new Array<boolean>(this.undoEntries.length).fill(false);
  }

  private onUndoCancel(): void {
    this.showUndoDialog = false;
  }

  private onUndoConfirm(): void {
    const remove: number[] = [];
    for (let i = 0; i < this.undoChecked.length; i++) {
      if (this.undoChecked[i] && i < this.undoBatchOpIndexes.length) {
        remove.push(this.undoBatchOpIndexes[i]);
      }
    }
    remove.sort((a: number, b: number) => b - a);
    for (let i = 0; i < remove.length; i++) {
      const o = this.ops[remove[i]];
      if (o && o.op === 'rewriteText') {
        const idx = this.rewriteBlocks.findIndex((b) => b.index === o.index);
        if (idx >= 0 && idx < this.rewritePreviews.length) {
          const arr: Array<string> = this.rewritePreviews.slice();
          arr[idx] = '';
          this.rewritePreviews = arr;
        }
      }
      this.ops.splice(remove[i], 1);
    }
    this.rewritePreviewTick = this.rewritePreviewTick + 1;
    this.showUndoDialog = false;
    this.opsCount = this.ops.length;
    this.canUndo = this.ops.length > 0;
    this.selectedOpIndex = -1;
    this.statusMsg = `已撤回 ${remove.length} 处改字修改`;
  }

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as EditPageParams;
    this.isNewDoc = params?.newDoc ?? false;
    this.filePath = params?.filePath ?? '';
    const hostCtx = this.getUIContext().getHostContext();
    if (hostCtx) {
      this.ocrService.configure(hostCtx as common.Context);
    }
    if (this.isNewDoc) {
      this.loadResult = pdfService.ParseResult.PARSE_SUCCESS;
      this.pageCount = 1;
    } else if (this.filePath) {
      this.loadPDF();
    }
  }

  aboutToDisappear(): void {
    if (!this.isNewDoc) {
      this.controller.releaseDocument();
    }
  }

  private loadPDF(): void {
    (async () => {
      this.registerListeners();
      try {
        this.loadResult = await this.controller.loadDocument(this.filePath, '', 0);
        if (this.loadResult === pdfService.ParseResult.PARSE_SUCCESS) {
          this.controller.setPageLayout(pdfService.PageLayout.LAYOUT_SINGLE);
          this.controller.setPageContinuous(false);
          this.controller.setPageFit(pdfService.PageFit.FIT_WIDTH);
          this.controller.registerScrollListener((param: pdfViewManager.ScrollParam) => {
            this.scrollParam = param;
          });
        }
      } catch (err) {
        console.error('edit loadDocument failed', JSON.stringify(err));
      }
    })();
  }

  private reloadPDF(): void {
    this.controller.releaseDocument();
    this.loadPDF();
  }

  private registerListeners(): void {
    this.controller.registerPageCountChangedListener((count: number) => {
      this.pageCount = count;
    });
    this.controller.registerPageChangedListener((pageIndex: number) => {
      this.currentPage = pageIndex;
      this.onPageChangedForRewrite();
    });
  }

  private onPageChangedForRewrite(): void {
    if (this.activedTool === 4) {
      this.activedTool = -1;
      this.showSelectDialog = false;
      this.showEditDialog = false;
      this.showUndoDialog = false;
      this.selectedIds = [];
      this.rewritePanelOpen = false;
      this.rewriteSelected = -1;
      this.rewritePreviews = [];
      this.rewriteBlocks = [];
      this.rewriteAsync();
    }
  }

  private showToast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (err) {
      console.error('showToast failed:', JSON.stringify(err));
    }
  }

  private showRewriteError(msg: string): void {
    this.toastDebounced('改字错误：' + msg);
  }

  private toastDebounced(msg: string): void {
    if (this.toastTimer >= 0) {
      return;
    }
    this.toastTimer = 1;
    this.showToast(msg);
    setTimeout(() => {
      this.toastTimer = -1;
    }, 300);
  }

  private dialogInput: string = '';
  private dialogOnConfirm: (value: string) => void = (v: string) => { };
  private dialogId: number = -1;

  @Builder
  private dialogContent(title: string, placeholder: string) {
    Column({ space: 12 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
      TextInput({ placeholder: placeholder })
        .onChange((v: string) => {
          this.dialogInput = v;
        })
      Row({ space: 12 }) {
        GlassButton({
          label: '取消', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 100,
          onClickHandler: () => {
            this.getUIContext().getPromptAction().closeCustomDialog(this.dialogId);
          }
        })
        GlassButton({
          label: '确定', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 100,
          onClickHandler: () => {
            const v = this.dialogInput;
            this.getUIContext().getPromptAction().closeCustomDialog(this.dialogId);
            this.dialogOnConfirm(v);
          }
        })
        }
      }
      .padding(24)
      .backgroundBlurStyle(GlassTokens.BLUR_MODAL)
      .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
.borderRadius(20)
    .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
  }

  @Builder
  private pickColorRow() {
    Row({ space: 10 }) {
      ForEach(HIGHLIGHT_COLORS, (c: number) => {
        Stack({ alignContent: Alignment.Center }) {
          if (c === this.highlightColor) {
            Circle({ width: 34, height: 34 })
              .fill(Color.Transparent)
              .stroke(Color.White)
              .strokeWidth(3)
          }
          Circle({ width: 28, height: 28 })
            .fill(c)
        }
        .width(34)
        .height(34)
        .onClick(() => {
          this.highlightColor = c;
        })
      }, (c: number) => `${c}`)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private rewriteBlockBox(block: TextBlockInfo, idx: number) {
    Stack() {
      Text(this.showRewriteText(block, idx))
        .fontSize(11)
        .fontColor(this.dark ? '#9EC6FF' : '#2A6FDB')
        .maxLines(1)
    }
    .position({ x: this.rewriteBlockPxX(block), y: this.rewriteBlockPxY(block) })
    .width(this.rewriteBlockPxW(block))
    .height(this.rewriteBlockPxH(block))
    .padding({ left: 4, right: 4 })
    .borderRadius(2)
    .border({ width: 1, color: this.rewriteSelected === block.index ? '#4C9AFF' : 'rgba(76,154,255,0.45)', style: BorderStyle.Dashed })
    .backgroundColor(this.rewriteSelected === block.index ? 'rgba(76,154,255,0.22)' : 'rgba(76,154,255,0.06)')
  }

  private rewriteBlockScale(): number {
    return this.ocrBlockScale();
  }

  private rewriteBlockPxX(block: TextBlockInfo): number {
    return block.x * this.rewriteBlockScale();
  }

  private rewriteBlockPxY(block: TextBlockInfo): number {
    const hpt = this.pageHeightPt();
    return (hpt - block.y - block.height) * this.rewriteBlockScale();
  }

  private rewriteBlockPxW(block: TextBlockInfo): number {
    return block.width * this.rewriteBlockScale();
  }

  private rewriteBlockPxH(block: TextBlockInfo): number {
    return block.height * this.rewriteBlockScale();
  }

  private showRewriteText(block: TextBlockInfo, idx: number): string {
    const preview = this.rewritePreviewText(idx);
    if (preview.length > 0) {
      return preview.length > 20 ? preview.substring(0, 20) + '…' : preview;
    }
    return block.text.length > 20 ? block.text.substring(0, 20) + '…' : block.text;
  }

  @Builder
  private rewriteEditPanel() {
    Column({ space: 12 }) {
      Text(`修改文字（第 ${this.currentPage + 1} 页 · ${this.rewriteBlocks.length} 块）`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
      if (this.rewriteSelected >= 0 && this.rewriteSelected < this.rewriteBlocks.length) {
        TextArea({ text: this.rewriteInput })
          .height(90)
          .width('100%')
          .fontSize(14)
          .onChange((v: string) => {
            this.rewriteInput = v;
          })
        if (this.rewriteSizeExpanded) {
          Row({ space: 8 }) {
            Text('字号')
              .fontSize(13)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            TextInput({ text: this.rewriteSizeValue() })
              .type(InputType.Number)
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .onChange((v: string) => {
                this.rewriteSize = v;
              })
          }
          .width('100%')
        } else {
          Text(`字号：沿用原文 ${this.rewriteSizeValue()}pt（点击上方「字号」可调整）`)
            .fontSize(12)
            .fontColor('#888888')
        }
        Text(this.rewriteFontHint())
          .fontSize(11)
          .fontColor(this.dark ? '#A9A9B5' : '#8A8A96')
      }
      Row({ space: 12 }) {
        GlassButton({
          label: '字号',
          dark: this.dark,
          heightVp: 40,
          fontSize: 14,
          widthVp: 90,
          onClickHandler: () => {
            this.rewriteSizeExpanded = !this.rewriteSizeExpanded;
          }
        })
        Blank()
        GlassButton({
          label: '取消',
          dark: this.dark,
          heightVp: 40,
          fontSize: 14,
          widthVp: 90,
          onClickHandler: () => {
            this.rewritePanelOpen = false;
            this.rewriteSelected = -1;
          }
        })
        GlassButton({
          label: '确定',
          dark: this.dark,
          heightVp: 40,
          fontSize: 14,
          widthVp: 90,
          onClickHandler: () => {
            this.confirmRewrite();
          }
        })
      }
      .width('100%')
      Button('收起')
        .fontSize(12)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
        .backgroundColor(Color.Transparent)
        .width(64)
        .onClick(() => {
          this.activedTool = -1;
        })
    }
    .padding(24)
    .width('92%')
    .backgroundBlurStyle(GlassTokens.BLUR_MODAL)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
    .borderRadius(20)
    .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
    .shadow(GlassTokens.SHADOW)
  }

  private confirmRewrite(): void {
    if (this.rewriteSelected < 0 || this.rewriteSelected >= this.rewriteBlocks.length) {
      return;
    }
    const block = this.rewriteBlocks[this.rewriteSelected];
    const newText = this.rewriteInput.trim();
    if (!newText) {
      this.showRewriteError('请输入文字内容');
      return;
    }
    let newSize = block.size;
    if (this.rewriteSizeExpanded) {
      const parsed = parseInt(this.rewriteSize, 10);
      if (!isNaN(parsed) && parsed > 0) {
        newSize = parsed;
      }
    }
    this.pushOp({
      op: 'rewriteText',
      page: this.currentPage,
      index: block.index,
      newText: newText,
      newSize: newSize
    } as EditRewriteTextOp);
    if (this.rewriteSelected >= 0 && this.rewriteSelected < this.rewritePreviews.length) {
      const arr: Array<string> = this.rewritePreviews.slice();
      arr[this.rewriteSelected] = newText;
      this.rewritePreviews = arr;
    }
    this.rewriteSelected = -1;
    this.rewritePanelOpen = false;
    this.rewriteSizeExpanded = false;
    this.rewritePreviewTick = this.rewritePreviewTick + 1;
    this.statusMsg = `已修改文字（保存后生效）`;
  }

  private rewritePreviewText(idx: number): string {
    const p = this.rewritePreviews[idx];
    return p && p.length > 0 ? p : '';
  }

  private rewriteFontHint(): string {
    if (this.rewriteSelected < 0 || this.rewriteSelected >= this.rewriteBlocks.length) {
      return '';
    }
    const font = this.rewriteBlocks[this.rewriteSelected].fontName;
    if (!font || font.trim().length === 0) {
      return '原字体未知，保存时回退系统字体 HarmonyOS Sans';
    }
    const matched = FontMatcher.matchFont(font);
    if (matched.fallback) {
      return `原字体「${font}」将尽量保留，必要时自动回退为系统字体`;
    }
    return `原字体：${font}（已匹配 ${matched.fontName}）`;
  }

  private rewriteSizeValue(): string {
    if (this.rewriteSelected >= 0 && this.rewriteSelected < this.rewriteBlocks.length) {
      return `${this.rewriteBlocks[this.rewriteSelected].size}`;
    }
    return '0';
  }

  private promptTextInput(title: string, placeholder: string, onConfirm: (value: string) => void): void {
    this.dialogInput = '';
    this.dialogOnConfirm = onConfirm;
    const uiCtx = this.getUIContext();
    uiCtx.getPromptAction().openCustomDialog({
      builder: () => {
        this.dialogContent(title, placeholder)
      },
      autoCancel: true
    }).then((id: number) => {
      this.dialogId = id;
    }).catch(() => {
      console.error('open dialog failed');
    });
  }

  private onAddText(): void {
    this.activedTool = 0;
    this.showToast('点击页面任意位置放置文本框');
  }

  private clamp01(v: number): number {
    if (v < 0) {
      return 0;
    }
    if (v > 1) {
      return 1;
    }
    return v;
  }

  // 唯一正确：px(屏幕, 相对 PdfView 左上, 含滚动) → PDF pt(距左, 距下)
  // 只用 ScrollParam + getPageZoom()。FIT_WIDTH 下 pdfWidth==viewWidth==W_pt*zoom。
  private screenToPdf(pxX: number, pxY: number, sp: pdfViewManager.ScrollParam, zoom: number): PdfCoord {
    const W_pt = sp.pdfWidth / zoom;
    const H_pt = sp.pdfHeight / zoom;
    const cx = pxX + sp.offsetX * sp.viewWidth;   // 内容坐标 px
    const cy = pxY + sp.offsetY * sp.viewHeight;
    const fx = this.clamp01(cx / sp.pdfWidth);    // 归一化 0..1
    const fy = this.clamp01(cy / sp.pdfHeight);
    const coord: PdfCoord = {
      x: W_pt * fx,          // 距左 pt
      y: H_pt * (1 - fy)     // 距下 pt（y 翻转）
    };
    return coord;
  }

  private onOverlayTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down && event.touches.length > 0) {
      const t = event.touches[0];
      this.touchStartX = t.x;
      this.touchStartY = t.y;
      this.touchStartT = Date.now();
    } else if (event.type === TouchType.Up && this.touchStartX >= 0 && event.touches.length > 0) {
      const t = event.touches[0];
      const dx = t.x - this.touchStartX;
      const dy = t.y - this.touchStartY;
      const dt = Date.now() - this.touchStartT;
      const dist = Math.sqrt(dx * dx + dy * dy);
      this.touchStartX = -1;
      this.touchStartY = -1;
      if (dist > 10 || dt > 500) {
        return;
      }
      const sp = this.scrollParam;
      if (!sp || sp.pdfWidth <= 0 || sp.pdfHeight <= 0) {
        return;
      }
      if (this.activedTool === 4) {
        this.onRewriteBlockTap(t.x, t.y);
        return;
      }
      const pos = this.screenToPdf(t.x, t.y, sp, this.controller.getPageZoom());
      this.placeAt(pos.x, pos.y);
    }
  }

  private pageHeightPt(): number {
    const sp = this.scrollParam;
    if (sp && sp.pdfHeight > 0) {
      const zoom = this.controller.getPageZoom();
      if (zoom > 0) {
        return sp.pdfHeight / zoom;
      }
    }
    return this.pdfPageH;
  }

  private pageWidthPt(): number {
    const sp = this.scrollParam;
    if (sp && sp.pdfWidth > 0) {
      const zoom = this.controller.getPageZoom();
      if (zoom > 0) {
        return sp.pdfWidth / zoom;
      }
    }
    return this.pdfPageW;
  }

  private scalePx(): number {
    const wpt = this.pageWidthPt();
    return wpt > 0 ? this.overlayW / wpt : 1;
  }

  private opRect(index: number): PdfCoord {
    const op = this.ops[index];
    if (!op) {
      return { x: 0, y: 0 };
    }
    const s = this.scalePx();
    const hpt = this.pageHeightPt();
    const size = this.opPdfSize(index);
    if (op.op === 'addText') {
      return { x: op.x * s, y: (hpt - op.y) * s - size.y * s };
    }
    if (op.op === 'addImage') {
      return { x: op.x * s, y: (hpt - op.y) * s - size.y * s };
    }
    if (op.op === 'addHighlight') {
      return { x: op.x * s, y: (hpt - op.y) * s - size.y * s };
    }
    if (op.op === 'addTextAnnot') {
      return { x: op.x * s, y: (hpt - op.y) * s - size.y * s };
    }
    return { x: 0, y: 0 };
  }

  private opSize(index: number): PdfCoord {
    const s = this.scalePx();
    const size = this.opPdfSize(index);
    return { x: size.x * s, y: size.y * s };
  }

  private opPdfSize(index: number): PdfCoord {
    const op = this.ops[index];
    if (!op) {
      return { x: 0, y: 0 };
    }
    if (op.op === 'addText') {
      const t = (op as EditTextOp).text;
      const len = t.length > 0 ? t.length : 1;
      return { x: len * 8, y: 20 };
    }
    if (op.op === 'addImage') {
      return { x: (op as EditImageOp).width, y: (op as EditImageOp).height };
    }
    if (op.op === 'addHighlight') {
      return { x: 200, y: 30 };
    }
    if (op.op === 'addTextAnnot') {
      const c = (op as EditTextAnnotOp).content;
      const len = c.length > 0 ? c.length : 1;
      return { x: len * 10, y: 24 };
    }
    return { x: 0, y: 0 };
  }

  private onObjDragStart(index: number, x: number, y: number): void {
    this.selectedOpIndex = index;
    this.dragStartX = x;
    this.dragStartY = y;
  }

  private onObjDragMove(index: number, x: number, y: number): void {
    if (this.selectedOpIndex !== index) {
      return;
    }
    const op = this.ops[index];
    if (!op) {
      return;
    }
    const s = this.scalePx();
    if (s <= 0) {
      return;
    }
    const dx = (x - this.dragStartX) / s;
    const dy = (y - this.dragStartY) / s;
    this.dragStartX = x;
    this.dragStartY = y;
    if (op.op === 'addText') {
      op.x = op.x + dx;
      op.y = op.y - dy;
    } else if (op.op === 'addImage') {
      op.x = op.x + dx;
      op.y = op.y - dy;
    } else if (op.op === 'addHighlight') {
      op.x = op.x + dx;
      op.y = op.y - dy;
    } else if (op.op === 'addTextAnnot') {
      op.x = op.x + dx;
      op.y = op.y - dy;
    } else {
      return;
    }
    this.objTick = this.objTick + 1;
  }

  private onObjResize(index: number, x: number, y: number): void {
    const op = this.ops[index];
    if (!op || op.op !== 'addImage') {
      return;
    }
    const s = this.scalePx();
    if (s <= 0) {
      return;
    }
    const rect = this.opRect(index);
    const dx = (x - rect.x) / s;
    const dy = (rect.y - y) / s;
    const minW = 40;
    const minH = 40;
    if (dx >= minW) {
      (op as EditImageOp).width = dx;
    }
    if (dy >= minH) {
      (op as EditImageOp).height = dy;
    }
    this.objTick = this.objTick + 1;
  }

  private async pickImage(): Promise<string> {
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      return '';
    }
    const context = ctx as common.Context;
    let src: image.ImageSource | null = null;
    let pm: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await photoPicker.select(options);
      if (!result.photoUris || result.photoUris.length === 0) {
        return '';
      }
      const uri = result.photoUris[0];
      src = await image.createImageSource(uri);
      pm = await src.createPixelMap();
      packer = image.createImagePacker();
      const packOptions: image.PackingOption = {
        format: 'image/png',
        quality: 90
      };
      const data = await packer.packToData(pm, packOptions);
      const sandboxPath = context.filesDir + '/edit_img_' + Date.now() + '.png';
      let dstFd: number = 0;
      try {
        const dst = await fileIo.open(sandboxPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        dstFd = dst.fd;
        await fileIo.write(dstFd, data);
      } finally {
        if (dstFd !== 0) {
          await fileIo.close(dstFd);
        }
      }
      return sandboxPath;
    } catch (err) {
      console.error('pick image failed', JSON.stringify(err));
      return '';
    } finally {
      if (packer) {
        try {
          await packer.release();
        } catch (err) {
        }
      }
      if (pm) {
        try {
          await pm.release();
        } catch (err) {
        }
      }
      if (src) {
        try {
          await src.release();
        } catch (err) {
        }
      }
    }
  }

  @Builder
  sessionObjectBox(index: number) {
    Stack() {
      if (this.selectedOpIndex === index) {
        Stack()
          .width('100%')
          .height('100%')
          .border({ width: 2, color: '#4C9AFF' })
      }
      if (this.ops[index] !== undefined && (this.ops[index] as EditOp).op === 'addImage' && this.selectedOpIndex === index) {
        Stack()
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor('#4C9AFF')
          .position({ x: '100%', y: '100%' })
          .translate({ x: -10, y: -10 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Move && event.touches.length > 0) {
              const t = event.touches[0];
              this.onObjResize(index, t.x, t.y);
            }
          })
      }
    }
    .position({ x: this.opRect(index).x, y: this.opRect(index).y })
    .width(this.opSize(index).x)
    .height(this.opSize(index).y)
    .borderRadius(4)
    .opacity(this.objTick >= 0 ? 1 : 1)
    .border({ width: 1, color: this.selectedOpIndex === index ? '#4C9AFF' : 'rgba(76,154,255,0.4)' })
    .backgroundColor('rgba(76,154,255,0.08)')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down && event.touches.length > 0) {
        const t = event.touches[0];
        this.onObjDragStart(index, t.x, t.y);
      } else if (event.type === TouchType.Move && event.touches.length > 0) {
        const t = event.touches[0];
        this.onObjDragMove(index, t.x, t.y);
      }
    })
  }

  private pageLabel(): string {
    let base = this.isNewDoc ? '新建 PDF'
      : (this.pageCount > 0 ? `${this.currentPage + 1} / ${this.pageCount}` : '加载中');
    if (this.opsCount > 0) {
      base = base + ` · ${this.opsCount}步`;
    }
    return base;
  }

  private sessionOpIndexes(): number[] {
    const res: number[] = [];
    for (let i = 0; i < this.ops.length; i++) {
      const op = this.ops[i];
      if (op.op === 'addText' || op.op === 'addImage' || op.op === 'addHighlight' || op.op === 'addTextAnnot') {
        res.push(i);
      }
    }
    return res;
  }

  private placeAt(x: number, y: number): void {
    const page = this.currentPage;
    switch (this.activedTool) {
      case 0: {
        this.promptTextInput('输入文本内容', '', (text: string) => {
          if (!text.trim()) {
            return;
          }
          const op: EditTextOp = {
            op: 'addText',
            page: page,
            x: x,
            y: y,
            size: 16,
            color: this.dark ? 0xF2F2F7 : 0x1A1A1F,
            text: text
          };
          this.pushOp(op);
          this.selectLastOp();
          this.promptTextInput('修改字号（pt，默认16）', '16', (sizeValue: string) => {
            const newSize = parseInt(sizeValue, 10);
            if (isNaN(newSize) || newSize <= 0) {
              return;
            }
            (op as EditTextOp).size = newSize;
            this.objTick = this.objTick + 1;
          });
          this.statusMsg = `已添加文本到第 ${page + 1} 页（保存后生效）`;
        });
        break;
      }
      case 1: {
        this.pickImage().then((path: string) => {
          if (!path) {
            this.showToast('未选择图片');
            this.activedTool = -1;
            return;
          }
          const op: EditImageOp = {
            op: 'addImage',
            page: page,
            x: x,
            y: y,
            width: 200,
            height: 200,
            imagePath: path
          };
          this.pushOp(op);
          this.selectLastOp();
          this.statusMsg = `已添加图片到第 ${page + 1} 页（保存后生效）`;
        });
        break;
      }
      case 2: {
        const op: EditHighlightOp = {
          op: 'addHighlight',
          page: page,
          x: x,
          y: y,
          width: this.highlightWidth,
          height: 30,
          color: this.highlightColor
        };
        this.pushOp(op);
        this.selectLastOp();
        break;
      }
      case 3: {
        this.promptTextInput('输入标注内容', '', (content: string) => {
          if (!content.trim()) {
            return;
          }
          const op: EditTextAnnotOp = {
            op: 'addTextAnnot',
            page: page,
            x: x,
            y: y,
            content: content,
            color: 0x1A1A1F
          };
          this.pushOp(op);
          this.selectLastOp();
          this.statusMsg = `已添加标注到第 ${page + 1} 页（保存后生效）`;
        });
        break;
      }
      default:
        return;
    }
    if (this.activedTool === 2) {
      this.statusMsg = `已添加，保存后生效（第 ${page + 1} 页）`;
    }
  }

  private selectLastOp(): void {
    this.activedTool = -1;
    this.selectedOpIndex = this.ops.length - 1;
  }

  private onOcrMode(): void {
    this.activedTool = -1;
    this.ocrMode = true;
    this.ocrBlocks = [];
    this.ocrBusy = true;
    this.ocrProgress = 0;
    this.showToast('正在识别当前页…');
    this.runOcr();
  }

  private exitOcrMode(): void {
    this.ocrMode = false;
    this.ocrBusy = false;
    this.ocrBlocks = [];
  }

  private async runOcr(): Promise<void> {
    if (!this.filePath) {
      this.ocrBusy = false;
      this.showToast('请先打开 PDF 文件');
      return;
    }
    const result: OCRResult = await this.ocrService.recognize(this.filePath, {
      startPage: this.currentPage,
      endPage: this.currentPage
    }, (p: OCRProgress) => {
      this.ocrProgress = p.percent;
    });
    if (result.pages.length > 0) {
      this.ocrBlocks = result.pages[0].blocks;
      this.statusMsg = `识别到 ${this.ocrBlocks.length} 个文本块，点击块可修改`;
    } else {
      this.statusMsg = '未识别到文本';
    }
    this.ocrBusy = false;
  }

  private onOcrBlockTap(block: TextBlock, x: number, y: number): void {
    const sp = this.scrollParam;
    if (!sp || sp.pdfWidth <= 0 || sp.pdfHeight <= 0) {
      return;
    }
    const pos = this.screenToPdf(x, y, sp, this.controller.getPageZoom());
    this.promptTextInput('编辑文本（点击页放置）', block.text, (value: string) => {
      if (!value.trim()) {
        return;
      }
      const op: EditTextOp = {
        op: 'addText',
        page: this.currentPage,
        text: value,
        x: pos.x,
        y: pos.y,
        size: Math.max(10, block.fontSize),
        color: this.dark ? 0xF2F2F7 : 0x1A1A1F
      };
      this.pushOp(op);
      this.statusMsg = `已添加文本到第 ${this.currentPage + 1} 页（保存后生效）`;
    });
  }

  @Builder
  ocrBlockBox(block: TextBlock, index: number) {
    Stack() {
      Text(block.text.length > 20 ? block.text.substring(0, 20) + '…' : block.text)
        .fontSize(11)
        .fontColor(this.dark ? '#9EC6FF' : '#2A6FDB')
        .maxLines(1)
    }
    .position({ x: this.ocrBlockPxX(block), y: this.ocrBlockPxY(block) })
    .width(this.ocrBlockPxW(block))
    .height(this.ocrBlockPxH(block))
    .padding({ left: 4, right: 4 })
    .borderRadius(2)
    .border({ width: 1, color: '#4C9AFF' })
    .backgroundColor('rgba(76,154,255,0.10)')
    .onClick(() => {
      this.onOcrBlockTap(block, this.ocrBlockCenterX(block), this.ocrBlockCenterY(block));
    })
  }

  private ocrBlockScale(): number {
    const wpt = this.pageWidthPt();
    return wpt > 0 ? this.overlayW / wpt : 1;
  }

  private ocrBlockPxX(block: TextBlock): number {
    return block.x * this.ocrBlockScale();
  }

  private ocrBlockPxY(block: TextBlock): number {
    const hpt = this.pageHeightPt();
    const s = this.ocrBlockScale();
    return (hpt - block.y - block.height) * s;
  }

  private ocrBlockPxW(block: TextBlock): number {
    return block.width * this.ocrBlockScale();
  }

  private ocrBlockPxH(block: TextBlock): number {
    return block.height * this.ocrBlockScale();
  }

  private ocrBlockCenterX(block: TextBlock): number {
    return block.x * this.ocrBlockScale() + (block.width * this.ocrBlockScale()) / 2;
  }

  private ocrBlockCenterY(block: TextBlock): number {
    return (this.pageHeightPt() - block.y - block.height / 2) * this.ocrBlockScale();
  }

  private onAddImage(): void {
    this.activedTool = 1;
    this.showToast('点击页面任意位置放置图片');
  }

  private onAddHighlight(): void {
    this.activedTool = 2;
    this.showToast('点击页面任意位置添加高亮');
  }

  private onAddTextAnnot(): void {
    this.activedTool = 3;
    this.showToast('点击页面任意位置添加标注');
  }

  private onInsertPage(): void {
    this.activedTool = 5;
    this.insertPageAsync();
  }

  private async insertPageAsync(): Promise<void> {
    if (this.isNewDoc || !this.filePath) {
      this.pushOp({
        op: 'insertBlankPage',
        index: this.currentPage + 1,
        width: 595,
        height: 842
      } as EditInsertBlankOp);
      this.statusMsg = '已插入空白页（保存后生效）';
      return;
    }
    const size = await getPageSizeAsync(this.filePath, this.currentPage);
    const w = size.ok && size.width > 0 ? size.width : 595;
    const h = size.ok && size.height > 0 ? size.height : 842;
    this.pushOp({
      op: 'insertBlankPage',
      index: this.currentPage + 1,
      width: w,
      height: h
    } as EditInsertBlankOp);
    this.statusMsg = '已插入空白页（保存后生效）';
  }

  private onDeletePage(): void {
    this.activedTool = 6;
    if (this.pageCount <= 1) {
      this.showToast('至少保留一页');
      return;
    }
    this.pushOp({
      op: 'deletePage',
      index: this.currentPage
    } as EditDeletePageOp);
    this.statusMsg = `已删除第 ${this.currentPage + 1} 页（保存后生效）`;
  }

  private onRewriteText(): void {
    if (this.activedTool === 4) {
      this.activedTool = -1;
      this.rewriteBlocks = [];
      this.rewriteSelected = -1;
      this.rewritePanelOpen = false;
      this.showSelectDialog = false;
      this.showEditDialog = false;
      this.showUndoDialog = false;
      this.selectedIds = [];
      return;
    }
    this.activedTool = 4;
    this.rewriteSelected = -1;
    this.rewritePanelOpen = false;
    this.rewriteInput = '';
    this.rewriteSize = '';
    this.rewriteSizeExpanded = false;
    this.showSelectDialog = false;
    this.showEditDialog = false;
    this.showUndoDialog = false;
    this.selectedIds = [];
    this.rewriteAsync();
  }

  private async rewriteAsync(): Promise<void> {
    if (!this.filePath) {
      this.activedTool = -1;
      this.showRewriteError('请先打开一个 PDF 文件');
      return;
    }
    try {
      const result: TextObjectResult = await listTextObjectsAsync(this.filePath, this.currentPage);
      if (!result.ok) {
        this.activedTool = -1;
        this.showRewriteError('读取文本块失败（文件可能已损坏）');
        return;
      }
      if (result.blocks.length === 0) {
        this.activedTool = -1;
        this.showRewriteError('此页无文本或为扫描版，无法修改');
        return;
      }
      this.rewriteBlocks = result.blocks;
      this.rewritePreviews = new Array<string>(result.blocks.length);
      this.selectedIds = [];
      this.statusMsg = `共 ${result.blocks.length} 个文本块，请选择要修改的文字`;
      if (this.activedTool === 4) {
        this.showSelectDialog = true;
      }
    } catch (err) {
      this.activedTool = -1;
      console.error('list text blocks failed', JSON.stringify(err));
      this.showRewriteError('解析文本块异常，请重试');
    }
  }

  private onToggleBlock(id: string): void {
    const idx = this.selectedIds.indexOf(id);
    if (idx >= 0) {
      const arr: string[] = this.selectedIds.slice();
      arr.splice(idx, 1);
      this.selectedIds = arr;
    } else {
      const arr: string[] = this.selectedIds.slice();
      arr.push(id);
      this.selectedIds = arr;
    }
  }

  private onSelectAll(): void {
    const arr: string[] = [];
    for (let i = 0; i < this.rewriteBlocks.length; i++) {
      arr.push(this.rewriteBlocks[i].id);
    }
    this.selectedIds = arr;
  }

  private onSelectNone(): void {
    this.selectedIds = [];
  }

  private onSelectConfirm(): void {
    if (this.selectedIds.length === 0) {
      this.showRewriteError('请至少选择一个文本块');
      return;
    }
    this.showSelectDialog = false;
    this.prepareEditDialog();
  }

  private onSelectCancel(): void {
    this.showSelectDialog = false;
  }

  private firstSelectedBlock(): TextBlockInfo | null {
    if (this.selectedIds.length === 0 || this.rewriteBlocks.length === 0) {
      return null;
    }
    const firstId = this.selectedIds[0];
    for (let i = 0; i < this.rewriteBlocks.length; i++) {
      if (this.rewriteBlocks[i].id === firstId) {
        return this.rewriteBlocks[i];
      }
    }
    return null;
  }

  private prepareEditDialog(): void {
    const first = this.firstSelectedBlock();
    if (!first) {
      return;
    }
    this.editText = first.text;
    this.editSizeText = `${first.size}`;
    this.editErrorMsg = '';
    this.showEditDialog = true;
  }

  private onEditCancel(): void {
    this.showEditDialog = false;
  }

  private onEditConfirm(): void {
    const newText = this.editText.trim();
    if (!newText) {
      this.editErrorMsg = '改字错误：请输入新的文字内容';
      return;
    }
    let newSize = 0;
    if (this.editSizeText.trim().length === 0) {
      newSize = 0;
    } else {
      const parsed = parseInt(this.editSizeText, 10);
      if (isNaN(parsed) || parsed <= 0) {
        this.editErrorMsg = '改字错误：字号必须为正整数';
        return;
      }
      newSize = parsed;
    }
    this.applyBatchRewrite(newText, newSize);
  }

  private applyBatchRewrite(newText: string, newSize: number): void {
    const batch = 'b' + Date.now().toString();
    this.batchId = batch;
    const blocks: Array<TextBlockInfo> = [];
    for (let i = 0; i < this.rewriteBlocks.length; i++) {
      if (this.selectedIds.indexOf(this.rewriteBlocks[i].id) >= 0) {
        blocks.push(this.rewriteBlocks[i]);
      }
    }
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      const op: EditRewriteTextOp = {
        op: 'rewriteText',
        page: this.currentPage,
        index: block.index,
        newText: newText,
        newSize: newSize > 0 ? newSize : block.size,
        batchId: batch
      };
      this.pushOp(op);
    }
    const previews: Array<string> = this.rewritePreviews.slice();
    for (let i = 0; i < blocks.length; i++) {
      const bi = this.rewriteBlocks.findIndex((b) => b.id === blocks[i].id);
      if (bi >= 0 && bi < previews.length) {
        previews[bi] = newText;
      }
    }
    this.rewritePreviews = previews;
    this.rewritePreviewTick = this.rewritePreviewTick + 1;
    this.showEditDialog = false;
    this.selectedIds = [];
    this.statusMsg = `已批量修改 ${blocks.length} 处文字（保存后生效）`;
  }

  private onRewriteBlockTap(x: number, y: number): void {
    const sp = this.scrollParam;
    if (!sp || sp.pdfWidth <= 0 || sp.pdfHeight <= 0) {
      return;
    }
    const pos = this.screenToPdf(x, y, sp, this.controller.getPageZoom());
    let hit = -1;
    for (let i = 0; i < this.rewriteBlocks.length; i++) {
      const b = this.rewriteBlocks[i];
      if (pos.x >= b.x && pos.x <= b.x + b.width && pos.y >= b.y && pos.y <= b.y + b.height) {
        hit = i;
        break;
      }
    }
    if (hit < 0) {
      this.showRewriteError('未命中文本块，请点击文字区域');
      return;
    }
    this.rewriteSelected = hit;
    this.rewriteInput = this.rewriteBlocks[hit].text;
    this.rewriteSize = `${this.rewriteBlocks[hit].size}`;
    this.rewriteSizeExpanded = false;
    this.rewritePanelOpen = true;
  }

  private onMergePDF(): void {
    this.activedTool = 7;
    this.mergeAsync();
  }

  private async mergeAsync(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      return;
    }
    const context = ctx as common.Context;
    const srcPath = await pickAndCopyPDF(context);
    if (!srcPath) {
      return;
    }
    this.pushOp({
      op: 'mergePages',
      srcPath: srcPath,
      srcStart: 0,
      srcCount: 100000,
      dstIndex: this.pageCount
    } as EditMergeOp);
    this.statusMsg = '已追加合并的 PDF 页（保存后生效）';
  }

  private onSave(): void {
    if (this.saving) {
      return;
    }
    this.saving = true;
    this.saveAsync();
  }

  private async saveAsync(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      this.saving = false;
      return;
    }
    const context = ctx as common.Context;
    const outPath = context.filesDir + '/edited_' + Date.now() + '.pdf';
    try {
        const result = await applyEditsAsync(this.filePath, outPath, this.ops, this.isNewDoc);
        if (!result.success) {
          this.showToast('保存失败：' + (result.error ?? '未知错误'));
          this.saving = false;
          return;
        }
        const baseName = this.isNewDoc ? '新文档.pdf' : this.currentFileName(outPath);
        const newPath = await addEditedFile(context, outPath, baseName);
        this.filePath = newPath;
        this.isNewDoc = false;
        this.reloadPDF();
        const saved = await saveSandboxFile(context, newPath, baseName, '.pdf');
        if (saved) {
          this.showToast('已保存并导出');
        } else {
          this.showToast('已保存到最近文档');
        }
        this.bumpRefresh();
        this.clearOps();
        this.activedTool = -1;
        this.rewriteBlocks = [];
        this.rewriteSelected = -1;
        this.rewritePanelOpen = false;
        this.statusMsg = '';
      } catch (err) {
        const e = err as BusinessError;
        console.error('save edit failed', JSON.stringify(e));
        this.showToast('保存失败');
      } finally {
        this.saving = false;
      }
  }

  private currentFileName(fallback: string): string {
    const src = this.filePath;
    if (src) {
      const name = src.split('/').pop();
      if (name) {
        return name;
      }
    }
    return 'edited.pdf';
  }

  private bumpRefresh(): void {
    const tick = (AppStorage.get<number>('recentRefreshTick') ?? 0) as number;
    AppStorage.setOrCreate('recentRefreshTick', tick + 1);
  }

  build() {
    Column() {
      GlassToolbar({ dark: this.dark }) {
        Row({ space: 8 }) {
          GlassButton({
            label: '撤回',
            dark: this.dark,
            onClickHandler: () => {
              if (this.canUndo) {
                this.undoLastOp();
              } else {
                const router = this.getUIContext().getRouter();
                if (router.getStackSize() > 1) {
                  router.back();
                } else {
                  router.back(-1);
                }
              }
            },
            heightVp: 40,
            fontSize: 14,
            widthVp: 64
          })
          Text(this.pageLabel())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .fontSize(14)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : '#666666')
          GlassButton({
            label: this.saving ? '保存中…' : '保存',
            dark: this.dark,
            onClickHandler: () => this.onSave(),
            heightVp: 40,
            fontSize: 14,
            widthVp: 64
          })
        }
        .width('100%')
      }

      if (this.statusMsg) {
        Text(this.statusMsg)
          .fontSize(12)
          .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      }

      if (this.isNewDoc) {
        Column() {
          Text('空白文档（A4）\n请使用下方工具添加文本与图片')
            .fontSize(15)
            .textAlign(TextAlign.Center)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : '#666666')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.loadResult === pdfService.ParseResult.PARSE_SUCCESS) {
        Stack() {
          PdfView({
            controller: this.controller,
            pageFit: pdfService.PageFit.FIT_WIDTH,
            showScroll: true
          })
            .width('100%')
            .height('100%')

          if (this.ocrMode) {
            if (this.ocrBusy) {
              Column() {
                Text(`识别中 ${this.ocrProgress}%`)
                  .fontSize(14)
                  .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            } else {
              ForEach(this.ocrBlocks, (block: TextBlock, idx: number) => {
                this.ocrBlockBox(block, idx)
              }, (block: TextBlock, idx: number) => block.id + '_' + idx.toString())
            }
          } else if (this.activedTool >= 0 && this.activedTool <= 4) {
            if (this.activedTool === 4) {
              Stack() {
                ForEach(this.rewriteBlocks, (block: TextBlockInfo, idx: number) => {
                  this.rewriteBlockBox(block, idx)
                }, (block: TextBlockInfo, idx: number) => block.id)
                if (this.rewritePanelOpen) {
                  this.rewriteEditPanel()
                }
                if (this.showSelectDialog) {
                  RewriteSelectDialog({
                    blocks: this.rewriteBlocks,
                    selectedIds: this.selectedIds,
                    dark: this.dark,
                    onToggle: (id: string) => this.onToggleBlock(id),
                    onSelectAll: () => this.onSelectAll(),
                    onSelectNone: () => this.onSelectNone(),
                    onConfirm: () => this.onSelectConfirm(),
                    onCancel: () => this.onSelectCancel()
                  })
                }
                if (this.showEditDialog) {
                  RewriteEditDialog({
                    block: this.firstSelectedBlock(),
                    text: this.editText,
                    sizeText: this.editSizeText,
                    dark: this.dark,
                    errorMsg: this.editErrorMsg,
                    onTextChange: (v: string) => { this.editText = v; },
                    onEditSizeChange: (v: string) => { this.editSizeText = v; },
                    onConfirm: () => this.onEditConfirm(),
                    onCancel: () => this.onEditCancel()
                  })
                }
                if (this.showUndoDialog) {
                  RewriteUndoDialog({
                    entries: this.undoEntries,
                    selected: this.undoChecked,
                    dark: this.dark,
                    onToggle: (idx: number) => this.onToggleUndo(idx),
                    onSelectAll: () => this.onUndoSelectAll(),
                    onSelectNone: () => this.onUndoSelectNone(),
                    onConfirm: () => this.onUndoConfirm(),
                    onCancel: () => this.onUndoCancel()
                  })
                }
              }
              .width('100%')
              .height('100%')
              .alignContent(Alignment.Bottom)
              .backgroundColor(Color.Transparent)
              .onAreaChange((oldArea: Area, newArea: Area) => {
                this.overlayW = Number(newArea.width);
                this.overlayH = Number(newArea.height);
              })
              .onTouch((event: TouchEvent) => {
                if (this.rewritePanelOpen || this.showSelectDialog || this.showEditDialog || this.showUndoDialog) {
                  return;
                }
                this.onOverlayTouch(event);
              })
            } else {
            Column() {
              if (this.activedTool === 2) {
                Column({ space: 8 }) {
                  this.pickColorRow()
                  Row({ space: 8 }) {
                    ForEach(HIGHLIGHT_WIDTHS, (w: number) => {
                      Text(`${w}`)
                        .fontSize(12)
                        .fontColor(this.highlightWidth === w
                          ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
                          : '#8A8A96')
                        .fontWeight(this.highlightWidth === w ? FontWeight.Bold : FontWeight.Normal)
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .borderRadius(12)
                        .backgroundColor(this.highlightWidth === w
                          ? (this.dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.08)')
                          : Color.Transparent)
                        .onClick(() => {
                          this.highlightWidth = w;
                        })
                    }, (w: number) => `${w}`)
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                }
                .width('100%')
                .padding({ top: 12, bottom: 8 })
              }
            }
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .onAreaChange((oldArea: Area, newArea: Area) => {
              this.overlayW = Number(newArea.width);
              this.overlayH = Number(newArea.height);
            })
            .onTouch((event: TouchEvent) => {
              this.onOverlayTouch(event);
            })
            }
          } else {
            ForEach(this.sessionOpIndexes(), (index: number) => {
              this.sessionObjectBox(index)
            }, (index: number) => index.toString())
          }
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        Column() {
          Text('无法解析 PDF 文件')
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : '#666666')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }

      Scroll() {
        Row({ space: 8 }) {
          PdfEditToolItem({ label: '文本', icon: $r('sys.symbol.character_textbox'), dark: this.dark, actived: this.activedTool === 0, onClickHandler: () => this.onAddText() })
          PdfEditToolItem({ label: '图片', icon: $r('sys.symbol.picture_fill'), dark: this.dark, actived: this.activedTool === 1, onClickHandler: () => this.onAddImage() })
          PdfEditToolItem({ label: '高亮', icon: $r('sys.symbol.highlighter_line'), dark: this.dark, actived: this.activedTool === 2, onClickHandler: () => this.onAddHighlight() })
          PdfEditToolItem({ label: '标注', icon: $r('sys.symbol.square_and_pencil_fill'), dark: this.dark, actived: this.activedTool === 3, onClickHandler: () => this.onAddTextAnnot() })
          PdfEditToolItem({ label: '改字', icon: $r('sys.symbol.character_arrow_2_circlepath'), dark: this.dark, actived: this.activedTool === 4, onClickHandler: () => this.onRewriteText() })
          PdfEditToolItem({ label: '插页', icon: $r('sys.symbol.plus_circle'), dark: this.dark, actived: this.activedTool === 5, onClickHandler: () => this.onInsertPage() })
          PdfEditToolItem({ label: '删页', icon: $r('sys.symbol.trash_fill'), dark: this.dark, actived: this.activedTool === 6, onClickHandler: () => this.onDeletePage() })
          PdfEditToolItem({ label: '合并', icon: $r('sys.symbol.rectangle_on_rectangle_fill'), dark: this.dark, actived: this.activedTool === 7, onClickHandler: () => this.onMergePDF() })
          PdfEditToolItem({ label: 'OCR', icon: $r('sys.symbol.doc'), dark: this.dark, actived: this.ocrMode, onClickHandler: () => {
            if (this.ocrMode) {
              this.exitOcrMode();
            } else {
              this.onOcrMode();
            }
          } })
        }
        .padding({ left: 12, right: 12, top: 10, bottom: 18 })
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
      .backgroundColor(this.dark ? 'rgba(30,30,42,0.65)' : 'rgba(255,255,255,0.6)')
      .borderRadius({ topLeft: 20, topRight: 20 })
      .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
      .shadow(GlassTokens.SHADOW)
    }
    .width('100%')
    .height('100%')
    .backgroundBlurStyle(GlassTokens.BLUR)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
  }
}
