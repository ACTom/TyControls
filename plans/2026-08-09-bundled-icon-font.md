# 自带图标字体 + 设计期图标选择器 —— 方案

> 状态:**方案待批准**,尚未动工。前置判断已经做完,两条都是实测/查源得出的,不是回忆。

## 一、选哪套字体:**Lucide(ISC)**,备选 Tabler(MIT)

十二套逐个核对过它们**自己仓库里的 LICENSE**,不是凭印象。两条结论会被凭记忆做的人搞错:

- **Remix Icon 已经不是 Apache-2.0 了**。2026 年 1 月起是自订的 "Remix Icon License v1.0",没有 SPDX
  标识,而且有真实的使用限制(§3.1 禁止把图标打包成独立图标库/图标字体出售,§3.2 禁止用它做竞品图标库,
  §9 明说与要求无限制再分发的许可不兼容)。**直接出局。**
- **"100–400KB" 这个体量假设不成立**。除了已经冻结的 MaterialIcons-Regular.ttf,现在还有真 TTF 的集合
  没有这么小。Lucide 的 `lucide.ttf` 是 **853KB**。这让"可选单元、不 uses 就被智能链接扔掉"从锦上添花
  变成**硬需求**。

选 Lucide 的理由,按你关心的顺序:

| 判据 | Lucide |
|---|---|
| 许可 | **ISC**,比 MIT 还简单,无专利条款、无 NOTICE 机制。义务只有"随分发附版权与许可声明",一个 `THIRD-PARTY-NOTICES` 文件就够。**对下游用户零可见义务**:不用署名、不用挂链接、运行时不用显示任何东西 |
| 有没有现成字体 | **有,而且是一等公民**:根 `package.json` 有 `build:font`,有独立的 `tools/build-font` 包和测试,有 CI 发布。产物在 `lucide-static@1.30.0/font/lucide.ttf` |
| 码点稳定性 | **构建期保证**:`allocateCodepoints.ts` 会拉上一版的 `codepoints.json` 并复用全部既有码点,只给新图标分配。**升级字体不会把常量表整体重排** |
| 元数据 | 最好的一档,而且全是 JSON:每图标 `icons/<name>.json`(tags / categories / aliases)+ 48 个分类文件 + 扁平的 `codepoints.json`。**不用写解析器** |
| 风格中立 | Feather 的维护派生,24px 等宽描边,没有厂商性格;v1.0 还把品牌 logo 全删了,顺带清掉商标风险 |
| 图标数 | ~1641,中等。放最后权衡 |

需要附两份声明(Lucide 的 ISC + Feather 派生部分的 MIT)。

**备选 Tabler(MIT,6150 个)**:视觉最接近,码点是源文件里手写的(比机器分配更稳)。输在两点——
outline 的 ttf 是 **2.83MB**,以及 tags/分类只存在于 6150 个 SVG 文件的 HTML 注释里,得自己写注释解析器。
**如果覆盖面比包体积更重要就换它。**

Phosphor(MIT)字体最小(489KB)、目录最整齐,但风格有自己的个性,按"中立"这条判据落后。

## 二、能不能从内存加载:**四中之四能,GTK2 不能**

| widgetset | 内存 API | 结论 |
|---|---|---|
| Windows | `AddFontMemResourceEx` / `RemoveFontMemResourceEx` | **本机实测通过** |
| Qt5 / Qt6 | `QFontDatabase_addApplicationFontFromData` + `QByteArray_Create(ptr,size)` | 绑定确认存在(qt56.pas:7991 / qt62.pas:8323,C++ 侧也真的导出),运行时未验 |
| Cocoa | `CGDataProviderCreateWithData` → `CGFontCreateWithDataProvider` → `CTFontManagerRegisterGraphicsFont` | 声明确认,运行时未验 |
| GTK2 | **没有**。fontconfig 2.18.2 的三个 app-font 函数全是路径式 | 必须落临时文件 |

Windows 那条是跑出来的:用一个本机没装的字族(FreeMono)做探针,`AddFontMemResourceEx` 返回非零句柄,
之后 GDI **按名字**解析得到该字族(`GetFontData` 报出的字体文件大小恰好等于 .ttf 的 343284 字节),
而且 GDI **拷贝**了字节 —— 释放缓冲区后仍能解析。

**真正会改变设计的一条发现**(API 文档里看不出来):**内存注册的字体不可枚举**。同一个字体、同一个进程:
`AddFontResourceExW(FR_PRIVATE)`(现在用的文件路径)让枚举面数 1445 → 1453、"FreeMono" 命中 8 次;
`AddFontMemResourceEx` 枚举数不变、命中 0 次 —— 但两种方式按名字渲染都正常。

