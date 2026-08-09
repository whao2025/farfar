#!/usr/bin/env python3
"""
Synthesize training samples from the app's keyword rules (RecordModel.ets),
produce scalable bookkeeping text corpus for ALBERT fine-tuning.

Produces JSONL: each line {text, category, type, amount, merchant, source}.
Expected seed: data/real_training.json ({records:[...]} wrapper, from
DatasetExportUtil.exportToJSON).

Output records are labeled per the app's EXPENSE/INCOME keyword tables so the
model learns the same input distribution the device RuleCategorizer uses.
"""

import json
import random
import argparse
from collections import defaultdict
from pathlib import Path

# Mirrors entry/src/main/ets/model/RecordModel.ets keyword tables.
EXPENSE = {
    '餐饮': ['餐厅', '火锅', '咖啡', '奶茶', '外卖', '食堂', '午餐', '晚餐', '早餐',
             '蛋糕', '面包', '快餐', '饮料', '零食', '麦当劳', '肯德基', '星巴克',
             '瑞幸', '汉堡', '烧烤', '小吃', '茶饮', '美团'],
    '交通': ['地铁', '公交', '打车', '出租车', '滴滴', '加油', '汽油', '高铁', '火车',
             '机票', '共享单车', '停车', '过路', '中石油', '中石化', '高速'],
    '购物': ['超市', '商场', '淘宝', '京东', '天猫', '便利店', '百货', '服装', '鞋子',
             '箱包', '电商', '拼多多', '沃尔玛', '山姆', '永辉', '华联'],
    '医疗': ['医院', '挂号', '药店', '药品', '诊所', '体检', '门诊', '手术', '医药'],
    '娱乐': ['电影', 'KTV', '游戏', '旅游', '景点', '演出', '展览', '酒吧', '洗浴',
             '按摩', '咖啡厅'],
    '居住': ['房租', '水费', '电费', '燃气', '物业', '房贷', '租金', '取暖', '水电'],
    '通讯': ['话费', '流量', '宽带', '快递', '邮费', '物流', '充值'],
}
INCOME = {
    '工资': ['工资', '薪水', '薪酬', '奖金', '补贴', '薪资'],
    '理财': ['利息', '存款', '基金', '股票', '保险', '分红', '投资', '返息', '收益'],
}

# Least-count guarantee per category (real + synthetic combined).
DEFAULT_TARGET = 400
AMOUNTS_EXPENSE = ['3', '5', '8', '10', '12.5', '15', '18', '20', '25.5', '35', '48',
                   '60', '75', '89', '99', '120', '150.8', '200', '328', '489', '599']
AMOUNTS_INCOME = ['2500', '3000', '4500', '6000', '8000', '10000', '15000',
                  '20000', '3500', '1800']

PATTERNS_EXPENSE = [
    '{m}', '{m} {a}元', '{v}{m} {a}', '{v} 在{m} 消费 {a}', '{m} 消费{amt}',
    '{v}{m} 支付{a}', '{m} {a}元',
]
PATTERNS_INCOME = [
    '{m} {a}元', '{m}到账{a}', '{v}{m} {a}', '{m}发放{a}',
]
VERBS = ['支付宝', '微信', '扫码', '订', '充值', '支付']
ENGINE = {'餐饮': '吃', '交通': '出行', '购物': '购物', '医疗': '看病', '娱乐': '娱乐',
          '居住': '交', '通讯': '充'}


def load_real(path: Path):
    raw = json.loads(path.read_text(encoding='utf-8'))
    if isinstance(raw, dict):
        records = raw.get('records', [])
    else:
        records = raw
    out = []
    for r in records:
        out.append({
            'text': (r.get('text') or '').strip(),
            'category': r.get('category', '其他'),
            'type': r.get('type', 'expense'),
            'amount': r.get('amount', 0),
            'merchant': (r.get('merchant') or '').strip(),
            'source': r.get('source', 'pdf-text'),
        })
    return out


def make_expense(cat, rng, n):
    kws = EXPENSE[cat]
    rows = []
    for _ in range(n):
        kw = rng.choice(kws)
        m = rng.choice([kw, kw + rng.choice(['店', '广场', '中心', '旗舰店', ''])])
        amt = rng.choice(AMOUNTS_EXPENSE)
        tpl = rng.choice(PATTERNS_EXPENSE)
        text = tpl.format(m=m, a=amt, amt=amt, v=rng.choice(VERBS))
        rows.append({
            'text': text, 'category': cat, 'type': 'expense',
            'amount': -float(amt), 'merchant': m, 'source': 'pdf-text',
        })
    return rows


def make_income(cat, rng, n):
    kws = INCOME[cat]
    rows = []
    for _ in range(n):
        kw = rng.choice(kws)
        amt = rng.choice(AMOUNTS_INCOME)
        tpl = rng.choice(PATTERNS_INCOME)
        text = tpl.format(m=kw, a=amt, v=rng.choice(['银行', '公司', '单位']))
        rows.append({
            'text': text, 'category': cat, 'type': 'income',
            'amount': float(amt), 'merchant': kw, 'source': 'pdf-text',
        })
    return rows


def main():
    parser = argparse.ArgumentParser(description='Synthesize bookkeeping corpus')
    parser.add_argument('--real', default='data/real_training.json')
    parser.add_argument('--out', default='data/synthetic.jsonl')
    parser.add_argument('--per-category', type=int, default=DEFAULT_TARGET)
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    real_path = Path(args.real)
    real = load_real(real_path) if real_path.exists() else []

    counts = defaultdict(int)
    for r in real:
        counts[(r['type'], r['category'])] += 1

    rows = [dict(r) for r in real]
    for cat in EXPENSE:
        needed = max(0, args.per_category - counts[('expense', cat)])
        rows.extend(make_expense(cat, rng, needed))
    for cat in INCOME:
        needed = max(0, args.per_category - counts[('income', cat)])
        rows.extend(make_income(cat, rng, needed))

    rng.shuffle(rows)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')

    dist = defaultdict(int)
    real_dist = defaultdict(int)
    for r in rows:
        dist[r['category']] += 1
    for r in real:
        real_dist[r['category']] += 1
    print(f'real={len(real)} total={len(rows)}')
    for cat in sorted(dist):
        print(f'  {cat}: total={dist[cat]} real={real_dist[cat]}')
    print(f'wrote {out_path}')


if __name__ == '__main__':
    main()