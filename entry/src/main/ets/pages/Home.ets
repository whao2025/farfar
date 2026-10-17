import { HdsTabsController } from '@kit.UIDesignKit';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassToolbar } from '../components/GlassToolbar';
import { EditTab } from './tabs/EditTab';
import { ConvertTab } from './tabs/ConvertTab';
import { BookkeepingTab } from './tabs/BookkeepingTab';
import { ProfileTab } from './tabs/ProfileTab';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import curves from '@ohos.curves';
import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SmartReachBar } from '../components/SmartReachBar';
import { pickImagesToSandbox, ocrImagesToText } from '../utils/BookOcr';

@Entry
@Component
struct Home {
  @StorageProp('breakpoint') breakpoint: string = 'sm';
  @StorageProp('darkMode') dark: boolean = false;
  @StorageProp('windowWidth') @Watch('onWinResize') winW: number = 0;
  @StorageProp('windowHeight') @Watch('onWinResize') winH: number = 0;
  @StorageProp('windowDensity') density: number = 0;
  @State currentIndex: number = 0;
  @State capInnerW: number = 0;
  @State barX: number = 0;
  @State barY: number = 0;
  @State hidden: boolean = true;
  private tabsController: HdsTabsController = new HdsTabsController();

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
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
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
    const aboveNav = H - 150 - this.BAR_H / 2 - this.EDGE;
    const contentBottom = H * 0.68 - this.BAR_H / 2;
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
    if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
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
      return true;
    }
  }

  private onAddRecord(): void {
    if (this.hidden) {
      return;
    }
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ManualEntryPage'
      });
    } catch (err) {
      console.error('onAddRecord pushUrl failed:', JSON.stringify(err));
    }
  }

  private onImportPdf(): void {
    if (this.hidden) {
      return;
    }
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/PDFConvertPage',
        params: {
          mode: 'pdfToCredit'
        }
      });
    } catch (err) {
      console.error('onImportPdf pushUrl failed:', JSON.stringify(err));
    }
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
        this.getUIContext().getPromptAction().showToast({ message: '未识别到文字' });
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
      try {
        this.getUIContext().getPromptAction().showToast({ message: '图片识别失败' });
      } catch (toastErr) {
        console.error('showToast failed:', JSON.stringify(toastErr));
      }
    }
  }

  private indicatorWidth(): number {
    return this.capInnerW > 0 ? this.capInnerW / 4 : 0;
  }

  private indicatorX(): number {
    return this.capInnerW * (this.currentIndex / 4 - 3 / 8);
  }

  @Builder
  capTabItem(symbol: Resource, label: string, index: number) {
    Column({ space: 3 }) {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([this.currentIndex === index ? '#6C8CFF' : '#8A8A96'])
        .opacity(this.currentIndex === index ? 1 : 0.6)
      Text(label)
        .fontSize(11)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? '#6C8CFF' : '#8A8A96')
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.tabsController.changeIndex(index);
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .hitTestBehavior(HitTestMode.Block)
  }

  @Builder
  capTabBar() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        this.capTabItem($r('sys.symbol.square_and_pencil'), '编辑', 0)
        this.capTabItem($r('sys.symbol.arrow_left_arrow_right'), '转化', 1)
        this.capTabItem($r('sys.symbol.wallet'), '记账', 2)
        this.capTabItem($r('sys.symbol.person'), '我的', 3)
      }
      .width('100%')
      .height('100%')
      .onAreaChange((oldVal: Area, newVal: Area) => {
        this.capInnerW = Number(newVal.width);
      })

      Column()
        .width(this.indicatorWidth())
        .height(54)
        .borderRadius(27)
        .backgroundColor(this.dark ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.55)')
        .offset({ x: this.indicatorX() })
        .animation({ curve: curves.springMotion(0.4, 0.85, 0) })
    }
    .width('94%')
    .height(66)
    .borderRadius(33)
    .backgroundBlurStyle(GlassTokens.BLUR_PANEL)
    .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
    .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
    .shadow(GlassTokens.SHADOW)
    .margin({ bottom: 24 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [this.dark ? '#1b1b22' : '#dfe7ff', 0],
            [this.dark ? '#2a2440' : '#f6e9ff', 1]
          ]
        })

      Column() {
        GlassToolbar({ dark: this.dark }) {
          Row() {
            Text('freepdf')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
          }
          .width('100%')
        }

        Tabs({ index: this.currentIndex, controller: this.tabsController }) {
          TabContent() {
            EditTab()
          }

          TabContent() {
            ConvertTab()
          }

          TabContent() {
            BookkeepingTab()
          }

          TabContent() {
            ProfileTab()
          }
        }
        .barPosition(BarPosition.End)
        .vertical(false)
        .scrollable(true)
        .barHeight(0)
        .barBackgroundColor(Color.Transparent)
        .width('100%')
        .layoutWeight(1)
        .onChange((index: number) => {
          this.currentIndex = index;
        })

        this.capTabBar()
      }
      .width('100%')
      .height('100%')

      if (this.currentIndex === 2) {
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
        .zIndex(10)
      }
    }
    .width('100%')
    .height('100%')
  }
}
