# TyControls v1.3 设计文档 — 内置默认皮肤(零配置可见性)

- **日期:** 2026-06-13
- **状态:** 自主推进(用户授权"按你想法来"),由用户现场报告的两个缺陷驱动。
- **前置:** v1+v1.1+v1.2 已在 main(16 控件、289 测试)。

## 0. 问题(用户报告)

1. **控件未绑定 Controller 就完全不显示。** 期望:这不应该发生。
2. **设计期(Lazarus 窗体设计器)中控件也完全不显示。**

**根因(同一个):** 未加载任何主题时,`TTyStyleModel.ResolveStyle` 返回 `EmptyStyleSet`
(`Present=[]`、所有颜色透明)。`TTyCustomControl.DrawFrame` 的每个分支都以
`tpXxx in AStyle.Present` 为前提,于是**什么都不画**——背景、边框、文字全无。

- 缺陷 1:无显式 Controller 的控件回退到 `TyDefaultController`,其 model 在 app 未调用
  `LoadTheme` 时为空 ⇒ 全透明。
- 缺陷 2:设计器从不执行运行期的 `LoadTheme` 代码 ⇒ model 为空 ⇒ 所有拖放控件空白。

> 补充:`examples/demo` 用纯代码建 UI(无 .lfm),其设计器窗体本就为空,这是预期的;
> 但"往任意窗体拖一个 TTyButton 即空白"这一真实缺陷与上面同源。

**产品判断:** 一套**卖给其他开发者**的皮肤控件库必须**零配置即有合理外观**。修复 =
在引擎内置一套默认皮肤,作为始终存在的基础层。

## 1. 方案:按 typeKey 的内置默认皮肤回退(Option C)

内置默认皮肤**仅对"已加载主题未定义该 typeKey"的控件生效**;主题一旦为某 typeKey
写了任意规则,该 typeKey 的内置层被整体抑制(避免任何属性渗漏)。

| 场景 | 行为 |
|---|---|
| 未加载任何主题 | 全部控件走内置默认皮肤(修复缺陷 1、2) |
| 加载完整主题(light/dark/showcase 定义了全部 typeKey) | 内置层对每个 typeKey 都被抑制 ⇒ **渲染零变化** |
| 加载部分主题(只改了 --accent / 只定义了 TyButton) | 未提及的 typeKey 仍走内置默认皮肤 ⇒ 不会出现"重新换肤后大片控件消失" |

为什么是"按 typeKey 整体抑制"而非"逐属性兜底":避免内置层给某主题没写的属性
"渗漏"出一个意外值;主题对某控件的呈现保持完全自主。三个随附主题对每个控件都写满了
核心属性,因此内置层对它们**完全不生效**,渲染与现状逐像素一致。

### 内置皮肤内容

内置默认皮肤是 `themes/light.tycss` 的**内嵌副本**(浅色、蓝色强调),覆盖全部
16 控件 typeKey + 子部件(TyListItem/TyProgressFill/TyTrackThumb/TyTab)+
TyTitleBar/TyCaptionButton。必须**编译进二进制**(不从磁盘读),以便在设计器/任意
部署环境零依赖工作。与 light.tycss 保持同步(加注释 + 测试断言覆盖一致)。

## 2. 实现

### A. 新单元 `source/tyControls.DefaultTheme.pas`
```pascal
function TyBuiltinThemeCss: string;   // 返回内嵌的浅色默认 .tycss 文本
```
内容 = light.tycss 全文(去掉 var/函数无所谓,引擎在 load 时即解析求值)。

### B. `source/tyControls.StyleModel.pas` — 基础层
- 新增私有 `FBaseRules: TFPList` + `FBaseVars: TStringList`,在 `Create` 中一次性由
  `TyBuiltinThemeCss` 解析填充(独立于用户层)。
- 重构:把"按一组 (rules, vars) 解析"的逻辑抽成私有
  `ResolveLayer(ARules: TFPList; AVars: TStrings; ...): TTyStyleSet`,
  `FindStyleIn(ARules; ...)`,`AddEntryTo(ARules; ...)`。现有 `ResolveStyle` 主体
  改为对某层调用。
- 新增私有 `UserHasTypeKey(const ATypeKey): Boolean`(`FRules` 中是否存在
  `SameText(TypeName, ATypeKey)` 的条目)。
- `ResolveStyle` 改为两层:
  ```
  Result := EmptyStyleSet;
  if not UserHasTypeKey(ATypeKey) then
    Result := ResolveLayer(FBaseRules, FBaseVars, ATypeKey, AStyleClass, AStates);
  TyMergeStyleSet(Result, ResolveLayer(FRules, FVars, ATypeKey, AStyleClass, AStates));
  ```
