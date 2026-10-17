import { TextBlockInfo } from '../utils/PDFEditUtils';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassButton } from './GlassButton';

@Component
export struct RewriteSelectDialog {
  @Prop blocks: Array<TextBlockInfo> = [];
  @Prop selectedIds: string[] = [];
  @Prop dark: boolean = false;
  onToggle: (id: string) => void = () => {};
  onSelectAll: () => void = () => {};
  onSelectNone: () => void = () => {};
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};

  private isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

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
      Text(`${this.selectedIds.length} / ${this.blocks.length}`)
        .fontSize(12)
        .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
    }
    .width('100%')
  }

  @Builder
  private blockRow(block: TextBlockInfo) {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.character_textbox'))
        .fontSize(18)
        .fontColor([$r('sys.color.icon_tertiary')])
      Column({ space: 3 }) {
        Text(this.previewOf(block.text))
          .fontSize(13)
          .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 10 }) {
          Text(`字号 ${block.size}pt`)
            .fontSize(10)
            .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
          if (block.fontName && block.fontName.length > 0) {
            Text(block.fontName)
              .fontSize(10)
              .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph(this.isSelected(block.id) ? $r('sys.symbol.checkmark') : $r('sys.symbol.xmark'))
        .fontSize(18)
        .fontColor([this.isSelected(block.id) ? $r('sys.color.icon_emphasize') : $r('sys.color.icon_tertiary')])
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.isSelected(block.id)
      ? (this.dark ? 'rgba(99,102,241,0.18)' : 'rgba(99,102,241,0.10)')
      : Color.Transparent)
    .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      this.onToggle(block.id);
    })
  }

  private previewOf(text: string): string {
    return text.length > 28 ? text.substring(0, 28) + '…' : text;
  }

  @Builder
  private dialogBody() {
    Column({ space: 12 }) {
      Text('选择要修改的文字（可多选）')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
      this.selectAllRow()
      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.blocks, (block: TextBlockInfo) => {
            this.blockRow(block)
          }, (block: TextBlockInfo) => block.id)
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
          label: '下一步', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 100,
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

  build() {
    Stack() {
      this.dialogBody()
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
