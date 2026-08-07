import { webview } from '@kit.ArkWeb';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassToolbar } from '../components/GlassToolbar';
import { GlassButton } from '../components/GlassButton';

@Entry
@Component
struct ProfilePrivacyPage {
  @StorageProp('darkMode') dark: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Column() {
      GlassToolbar({ dark: this.dark }) {
        Row({ space: 8 }) {
          GlassButton({ label: '← 返回', dark: this.dark, onClickHandler: () => { this.getUIContext().getRouter().back() }, heightVp: 40, fontSize: 14 })
          Blank()
          Text('隐私政策')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          Blank()
        }
        .width('100%')
      }

      Web({ src: $rawfile('privacy-policy.html'), controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .darkMode(this.dark ? WebDarkMode.On : WebDarkMode.Off)
        .forceDarkAccess(this.dark)
        .backgroundColor(this.dark ? '#1b1b22' : '#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : '#FFFFFF')
  }
}
