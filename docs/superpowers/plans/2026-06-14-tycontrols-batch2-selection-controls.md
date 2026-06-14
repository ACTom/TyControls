# TyControls 批② 选择类 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `TTyRadioButton` 加 `GroupIndex`;`TTyComboBox`(仍只读下拉)加关闭态键盘选择(↑↓/Home/End/Alt↓/F4)+ type-ahead;`TTyListBox` 加 `MultiSelect` + `Selected[]`/`SelCount`/`ClearSelection`/`SelectAll` + 鼠标(plain/Ctrl/Shift)与键盘(PageUp/Down/Home/End/Shift-extend/Space)多选 + 翻页。

**Architecture:** 纯叠加、向后兼容。RadioButton 的 `UncheckSiblings` 按 `GroupIndex` 过滤。ComboBox 在 `KeyDown`/`UTF8KeyPress` 加分支,type-ahead 用纯函数 `TyComboTypeAheadMatch` + `QWord` tick 超时。ListBox 选择集用托管 `FSelected: array of Boolean`(随 Items 重置),`FItemIndex` 在多选下兼作焦点/锚点,`Selected[]`/`SelCount` 在两种模式下统一可读。

**Tech Stack:** Free Pascal / Lazarus LCL;FPCUnit;PPI=96;无头键盘/鼠标注入。

**约定:** 运行测试 `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`。基线 **0 failures + 15 个无头 win32(error 1407)环境错误(非回归,忽略)**。新增测试加在已注册单元里。提交 `feat(tycontrols): …`。**勿动 `examples/demo/demo.lpi` 与 `examples/demo/mainform.lfm`**(用户未提交改动;每任务只 stage 自己的文件)。

---

## File Structure
- `source/tyControls.CheckBox.pas` — `TTyRadioButton` 加 `FGroupIndex` + published `GroupIndex`;`UncheckSiblings` 按 GroupIndex 过滤。
- `source/tyControls.ComboBox.pas` — `KeyDown` 加关闭态导航;新增 `UTF8KeyPress` type-ahead + 字段 `FTypeAhead`/`FTypeAheadTick`;新增独立纯函数 `TyComboTypeAheadMatch`(unit 级,导出)。
- `source/tyControls.ListBox.pas` — `FMultiSelect`/`FSelected: array of Boolean`/`FSelAnchor`;published `MultiSelect`;`Selected[]`/`SelCount`/`ClearSelection`/`SelectAll`;`MouseDown`/`KeyDown` 多选 + 翻页;`RenderTo` 行状态读 `FSelected`。
- Tests:`tests/test.radiobutton.pas`(有 `TTyRadioButtonAccess`)、`tests/test.controls.combobox.pas`(有 `TComboAccess`/`FCombo`)、`tests/test.listbox.pas`(有 `TTyListBoxTest`/`TListBoxAccess`)。
- Docs:`docs/controls/radiobutton.md`、`combobox.md`、`listbox.md`。

---

## Task 1: TTyRadioButton.GroupIndex

**Files:** Modify `source/tyControls.CheckBox.pas`;Test `tests/test.radiobutton.pas`.

- [ ] **Step 1: 失败测试**(加到 `TRadioButtonTest` published + impl):
```pascal
procedure TestGroupIndexSeparatesGroups;
var F: TCustomForm; A, B, C, D: TTyRadioButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    // group 0: A,B ; group 1: C,D ; all under the SAME parent F
    A := TTyRadioButton.Create(F); A.Parent := F; A.GroupIndex := 0;
    B := TTyRadioButton.Create(F); B.Parent := F; B.GroupIndex := 0;
    C := TTyRadioButton.Create(F); C.Parent := F; C.GroupIndex := 1;
    D := TTyRadioButton.Create(F); D.Parent := F; D.GroupIndex := 1;
    A.Click; C.Click;
    AssertTrue('A checked', A.Checked);
    AssertTrue('C checked (other group)', C.Checked);
    B.Click;
    AssertFalse('A cleared by B (same group)', A.Checked);
    AssertTrue('C still checked (different group)', C.Checked);
    D.Click;
    AssertFalse('C cleared by D (same group)', C.Checked);
    AssertTrue('B still checked (different group)', B.Checked);
  finally F.Free; end;
end;
```
Register it.

