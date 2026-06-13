# TyControls v1.6 — CSS DSL 完整度 Implementation Plan

> 执行:superpowers:subagent-driven-development,**串行**派发 implementer。约束:几何/像素测试钉 PPI=96;`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests`;现有 327 测试保持全绿、不改既有测试;`examples/demo/mainform.lfm`+`demo.lpi` 有用户未提交改动勿碰;子代理派发以 "DIRECT task. Do NOT invoke any brainstorming/planning skill." 开头。

**现状(已核对):** `TTyProp`(Types.pas:27)无 `tpBorderStyle`;`TTyStyleSet`(:31)有 `BorderWidth` 无 `BorderStyle`;`TyApplyDeclaration`(StyleModel.pas:~273)处理 `border-color`/`border-width`,无 `border-style`/`border` 简写;`DrawFrame`(Base.pas:171-181 与 313-323 两份)用 `(tpBorderColor in Present) and (BorderWidth>0)` 决定画边框;`TyMergeStyleSet`(StyleModel.pas:~45)逐属性合并;`TyEvalColor`(Css.Values.pas:~195)函数分派含 lighten/darken/alpha/mix;`TyRGB`/`TyRGBA` 在 Types.pas。

任务:Task 1 border-style;Task 2 border 简写;Task 3 background-color 别名 + rgb/rgba;Task 4 文档。

---

## Task 1: border-style + DrawFrame 抑制

**Files:** `source/tyControls.Types.pas`、`source/tyControls.StyleModel.pas`、`source/tyControls.Base.pas`;tests `tests/test.StyleModel.pas` + `tests/test.base.drawframe.pas`。

- [ ] **Step 1 失败测试:**
  test.StyleModel.pas:
  ```pascal
  procedure TestBorderStyleNoneParsed;
  var m: TTyStyleModel; s: TTyStyleSet;
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss('T { border-style: none; border-width: 2px; border-color: #FF0000; }');
      s := m.ResolveStyle('T','',[]);
      AssertTrue('border-style present', tpBorderStyle in s.Present);
      AssertTrue('border-style none', s.BorderStyle = tbsNone);
    finally m.Free; end;
  end;
  procedure TestBorderStyleSolidDefault;
  var m: TTyStyleModel; s: TTyStyleSet;
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss('T { border-style: solid; }');
      s := m.ResolveStyle('T','',[]);
      AssertTrue('border-style solid', s.BorderStyle = tbsSolid);
    finally m.Free; end;
  end;
  ```
  test.base.drawframe.pas(用已有 TDrawFrameProbe + painter + bitmap 像素探针,参照 TestSolidBackgroundCenterPixel):
  ```pascal
  procedure TestBorderStyleNoneSuppressesBorder;
  // style: Background none, BorderColor #FF0000, BorderWidth 4, Present={tpBorderColor,tpBorderWidth,tpBorderStyle}, BorderStyle=tbsNone
  // render 40x40, probe an edge pixel where the border would be (e.g. (1,20)) -> must NOT be red (border suppressed).
  // Compare to a sibling case WITHOUT tpBorderStyle (or solid) where the edge IS red.
  ```
- [ ] **Step 2 确认失败/不编译**(tpBorderStyle/tbsNone 未声明)。
- [ ] **Step 3 实现:**
  (a) Types.pas:`type TTyBorderStyle = (tbsSolid, tbsNone);`。`TTyProp` 末尾加 `tpBorderStyle`。`TTyStyleSet` 加 `BorderStyle: TTyBorderStyle;`(放在 BorderWidth 附近)。`EmptyStyleSet` 用 `Default(TTyStyleSet)` 已使 BorderStyle=tbsSolid(序 0),无需额外赋值——确认即可。
  (b) StyleModel.pas `TyApplyDeclaration` 加:
  ```pascal
  else if prop = 'border-style' then
  begin
    if LowerCase(raw) = 'none' then AStyle.BorderStyle := tbsNone
    else AStyle.BorderStyle := tbsSolid;   // 'solid' 或其它都按 solid
    Include(AStyle.Present, tpBorderStyle);
  end
  ```
  (c) StyleModel.pas `TyMergeStyleSet` 加 `if tpBorderStyle in AOver.Present then ABase.BorderStyle := AOver.BorderStyle;`。
  (d) Base.pas **两处** DrawFrame:边框分支条件改为
  ```pascal
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0)
     and not ((tpBorderStyle in AStyle.Present) and (AStyle.BorderStyle = tbsNone)) then
    APainter.StrokeBorder(...);
  ```
