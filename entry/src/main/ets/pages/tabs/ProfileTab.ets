import { GlassTokens } from '../../theme/GlassTokens';
import { GlassButton } from '../../components/GlassButton';
import { bundleManager, common } from '@kit.AbilityKit';
import { DarkModeStore } from '../../utils/DarkModeStore';

@Component
export struct ProfileTab {
  @StorageProp('darkMode') dark: boolean = false;
  @State versionName: string = '';

  aboutToAppear(): void {
    this.loadVersion();
  }

  private async loadVersion(): Promise<void> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (err) {
      console.error('loadVersion failed', JSON.stringify(err));
      this.versionName = '';
    }
  }

  private onToggleDark(isOn: boolean): void {
    AppStorage.setOrCreate('darkMode', isOn);
    AppStorage.setOrCreate('userDarkModeOverride', true);
    const host = this.getUIContext().getHostContext();
    if (!host) {
      return;
    }
    const ctx = host as common.Context;
    DarkModeStore.save(ctx, isOn ? 'dark' : 'light');
  }

  build() {
    Column({ space: 16 }) {
      Column({ space: 12 }) {
        Text('我的')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
      }
      .padding({ left: 24, right: 24, top: 24, bottom: 8 })

      Column({ space: 0 }) {
        Row() {
          Text('深色模式')
            .fontSize(15)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.dark })
            .onChange((isOn: boolean) => {
              this.onToggleDark(isOn);
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 14 })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
      .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
      .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
      .shadow(GlassTokens.SHADOW)

      Column({ space: 0 }) {
        Row() {
          Text('隐私政策')
            .fontSize(15)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          Blank()
          Text('›')
            .fontSize(20)
            .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 14 })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/ProfilePrivacyPage' });
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
      .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
      .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
      .shadow(GlassTokens.SHADOW)

      Text('freepdf v' + (this.versionName || '1.1.0'))
        .fontSize(12)
        .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
