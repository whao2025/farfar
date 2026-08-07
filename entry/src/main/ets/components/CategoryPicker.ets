import { GlassTokens } from '../theme/GlassTokens';

const CATEGORY_ICONS: Record<string, Resource> = {
  '餐饮': $r('sys.symbol.fork_knife'),
  '交通': $r('sys.symbol.car'),
  '购物': $r('sys.symbol.cart'),
  '医疗': $r('sys.symbol.cross_case'),
  '娱乐': $r('sys.symbol.gamecontroller'),
  '居住': $r('sys.symbol.house'),
  '通讯': $r('sys.symbol.wifi'),
  '其他': $r('sys.symbol.doc_text'),
  '工资': $r('sys.symbol.person'),
  '理财': $r('sys.symbol.creditcard')
};

@Component
export struct CategoryPicker {
  @Prop categories: string[] = [];
  @Prop selected: string = '';
  @Prop dark: boolean = false;
  onPick: (name: string) => void = () => {};

  private iconOf(name: string): Resource {
    return CATEGORY_ICONS[name] ?? $r('sys.symbol.doc_text');
  }

  @Builder
  chip(name: string) {
    Row({ space: 6 }) {
      SymbolGlyph(this.iconOf(name))
        .fontSize(18)
        .fontColor([this.selected === name
          ? $r('sys.color.icon_emphasize')
          : $r('sys.color.icon_tertiary')])
      Text(name)
        .fontSize(14)
        .fontWeight(this.selected === name ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected === name
          ? $r('sys.color.font_emphasize')
          : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .padding({ left: 14, right: 14, top: 9, bottom: 9 })
    .borderRadius(20)
    .backgroundBlurStyle(GlassTokens.BLUR_BUTTON)
    .backgroundColor(this.selected === name
      ? $r('sys.color.comp_background_tertiary')
      : Color.Transparent)
    .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
    .shadow(GlassTokens.SHADOW)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      this.onPick(name);
    })
  }

  build() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.categories, (c: string) => {
          this.chip(c)
        }, (c: string) => c)
      }
      .padding({ left: 2, right: 2 })
      .justifyContent(FlexAlign.Start)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height(48)
  }
}