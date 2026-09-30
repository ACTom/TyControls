# 终端 7 期验收截图

`tools/terminal-shots` 离屏画出来的（不开窗口，控件自己的 RenderTo），Windows、默认字体、96 PPI。传输走真的 Core 和示例的 ZModem（`uzmodemterm`），喂的是 lrzsz 自己的录制 `tests/fixtures/terminal-zmodem/big-block.sz.bin`（`sz -8`，20000 字节），时钟注入（每 500 字节 40 ms），所以数字每次一样。重新生成：编 `tools/terminal-shots/terminalshots.lpi`，跑 `terminalshots --phase7`。

| 文件 | 主题 | 明暗 | 看什么 |
|---|---|---|---|
| `zmodem-progress-light.png` | default | light | 传输到一半：`sz` 打的 `rz` 被进度行原地盖掉，一行：箭头、文件名、已收 / 总大小、百分比、速度 |
| `zmodem-progress-dark.png` | default | dark | 传输到一半：`sz` 打的 `rz` 被进度行原地盖掉，一行：箭头、文件名、已收 / 总大小、百分比、速度 |
| `zmodem-done-light.png` | default | light | 传完：进度行换成摘要（文件数、大小、用时、平均速度），下一行是交还之后程序接着输出的提示符 `$ ` |
| `zmodem-done-dark.png` | default | dark | 传完：进度行换成摘要（文件数、大小、用时、平均速度），下一行是交还之后程序接着输出的提示符 `$ ` |
| `zmodem-conpty-refused.png` | default | light | ConPTY 后面：终端里一行说明 ConPTY 会改坏二进制数据、请改用管道模式，`sz` 收到中止序列 |
| `claimed-selection.png` | default | light | 程序开着鼠标（1000）时接管：拖动出的是本地选区（程序拿不到这次拖动），传输照常 |
