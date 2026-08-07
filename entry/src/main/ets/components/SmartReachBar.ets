import { GlassTokens } from '../theme/GlassTokens';

@Component
export struct SmartReachBar {
  @Prop dark: boolean = false;
  onManual: () => void = () => {};
  onPdfAuto: () => void = () => {};

  private readonly BALL_SIZE: number = 68 * 0.75;   // 51vp
  private readonly BALL_GAP: number = 16 * 0.75;    // 12vp
  private readonly PADDING: number = 8 * 0.75;      // 6vp

  @Builder
  private Ball(label: string, icon: Resource, color: string, onTap: () => void) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 2 * 0.75 }) {
        SymbolGlyph(icon)
          .fontSize(24 * 0.75)
          .fontColor(['#FFFFFF'])
        Text(label)
          .fontSize(9 * 0.75)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.BALL_SIZE)
    .height(this.BALL_SIZE)
    .borderRadius(this.BALL_SIZE / 2)
    .backgroundColor(color)
    .onClick(() => onTap())
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .shadow({
      radius: 8 * 0.75,
      color: 'rgba(0,0,0,0.3)',
      offsetX: 0,
      offsetY: 2 * 0.75
    })
  }

  build() {
    // 仅透明玻璃 + 双球，无渐变/高光/额外背景色
    Column({ space: this.BALL_GAP }) {
      this.Ball('记账', $r('sys.symbol.wallet'), '#00B4A0', this.onManual)     // 黛青
      this.Ball('PDF', $r('sys.symbol.doc_text'), '#D4A017', this.onPdfAuto)   // 藤黄
    }
    .padding({ left: this.PADDING, right: this.PADDING, top: this.PADDING, bottom: this.PADDING })
    .backgroundBlurStyle(GlassTokens.BLUR_BUTTON)
    .backgroundColor('transparent')
    .borderColor(this.dark ? GlassTokens.BORDER_DARK + '40' : GlassTokens.BORDER_LIGHT + '40')
    .borderWidth(0.5)
    .borderRadius((this.BALL_SIZE + this.PADDING * 2) / 2)
  }
}