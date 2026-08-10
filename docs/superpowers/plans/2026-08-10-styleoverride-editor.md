# StyleOverride 编辑器 + tycss 词汇 catalog + Controller 全局 override — 实施计划

> **STATUS(2026-08-10):全部三个 Phase 已实现 + 提交 + headless 全绿(6249/0)。** 下方逐步
> checkbox 未回头勾,属过期记账,不代表未做。提交:`21e08ed` `53bbd8c` `6005a27`(Phase 1 catalog)、
> `80a44c1`(Lucide 授权,附带)、`94e3981`(Phase 2 编辑器 + Phase 3 控制器 override + SetDensity 丢
> accent 的既有坑)、`5673c2a`(改用 `TSynCssSyn` 上色)。
>
> **和计划的偏差(有意)**:Task 2.1 没手搓 `TTyCssHighlighter`,改用 SynEdit 自带 `TSynCssSyn`(tycss
> 是 CSS 方言,够用、免维护)。Task 1.5 的聚合 re-export 判为 YAGNI 未做(编辑器直接 `uses` 各常量单元)。
> 补全纯逻辑落在**运行期** `tyControls.Css.Complete`(而非设计期),这样可 headless 测。
>
> **真正剩下的(都是验证/收尾,非待写代码)**:①对话框 UI 真机(真 IDE)验;②46 example 全量编译复核
> (改了运行期后应跑一遍);③合 main 前 pre-merge(i18n / README / CHANGELOG 补 StyleOverride)。见文末验收清单。

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans（本仓库惯例：单会话内分阶段执行、每阶段跑全套测试 + 里程碑验证）。步骤用 `- [ ]` 勾选跟踪。

**Goal:** 让用户能在 IDE 里舒服地写 `StyleOverride`（tycss）——带语法高亮、按 catalog 补全、对未知属性给警告；并给 `TTyStyleController` 加一个同名的全局 `StyleOverride`（带选择器的主题补丁，跟随换肤持久生效）。

**Architecture:** 三层，依赖自下而上：
1. **catalog 基建**——把 tycss 词汇（属性 / 取值提示 / 令牌 / typeKey / 颜色函数 / 伪类）做成机器可读、从真相源生成或共享、且有一致性测试守护，永不漂移。
2. **SynEdit 属性编辑器**（只进 `tycontrols_dt`，运行库不碰）——`TStringPropertyEditor` 子类 + `paDialog`，弹一个 SynEdit 对话框：tycss 高亮 + `SynCompletion`（吃 catalog）+ 右侧分类列表 + 未知属性警告。控件级 / 控制器级同名同编辑器。
3. **Controller 全局 `StyleOverride`**——照 `ApplyDensityPack` 的既有套路,把用户的 tycss 补丁作为最后一个 additive 层,在每次换肤后重放。

**Tech Stack:** Free Pascal / Lazarus,BGRABitmap 自绘,tycss(自研 CSS 方言),SynEdit / SynCompletion / SynCustomHighlighter(仅设计期),fpcunit。

**调查已确认的关键事实(写计划的地基):**
- 属性词汇是**闭集但没有 enum/数组**:识别发生在 `source/tyControls.StyleModel.pas` 的 `TyApplyDeclaration`(约 727-879 行)一条 `prop = '字面量'` if/else 链,末尾 `else Result:=False`;而这个返回值**三个调用点全不看**(约 1196/1241/1751),所以**未知属性静默丢弃、无任何报错**。共 23 个属性名 + `background-color` 别名。
- 令牌(`--xxx`)是**开放轴**:176 个定义在 `themes/light.tycss` 的 `:root`,代码里不枚举,按名字懒解析;主题能随便造新 token。→ 补全只**建议**已知的、**不拦**未知的。
- 颜色函数是闭集(`lighten/darken/alpha/mix/rgb/rgba/elevate/on`),`source/tyControls.Css.Values.pas` 的 `TyEvalColor`(约 270-306)dispatch,未知**硬报错**。
- 伪类是闭集(`hover/active/focus/disabled/selected/checked`),`source/tyControls.Css.Parser.pas` 的 `PseudoToState`(约 151-171),未知**硬报错**。
- typeKey(约 183 个)= `light.tycss` 里选择器头。
- per-control `StyleOverride`:`source/tyControls.Base.pas` 上 `TTyGraphicControl`(76/275)和 `TTyCustomControl`(289/444)两个 published string;经 `TTyStyleModel.ResolveOverride`(StyleModel.pas:153,`TyParseOverride` 无选择器 bare decl block)叠在该实例已解析样式之上。设计期只有一个注册:`designtime/tyControls.Design.pas:1493` 把它在 `TTyFormSurface` 上 **藏掉**。
- Controller 已有 `LoadThemeCssAdditive`→`FModel.LoadFromCssAdditive`(**追加** rules 到 `FRules` 用户层 + 合并 vars);`LoadFromCss` 是 **REPLACE**(清 `FRules`),所以换肤会丢 additive 层。既有 `ApplyDensityPack`(Controller.pas:59)就是"换肤后重放 additive 层"的样板。
- 现成机器可读 catalog:**没有**。`docs/tycss-reference.md` 是人读参考、声称逐行对过实现、看着一致但机器读不了。SynEdit 目前**全仓库没用到**。

