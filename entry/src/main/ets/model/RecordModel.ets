import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export enum RecordStatus {
  PENDING = 0,
  CONFIRMED = 1,
  DELETED = 2
}

export type RecordType = 'expense' | 'income';

export type RecordSource = 'pdf-text' | 'pdf-ocr' | 'img-ocr' | 'excel';

export type BudgetType = 'daily' | 'weekly' | 'monthly';

export interface CategoryInfo {
  name: string;
  keywords: string[];
  icon: string;
}

export interface MerchantEntry {
  name: string;
  category: string;
}

export let MERCHANT_MAP: MerchantEntry[] = [
  { name: '沃尔玛', category: '购物' },
  { name: '山姆', category: '购物' },
  { name: '永辉', category: '购物' },
  { name: '华联', category: '购物' },
  { name: '肯德基', category: '餐饮' },
  { name: '麦当劳', category: '餐饮' },
  { name: '星巴克', category: '餐饮' },
  { name: '瑞幸', category: '餐饮' },
  { name: 'luckin', category: '餐饮' },
  { name: '农夫山泉芝麻店', category: '餐饮' },
  { name: '汉堡王', category: '餐饮' },
  { name: '饿了么', category: '餐饮' },
  { name: '美团打车', category: '交通' },
  { name: '美团外卖', category: '餐饮' },
  { name: '美团', category: '购物' },
  { name: '淘宝', category: '购物' },
  { name: '京东', category: '购物' },
  { name: '天猫', category: '购物' },
  { name: '拼多多', category: '购物' },
  { name: '滴滴', category: '交通' },
  { name: '中石油', category: '交通' },
  { name: '中石化', category: '交通' },
  { name: '地铁', category: '交通' },
];

export interface BookkeepingRecord {
  id: number | null;
  amount: number;
  type: RecordType;
  category: string;
  note: string;
  merchant: string | null;
  timestamp: number;
  dateStr: string;
  confidence: number;
  source: RecordSource;
  status: RecordStatus;
  createdAt: number;
}

export interface ParsedAmount {
  amount: number;
  type: 'expense' | 'income' | 'refund';
  category: string;
  confidence: number;
}

export interface Suggestion extends ParsedAmount {
  note: string;
  merchant?: string;
  date?: string;
  timestamp?: number;
  source: RecordSource;
}

export interface WeekDaySpending {
  day: string;
  dateStr: string;
  amount: number;
  isToday: boolean;
}

export interface CategoryStat {
  name: string;
  amount: number;
}

export interface BudgetConfig {
  daily: number;
  weekly: number;
  monthly: number;
}

export let EXPENSE_CATEGORIES: CategoryInfo[] = [
  { name: '餐饮', keywords: ['餐厅', '火锅', '咖啡', '奶茶', '外卖', '食堂', '午餐', '晚餐', '早餐', '蛋糕', '面包', '快餐', '饮料', '零食', '麦当劳', '肯德基', '星巴克', '瑞幸', '汉堡', '烧烤', '小吃', '茶饮', '红茶', '绿茶', '柠檬茶', '果茶', '炒饭', '盖饭', '面条', '米线', '米粉', '泡芙', '甜品', '烘焙', '西点', '奶昔', '冰淇淋', '冰激凌', '糕点', '芝士', '葡萄', '美式', '拿铁', '草莓', '杨枝甘露', '厚乳', '生椰', 'luckin', '咖啡厅', '农夫山泉'], icon: 'cart.circle.fill' },
  { name: '交通', keywords: ['地铁', '公交', '打车', '出租车', '滴滴', '加油', '汽油', '高铁', '火车', '机票', '共享单车', '停车', '过路', '中石油', '中石化', '高速'], icon: 'car.circle.fill' },
  { name: '购物', keywords: ['超市', '商场', '淘宝', '京东', '天猫', '便利店', '百货', '服装', '鞋子', '箱包', '电商', '拼多多', '沃尔玛', '山姆', '永辉', '华联', '美团'], icon: 'cart.fill' },
  { name: '医疗', keywords: ['医院', '挂号', '药店', '药品', '诊所', '体检', '门诊', '手术', '医药'], icon: 'cross.case.fill' },
  { name: '娱乐', keywords: ['电影', 'KTV', '游戏', '旅游', '景点', '演出', '展览', '酒吧', '洗浴', '按摩'], icon: 'gamecontroller.fill' },
  { name: '居住', keywords: ['房租', '水费', '电费', '燃气', '物业', '房贷', '租金', '取暖', '水电'], icon: 'house.fill' },
  { name: '通讯', keywords: ['话费', '流量', '宽带', '快递', '邮费', '物流', '充值'], icon: 'antenna.radiowaves.expermimental.br' },
  { name: '其他', keywords: [], icon: 'scribble.variable' }
];