- [ ] **Step 2: 确认失败/不编译**(`GroupIndex` 未声明)。`lazbuild tests/tytests.lpi`。
- [ ] **Step 3: 实现**(`source/tyControls.CheckBox.pas`,`TTyRadioButton`):
  - private `FGroupIndex: Integer;`(`Create` 已无需初始化,默认 0;published `default 0` 即可)。setter 可省(纯数据,改不影响已选态):直接 `property GroupIndex: Integer read FGroupIndex write FGroupIndex default 0;` 放 published。
  - `UncheckSiblings` 的循环条件由 `(Sib <> Self) and (Sib is TTyRadioButton)` 改为同时要求同 GroupIndex:
    ```pascal
    if (Sib <> Self) and (Sib is TTyRadioButton)
       and (TTyRadioButton(Sib).GroupIndex = FGroupIndex) then
      TTyRadioButton(Sib).SetChecked(False);
    ```
- [ ] **Step 4: 跑;新用例 PASS;现有 radiobutton 测试(`TestClickClearsGroup` 等,GroupIndex 默认都 0 → 仍互斥)全绿。**
- [ ] **Step 5: Commit** `git add source/tyControls.CheckBox.pas tests/test.radiobutton.pas && git commit -m "feat(tycontrols): TTyRadioButton.GroupIndex (per-group mutual exclusion within one parent)"`

---

## Task 2: TTyComboBox 关闭态键盘选择

**Files:** Modify `source/tyControls.ComboBox.pas`;Test `tests/test.controls.combobox.pas`.

- [ ] **Step 1: 失败测试** —— 给 `TComboAccess` 加 `procedure DoKeyDown(var Key: Word; Shift: TShiftState); begin KeyDown(Key, Shift); end;`(public)。`uses` 确认含 `LCLType`(VK_*)。加测试(`FCombo` 在 SetUp 建;读该文件确认 SetUp 给 FCombo 加了若干 Items;若没有,测试里自行 `FCombo.Items.Add`)。
```pascal
procedure TestArrowKeysChangeSelectionClosed;
var K: Word;
begin
  FCombo.Items.Clear;
  FCombo.Items.Add('Alpha'); FCombo.Items.Add('Beta'); FCombo.Items.Add('Gamma');
  FCombo.ItemIndex := 0;
  K := VK_DOWN; FCombo.DoKeyDown(K, []);
  AssertEquals('down selects next', 1, FCombo.ItemIndex);
  AssertFalse('did not open dropdown', FCombo.DroppedDown);
  K := VK_DOWN; FCombo.DoKeyDown(K, []);
  AssertEquals('down again', 2, FCombo.ItemIndex);
  K := VK_DOWN; FCombo.DoKeyDown(K, []);
  AssertEquals('down clamps at last', 2, FCombo.ItemIndex);
  K := VK_UP; FCombo.DoKeyDown(K, []);
  AssertEquals('up selects prev', 1, FCombo.ItemIndex);
  K := VK_HOME; FCombo.DoKeyDown(K, []);
  AssertEquals('home -> first', 0, FCombo.ItemIndex);
  K := VK_END; FCombo.DoKeyDown(K, []);
  AssertEquals('end -> last', 2, FCombo.ItemIndex);
end;

procedure TestAltDownOpensDropdown;
var K: Word;
begin
  FCombo.Items.Clear; FCombo.Items.Add('A'); FCombo.Items.Add('B');
  AssertFalse('starts closed', FCombo.DroppedDown);
  K := VK_DOWN; FCombo.DoKeyDown(K, [ssAlt]);
  AssertTrue('Alt+Down opens dropdown', FCombo.DroppedDown);
end;
```
Register both.

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现** —— `source/tyControls.ComboBox.pas` `KeyDown`,在现有 Esc 分支之后扩展。把方法改为:
```pascal
procedure TTyComboBox.KeyDown(var Key: Word; Shift: TShiftState);
var Cnt: Integer;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and DroppedDown then
  begin
    CloseUp; Key := 0; Exit;
  end;
  // Alt+Down or F4 toggles the dropdown.
  if ((Key = VK_DOWN) and (ssAlt in Shift)) or (Key = VK_F4) then
  begin
    if DroppedDown then CloseUp else DropDown;
    Key := 0; Exit;
  end;
  Cnt := FItems.Count;
  if Cnt = 0 then Exit;
  case Key of
    VK_DOWN:
      begin
        if FItemIndex < 0 then SelectItem(0)
        else if FItemIndex < Cnt - 1 then SelectItem(FItemIndex + 1);
        Key := 0;
      end;
    VK_UP:
      begin
        if FItemIndex < 0 then SelectItem(0)
        else if FItemIndex > 0 then SelectItem(FItemIndex - 1);
        Key := 0;
      end;
    VK_HOME: begin SelectItem(0); Key := 0; end;
    VK_END:  begin SelectItem(Cnt - 1); Key := 0; end;
  end;
end;
```
（注意:`Alt+Down` 分支必须在普通 `VK_DOWN` 之前判定,否则会被吞成选下一项。)
- [ ] **Step 4: 跑;两用例 PASS;现有 combobox 测试全绿(尤其 `TestClickDoesNotCycleItems`/下拉相关)。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyComboBox closed-state keyboard selection (arrows/Home/End, Alt+Down/F4 open)`

---

## Task 3: TTyComboBox type-ahead

**Files:** Modify `source/tyControls.ComboBox.pas`;Test `tests/test.controls.combobox.pas`.

- [ ] **Step 1: 失败测试**(纯函数 + 集成):
```pascal
procedure TestTypeAheadMatchPureFunction;
var L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('Apple'); L.Add('Banana'); L.Add('Avocado'); L.Add('Cherry');
    AssertEquals('from -1, prefix a -> Apple(0)', 0, TyComboTypeAheadMatch(L, -1, 'a'));
    AssertEquals('from 0, prefix a -> Avocado(2)', 2, TyComboTypeAheadMatch(L, 0, 'a'));
    AssertEquals('wrap: from 2, prefix a -> Apple(0)', 0, TyComboTypeAheadMatch(L, 2, 'a'));
    AssertEquals('prefix av -> Avocado(2)', 2, TyComboTypeAheadMatch(L, -1, 'av'));
    AssertEquals('no match -> -1', -1, TyComboTypeAheadMatch(L, -1, 'z'));
    AssertEquals('case-insensitive', 1, TyComboTypeAheadMatch(L, -1, 'BAN'));
  finally L.Free; end;