LCL 的 `Screen.Fonts` 就是这个枚举建的,本仓库有 4 处读它(`FontComboBox.pas:84`、`FontListBox.pas:39`、
`Dialogs.Font.pas:365/402`、`designtime/tyControls.Design.pas:587`)。对**图标字体**来说不出现在文字字体
选择器里其实是对的,但这必须是**有意决定**,而且意味着:**"字体到底加载上没有"不能靠枚举判断**,
`TTyIconFont` 需要自己的 `Available` 属性。

GTK2 那条临时文件不是随手写写:文件名必须带 PID(否则第二个实例会截断并重写第一个实例已交给 fontconfig
的那个文件)、**不能**在 `UnloadFontFile` 时删(fontconfig 没有按文件反注册,FreeType 还会按路径惰性重开)、
只能在 unit finalization 删、**并且必须**在启动时扫一遍按 PID 清理崩溃残留 —— 否则每次崩溃永久漏一份。

## 三、切三刀,每刀单独可落地

评审的结论是原方案"没有可落地的第一步",重新切成:

**Slice 0 —— 能力接缝(只动 `source/`,约 200 行,不带字体、不带对话框、不带生成器,全部可无头测试)**

给 `TTyIconFont` 补:`Available` / `LoadError`;名字→码点的哈希索引;一个 `OnChange`/版本计数,让
`TTyCharImage`、`TTyGlyphImageList`、`TTyRibbonGallery` 能跟着刷新;可插拔的名字解析器注册表;
字族解析探针;以及每条加载路径上调 `TyInvalidateTextMeasureCache`。顺带把
`TTyFontFamilyPropertyEditor.GetValues` 扩成把"已注册但不可枚举"的字族插到前面。

**这一刀本身就是净收益**:它修的是**今天树里就有**的静默失败 —— icons 示例自己那条"加载 .ttf"的流程,
除了一个状态标签之外没有任何反馈。而且它同时解锁后两刀。

**Slice 1 —— 字体包,先不做选择器**

生成器 + `assets/lucide/` + 常量单元 + 字体单元 + `THIRD-PARTY-NOTICES.md` + 两份 README + 漂移守卫。
交付的正是那个头号缺口("一个字体、一个码点常量都没自带"),用户一行代码可用:

```pascal
CharImage1.IconFont  := TyLucideFont;
CharImage1.GlyphName := 'house';
```

不碰任何 `.lfm`、不碰发布脚本过滤器、不碰设计期包、不碰 i18n。每个 widgetset 需要一次真机验证。

**Slice 2 —— 选择器对话框**

到这时目录里已经有真数据可浏览,诊断信息也能区分"字体没加载"和"图标名没映射",剩下的未知量都是
必须有 IDE 才能验的设计期问题。

## 四、评审挑出来、必须先解决的坑

1. **发布脚本会把 `source/` 里的 `.lfm` 丢掉**。`make-release.ps1:67` 只收 `.pas`/`.inc`,`make-release.sh:70`
   同理。选择器对话框若按 `.lfm` 放进 `source/`,从 release 包安装的用户拿到的是带 `{$R *.lfm}` 的 `.pas`
   而没有 `.lfm` —— **运行时包直接编译不过**,不是降级。落第一个包内 `.lfm` 的那次提交必须同时改两个脚本,
   并加一条守卫去 grep 它们。
2. **可选单元的"可丢弃性"是有条件的**。要抄 `gen-builtinthemes` 那条路(数据放 `.pas` 单元),**不能**抄
   `gen-icons` 那条(`.lrs` 是整文件链接,永远丢不掉)。而且树里已经有反例:
   `tyControls.BuiltinThemes.pas:15` uses `BuiltinThemeData`,把 476KB 拖进每个 app。字体单元必须**没有任何
   核心单元 uses 它**,依赖只能单向。
3. **字体在目标机注册失败会渲染成豆腐块**,而且现在是静默的:`IconFont.pas:256` 在 `not FileExists` 时早退,
   但 `FFontFamily` 已经设了,`RenderGlyph` 的守卫过得去,于是画出空框。Slice 0 的 `Available` 就是为这个。

## 五、待你拍板的两件事

1. **Lucide(853KB / 1641 个 / ISC)还是 Tabler(2.83MB / 6150 个 / MIT)**。我的建议是 Lucide。
2. **要不要先只做 Slice 0**(纯改进、无风险、可无头测试),把字体和选择器排到后面?我的建议是要。
