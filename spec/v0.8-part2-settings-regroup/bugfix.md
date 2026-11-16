# v0.8-part2-settings-regroup 轮 bugfix 记录

## 1. 关于弹窗 GitHub 项目地址更正（用户真机自查反馈）

- 现象：关于弹窗 GitHub 项目地址指向 `https://github.com/Link-Z-233/BiliRadio`，实际仓库为 `BiliRadio-HM`
- 修复：`Constants.LINK_PROJECT_GITHUB` 补 `-HM` 后缀；GitCode 地址 `https://gitcode.com/Link-Z-233/BiliRadio` 与用户给定一致，无改动
- 备注：项目地址仅在关于弹窗展示（`SettingsPage.aboutLinkRow`），LogPage 无链接