end;

procedure TestTypeAheadSelectsViaKeypress;
var ch: TUTF8Char;
begin
  FCombo.Items.Clear;
  FCombo.Items.Add('Apple'); FCombo.Items.Add('Banana'); FCombo.Items.Add('Cherry');
  FCombo.ItemIndex := -1;
  ch := 'b'; FCombo.DoTypeChar(ch);
  AssertEquals('typing b selects Banana', 1, FCombo.ItemIndex);
end;
```
给 `TComboAccess` 加 `procedure DoTypeChar(const C: TUTF8Char); var k: TUTF8Char; begin k := C; UTF8KeyPress(k); end;`(public)。`uses` 加 `LazUTF8` 若 type-ahead 测试需要(此处不需要)。Register 两个。

- [ ] **Step 2: 确认失败/不编译**(`TyComboTypeAheadMatch`/`DoTypeChar` 未声明)。
- [ ] **Step 3: 实现**(`source/tyControls.ComboBox.pas`):
  - interface 段 unit 级导出:
    ```pascal
    function TyComboTypeAheadMatch(AItems: TStrings; AStart: Integer; const APrefix: string): Integer;
    ```
    implementation:
    ```pascal
    function TyComboTypeAheadMatch(AItems: TStrings; AStart: Integer; const APrefix: string): Integer;
    var n, i, idx: Integer; pfx: string;
    begin
      Result := -1;
      n := AItems.Count;
      if (n = 0) or (APrefix = '') then Exit;
      pfx := LowerCase(APrefix);
      for i := 1 to n do
      begin
        idx := (AStart + i) mod n;     // start searching AFTER AStart, wrapping
        if idx < 0 then idx := idx + n;
        if Copy(LowerCase(AItems[idx]), 1, Length(pfx)) = pfx then
          Exit(idx);
      end;
    end;
    ```
  - private 字段 `FTypeAhead: string; FTypeAheadTick: QWord;`(`QWord` 与现有 `FCloseUpTick: QWord` 同型;`GetTickCount64` 已用于 ComboBox)。
  - 新增 `UTF8KeyPress` override:
    ```pascal
    procedure TTyComboBox.UTF8KeyPress(var UTF8Key: TUTF8Char);
    var nowTick: QWord; hit: Integer;
    begin
      if not Enabled then Exit;
      inherited UTF8KeyPress(UTF8Key);
      if (UTF8Key = '') or (UTF8Key[1] < #32) then Exit;
      nowTick := GetTickCount64;
      if nowTick - FTypeAheadTick > 600 then FTypeAhead := '';   // restart after pause
      FTypeAheadTick := nowTick;
      FTypeAhead := FTypeAhead + UTF8Key;
      hit := TyComboTypeAheadMatch(FItems, FItemIndex, FTypeAhead);
      if hit >= 0 then SelectItem(hit);
    end;
    ```
    在 protected 段声明 `procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;`。
    > 注意:`TyComboTypeAheadMatch` 从 `FItemIndex` 之后找,这样连按同一字母会在多个匹配项间循环(标准 type-ahead);累积前缀(如 'av')时从当前项后找仍能命中 'Avocado'(若当前不是它)。测试 `TestTypeAheadSelectsViaKeypress` 单字符 'b' 从 -1 起命中 Banana。
- [ ] **Step 4: 跑;两用例 PASS;现有 combobox 测试全绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyComboBox type-ahead (prefix match with timeout) + TyComboTypeAheadMatch pure fn`

---

## Task 4: TTyListBox 多选地基(MultiSelect + Selected[]/SelCount + 渲染)

**Files:** Modify `source/tyControls.ListBox.pas`;Test `tests/test.listbox.pas`.

- [ ] **Step 1: 失败测试** —— 给 `TListBoxAccess` 加 `RenderTo` 已有;无需新 access(用公开 API)。加测试(`TTyListBoxTest` 有 `FList`/`FForm` SetUp;读其 SetUp 确认 FList 已建并可能已填 Items;测试里自行设 Items)。
```pascal
procedure TestMultiSelectSelectedAndSelCount;
begin
  FList.Items.Clear;
  FList.Items.Add('a'); FList.Items.Add('b'); FList.Items.Add('c'); FList.Items.Add('d');
  FList.MultiSelect := True;
  AssertEquals('empty selcount', 0, FList.SelCount);
  FList.Selected[1] := True;
  FList.Selected[3] := True;
  AssertTrue('1 selected', FList.Selected[1]);
  AssertFalse('0 not selected', FList.Selected[0]);
  AssertEquals('selcount 2', 2, FList.SelCount);
  FList.Selected[1] := False;
  AssertEquals('selcount 1', 1, FList.SelCount);
  FList.SelectAll;
  AssertEquals('select all', 4, FList.SelCount);
  FList.ClearSelection;
  AssertEquals('cleared', 0, FList.SelCount);
end;

procedure TestSingleSelectSelectedReflectsItemIndex;
begin
  FList.Items.Clear; FList.Items.Add('a'); FList.Items.Add('b');
  FList.MultiSelect := False;
  FList.ItemIndex := 1;
  AssertTrue('Selected[1] true in single', FList.Selected[1]);
  AssertFalse('Selected[0] false', FList.Selected[0]);
  AssertEquals('selcount 1 in single', 1, FList.SelCount);
  FList.SelectAll;   // no-op in single mode
  AssertEquals('SelectAll no-op single', 1, FList.SelCount);
end;
```
Register both. (Also add a render test that a multi-selected row paints the active style — mirror existing `TestSelectedRowRendersActiveStyle` but set MultiSelect + Selected[].)

- [ ] **Step 2: 确认失败/不编译**(`MultiSelect`/`Selected`/`SelCount` 未声明)。
- [ ] **Step 3: 实现**(`source/tyControls.ListBox.pas`):
  - private 字段:`FMultiSelect: Boolean; FSelected: array of Boolean; FSelAnchor: Integer;`(`Create`:`FSelAnchor := -1;`)。
  - 私有 helper:
    ```pascal
    procedure TTyListBox.EnsureSelectedLen;
    begin
      if Length(FSelected) <> FItems.Count then
        SetLength(FSelected, FItems.Count);   // new slots default False
    end;
    function TTyListBox.GetSelected(AIndex: Integer): Boolean;
    begin
      if (AIndex < 0) or (AIndex >= FItems.Count) then Exit(False);
      if FMultiSelect then
      begin
        EnsureSelectedLen;
        Result := FSelected[AIndex];
      end
      else
        Result := (AIndex = FItemIndex);
    end;
    procedure TTyListBox.SetSelected(AIndex: Integer; AValue: Boolean);
    begin
      if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;
      if FMultiSelect then
      begin
        EnsureSelectedLen;
        if FSelected[AIndex] = AValue then Exit;
        FSelected[AIndex] := AValue;
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end
      else if AValue then
        SelectItem(AIndex);   // single mode: setting True selects it
    end;
    function TTyListBox.SelCount: Integer;
    var i: Integer;
    begin
      if FMultiSelect then
      begin
        EnsureSelectedLen;
        Result := 0;
        for i := 0 to High(FSelected) do if FSelected[i] then Inc(Result);
      end
      else if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then Result := 1
      else Result := 0;
    end;
    procedure TTyListBox.ClearSelection;
    var i: Integer;
    begin
      if FMultiSelect then
      begin
        EnsureSelectedLen;
        for i := 0 to High(FSelected) do FSelected[i] := False;
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;
      // single mode: ClearSelection leaves FItemIndex (spec: ClearSelection is a multi-select op)
    end;
    procedure TTyListBox.SelectAll;
    var i: Integer;
    begin
      if not FMultiSelect then Exit;   // no-op in single mode
      EnsureSelectedLen;
      for i := 0 to High(FSelected) do FSelected[i] := True;
      Invalidate;
      if Assigned(FOnChange) then FOnChange(Self);
    end;
    procedure TTyListBox.SetMultiSelect(AValue: Boolean);
    begin
      if FMultiSelect = AValue then Exit;
      FMultiSelect := AValue;
      EnsureSelectedLen;
      Invalidate;
    end;
    ```
    在合适的可见区声明这些(`GetSelected/SetSelected/SetMultiSelect/EnsureSelectedLen` private;`SelCount/ClearSelection/SelectAll` public)。
  - published `property MultiSelect: Boolean read FMultiSelect write SetMultiSelect default False;`
  - public `property Selected[AIndex: Integer]: Boolean read GetSelected write SetSelected;`(数组属性放 public)。
  - public `function SelCount: Integer; procedure ClearSelection; procedure SelectAll;`
  - `SetItems`:在末尾(`Invalidate` 前)加 `SetLength(FSelected, FItems.Count);`(重置选择,越界自动清)。
  - `RenderTo`:行状态判定改为:
    ```pascal
    ItemStates := [];
    if (FMultiSelect and GetSelected(i)) or ((not FMultiSelect) and (i = FItemIndex)) then
      Include(ItemStates, tysActive)
    else if i = FHoverRow then
      Include(ItemStates, tysHover)
    else
      Include(ItemStates, tysNormal);
    ```
- [ ] **Step 4: 跑;新用例 PASS;现有 listbox 单选测试全绿(MultiSelect 默认 False)。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyListBox MultiSelect foundation (Selected[]/SelCount/ClearSelection/SelectAll + render)`

---

## Task 5: TTyListBox 鼠标多选(plain/Ctrl/Shift + 锚点)

**Files:** Modify `source/tyControls.ListBox.pas`;Test `tests/test.listbox.pas`.

- [ ] **Step 1: 失败测试** —— 给 `TListBoxAccess` 加 `procedure DoMouseDown(Shift: TShiftState; X, Y: Integer); begin MouseDown(mbLeft, Shift, X, Y); end;`(public)。多选下点击行 r 用 `Y := r*ItemHeight + 1`(默认 ItemHeight=24,PPI 取 Font.PixelsPerInch=96 → ScaledItemHeight=24)。测试里把 `FList` 强转 `TListBoxAccess`(或新建一个)。
```pascal
procedure TestMultiSelectMouseClicks;
var LA: TListBoxAccess;
begin
  LA := TListBoxAccess.Create(FForm); LA.Parent := FForm;
  LA.Font.PixelsPerInch := 96; LA.SetBounds(0,0,160,240);
  LA.Items.Add('0'); LA.Items.Add('1'); LA.Items.Add('2'); LA.Items.Add('3'); LA.Items.Add('4');
  LA.MultiSelect := True;
  LA.DoMouseDown([], 5, 1*24+2);                 // plain click row 1
  AssertEquals('plain click selects 1', 1, LA.SelCount);
  AssertTrue('row1 selected', LA.Selected[1]);
  LA.DoMouseDown([ssCtrl], 5, 3*24+2);           // ctrl-click row 3 -> add
  AssertEquals('ctrl adds -> 2', 2, LA.SelCount);
  AssertTrue('row3 selected', LA.Selected[3]);
  LA.DoMouseDown([ssShift], 5, 4*24+2);          // shift-click row 4 -> range anchor(3)..4
  AssertTrue('row3..4 selected', LA.Selected[3] and LA.Selected[4]);
  AssertFalse('row1 cleared by shift-range', LA.Selected[1]);
  LA.DoMouseDown([], 5, 0*24+2);                 // plain click row 0 -> only 0
  AssertEquals('plain resets to 1', 1, LA.SelCount);
  AssertTrue('row0', LA.Selected[0]);
end;
```
Register it.

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现** —— `MouseDown`,在 `Button = mbLeft` 分支内,把 `if (Row >= 0) and (Row < FItems.Count) then SelectItem(Row);` 替换为多选感知逻辑:
```pascal
    if (Row >= 0) and (Row < FItems.Count) then
    begin
      if not FMultiSelect then
        SelectItem(Row)
      else
      begin
        EnsureSelectedLen;
        if ssShift in Shift then
        begin
          ApplyRangeSelection(FSelAnchorOr(Row), Row);   // see helper below
          FItemIndex := Row;
        end
        else if ssCtrl in Shift then
        begin
          FSelected[Row] := not FSelected[Row];
          FItemIndex := Row; FSelAnchor := Row;
          Invalidate; DoChangeSel;
        end
        else
        begin
          ClearAllBits;
          FSelected[Row] := True;
          FItemIndex := Row; FSelAnchor := Row;
          Invalidate; DoChangeSel;
        end;
      end;
    end;
```
  新增私有 helper:
```pascal
procedure TTyListBox.DoChangeSel;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;
procedure TTyListBox.ClearAllBits;
var i: Integer;
begin
  EnsureSelectedLen;
  for i := 0 to High(FSelected) do FSelected[i] := False;
end;
function TTyListBox.FSelAnchorOr(ADefault: Integer): Integer;
begin
  if (FSelAnchor >= 0) and (FSelAnchor < FItems.Count) then Result := FSelAnchor
  else Result := ADefault;
end;
procedure TTyListBox.ApplyRangeSelection(ALo, AHi: Integer);
var i, t: Integer;
begin
  EnsureSelectedLen;
  if ALo > AHi then begin t := ALo; ALo := AHi; AHi := t; end;
  ClearAllBits;
  for i := ALo to AHi do
    if (i >= 0) and (i < FItems.Count) then FSelected[i] := True;
  Invalidate;
  DoChangeSel;
end;
```
  （`EnsureSelectionVisible` 已以 `FItemIndex` 为准,多选移动焦点后仍能滚动;`MouseDown` 后调用 `EnsureSelectionVisible; UpdateScrollBar;` 可选,plain/ctrl/shift 各分支末尾统一加更稳——但点击在可见区内,通常不需要。保留现状即可。）
- [ ] **Step 4: 跑;新用例 PASS;现有单选 MouseDown 行为不变(MultiSelect=False 走 SelectItem)。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyListBox mouse multi-select (plain/Ctrl/Shift + anchor)`

---

## Task 6: TTyListBox 键盘(翻页 + 多选扩展/Space)

**Files:** Modify `source/tyControls.ListBox.pas`;Test `tests/test.listbox.pas`.

- [ ] **Step 1: 失败测试** —— 给 `TListBoxAccess` 加 `procedure DoKeyDown(Key: Word; Shift: TShiftState); begin KeyDown(Key, Shift); end;`(public)。
```pascal
procedure TestPageKeysSingleSelect;
var LA: TListBoxAccess; i: Integer;
begin
  LA := TListBoxAccess.Create(FForm); LA.Parent := FForm;
  LA.Font.PixelsPerInch := 96; LA.SetBounds(0,0,160,120);  // 120/24 = 5 visible rows
  for i := 0 to 19 do LA.Items.Add(IntToStr(i));
  LA.MultiSelect := False; LA.ItemIndex := 0;
  LA.DoKeyDown(VK_NEXT, []);                 // PageDown
  AssertEquals('pagedown +VisibleRows', LA.VisibleRows, LA.ItemIndex);
  LA.DoKeyDown(VK_PRIOR, []);                // PageUp
  AssertEquals('pageup back to 0', 0, LA.ItemIndex);
end;

// Note: the anchor is internal state, so seed it with a Task-5 `DoMouseDown` click
// (anchor=focus=1) before the Shift+Down extend.
procedure TestMultiSelectShiftDownExtends;
var LA: TListBoxAccess;
begin
  LA := TListBoxAccess.Create(FForm); LA.Parent := FForm;
  LA.Font.PixelsPerInch := 96; LA.SetBounds(0,0,160,240);
  LA.Items.Add('0'); LA.Items.Add('1'); LA.Items.Add('2'); LA.Items.Add('3');
  LA.MultiSelect := True;
  LA.DoMouseDown([], 5, 1*24+2);             // anchor=focus=1, selects {1}
  LA.DoKeyDown(VK_DOWN, [ssShift]);          // extend 1..2
  AssertTrue('1..2 selected', LA.Selected[1] and LA.Selected[2]);
  AssertFalse('3 not', LA.Selected[3]);
  LA.DoKeyDown(VK_DOWN, [ssShift]);          // extend 1..3
  AssertTrue('1..3 selected', LA.Selected[1] and LA.Selected[2] and LA.Selected[3]);
  LA.DoKeyDown(VK_SPACE, []);                // toggle focus(3) off
  AssertFalse('focus 3 toggled off', LA.Selected[3]);
end;
```
Register `TestPageKeysSingleSelect` + `TestMultiSelectShiftDownExtends`.

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现** —— 重写 `KeyDown`。在 `inherited` 与 `Count=0` 守卫之后,先算 `NewFocus`,再按模式落选:
```pascal
procedure TTyListBox.KeyDown(var Key: Word; Shift: TShiftState);
var Count, NewFocus, VR: Integer; Extend: Boolean;
  procedure MoveFocus(ATarget: Integer);
  begin
    if ATarget < 0 then ATarget := 0;
    if ATarget > Count - 1 then ATarget := Count - 1;
    NewFocus := ATarget;
  end;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  Count := FItems.Count;
  if Count = 0 then Exit;
  VR := VisibleRows;
  Extend := (ssShift in Shift) and FMultiSelect;
  NewFocus := FItemIndex;

  case Key of
    VK_UP:    MoveFocus(IfThenIdx(FItemIndex <= 0, 0, FItemIndex - 1));
    VK_DOWN:  MoveFocus(IfThenIdx(FItemIndex < 0, 0, FItemIndex + 1));
    VK_PRIOR: MoveFocus(IfThenIdx(FItemIndex < 0, 0, FItemIndex - VR));   // PageUp
    VK_NEXT:  MoveFocus(IfThenIdx(FItemIndex < 0, 0, FItemIndex + VR));   // PageDown
    VK_HOME:  MoveFocus(0);
    VK_END:   MoveFocus(Count - 1);
    VK_SPACE:
      begin
        if FMultiSelect and (FItemIndex >= 0) then
        begin
          EnsureSelectedLen;
          FSelected[FItemIndex] := not FSelected[FItemIndex];
          FSelAnchor := FItemIndex;
          Invalidate; DoChangeSel;
        end;
        Key := 0; Exit;
      end;
  else
    Exit;   // key not handled
  end;
  Key := 0;

  if not FMultiSelect then
  begin
    SelectItem(NewFocus);   // single mode: existing behavior (also fires OnChange, scrolls)
    Exit;
  end;

  // Multi mode: move focus; extend range from anchor if Shift, else select-only.
  FItemIndex := NewFocus;
  EnsureSelectedLen;
  if Extend then
    ApplyRangeSelection(FSelAnchorOr(NewFocus), NewFocus)
  else
  begin
    ClearAllBits;
    FSelected[NewFocus] := True;
    FSelAnchor := NewFocus;
    Invalidate; DoChangeSel;
  end;
  EnsureSelectionVisible;
  UpdateScrollBar;
end;
```
  新增 unit-level 小助手(放 implementation 顶部):
```pascal
function IfThenIdx(ACond: Boolean; ATrue, AFalse: Integer): Integer;
begin if ACond then Result := ATrue else Result := AFalse; end;
```
  （`VK_PRIOR`=PageUp、`VK_NEXT`=PageDown,来自 LCLType。`ApplyRangeSelection`/`FSelAnchorOr`/`ClearAllBits`/`DoChangeSel` 来自 Task 5。单选下 PageUp/Down 经 `SelectItem(NewFocus)` 生效。)
