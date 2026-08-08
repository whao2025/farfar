import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class MLOptions {
  private static instance: MLOptions | null = null;
  private prefs: preferences.Preferences | null = null;
  private static readonly PREFS_NAME = 'freepdf_ml_prefs';
  private static readonly KEY_ENABLED = 'ml_classification_enabled';
  private enabled: boolean = false;

  private constructor() {}

  static getInstance(): MLOptions {
    if (!MLOptions.instance) {
      MLOptions.instance = new MLOptions();
    }
    return MLOptions.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.prefs) return;

    this.prefs = await preferences.getPreferences(context, { name: MLOptions.PREFS_NAME });
    this.enabled = this.prefs.getSync(MLOptions.KEY_ENABLED, false) as boolean;
  }

  async setEnabled(enabled: boolean): Promise<void> {
    this.enabled = enabled;
    if (this.prefs) {
      this.prefs.putSync(MLOptions.KEY_ENABLED, enabled);
      await this.prefs.flush();
    }
  }

  isEnabled(): boolean {
    return this.enabled;
  }
}

export const mlOptions = MLOptions.getInstance();