- `LoadFromCss`/`Clear` 只清空**用户层**(`FRules`+`FVars`);`FBaseRules`/`FBaseVars`
  恒存(它们只在 Create 时建一次,Destroy 时释放)。
- `Destroy` 释放两组列表。

> 性能:每个 `TTyStyleModel.Create` 解析一次内嵌 CSS(~60 行,微秒级)。一个 app 通常
> 1 个 controller,测试里约 50 个 model,可忽略。

### C. 设计期
内置皮肤即修复:设计器调用 `Paint → RenderTo → ResolveStyle`,现在返回内置默认 ⇒
`DrawFrame` 有内容可画。控件 Paint 路径无 `csDesigning` 早退(唯一的 `csDesigning`
在 `TTyFormChrome`,只挡窗口操作)。**无法在无头环境跑 IDE 设计器**,因此用
"无主题渲染出非空像素"的端到端测试作为设计期等价证明(设计器与该路径一致)。

## 3. 测试(新增,务必钉死 PPI=96)

新建 `tests/test.defaulttheme.pas`:
1. **内置 CSS 可解析且覆盖完整**:`model.LoadFromCss(TyBuiltinThemeCss)`(临时载入普通
   model 的用户层即可验证内容),对每个 typeKey 解析,断言关键属性 present
   (TyButton/TyEdit/.../TyTabControl 有 Background+TextColor 或 Background;子部件有
   Background;TyGroupBox 有 BorderColor)。
2. **空 model 走内置兜底**:`TTyStyleModel.Create` 后**不 load**,`ResolveStyle('TyButton','',[])`
   断言 `tpBackground in Present` 且 `tpTextColor in Present`,颜色为浅色 surface。
3. **按 typeKey 抑制 + 无渗漏**:`LoadFromCss('TyButton { background:#FF0000; }')` 后:
   - `ResolveStyle('TyButton','',[])` ⇒ background 红 `$FF0000`(用户),且
     **`tpBorderWidth`/`tpPadding` NOT present**(内置 TyButton 被整体抑制,不渗漏)。
   - `ResolveStyle('TyLabel','',[])` ⇒ 仍有内置兜底(`tpTextColor in Present`)。
4. **完整主题零渗漏**:`LoadFromFile(light.tycss)` 后 `ResolveStyle('TyButton','',[])`
   的 Present 集合与"内置被抑制、纯 light"一致(断言 border-width=1、padding 等来自
   light,而非内置——因二者相同,改为断言不会因内置层多出 light 未写的属性;light 写满
   核心属性,直接断言关键值即可)。
5. **端到端可见性(核心缺陷回归)**:新建 `TTyStyleController`(**不 load 主题**)→
   `TTyButton.Controller := ctl` → `RenderTo` 到位图 → 断言中心像素**非透明/非空白**
   (背景被绘制)。证明"控件 + 无主题 controller ⇒ 不再空白"。注:无 controller 路径
   回退 `TyDefaultController`,model 行为相同。

回归保障:现有 289 测试**零改动通过**(已核查:所有逐像素控件测试都先 LoadTheme 对应
typeKey ⇒ 内置被抑制;`test.Types` 的 `tfkNone` 断言针对 `EmptyStyleSet` 本身非 model;
`test.StyleModel`/`test.controller`/`test.themes` 解析前都先 load 且只做 present 断言)。

## 4. 集成
- `tycontrols.lpk`:Files 列表加入 `source/tyControls.DefaultTheme.pas`。
- `tests/tytests.lpr`:uses 加入 `test.defaulttheme`。
- 文档同步:
  - `docs/getting-started.md`:新增"内置默认皮肤"小节(未加载主题即有浅色默认外观;
    加载主题在其之上覆盖;部分主题只覆盖所写 typeKey)。修订"已知限制 #4 设计期渲染"——
    拖放控件现在在设计器中以内置默认皮肤呈现(仅完整自绘窗框仍为运行期)。
  - `docs/KNOWN_GAPS.md`:同步上述设计期描述。
  - `docs/tycss-reference.md`:补"内置默认皮肤 + 按 typeKey 覆盖"语义说明。
  - `README.md`:卖点补一句"零配置即有默认皮肤"。

## 5. 不做
内置皮肤开关(让控件在未换肤前保持不可见)——YAGNI;主题间 var 继承(内置 var 不注入
用户主题)——保持各主题自带 var;Windows native;词级跳转;页签滚动。

## 6. 验收
289 + 新增测试全绿;构建矩阵(2 包 + 17 示例 + 测试器)全绿;全套件 heaptrc 0 泄漏;
三个随附主题渲染零变化(逐像素控件测试不变即证);终审通过;文档同步。