---

## File Structure

**Phase 1 — catalog 基建**
- Modify `source/tyControls.StyleModel.pas` — interface 加 `const TyKnownStyleProps: array of string`(23 名)与 `TyStylePropValueHints`(属性→建议关键字/函数),放在真相源同一单元。
- Modify `source/tyControls.Css.Values.pas` — interface 加 `const TyKnownColorFns: array of string`(与 `TyEvalColor` dispatch 同源)。
- Modify `source/tyControls.Css.Parser.pas` — interface 加 `const TyKnownPseudoStates: array of string`(与 `PseudoToState` 同源)。
- Create `scripts/gen-tycss-catalog.ps1` — 读 `themes/light.tycss`,抽 `:root` 里的 `--token` 名 + 选择器头 typeKey,生成 Pascal 单元(照 `gen-defaulttheme.ps1` 的逐行 emit 习惯,PS 5.1 用 `[System.IO.File]::ReadAllText` 读 UTF-8)。
- Create `source/tyControls.Css.Catalog.pas`(**生成物**) — `TyCatalogTokens: array of string`、`TyCatalogTypeKeys: array of string`;并 re-export 上面三个手写 const 的聚合访问器(方便编辑器一处拿全)。
- Create `tests/test.css.catalog.pas` — 一致性测试:(a) `TyKnownStyleProps` 每个名喂给 `TyApplyDeclaration` 都被识别、一个已知坏名被丢;(b) `TyKnownColorFns` 每个在 `TyEvalColor` 下不报"未知函数"、坏名报错;(c) `TyKnownPseudoStates` 每个 `PseudoToState` 认、坏名报错;(d) 生成物 byte-sync:重跑 `gen-tycss-catalog.ps1` 后 `git diff --quiet`(照 `test.defaulttheme`/`test.builtinthemes` 套路)。
- Modify `tests/tytests.lpr` — 注册 `test.css.catalog`。

**Phase 2 — SynEdit 编辑器(设计期)**
- Create `designtime/tyControls.Design.Css.Highlighter.pas` — `TTyCssHighlighter = class(TSynCustomHighlighter)`:高亮注释 / 选择器(Type.variant:state)/ `--token` / 属性名 / `var()`/颜色函数 / 字符串 / 大括号。
- Create `designtime/tyControls.Design.Css.Editor.pas` — `TTyStyleOverrideDialog`(一个 form:左 SynEdit + 右分类列表 + 底部警告条)+ `TTyStyleOverrideProperty = class(TStringPropertyEditor)`(`GetAttributes` 含 `paDialog`;`Edit` 弹对话框)。含"选择器模式"开关(控制器级 true,控件级 false)。
- Modify `designtime/tyControls.Design.pas` — `RegisterPropertyEditor` 把 `TTyStyleOverrideProperty` 绑到 `StyleOverride`(控件基类 + 控制器);去掉/保留 `TTyFormSurface` 上的隐藏(见 Task 2.5 说明)。
- Modify `tycontrols_dt.lpk` — 依赖加 `SynEdit`(Lazarus 自带包)。
- Create `tests/test.css.highlighter.pas` — 对若干 tycss 片段断言 token 分类(highlighter 是纯逻辑,可 headless 测)。

