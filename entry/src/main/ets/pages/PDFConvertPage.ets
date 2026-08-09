import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassToolbar } from '../components/GlassToolbar';
import { GlassButton } from '../components/GlassButton';
import { pdfToImagesAsync, imagesToPdfAsync, listFiles } from '../utils/PDFConvertUtils';
import { extractTextAsync } from '../utils/PDFEditUtils';
import { extractTextWithOCRFallback, isAllPageMarkers } from '../utils/PDFOCRUtils';
import { saveSandboxFile } from '../utils/PickerSaveUtils';
import { pickAndCopyPDF } from '../utils/PDFImportUtils';

interface ConvertPageParams {
  mode?: string;
}

@Entry
@Component
struct PDFConvertPage {
  @StorageProp('darkMode') dark: boolean = false;
  @State mode: string = 'pdfToImage';
  @State busy: boolean = false;
  @State statusMsg: string = '';

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as ConvertPageParams;
    this.mode = params?.mode ?? 'pdfToImage';
  }

  private showToast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (err) {
      console.error('showToast failed:', JSON.stringify(err));
    }
  }

  private getTitle(): string {
    if (this.mode === 'imageToPdf') {
      return '图片合成 PDF';
    }
    if (this.mode === 'pdfToText') {
      return 'PDF 提取文本';
    }
    if (this.mode === 'pdfToCredit') {
      return 'PDF 转记账';
    }
    return 'PDF 转图片';
  }

  private getDesc(): string {
    if (this.mode === 'imageToPdf') {
      return '选择多张图片，合成为一个 PDF 文件';
    }
    if (this.mode === 'pdfToText') {
      return '提取 PDF 文本内容保存为 txt（扫描件无效）';
    }
    if (this.mode === 'pdfToCredit') {
      return '提取 PDF 文本，自动识别账单记录，保存到记账';
    }
    return '将 PDF 每页导出为 PNG 图片';
  }

  private onStart(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.statusMsg = '';
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      this.busy = false;
      return;
    }
    const context = ctx as common.Context;
    if (this.mode === 'pdfToImage') {
      this.runPdfToImage(context);
    } else if (this.mode === 'imageToPdf') {
      this.runImageToPdf(context);
    } else if (this.mode === 'pdfToText') {
      this.runPdfToText(context);
    } else if (this.mode === 'pdfToCredit') {
      this.runPdfToCredit(context);
    }
  }

  private async runPdfToImage(context: common.Context): Promise<void> {
    try {
      const srcPath = await pickAndCopyPDF(context);
      if (!srcPath) {
        this.busy = false;
        return;
      }
      const outDir = context.filesDir + '/pdf_out_' + Date.now();
      await fileIo.mkdir(outDir);
      this.statusMsg = '转换中…';
      const ok = await pdfToImagesAsync(srcPath, outDir, (p: number) => { });
      if (!ok) {
        this.showToast('转换失败');
        this.busy = false;
        return;
      }
      const files = await listFiles(outDir);
      if (files.length === 0) {
        this.showToast('未生成图片');
        this.busy = false;
        return;
      }
      this.statusMsg = `已生成 ${files.length} 张图片，选择导出位置…`;
      const saved = await this.exportAllImages(context, outDir, files);
      this.showToast(saved ? `已导出 ${files.length} 张图片` : '已生成，未选择导出位置');
    } catch (err) {
      console.error('pdfToImage failed', JSON.stringify(err));
      this.showToast('转换失败');
    } finally {
      this.busy = false;
    }
  }

  private async exportAllImages(context: common.Context, outDir: string, files: string[]): Promise<boolean> {
    let allSaved = true;
    for (let i = 0; i < files.length; i++) {
      const fullPath = outDir + '/' + files[i];
      const ok = await saveSandboxFile(context, fullPath, `page_${i + 1}.png`, '.png');
      if (!ok) {
        allSaved = false;
        break;
      }
    }
    return allSaved;
  }

  private async runImageToPdf(context: common.Context): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 30;
      const result = await photoPicker.select(options);
      if (!result.photoUris || result.photoUris.length === 0) {
        this.busy = false;
        return;
      }
      this.statusMsg = '处理图片…';
      const imagePaths: string[] = [];
      let pageWidth = 595;
      let pageHeight = 842;
      for (let i = 0; i < result.photoUris.length; i++) {
        const uri = result.photoUris[i];
        const sandboxPath = context.filesDir + '/conv_img_' + Date.now() + '_' + i + '.jpg';
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
          imagePaths.push(sandboxPath);
          if (i === 0) {
            const src = image.createImageSource(sandboxPath);
            const info = await src.getImageInfo();
            await src.release();
            pageWidth = Math.round(info.size.width * 72 / 96);
            pageHeight = Math.round(info.size.height * 72 / 96);
          }
        } finally {
          if (srcFd !== 0) {
            await fileIo.close(srcFd);
          }
          if (dstFd !== 0) {
            await fileIo.close(dstFd);
          }
        }
      }
      this.statusMsg = '合成 PDF…';
      const outPath = context.filesDir + '/images_' + Date.now() + '.pdf';
      const ok = await imagesToPdfAsync(imagePaths, outPath, pageWidth, pageHeight);
      if (!ok) {
        this.showToast('合成失败');
        this.busy = false;
        return;
      }
      this.statusMsg = '选择导出位置…';
      const saved = await saveSandboxFile(context, outPath, 'images.pdf', '.pdf');
      this.showToast(saved ? '已导出 PDF' : '已生成，未选择导出位置');
    } catch (err) {
      console.error('imageToPdf failed', JSON.stringify(err));
      this.showToast('转换失败');
    } finally {
      this.busy = false;
    }
  }

  private async runPdfToCredit(context: common.Context): Promise<void> {
    try {
      const srcPath = await pickAndCopyPDF(context);
      if (!srcPath) {
        this.busy = false;
        return;
      }
      this.statusMsg = '提取文本中…';
      const raw = await extractTextAsync(srcPath);
      const ocrNeeded = raw.trim().length === 0 || isAllPageMarkers(raw);
      if (ocrNeeded) {
        this.statusMsg = '检测到扫描件，正在 OCR 识别…';
      }
      const text = await extractTextWithOCRFallback(srcPath, raw);
      const usedOcr = ocrNeeded;
      if (!text || !text.trim()) {
        this.showToast('未提取到文本，请确认 PDF 可识别');
        this.busy = false;
        return;
      }
      this.statusMsg = '识别账单中…';
      // 跳转到记账确认页面（即便 0 条也跳转，便于提示/人工核验），文本在确认页统一解析，避免重复 parse
      const hasText: boolean = text.trim().length > 0;
      setTimeout(() => {
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/BookkeepingConfirmPage',
          params: {
            mode: 'pdfToCredit',
            source: usedOcr ? 'pdf-ocr' : 'pdf-text',
            text: text
          }
        });
        this.busy = false;
      }, hasText ? 800 : 200);
    } catch (err) {
      console.error('pdfToCredit failed', JSON.stringify(err));
      this.showToast('转换失败');
    } finally {
      this.busy = false;
    }
  }

  private async runPdfToText(context: common.Context): Promise<void> {
    try {
      const srcPath = await pickAndCopyPDF(context);
      if (!srcPath) {
        this.busy = false;
        return;
      }
      this.statusMsg = '提取文本中…';
      const text = await extractTextAsync(srcPath);
      if (!text) {
        this.showToast('未提取到文本（扫描件可能无效）');
        this.busy = false;
        return;
      }
      const txtPath = context.filesDir + '/extracted_' + Date.now() + '.txt';
      let fd: number = 0;
      try {
        const file = await fileIo.open(txtPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fd = file.fd;
        const encoder = new util.TextEncoder();
        const buf = encoder.encodeInto(text).buffer;
        await fileIo.write(fd, buf);
      } finally {
        if (fd !== 0) {
          await fileIo.close(fd);
        }
      }
      this.statusMsg = '选择导出位置…';
      const saved = await saveSandboxFile(context, txtPath, 'extracted.txt', '.txt');
      this.showToast(saved ? '已导出 txt' : '已生成，未选择导出位置');
    } catch (err) {
      console.error('pdfToText failed', JSON.stringify(err));
      this.showToast('转换失败');
    } finally {
      this.busy = false;
    }
  }

  build() {
    Stack() {
      Column() {
        GlassToolbar({ dark: this.dark }) {
          Row() {
            Blank()
            Text(this.getTitle())
              .fontSize(16)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            Blank()
          }
          .width('100%')
        }

        Column({ space: 24 }) {
          Column({ space: 12 }) {
            Text(this.getDesc())
              .fontSize(14)
              .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
              .textAlign(TextAlign.Center)
          }
          .padding(24)

          if (this.statusMsg) {
            Text(this.statusMsg)
              .fontSize(13)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          }

          GlassButton({
            label: this.busy ? '处理中…' : this.getStartLabel(),
            dark: this.dark,
            heightVp: 48,
            fontSize: 15,
            onClickHandler: () => this.onStart()
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundBlurStyle(GlassTokens.BLUR)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
  }

  private getStartLabel(): string {
    if (this.mode === 'imageToPdf') {
      return '选择图片开始合成';
    }
    if (this.mode === 'pdfToText') {
      return '选择 PDF 提取文本';
    }
    if (this.mode === 'pdfToCredit') {
      return '选择 PDF 转记账';
    }
    return '选择 PDF 转图片';
  }
}
