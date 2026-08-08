export enum RecordStatus {
  PENDING = 0,
  CONFIRMED = 1,
  DELETED = 2
}

export type RecordType = 'expense' | 'income';

export type RecordSource = 'pdf-text' | 'pdf-ocr' | 'img-ocr';

export type BudgetType = 'daily' | 'weekly' | 'monthly';

export interface CategoryInfo {
  name: string;
  keywords: string[];
  icon: string;
}

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

export const EXPENSE_CATEGORIES: CategoryInfo[] = [
  { name: '餐饮', keywords: ['餐厅', '火锅', '咖啡', '奶茶', '外卖', '食堂', '午餐', '晚餐', '早餐', '蛋糕', '面包', '快餐', '饮料', '零食', '麦当劳', '肯德基', '星巴克', '瑞幸', '汉堡', '烧烤', '小吃', '茶饮'], icon: 'cart.circle.fill' },
  { name: '交通', keywords: ['地铁', '公交', '打车', '出租车', '滴滴', '加油', '汽油', '高铁', '火车', '机票', '共享单车', '停车', '过路', '中石油', '中石化', '高速'], icon: 'car.circle.fill' },
  { name: '购物', keywords: ['超市', '商场', '淘宝', '京东', '天猫', '便利店', '百货', '服装', '鞋子', '箱包', '电商', '拼多多', '沃尔玛', '山姆', '永辉', '华联', '美团', '饿了么'], icon: 'cart.fill' },
  { name: '医疗', keywords: ['医院', '挂号', '药店', '药品', '诊所', '体检', '门诊', '手术', '医药'], icon: 'cross.case.fill' },
  { name: '娱乐', keywords: ['电影', 'KTV', '游戏', '旅游', '景点', '演出', '展览', '酒吧', '洗浴', '按摩', '咖啡厅'], icon: 'gamecontroller.fill' },
  { name: '居住', keywords: ['房租', '水费', '电费', '燃气', '物业', '房贷', '租金', '取暖', '水电'], icon: 'house.fill' },
  { name: '通讯', keywords: ['话费', '流量', '宽带', '快递', '邮费', '物流', '充值'], icon: 'antenna.radiowaves.expermimental.br' },
  { name: '其他', keywords: [], icon: 'scribble.variable' }
];

export const INCOME_CATEGORIES: CategoryInfo[] = [
  { name: '工资', keywords: ['工资', '薪水', '薪酬', '奖金', '补贴', '薪资'], icon: 'dollarsign.circle.fill' },
  { name: '理财', keywords: ['利息', '存款', '基金', '股票', '保险', '分红', '投资', '返息', '收益'], icon: 'banknote.fill' },
  { name: '其他', keywords: [], icon: 'scribble.variable' }
];

export const REFUND_KEYWORDS: string[] = ['退款', '退钱', '返现', '撤销', '退票', '退费', '充正', '退回'];

export const TOTAL_LABELS: string[] = [
  '价税合计', '合计', '总计', '总金额', '实收', '应收', '实付',
  '小计', '应付', '消费', '支出', '金额', '付款'
];