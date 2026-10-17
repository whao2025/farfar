import { GlassTokens } from '../theme/GlassTokens';
import { GlassButton } from './GlassButton';

export interface RewriteUndoEntry {
  page: number;
  origText: string;
  newText: string;
}

@Component
export struct RewriteUndoDialog {
  @Prop entries: Array<RewriteUndoEntry> = [];
  @Prop selected: boolean[] = [];
  @Prop dark: boolean = false;
  onToggle: (idx: number) => void = () => {};
  onSelectAll: () => void = () => {};
  onSelectNone: () => void = () => {};
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};

  @Builder
  private selectAllRow() {
    Row({ space: 8 }) {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([$r('sys.color.icon_emphasize')])
        Text('全选')
          .fontSize(14)
          .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundBlurStyle(GlassTokens.BLUR_BUTTON)
      .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
      .onClick(() => {
        this.onSelectAll();
      })
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([$r('sys.color.icon_tertiary')])
        Text('全不选')
          .fontSize(14)
          .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundBlurStyle(GlassTokens.BLUR_BUTTON)
      .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
      .onClick(() => {
        this.onSelectNone();
      })
      Blank()
      Text(`${this.checkedCount()} / ${this.entries.length}`)
        .fontSize(12)
        .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
    }
    .width('100%')
  }

  private checkedCount(): number {
    let n = 0;
    for (let i = 0; i < this.selected.length; i++) {
      if (this.selected[i]) {
        n++;
      }
    }
    return n;
  }

  private isChecked(idx: number): boolean {
    return idx >= 0 && idx < this.selected.length && this.selected[idx];
  }

  @Builder
  private undoRow(entry: RewriteUndoEntry, idx: number) {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.character_textbox'))
        .fontSize(18)
        .fontColor([$r('sys.color.icon_tertiary')])
      Column({ space: 3 }) {
        Text(this.previewOf(entry.newText))
          .fontSize(13)
          .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 10 }) {
          Text(`第 ${entry.page + 1} 页`)
            .fontSize(10)
            .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
          Text(`原文：${this.previewOf(entry.origText)}`)
            .fontSize(10)
            .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph(this.isChecked(idx) ? $r('sys.symbol.checkmark') : $r('sys.symbol.xmark'))
        .fontSize(18)
        .fontColor([this.isChecked(idx) ? $r('sys.color.icon_emphasize') : $r('sys.color.icon_tertiary')])
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.isChecked(idx)
      ? (this.dark ? 'rgba(239,68,68,0.16)' : 'rgba(239,68,68,0.08)')
      : Color.Transparent)
    .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      this.onToggle(idx);
    })
  }

  private previewOf(text: string): string {
    return text.length > 20 ? text.substring(0, 20) + '…' : text;
  }

  build() {
    Stack() {
      Column({ space: 12 }) {
        Text('撤回本批次的改字操作')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
        this.selectAllRow()
        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.entries, (entry: RewriteUndoEntry, idx: number) => {
              this.undoRow(entry, idx)
            }, (entry: RewriteUndoEntry, idx: number) => idx.toString() + '_' + this.entries.length.toString())
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        Row({ space: 12 }) {
          GlassButton({
            label: '取消', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 100,
            onClickHandler: () => {
              this.onCancel();
            }
          })
          GlassButton({
            label: '撤回选中', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 100,
            onClickHandler: () => {
              this.onConfirm();
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .padding(20)
      .width('94%')
      .height('78%')
      .backgroundBlurStyle(GlassTokens.BLUR_MODAL)
      .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
      .borderRadius(20)
      .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
      .shadow(GlassTokens.SHADOW)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
