import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassToolbar } from '../components/GlassToolbar';
import { GlassButton } from '../components/GlassButton';

interface PdfViewerParams {
  filePath?: string;
}

@Entry
@Component
struct PDFViewer {
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  @StorageProp('darkMode') dark: boolean = false;
  @State filePath: string = ''
  @State pageCount: number = 0
  @State loadResult: pdfService.ParseResult = pdfService.ParseResult.PARSE_ERROR_FORMAT
  @State currentPage: number = 0
  @State loadingProgress: number = -1

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as PdfViewerParams;
    this.filePath = params?.filePath ?? '';
    if (!this.filePath) {
      return
    }
    this.loadPDF()
  }

  aboutToDisappear(): void {
    this.controller.releaseDocument()
  }

  private loadPDF(): void {
    (async () => {
      this.controller.registerPageCountChangedListener((count: number) => {
        this.pageCount = count
      })
      this.controller.registerPageChangedListener((pageIndex: number) => {
        this.currentPage = pageIndex
      })
      try {
        this.loadResult = await this.controller.loadDocument(this.filePath, '', 0, (progress: number) => {
          this.loadingProgress = progress
        })
        if (this.loadResult === pdfService.ParseResult.PARSE_SUCCESS) {
          this.controller.setPageLayout(pdfService.PageLayout.LAYOUT_SINGLE)
          this.controller.setPageContinuous(true)
          this.controller.setPageFit(pdfService.PageFit.FIT_WIDTH)
        }
      } catch (err) {
        const e = err as BusinessError
        this.loadingProgress = -1
        console.error('loadDocument failed', JSON.stringify(e))
      }
    })()
  }

  build() {
    Stack() {
      Column() {
        GlassToolbar({ dark: this.dark }) {
          Row({ space: 8 }) {
            Blank()
            Text(this.pageCount > 0
              ? `${this.currentPage + 1} / ${this.pageCount}`
              : (this.loadingProgress >= 0 ? `加载中 ${this.loadingProgress}%` : ''))
              .fontSize(14)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : '#666666')
            Blank()
            GlassButton({
              label: '编辑',
              dark: this.dark,
              onClickHandler: () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/PDFEditPage', params: { filePath: this.filePath } });
              },
              heightVp: 40,
              fontSize: 14,
              widthVp: 64
            })
          }
          .width('100%')
        }

        if (this.loadResult === pdfService.ParseResult.PARSE_SUCCESS) {
          PdfView({
            controller: this.controller,
            pageFit: pdfService.PageFit.FIT_WIDTH,
            showScroll: true,
          })
            .layoutWeight(1)
            .width('100%')
        } else if (this.loadResult === pdfService.ParseResult.PARSE_ERROR_FORMAT) {
          Column() {
            Text('无法解析 PDF 文件')
              .fontSize(16)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : '#666666')
            GlassButton({ label: '重新选择', dark: this.dark, onClickHandler: () => { this.getUIContext().getRouter().back() }, heightVp: 44, fontSize: 15 })
              .margin({ top: 16 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundBlurStyle(GlassTokens.BLUR)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
  }
}