**Phase 3 — Controller 全局 StyleOverride**
- Modify `source/tyControls.Controller.pas` — 加 `FStyleOverride: string` + published `StyleOverride`(published,`stored` 常规)+ `SetStyleOverride` + `ApplyStyleOverride`(照 `ApplyDensityPack`);在每个"换肤后重放层"的位置(`ApplyDensityPack` 调用点之后)追加 `ApplyStyleOverride`。
- Modify `tests/test.controller.pas`(或新 `tests/test.controller.styleoverride.pas`)— 测:设了全局 override → 目标 typeKey 的 resolve 里能读到补丁值;换肤(REPLACE)后补丁仍在;清空 override 后恢复;override 在 density 之后(赢过 density)。
- Modify `tests/tytests.lpr` — 注册新测试单元(若新建)。

---

## Phase 1 — tycss 词汇 catalog(基建,先落这一步)

### Task 1.1: 属性真相源常量 + 一致性测试

**Files:**
- Modify: `source/tyControls.StyleModel.pas`(interface const 区)
- Test: `tests/test.css.catalog.pas`

- [ ] **Step 1: 先写失败测试** —— 断言 `TyKnownStyleProps` 里每个名都被 `TyApplyDeclaration` 识别,且一个乱名被丢弃。

```pascal
procedure TCssCatalogTest.EveryKnownPropIsRecognisedAndUnknownIsDropped;
var
  ss: TTyStyleSet;
  i: Integer;
  vars: TStringList;
begin
  vars := TStringList.Create;
  try
    for i := 0 to High(TyKnownStyleProps) do
    begin
      ss := EmptyStyleSet;
      AssertTrue(TyKnownStyleProps[i] + ' 应被识别',
        TyApplyDeclaration(ss, TyKnownStyleProps[i], SafeValueFor(TyKnownStyleProps[i]), vars));
    end;
    ss := EmptyStyleSet;
    AssertFalse('乱名应被丢弃(返回 False)',
      TyApplyDeclaration(ss, 'zznot-a-prop', 'x', vars));
  finally
    vars.Free;
  end;
end;
```

其中 `SafeValueFor` 给每个属性一个能过 `TyApplyDeclaration` 的合法值(如 `color`→`#fff`、`padding`→`4px`、`border-style`→`solid`……)。注意 `TyApplyDeclaration` 对某些属性会 raise（坏值），本测试要给合法值,只验"识别与否",不验取值解析。

- [ ] **Step 2: 跑,确认失败**(`TyKnownStyleProps` 尚不存在 → 编译失败)。
Run: `/c/lazarus/lazbuild.exe --quiet tests/tytests.lpi`
Expected: 编译错误 `Identifier not found "TyKnownStyleProps"`。

- [ ] **Step 3: 在 StyleModel interface 加常量。** 名字逐条对照 `TyApplyDeclaration` 那条 if 链(727-879),一个不漏一个不多。

```pascal
const
  { tycss 认得的声明属性名 —— 真相源是 TyApplyDeclaration 的 if 链,这里是它的可枚举镜像。
    改这条链时必须同步这里;test.css.catalog 会 cross-check,漂移即红。 }
  TyKnownStyleProps: array[0..22] of string = (
    'background', 'background-image', 'background-size', 'background-blur',
    'glass-blur', 'glass-tint', 'background-under-titlebar', 'window-shadow', 'shadow',
    'color', 'border', 'border-color', 'border-width', 'border-radius', 'border-style',
    'render-style', 'padding', 'font-family', 'font-size', 'font-weight',
    'outline', 'outline-offset', 'opacity');
  { 'background-color' 是 'background' 的别名(TyApplyDeclaration 同一分支),编辑器把它并入建议。 }
```

- [ ] **Step 4: 跑测试,确认通过。**
Run: `/c/lazarus/lazbuild.exe --quiet tests/tytests.lpi && ./tests/tytests.exe --suite=TCssCatalogTest -a`
Expected: PASS。若某属性因合法值仍返回 False,说明我漏读了链上的分支——回去核对 `TyApplyDeclaration`。

- [ ] **Step 5: 提交。**

