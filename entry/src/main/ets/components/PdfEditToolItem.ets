import { GlassTokens } from '../theme/GlassTokens';

@Component
export struct PdfEditToolItem {
  @Prop label: string = '';
  @Prop icon: Resource = $r('sys.symbol.doc');
  @Prop actived: boolean = false;
  @Prop dark: boolean = false;
  onClickHandler: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.icon)
          .fontSize(20)
          .fontColor([this.actived ? $r('sys.color.icon_emphasize') : $r('sys.color.icon_tertiary')])
      }
      .width(36)
      .height(36)
      .backgroundColor(this.actived ? $r('sys.color.comp_background_tertiary') : Color.Transparent)

      Text(this.label)
        .fontSize(10)
        .fontWeight(this.actived ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.actived ? $r('sys.color.font_emphasize') : $r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(56)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onClickHandler();
    })
  }
}
