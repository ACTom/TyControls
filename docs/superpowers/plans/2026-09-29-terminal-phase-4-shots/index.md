# 终端 4 期验收截图

`tools/terminal-shots` 离屏画出来的（不开窗口，控件自己的 RenderTo），Windows、默认字体、96 PPI。鼠标动作经控件自己的 MouseDown / MouseMove / MouseUp。重新生成：编 `tools/terminal-shots/terminalshots.lpi`，跑 `terminalshots --phase4`。

| 文件 | 主题 | 明暗 | 看什么 |
|---|---|---|---|
| `selection-default-light.png` | default | light | 失焦的选区：从第一行中间拖到第二行；选中格的底色换成选区色（在主题底色上混成不透明），字色不变 |
| `selection-focused-default-light.png` | default | light | 聚焦的选区：同一段，换成聚焦那一色 |
| `column-default-light.png` | default | light | 聚焦的列选区（Alt+拖）：三行都是第 3–14 列；宽字符按它的第一列算——第二、三行的「文」「三」第一列在 2、起点落在它们后半，整字不选；第一行的「试」（13–14 列）整字选中 |
| `link-hover-default-light.png` | default | light | 按着 Ctrl 悬停网址：只有网址那一段有链接色的下划线 |
| `selection-default-dark.png` | default | dark | 失焦的选区：从第一行中间拖到第二行；选中格的底色换成选区色（在主题底色上混成不透明），字色不变 |
| `selection-focused-default-dark.png` | default | dark | 聚焦的选区：同一段，换成聚焦那一色 |
| `column-default-dark.png` | default | dark | 聚焦的列选区（Alt+拖）：三行都是第 3–14 列；宽字符按它的第一列算——第二、三行的「文」「三」第一列在 2、起点落在它们后半，整字不选；第一行的「试」（13–14 列）整字选中 |
| `link-hover-default-dark.png` | default | dark | 按着 Ctrl 悬停网址：只有网址那一段有链接色的下划线 |
| `selection-xp-light.png` | xp | light | 失焦的选区：从第一行中间拖到第二行；选中格的底色换成选区色（在主题底色上混成不透明），字色不变 |
| `selection-focused-xp-light.png` | xp | light | 聚焦的选区：同一段，换成聚焦那一色 |
| `column-xp-light.png` | xp | light | 聚焦的列选区（Alt+拖）：三行都是第 3–14 列；宽字符按它的第一列算——第二、三行的「文」「三」第一列在 2、起点落在它们后半，整字不选；第一行的「试」（13–14 列）整字选中 |
| `link-hover-xp-light.png` | xp | light | 按着 Ctrl 悬停网址：只有网址那一段有链接色的下划线 |
| `selection-macos-light.png` | macos | light | 失焦的选区：从第一行中间拖到第二行；选中格的底色换成选区色（在主题底色上混成不透明），字色不变 |
| `selection-focused-macos-light.png` | macos | light | 聚焦的选区：同一段，换成聚焦那一色 |
| `column-macos-light.png` | macos | light | 聚焦的列选区（Alt+拖）：三行都是第 3–14 列；宽字符按它的第一列算——第二、三行的「文」「三」第一列在 2、起点落在它们后半，整字不选；第一行的「试」（13–14 列）整字选中 |
| `link-hover-macos-light.png` | macos | light | 按着 Ctrl 悬停网址：只有网址那一段有链接色的下划线 |
