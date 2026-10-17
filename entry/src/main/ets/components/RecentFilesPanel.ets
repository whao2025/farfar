import { GlassTokens } from '../theme/GlassTokens';
import { GlassButton } from './GlassButton';
import { ImportFileItem, loadRecentFiles, toggleStar, pinStarBatch, deleteImports, moveToTopBatch, formatRelativeTime } from '../utils/ImportLibrary';
import { common } from '@kit.AbilityKit';

@Component
export struct RecentFilesPanel {
  @Prop searchMode: boolean = false;
  @Prop keyword: string = '';
  @StorageProp('fileFilterMode') @Watch('onFilterChange') filterMode: string = 'all';
  @StorageProp('darkMode') dark: boolean = false;
  @StorageProp('recentRefreshTick') @Watch('onRefreshTick') refreshTick: number = 0;
  @Link @Watch('onSelectModeChange') selectModeActive: boolean;
  @State selectedPaths: Array<string> = [];
  @State recentFiles: Array<ImportFileItem> = [];
  @State expanded: boolean = false;
  @State confirmDialogId: number = -1;
  @State confirmTitle: string = '';
  @State confirmMessage: string = '';
  private pendingConfirm: () => void = () => {};

  aboutToAppear(): void {
    this.load();
  }

  onSelectModeChange(): void {
    if (!this.selectModeActive) {
      this.selectedPaths = [];
      this.expanded = false;
    } else {
      this.expanded = true;
    }
  }

  onRefreshTick(): void {
    this.load();
  }

  onFilterChange(): void {
    // @StorageProp 变更自动重渲染，无需额外处理
  }

  async load(): Promise<void> {
    const uiContext = this.getUIContext();
    const host = uiContext.getHostContext();
    if (!host) {
      return;
    }
    const ctx = host as common.Context;
    this.recentFiles = await loadRecentFiles(ctx);
  }

  getVisibleFiles(): Array<ImportFileItem> {
    let source = this.recentFiles;
    if (this.filterMode === 'starred') {
      const starred = source.filter((f) => f.star);
      const pinned = starred.filter((f) => f.starPinTime !== undefined)
        .sort((a, b) => ((b.starPinTime ?? 0) - (a.starPinTime ?? 0)));
      const unpinned = starred.filter((f) => f.starPinTime === undefined)
        .sort((a, b) => (b.time - a.time));
      source = pinned.concat(unpinned);
    }
    if (this.searchMode && this.keyword !== '') {
      source = source.filter((f) => f.name.includes(this.keyword));
    }
    return source;
  }

  getVisibleShown(): Array<ImportFileItem> {
    const visible = this.getVisibleFiles();
    if (this.selectModeActive || this.expanded) {
      return visible;
    }
    return visible.slice(0, 4);
  }

  shouldShowExpand(): boolean {
    return !this.selectModeActive && this.getVisibleFiles().length > 4;
  }

  private async onToggleStar(item: ImportFileItem): Promise<void> {
    console.info(`[Star] toggle clicked for: ${item.name}`);
    const uiContext = this.getUIContext();
    const host = uiContext.getHostContext();
    if (!host) {
      return;
    }
    const ctx = host as common.Context;
    const updated = await toggleStar(ctx, item.name);
    console.info(`[Star] after toggle, recentFiles=${updated.length}, name=${item.name} star=${this.getStarState(updated, item.name)}`);
    this.recentFiles = updated.slice();
  }

  private getStarState(files: Array<ImportFileItem>, name: string): boolean {
    const f = files.find((x) => x.name === name);
    return f ? f.star : false;
  }

