# TyControls v1.5 — 加固 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** 修复全库审计确认的 9 个真实缺陷,每个配回归测试。

**约束(记忆):** 几何/像素测试钉 `Font.PixelsPerInch:=96`;测试构建 `lazbuild tests/tytests.lpi` 后跑 `./tests/tytests`;新测试单元加进 `tytests.lpr` uses;子代理派发以 "DIRECT task. Do NOT invoke any brainstorming/planning skill, do NOT create plan files." 开头;现有 305 测试必须保持全绿,**不得修改既有测试**;`examples/demo/mainform.lfm` + `demo.lpi` 有用户未提交 IDE 改动,**勿碰**(本计划只改 `chromeform.pas`)。

**任务分组:**
- Task 1 — 引擎修复(#2 事务化 LoadFromCss、#5 后者覆盖、#6 alpha %、#7 3 值 padding)
- Task 2 — FormChrome 析构(#1)
- Task 3 — Enabled 守卫(#3)
- Task 4 — 渲染/一致性(#8 CheckBox/Radio 本地 rect、#9 ComboBox SetController)
- Task 5 — demo chromeform 主题路径(#4)

---

## Task 1: 引擎修复(StyleModel + Css.Values)

**Files:** Modify `source/tyControls.StyleModel.pas`, `source/tyControls.Css.Values.pas`; tests in `tests/test.StyleModel.pas` + `tests/test.Css.Values.pas`.

- [ ] **Step 1: 写失败测试**

加到 `tests/test.StyleModel.pas`(新 published 方法 + 实现):
```pascal
// 事务化:解析出错保留旧主题
procedure TestLoadFromCssParseErrorPreservesPrevious;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { color: #112233; border-width: 9px; }');
    try m.LoadFromCss('TyButton { @@@ broken'); except on ETyCssError do ; end;
    s := m.ResolveStyle('TyButton','',[]);
    AssertEquals('previous color preserved after parse error', $11, TyRedOf(s.TextColor));
    AssertEquals('previous border-width preserved', 9, s.BorderWidth);
  finally m.Free; end;
end;
// 后者覆盖
procedure TestDuplicateRuleLastWins;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { color:#111111; } TyButton { color:#222222; }');
    s := m.ResolveStyle('TyButton','',[]);
    AssertEquals('later duplicate rule wins', $22, TyRedOf(s.TextColor));
  finally m.Free; end;
end;
// 3 值 padding
procedure TestPaddingThreeValues;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { padding: 1px 2px 3px; }');  // top / left-right / bottom
    s := m.ResolveStyle('T','',[]);
    AssertEquals('top',1,s.Padding.Top); AssertEquals('right',2,s.Padding.Right);
    AssertEquals('bottom',3,s.Padding.Bottom); AssertEquals('left',2,s.Padding.Left);
  finally m.Free; end;
end;
```
加到 `tests/test.Css.Values.pas`(uses 已含 tyControls.Css.Values/Types):
```pascal
// alpha 百分号 = /100
procedure TestAlphaPercentArg;
var c: TTyColor;
begin
  c := TyEvalColor('alpha(#FF0000, 50%)', nil);
  AssertEquals('alpha 50% -> ~128', 128, TyAlphaOf(c));
  c := TyEvalColor('alpha(#FF0000, 0.5)', nil);  // bare still 0..1
  AssertEquals('alpha 0.5 -> ~128', 128, TyAlphaOf(c));
  c := TyEvalColor('alpha(#FF0000, 0)', nil);
  AssertEquals('alpha 0 -> 0', 0, TyAlphaOf(c));
end;
```
(把新方法名加进各测试类的 published 区。`TyEvalColor` 接受 `Vars: TStrings`——传 `nil` 可用;若该单元的 TyEvalColor 不容忍 nil Vars,则在测试里建一个空 `TStringList` 传入并释放。)

- [ ] **Step 2: 运行确认失败** — `cd /Users/tom/Projects/TyControls && lazbuild tests/tytests.lpi && ./tests/tytests --suite=TTestStyleLoad --format=plain` 等;新测试应失败(事务/后者覆盖/3值/alpha 当前都不满足)。

- [ ] **Step 3: 实现**

(3a) **#2 事务化 `LoadInto`**(`StyleModel.pas`):当前先 `ClearList(ARules); AVars.Clear;` 再 `parser.Parse`。改为:先解析到**局部临时** `TFPList` + `TStringList`,全部成功后再 `ClearList(ARules); AVars.Clear;` 并把临时内容搬入 `ARules`/`AVars`;解析中途异常则不动 `ARules`/`AVars`,异常照常外抛,并确保临时对象在 except 路径被释放(try/finally)。示意:
```pascal
procedure TTyStyleModel.LoadInto(ARules: TFPList; AVars: TStrings; const ASource: string);
var
  parser: TTyCssParser; sheet: TTyCssStylesheet;
  tmpRules: TFPList; tmpVars: TStringList;
  ri, si, di: Integer; rule: TTyCssRule; sel: TTyCssSelector; decl: TTyCssDeclaration; st: TTyStyleSet;
begin
  tmpRules := TFPList.Create;
  tmpVars := TStringList.Create;
  try
    parser := TTyCssParser.Create(ASource);
    try
      sheet := parser.Parse;           // may raise -> tmp* freed in finally, ARules untouched
      try
        tmpVars.Assign(sheet.RootVars);
        for ri := 0 to sheet.Rules.Count - 1 do
        begin
          rule := TTyCssRule(sheet.Rules[ri]);
          st := EmptyStyleSet;
          for di := 0 to High(rule.Declarations) do
          begin
            decl := rule.Declarations[di];
            TyApplyDeclaration(st, decl.Prop, decl.RawValue, tmpVars);
          end;
          for si := 0 to High(rule.Selectors) do
          begin
            sel := rule.Selectors[si];
            AddEntryTo(tmpRules, sel.TypeName, sel.Variant, sel.HasState, sel.State, st);
          end;
        end;
      finally
        sheet.Free;
      end;
    finally
      parser.Free;
    end;
    // success: commit
    ClearList(ARules);
    AVars.Clear;
    for ri := 0 to tmpRules.Count - 1 do ARules.Add(tmpRules[ri]);
    tmpRules.Clear;                    // ownership transferred; do NOT free entries
    AVars.Assign(tmpVars);
  except
    ClearList(tmpRules);               // free any entries built before the failure
    tmpRules.Free; tmpVars.Free;
    raise;
  end;
  tmpRules.Free; tmpVars.Free;
end;
```
> 注意所有权:成功路径把 entry 指针从 tmpRules 转移给 ARules 后,`tmpRules.Clear`(只清列表不 Free 元素),最后 `tmpRules.Free`(空列表)。异常路径 `ClearList(tmpRules)` 释放已建 entry。请仔细核对无双重释放/泄漏(Step 5 跑 heaptrc)。

(3b) **#5 后者覆盖** —— `FindStyleIn` 由 `for i := 0 to ARules.Count-1` 改为 `for i := ARules.Count-1 downto 0`(首个匹配即 Exit ⇒ 现在是最后一条胜出)。

(3c) **#7 3 值 padding** —— `ParsePadding` 的 `case parts.Count of` 加:
```pascal
      3:
        begin
          v[1] := TyEvalLength(parts[0], Vars); // top
          v[0] := TyEvalLength(parts[1], Vars); // left
          v[2] := v[0];                          // right
          v[3] := TyEvalLength(parts[2], Vars); // bottom
        end;
```

(3d) **#6 alpha %**(`Css.Values.pas` line ~223-224)—— alpha 第二参带 `%` 时按 /100。读 `ParsePctOrNum`;最简:专门给 alpha 算参数:
```pascal
// 替换 alpha 分支:
if (fn = 'alpha') and (args.Count = 2) then
begin
  a := Trim(args[1]);
  if (a <> '') and (a[Length(a)] = '%') then
    Exit(TyAlpha(TyEvalColor(args[0], Vars), ParsePctOrNum(a) / 100.0))
  else
    Exit(TyAlpha(TyEvalColor(args[0], Vars), ParsePctOrNum(a)));
end;
```
(在该函数 var 区加 `a: string;`。`ParsePctOrNum('50%')` 返回 50 ⇒ /100=0.5;`ParsePctOrNum('0.5')`=0.5;`'0'`=0。)

- [ ] **Step 4: 跑新测试 + 子套件** — 全绿。
- [ ] **Step 5: 全量回归 + heaptrc** — `./tests/tytests -a` = 305+新增、0/0;并按记忆做一次 `-gh` heaptrc(临时加 `-gh`、`HEAPTRC=log=` 跑、读 0 unfreed、`git checkout tests/tytests.lpi`),确认事务化 LoadInto 无泄漏/双重释放。
- [ ] **Step 6: Commit** — `git commit -m "fix(tycontrols): transactional theme load, last-wins duplicate rules, alpha() percent, 3-value padding"`

---

## Task 2: TTyFormChrome 析构(#1 Critical)

**Files:** Modify `source/tyControls.Form.pas`; test `tests/test.form.pas`.

- [ ] **Step 1: 写失败/崩溃回归测试**(加到 `tests/test.form.pas`)
```pascal
// Free 一个 Active 的 chrome 不应留下宿主窗体的悬空处理器
procedure TestFormChromeFreeWhileActiveNoDangling;
var F: TForm; Chrome: TTyFormChrome;
begin
  F := TForm.CreateNew(nil);
  try
    Chrome := TTyFormChrome.Create(F);
    Chrome.Active := True;            // installs: hijacks F.OnMouseDown etc.
    Chrome.Free;                      // must UninstallChrome in destructor
    AssertFalse('host OnMouseDown cleared after chrome free', Assigned(F.OnMouseDown));
    AssertFalse('host OnMouseMove cleared after chrome free', Assigned(F.OnMouseMove));
    // exercising the handler must not AV (it was restored to nil/original)
    if Assigned(F.OnMouseMove) then F.OnMouseMove(F, [], 10, 10);
    AssertTrue('no crash', True);
  finally
    F.Free;
  end;
end;
```
> 若该测试环境下 `Chrome.Active:=True` 因无真实 widgetset 句柄而无法完整安装,改为更稳的断言:安装后 `F.OnMouseDown` 已被接管(Assigned 为真且指向 chrome),Free 后变回未接管。实现者按实际 `InstallChrome` 行为微调断言,但**核心**是"Free 后宿主不再持有指向已释放 chrome 的处理器"。`test.form.pas` 已有 chrome 渲染测试可参考其构造方式。

- [ ] **Step 2: 确认失败**(无析构 ⇒ Free 后 OnMouseDown 仍 Assigned)。
- [ ] **Step 3: 实现** —— `TTyFormChrome` public 区加 `destructor Destroy; override;`,实现:
```pascal
destructor TTyFormChrome.Destroy;
begin
  if FForm <> nil then
    UninstallChrome;
  inherited Destroy;
end;
```
(`UninstallChrome` 撤销 OnMouseDown/Move/Up/ChangeBounds 并复原 BorderStyle;`Create(nil)`/未安装时 `FForm=nil` ⇒ no-op。)
- [ ] **Step 4: 跑测试** — 通过。
- [ ] **Step 5: 全量回归** — 305+1、0/0。
- [ ] **Step 6: Commit** — `git commit -m "fix(tycontrols): TTyFormChrome destructor uninstalls chrome to avoid dangling host handlers"`

---

## Task 3: Enabled 守卫(#3 High)

**Files:** Modify the input handlers across controls; tests in `tests/test.*` (toggleswitch/checkbox/trackbar/listbox at least).

- [ ] **Step 1: 写失败测试** —— 对审计已复现的代表路径,断言 `Enabled=False` 时输入**不**改状态:
  - `tests/test.toggleswitch.pas`:禁用后模拟 KeyDown(VK_SPACE)(或对应输入路径)→ Checked 不变、OnChange 不触发。
  - `tests/test.checkbox.pas`:禁用后 `Click` → Checked 不变。
  - `tests/test.trackbar.pas`:禁用后模拟 MouseDown 在远端 → Position 不变。
  - `tests/test.listbox.pas`:禁用后模拟 KeyDown(VK_DOWN)→ ItemIndex 不变。
  用各文件已有的 access 子类模式(暴露 protected MouseDown/KeyDown/Click)。
- [ ] **Step 2: 确认失败**(当前会改状态)。
- [ ] **Step 3: 实现** —— 在每个**输入入口**方法顶部加 `if not Enabled then Exit;`。覆盖(读各单元,只加在输入处理器,**不**加在属性 setter / 公开 SetChecked / SetPosition):
  - `Button.Click`、`CheckBox.Click`、`RadioButton.Click`、`ToggleSwitch` 的输入路径(Click / MouseUp / KeyDown,凡调用 Toggle 的)。
  - `TrackBar`:MouseDown、MouseMove(拖动)、KeyDown。
  - `ScrollBar`:MouseDown、MouseMove(拖动)、KeyDown(若有)。
  - `ListBox`:MouseDown、KeyDown、鼠标滚轮(DoMouseWheel)。
  - `ComboBox`:Click、MouseDown、KeyDown。
  - `TabControl`:MouseDown、KeyDown。
  - `Edit`:MouseDown、MouseMove(选区拖动)、KeyDown、UTF8KeyPress。
  统一加在方法第一行(在 `inherited` 之前),禁用时彻底不处理。
- [ ] **Step 4: 跑测试** — 新测试通过;**特别确认**既有交互测试(它们用默认 Enabled=True)仍全绿。
- [ ] **Step 5: 全量回归** — 0/0。
- [ ] **Step 6: Commit** — `git commit -m "fix(tycontrols): ignore input on disabled controls (Enabled guards)"`

---

## Task 4: 渲染/一致性(#8 + #9)

**Files:** Modify `source/tyControls.CheckBox.pas`, `source/tyControls.ComboBox.pas`; tests in `tests/test.checkbox.pas` / `tests/test.radiobutton.pas` / `tests/test.controls.combobox.pas`.

- [ ] **Step 1: 写失败测试**
  - #8:`test.checkbox.pas`(和/或 radiobutton)加偏移原点 + shadow 回归:主题 `TyCheckBox { shadow: 0px 0px 0px #FF0000FF; border-width:0px; }`,在 `Rect(20,5,100,33)` @96 渲染到 120×40 位图,探针——控件本地左上区(如 (22,7))应被红阴影覆盖(R>200),且红色不应整体偏移 (ARect.Left,ARect.Top)。参照 `test.trackbar.pas` 的偏移原点回归写法。
  - #9:`test.controls.combobox.pas`:建 combo,先 `DropDown` 触发 `FPopupList` 创建(或直接断言),再 `combo.Controller := Ctl2`,断言 `FPopupList.Controller = Ctl2`。`FPopupList` 是 private——用 access 子类暴露,或断言"重设 Controller 后弹层用新 controller"的可观察行为。
- [ ] **Step 2: 确认失败**。
- [ ] **Step 3: 实现**
  - #8:`CheckBox.pas` 两处 `DrawFrame(P, ARect, FrameS)` 改为先算 `ContentRect := Rect(0,0,ARect.Right-ARect.Left,ARect.Bottom-ARect.Top)` 再 `DrawFrame(P, ContentRect, FrameS)`(`ContentRect` 变量两行后已重算 box 区,确认不冲突——必要时用新局部变量名如 `FullRect`)。`RadioButton.RenderTo` 同改。
  - #9:`ComboBox.pas` 重写 `SetController`(protected,virtual——基类 `TTyCustomControl.SetController` 是 virtual):`inherited SetController(AValue); if FPopupList <> nil then FPopupList.Controller := AValue;`。在类声明 protected 区加 `procedure SetController(AValue: TTyStyleController); override;`。
- [ ] **Step 4: 跑测试** — 通过。
- [ ] **Step 5: 全量回归** — 0/0。
- [ ] **Step 6: Commit** — `git commit -m "fix(tycontrols): checkbox/radio (0,0)-local DrawFrame rect; combobox propagates Controller to popup"`

---

## Task 5: demo chromeform 主题路径(#4 High)

**Files:** Modify `source/.../examples/demo/chromeform.pas` ONLY(勿碰 mainform.lfm/demo.lpi 的用户改动)。

- [ ] **Step 1:** 读 `examples/demo/chromeform.pas` 的 `ThemeDir`,替换为与 `examples/demo/mainform.pas` 相同的向上逐级查找实现(循环 `DirectoryExists(Dir+'themes')`,最多 8 级,兜底相对路径)。对 `LoadTheme` 加防御:若解析到的主题文件 `not FileExists` 则跳过 LoadTheme(避免 `EFOpenError` 启动崩溃),控件回退内置皮肤。
- [ ] **Step 2:** 构建 demo:`cd /Users/tom/Projects/TyControls && lazbuild examples/demo/demo.lpi 2>&1 | tail -5` → 0 errors。
- [ ] **Step 3:** 用临时 smoke 程序实例化 demo + chrome 窗体(`Application.CreateForm` 不 `Run`)验证从 `lib/<cpu>-<os>/` 输出位置 LoadTheme 不再抛 `EFOpenError`(或至少 `ThemeDir` 解析到真实存在的 `themes/`)。或更轻:在 chromeform 单元内用一个临时 .lpi/.lpr 调 `ThemeDir` 打印结果并 `FileExists` 断言。完成后清理临时文件 + 任何 .lpi 构建 churn(`git checkout examples/demo/demo.lpi` 若被动过——它有用户改动,务必只还原构建噪音,保留用户的 cursor/Height 改动……**更稳妥:根本不构建会改 demo.lpi 的目标**;若 lazbuild 改了 demo.lpi,用 `git stash`/手工还原仅 UsageCount 行——或干脆不提交 demo.lpi)。
- [ ] **Step 4:** Commit —— **只** stage `examples/demo/chromeform.pas`:`git add examples/demo/chromeform.pas && git commit -m "fix(example/demo): robust upward theme-dir lookup in chrome window"`。`git status` 确认 mainform.lfm/demo.lpi 仍是用户未提交改动、未被 stage。

---

## 完成后
- 最终全套件 + 构建矩阵 + heaptrc 0 泄漏 + FormChrome free-while-active 不崩。
- 终审(reviewer 跑探针)。
- superpowers:finishing-a-development-branch(本地快进合并 main + 删分支)。
- 更新记忆。