- [ ] **Step 4/5/6:** 跑两套件 + 全量回归(327+3,0/0)+ commit `feat(tycontrols): border-style property (none suppresses border)`。

---

## Task 2: `border` 简写

**Files:** `source/tyControls.StyleModel.pas`;test `tests/test.StyleModel.pas`。

- [ ] **Step 1 失败测试:**
  ```pascal
  procedure TestBorderShorthand;
  var m: TTyStyleModel; s: TTyStyleSet;
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss('T { border: 2px solid #3B82F6; }');
      s := m.ResolveStyle('T','',[]);
      AssertEquals('width', 2, s.BorderWidth);
      AssertTrue('width present', tpBorderWidth in s.Present);
      AssertTrue('color present', tpBorderColor in s.Present);
      AssertEquals('color r', $3B, TyRedOf(s.BorderColor));
      AssertTrue('style solid', s.BorderStyle = tbsSolid);
      AssertTrue('style present', tpBorderStyle in s.Present);
    finally m.Free; end;
  end;
  procedure TestBorderShorthandNoneWidthColor;
  // 'border: 1px none #000000;' -> width1, color present, BorderStyle=tbsNone
  procedure TestBorderShorthandWithVarColor;
  // ':root{--a:#112233;} T{ border: 1px solid var(--a); }' -> color r=$11
  ```
- [ ] **Step 2 确认失败。**
- [ ] **Step 3 实现** —— `TyApplyDeclaration` 加 `border` 分支(放在 `border-color` 等之前或之后均可,注意 `prop='border'` 不能被 `border-color` 等的判断抢走——用精确 `prop = 'border'`):
  ```pascal
  else if prop = 'border' then
  begin
    ApplyBorderShorthand(AStyle, raw, Vars);  // 见下
  end
  ```
  新增私有 `procedure ApplyBorderShorthand(var AStyle: TTyStyleSet; const ARaw: string; Vars: TStrings);`:
  - 用 SplitArgs/手工按顶层空格切 token(对含括号的函数 token 如 `rgb(0, 0, 0)`/`var(--a)` 做括号配对,避免被内部空格/逗号切碎)。实现可参考 StyleModel 已有 `SplitArgs`(Css.Values 里,处理逗号);这里按**空格**切但要括号感知。若实现复杂,先支持:width(以数字开头、可带 px)、style(`solid`/`none`)、color(剩余 token 合并)三类,按 token 内容分类,而非严格位置。
  - width token → `AStyle.BorderWidth := TyEvalLength(tok, Vars); Include(tpBorderWidth)`。
  - style token(`solid`/`none`)→ 设 BorderStyle;`Include(tpBorderStyle)`。
  - color token(其余)→ `AStyle.BorderColor := TyEvalColor(tok, Vars); Include(tpBorderColor)`。若未给 style,不设 tpBorderStyle(按默认 solid 画)——但为明确,简写出现即可 `Include(tpBorderStyle)` 且默认 tbsSolid;两种都行,测试按"出现 solid 关键字才断言 style present"或"简写总设 style present"——**实现与测试保持一致**(本计划测试 `TestBorderShorthand` 断言 style present 且 solid,故简写中即便没写 solid 也应 Include tpBorderStyle=solid;`'2px solid #3B82F6'` 显式给了 solid,满足)。
  - 颜色 token 的括号感知切分:确保 `border: 1px solid rgb(0, 0, 0)` 中 `rgb(0, 0, 0)` 不被空格切碎(Task 3 才有 rgb,但切分逻辑要先就绪;若 Task 3 未完成,该用例可放 Task 3)。
- [ ] **Step 4/5/6:** 跑 + 全量回归(+3)+ commit `feat(tycontrols): border shorthand (border: <width> <style> <color>)`。

---

## Task 3: `background-color` 别名 + `rgb()/rgba()`

