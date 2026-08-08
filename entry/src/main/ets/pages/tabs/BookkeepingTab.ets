import { GlassTokens } from '../../theme/GlassTokens';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import curves from '@ohos.curves';
import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BudgetCard } from '../../components/BudgetCard';
import { TrendCard } from '../../components/TrendCard';
import { GlassButton } from '../../components/GlassButton';
import { recordDb } from '../../utils/RecordDatabase';
import { budgetPrefs } from '../../utils/BudgetPreferences';
import { BookkeepingRecord, WeekDaySpending, CategoryStat } from '../../model/RecordModel';
import { SmartReachBar } from '../../components/SmartReachBar';
import { pickImagesToSandbox, ocrImagesToText } from '../../utils/BookOcr';

@Component
export struct BookkeepingTab {
  @StorageProp('darkMode') dark: boolean = false;
  @StorageProp('recordRefreshTick') @Watch('onRefreshTick') refreshTick: number = 0;
  @StorageProp('windowWidth') @Watch('onWinResize') winW: number = 0;
  @StorageProp('windowHeight') @Watch('onWinResize') winH: number = 0;
  @StorageProp('windowDensity') density: number = 0;
  @State monthlyBudget: number = 0;
  @State monthlyExpense: number = 0;
  @State weeklyExpense: number = 0;
  @State dailyExpense: number = 0;
  @State lastMonthExpense: number = 0;
  @State weekData: WeekDaySpending[] = [];
  @State categoryStats: CategoryStat[] = [];
  @State barX: number = 0;
  @State barY: number = 0;
  @State hidden: boolean = true;

  private lastSide: string = 'right';
  private currentSide: string = 'right';
  private subscribed: boolean = false;
  private motionSubscribed: string = '';
  private motionOperatingCb: (s: motion.OperatingHandStatus) => void = () => {};
  private motionHoldingCb: (s: motion.HoldingHandStatus) => void = () => {};
  private dragging: boolean = false;
  private dragStartX: number = 0;
  private dragCooldown: boolean = false;
  private hideTimer: number = -1;
  private hideToken: number = 0;
  private avoidLeft: number = 0;
  private avoidRight: number = 0;
  private readonly BAR_W: number = 68 * 0.6 + 8 * 0.6 * 2;  // 约 50.4vp
  private readonly BAR_H: number = (68 * 0.6) * 3 + 16 * 0.6 * 2 + 8 * 0.6 * 2;  // 三球约 151.2vp
  private readonly EDGE: number = 16;
  private readonly EXPOSE: number = (68 * 0.6 + 8 * 0.6 * 2) * 0.5;  // 收起露一半（≈25.2vp）
  private readonly SAFE_MARGIN: number = 6;
  private readonly HIDE_TIMEOUT: number = 10000;

  aboutToAppear() {
    const ctx = this.getUIContext().getHostContext();
    if (ctx) {
      recordDb.init(ctx as common.Context).then(() => {
        budgetPrefs.init(ctx as common.Context).then(() => {
          this.loadBudget();
          this.loadStats();
        }).catch((err: Error) => console.error('prefs init failed:', err));
      }).catch((err: Error) => console.error('db init failed:', err));
    }
    if (!this.subscribed) {
      this.subscribeMotion();
    }
    this.hidden = true;
    this.barX = this.calcHiddenX(this.currentSide);
    this.barY = this.centerY();
    this.loadAvoidArea();
  }

  aboutToDisappear(): void {
    if (this.subscribed) {
      this.subscribed = false;
      if (this.motionSubscribed === 'operating') {
        try {
          motion.off('operatingHandChanged', this.motionOperatingCb);
        } catch (e) {
          // 忽略
        }
      } else if (this.motionSubscribed === 'holding') {
        try {
          motion.off('holdingHandChanged', this.motionHoldingCb);
        } catch (e) {
          // 忽略
        }
      }
      this.motionSubscribed = '';
    }
    this.clearHideTimer();
    this.dragging = false;
    this.dragCooldown = false;
  }