```bash
git add source/tyControls.StyleModel.pas tests/test.css.catalog.pas tests/tytests.lpr
git commit -m "feat(css): TyKnownStyleProps -- an enumerable mirror of the resolver's property set, pinned by a consistency test"
```

### Task 1.2: 属性取值建议(闭集关键字 / 函数)

**Files:**
- Modify: `source/tyControls.StyleModel.pas`
- Test: `tests/test.css.catalog.pas`

- [ ] **Step 1: 失败测试** —— 断言有闭集取值的属性,其建议关键字确实被 `TyApplyDeclaration` 接受。

```pascal
procedure TCssCatalogTest.ValueHintsAreAcceptedByTheResolver;
var ss: TTyStyleSet; vars: TStringList; kw: string;
begin
  vars := TStringList.Create;
  try
    for kw in HintsFor('border-style') do          // none/solid/outset/inset
    begin
      ss := EmptyStyleSet;
      AssertTrue('border-style: ' + kw + ' 应被接受',
        TyApplyDeclaration(ss, 'border-style', kw, vars));
    end;
    for kw in HintsFor('background-size') do        // stretch/center/cover
    begin
      ss := EmptyStyleSet;
      AssertTrue('background-size: ' + kw,
        TyApplyDeclaration(ss, 'background-size', kw, vars));
    end;
  finally vars.Free; end;
end;
```

`HintsFor(prop)` 从 `TyStylePropValueHints` 取该属性的建议数组。

- [ ] **Step 2: 跑,确认失败**(`TyStylePropValueHints`/`HintsFor` 未定义)。

- [ ] **Step 3: 加取值建议常量。** 只覆盖**闭集**取值(照 StyleModel 的关键字处理:`border-style`=none/solid/outset/inset;`background-size`=stretch/center/cover;`render-style`=bevel3d/inset3d/flat;`font-weight`=bold/normal;布尔属性=true/false;颜色属性建议颜色函数名 + `transparent`)。开放取值(px 数、url()、任意颜色)不进建议,让用户自由写。

```pascal
type
  TTyStylePropHint = record Prop: string; Hints: array of string; end;
const
  TyStylePropValueHints: array[0..6] of TTyStylePropHint = (
    (Prop: 'border-style';   Hints: ('none','solid','outset','inset')),
    (Prop: 'background-size'; Hints: ('stretch','center','cover')),
    (Prop: 'render-style';    Hints: ('bevel3d','inset3d','flat')),
    (Prop: 'font-weight';     Hints: ('bold','normal')),
    (Prop: 'window-shadow';   Hints: ('true','false')),
    (Prop: 'background-under-titlebar'; Hints: ('true','false')),
    (Prop: 'color';           Hints: ('transparent','var(','lighten(','darken(','alpha(','mix('))
  );
```

（`array of string` 在 record const 里的具体写法按 FPC 语法核对;若 `record` 里开放数组常量不便,退化为两个平行数组 `PropNames` / `PropHintBlocks` 或一个 `function HintsFor(const AProp: string): TStringArray`。执行时以能编译为准。)

- [ ] **Step 4: 跑测试通过。** — Step 5: 提交(`feat(css): value hints for the closed-keyword style properties`)。

### Task 1.3: 颜色函数 + 伪类 真相源常量

**Files:**
- Modify: `source/tyControls.Css.Values.pas`(`TyKnownColorFns`)、`source/tyControls.Css.Parser.pas`(`TyKnownPseudoStates`)
- Test: `tests/test.css.catalog.pas`

- [ ] **Step 1: 失败测试** —— 每个颜色函数在 `TyEvalColor` 下能被解析(用最简参数),坏函数名 raise;每个伪类 `PseudoToState` 认,坏伪类 raise。

```pascal
procedure TCssCatalogTest.KnownColorFnsResolveAndUnknownRaises;
var vars: TStringList; fn: string; raised: Boolean;
begin
  vars := TStringList.Create;
  try
    vars.Values['accent'] := '#3B82F6';
    for fn in TyKnownColorFns do
      TyEvalColor(SampleCallFor(fn), vars);       // 不 raise 即通过(rgb('...')/alpha(var(--accent),.5) 等)
    raised := False;
    try TyEvalColor('zzfn(#fff)', vars); except raised := True; end;
    AssertTrue('未知颜色函数应 raise', raised);
  finally vars.Free; end;
end;
```

