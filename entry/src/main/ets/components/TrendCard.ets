import { GlassTokens } from '../theme/GlassTokens';
import { WeekDaySpending, CategoryStat } from '../model/RecordModel';
import curves from '@ohos.curves';

@Component
export struct TrendCard {
  @Prop weekData: WeekDaySpending[] = [];
  @Prop categoryStats: CategoryStat[] = [];
  @Prop dailyBudget: number = 0;
  @Prop monthlyExpense: number = 0;
  @Prop lastMonthExpense: number = 0;
  @Prop weekTotal: number = 0;
  @Prop dark: boolean = false;

  private getMaxAmount(): number {
    let max = 0;
    for (let i = 0; i < this.weekData.length; i++) {
      if (this.weekData[i].amount > max) {
        max = this.weekData[i].amount;
      }
    }
    return Math.max(max, this.dailyBudget, 1);
  }

  private barHeight(amount: number): number {
    const max = this.getMaxAmount();
    if (max <= 0) return 0;
    const ratio = amount / max;
    return Math.max(Math.min(ratio * 96, 96), 4);
  }

  private budgetLineY(): number {
    const max = this.getMaxAmount();
    if (max <= 0 || this.dailyBudget <= 0) return -1;
    const ratio = this.dailyBudget / max;
    return Math.max(Math.min(ratio * 96, 96), 0);
  }

  private shortAmount(n: number): string {
    if (n >= 10000) return (n / 10000).toFixed(1) + 'w';
    return Math.round(n).toString();
  }

  private catColor(i: number): string {
    const palette: string[] = [GlassTokens.ACCENT, GlassTokens.ACCENT_SKY, GlassTokens.PURPLE, GlassTokens.CYAN, GlassTokens.WARN];
    return palette[i % palette.length];
  }

  private weekMax(): number {
    let max = 0;
    for (let i = 0; i < this.weekData.length; i++) {
      if (this.weekData[i].amount > max) {
        max = this.weekData[i].amount;
      }
    }
    return max;
  }

  private isMaxBar(amount: number): boolean {
    const m = this.weekMax();
    return amount > 0 && m > 0 && amount === m;
  }

  private isOverBudget(amount: number): boolean {
    return this.dailyBudget > 0 && amount > this.dailyBudget;
  }

  private barGradient(item: WeekDaySpending, isToday: boolean): Array<[string, number]> {
    if (isToday) {
      return [[GlassTokens.ACCENT_BLUE, 0], [GlassTokens.ACCENT_SKY, 1]];
    }
    if (this.isOverBudget(item.amount)) {
      return [[GlassTokens.DANGER, 0], [GlassTokens.WARN, 1]];
    }
    if (this.isMaxBar(item.amount)) {
      return [[GlassTokens.PURPLE, 0], [GlassTokens.CYAN, 1]];
    }
    return [[GlassTokens.NEUTRAL_DARK, 0], [GlassTokens.NEUTRAL_LIGHT, 1]];
  }

  private vsLastText(): string {
    if (this.lastMonthExpense <= 0) return '无上月对比';
    const diff = this.monthlyExpense - this.lastMonthExpense;
    const pct = diff / this.lastMonthExpense * 100;
    if (pct === 0) return '与上月持平';
    return pct > 0 ? '较上月 ↑ ' + Math.round(pct) + '%' : '较上月 ↓ ' + Math.abs(Math.round(pct)) + '%';
  }

  private vsLastColor(): string {
    if (this.lastMonthExpense <= 0) return this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80';
    const pct = (this.monthlyExpense - this.lastMonthExpense) / this.lastMonthExpense;
    if (pct === 0) return this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT;
    return pct > 0 ? GlassTokens.DANGER : GlassTokens.SUCCESS;
  }

  @Builder
  BarItem(item: WeekDaySpending, isToday: boolean) {
    Column() {
      Text(item.amount > 0 ? this.shortAmount(item.amount) : '')
        .fontSize(9)
        .fontColor(this.isOverBudget(item.amount)
          ? GlassTokens.DANGER
          : (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT))
        .margin({ bottom: 4 })
        .maxLines(1)

      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width(20)
          .height(this.barHeight(item.amount))
          .borderRadius({ topLeft: 5, topRight: 5, bottomLeft: 3, bottomRight: 3 })
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: this.barGradient(item, isToday)
          })
          .animation({ duration: 400, curve: curves.springMotion(0.6, 0.9, 0) })

        if (this.budgetLineY() >= 0) {
          Row()
            .width('100%')
            .height(2)
            .alignSelf(ItemAlign.End)
            .margin({ bottom: this.budgetLineY() })
            .backgroundColor(this.dark ? GlassTokens.HALO_DARK : GlassTokens.HALO_LIGHT)
        }
      }
      .width('100%')
      .height(96)
      .backgroundColor(this.dark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)')
      .borderRadius(6)

      Text(item.day)
        .fontSize(11)
        .fontColor(isToday
          ? (this.dark ? GlassTokens.ACCENT_BLUE : GlassTokens.ACCENT_SKY)
          : (this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT))
        .fontWeight(isToday ? FontWeight.Bold : FontWeight.Normal)
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  @Builder
  CatSlice(item: CategoryStat, idx: number) {
    Row({ space: 8 }) {
      Column()
        .width(10)
        .height(10)
        .borderRadius(5)
        .backgroundColor(this.catColor(idx))
      Text(item.name)
        .fontSize(11)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
        .layoutWeight(1)
        .maxLines(1)
      Text(this.shortAmount(item.amount))
        .fontSize(11)
        .fontColor(this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
    }
    .width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Text('本周支出')
          .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
        Blank()
        Text('¥' + this.shortAmount(this.weekTotal))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.dark ? GlassTokens.ACCENT_BLUE : GlassTokens.ACCENT_SKY)
      }
      .width('100%')

      Row() {
        ForEach(this.weekData, (item: WeekDaySpending) => {
          this.BarItem(item, item.isToday)
        }, (item: WeekDaySpending) => item.dateStr)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 6 })

      Text(this.vsLastText())
        .fontSize(11)
        .fontColor(this.vsLastColor())
        .width('100%')
        .textAlign(TextAlign.End)
        .margin({ top: 4 })

      if (this.categoryStats.length > 0) {
        Column({ space: 8 }) {
          Text('分类占比')
            .fontSize(12)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK + '80' : GlassTokens.TEXT_LIGHT + '80')
            .width('100%')
            .margin({ top: 6 })

          ForEach(this.categoryStats, (item: CategoryStat, idx: number) => {
            this.CatSlice(item, idx)
          }, (item: CategoryStat, idx: number) => idx.toString())
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(18)
    .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
    .borderColor(this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT)
    .borderWidth(1)
    .borderRadius(20)
    .shadow(GlassTokens.SHADOW)
  }
}