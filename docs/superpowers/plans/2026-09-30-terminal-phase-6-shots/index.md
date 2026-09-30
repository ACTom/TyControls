# 终端 6 期验收截图

`tools/terminal-shots` 离屏画出来的（不开窗口，控件自己的 RenderTo），Windows、默认字体、96 PPI。方案取自示例的 `examples/terminal/colorschemes/windows-terminal.json`（Windows Terminal 自带的七套）。重新生成：编 `tools/terminal-shots/terminalshots.lpi`，跑 `terminalshots --phase6`。

| 文件 | 主题 | 明暗 | 看什么 |
|---|---|---|---|
| `scheme-campbell.png` | default | light | `palette.cast`，方案 Campbell：16 色、前景、底色（连内边距）都是这一套的，不跟主题 |
| `scheme-onehalf-dark.png` | default | light | `palette.cast`，方案 One Half Dark：16 色、前景、底色（连内边距）都是这一套的，不跟主题 |
| `scheme-onehalf-light.png` | default | light | `palette.cast`，方案 One Half Light：16 色、前景、底色（连内边距）都是这一套的，不跟主题 |
| `scheme-solarized-dark.png` | default | light | `palette.cast`，方案 Solarized Dark：16 色、前景、底色（连内边距）都是这一套的，不跟主题 |
| `scheme-solarized-light.png` | default | light | `palette.cast`，方案 Solarized Light：16 色、前景、底色（连内边距）都是这一套的，不跟主题 |
| `scheme-tango-dark.png` | default | light | `palette.cast`，方案 Tango Dark：16 色、前景、底色（连内边距）都是这一套的，不跟主题 |
| `scheme-tango-light.png` | default | light | `palette.cast`，方案 Tango Light：16 色、前景、底色（连内边距）都是这一套的，不跟主题 |
| `scheme-pair-tango-light.png` | default | light | 明暗配对（Tango Light / Tango Dark）：浅色主题是 Tango Light，深色主题是 Tango Dark |
| `scheme-pair-tango-dark.png` | default | dark | 明暗配对（Tango Light / Tango Dark）：浅色主题是 Tango Light，深色主题是 Tango Dark |
| `scheme-follow-default-light.png` | default | light | 跟随主题：方案里装着 Campbell 但 `ColorSource = tsrcTheme`，和从没设过方案的控件逐像素比，0 个像素不同 |
| `scheme-follow-default-dark.png` | default | dark | 跟随主题：方案里装着 Campbell 但 `ColorSource = tsrcTheme`，和从没设过方案的控件逐像素比，0 个像素不同 |
| `scheme-osc11-solarized-dark.png` | default | light | Solarized Dark 下程序发 `OSC 11 ;#203040`：底色连内边距换成程序的颜色 |
| `scheme-contrast-1-solarized-light.png` | default | light | Solarized Light，16 色写字、█ 块、当底色，最低对比度 1（不调） |
| `scheme-contrast-45-solarized-light.png` | default | light | 同上，4.5：对方案底色 #FDF6E3 不到 4.5:1 的字压暗；█ 块和当底色的格不变 |
| `scheme-partial-default-light.png` | default | light | 方案只设了前景（#303060）、底色（#FFF4E0）、红（#E00070）：其余 15 色跟主题（浅底那套） |
| `scheme-selection-unfocused-campbell.png` | default | light | Campbell 的选区（#FFFFFF 降到 0.3，在底色 #0C0C0C 上混成 #555555），失焦：没设失焦色，用同一色 |
| `scheme-selection-focused-campbell.png` | default | light | 同上，聚焦 |
