import { TextBlockInfo } from '../utils/PDFEditUtils';
import { GlassTokens } from '../theme/GlassTokens';
import { GlassButton } from './GlassButton';

@Component
export struct RewriteEditDialog {
  @Prop block: TextBlockInfo | null = null;
  @Prop text: string = '';
  @Prop sizeText: string = '';
  @Prop dark: boolean = false;
  @Prop errorMsg: string = '';
  onTextChange: (v: string) => void = () => {};
  onEditSizeChange: (v: string) => void = () => {};
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};

  build() {
    Stack() {
      Column({ space: 12 }) {
        Text('批量修改文字')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
        if (this.block) {
          Row({ space: 6 }) {
            Text('原字体')
              .fontSize(12)
              .fontColor(this.dark ? '#A9A9B5' : '#6B6B76')
            Text(this.block.fontName && this.block.fontName.length > 0 ? this.block.fontName : '未知（回退系统字体）')
              .fontSize(12)
              .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(10)
          .backgroundColor(this.dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)')
        }
        Column({ space: 4 }) {
          Text('新文字')
            .fontSize(12)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            .width('100%')
            .textAlign(TextAlign.Start)
          TextArea({ text: this.text })
            .height(90)
            .width('100%')
            .fontSize(14)
            .onChange((v: string) => {
              this.onTextChange(v);
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        Column({ space: 4 }) {
          Text('字号（pt）')
            .fontSize(12)
            .fontColor(this.dark ? GlassTokens.TEXT_DARK : GlassTokens.TEXT_LIGHT)
            .width('100%')
            .textAlign(TextAlign.Start)
          TextInput({ text: this.sizeText })
            .type(InputType.Number)
            .width('100%')
            .height(38)
            .fontSize(14)
            .onChange((v: string) => {
              this.onEditSizeChange(v);
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(12)
            .fontColor('#EF4444')
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        Row({ space: 12 }) {
          GlassButton({
            label: '取消', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 100,
            onClickHandler: () => {
              this.onCancel();
            }
          })
          GlassButton({
            label: '确定', dark: this.dark, heightVp: 40, fontSize: 14, widthVp: 100,
            onClickHandler: () => {
              this.onConfirm();
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .padding(20)
      .width('94%')
      .backgroundBlurStyle(GlassTokens.BLUR_MODAL)
      .backgroundColor(this.dark ? GlassTokens.BG_DARK : GlassTokens.BG_LIGHT)
      .borderRadius(20)
      .border({ width: 1, color: this.dark ? GlassTokens.BORDER_DARK : GlassTokens.BORDER_LIGHT })
      .shadow(GlassTokens.SHADOW)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
