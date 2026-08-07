import { GlassTokens } from '../../theme/GlassTokens';
import { pickAndCopyPDF } from '../../utils/PDFImportUtils';
import { RecentFilesPanel } from '../../components/RecentFilesPanel';
import { common } from '@kit.AbilityKit';

@Component
export struct EditTab {
  @StorageProp('darkMode') dark: boolean = false;
  @State busy: boolean = false;
  @State searchMode: boolean = false;
  @State keyword: string = '';
  @State selectModeActive: boolean = false;
  @StorageProp('fileFilterMode') filterMode: string = 'all';

  build() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text('编辑 PDF')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          Text('导入阅读、编辑，一站式 PDF 处理')
            .fontSize(12)
            .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: 12 }) {
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
          SymbolGlyph($r('sys.symbol.pencil_line'))
            .fontSize(22)
            .fontColor([this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT])
            .padding(12)
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.onEditPDF();
            })
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT])
            .padding(12)
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.onImportPDF();
            })
        }
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
        Row({ space: 16 }) {
          Text('全部')
            .fontSize(14)
            .fontWeight(this.filterMode === 'all' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.filterMode === 'all'
              ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              : (this.dark ? '#8A8A96' : '#8A8A96'))
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              this.setFilter('all');
            })
          Text('星标')
            .fontSize(14)
            .fontWeight(this.filterMode === 'starred' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.filterMode === 'starred'
              ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              : (this.dark ? '#8A8A96' : '#8A8A96'))
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              this.setFilter('starred');
            })
        }
        .padding({ left: 24, right: 24, top: 8, bottom: 4 })
      } else {
        Row({ space: 16 }) {
          Text('全部')
            .fontSize(14)
            .fontWeight(this.filterMode === 'all' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.filterMode === 'all'
              ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              : (this.dark ? '#8A8A96' : '#8A8A96'))
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              this.setFilter('all');
            })
          Text('星标')
            .fontSize(14)
            .fontWeight(this.filterMode === 'starred' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.filterMode === 'starred'
              ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              : (this.dark ? '#8A8A96' : '#8A8A96'))
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              this.setFilter('starred');
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 4 })
      }

      RecentFilesPanel({ searchMode: this.searchMode, keyword: this.keyword, selectModeActive: this.selectModeActive })
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  private async onImportPDF(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const uiContext = this.getUIContext();
    const host = uiContext.getHostContext();
    if (!host) {
      this.busy = false;
      return;
    }
    const ctx = host as common.Context;
    try {
      const sandboxPath = await pickAndCopyPDF(ctx);
      if (sandboxPath) {
        this.bumpRefresh();
      }
    } catch (err) {
      console.error('import PDF failed', JSON.stringify(err));
    } finally {
      this.busy = false;
    }
  }

  private async onEditPDF(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const uiContext = this.getUIContext();
    const host = uiContext.getHostContext();
    if (!host) {
      this.busy = false;
      return;
    }
    const ctx = host as common.Context;
    try {
      const sandboxPath = await pickAndCopyPDF(ctx);
      if (sandboxPath) {
        this.getUIContext().getRouter().pushUrl({ url: 'pages/PDFEditPage', params: { filePath: sandboxPath } });
        this.bumpRefresh();
      }
    } catch (err) {
      console.error('edit PDF failed', JSON.stringify(err));
    } finally {
      this.busy = false;
    }
  }

  private setFilter(mode: string): void {
    this.filterMode = mode;
    AppStorage.setOrCreate('fileFilterMode', mode);
  }

  private bumpRefresh(): void {
    const tick = (AppStorage.get<number>('recentRefreshTick') ?? 0) as number;
    AppStorage.setOrCreate('recentRefreshTick', tick + 1);
  }
}