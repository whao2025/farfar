import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { privacyManager } from '@kit.AppGalleryKit';
import { Breakpoint } from '../theme/Breakpoint';
import { DarkModeStore, DarkModeOverride } from '../utils/DarkModeStore';
import { ensureRuleDataLoaded } from '../model/RecordModel';

class DarkModeEnvCallback extends EnvironmentCallback {
  onConfigurationUpdated(config: Configuration): void {
    if (AppStorage.get<boolean>('userDarkModeOverride') === true) {
      return;
    }
    AppStorage.setOrCreate('darkMode',
      config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
  }
}

export default class EntryAbility extends UIAbility {
  private envCallbackId: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 应用级初始化可在此扩展
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const appCtx = this.context.getApplicationContext();
    this.envCallbackId = appCtx.on('environment', new DarkModeEnvCallback());
    AppStorage.setOrCreate('userDarkModeOverride', false);
    AppStorage.setOrCreate('fileFilterMode', 'all');
    this.syncDarkModeFromSystem();
    ensureRuleDataLoaded(this.context);
    windowStage.loadContent('pages/Splash', (err: BusinessError) => {
        if (err.code) {
          return;
        }
        this.ensurePrivacyConsent();
        this.applyStoredDarkMode();
        windowStage.getMainWindow((errGet: BusinessError, win: window.Window) => {
        if (errGet.code) {
          return;
        }
        const rect: window.Rect = win.getWindowProperties().windowRect;
        const density = display.getDefaultDisplaySync().densityPixels;
        AppStorage.setOrCreate('windowWidth', rect.width);
        AppStorage.setOrCreate('windowHeight', rect.height);
        AppStorage.setOrCreate('windowDensity', density);
        AppStorage.setOrCreate('breakpoint', Breakpoint.calcFromPx(rect.width, density));
        if (AppStorage.get<boolean>('userDarkModeOverride') !== true) {
          AppStorage.setOrCreate('darkMode',
            this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        }
        win.on('windowSizeChange', (size: window.Size) => {
          const density = display.getDefaultDisplaySync().densityPixels;
          AppStorage.setOrCreate('windowWidth', size.width);
          AppStorage.setOrCreate('windowHeight', size.height);
          AppStorage.setOrCreate('windowDensity', density);
          AppStorage.setOrCreate('breakpoint', Breakpoint.calcFromPx(size.width, density));
        });
        try {
          if (canIUse('SystemCapability.Window.SessionManager')) {
            display.on('foldStatusChange', (status: display.FoldStatus) => {
              AppStorage.setOrCreate('foldStatus', status);
            });
          }
        } catch (e) {
          // 不支持折叠屏的设备忽略
        }
      });
    });
  }

  private syncDarkModeFromSystem(): void {
    AppStorage.setOrCreate('darkMode',
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private async applyStoredDarkMode(): Promise<void> {
    const mode = await DarkModeStore.load(this.context);
    if (mode === 'system') {
      return;
    }
    AppStorage.setOrCreate('darkMode', mode === 'dark');
    AppStorage.setOrCreate('userDarkModeOverride', true);
  }

  private ensurePrivacyConsent(): void {
    privacyManager.requestAppPrivacyConsent(this.context).catch(
      (err: BusinessError) => {
        if (err.code !== 1006700003) {
          console.error('requestAppPrivacyConsent failed', JSON.stringify(err));
        }
      }
    );
  }

  onDestroy(): void {
    const appCtx = this.context.getApplicationContext();
    appCtx.off('environment', this.envCallbackId);
    super.onDestroy();
  }
}
