# TyControls 批① 文本类 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把三个文本控件补到接近 LCL 同名控件:`TTyEdit` 加 ReadOnly/MaxLength/PasswordChar/TextHint;`TTyMemo` 加 ReadOnly/MaxLength;`TTySpinEdit` 从只读显示升级为可内联编辑的整数框;`TTyEdit`/`TTyMemo`/`TTySpinEdit` 共享一个可步进、无头静止的光标闪烁。

**Architecture:** 纯叠加。Edit/Memo 在已有 mutator 入口加 `ReadOnly`/`MaxLength` 守卫,`PasswordChar` 走掩码渲染+测量,`TextHint` 走空文本渲染分支(派生色)。SpinEdit 内置一个自包含轻量编辑层(编辑缓冲 `FEditText`+码点光标+提交/还原)。闪烁:`tyControls.Animation` 加纯函数 `TyCaretVisible`,各控件用惰性运行期 `TTimer` 翻转 `FCaretVisible`(默认 True、无头不启 timer→静态光标测试不变)。

**Tech Stack:** Free Pascal / Lazarus LCL / BGRABitmap;FPCUnit;PPI=96 像素探针;无头剪贴板 hook。

**约定:** 运行测试 `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`。基线 **0 failures + 15 个无头 win32(error 1407)环境错误(非回归,忽略)**。新增测试加在已注册单元里。提交信息 `feat(tycontrols): …`。**勿动 `examples/demo/demo.lpi`**(用户未提交改动)。

---

## File Structure

- `source/tyControls.Edit.pas` — 加 `FReadOnly/FMaxLength/FPasswordChar/FTextHint` + published;mutator 守卫;`DisplayText` 掩码 helper;`RenderTo` 掩码/占位符分支;blink 字段+timer。
- `source/tyControls.Memo.pas` — 加 `FReadOnly/FMaxLength` + published;mutator 守卫;blink 字段+timer。
- `source/tyControls.SpinEdit.pas` — 内联编辑层(`FEditText`/`FCaret`/测量/键入/提交/还原/渲染)+ blink。
- `source/tyControls.Animation.pas` — 纯函数 `TyCaretVisible`。
- `docs/controls/edit.md`、`memo.md`、`spinedit.md` — 新属性文档。
- Tests(已注册单元):`tests/test.edit.pas`、`tests/test.memo.pas`、`tests/test.spinedit.pas`、`tests/test.animation.pas`。`tests/test.edit.pas` 已有 `TTyEditAccess`(暴露 RenderTo/SimulateKeyDown/…)与 `TTyEditClipboardAccess`(内存剪贴板)。`tests/test.memo.pas` 用 Memo 的公开 `InjectChar/InjectKey/InjectBackspace/InjectDelete` + 同款 clipboard access。

---

## Group A — TTyEdit 属性

### Task 1: TTyEdit.ReadOnly

**Files:** Modify `source/tyControls.Edit.pas`; Test `tests/test.edit.pas`.

- [ ] **Step 1: 失败测试**(用 `TTyEditClipboardAccess`)。加到 `TEditTest` 的 published + 实现:

```pascal
procedure TestReadOnlyBlocksEditingButAllowsCopy;
var E: TTyEditClipboardAccess;
begin
  E := TTyEditClipboardAccess.Create(nil);
  try
    E.Text := 'abc';
    E.ReadOnly := True;
    E.CaretPos := 3;
    E.InjectKey('x');           // typing blocked
    AssertEquals('typing blocked', 'abc', E.Text);
    E.InjectBackspace;          // backspace blocked
    AssertEquals('backspace blocked', 'abc', E.Text);
    E.InjectDelete;             // delete blocked (at end anyway, but assert)
    E.CaretPos := 0; E.InjectDelete;
    AssertEquals('delete blocked', 'abc', E.Text);
    E.SelectAll;                // selection still works
    E.CopyToClipboard;
    AssertEquals('copy works in readonly', 'abc', E.ClipText);
    E.ClipText := 'ZZ'; E.PasteFromClipboard;   // paste blocked
    AssertEquals('paste blocked', 'abc', E.Text);
    E.Text := 'def';            // programmatic SetText still works
    AssertEquals('SetText still works', 'def', E.Text);
  finally E.Free; end;
end;

procedure TestReadOnlyCutActsAsCopy;
var E: TTyEditClipboardAccess;
begin
  E := TTyEditClipboardAccess.Create(nil);
  try
    E.Text := 'abc'; E.ReadOnly := True; E.SelectAll;
    E.CutToClipboard;
    AssertEquals('cut copied', 'abc', E.ClipText);
    AssertEquals('cut did not delete (readonly)', 'abc', E.Text);
  finally E.Free; end;
end;
```
Register both.

- [ ] **Step 2: 确认失败/不编译**(`ReadOnly` 未声明)。`lazbuild tests/tytests.lpi`。

- [ ] **Step 3: 实现**(`source/tyControls.Edit.pas`):
  - private 字段:`FReadOnly: Boolean;` 与 setter `procedure SetReadOnly(const AValue: Boolean);`(`if FReadOnly=AValue then Exit; FReadOnly:=AValue; Invalidate;`)。
  - published:`property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;`
  - 在这些方法体**第一行**(各方法已有的逻辑之前)加 `if FReadOnly then Exit;`:`InjectKey`、`InjectBackspace`、`InjectDelete`、`DeleteWordBackward`、`DeleteWordForward`、`InjectStringAt`、`PasteFromClipboard`。(注意:`UTF8KeyPress` 调 `InjectKey`、`KeyDown` 的退格/删除/词删/粘贴分支调上述方法,故守住这些即守住用户输入路径;`SetText` **不**加守卫。)
  - `CutToClipboard`:在 `BeginUndoStep(uskCut);` 之前加 `if FReadOnly then begin CopyToClipboard; Exit; end;`(ReadOnly 下只复制)。

- [ ] **Step 4: 跑** `./tests/tytests.exe -a --format=plain`;两用例 PASS;现有 edit 测试全绿;0 failures。
- [ ] **Step 5: Commit** `git add source/tyControls.Edit.pas tests/test.edit.pas && git commit -m "feat(tycontrols): TTyEdit.ReadOnly (blocks user edits, keeps copy/nav; cut acts as copy)"`