- [ ] **Step 4: 跑;两用例 PASS;现有键盘测试(`TestKeyboardMovesSelection` 单选 Up/Down/Home/End)全绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyListBox keyboard paging + multi-select extend/toggle`

---

## Task 7: 文档 + 收口

**Files:** `docs/controls/radiobutton.md`、`combobox.md`、`listbox.md`;全量回归 + 构建矩阵。

- [ ] **Step 1: 文档**:
  - radiobutton.md:`GroupIndex`(同 Parent 内按 GroupIndex 细分单选组)。
  - combobox.md:关闭态键盘(↑↓/Home/End 选择、Alt+↓/F4 开下拉)、type-ahead(前缀跳选、~600ms 超时重置);注明仍是只读下拉(可编辑文本留后续)。
  - listbox.md:`MultiSelect`、`Selected[]`、`SelCount`、`ClearSelection`、`SelectAll`;鼠标 plain/Ctrl/Shift、键盘 PageUp/Down/Home/End/Shift-扩展/Space;`OnChange` 触发。
- [ ] **Step 2: 全量回归 + 矩阵**
  ```bash
  lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain
  bash scripts/build-matrix.sh
  ```
  Expected:0 failures(+15 env errors only);`== matrix OK ==`。
- [ ] **Step 3: Commit** `docs(tycontrols): document RadioButton GroupIndex, ComboBox keyboard/type-ahead, ListBox multi-select/paging`

---

## 完成后
全套件 + 构建矩阵 + heaptrc 0 + 终审(reviewer 跑 GroupIndex 分组、type-ahead、多选 click/键盘);本地快进合并 main + 删分支;更新记忆(批② 完成,批③ 起)。

## Self-Review(规划者自查,已执行)
- **Spec 覆盖**:RadioButton GroupIndex→T1;ComboBox 键盘→T2、type-ahead→T3;ListBox 多选地基→T4、鼠标→T5、键盘+翻页→T6;文档→T7。
- **类型/签名一致**:`GroupIndex`(T1);`TyComboTypeAheadMatch`/`FTypeAhead`/`FTypeAheadTick`(T2/T3);`FMultiSelect`/`FSelected`/`FSelAnchor`/`Selected[]`/`SelCount`/`ClearSelection`/`SelectAll`/`EnsureSelectedLen`/`GetSelected`/`SetSelected`(T4)、`ApplyRangeSelection`/`FSelAnchorOr`/`ClearAllBits`/`DoChangeSel`(T5)、`IfThenIdx`(T6)前后一致。
- **向后兼容**:GroupIndex 默认 0(现有 radio 仍互斥);ComboBox 新增键盘/type-ahead 叠加(Click/Esc/下拉不变);ListBox MultiSelect 默认 False → 单选行为逐字不变(render/MouseDown/KeyDown 均有 `if not FMultiSelect` 走原路径)。
- **无占位符**:各任务给完整代码;`array of Boolean` 托管无需 Destroy 释放。
