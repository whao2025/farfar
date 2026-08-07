import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { AmountParser } from '../../main/ets/utils/AmountParser';
import { AutoCategorizer } from '../../main/ets/utils/AutoCategorizer';

const ALIPAY_TEXT = `
交易时间:2023-10-15 14:32:11
交易类型:消费
交易对方:沃尔玥超市
商品描述:苹果面包
金额:¥28.50
支付方式:余额
订单号:20231015220012345678
`.trim();

const WECHAT_REFUND = `
微信支付
商户:肯德基快餐店
交易时间:2024-03-20 18:00:00
交易类型:退款
金额:-¥54.80
`.trim();

const RECEIPT_FULL = `
沃尔玥超市
地址:北京市朝阳区xxx
电话:010-12345678
开票日期:2024-03-15 16:28:02
品名  数量  单位价  金额
苹果  2.5kg 8.80  22.00
牛奶  1    32.00 32.00
小计                    54.00
税率    13%    税额 7.02
合计                   ¥61.02
付款方式:微信支付
`.trim();

export default function amountParserTest() {
  describe('AmountParser - 基础金额提取', () => {
    it('提取简单金额: 合计 ¥54.80', () => {
      const result = AmountParser.parseLine('合计 ¥54.80');
      expect(result?.amount).assertEqual(54.80);
    });

    it('提取整数金额: 100 元', () => {
      const result = AmountParser.parseLine('消费 100 元');
      expect(result?.amount).assertEqual(100);
    });

    it('提取负金额 (退款): -¥28.80', () => {
      const result = AmountParser.parseLine('退款 -¥28.80');
      expect(result?.amount).assertEqual(-28.80);
    });

    it('全角字符: －￥２８．８０', () => {
      const result = AmountParser.parseLine('退款 －￥２８．８０');
      expect(result?.amount).assertEqual(-28.80);
    });

    it('千位分隔: ¥1,234.56', () => {
      const result = AmountParser.parseLine('合计 ¥1,234.56');
      expect(result?.amount).assertEqual(1234.56);
    });
  });

  describe('AmountParser - 退款处理', () => {
    it('退款文本自动为负: 退款金额: ¥28.80', () => {
      const result = AmountParser.parseLine('退款金额: ¥28.80');
      expect(result?.amount).assertEqual(-28.80);
      expect(result?.type).assertEqual('refund');
    });
  });

  describe('AmountParser - 多金额处理', () => {
    it('优先提取合计: 小计54 + 税7.02 + 合计61.02', () => {
      const text = '小计54.00\n税额7.02\n合计61.02';
      const results = AmountParser.parse(text);
      const total = results.find(r => Math.abs(r.amount - 61.02) < 0.01);
      expect(total).assertDefined();
    });

    it('过滤订单号: 2023101522001457521050262559', () => {
      const result = AmountParser.parseLine('订单号:2019072122001457521050262559\n合计:¥54.80');
      expect(result?.amount).assertEqual(54.80);
    });

    it('过滤电话号码: 010-12345678', () => {
      const result = AmountParser.parseLine('电话:010-12345678\n金额:¥28.80');
      expect(result?.amount).assertEqual(28.80);
    });
  });

  describe('AmountParser - 分类', () => {
    it('餐饮关键词: 午餐/咖啡', () => {
      expect(AmountParser.parseLine('午餐 35 元')?.category).assertEqual('餐饮');
      expect(AmountParser.parseLine('咖啡 25元')?.category).assertEqual('餐饮');
    });

    it('交通关键词: 地铁/打车', () => {
      expect(AmountParser.parseLine('地铁 5 元')?.category).assertEqual('交通');
      expect(AmountParser.parseLine('打车 28.5')?.category).assertEqual('交通');
    });

    it('购物关键词: 淘宝/超市', () => {
      expect(AmountParser.parseLine('淘宝 199.00')?.category).assertEqual('购物');
      expect(AmountParser.parseLine('沃尔玛 54.00 元')?.category).assertEqual('购物');
    });

    it('其他 (无关键字匹配)', () => {
      const result = AmountParser.parseLine('未知支出 100 元');
      expect(result?.category).assertEqual('其他');
    });
  });

  describe('AmountParser - 真实场景测试', () => {
    it('解析 Alipay 支付宝收据', () => {
      const results = AmountParser.parse(ALIPAY_TEXT);
      const amount = results.find(r => Math.abs(r.amount - 28.50) < 0.01);
      expect(amount).assertDefined();
      expect(amount?.category).assertEqual('购物');
    });

    it('解析微信退款', () => {
      const results = AmountParser.parse(WECHAT_REFUND);
      const refund = results.find(r => r.amount === -54.80);
      expect(refund).assertDefined();
    });

    it('解析超市小票, 提取合计 61.02', () => {
      const results = AmountParser.parse(RECEIPT_FULL);
      const total = results.find(r => Math.abs(r.amount - 61.02) < 0.01);
      expect(total).assertDefined();
    });
  });

  describe('AmountParser - 边界情况', () => {
    it('无金额返回 null', () => {
      expect(AmountParser.parseLine('没有金额的文本')).assertNull();
    });

    it('空字符串返回 null', () => {
      expect(AmountParser.parseLine('')).assertNull();
    });
  });

  describe('AmountParser - 修复回归', () => {
    it('千分位/合计不被截断: 合计 1280.00 = 1280', () => {
      const result = AmountParser.parseLine('合计 1280.00');
      expect(result?.amount).assertEqual(1280);
    });

    it('无千分位的 4 位金额保留完整: 12000 = 12000', () => {
      const result = AmountParser.parseLine('金额 12000 元');
      expect(result?.amount).assertEqual(12000);
    });

    it('超过万元上限的兜底金额也被过滤', () => {
      const result = AmountParser.parseLine('合计 99999999 元');
      expect(result).assertNull();
    });

    it('垃圾行 (日期/电话/页签) 不产生记录', () => {
      expect(AmountParser.parseLine('2024-03-20 18:00:00')).assertNull();
      expect(AmountParser.parseLine('订单号:20231015220012345678')).assertNull();
      expect(AmountParser.parseLine('--- 第 1 页 ---')).assertNull();
    });

    it('退款负金额被识别为 refund + 负值', () => {
      const result = AmountParser.parseLine('退款 ¥54.80');
      expect(result?.amount).assertEqual(-54.80);
      expect(result?.type).assertEqual('refund');
    });

    it('回写负号金额 parse 返回', () => {
      const results = AmountParser.parse('退款 -￥28.80\n吐槽\n2024 年 3 月 20 日');
      const refund = results.find(r => Math.abs(r.amount - 28.80) < 0.01 && r.type === 'refund');
      expect(refund).assertDefined();
    });

    it('跨行上下文: 退款行后面的消费不串扰', () => {
      const text = '退款\n金额 100\n午餐 25';
      const results = AmountParser.parse(text);
      const refund = results.find(r => r.amount === -100);
      const lunch = results.find(r => r.amount === 25 && r.category === '餐饮');
      expect(refund).assertDefined();
      expect(lunch).assertDefined();
    });
  });

  describe('AutoCategorizer - 批量优化', () => {
    it('批量解析并增强商户分类', async () => {
      const text = '合计 ¥54.80 沃尔玛\n消费 25 元 肯德基';
      const result = await AutoCategorizer.categorizeBatch(text, 'pdf-text');
      expect(result.summary.total).assertEqual(2);
      expect(result.suggestions[0].category).assertEqual('购物');
    });

    it('验证建议记录格式', () => {
      const s = {
        amount: 28.50,
        type: 'expense' as const,
        category: '购物',
        confidence: 0.9,
        note: '沃尔玛购买',
        source: 'pdf-text' as const
      };
      expect(AutoCategorizer.validateSuggestion(s)).assertTrue();
    });
  });
}

export { amountParserTest };