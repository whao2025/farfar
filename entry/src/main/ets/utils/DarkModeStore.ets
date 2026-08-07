import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREFS_NAME = 'freepdf_settings';
const KEY_DARK_OVERRIDE = 'darkModeOverride';

export type DarkModeOverride = 'system' | 'light' | 'dark';

export class DarkModeStore {
  static async load(context: common.Context): Promise<DarkModeOverride> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
      const value = prefs.getSync(KEY_DARK_OVERRIDE, 'system') as DarkModeOverride;
      return value;
    } catch (err) {
      console.error('DarkModeStore.load failed', JSON.stringify(err));
      return 'system';
    }
  }

  static async save(context: common.Context, mode: DarkModeOverride): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
      prefs.putSync(KEY_DARK_OVERRIDE, mode);
      await prefs.flush();
    } catch (err) {
      console.error('DarkModeStore.save failed', JSON.stringify(err));
    }
  }
}
