# TyControls v1.5 设计文档 — 加固(修复审计确认的缺陷)

- **日期:** 2026-06-13
- **状态:** 自主推进。由一次全库 5 维并行 bug 审计驱动,修复全部**运行时已复现**的真实缺陷。
- **前置:** main(@573a6f6,v1–v1.4,305 测试)。

## 范围:修复 9 个已确认缺陷 + 回归测试

### #1 [Critical] TTyFormChrome 缺析构 → 悬空事件处理器
`InstallChrome` 把 `FForm.OnMouseDown/OnMouseMove/OnMouseUp/OnChangeBounds := @自身方法`,只有 `SetActive(False)→UninstallChrome` 会撤销。无析构 ⇒ Active 时被 Free 后宿主窗体仍持有指向已释放 chrome 的方法指针,下次鼠标/resize → EAccessViolation(已复现 exit 217)。
**修:** 加 `destructor Destroy; override;`,`if FForm <> nil then UninstallChrome;`(`Create(nil)`/未安装时为 no-op)。

### #2 [High] LoadFromCss 解析出错破坏状态
`LoadInto`(StyleModel.pas)先 `ClearList(ARules); AVars.Clear;` 再 `parser.Parse`;解析抛 `ETyCssError` 时旧规则已毁 ⇒ 模型清空,全控件跌回内置浅色(暗色应用瞬间翻白),异常再外抛。
**修:** 事务化——先解析到**临时** rules/vars,`Parse` 成功后再 `ClearList` + 交换进 `FRules`/`FVars`;失败则保留原主题、异常照常外抛(调用方可感知)。

### #3 [High] 控件无 Enabled 守卫
全库仅 `CurrentStates` 读 `Enabled`(用于样式),**无任何输入处理器检查 Enabled**。LCL 不为自绘控件拦鼠标(Cocoa 尤甚),且公开 `Click`/`Toggle` 可被代码直接调用。已复现:`Enabled=False` 时 ToggleSwitch 空格键 Toggle、CheckBox/Radio `Click`、TrackBar 鼠标 DragTo、ListBox 方向键 SelectItem 均改状态。
**修:** 在各**输入入口**(Click 重写、MouseDown/MouseMove(拖动)、KeyDown、UTF8KeyPress、鼠标滚轮)顶部加 `if not Enabled then Exit;`。**不**动属性设置器(`Checked:=`/`Position:=` 等是开发者主动 API,禁用态也应允许)。覆盖:Button.Click、CheckBox.Click、RadioButton.Click、ToggleSwitch 输入路径、TrackBar、ScrollBar、ListBox、ComboBox、TabControl、Edit 的输入路径。

### #4 [High] demo chromeform 硬编码主题路径
`examples/demo/chromeform.pas` 的 `ThemeDir` 写死 `ParamStr(0)/../../themes`;从 `lib/<cpu>-<os>/` 输出跑 → `EFOpenError`,启动即异常(`chromeform.lfm` 流式 `Active=True`,OnCreate 里 LoadTheme)。其余示例都用向上逐级查找。
**修:** 换成 `mainform.pas` 那套向上逐级 `DirectoryExists(Dir+'themes')` 查找;并对 LoadTheme 缺文件加防御(找不到则跳过,不崩)。

### #5 [Medium] 同名规则先到先得(应后者覆盖)
`FindStyleIn`(StyleModel.pas)返回**首个**匹配即 Exit;`LoadInto` 按源序 append ⇒ 前者赢。CSS 级联应**后者赢**(且规则内重复声明已是后者赢,行为不一致)。仅影响用户自写主题。
**修:** `FindStyleIn` 倒序遍历(`for i := Count-1 downto 0`)使最后匹配胜出。

### #6 [Medium] alpha() 百分号参数 → 255
`Css.Values.pas` 把 alpha 第二参经 `ParsePctOrNum` 去掉 `%` 返回裸数,`alpha(c,50%)`→50→`ClampByte(50*255)`→255(全不透明),与意图相反。契约本是 0..1。
**修:** 第二参带 `%` 时按 /100 解释(`50%`→0.5);裸数仍按 0..1。严格超集,不破坏 `alpha(c,0)`/`alpha(c,0.5)`。

### #7 [Low] 3 值 padding 抛异常
`ParsePadding` 只处理 1/2/4 值,3 值落 `else` 抛 `Invalid padding`。CSS 允许 3 值(上 / 左右 / 下)。
**修:** 加 `3:` 分支(top=p0;left=right=p1;bottom=p2)。

### #8 [Low] CheckBox/RadioButton 把绝对 ARect 传 DrawFrame
`CheckBox.pas` 两处 `DrawFrame(P, ARect, FrameS)`;其余控件都用本地 `Rect(0,0,W,H)`。偏移渲染 + 主题带 shadow 时阴影错位/裁切(同 TrackBar 历史 bug)。当前 latent(FrameS 清了 bg/border,只剩 shadow;实时 Paint 用 ClientRect 原点 0)。
**修:** 改用 `Rect(0,0,ARect.Right-ARect.Left,ARect.Bottom-ARect.Top)`(变量已在两行后重算),加偏移原点 + shadow 回归测试。

### #9 [Low] ComboBox 无 SetController 重写
重设 `combo.Controller` 后,已建的 `FPopupList` 仍指旧 controller 直到下次 DropDown 才同步(陈旧样式,无悬空)。
**修:** 重写 `SetController`:`inherited` 后,若 `FPopupList<>nil` 则 `FPopupList.Controller := AValue`。

## 不做
圆角填充右/下边 1px 内缩(与边框自洽、纯外观,改动有回归风险);`border:` 简写/`border-style`(DSL 完整度——进特性路线图 Phase B,非 bug)。

## 验收
305 + 新增回归测试全绿;构建矩阵全绿;heaptrc 0 泄漏;FormChrome Free-while-active 不再崩;终审通过。每个 fix 配回归测试(失败→修→通过)。
