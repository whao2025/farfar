import { HdsTabsController } from '@kit.UIDesignKit';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassToolbar } from '../components/GlassToolbar';
import { EditTab } from './tabs/EditTab';
import { ConvertTab } from './tabs/ConvertTab';
import { BookkeepingTab } from './tabs/BookkeepingTab';
import { ProfileTab } from './tabs/ProfileTab';

@Entry
@Component
struct Home {
  @StorageProp('breakpoint') breakpoint: string = 'sm';
  @StorageProp('darkMode') dark: boolean = false;
  @State currentIndex: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();

  @Builder
  tabBarItem(symbol: Resource, label: string, index: number) {
    Column({ space: 3 }) {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([this.currentIndex === index
          ? (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          : '#8A8A96'])
        .opacity(this.currentIndex === index ? 1 : 0.55)
      Text(label)
        .fontSize(13)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [this.dark ? '#1b1b22' : '#dfe7ff', 0],
            [this.dark ? '#2a2440' : '#f6e9ff', 1]
          ]
        })

      Column() {
        GlassToolbar({ dark: this.dark }) {
          Row() {
            Text('freepdf')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          }
          .width('100%')
        }

        Tabs({ index: this.currentIndex, controller: this.tabsController }) {
          TabContent() {
            EditTab()
          }
          .tabBar(this.tabBarItem($r('sys.symbol.square_and_pencil'), '编辑', 0))

          TabContent() {
            ConvertTab()
          }
          .tabBar(this.tabBarItem($r('sys.symbol.arrow_left_arrow_right'), '转化', 1))

          TabContent() {
            BookkeepingTab()
          }
          .tabBar(this.tabBarItem($r('sys.symbol.wallet'), '记账', 2))

          TabContent() {
            ProfileTab()
          }
          .tabBar(this.tabBarItem($r('sys.symbol.person'), '我的', 3))
        }
        .barPosition(BarPosition.End)
        .vertical(false)
        .scrollable(false)
        .barOverlap(true)
        .barBackgroundBlurStyle(GlassTokens.BLUR_PANEL)
        .barMode(BarMode.Fixed)
        .width('100%')
        .layoutWeight(1)
        .onChange((index: number) => {
          this.currentIndex = index;
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}