`SampleCallFor(fn)` 给每个函数一个最简合法调用。

- [ ] **Step 2: 跑失败。 Step 3: 加常量。**

```pascal
// Css.Values.pas —— 真相源是 TyEvalColor(约 259-306)的 dispatch
const TyKnownColorFns: array[0..7] of string =
  ('var','lighten','darken','alpha','mix','rgb','rgba','elevate'); // 'on' 见下注

// Css.Parser.pas —— 真相源是 PseudoToState(约 151-171)
const TyKnownPseudoStates: array[0..5] of string =
  ('hover','active','focus','disabled','selected','checked');
```
（执行时按 `TyEvalColor` 实际认的函数名核对:调查报告提到 `on()` 也在,若确认则并入 `TyKnownColorFns` 并给 `SampleCallFor` 补样例。）

- [ ] **Step 4: 跑通过。 Step 5: 提交**(`feat(css): color-fn & pseudo-state name constants, pinned to their dispatchers`)。

### Task 1.4: 生成 token / typeKey catalog + byte-sync 测试

**Files:**
- Create: `scripts/gen-tycss-catalog.ps1`、`source/tyControls.Css.Catalog.pas`(生成物)
- Test: `tests/test.css.catalog.pas`

- [ ] **Step 1: 写生成脚本。** 读 `themes/light.tycss`(用 `[System.IO.File]::ReadAllText`,别用 `Get-Content -Raw`——PS 5.1 会毁 UTF-8);正则抽 `:root { }` 内的 `--([a-z0-9-]+)\s*:` 作 token 名(去重、保序或排序);抽顶层选择器头(逗号分隔的 `TyXxx`,含 `.variant`/`:state` 前的裸 typeKey,去重)。emit 一个 Pascal 单元,数组常量逐行 emit(照 `gen-defaulttheme.ps1` 42-46 的字面量拼接习惯)。

