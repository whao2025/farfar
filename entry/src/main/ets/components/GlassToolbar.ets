import { GlassTokens } from '../theme/GlassTokens';

@Component
export struct GlassToolbar {
  @Prop dark: boolean = false;
  @Prop heightVp: number = 64;
  @BuilderParam content: () => void = this.defaultContent;

  @Builder
  private defaultContent() {
  }

  build() {
    Row() {
      this.content();
    }
    .width('100%')
    .height(this.heightVp)
    .padding({ left: 16, right: 16 })
    .backgroundBlurStyle(GlassTokens.BLUR_TOOLBAR)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
    .border({
      width: { top: 0, bottom: 1, left: 0, right: 0 },
      color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT
    })
    .shadow(GlassTokens.SHADOW)
  }
}
