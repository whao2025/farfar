import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassToolbar } from '../components/GlassToolbar';
import { GlassButton } from '../components/GlassButton';
import { applyEditsAsync, EditOp, EditTextOp, EditImageOp, EditHighlightOp, EditTextAnnotOp, EditInsertBlankOp, EditDeletePageOp, EditMergeOp, EditRewriteTextOp, TextBlockInfo, TextObjectResult, listTextObjectsAsync, getPageSizeAsync } from '../utils/PDFEditUtils';
import { saveSandboxFile } from '../utils/PickerSaveUtils';
import { pickAndCopyPDF } from '../utils/PDFImportUtils';
import { addEditedFile } from '../utils/ImportLibrary';
import { PdfEditToolItem } from '../components/PdfEditToolItem';
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
  @State textBlocks: Array<TextBlockInfo> = [];
  @State activedTool: number = -1;
  @State canUndo: boolean = false;
  @State highlightColor: number = 0xFFC300;
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
  private selectedBlockIndex: number = -1;
  private blockListId: number = -1;
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
    const op = this.ops.pop();
    this.opsCount = this.ops.length;
    this.canUndo = this.ops.length > 0;
    this.selectedOpIndex = -1;
    this.statusMsg = op ? '已撤回上一步操作' : '';
  }

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as EditPageParams;
    this.isNewDoc = params?.newDoc ?? false;
    this.filePath = params?.filePath ?? '';
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
    });
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
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
  private blockListContent(title: string) {
    Column({ space: 12 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.textBlocks, (block: TextBlockInfo) => {
            Row() {
              Text(`第 ${block.index + 1} 块`)
                .fontSize(12)
                .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              Blank()
              Text(block.text.length > 12 ? block.text.substring(0, 12) + '…' : block.text)
                .fontSize(13)
                .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
                .maxLines(1)
              Blank()
              Text(`${block.size}pt`)
                .fontSize(12)
                .fontColor('#888888')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(12)
            .backgroundBlurStyle(GlassTokens.BLUR_BUTTON)
            .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
            .onClick(() => {
              this.onPickBlock(block.index)
            })
          }, (block: TextBlockInfo) => `${block.index}`)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)

      Row({ space: 12 }) {
        GlassButton({
          label: '取消', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 100,
          onClickHandler: () => {
            this.getUIContext().getPromptAction().closeCustomDialog(this.blockListId);
          }
        })
        GlassButton({
          label: '确定', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 100,
          onClickHandler: () => {
            this.getUIContext().getPromptAction().closeCustomDialog(this.blockListId);
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
    if (op.op === 'addText' || op.op === 'addImage' || op.op === 'addHighlight' || op.op === 'addTextAnnot') {
      const w = op.op === 'addText' ? (op as EditTextOp).text.length * 8 : ((op.op === 'addHighlight' ? 200 : (op as EditImageOp).width));
      const h = op.op === 'addText' ? 20 : (op.op === 'addHighlight' ? 30 : (op as EditImageOp).height);
      return {
        x: op.x * s,
        y: (hpt - op.y) * s - h * s
      };
    }
    return { x: 0, y: 0 };
  }

  private opSize(index: number): PdfCoord {
    const op = this.ops[index];
    if (!op) {
      return { x: 0, y: 0 };
    }
    const s = this.scalePx();
    if (op.op === 'addText') {
      return { x: (op as EditTextOp).text.length * 8 * s, y: 20 * s };
    }
    if (op.op === 'addImage') {
      return { x: (op as EditImageOp).width * s, y: (op as EditImageOp).height * s };
    }
    if (op.op === 'addHighlight') {
      return { x: 200 * s, y: 30 * s };
    }
    return { x: 0, y: 0 };
  }

  private isDraggableOp(index: number): boolean {
    const op = this.ops[index];
    return op !== undefined && (op.op === 'addText' || op.op === 'addImage');
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
    if (!op || (op.op !== 'addText' && op.op !== 'addImage')) {
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
    op.x = op.x + dx;
    op.y = op.y - dy;
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
      const sandboxPath = context.filesDir + '/edit_img_' + Date.now() + '.png';
      let srcFd: number = 0;
      let dstFd: number = 0;
      try {
        const stat = await fileIo.stat(uri);
        const buf = new ArrayBuffer(stat.size);
        const src = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
        srcFd = src.fd;
        await fileIo.read(srcFd, buf);
        const dst = await fileIo.open(sandboxPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        dstFd = dst.fd;
        await fileIo.write(dstFd, buf);
      } finally {
        if (srcFd !== 0) {
          await fileIo.close(srcFd);
        }
        if (dstFd !== 0) {
          await fileIo.close(dstFd);
        }
      }
      return sandboxPath;
    } catch (err) {
      console.error('pick image failed', JSON.stringify(err));
      return '';
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
      if (this.isDraggableOp(index) && this.selectedOpIndex === index) {
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
      if (op.op === 'addText' || op.op === 'addImage') {
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
          this.statusMsg = `已添加文本到第 ${page + 1} 页（保存后生效）`;
        });
        break;
      }
      case 1: {
        this.pickImage().then((path: string) => {
          if (!path) {
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
          this.statusMsg = `已添加图片到第 ${page + 1} 页（保存后生效）`;
        });
        break;
      }
      case 2: {
        const hpt = this.pageHeightPt();
        const w = 200;
        const h = 30;
        const hlY = hpt - y - h;
        const hlX = x - w / 2;
        const op: EditHighlightOp = {
          op: 'addHighlight',
          page: page,
          x: hlX,
          y: hlY,
          width: w,
          height: h,
          color: this.highlightColor
        };
        this.pushOp(op);
        break;
      }
      case 3: {
        const op: EditTextAnnotOp = {
          op: 'addTextAnnot',
          page: page,
          x: x,
          y: y,
          content: '',
          color: 0x1A1A1F
        };
        this.pushOp(op);
        break;
      }
      default:
        return;
    }
    if (this.activedTool !== 0 && this.activedTool !== 1) {
      this.statusMsg = `已添加，保存后生效（第 ${page + 1} 页）`;
    }
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
    this.activedTool = 4;
    this.rewriteAsync();
  }

  private async rewriteAsync(): Promise<void> {
    if (!this.filePath) {
      this.showToast('请先打开一个 PDF 文件');
      return;
    }
    try {
      const result: TextObjectResult = await listTextObjectsAsync(this.filePath, this.currentPage);
      if (!result.ok) {
        this.showToast('读取文本块失败（文件可能已损坏）');
        return;
      }
      if (result.blocks.length === 0) {
        this.showToast('此页无文本或为扫描版，无法修改');
        return;
      }
      this.textBlocks = result.blocks;
      const uiCtx = this.getUIContext();
      uiCtx.getPromptAction().openCustomDialog({
        builder: () => {
          this.blockListContent(`修改文字（第 ${this.currentPage + 1} 页）`)
        },
        autoCancel: true
      }).then((id: number) => {
        this.blockListId = id;
      }).catch(() => {
        console.error('open block list dialog failed');
      });
    } catch (err) {
      console.error('list text blocks failed', JSON.stringify(err));
      this.showToast('解析文本块异常，请重试');
    }
  }

  private onPickBlock(index: number): void {
    this.getUIContext().getPromptAction().closeCustomDialog(this.blockListId);
    const block = this.textBlocks.find((b) => b.index === index);
    if (!block) {
      return;
    }
    this.selectedBlockIndex = index;
    this.promptTextInput('修改文字内容', block.text, (value: string) => {
      if (!value.trim()) {
        return;
      }
      const newText = value.trim();
      this.promptTextInput('修改字号（pt）', `${block.size}`, (sizeValue: string) => {
        const newSize = parseInt(sizeValue, 10);
        if (isNaN(newSize) || newSize <= 0) {
          this.showToast('请输入有效字号');
          return;
        }
        this.pushOp({
          op: 'rewriteText',
          page: this.currentPage,
          index: this.selectedBlockIndex,
          newText: newText,
          newSize: newSize
        } as EditRewriteTextOp);
        this.statusMsg = `已修改文字（保存后生效）`;
      });
    });
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
          } else if (this.activedTool >= 0 && this.activedTool <= 3) {
            Column()
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