- [ ] **Step 2: 跑脚本生成 `tyControls.Css.Catalog.pas`。**
Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gen-tycss-catalog.ps1`
Expected: 生成 `source/tyControls.Css.Catalog.pas`,含 `TyCatalogTokens`(~176 名)与 `TyCatalogTypeKeys`(~183 名)。

- [ ] **Step 3: byte-sync 测试。** 照 `test.defaulttheme` 的套路:测试里断言(a)`TyCatalogTokens` 非空且包含几个已知 token(`--accent`/`--surface`/`--border`/`--chrome-bar-bg`);(b)每个 `TyCatalogTokens` 名都能在 `light.tycss` 里找到 `--name:`(反查,防生成器乱造);(c)一个"生成物 = 重跑脚本输出"的 byte 对比(把新生成写临时文件、与在库文件比对;或在 CI 步骤跑 `gen` 后 `git diff --quiet source/tyControls.Css.Catalog.pas`)。headless 单元测试用(a)(b);byte 对比放脚本/CI 步骤更稳。

- [ ] **Step 4: 跑测试通过。** — **Step 5: 提交**(`feat(css): generated token/typeKey catalog from light.tycss + drift guard`)。

### Task 1.5: 聚合访问器 + Phase-1 里程碑验证

- [ ] **Step 1:** 在 `tyControls.Css.Catalog.pas`(或一个薄单元)re-export 一个"给编辑器一处拿全"的接口:`TyCatalogProperties`(=`TyKnownStyleProps`)、`TyCatalogValueHints`、`TyCatalogColorFns`、`TyCatalogPseudoStates`、`TyCatalogTokens`、`TyCatalogTypeKeys`。纯转发,不新增真相。
- [ ] **Step 2:** 全量构建 + 全套测试。
Run: `/c/lazarus/lazbuild.exe --quiet tycontrols.lpk && /c/lazarus/lazbuild.exe -B tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`
Expected: 0 failures;`TCssCatalogTest` 全绿。
- [ ] **Step 3: 提交** + 里程碑:此时"属性拼错静默丢"已有守卫(catalog + 一致性测试),且编辑器所需数据全部就绪、且被测试钉死不漂移。

---

## Phase 2 — SynEdit 属性编辑器(设计期)

> 前置:Phase 1 的 catalog。SynEdit 只进 `tycontrols_dt`,运行库零依赖(符合"只给 IDE 用")。
> 执行期须先确认:`tycontrols_dt.lpk` 加 `SynEdit` 依赖后,`designtime` 单独编译通过(记忆:改 designtime 必须单独编 `tycontrols_dt.lpk`)。

### Task 2.1: tycss 语法高亮器
**Files:** Create `designtime/tyControls.Design.Css.Highlighter.pas`;Test `tests/test.css.highlighter.pas`。
- [ ] Step 1(失败测试):对片段 `TyButton:hover { color: var(--accent); /* c */ }` 断言各段 token 种类(选择器 / 伪类 / 属性 / 函数 / token / 注释)。SynCustomHighlighter 可 headless 驱动(`SetLine` + `GetTokenEx`/`GetTokenAttribute` 遍历),不需 GUI。
- [ ] Step 2:跑失败。
- [ ] Step 3:实现 `TTyCssHighlighter = class(TSynCustomHighlighter)`。识别:`/* */` 注释、`{` `}` `:` `;`、`--ident`(token)、`ident(`(函数)、裸 `ident`(属性名 or 选择器,按是否在 `{` 前/内区分)、`.ident`(variant)、`:ident`(state/pseudo)、字符串、`#hex`、数字+`px`。属性名命中 `TyKnownStyleProps` 给"已知属性"色、否则"未知属性(警告)"色——高亮层就顺手把"未知属性"标出来。
- [ ] Step 4:跑通过。 Step 5:提交。

### Task 2.2: 补全数据源(catalog → SynCompletion 词表)
**Files:** Modify `tyControls.Design.Css.Editor.pas`(先建个 helper 单元或就放编辑器单元)。
- [ ] Step 1(失败测试):`BuildCompletionItems(context)` 给"属性位置"返回 `TyKnownStyleProps`,给"值位置且属性=border-style"返回其 hints,给"选择器位置(仅控制器模式)"返回 `TyCatalogTypeKeys`+伪类,给 `--` 前缀返回 `TyCatalogTokens`。纯逻辑,可 headless。
- [ ] Step 2-4:实现一个纯函数 `TyCssCompletionFor(const ALineToCaret: string; ASelectorMode: Boolean): TStringArray`——用极简上下文判断(是否在 `{}` 内、光标前是不是 `--`、是不是在 `:` 之后的值区、是否属性行)。**不做完整解析**,词法级启发即可。 Step 5:提交。

### Task 2.3: 编辑器对话框
**Files:** Create/Modify `tyControls.Design.Css.Editor.pas`。
- [ ] `TTyStyleOverrideDialog`:一个 `TForm`(设计期,可用普通 LCL 控件,因为是 IDE 内 UI,不受"UI 内不用裸 LCL"约束——那条针对运行期自绘控件)。左 `TSynEdit` + 挂 `TTyCssHighlighter` + `TSynCompletion`(`OnExecute` 填 `TyCssCompletionFor`);右 `TListBox`/`TTreeView` 分类展示(属性 / 令牌 / typeKey / 函数),双击插入;底部一条警告标签:扫当前文本里出现但不在 `TyKnownStyleProps` 的属性名,列出来(因为运行时不会报)。`Execute(var AText; ASelectorMode): Boolean`。
- [ ] 无法 headless 测 GUI 布局;至少对"警告扫描"和"双击插入文本"这类纯逻辑抽函数单测。 提交。

### Task 2.4: 属性编辑器注册
**Files:** Create `TTyStyleOverrideProperty`;Modify `designtime/tyControls.Design.pas`。
- [ ] `TTyStyleOverrideProperty = class(TStringPropertyEditor)`:`GetAttributes := [paDialog, paMultiLine, paRevertable]`;`Edit` 读当前值 → `TTyStyleOverrideDialog.Execute` → 写回。选择器模式:靠 `GetComponent(0)` 是不是 `TTyStyleController` 判断(控制器→true)。
- [ ] `RegisterPropertyEditor(TypeInfo(string), TTyGraphicControl, 'StyleOverride', TTyStyleOverrideProperty)` 和对 `TTyCustomControl`、`TTyStyleController`(Phase 3 后)各注册一次。

### Task 2.5: TTyFormSurface 的隐藏怎么办 + 里程碑
- [ ] 现状:`Design.pas:1493` 在 `TTyFormSurface` 上用 `THiddenPropertyEditor` 藏了 `StyleOverride`(因为 Surface 是内部容器)。决定:**保持隐藏 Surface 上的**,但确认 `TTyForm` 本体的 `StyleOverride`(针对 Form 自己,见另一条讨论)走新编辑器、且**不级联子控件**(本仓库已定:级联等 tycss 支持级联再说)。
- [ ] 里程碑:单独编 `tycontrols_dt.lpk` 通过;在真机 IDE 里对一个控件的 `StyleOverride` 点开对话框、验高亮 + 补全 + 警告(这步只能真机验,记入验收清单)。

---

## Phase 3 — Controller 全局 StyleOverride

> 机制:照 `ApplyDensityPack` 的样板——控制器持有补丁源,换肤(REPLACE)会清用户层,故每次换肤后重放。顺序:主题(layer-1)→ density(additive)→ **StyleOverride(additive,最后 → 赢过 density)**。

### Task 3.1: 定位所有"重放层"的调用点
**Files:** 只读 `source/tyControls.Controller.pas`。
- [ ] Step 1:`grep -n "ApplyDensityPack" source/tyControls.Controller.pas` 找出每个调用点(换肤 / SetDensity / ThemeName / ThemeFile / LoadThemeCss 之后)。记下清单——`ApplyStyleOverride` 要跟在每一个 `ApplyDensityPack` 之后。

### Task 3.2: published StyleOverride + 重放
**Files:** Modify `source/tyControls.Controller.pas`;Test `tests/test.controller.styleoverride.pas`。
- [ ] **Step 1(失败测试):**

```pascal
procedure TControllerStyleOverrideTest.OverridePatchesResolvedStyleAndSurvivesReload;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'light';
    c.StyleOverride := 'TyButton { --radius: 12px; }';   // 带选择器的补丁
    AssertEquals('补丁生效', 12, MetricOfTypeKeyToken(c, 'TyButton', '--radius'));
    c.ThemeName := 'dark';                                 // REPLACE 换肤
    AssertEquals('换肤后补丁仍在', 12, MetricOfTypeKeyToken(c, 'TyButton', '--radius'));
    c.StyleOverride := '';                                  // 清空
    AssertTrue('清空后恢复', MetricOfTypeKeyToken(c, 'TyButton', '--radius') <> 12);
  finally c.Free; end;
end;
```

`MetricOfTypeKeyToken` 用 `c.Model` 解析该 typeKey 下的 token 值(执行期按 Model 的 resolve API 写这个 helper)。

- [ ] **Step 2:** 跑失败(`StyleOverride` 不存在于 Controller)。
- [ ] **Step 3:** 加字段/属性/方法:

```pascal
// interface, TTyStyleController
private
  FStyleOverride: string;
  procedure SetStyleOverride(const AValue: string);
  procedure ApplyStyleOverride;   // 照 ApplyDensityPack:若非空,追加补丁作最后一层
published
  property StyleOverride: string read FStyleOverride write SetStyleOverride;

// implementation
procedure TTyStyleController.SetStyleOverride(const AValue: string);
begin
  if FStyleOverride = AValue then Exit;
  FStyleOverride := AValue;
  { 换补丁 = 重建整条层链:additive 只能追加、不能删单层,所以重装当前主题(REPLACE 清用户层)
    再依次重放 density 与新补丁。复用现有换肤路径即可。 }
  ReloadThemeChain;   // 执行期:提取"重装 layer-1 + ApplyDensityPack + ApplyStyleOverride"为一个私有方法,
                      // SetDensity / SetStyleOverride / 换肤 都走它;避免三处各写一遍。
  Changed;
end;

procedure TTyStyleController.ApplyStyleOverride;
begin
  if FStyleOverride <> '' then
    FModel.LoadFromCssAdditive(FStyleOverride);
end;
```

关键重构:把"重装主题→density→override"收敛成一个 `ReloadThemeChain`(或复用现成的换肤入口 + 在其尾部统一追加 `ApplyDensityPack; ApplyStyleOverride;`)。**每个** `ApplyDensityPack` 调用点后补 `ApplyStyleOverride`(Task 3.1 的清单)。

- [ ] **Step 4:** 跑测试通过。
- [ ] **Step 5:** 提交(`feat(controller): global StyleOverride -- a themable patch that survives theme switches`)。

### Task 3.3: 默认控制器 + 编辑器接线 + 里程碑
- [ ] `TyDefaultController` 天然就有这个属性(同类)。补一个测试:`TyDefaultController.StyleOverride := '...'` 代码设置即生效(不弹编辑器——编辑器只在设计期对拖出来的 Controller 弹)。
- [ ] Phase 2 的 `RegisterPropertyEditor` 对 `TTyStyleController` 注册(选择器模式 = true)。
- [ ] 全套测试 + 全 46 example 编译 + 单独编 dt。里程碑:真机 IDE 里拖一个 Controller、写带选择器的补丁、运行时换肤验证补丁跟随。

---

## Phase 3 执行期发现(2026-08-10,写代码前必读)

- **REPLACE 主题加载会清掉 accent 覆盖**(`StyleModel.pas:1496`,`FVarOverrides.Clear`)。所以"每次 `SetStyleOverride` 就重装层链"会**顺手丢掉用户在取色器里选的强调色**。
- **而且 `SetDensity` 现在就有这个 bug**:`SetDensity → ReloadThemeLayer → LoadFromCss/File(REPLACE)→ 清 FVarOverrides`,所以**换密度会丢 accent**。这是个 3.0 前该顺手修的既有坑。
- **additive 层无法单独卸载**(`LoadFromCssAdditive` 只追加到 `FRules`;REPLACE 才清)。所以"改/清 override"必须重装底层再重叠,没法只撤那一层。
- **无主题的默认控制器**:`ReloadThemeLayer` 在 `FThemeFile=''` 且 `FThemeName=''` 时**不重装任何东西**(内置 base 在 `FBaseRules`,不是 `FRules`)。于是第二次设 override 时,第一次的 override 还在 `FRules` 里、新的又追加 → **累积**。需要一个"把 `FRules` 清成干净起点"的动作(如 `LoadFromCss('')`),但它也会清 accent(见上)。

**Phase 3 方案分叉(需拍板):**
- **A 简单**:`SetStyleOverride` 走 `ReloadThemeLayer`(同 `SetDensity`),accent 一并被重置——与 `SetDensity` 现有行为一致(即也继承了那个 bug)。改动最小。
- **B 保 accent**:在 override 重装前后 capture/restore accent(`AccentOverride`/`SetAccent`);顺带把 `SetDensity` 也改成保 accent(修那个既有坑)。中等改动,行为最合直觉。
- **C 独立 override 层**:在 model 里给 override 开一个可单独卸载的层(不走 REPLACE、不动 accent/density)。最稳、最贵,改到 model 分层。

倾向 **B**:既实现 override 的持久,又顺手修掉 `SetDensity` 丢 accent 的既有坑,契合"3.0 前填坑"。

## Open Decisions(执行前/中需拍板,不阻塞 Phase 1)

1. **catalog 落地形态**:生成 Pascal 单元(本计划采用,设计期直接 `uses`,无文件 IO)vs 生成 JSON(更通用但设计期要读文件)。倾向 Pascal 单元。
2. **`background-color` 别名**是否进属性补全列表:进(用户常写),但标注"= background"。
3. **Controller.StyleOverride 用 `string` 还是 `TStrings`**:per-control 已是 `string`;为同名一致 + 有 SynEdit 编辑器托底,控制器也用 `string`。若 OI 里多行体验差可后续换 `TStrings`(非破坏性,可延后)。
4. **未知属性:警告 vs 硬错**:编辑器里给**警告**(不拦保存);运行时是否也从"静默丢"改成"lint 可报"是另一件事(ThemeLint 已有 property lint,可让 override 复用),本计划范围内只在编辑器侧警告。

## 验收清单(真机)
- [ ] IDE 里控件 `StyleOverride` 弹 SynEdit 对话框:高亮对、补全对(属性/token/函数)、未知属性有警告。
- [ ] Controller `StyleOverride`(带选择器)运行时生效,且**换肤后仍在**。
- [ ] 默认控制器代码设 `StyleOverride` 生效。
- [ ] per-control override 仍**只作用于该实例**、不级联(回归)。