  private rightX(): number {
    return Math.max(this.EDGE, (this.winW / Math.max(this.density, 1)) - this.BAR_W - this.EDGE);
  }

  private widthVp(): number {
    return this.winW / Math.max(this.density, 1);
  }

  private leftHiddenX(): number {
    const edge = Math.max(this.EDGE, this.avoidLeft + this.SAFE_MARGIN);
    return edge - this.BAR_W + this.EXPOSE;
  }

  private rightHiddenX(): number {
    return this.widthVp() - this.avoidRight - this.SAFE_MARGIN - this.EXPOSE;
  }

  private calcHiddenX(side: string): number {
    return side === 'left' ? this.leftHiddenX() : this.rightHiddenX();
  }

  private centerY(): number {
    const H = this.winH / Math.max(this.density, 1);
    // 底部导航浮动胶囊约占屏高 140vp，胶囊高 ~151vp
    // 中心位置 = H - 140 - 50 - EDGE
    const aboveNav = H - 150 - this.BAR_H / 2 - this.EDGE;
    const contentBottom = H * 0.68 - this.BAR_H / 2;  // 内容区约 68% 处
    return Math.max(this.EDGE, Math.min(contentBottom, aboveNav));
  }

  private loadAvoidArea(): void {
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      return;
    }
    try {
      window.getLastWindow(ctx as common.Context).then((win: window.Window) => {
        const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM_GESTURE);
        const d = Math.max(this.density, 1);
        this.avoidLeft = (avoid.leftRect ? avoid.leftRect.width : 0) / d;
        this.avoidRight = (avoid.rightRect ? avoid.rightRect.width : 0) / d;
      }).catch(() => {
        this.avoidLeft = 0;
        this.avoidRight = 0;
      });
    } catch (e) {
      this.avoidLeft = 0;
      this.avoidRight = 0;
    }
  }

  private onWinResize(): void {
    this.loadAvoidArea();
    if (this.hidden) {
      const tx = this.calcHiddenX(this.currentSide);
      const ty = this.centerY();
      this.getUIContext().animateTo({ curve: curves.springMotion(0.6, 0.9, 0) }, () => {
        this.barX = tx;
        this.barY = ty;
      });
      return;
    }
    const tx = this.lastSide === 'left' ? this.EDGE : this.rightX();
    const ty = this.centerY();
    this.getUIContext().animateTo({ curve: curves.springMotion(0.6, 0.9, 0) }, () => {
      this.barX = tx;
      this.barY = ty;
    });
  }

  private moveToSide(side: string): void {
    if (this.winW <= 0 || this.dragging || this.dragCooldown || side === this.currentSide) {
      return;
    }
    this.currentSide = side;
    if (this.hidden) {
      // 半隐藏态换手：实际挪到新侧隐藏位（半露），否则用户无视觉反馈
      this.lastSide = side;
      const tx = this.calcHiddenX(side);
      const ty = this.centerY();
      this.getUIContext().animateTo({ curve: curves.springMotion(0.6, 0.9, 0) }, () => {
        this.barX = tx;
        this.barY = ty;
      });
      return;
    }
    const tx = side === 'left' ? this.EDGE : this.rightX();
    const ty = this.centerY();
    this.getUIContext().animateTo({ curve: curves.springMotion(0.6, 0.9, 0) }, () => {
      this.barX = tx;
      this.barY = ty;
    });
  }

  private clearHideTimer(): void {
    this.hideToken++;
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  private resetHideTimer(): void {
    if (this.hidden) {
      return;
    }
    this.clearHideTimer();
    const t: number = this.hideToken;
    const token: number = t;
    this.hideTimer = setTimeout(() => {
      if (this.hideToken !== token) {
        return;
      }
      this.hideToCurrentSide();
    }, this.HIDE_TIMEOUT);
  }

  private hideToCurrentSide(): void {
    this.clearHideTimer();
    const tx = this.calcHiddenX(this.currentSide);
    const ty = this.centerY();
    this.getUIContext().animateTo({ curve: curves.springMotion(0.6, 0.9, 0) }, () => {
      this.barX = tx;
      this.barY = ty;
    });
    this.hidden = true;
  }

  private onDragStartCb(): void {
    this.hidden = false;
    this.dragging = true;
    this.dragStartX = this.barX;
  }

  private onDragMoveCb(dx: number): void {
    const minX = this.calcHiddenX('left');
    const maxX = this.rightHiddenX();
    if (maxX > minX) {
      this.barX = Math.min(maxX, Math.max(minX, this.dragStartX + dx));
    } else {
      this.barX = this.draggingFlagGuard(this.dragStartX + dx);
    }
  }

  private draggingFlagGuard(x: number): number {
    const minX = this.EDGE;
    const maxX = this.rightX();
    return Math.min(maxX, Math.max(minX, x));
  }

  private onDragEndCb(): void {
    this.dragging = false;
    const minX = this.calcHiddenX('left');
    const maxX = this.rightHiddenX();
    if (maxX > minX && (this.barX <= minX + this.BAR_W * 0.5 || this.barX >= maxX - this.BAR_W * 0.5)) {
      const side = this.barX <= minX + this.BAR_W * 0.5 ? 'left' : 'right';
      this.currentSide = side;
      this.lastSide = side;
      this.hideToCurrentSide();
      this.armCooldown();
      return;
    }
    const mid = (this.EDGE + this.rightX()) / 2;
    const side = this.barX < mid ? 'left' : 'right';
    const tx = side === 'left' ? this.EDGE : this.rightX();
    this.currentSide = side;
    this.lastSide = side;
    this.hidden = false;
    this.getUIContext().animateTo({ curve: curves.springMotion(0.6, 0.9, 0) }, () => {
      this.barX = tx;
      this.barY = this.centerY();
    });
    this.armCooldown();
    this.resetHideTimer();
  }

  private armCooldown(): void {
    this.dragCooldown = true;
    const t = this.hideToken;
    setTimeout(() => {
      if (this.hideToken === t) {
        this.dragCooldown = false;
      }
    }, 300);
  }

  private subscribeMotion(): void {
    if (!this.canUseMotion()) {
      console.warn('motion syscap unsupported, keep right side');
      return;
    }
    let anySuccess: boolean = false;
    // ① 一次性查询：独立 try/catch，失败不牵连订阅；LEFT 时同步校正初始侧
    try {
      const st = motion.getRecentOperatingHandStatus();
      if (st === motion.OperatingHandStatus.LEFT_HAND_OPERATED) {
        this.currentSide = 'left';
        this.lastSide = 'left';
      }
    } catch (err) {
      const e = err as BusinessError;
      console.error('motion getRecent failed:', e.code, e.message);
    }
    // ② 主订阅 holdingHandChanged（@since20，握持手语义，设备实测可用）
    try {
      this.motionHoldingCb = (s: motion.HoldingHandStatus): void => {
        if (s === motion.HoldingHandStatus.LEFT_HAND_HELD) {
          console.info('motion event -> LEFT_HAND_HELD');
          this.moveToSide('left');
          this.resetHideTimer();
        } else if (s === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
          console.info('motion event -> RIGHT_HAND_HELD');
          this.moveToSide('right');
          this.resetHideTimer();
        } else {
          console.info('motion event ->', s);
        }
      };
      motion.on('holdingHandChanged', this.motionHoldingCb);
      this.motionSubscribed = 'holding';
      anySuccess = true;
    } catch (err) {
      const e = err as BusinessError;
      console.error('motion on holdingHandChanged failed:', e.code, e.message);
    }
    // ③ 备订阅 operatingHandChanged（@since15，ACTIVITY_MOTION 或 DETECT_GESTURE）：主订阅失败才尝试
    if (!anySuccess) {
      try {
        this.motionOperatingCb = (s: motion.OperatingHandStatus): void => {
          if (s === motion.OperatingHandStatus.LEFT_HAND_OPERATED) {
            console.info('motion event -> LEFT_HAND_OPERATED');
            this.moveToSide('left');
            this.resetHideTimer();
          } else if (s === motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
            console.info('motion event -> RIGHT_HAND_OPERATED');
            this.moveToSide('right');
            this.resetHideTimer();
          } else {
            console.info('motion event ->', s);
          }
        };
        motion.on('operatingHandChanged', this.motionOperatingCb);
        this.motionSubscribed = 'operating';
        anySuccess = true;
      } catch (err) {
        const e = err as BusinessError;
        console.error('motion on operatingHandChanged failed:', e.code, e.message);
      }
    }
    if (anySuccess) {
      this.subscribed = true;
      console.info(`motion subscribed ok, type=${this.motionSubscribed}`);
    } else {
      console.error('motion both subscriptions failed, keep right side');
    }
  }

  private canUseMotion(): boolean {
    try {
      return canIUse('SystemCapability.MultimodalAwareness.Motion');
    } catch (err) {
      // 无法判断时放行，交给订阅 catch 兜底
      return true;
    }
  }

  private onRefreshTick(): void {
    this.loadStats();
  }

  private async loadBudget(): Promise<void> {
    try {
      this.monthlyBudget = await budgetPrefs.getMonthlyBudget();
    } catch (err) {
      console.error('loadBudget failed:', err);
    }
  }

  private async onBudgetSaved(): Promise<void> {
    await this.loadBudget();
    await this.loadStats();
    this.bumpTick();
  }

  private bumpTick(): void {
    const tick = AppStorage.get<number>('recordRefreshTick') ?? 0;
    AppStorage.setOrCreate('recordRefreshTick', tick + 1);
  }

  private async loadStats(): Promise<void> {
    try {
      const today = new Date();
      const dateStr = this.formatDate(today);
      const monthPrefix = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;

      const weekStart = this.getWeekStartDate(today);
      const weekEnd = this.getWeekEndDate(today);

      const dailyRecords = recordDb.getByDateRange(dateStr, dateStr);
      const monthRecords = recordDb.getByDateRange(
        monthPrefix + '-01',
        monthPrefix + '-31'
      );
      const weekRecords = recordDb.getByDateRange(
        this.formatDate(weekStart),
        this.formatDate(weekEnd)
      );
      const lastMonthPrefix = this.lastMonthPrefix(today);
      const lastMonthTotal = recordDb.getMonthlyTotals(lastMonthPrefix);

      const daily = await dailyRecords;
      const month = await monthRecords;
      const week = await weekRecords;
      const last = await lastMonthTotal;

      this.dailyExpense = this.sumExpense(daily);
      this.monthlyExpense = this.sumExpense(month);
      this.weeklyExpense = this.sumExpense(week);
      this.lastMonthExpense = Math.abs(last.expense);
      this.weekData = this.buildWeek(weekStart, week);
      this.categoryStats = this.aggregateByCategory(month);
    } catch (err) {
      console.error('loadStats failed:', err);
    }
  }

  private sumExpense(records: BookkeepingRecord[]): number {
    return Math.abs(records.reduce((sum, r) =>
      sum + (r.type === 'expense' ? r.amount : 0), 0));
  }

  private buildWeek(weekStart: Date, weekRecords: BookkeepingRecord[]): WeekDaySpending[] {
    const today = new Date();
    const todayStr = this.formatDate(today);
    const dayNames = ['日', '一', '二', '三', '四', '五', '六'];
    const map = new Map<string, number>();
    for (const r of weekRecords) {
      const key = r.dateStr;
      const amt = Math.abs((r.type === 'expense' ? r.amount : 0));
      map.set(key, (map.get(key) ?? 0) + amt);
    }
    const data: WeekDaySpending[] = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + i);
      const ds = this.formatDate(d);
      data.push({
        day: dayNames[d.getDay()],
        dateStr: ds,
        amount: map.get(ds) ?? 0,
        isToday: ds === todayStr
      });
    }
    return data;
  }

  private aggregateByCategory(records: BookkeepingRecord[]): CategoryStat[] {
    const map = new Map<string, number>();
    for (const r of records) {
      if (r.type !== 'expense') continue;
      const key = r.category || '其他';
      const add = Math.abs(r.amount);
      map.set(key, (map.get(key) ?? 0) + add);
    }
    const list: CategoryStat[] = [];
    map.forEach((value, key) => {
      list.push({ name: key, amount: value });
    });
    list.sort((a: CategoryStat, b: CategoryStat) => b.amount - a.amount);
    const top: CategoryStat[] = [];
    let rest = 0;
    for (let i = 0; i < list.length; i++) {
      if (i < 4) {
        top.push(list[i]);
      } else {
        rest += list[i].amount;
      }
    }
    if (rest > 0) {
      const existing = top.find((s) => s.name === '其他');
      if (existing) {
        existing.amount += rest;
      } else {
        top.push({ name: '其他', amount: rest });
      }
    }
    return top;
  }

  private lastMonthPrefix(d: Date): string {
    const y = d.getFullYear();
    const m = d.getMonth();
    if (m === 0) {
      return `${y - 1}-12`;
    }
    return `${y}-${String(m).padStart(2, '0')}`;
  }

  private formatDate(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  private getWeekStartDate(d: Date): Date {
    const start = new Date(d);
    const day = start.getDay();
    const diff = start.getDate() - day + (day === 0 ? -6 : 1);
    start.setDate(diff);
    return start;
  }

  private getWeekEndDate(d: Date): Date {
    const end = new Date(d);
    const start = this.getWeekStartDate(d);
    end.setDate(start.getDate() + 6);
    return end;
  }

  private onAddRecord(): void {
    if (this.hidden) {
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/ManualEntryPage'
    });
  }

  private onImportPdf(): void {
    if (this.hidden) {
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/PDFConvertPage',
      params: {
        mode: 'pdfToCredit'
      }
    });
  }

  private async onImportImage(): Promise<void> {
    if (this.hidden) {
      return;
    }
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      return;
    }
    try {
      const paths = await pickImagesToSandbox(ctx as common.Context);
      if (paths.length === 0) {
        return;
      }
      const text = await ocrImagesToText(paths);
      if (text.trim().length === 0) {
        promptAction.showToast({ message: '未识别到文字' });
        return;
      }
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/BookkeepingConfirmPage',
        params: {
          source: 'img-ocr',
          text: text,
          mode: 'full'
        }
      });
    } catch (err) {
      console.error('onImportImage failed', JSON.stringify(err));
      promptAction.showToast({ message: '图片识别失败' });
    }
  }

  build() {
    Stack() {
      Column({ space: 16 }) {
        Scroll() {
          Column({ space: 16 }) {
            BudgetCard({
              monthlyBudget: this.monthlyBudget,
              dailyBudget: Math.round(this.monthlyBudget / 30),
              weeklyBudget: Math.round(this.monthlyBudget / (30 / 7)),
              actualDaily: this.dailyExpense,
              actualWeekly: this.weeklyExpense,
              actualMonthly: this.monthlyExpense,
              dark: this.dark,
              onBudgetSaved: () => this.onBudgetSaved()
            })
            .width('100%')

            TrendCard({
              weekData: this.weekData,
              categoryStats: this.categoryStats,
              dailyBudget: Math.round(this.monthlyBudget / 30),
              monthlyExpense: this.monthlyExpense,
              lastMonthExpense: this.lastMonthExpense,
              weekTotal: this.weeklyExpense,
              dark: this.dark
            })
            .width('100%')
          }
          .width('100%')
          .padding({ bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .padding(20)

      // 智感握姿浮动记账栏（左手滑左 / 右手滑右），代替原 "+" 悬浮球与底部按钮
      SmartReachBar({
        dark: this.dark,
        onManual: () => this.onAddRecord(),
        onPdfAuto: () => this.onImportPdf(),
        onImageImport: () => this.onImportImage(),
        onReachDragStart: () => this.onDragStartCb(),
        onReachDragMove: (dx: number) => this.onDragMoveCb(dx),
        onReachDragEnd: () => this.onDragEndCb()
      })
      .position({ x: this.barX, y: this.barY })
    }
    .width('100%')
    .height('100%')
  }
}