**Files:** `source/tyControls.StyleModel.pas`(background-color)、`source/tyControls.Css.Values.pas`(rgb/rgba);tests `tests/test.StyleModel.pas` + `tests/test.Css.Values.pas`。

- [ ] **Step 1 失败测试:**
  test.Css.Values.pas:
  ```pascal
  procedure TestRgbFunc;
  begin
    AssertEquals('rgb r', $12, TyRedOf(TyEvalColor('rgb(18, 52, 86)', nil)));   // 18=$12,52=$34,86=$56
    AssertEquals('rgb g', $34, TyGreenOf(TyEvalColor('rgb(18, 52, 86)', nil)));
    AssertEquals('rgb b', $56, TyBlueOf(TyEvalColor('rgb(18, 52, 86)', nil)));
    AssertEquals('rgb a opaque', $FF, TyAlphaOf(TyEvalColor('rgb(18, 52, 86)', nil)));
    AssertEquals('rgba a half', 128, TyAlphaOf(TyEvalColor('rgba(0, 0, 0, 0.5)', nil)));
  end;
  ```
  test.StyleModel.pas:
  ```pascal
  procedure TestBackgroundColorAlias;
  var m: TTyStyleModel; s: TTyStyleSet;
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss('T { background-color: #FF0000; }');
      s := m.ResolveStyle('T','',[]);
      AssertTrue('bg present', tpBackground in s.Present);
      AssertTrue('solid', s.Background.Kind = tfkSolid);
      AssertEquals('r', $FF, TyRedOf(s.Background.Color));
    finally m.Free; end;
  end;
  ```
- [ ] **Step 2 确认失败。**
- [ ] **Step 3 实现:**
  (a) Css.Values.pas `TyEvalColor` 函数分派加:
  ```pascal
  if (fn = 'rgb') and (args.Count = 3) then
    Exit(TyRGB(ClampByte(ParsePctOrNum(args[0])), ClampByte(ParsePctOrNum(args[1])), ClampByte(ParsePctOrNum(args[2]))));
  if (fn = 'rgba') and (args.Count = 4) then
  begin
    a := Trim(args[3]);
    if (a<>'') and (a[Length(a)]='%') then aF := ParsePctOrNum(a)/100.0 else aF := ParsePctOrNum(a);
    Exit(TyRGBA(ClampByte(ParsePctOrNum(args[0])), ClampByte(ParsePctOrNum(args[1])), ClampByte(ParsePctOrNum(args[2])), ClampByte(aF*255)));
  end;
  ```
  (var 区加 `a: string; aF: Single;`;`ClampByte` 已在单元;`TyRGB`/`TyRGBA` 在 tyControls.Types,确认 Css.Values uses 了 Types——是。args 用现有 SplitArgs 切。)
  (b) StyleModel.pas `TyApplyDeclaration`:把 `background-color` 当 `background` 同义——在 `prop = 'background'` 分支前/内加 `(prop = 'background') or (prop = 'background-color')` 判定(走纯色/渐变同一逻辑;`background-color` 一般是纯色,但复用 background 逻辑无害)。
- [ ] **Step 4/5/6:** 跑 + 全量回归(+2)+ commit `feat(tycontrols): rgb()/rgba() color functions + background-color alias`。
  > 若 Task 2 推迟了 `border: ... rgb(...)` 用例,在此补一个 `TestBorderShorthandWithRgb` 验证简写+rgb 协同。

---

## Task 4: 文档

**Files:** `docs/tycss-reference.md`(+ 可选 README)。

- [ ] 在 tycss-reference 的属性/函数表补:`border`(简写)、`border-style`(none/solid)、`background-color`(别名)、`rgb()`/`rgba()`。各给一行示例。说明 dashed/dotted/margin 暂不支持(KNOWN_GAPS 或文中注明)。commit `docs(tycontrols): document border shorthand, border-style, background-color, rgb()/rgba()`。

---

## 完成后
全套件 + 构建矩阵 + heaptrc 0 + 终审(reviewer 跑探针 + 确认三主题渲染零变化:它们用长写法,新特性纯叠加);本地快进合并 main + 删分支;更新记忆。
