import { Constants } from '../service/Constants';
import { connectNum, connectStr, NumState, StrState } from '../service/V2State';

@ComponentV2
export struct OptionSheet {
  @Param title: string = '';
  @Param notice: string = '';
  @Param optionLabels: string[] = [];
  @Param selectedLabel: string = '';
  @Param onSelect: (index: number) => void = (_index: number): void => {};
  @Local accentColor: StrState =
    connectStr(Constants.AS_ACCENT_COLOR, Constants.ACCENT_DEFAULT);
  @Local navBarHeight: NumState =
    connectNum(Constants.AS_NAV_BAR_HEIGHT, 0);

  build() {
    Column() {
      Text(this.title)
        .fontSize(Constants.TOKEN_FONT_17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_S })

      if (this.notice !== '') {
        Text(this.notice)
          .fontSize(Constants.TOKEN_FONT_BODY_S)
          .fontColor(this.accentColor.value)
          .width('100%')
          .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, bottom: Constants.TOKEN_SPACE_S })
      }

      Scroll() {
        Column() {
          ForEach(this.optionLabels, (label: string, index: number) => {
            Row() {
              Text(label)
                .fontSize(Constants.TOKEN_FONT_BODY_L)
                .fontColor(this.selectedLabel === label
                  ? this.accentColor.value : $r('app.color.text_primary'))
                .layoutWeight(1)
              if (this.selectedLabel === label) {
                Text('✓')
                  .fontSize(Constants.TOKEN_FONT_BODY_L)
                  .fontColor(this.accentColor.value)
              }
            }
            .width('100%')
            .padding({ left: Constants.TOKEN_SPACE_L, right: Constants.TOKEN_SPACE_L, top: Constants.TOKEN_SPACE_13, bottom: Constants.TOKEN_SPACE_13 })
            .onClick(() => {
              this.onSelect(index);
            })
          }, (label: string) => label)
        }
        .width('100%')
      }
      .width('100%')
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .backgroundColor($r('app.color.sheet_background'))
    .padding({ bottom: this.navBarHeight.value + Constants.TOKEN_SPACE_S })
  }
}
