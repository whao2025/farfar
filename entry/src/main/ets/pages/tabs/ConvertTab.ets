import { GlassButton } from '../../components/GlassButton';
import { GlassTokens } from '../../theme/GlassTokens';
import { RecentFilesPanel } from '../../components/RecentFilesPanel';

@Component
export struct ConvertTab {
  @StorageProp('darkMode') dark: boolean = false;
  @State searchMode: boolean = false;
  @State keyword: string = '';
  @State selectModeActive: boolean = false;
  @StorageProp('fileFilterMode') filterMode: string = 'all';

  build() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text('转换 PDF')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          Text('本地转换，不上传任何数据')
            .fontSize(12)
            .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph(this.selectModeActive ? $r('sys.symbol.xmark') : $r('sys.symbol.checkmark_square'))
          .fontSize(22)
          .fontColor([this.selectModeActive ? '#4C9AFF' : (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)])
          .padding(12)
          .onClick(() => {
            this.selectModeActive = !this.selectModeActive;
          })
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(22)
          .fontColor([this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT])
          .padding(12)
          .onClick(() => {
            this.searchMode = !this.searchMode;
          })
      }
      .width('100%')
      .padding({ top: 16, left: 24, right: 24, bottom: 8 })

      if (this.searchMode) {
        TextInput({ placeholder: '搜索文件名', text: this.keyword })
          .width('100%')
          .height(40)
          .placeholderColor(this.dark ? '#8A8A96' : '#8A8A96')
          .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
          .padding({ left: 24, right: 24 })
          .onChange((value: string) => {
            this.keyword = value;
          })
      }

      Row({ space: 16 }) {
        Text('全部')
          .fontSize(14)
          .fontWeight(this.filterMode === 'all' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.filterMode === 'all'
            ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            : (this.dark ? '#8A8A96' : '#8A8A96'))
          .padding({ top: 4, bottom: 4 })
          .onClick(() => {
            this.filterMode = 'all';
            AppStorage.setOrCreate('fileFilterMode', 'all');
          })
        Text('星标')
          .fontSize(14)
          .fontWeight(this.filterMode === 'starred' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.filterMode === 'starred'
            ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            : (this.dark ? '#8A8A96' : '#8A8A96'))
          .padding({ top: 4, bottom: 4 })
          .onClick(() => {
            this.filterMode = 'starred';
            AppStorage.setOrCreate('fileFilterMode', 'starred');
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 4 })

      Column({ space: 10 }) {
        Row({ space: 10 }) {
          GlassButton({ label: 'PDF转图片', dark: this.dark, heightVp: 44, fontSize: 14, onClickHandler: () => this.openConvert('pdfToImage') })
            .layoutWeight(1)
          GlassButton({ label: '图片合成PDF', dark: this.dark, heightVp: 44, fontSize: 14, onClickHandler: () => this.openConvert('imageToPdf') })
            .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 10 }) {
          GlassButton({ label: 'PDF提取文本', dark: this.dark, heightVp: 44, fontSize: 14, onClickHandler: () => this.openConvert('pdfToText') })
            .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 10 }) {
          GlassButton({ label: 'PDF转Word', dark: this.dark, heightVp: 44, fontSize: 14, onClickHandler: () => this.openConvert('pdfToWord') })
            .layoutWeight(1)
          GlassButton({ label: 'Word转PDF', dark: this.dark, heightVp: 44, fontSize: 14, onClickHandler: () => this.openConvert('wordToPdf') })
            .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 8 })

      RecentFilesPanel({ searchMode: this.searchMode, keyword: this.keyword, selectModeActive: this.selectModeActive })
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  private openConvert(mode: string): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PDFConvertPage', params: { mode: mode } });
    } catch (err) {
      console.error('openConvert pushUrl failed:', JSON.stringify(err));
    }
  }
}