  private openFile(item: ImportFileItem): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PDFViewer', params: { filePath: item.path } });
    } catch (err) {
      console.error('openFile pushUrl failed:', JSON.stringify(err));
    }
  }

  private openConfirmDialog(title: string, message: string, onConfirm: () => void): void {
    this.confirmTitle = title;
    this.confirmMessage = message;
    this.pendingConfirm = onConfirm;
    const uiContext = this.getUIContext();
    uiContext.getPromptAction().openCustomDialog({
      builder: () => {
        this.confirmDialog()
      },
      autoCancel: true
    }).then((id: number) => {
      this.confirmDialogId = id;
    }).catch(() => {
      console.error('open confirm dialog failed');
    });
  }

  private closeConfirmDialog(): void {
    if (this.confirmDialogId >= 0) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(this.confirmDialogId);
      } catch (e) {
        console.error('close confirm dialog failed:', JSON.stringify(e));
      }
      this.confirmDialogId = -1;
    }
  }

  @Builder
  confirmDialog() {
    Column({ space: 14 }) {
      Text(this.confirmTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
      Text(this.confirmMessage)
        .fontSize(13)
        .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
        .textAlign(TextAlign.Center)
        .maxLines(3)
      Row({ space: 12 }) {
        GlassButton({
          label: '取消', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 108,
          onClickHandler: () => this.closeConfirmDialog()
        })
        GlassButton({
          label: '删除', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 108,
          onClickHandler: () => {
            const fn = this.pendingConfirm;
            this.closeConfirmDialog();
            fn();
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .padding(24)
    .backgroundBlurStyle(GlassTokens.BLUR_MODAL)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
    .borderRadius(20)
    .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
  }

  private isSelected(path: string): boolean {
    return this.selectedPaths.includes(path);
  }

  private toggleSelect(path: string): void {
    if (this.isSelected(path)) {
      this.selectedPaths = this.selectedPaths.filter((p) => p !== path);
    } else {
      this.selectedPaths = [...this.selectedPaths, path];
    }
  }

  private allSelected(): boolean {
    const visible = this.getVisibleFiles();
    return visible.length > 0 && visible.every((f) => this.selectedPaths.includes(f.path));
  }

  private toggleSelectAll(): void {
    const visible = this.getVisibleFiles();
    if (this.allSelected()) {
      this.selectedPaths = [];
    } else {
      this.selectedPaths = visible.map((f) => f.path);
    }
  }

  private exitSelectMode(): void {
    this.selectModeActive = false;
    this.selectedPaths = [];
  }

  private onRowClick(item: ImportFileItem): void {
    if (this.selectModeActive) {
      this.toggleSelect(item.path);
    } else {
      this.openFile(item);
    }
  }

  private async onBatchMoveToTop(): Promise<void> {
    const uiContext = this.getUIContext();
    const host = uiContext.getHostContext();
    if (!host || this.selectedPaths.length === 0) {
      return;
    }
    const ctx = host as common.Context;
    const names = this.getVisibleFiles().filter((f) => this.selectedPaths.includes(f.path)).map((f) => f.name);
    if (names.length === 0) {
      return;
    }
    let updated: Array<ImportFileItem>;
    if (this.filterMode === 'starred') {
      updated = await pinStarBatch(ctx, names);
    } else {
      updated = await moveToTopBatch(ctx, names);
    }
    this.recentFiles = updated.slice();
    this.bumpRefresh();
    this.exitSelectMode();
    try {
      uiContext.getPromptAction().showToast({ message: `已置顶 ${names.length} 个文件` });
    } catch (err) {
      console.error('onBatchPin showToast failed:', JSON.stringify(err));
    }
  }

  private async onBatchDelete(): Promise<void> {
    const uiContext = this.getUIContext();
    const host = uiContext.getHostContext();
    if (!host || this.selectedPaths.length === 0) {
      return;
    }
    const ctx = host as common.Context;
    const names = this.getVisibleFiles().filter((f) => this.selectedPaths.includes(f.path)).map((f) => f.name);
    if (names.length === 0) {
      return;
    }
    try {
      this.openConfirmDialog('批量删除', `确定删除选中的 ${names.length} 个文件？此操作不可恢复。`, () => {
        this.doBatchDelete(ctx, names);
      });
    } catch (e) {
      console.error('batch delete failed', JSON.stringify(e));
    }
  }

  private async doBatchDelete(ctx: common.Context, names: string[]): Promise<void> {
    const uiContext = this.getUIContext();
    try {
      const updated = await deleteImports(ctx, names);
      this.recentFiles = updated.slice();
      this.bumpRefresh();
      this.selectedPaths = [];
      if (this.getVisibleFiles().length === 0) {
        this.exitSelectMode();
      }
      uiContext.getPromptAction().showToast({ message: `已删除 ${names.length} 个文件` });
    } catch (e) {
      console.error('batch delete failed', JSON.stringify(e));
    }
  }

  private bumpRefresh(): void {
    const tick = (AppStorage.get<number>('recentRefreshTick') ?? 0) as number;
    AppStorage.setOrCreate('recentRefreshTick', tick + 1);
  }

  @Builder
  batchActionBar() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.allSelected() ? $r('sys.symbol.checkmark_square') : $r('sys.symbol.square'))
          .fontSize(20)
          .fontColor([this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT])
          .fontWeight(FontWeight.Bold)
      }
      .width(40)
      .height(40)
      .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
      .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
      .onClick(() => {
        this.toggleSelectAll();
      })

      Text(this.allSelected() ? '取消全选' : '全选')
        .fontSize(13)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
        .layoutWeight(1)

      Text(`${this.selectedPaths.length} 项`)
        .fontSize(13)
        .fontColor(this.dark ? '#8A8A96' : '#8A8A96')

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.arrow_up'))
          .fontSize(20)
          .fontColor([Color.White])
          .fontWeight(FontWeight.Bold)
      }
      .width(40)
      .height(40)
      .backgroundColor('#4C9AFF')
      .opacity(this.selectedPaths.length === 0 ? 0.4 : 1)
      .onClick(() => {
        this.onBatchMoveToTop();
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([Color.White])
          .fontWeight(FontWeight.Bold)
      }
      .width(40)
      .height(40)
      .backgroundColor('#FF453A')
      .opacity(this.selectedPaths.length === 0 ? 0.4 : 1)
      .onClick(() => {
        this.onBatchDelete();
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([Color.White])
          .fontWeight(FontWeight.Bold)
      }
      .width(40)
      .height(40)
      .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
      .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
      .onClick(() => {
        this.exitSelectMode();
      })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
    .borderRadius(16)
    .margin({ bottom: 16 })
  }

  build() {
    Column() {
      if (this.getVisibleFiles().length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.doc'))
            .fontSize(40)
            .fontColor([this.dark ? '#8A8A96' : '#8A8A96'])
            .opacity(0.6)
          Text(this.searchMode ? '未找到匹配文件' : (this.filterMode === 'starred' ? '暂无星标文件' : '暂无导入文件'))
            .fontSize(14)
            .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
          if (!this.searchMode) {
            Text('点击右上角 + 导入 PDF 文件')
              .fontSize(12)
              .fontColor(this.dark ? '#8A8A96' : '#8A8A96')
          }
        }
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.getVisibleShown(), (item: ImportFileItem) => {
            ListItem() {
              Row({ space: 12 }) {
                Row({ space: 12 }) {
                  if (this.selectModeActive) {
                    SymbolGlyph(this.isSelected(item.path) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
                      .fontSize(24)
                      .fontColor([this.isSelected(item.path) ? '#4C9AFF' : (this.dark ? '#8A8A96' : '#8A8A96')])
                  } else {
                    SymbolGlyph($r('sys.symbol.doc_text'))
                      .fontSize(24)
                      .fontColor([this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT])
                  }
                  Column({ space: 2 }) {
                    Text(item.name)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(formatRelativeTime(item.time))
                      .fontSize(11)
                      .fontColor(this.dark ? '#8A8A96' : '#8A8A96')
                  }
                  .alignItems(HorizontalAlign.Start)
                }
                .layoutWeight(1)
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.onRowClick(item);
                })

                if (this.selectModeActive) {
                  Blank()
                } else {
                  SymbolGlyph(item.star ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                    .fontSize(20)
                    .fontColor([item.star ? '#F5B544' : (this.dark ? '#8A8A96' : '#8A8A96')])
                    .opacity(item.star ? 1 : 0.6)
                    .padding(8)
                    .onClick(() => {
                      this.onToggleStar(item);
                    })
                }
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
              .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
              .gesture(
                LongPressGesture().onAction(() => {
                  if (!this.selectModeActive) {
                    this.selectModeActive = true;
                    this.selectedPaths = [item.path];
                  }
                })
              )
            }
          }, (item: ImportFileItem) => item.path + '_' + item.star)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ bottom: this.selectModeActive ? 0 : 16 })

        if (this.shouldShowExpand()) {
          Row() {
            Row() {
              Text(this.expanded ? '收起' : `展开全部 (${this.getVisibleFiles().length})`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(GlassTokens.TEXT_DARK)
                .padding({ left: 18, right: 18, top: 7, bottom: 7 })
            }
            .backgroundColor(this.dark ? '#454555' : '#3A3A46')
            .borderRadius(17)
            .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : 'rgba(255,255,255,0.4)' })
            .shadow(GlassTokens.SHADOW)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
            .onClick(() => {
              this.expanded = !this.expanded;
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 16 })
        }

        if (this.selectModeActive) {
          this.batchActionBar()
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}