import { GlassTokens } from '../theme/GlassTokens';

@Component
export struct GlassButton {
  @Prop label: string = '';
  @Prop dark: boolean = false;
  @Prop blurStyle: BlurStyle = GlassTokens.BLUR_BUTTON;
  @Prop heightVp: number = 48;
  @Prop fontSize: number = 16;
  @Prop widthVp: number = 0;
  onClickHandler: () => void = () => {};

  build() {
    Stack() {
      Text(this.label)
        .fontSize(this.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(this.widthVp > 0 ? this.widthVp : '100%')
    .height(this.heightVp)
    .borderRadius(this.heightVp / 2)
    .backgroundBlurStyle(this.blurStyle)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
    .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
    .shadow(GlassTokens.SHADOW)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      this.onClickHandler();
    })
  }
}
