# 主题编辑器验收截图

验收单 `docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md` 「截图」一节引用的图。由 `tools/themebuilder-shots` 生成：在进程里真建工具的主窗口（与 `tests/test.themebuilder.main` 一样，设置写临时目录、提问由测试缝作答、不调 `ShowModal`、不弹消息框），窗口放在屏幕外，用 `PrintWindow`（flags 0，即让窗口自己经 WM_PRINT 把标题栏和全部内容画进位图）只渲染这一个窗口（锁屏、被遮挡都不影响，截不到桌面上的别的东西）。实测 `PW_RENDERFULLCONTENT` 对屏幕外的窗口取的是 DWM 的副本：第一次全空、之后是几秒前的旧画面，所以不用。Windows 10、96 PPI（工具不带 DPI 清单）、英文界面（不加载翻译）、工具默认外观。

AI 的两张图用**假后端**：测试里的脚本模型（`tests/tbaitesthelp.pas` 的 `TScriptedBackend`）给一段固定回答，不连任何服务；唯一出现过的密钥是假密钥 `sk-test-0000`（设置窗口里显示为星号，且从未保存）。真实服务的生成（第 57 项）仍要验收时真机做。

重新生成：`lazbuild -B tools/themebuilder-shots/tbshots.lpi`，再在仓库根跑 `tools\themebuilder-shots\tbshots.exe > tbshots.log 2>&1`（输出重定向到文件）。退出码 0 即全部写出；某张是纯色 / 空白就不写、退出码 1。`--out <目录>` 换输出目录，`--onscreen` 把窗口放到屏幕左上角（屏幕外截不出时用）。

| 文件 | 验收项 | 看什么 | 怎么得到 |
|---|---|---|---|
| `p2-seeds-win32.png` | 30、33 | 主窗口，打开 `themes/builtin/win11.tycss`，侧栏在「种子」页：亮 / 暗两列，`--surface`、`--on-surface` 写「inherited」，圆角两列写「from :root」，色块与右边预览（win11 亮色）一致 | `OpenFile` 打开文件，侧栏 `ActivateWindow(SeedsWin)`；PrintWindow |
| `p2-export-win32.png` | 43、44 | 导出对话框，文档是 `themes/green.tycss`：文件列表里有 `assets/background.jpg`，zip 选项灰掉并写了原因，默认导出成文件夹 | `BuildExportForm` 建好后非模态 `Show`，截完关掉，什么都没导出；PrintWindow |
| `p3-ai-settings-win32.png` | 54 | AI 设置：左边五种预置都加上了，选中 Anthropic（模型 `claude-sonnet-5`、最大输出 32000），密钥框是假密钥（显示为星号）；底下有「会发给这里设置的服务」与密钥怎么存的说明；左下角「Add」是整个一块的菜单按钮，字完整 | `BuildAiSettingsForm` 后 `AddPreset` 五次、`SelectProfile`，密钥填 `sk-test-0000`；非模态 `Show`，不点确定、什么都不保存；PrintWindow |
| `p3-ai-settings-ollama-win32.png` | 54 | 同一窗口选中「Local (Ollama)」：地址是本机，字段下出现 Ollama 上下文长度的提示，三行完整，「Test connection」排在它下面、不重叠 | 同上一张，`SelectProfile` 换到本机预置；PrintWindow |
| `p3-ai-page-win32.png` | 57 | 主窗口，极简模板，侧栏在「AI」页：描述「Warm colours, and a bit more rounding.」，输出框里是模型的回答（**假后端**：测试用的脚本模型分 12 段流出一段固定回答，不连任何服务），状态行下面是「This conversation: 1 request.」（单数） | 服务是指向 127.0.0.1 的自定义预置，会话的后端换成 `tests/tbaitesthelp` 的 `TScriptedBackend`，`GenerateClick`；PrintWindow |
| `p3-compare-win32.png` | 57、69 | 对比窗口：左「Now」是编辑器的极简模板，右是 AI 的版本（暖色、圆角 10px），改动行左红右绿、两边对齐，顶上一句「4 changes. Problems left: 0.」（**假后端**的回答）。改动行上的字用编辑器正文的颜色，红、绿底上都清楚；左下「Try it in the preview」完整不截断 | 生成结束后主窗口经 `ShowModalForTest` 交来的对比窗口，非模态 `Show` 截图后按「放弃」的结果关掉；PrintWindow |
| `p1-edit-menu-win32.png` | 77–82（验收反馈） | 主窗口（win11 主题），「编辑」菜单展开：撤销 / 重做、剪切 / 复制 / 粘贴 / 删除 / 全选、格式化文档 / 格式化选中部分、查找… / 查找下一个 / 查找上一个 / 替换…，右边是快捷键；编辑区顶上是替换模式的查找条，选中的是第二处 `--accent`。另看：标题栏左边的应用图标、编辑区的字是平滑的（ClearType）、窗口 1480 宽 | `OpenFile` 打开 win11，`FindBar.Open(True)` 填好查找 / 替换、`FindNext` 两次；`MainMenuBar.OpenTopForTest(1)` 打开「编辑」；PrintWindow（窗口与下拉菜单各画一次再叠起来） |