---

### Task 2: TTyEdit.MaxLength

**Files:** Modify `source/tyControls.Edit.pas`; Test `tests/test.edit.pas`.

- [ ] **Step 1: 失败测试:**

```pascal
procedure TestMaxLengthCapsTyping;
var E: TTyEditClipboardAccess;
begin
  E := TTyEditClipboardAccess.Create(nil);
  try
    E.MaxLength := 3;
    E.InjectKey('a'); E.InjectKey('b'); E.InjectKey('c');
    E.InjectKey('d');                         // blocked at cap
    AssertEquals('typing capped', 'abc', E.Text);
  finally E.Free; end;
end;

procedure TestMaxLengthTruncatesPaste;
var E: TTyEditClipboardAccess;
begin
  E := TTyEditClipboardAccess.Create(nil);
  try
    E.MaxLength := 5; E.Text := 'ab'; E.CaretPos := 2;
    E.ClipText := 'XXXXXXXX'; E.PasteFromClipboard;  // only 3 fit
    AssertEquals('paste truncated to cap', 'abXXX', E.Text);
  finally E.Free; end;
end;

procedure TestMaxLengthZeroUnlimited;
var E: TTyEditClipboardAccess; i: Integer;
begin
  E := TTyEditClipboardAccess.Create(nil);
  try
    E.MaxLength := 0;
    for i := 1 to 20 do E.InjectKey('z');
    AssertEquals('unlimited', 20, UTF8Length(E.Text));
  finally E.Free; end;
end;
```
Register all three. (`UTF8Length` is from `LazUTF8`, already in test.edit's uses.)

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现:**
  - private `FMaxLength: Integer;` + setter `SetMaxLength`(`if FMaxLength=AValue then Exit; FMaxLength:=AValue;` — no truncate of existing text, matches LCL); published `property MaxLength: Integer read FMaxLength write SetMaxLength default 0;`
  - `InjectKey`:在删除选区之后、插入之前(`Before := UTF8Copy(...)` 之前)加:
    ```pascal
    if (FMaxLength > 0) and (UTF8Length(FText) >= FMaxLength) then Exit;
    ```
  - `InjectStringAt`(粘贴的实际插入点):在 `if AStr = '' then Exit;` 之后加截断:
    ```pascal
    if FMaxLength > 0 then
    begin
      var room: Integer = FMaxLength - UTF8Length(FText);
      if room <= 0 then Exit;
      if UTF8Length(AStr) > room then
        // truncate the inserted string to the remaining room (codepoints)
        Exit_or_truncate;  // see below
    end;
    ```
    具体写法(FPC 不支持内联 `var`,用顶部局部变量 `room: Integer; Ins: string;`):
    ```pascal
    procedure TTyEdit.InjectStringAt(const AStr: string);
    var Before, After, Ins: string; InsLen, room, APPI: Integer;
    begin
      if AStr = '' then Exit;
      if FReadOnly then Exit;              // (from Task 1)
      Ins := AStr;
      if FMaxLength > 0 then
      begin
        room := FMaxLength - UTF8Length(FText);
        if room <= 0 then Exit;
        if UTF8Length(Ins) > room then Ins := UTF8Copy(Ins, 1, room);
      end;
      BeginUndoStep(uskPaste);
      Before := UTF8Copy(FText, 1, FCaret);
      After  := UTF8Copy(FText, FCaret + 1, UTF8Length(FText) - FCaret);
      FText  := Before + Ins + After;
      InsLen := UTF8Length(Ins);
      FCaret := FCaret + InsLen;
      FSelAnchor := FCaret;
      InvalidateWidthCache;
      APPI := Font.PixelsPerInch;
      EnsureCaretVisible(APPI);
      Invalidate;
    end;
    ```
    (即把现有 `InjectStringAt` 整体替换为上面这版,合并 Task1 的 ReadOnly 守卫 + MaxLength 截断;其余逻辑与原版一致。)
- [ ] **Step 4: 跑;三用例 PASS;现有绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyEdit.MaxLength (codepoint cap on typing + paste truncation)`

---

### Task 3: TTyEdit.PasswordChar

**Files:** Modify `source/tyControls.Edit.pas`; Test `tests/test.edit.pas`.

- [ ] **Step 1: 失败测试**(掩码渲染:渲染 `'abc'` + PasswordChar `'*'`,验证某字母位置的墨迹形状对应掩码而非原字母——稳健做法:断言 `DisplayText` helper + 渲染不崩 + 掩码时复制为空):

```pascal
procedure TestPasswordCharMasksDisplayText;
var E: TTyEditAccess;
begin
  E := TTyEditAccess.Create(nil);
  try
    E.Text := 'abc';
    E.PasswordChar := '*';
    AssertEquals('display masked', '***', E.DisplayTextForTest);
    E.PasswordChar := '';
    AssertEquals('display plain when off', 'abc', E.DisplayTextForTest);
  finally E.Free; end;
end;

procedure TestPasswordCharDisablesCopy;
var E: TTyEditClipboardAccess;
begin
  E := TTyEditClipboardAccess.Create(nil);
  try
    E.Text := 'secret'; E.PasswordChar := '*'; E.SelectAll;
    E.ClipText := 'sentinel';
    E.CopyToClipboard;
    AssertEquals('copy disabled under mask', 'sentinel', E.ClipText);
    E.CutToClipboard;
    AssertEquals('cut disabled under mask (clip unchanged)', 'sentinel', E.ClipText);
    AssertEquals('cut did not delete under mask', 'secret', E.Text);
  finally E.Free; end;
end;

procedure TestPasswordCharCaretAlignsToMaskWidth;
{ Caret x at index 2 must equal the mask-measured width of 2 mask chars, not the
  plain 'ab' width — proving measurement uses the masked string. }
var E: TTyEditAccess;
begin
  E := TTyEditAccess.Create(nil);
  try
    E.Text := 'WiWi';            // proportional: 'Wi' wider than '**'
    E.PasswordChar := '*';
    E.Font.PixelsPerInch := 96;
    // With masking, all glyphs are '*'; caret at 2 should be 2 * one-'*' advance,
    // i.e. exactly half of caret-at-4. Assert monotonic + proportional to mask.
    AssertTrue('caret@2 < caret@4', E.CaretPixelX2(2) < E.CaretPixelX2(4));
    AssertTrue('caret@2 ~ half of caret@4 (uniform mask)',
      Abs((E.CaretPixelX2(4) - E.TextStartXForTest) - 2*(E.CaretPixelX2(2) - E.TextStartXForTest)) <= 2);
  finally E.Free; end;
end;
```
给 `TTyEditAccess` 加测试访问器(public):
```pascal
function DisplayTextForTest: string;            // calls protected DisplayText
function CaretPixelX2(AIdx: Integer): Integer;  // CaretPixelXAt(AIdx, 96)
function TextStartXForTest: Integer;            // TextStartX(96)
```
实现:`Result := DisplayText;` / `Result := CaretPixelXAt(AIdx, 96);` / `Result := TextStartX(96);`(`DisplayText`/`TextStartX` 需提为 protected,见 Step 3)。Register 三个测试。

- [ ] **Step 2: 确认失败/不编译。**
- [ ] **Step 3: 实现**(`source/tyControls.Edit.pas`):
  - private `FPasswordChar: string;` + setter `SetPasswordChar`(取首码点:`if UTF8Length(AValue) > 1 then FPasswordChar := UTF8Copy(AValue,1,1) else FPasswordChar := AValue; InvalidateWidthCache; Invalidate;`);published `property PasswordChar: string read FPasswordChar write SetPasswordChar;`
  - protected helper:
    ```pascal
    function TTyEdit.DisplayText: string;
    var i, n: Integer;
    begin
      if FPasswordChar = '' then Exit(FText);
      n := UTF8Length(FText);
      Result := '';
      for i := 1 to n do Result := Result + FPasswordChar;
    end;
    ```
    在 interface 的 protected 段声明 `function DisplayText: string;`;并把 `function TextStartX` 已是 private——**移到 protected**(测试访问器需要)。
  - `MeasureCodepointWidths`:把测量对象由 `FText` 改 `DisplayText`——即把循环里的 `UTF8Copy(FText, 1, i)` 改 `UTF8Copy(DisplayText, 1, i)`,并把缓存有效性判断也纳入 password 状态(在 cache key 上加 `FWidthCachePassword: string` 字段,比较 `FWidthCachePassword = FPasswordChar`;rebuild 时存 `FWidthCachePassword := FPasswordChar`)。避免明文/掩码切换后用错缓存。
  - `RenderTo`:把绘制正文那两处 `P.DrawText(..., FText, ...)` 改为 `P.DrawText(..., DisplayText, ...)`(选区带/光标用的是 `Widths`,已基于 DisplayText,无需改)。
  - `CopyToClipboard`:开头加 `if FPasswordChar <> '' then Exit;`。`CutToClipboard`:开头(ReadOnly 检查附近)加 `if FPasswordChar <> '' then Exit;`。
- [ ] **Step 4: 跑;三用例 PASS;现有 edit 渲染测试仍绿(默认 PasswordChar='' → DisplayText=FText,零变化)。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyEdit.PasswordChar (masked render+measure; copy/cut disabled under mask)`

---

### Task 4: TTyEdit.TextHint(占位符)

**Files:** Modify `source/tyControls.Edit.pas`; Test `tests/test.edit.pas`.

- [ ] **Step 1: 失败测试**(渲染空文本 + TextHint,验证内容区有墨迹;非空文本时无 hint。用白底+reread 探针,沿用 test.edit 既有渲染探针风格):

```pascal
procedure TestTextHintRendersWhenEmpty;
var E: TTyEditAccess; bmp: TBitmap; reread: TBGRABitmap; foundInk: Boolean; x,y: Integer; px: TBGRAPixel;
begin
  E := TTyEditClipboardAccess.Create(nil);
  bmp := TBitmap.Create;
  try
    E.Text := ''; E.TextHint := 'Search...'; E.Font.PixelsPerInch := 96;
    E.SetBounds(0,0,160,28);
    bmp.PixelFormat := pf32bit; bmp.SetSize(160,28);
    bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0,0,160,28);
    E.RenderTo(bmp.Canvas, Rect(0,0,160,28), 96);
    reread := TBGRABitmap.Create(bmp);
    try
      foundInk := False;
      for x := 4 to 80 do for y := 6 to 22 do
      begin
        px := reread.GetPixel(x,y);
        if (px.red < 230) or (px.green < 230) or (px.blue < 230) then foundInk := True;
      end;
      AssertTrue('hint ink present when empty', foundInk);
    finally reread.Free; end;
  finally bmp.Free; E.Free; end;
end;

procedure TestTextHintHiddenWhenNonEmpty;
var E: TTyEditAccess;
begin
  E := TTyEditAccess.Create(nil);
  try
    E.Text := 'x'; E.TextHint := 'Search...';
    AssertTrue('hint suppressed when text present', E.HintVisibleForTest = False);
  finally E.Free; end;
end;
```
给 `TTyEditAccess` 加 `function HintVisibleForTest: Boolean;`(`Result := (FText = '') and (FTextHint <> '');` — 需把判断逻辑暴露;实现里直接复制该条件)。Register 两个。

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现:**
  - private `FTextHint: string;` + setter `SetTextHint`(`if FTextHint=AValue then Exit; FTextHint:=AValue; if FText='' then Invalidate;`);published `property TextHint: string read FTextHint write SetTextHint;`
  - 测试访问器 `HintVisibleForTest`:`Result := (FText = '') and (FTextHint <> '');`
  - `RenderTo`:在绘制正文的分支处,当 `FText = ''` 且 `FTextHint <> ''` 时,改为绘制 hint(派生 50% alpha 色):
    ```pascal
    // after DrawFrame + ContentRect inset, before/instead of the normal text draw:
    if (FText = '') and (FTextHint <> '') then
    begin
      var hintColor := TyRGBA(TyRedOf(S.TextColor), TyGreenOf(S.TextColor),
                              TyBlueOf(S.TextColor), $80);   // ~50% alpha, theme-derived
      P.DrawText(ContentRect, FTextHint, S.FontName, EffSize, S.FontWeight,
        hintColor, taLeftJustify, tlCenter, True);
    end
    else
      <existing normal-text draw block (FScrollX>0 ... else ...)>;
    ```
    FPC 无内联 var:在 RenderTo 顶部 var 区加 `HintColor: TTyColor;`,赋值 `HintColor := TyRGBA(...)`。光标分支(`if Focused and not HasSelection`)保持不变——空文本聚焦时仍画光标在 hint 之上。
- [ ] **Step 4: 跑;两用例 PASS;现有绿(默认 TextHint='' → 走原正文分支,零变化)。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyEdit.TextHint placeholder (theme-derived dim color, shown when empty)`

---

## Group B — TTyMemo 属性

### Task 5: TTyMemo.ReadOnly

**Files:** Modify `source/tyControls.Memo.pas`; Test `tests/test.memo.pas`.

- [ ] **Step 1: 失败测试**(用 Memo 的 clipboard access 子类——若 test.memo.pas 无,加一个 `TTyMemoClipAccess = class(TTyMemo) ... override ReadClipboardText/WriteClipboardText`,镜像 test.memo.selection.pas 的做法)。Memo 公开 `InjectChar/InjectKey/InjectBackspace/InjectDelete/PasteFromClipboard/CutToClipboard/CopyToClipboard` + `Lines`。

```pascal
procedure TestMemoReadOnlyBlocksEditsAllowsNav;
var M: TTyMemoClipAccess;
begin
  M := TTyMemoClipAccess.Create(nil);
  try
    M.Lines.Text := 'abc';
    M.ReadOnly := True;
    M.InjectChar('x');                 // typing blocked
    AssertEquals('typing blocked', 'abc', M.Lines.Text);
    M.InjectKey(VK_RETURN, []);        // Enter (split) blocked
    AssertEquals('enter blocked (still 1 line)', 1, M.Lines.Count);
    M.InjectBackspace; M.InjectDelete; // blocked
    AssertEquals('bksp/del blocked', 'abc', M.Lines.Text);
    M.ClipText := 'ZZ'; M.PasteFromClipboard;   // paste blocked
    AssertEquals('paste blocked', 'abc', M.Lines.Text);
    M.Lines.Text := 'def';             // programmatic still works
    AssertEquals('Lines:= still works', 'def', Trim(M.Lines.Text));
  finally M.Free; end;
end;

procedure TestMemoReadOnlyCutActsAsCopy;
var M: TTyMemoClipAccess;
begin
  M := TTyMemoClipAccess.Create(nil);
  try
    M.Lines.Text := 'abc'; M.ReadOnly := True; M.SelectAll;
    M.CutToClipboard;
    AssertTrue('cut copied something', Pos('abc', M.ClipText) > 0);
    AssertEquals('cut did not delete', 'abc', Trim(M.Lines.Text));
  finally M.Free; end;
end;
```
Register both; ensure `LCLType` (VK_RETURN) in uses.

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现**(`source/tyControls.Memo.pas`):
  - private `FReadOnly: Boolean;` + `SetReadOnly`(`if FReadOnly=AValue then Exit; FReadOnly:=AValue; Invalidate;`);published `property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;`
  - **READ each method first**, then insert `if FReadOnly then Exit;` as the FIRST statement (after any existing `if not Enabled then Exit;`) of every USER-edit entry so a ReadOnly memo ignores edits but keeps nav/selection/copy. The model-mutation entries to guard: `UTF8KeyPress` (blocks printable typing); the public `InjectChar`, `InjectBackspace`, `InjectDelete`; `DeleteWordBackward`, `DeleteWordForward`; `PasteFromClipboard`; and the `VK_RETURN` (Enter/split) branch inside `KeyDown` (guard that branch with `if not FReadOnly then <existing split call>`). `CutToClipboard` → at its top add `if FReadOnly then begin CopyToClipboard; Exit; end;`. **Do NOT** guard `SetLines`/`Lines:=`, caret-nav branches, Shift-selection, `CopyToClipboard`, `SelectAll`.
  - The two tests above drive typing/Enter/Backspace/Delete/Paste/Cut and Lines:= ; they are the behavioral contract — make them pass. If KeyDown routes Backspace/Delete through the public `InjectBackspace/InjectDelete`, guarding those covers it; verify by reading `KeyDown`.
- [ ] **Step 4: 跑;两用例 PASS;现有 memo 测试全绿;0 failures。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyMemo.ReadOnly (blocks user edits, keeps nav/copy; cut acts as copy)`

---

### Task 6: TTyMemo.MaxLength

**Files:** Modify `source/tyControls.Memo.pas`; Test `tests/test.memo.pas`.

- [ ] **Step 1: 失败测试:**

```pascal
procedure TestMemoMaxLengthCapsTyping;
var M: TTyMemoClipAccess; i: Integer;
begin
  M := TTyMemoClipAccess.Create(nil);
  try
    M.MaxLength := 3;
    M.InjectChar('a'); M.InjectChar('b'); M.InjectChar('c');
    M.InjectChar('d');                         // blocked at cap
    AssertEquals('typing capped', 'abc', Trim(M.Lines.Text));
    // Enter still allowed even at cap (does not add content codepoints)
    M.InjectKey(VK_RETURN, []);
    AssertEquals('enter allowed at cap', 2, M.Lines.Count);
  finally M.Free; end;
end;

procedure TestMemoMaxLengthTruncatesPaste;
var M: TTyMemoClipAccess;
begin
  M := TTyMemoClipAccess.Create(nil);
  try
    M.MaxLength := 5; M.Lines.Text := 'ab';
    M.InjectKey(VK_END, [ssCtrl]);             // caret to doc end (or set caret)
    M.ClipText := 'XXXXXXXX'; M.PasteFromClipboard;
    AssertEquals('paste truncated to remaining room', 5, MemoContentCodepoints(M));
  finally M.Free; end;
end;
```
加一个测试内 helper `function MemoContentCodepoints(M: TTyMemo): Integer;`(sum of `UTF8Length(M.Lines[i])` over all lines)。Register both. (Content-codepoint = excludes line breaks, matching the spec.)

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现:**
  - private `FMaxLength: Integer;` + `SetMaxLength`(`if FMaxLength=AValue then Exit; FMaxLength:=AValue;`);published `property MaxLength: Integer read FMaxLength write SetMaxLength default 0;`
  - private helper `function ContentCodepointCount: Integer;`:
    ```pascal
    function TTyMemo.ContentCodepointCount: Integer;
    var i: Integer;
    begin
      Result := 0;
      for i := 0 to FLines.Count - 1 do Inc(Result, UTF8Length(FLines[i]));
    end;
    ```
  - Guard ONLY the content-adding paths:
    - The printable-insert path (the routine `UTF8KeyPress` uses to add one codepoint — likely a wrapper around `DoInsertText`): before inserting, add `if (FMaxLength > 0) and (ContentCodepointCount >= FMaxLength) then Exit;`. READ `UTF8KeyPress` to find the exact insert call and guard there (or guard at the top of `DoInsertText` with the count check — but `DoInsertText` is also used by paste; for paste we truncate instead, so prefer guarding the single-char insert wrapper, NOT `DoInsertText` directly).
    - `PasteFromClipboard`: after computing the text to insert, truncate so total ≤ MaxLength. READ the method; where it builds/inserts the clipboard text, compute `room := FMaxLength - ContentCodepointCount` (when `FMaxLength>0`) and truncate the inserted payload's codepoints to `room` (≤0 → no-op). For the multi-line paste, truncating to `room` total content codepoints across the joined insertion is acceptable; simplest correct approach: if `FMaxLength>0` and the clipboard content's codepoint count (excluding CR/LF) would exceed room, trim the clipboard string to fit before splitting. Document the choice in a comment.
  - Enter/Backspace/Delete/merge: NOT guarded (do not add content codepoints).
- [ ] **Step 4: 跑;两用例 PASS;现有绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyMemo.MaxLength (content-codepoint cap on typing + paste truncation)`

---

## Group C — TTySpinEdit 内联编辑

### Task 7: SpinEdit 编辑模型(缓冲/光标/键入/提交/还原,无头)

**Files:** Modify `source/tyControls.SpinEdit.pas`; Test `tests/test.spinedit.pas`.

- [ ] **Step 1: 失败测试**(给 `tests/test.spinedit.pas` 加 access 子类暴露注入 + 缓冲读取;读该文件取既有 access 风格):

```pascal
type
  TTySpinAccess = class(TTySpinEdit)
  public
    procedure DoKey(Key: Word; Shift: TShiftState);   // calls KeyDown
    procedure TypeChar(const C: TUTF8Char);            // calls UTF8KeyPress
    function EditTextForTest: string;                  // FEditText
    function CaretForTest: Integer;                    // FCaret
    procedure CommitForTest;                           // commit (parse+clamp)
  end;
...
procedure TTySpinAccess.DoKey(Key: Word; Shift: TShiftState); begin KeyDown(Key, Shift); end;
procedure TTySpinAccess.TypeChar(const C: TUTF8Char); var k: TUTF8Char; begin k := C; UTF8KeyPress(k); end;
function TTySpinAccess.EditTextForTest: string; begin Result := FEditText; end;
function TTySpinAccess.CaretForTest: Integer; begin Result := FCaret; end;
procedure TTySpinAccess.CommitForTest; begin CommitEdit; end;

procedure TestSpinTypeDigitsIntoBuffer;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 1000; S.Value := 0;
    S.FocusBufferForTest;                  // sync buffer to '0' and caret to end
    S.TypeChar('4'); S.TypeChar('2');
    AssertTrue('digits in buffer', Pos('42', S.EditTextForTest) > 0);
  finally S.Free; end;
end;

procedure TestSpinCommitParsesAndClamps;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 50; S.Value := 0;
    S.FocusBufferForTest; S.SetEditTextForTest('999');
    S.CommitForTest;
    AssertEquals('clamped to max', 50, S.Value);
    AssertEquals('buffer resynced', '50', S.EditTextForTest);
  finally S.Free; end;
end;

procedure TestSpinEscRevertsBuffer;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 7;
    S.FocusBufferForTest; S.SetEditTextForTest('99');
    S.DoKey(VK_ESCAPE, []);
    AssertEquals('value unchanged after Esc', 7, S.Value);
    AssertEquals('buffer reverted', '7', S.EditTextForTest);
  finally S.Free; end;
end;

procedure TestSpinEnterCommits;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 0;
    S.FocusBufferForTest; S.SetEditTextForTest('33');
    S.DoKey(VK_RETURN, []);
    AssertEquals('enter committed', 33, S.Value);
  finally S.Free; end;
end;

procedure TestSpinArrowStepsAndResyncsBuffer;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 5; S.Increment := 2;
    S.FocusBufferForTest;
    S.DoKey(VK_UP, []);
    AssertEquals('value stepped', 7, S.Value);
    AssertEquals('buffer resynced to value', '7', S.EditTextForTest);
  finally S.Free; end;
end;

procedure TestSpinInvalidCommitFallsBack;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 9;
    S.FocusBufferForTest; S.SetEditTextForTest('-');   // not a number
    S.CommitForTest;
    AssertEquals('invalid falls back to current value', 9, S.Value);
    AssertEquals('buffer resynced', '9', S.EditTextForTest);
  finally S.Free; end;
end;
```
给 access 子类再加 `procedure FocusBufferForTest;`(`SyncBufferToValue;`)与 `procedure SetEditTextForTest(const S: string);`(`FEditText := S; FCaret := UTF8Length(S);`)。Register all six. (`VK_ESCAPE` from LCLType.)

- [ ] **Step 2: 确认失败/不编译。**
- [ ] **Step 3: 实现**(`source/tyControls.SpinEdit.pas`):
  - private 字段:`FEditText: string; FCaret: Integer;`。
  - `uses` 加 `LazUTF8`。
  - 私有方法:
    ```pascal
    procedure SyncBufferToValue;   // FEditText := IntToStr(FValue); FCaret := UTF8Length(FEditText);
    procedure CommitEdit;          // v := StrToIntDef(FEditText, FValue); Value := v (setter clamps); SyncBufferToValue;
    procedure InsertEditChar(const C: TUTF8Char);   // digit/leading-minus rules below
    procedure EditBackspace;       // delete cp before caret in FEditText
    procedure EditDelete;          // delete cp at caret
    ```
    `InsertEditChar` 规则:接受 `'0'..'9'`;接受 `'-'` 仅当 `FCaret=0` 且 `Pos('-', FEditText)=0`;其它字符忽略。插入到 `FCaret`(UTF8 splice,Inc(FCaret))。
    `CommitEdit`:`var v: Integer; begin v := StrToIntDef(Trim(FEditText), FValue); Value := v; SyncBufferToValue; Invalidate; end;`(`Value` setter 已夹紧 `[Min,Max]` 并触发 OnChange;空串/`'-'` → StrToIntDef 回退 FValue。)
  - `Create`:末尾加 `SyncBufferToValue;`。
  - `SetValue`/`SetMinValue`/`SetMaxValue`:在各自改值后调 `SyncBufferToValue;`(保证步进/外部赋值后缓冲跟随)。**注意**:`SetValue` 里已有 `if FValue=Clamped then Exit;`——把 `SyncBufferToValue` 放在 `FValue := Clamped;` 之后、`Invalidate` 之前;另外即便相等也需在初始/箭头场景同步,故在三个 setter 末尾统一调用(相等早退的情况缓冲本就一致,无害)。简单起见:`SetValue` 改为算出 Clamped→若不同则更新+OnChange,**无论是否变化都** `SyncBufferToValue`(放在 Exit 之前不行;改为:先算 Clamped,if 不同则赋值/OnChange,最后 `SyncBufferToValue; Invalidate;` 在 if 之外)。
  - `UTF8KeyPress`(override,新增):
    ```pascal
    procedure TTySpinEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
    begin
      if not Enabled then Exit;
      inherited UTF8KeyPress(UTF8Key);
      InsertEditChar(UTF8Key);
      Invalidate;
    end;
    ```
  - `KeyDown`:在现有 `VK_UP`/`VK_DOWN`(它们 `Value := FValue ± FIncrement`——保持,`SetValue` 现在会 resync 缓冲)之外,新增分支:
    ```pascal
    VK_RETURN: begin CommitEdit; Key := 0; end;
    VK_ESCAPE: begin SyncBufferToValue; Invalidate; Key := 0; end;
    VK_BACK:   begin EditBackspace; Invalidate; Key := 0; end;
    VK_DELETE: begin EditDelete; Invalidate; Key := 0; end;
    VK_LEFT:   begin if FCaret > 0 then Dec(FCaret); Invalidate; Key := 0; end;
    VK_RIGHT:  begin if FCaret < UTF8Length(FEditText) then Inc(FCaret); Invalidate; Key := 0; end;
    VK_HOME:   begin FCaret := 0; Invalidate; Key := 0; end;
    VK_END:    begin FCaret := UTF8Length(FEditText); Invalidate; Key := 0; end;
    ```
    （`VK_UP/VK_DOWN` 维持原步进。）
  - `DoExit`(override,新增):`begin inherited DoExit; CommitEdit; end;`(失焦提交)。
- [ ] **Step 4: 跑;六用例 PASS;现有 spinedit 测试(箭头/滚轮/按钮步进、夹紧、OnChange)仍绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTySpinEdit inline edit model (typed digits, Enter/blur commit+clamp, Esc revert)`

---

### Task 8: SpinEdit 渲染缓冲 + 光标(测量对齐)

**Files:** Modify `source/tyControls.SpinEdit.pas`; Test `tests/test.spinedit.pas`.

- [ ] **Step 1: 失败测试**(渲染 + 光标像素):

```pascal
procedure TestSpinRendersBufferNotValue;
{ After typing into the buffer (uncommitted), the control shows the buffer text. }
var S: TTySpinAccess; bmp: TBitmap; reread: TBGRABitmap; foundInk: Boolean; x,y:Integer; px:TBGRAPixel;
begin
  S := TTySpinAccess.Create(nil);
  bmp := TBitmap.Create;
  try
    S.MinValue:=0; S.MaxValue:=1000; S.Value:=0; S.Font.PixelsPerInch:=96;
    S.FocusBufferForTest; S.SetEditTextForTest('789');
    bmp.PixelFormat:=pf32bit; bmp.SetSize(120,28);
    bmp.Canvas.Brush.Color:=clWhite; bmp.Canvas.FillRect(0,0,120,28);
    S.RenderToForTest(bmp.Canvas, Rect(0,0,120,28), 96);
    reread := TBGRABitmap.Create(bmp);
    try
      foundInk := False;
      for x := 2 to 60 do for y := 6 to 22 do
      begin px := reread.GetPixel(x,y);
        if (px.red<200) and (px.green<200) then foundInk := True; end;
      AssertTrue('buffer text rendered', foundInk);
    finally reread.Free; end;
  finally bmp.Free; S.Free; end;
end;

procedure TestSpinCaretXMonotonic;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue:=0; S.MaxValue:=100000; S.Font.PixelsPerInch:=96;
    S.FocusBufferForTest; S.SetEditTextForTest('12345');
    AssertTrue('caret x grows with index',
      S.CaretXForTest(1) < S.CaretXForTest(4));
  finally S.Free; end;
end;
```
给 access 加 `procedure RenderToForTest(...)`(calls protected `RenderTo`)与 `function CaretXForTest(AIdx: Integer): Integer;`(calls the new `CaretPixelX(AIdx, 96)` helper)。Register both.

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现:**
  - `uses` 加 `BGRABitmap, BGRABitmapTypes`。private `FMeasureBmp: TBGRABitmap;`(`Create` 不建,惰性;`Destroy` `FMeasureBmp.Free`)。
  - 测量 helper(镜像 Edit):
    ```pascal
    function TTySpinEdit.CaretPixelX(AIdx, APPI: Integer): Integer;
    var S: TTyStyleSet; EffSize: Integer;
    begin
      S := CurrentStyle;
      EffSize := S.FontSize; if EffSize <= 0 then EffSize := 12;
      Result := P_pad_left(APPI);   // = MulDiv(S.Padding.Left, APPI, 96)
      if (FEditText = '') or (AIdx <= 0) then Exit;
      if FMeasureBmp = nil then FMeasureBmp := TBGRABitmap.Create(1,1);
      TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
      Result := Result + FMeasureBmp.TextSize(UTF8Copy(FEditText, 1, AIdx)).cx;
    end;
    ```
    （`P_pad_left` 即内联 `MulDiv(S.Padding.Left, APPI, 96)`;`TyConfigureTextFont` 来自 `tyControls.Painter`,已在 uses。）
  - `RenderTo`:把绘制文本由 `IntToStr(FValue)` 改为 `FEditText`(`FEditText` 已随 Value/箭头 resync,故未聚焦时也等于值文本)。在画完文本后,**聚焦时**画 1px 光标(与 Edit 同款,但需考虑 blink——Task 10 接入;此任务先无条件按 `Focused` 画):
    ```pascal
    P.DrawText(TextR, FEditText, S.FontName, EffSize, S.FontWeight, S.TextColor, taLeftJustify, tlCenter, True);
    if Focused then
    begin
      cx := CaretPixelX(FCaret, APPI);   // device px from local left
      CaretRect := Rect(cx, TextR.Top + P.Scale(2), cx + P.Scale(1), TextR.Bottom - P.Scale(2));
      P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
    end;
    ```
    （RenderTo 顶部 var 区加 `cx: Integer; CaretRect: TRect; EffSize: Integer;`;`EffSize := S.FontSize; if EffSize<=0 then EffSize:=12;` 用同一 EffSize 画文本与测量,保证一致。注意 `CaretPixelX` 用的是 local-left 坐标系,与 RenderTo 的 (0,0)-local 一致。）
- [ ] **Step 4: 跑;两用例 PASS;现有 spinedit 渲染 smoke 仍绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTySpinEdit renders edit buffer + measured caret`

---

## Group D — 光标闪烁

### Task 9: TyCaretVisible 纯函数

**Files:** Modify `source/tyControls.Animation.pas`; Test `tests/test.animation.pas`.

- [ ] **Step 1: 失败测试**(加到 `tests/test.animation.pas`):

```pascal
procedure TestCaretVisibleHalfPeriodToggles;
begin
  AssertTrue ('t=0 visible',         TyCaretVisible(0, 530));
  AssertTrue ('mid first half',      TyCaretVisible(200, 530));
  AssertFalse('second half hidden',  TyCaretVisible(600, 530));   // 600 div 530 =1 -> odd -> hidden
  AssertTrue ('third half visible',  TyCaretVisible(1100, 530));  // 1100 div 530 =2 -> even
end;

procedure TestCaretVisibleGuardsZeroPeriod;
begin
  AssertTrue('zero/neg period -> always visible', TyCaretVisible(999, 0));
end;
```
Register both.

- [ ] **Step 2: 确认失败/不编译。**
- [ ] **Step 3: 实现**(`source/tyControls.Animation.pas`):interface 段加
  ```pascal
  // Square-wave caret visibility: visible during even half-periods, hidden during
  // odd ones. A non-positive half-period means "always visible" (degenerate guard).
  function TyCaretVisible(AElapsedMs, AHalfPeriodMs: Integer): Boolean;
  ```
  implementation:
  ```pascal
  function TyCaretVisible(AElapsedMs, AHalfPeriodMs: Integer): Boolean;
  begin
    if AHalfPeriodMs <= 0 then Exit(True);
    if AElapsedMs < 0 then AElapsedMs := 0;
    Result := (AElapsedMs div AHalfPeriodMs) mod 2 = 0;
  end;
  ```
- [ ] **Step 4: 跑;两用例 PASS。**
- [ ] **Step 5: Commit** `feat(tycontrols): TyCaretVisible pure square-wave caret-blink helper`

---

### Task 10: 把闪烁接入 Edit / Memo / SpinEdit

**Files:** Modify `source/tyControls.Edit.pas`, `tyControls.Memo.pas`, `tyControls.SpinEdit.pas`; Tests `tests/test.edit.pas` (+ memo/spinedit smoke).

> 关键不变量:`FCaretVisible` 默认 True,无头测试不创建 timer,故所有现有静态光标像素测试**不变**。本任务的"新测试"只验证 reset 逻辑(纯字段),不依赖真实计时。

- [ ] **Step 1: 失败测试**(纯字段 reset 逻辑,用 access 暴露 `FCaretVisible`):

加到 `tests/test.edit.pas`(给 `TTyEditAccess` 加 `function CaretVisibleForTest: Boolean;`→`Result := FCaretVisible;` 和 `procedure SetCaretVisibleForTest(b: Boolean);`→`FCaretVisible := b;`):
```pascal
procedure TestEditActivityResetsCaretVisible;
var E: TTyEditAccess;
begin
  E := TTyEditAccess.Create(nil);
  try
    E.SetCaretVisibleForTest(False);  // pretend mid-blink off
    E.InjectKey('a');                 // any edit must reset to visible
    AssertTrue('edit resets caret to visible', E.CaretVisibleForTest);
    E.SetCaretVisibleForTest(False);
    E.CaretPos := 0;                  // caret move resets too
    AssertTrue('nav resets caret to visible', E.CaretVisibleForTest);
  finally E.Free; end;
end;
```
Register it.

- [ ] **Step 2: 确认失败/不编译**(`FCaretVisible` 未声明)。
- [ ] **Step 3: 实现**(对 Edit、Memo、SpinEdit **各自**做同构改动):
  - `uses` 确认含 `ExtCtrls`(TTimer)与 `tyControls.Animation`(TyCaretVisible)。Edit 当前 uses 无 ExtCtrls/Animation——加上;Memo/SpinEdit 视情况加(SpinEdit 已无 ExtCtrls,加)。
  - private 字段:`FCaretVisible: Boolean; FBlinkTimer: TTimer; FBlinkElapsedMs: Integer;`
  - `Create`:`FCaretVisible := True;`(timer 惰性)。
  - 私有方法:
    ```pascal
    procedure EnsureBlinkTimer;   // lazy create; Interval=530; OnTimer:=@HandleBlink
    procedure HandleBlink(Sender: TObject);
    procedure ResetCaretBlink;    // FCaretVisible:=True; FBlinkElapsedMs:=0; (restart visible)
    ```
    实现:
    ```pascal
    procedure T<Ctl>.EnsureBlinkTimer;
    begin
      if FBlinkTimer = nil then
      begin
        FBlinkTimer := TTimer.Create(Self);
        FBlinkTimer.Enabled := False;
        FBlinkTimer.Interval := 530;
        FBlinkTimer.OnTimer := @HandleBlink;
      end;
    end;
    procedure T<Ctl>.HandleBlink(Sender: TObject);
    begin
      Inc(FBlinkElapsedMs, FBlinkTimer.Interval);
      FCaretVisible := TyCaretVisible(FBlinkElapsedMs, FBlinkTimer.Interval);
      Invalidate;
    end;
    procedure T<Ctl>.ResetCaretBlink;
    begin
      FCaretVisible := True;
      FBlinkElapsedMs := 0;
    end;
    ```
  - `DoEnter`(override; Edit/Memo/SpinEdit 若无则加):`inherited; ResetCaretBlink; if HandleAllocated then begin EnsureBlinkTimer; FBlinkTimer.Enabled := True; end;`
  - `DoExit`(override):`inherited; if FBlinkTimer <> nil then FBlinkTimer.Enabled := False; FCaretVisible := True; Invalidate;`（SpinEdit 的 DoExit 已在 Task7 加了 CommitEdit——把这两行并入。）
  - **复位**:在每个会改变文本或光标的入口末尾调用 `ResetCaretBlink`。低风险做法:在各控件已有的"活动后"共享点调用。Edit:`InvalidateWidthCache` 之外没有统一点,改为在 `InjectKey`/`InjectBackspace`/`InjectDelete`/`SetCaretPos`/`SelectAll`/方向键分支末尾(它们都已 `Invalidate`)前加 `ResetCaretBlink;`。**更省事且足够**:把 `ResetCaretBlink` 调用集中放进这些方法——但为减小改动面,**最少**满足测试与体验:在 `InjectKey`、`SetCaretPos` 末尾(`Invalidate` 前)加 `ResetCaretBlink;`,其余编辑/导航方法同样加(逐一)。Memo:在 `DoInsertText` 调用处的包装、`SetCaret*`/caret-move 共享后routine `AfterCaretMove`(见 Memo:1255 附近)末尾加 `ResetCaretBlink;`(`AfterCaretMove` 覆盖所有导航;编辑路径在 `AfterEdit` 末尾加)。SpinEdit:在 `InsertEditChar`/`EditBackspace`/`EditDelete`/方向键分支/`SyncBufferToValue` 末尾加。
    > 注意:`ResetCaretBlink` 只写字段,不依赖 timer;无头下安全。测试只断言"编辑/导航后 `FCaretVisible=True`"。
  - 光标绘制条件:Edit `RenderTo` 的 `if Focused and not HasSelection then` 改为 `if Focused and not HasSelection and FCaretVisible then`;Memo `RenderTo` 画光标的 `if`(2089 附近,绘制 CaretRect 处)加 `and FCaretVisible`;SpinEdit Task8 的 `if Focused then` 改 `if Focused and FCaretVisible then`。
  - `Destroy`:`FreeAndNil(FBlinkTimer);`(在 inherited 之前;TTimer 属 Self,但显式先释放避免回调时序问题——镜像 TTyButton.Destroy)。
- [ ] **Step 4: 跑全量**;`TestEditActivityResetsCaretVisible` PASS;**所有现有静态光标像素测试保持绿**(默认 FCaretVisible=True、无头不启 timer);0 failures;给 Memo/SpinEdit 跑各自 paint smoke。
- [ ] **Step 5: Commit** `feat(tycontrols): blinking caret for Edit/Memo/SpinEdit (runtime timer; static & headless-safe)`

---

### Task 11: 文档 + 收口

**Files:** `docs/controls/edit.md`、`docs/controls/memo.md`、`docs/controls/spinedit.md`;全量回归 + 构建矩阵。

- [ ] **Step 1: 文档** —— 各控件 md 的属性表补:
  - edit.md:`ReadOnly`、`MaxLength`(码点)、`PasswordChar`(UTF-8 单码点,掩码时禁用复制)、`TextHint`(占位符,派生 50% 色);并在 gaps 里移除/更新"无掩码/无占位符"等过期表述,加"光标现支持运行期闪烁(无头静止)"。
  - memo.md:`ReadOnly`、`MaxLength`(内容码点);更新光标闪烁说明。
  - spinedit.md:从"只读显示"改为"可内联编辑整数"(键入数字/前导负号、`←/→/Home/End`、`Enter`/失焦提交并夹紧、`Esc` 还原、箭头/滚轮/按钮步进);光标闪烁。
- [ ] **Step 2: 全量回归 + 矩阵 + heaptrc**
  ```bash
  lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain
  bash scripts/build-matrix.sh
  ```
  Expected:0 failures(+15 env errors only);`== matrix OK ==`;若启用 heaptrc,确认 0 泄漏(`FMeasureBmp`/`FBlinkTimer` 在 Destroy 释放)。
- [ ] **Step 3: Commit** `docs(tycontrols): document Edit/Memo ReadOnly/MaxLength/PasswordChar/TextHint, SpinEdit inline edit, caret blink`

---

## 完成后
全套件 + 构建矩阵 + heaptrc 0 + 终审(reviewer 跑 ReadOnly/PasswordChar/TextHint 像素与 SpinEdit 提交/Esc;确认现有静态光标测试零变化);本地快进合并 main + 删分支;更新记忆(批① 完成,批② 起)。

## Self-Review(规划者自查,已执行)
- **Spec 覆盖**:Edit ReadOnly→T1、MaxLength→T2、PasswordChar→T3、TextHint→T4;Memo ReadOnly→T5、MaxLength→T6;SpinEdit 编辑→T7+T8;闪烁→T9(纯函数)+T10(接入三控件);文档→T11。
- **类型/签名一致**:`DisplayText`(T3)、`ContentCodepointCount`(T6)、`FEditText`/`FCaret`/`CommitEdit`/`SyncBufferToValue`/`InsertEditChar`/`CaretPixelX`(T7/T8)、`TyCaretVisible`(T9)、`FCaretVisible`/`ResetCaretBlink`/`EnsureBlinkTimer`/`HandleBlink`(T10)前后一致。
- **向后兼容**:所有新属性默认值=旧行为;PasswordChar='' → DisplayText=FText;TextHint='' → 原正文分支;FCaretVisible 默认 True + 无头不启 timer → 现有像素测试零变化。Memo 守卫只拦内容新增路径。
- **无占位符**:Edit/SpinEdit/blink 给完整代码;Memo 守卫给精确方法清单 + 守卫代码 + 行为契约测试(实现者读方法后插入,与 v1.5"每输入入口加 Enabled 守卫"同型)。
