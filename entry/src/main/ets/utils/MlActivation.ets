import { common } from '@kit.AbilityKit';
import { mlOptions } from '../components/MLOptionsSwitch';
import { AutoCategorizer } from './AutoCategorizer';
import { RuleCategorizer } from './RuleCategorizer';
import { getBillClassifier } from './ml/BillClassifier';

/**
 * ML 智能分类激活（记帐链路公共入口）。
 * 读取 mlOptions 开关 → init 分类器 → 按结果 setEnhance。
 * BookkeepingTab（三条记帐入口）与 ProfileTab（开关页）共用，避免仅切「我的」tab 才生效。
 */
export async function activateMLIfEnabled(context: common.Context): Promise<void> {
  try {
    await mlOptions.init(context);
    if (!mlOptions.isEnabled()) {
      AutoCategorizer.setEnhance(null);
      return;
    }
    await getBillClassifier().init(context);
    if (getBillClassifier().isLoaded()) {
      AutoCategorizer.setEnhance(RuleCategorizer.mlEnhance);
    } else {
      AutoCategorizer.setEnhance(null);
    }
  } catch (err) {
    console.error('activateML failed', JSON.stringify(err));
    AutoCategorizer.setEnhance(null);
  }
}

export async function deactivateML(): Promise<void> {
  AutoCategorizer.setEnhance(null);
}

/**
 * 图片记账自动启用 ML（决策：不受 mlOptions 开关约束）。
 * 先同步挂 enhance（mlEnhance 内部已守卫 isLoaded，未加载时透传），再后台补载模型——消除首批发解析竞态。
 * PDF/文本记账仍走 activateMLIfEnabled 的开关语义。
 */
export async function ensureMlForImg(context: common.Context): Promise<void> {
  AutoCategorizer.setEnhance(RuleCategorizer.mlEnhance);
  try {
    if (!getBillClassifier().isLoaded()) {
      await getBillClassifier().init(context);
    }
  } catch (err) {
    console.error('ensureMlForImg init failed', JSON.stringify(err));
  }
}