export let INCOME_CATEGORIES: CategoryInfo[] = [
  { name: '工资', keywords: ['工资', '薪水', '薪酬', '奖金', '补贴', '薪资'], icon: 'dollarsign.circle.fill' },
  { name: '理财', keywords: ['利息', '存款', '基金', '股票', '保险', '分红', '投资', '返息', '收益'], icon: 'banknote.fill' },
  { name: '其他', keywords: [], icon: 'scribble.variable' }
];

export let REFUND_KEYWORDS: string[] = ['退款', '退钱', '返现', '撤销', '退票', '退费', '充正', '退回'];

export let TOTAL_LABELS: string[] = [
  '价税合计', '合计', '总计', '总金额', '实收', '应收', '实付',
  '小计', '应付', '消费', '支出', '金额', '付款'
];

// 商户排除词（加载期被 record_model.json 覆盖）
export let MERCHANT_EXCLUDE: string[] = ['退回', '退款', '支付成功', '交易成功', '银行卡', '尾号', '余额', '零钱', '账单', '红包', '转账'];

// 品名/商户行「元信息」黑名单：营养/计量/营销/状态行，如「咖啡因」「食品安全理赔」「已下架」
export let MERCHANT_EXCLUDE_META: string[] = [
  '成功通知', '支付成功', '交易成功', '食品安全', '理赔', '慢必赔', '已下架', '已售罄', '默认', '咖啡因', '热量',
  '脂肪', '蛋白质', '碳水', '能量', '正常冰', '去冰', '少冰', '多冰', '热饮', '冷饮', '免配送费', '新品', '热卖',
  '精选', '广告', '直播', 'BIG SALE', '大杯', '中杯', '小杯', 'kcal', 'mg', '毫升', '克'
];

const RULE_DATA_FILE = 'ml/record_model.json';

interface RuleDataConfig {
  expenseCategories?: CategoryInfo[];
  incomeCategories?: CategoryInfo[];
  merchantMap?: MerchantEntry[];
  merchantExclude?: string[];
  merchantExcludeMeta?: string[];
  refundKeywords?: string[];
  totalLabels?: string[];
}

let ruleDataLoaded = false;

/**
 * 从 rawfile 加载分类/商户/黑名单规则数据（单次幂等），加载后替换各 export let。
 * EntryAbility 启动时调用；加载失败或缺失时保留内置默认值。
 */
export async function ensureRuleDataLoaded(context: common.Context): Promise<void> {
  if (ruleDataLoaded) {
    return;
  }
  try {
    const bytes = await context.resourceManager.getRawFileContent(RULE_DATA_FILE);
    const decoder = new util.TextDecoder();
    const content = decoder.decodeToString(new Uint8Array(bytes.buffer));
    const cfg = JSON.parse(content) as RuleDataConfig;
    if (cfg.expenseCategories && cfg.expenseCategories.length > 0) {
      EXPENSE_CATEGORIES = cfg.expenseCategories;
    }
    if (cfg.incomeCategories && cfg.incomeCategories.length > 0) {
      INCOME_CATEGORIES = cfg.incomeCategories;
    }
    if (cfg.merchantMap && cfg.merchantMap.length > 0) {
      MERCHANT_MAP = cfg.merchantMap;
    }
    if (cfg.refundKeywords && cfg.refundKeywords.length > 0) {
      REFUND_KEYWORDS = cfg.refundKeywords;
    }
    if (cfg.totalLabels && cfg.totalLabels.length > 0) {
      TOTAL_LABELS = cfg.totalLabels;
    }
    if (cfg.merchantExclude && cfg.merchantExclude.length > 0) {
      MERCHANT_EXCLUDE = cfg.merchantExclude;
    }
    if (cfg.merchantExcludeMeta && cfg.merchantExcludeMeta.length > 0) {
      MERCHANT_EXCLUDE_META = cfg.merchantExcludeMeta;
    }
    ruleDataLoaded = true;
    console.log('RuleData loaded from record_model.json: expenseCats=' + EXPENSE_CATEGORIES.length
      + ' incomeCats=' + INCOME_CATEGORIES.length + ' merchantMap=' + MERCHANT_MAP.length
      + ' meta=' + MERCHANT_EXCLUDE_META.length);
  } catch (err) {
    console.error('ensureRuleDataLoaded failed, keep defaults', JSON.stringify(err));
    ruleDataLoaded = true;
  }
}