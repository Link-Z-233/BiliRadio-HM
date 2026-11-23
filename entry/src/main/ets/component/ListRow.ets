import { Constants } from '../service/Constants';
import { connectStr, StrState } from '../service/V2State';

@Builder
function rowEmptyTrailing() {
}

@ComponentV2
export struct ListRow {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param valueText: string = '';
  @Param rowIcon: Resource | undefined = undefined;
  // 账号行头像（v0.4-Part1-ux-fixes US9）：非空时圆形头像替代图标，加载失败回退 rowIcon
  @Param avatarUrl: string = '';
  @Param showArrow: boolean = false;
  @Param showToggle: boolean = false;
  @Param toggleOn: boolean = false;
  @Param showDivider: boolean = false;
  @Param danger: boolean = false;
  // 大会员徽标（v0.4-Part2 T012）：true 时标题侧渲染「大会员」小标签
  @Param vipBadge: boolean = false;
  // 选中态（v0.8-part4 US5）：图标与标题主题色高亮 + 行尾 ✓（样式对齐 OptionSheet 主题色 ✓）
  @Param selected: boolean = false;
  // 图标旋转角（度）：倒序等需旋转区分的模式图标，默认 0 渲染不变
  @Param iconRotate: number = 0;
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Param rowAction: () => void = (): void => {};
  @Param toggleChange: (on: boolean) => void = (_on: boolean): void => {};
  // 行尾自定义槽位（v0.8-part2-settings-regroup）：渲染于 valueText 之后、toggle/arrow 之前；未传零渲染
  @BuilderParam trailing: () => void = rowEmptyTrailing;
  @Local isPressed: boolean = false;
  @Local avatarBroken: boolean = false;

  // 头像 URL 更换时重置失败标记，允许新 URL 重新尝试加载
  @Monitor('avatarUrl')
  onAvatarUrlChanged(): void {
    this.avatarBroken = false;
  }

  @Builder
  private iconSlot(icon: Resource | undefined) {
    if (this.avatarUrl !== '' && !this.avatarBroken) {
      Image(this.avatarUrl)
        .width(Constants.ACCOUNT_AVATAR_SIZE)
        .height(Constants.ACCOUNT_AVATAR_SIZE)
        .borderRadius(Constants.ACCOUNT_AVATAR_SIZE / 2)
        .objectFit(ImageFit.Cover)
        .margin({ right: Constants.TOKEN_SPACE_M })
        .onError(() => {
          this.avatarBroken = true;
        })
    } else if (icon !== undefined) {
      SymbolGlyph(icon)
        .fontSize(Constants.TOKEN_FONT_TITLE_L)
        .fontColor([this.selected ? this.accentColor.value : $r('app.color.text_secondary')])
        .rotate({ angle: this.iconRotate })
        .margin({ right: Constants.TOKEN_SPACE_M })
    }
  }

  build() {
    Column() {
      Row() {
        this.iconSlot(this.rowIcon)
        Column() {
          Row() {
            Text(this.title)
              .fontSize(Constants.TOKEN_FONT_TITLE)
              .fontColor(this.danger ? $r('app.color.danger_red') :
                (this.selected ? this.accentColor.value : $r('app.color.text_primary')))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.vipBadge) {
              Text('大会员')
                .fontSize(Constants.TOKEN_FONT_BODY_S)
                .fontColor($r('app.color.vip_badge_text'))
                .backgroundColor($r('app.color.vip_badge_bg'))
                .borderRadius(Constants.TOKEN_RADIUS_S)
                .padding({ left: Constants.TOKEN_SPACE_6, right: Constants.TOKEN_SPACE_6, top: Constants.TOKEN_SPACE_XS, bottom: Constants.TOKEN_SPACE_XS })
                .margin({ left: Constants.TOKEN_SPACE_6 })
            }
          }
          if (this.subtitle !== '') {
            Text(this.subtitle)
              .fontSize(Constants.TOKEN_FONT_BODY_S)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: Constants.TOKEN_SPACE_XXS })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.valueText !== '') {
          Text(this.valueText)
            .fontSize(Constants.TOKEN_FONT_BODY_M)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ right: Constants.TOKEN_SPACE_6 })
        }
        this.trailing()
        if (this.selected) {
          // 行尾选中 ✓：主题色，字号对齐 OptionSheet 选中项
          Text('✓')
            .fontSize(Constants.TOKEN_FONT_BODY_L)
            .fontColor(this.accentColor.value)
        }
        if (this.showToggle) {
          Toggle({ type: ToggleType.Switch, isOn: this.toggleOn })
            .selectedColor(this.accentColor.value)
            .onChange((isOn: boolean) => {
              this.toggleChange(isOn);
            })
        }
        if (this.showArrow) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(Constants.TOKEN_FONT_TITLE)
            .fontColor([$r('app.color.placeholder_color')])
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 54 })
      .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_S, bottom: Constants.TOKEN_SPACE_S })
      .backgroundColor(this.isPressed ? $r('app.color.item_pressed_background') : Color.Transparent)
      .onTouch((e: TouchEvent): void => {
        if (e.type === TouchType.Down) {
          this.isPressed = true;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.isPressed = false;
        }
      })
      .onClick(() => {
        this.rowAction();
      })
      if (this.showDivider) {
        Divider()
          .color($r('app.color.track_color'))
          .margin({ left: Constants.TOKEN_SPACE_L })
      }
    }
    .width('100%')
  }
}
