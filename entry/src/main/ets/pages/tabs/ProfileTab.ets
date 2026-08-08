import { GlassTokens } from '../../theme/GlassTokens';
import { GlassButton } from '../../components/GlassButton';
import { bundleManager, common } from '@kit.AbilityKit';
import { DarkModeStore } from '../../utils/DarkModeStore';
import { mlOptions } from '../../components/MLOptionsSwitch';
import { AutoCategorizer } from '../../utils/AutoCategorizer';
import { RuleCategorizer } from '../../utils/RuleCategorizer';
import { getBillClassifier } from '../../utils/ml/BillClassifier';
import { Suggestion } from '../../model/RecordModel';
import { datasetExportUtil, TrainingRecord } from '../../utils/DatasetExportUtil';
import { saveSandboxFile } from '../../utils/PickerSaveUtils';
import { fileIo } from '@kit.CoreFileKit';

@Component
export struct ProfileTab {
  @StorageProp('darkMode') dark: boolean = false;
  @State versionName: string = '';
  @State mlEnabled: boolean = false;
  @State exporting: boolean = false;

  aboutToAppear(): void {
    this.loadVersion();
    this.loadMlState();
  }

  private async loadMlState(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) {
      return;
    }
    const ctx = host as common.Context;
    try {
      await mlOptions.init(ctx);
      this.mlEnabled = mlOptions.isEnabled();
    } catch (err) {
      console.error('loadMlState failed', JSON.stringify(err));
    }
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

  private async onToggleML(isOn: boolean): Promise<void> {
    this.mlEnabled = isOn;
    const host = this.getUIContext().getHostContext();
    if (!host) {
      return;
    }
    const ctx = host as common.Context;
    try {
      await mlOptions.init(ctx);
      await mlOptions.setEnabled(isOn);
      if (isOn) {
        try {
          await getBillClassifier().init(ctx);
          if (getBillClassifier().isLoaded()) {
            AutoCategorizer.setEnhance(RuleCategorizer.mlEnhance);
          } else {
            AutoCategorizer.setEnhance(null);
          }
        } catch (err) {
          console.error('ML classifier init failed', JSON.stringify(err));
          AutoCategorizer.setEnhance(null);
        }
      } else {
        AutoCategorizer.setEnhance(null);
      }
    } catch (err) {
      console.error('onToggleML failed', JSON.stringify(err));
    }
  }

  private async onExportTrainingData(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
      return;
    }
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    const ctx = host as common.Context;
    let outPath: string = '';
    try {
      await datasetExportUtil.init(ctx);
      let records: TrainingRecord[] = [];
      try {
        records = await datasetExportUtil.getAllRecords();
      } catch (err) {
        console.error('getAllRecords failed', JSON.stringify(err));
        records = [];
      }
      if (records.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '暂无已确认记录' });
        return;
      }
      outPath = ctx.filesDir + '/training_' + Date.now() + '.json';
      await datasetExportUtil.exportToJSON(outPath, records);
      const saved = await saveSandboxFile(ctx, outPath, 'freepdf_training_data.json', '.json');
      if (saved) {
        this.getUIContext().getPromptAction().showToast({ message: `已导出 ${records.length} 条记录` });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '已生成，未选择导出位置' });
      }
    } catch (err) {
      console.error('export training data failed', JSON.stringify(err));
      this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
    } finally {
      if (outPath) {
        try {
          await fileIo.unlink(outPath);
        } catch (err) {
          console.error('cleanup temp export failed', JSON.stringify(err));
        }
      }
      this.exporting = false;
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
    Scroll() {
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
          Text('智能分类')
            .fontSize(15)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.mlEnabled })
            .onChange((isOn: boolean) => {
              this.onToggleML(isOn);
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
          Column({ space: 4 }) {
            Text('导出训练数据')
              .fontSize(15)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            Text('已确认记账数据，供本地模型训练')
              .fontSize(12)
              .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Text(this.exporting ? '导出中…' : '›')
            .fontSize(20)
            .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 14 })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
        .enabled(!this.exporting)
        .onClick(() => {
          this.onExportTrainingData();
        })
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
      .padding(24)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
