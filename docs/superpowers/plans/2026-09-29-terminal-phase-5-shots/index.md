# 终端 5 期验收截图

`tools/terminal-shots` 离屏画出来的（不开窗口，控件自己的 RenderTo），Windows、默认字体、96 PPI，放大的注明。重新生成：编 `tools/terminal-shots/terminalshots.lpi`，跑 `terminalshots --phase5`。

| 文件 | 主题 | 明暗 | 看什么 |
|---|---|---|---|
| `reflow-wide-default-light.png` | default | light | 80 列：第二行（中英混排、表情、彩色、链接）是一整行；第三行 78 个减号加一个宽字符，正好压在第 80 列 |
| `reflow-narrow-default-light.png` | default | light | 改到 47 列：长行按新宽度折回，宽字符不劈开（放不下就整个挪到下一行），颜色、链接跟着字走 |
| `reflow-back-default-light.png` | default | light | 再改回 80 列：和第一张一样（折回的行接回去） |
| `reflow-wide-default-dark.png` | default | dark | 80 列：第二行（中英混排、表情、彩色、链接）是一整行；第三行 78 个减号加一个宽字符，正好压在第 80 列 |
| `reflow-narrow-default-dark.png` | default | dark | 改到 47 列：长行按新宽度折回，宽字符不劈开（放不下就整个挪到下一行），颜色、链接跟着字走 |
| `reflow-back-default-dark.png` | default | dark | 再改回 80 列：和第一张一样（折回的行接回去） |
| `reflow-oldconpty-narrow-default-light.png` | default | light | 同样内容，`WindowsPty = {conpty, 19044}` 下改到 47 列：不重新折行，长行截在网格外（老 ConPTY 自己会重画） |
| `contrast-1-xp-light.png` | xp | light | 16 色写字、█ 块、当底色，最低对比度 1（不调） |
| `contrast-45-xp-light.png` | xp | light | 同上，4.5：对底色不到 4.5:1 的字压暗到 4.5:1（xp 上差得最多的是 3、14、10 号）；█ 块和当底色的格不变 |
| `contrast-1-macos-light.png` | macos | light | 16 色写字、█ 块、当底色，最低对比度 1（不调） |
| `contrast-45-macos-light.png` | macos | light | 同上，4.5：对底色不到 4.5:1 的字压暗到 4.5:1（xp 上差得最多的是 3、14、10 号）；█ 块和当底色的格不变 |
| `contrast-1-breeze-light.png` | breeze | light | 16 色写字、█ 块、当底色，最低对比度 1（不调） |
| `contrast-45-breeze-light.png` | breeze | light | 同上，4.5：对底色不到 4.5:1 的字压暗到 4.5:1（xp 上差得最多的是 3、14、10 号）；█ 块和当底色的格不变 |
| `contrast-1-default-dark.png` | default | dark | 深底，最低对比度 1：纯黑底上的 0 号色、暗淡文字、选区里的字（第三行，失焦选区）、ls 的反显目录 |
| `contrast-45-default-dark.png` | default | dark | 同上，4.5：纯黑底上的 0 号色提亮，绿底上的黑字压暗；暗淡文字（比值减半）和选区里的字（对选区色比）本来就够，不变 |
| `contrast-excluded-default-light.png` | default | light | 4.5 下框线、块元素、Powerline 用的浅灰不变；右边同色的文字被压暗 |
| `glyphs-powerline-light.png` | default | light | Powerline（控件自己画，Consolas 里没有这些字形）：箭头、半圆和相邻格的底色严丝合缝；分支、行号、锁；E0B8–E0D4 |
| `glyphs-braille-light.png` | default | light | 盲文 U+2800–28FF 全部 256 个（每行 64 个），末行是 btop 式的图 |
| `glyphs-powerline-dark.png` | default | dark | Powerline（控件自己画，Consolas 里没有这些字形）：箭头、半圆和相邻格的底色严丝合缝；分支、行号、锁；E0B8–E0D4 |
| `glyphs-braille-dark.png` | default | dark | 盲文 U+2800–28FF 全部 256 个（每行 64 个），末行是 btop 式的图 |
| `glyphs-powerline-light-3x.png` | default | light | 同上，放大 3 倍 |
| `glyphs-braille-light-3x.png` | default | light | 同上，放大 3 倍 |
