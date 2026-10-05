unit tbcoverage;
{ The coverage check: two lists that say how far a theme reaches.

  1. Styled here but not shown: the typeKeys the document has rules for that nothing in the
     preview draws -- a typo (TyButon), or a control the preview does not have.
  2. Shown but styled by nobody: the typeKeys the preview draws that neither the document
     nor the base theme has a rule for -- they keep the built-in look the control's code
     falls back to.

  "The document" is the entry text's own rules (the forgiving scan; what an @import brings
  in is not counted). "The base" is the base theme's rules (TyBuiltinThemeCss, parsed once;
  not the catalogue, which is generated from light.tycss for the documentation and leaves
  out the keys the base deliberately does not define).

  "The preview" is every control's own typeKey plus the typeKeys its code resolves for the
  parts it draws inside itself -- a page control's tabs (TyTab, in TabStrip.pas), a scroll
  bar's thumb (TyScrollThumb). The model has no hook that says which keys were resolved
  (ResolveStyle is not virtual, controls call it on the model directly), and the library is
  not changed for this, so the tool carries a table: unit -> the typeKeys its code names.
  A control's class and every ancestor class are looked up by unit (TObject.UnitName). A
  unit that names the keys of several controls counts them all as shown -- that can only
  hide an entry from list 1, never add a wrong one.

  TTbCoverageTests.TestThePartTableMatchesTheSources holds the table to the sources: every
  typeKey a unit names in a string literal (comments stripped) is in its row; what a row
  adds by hand (keys built by concatenation: ...Fill, ...Star) must be a catalogue key. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tbcssscan;

procedure TbDocTypeKeys(AScan: TTbCssScan; ADest: TStrings);
procedure TbBaseTypeKeys(ADest: TStrings);
function TbPartKeysOfUnit(const AUnit: string): string;       { comma list, '' when no row }
procedure TbPartKeysOfClass(AClass: TClass; ADest: TStrings); { its unit's row and every ancestor's }
function TbPartKeyUnits: TStringArray;                          { FOR THE TESTS }
{ A typeKey something in the library resolves: a catalogue key, a key of the base theme's
  rules, a key of the part table (every row), or one of APreview (nil: none). The coverage
  check marks the rest "not a known typeKey" -- most often a typo. The catalogue alone is
  not enough: it is generated from light.tycss and leaves out what the base deliberately
  does not define (TyFormSurface, TyGridPanel). }
function TbIsKnownTypeKey(const AKey: string; APreview: TStrings): Boolean;
{ ANotShown: in ADoc, not in APreview. ADefaultLook: in APreview, in neither ADoc nor ABase.
  Both cleared, then filled in alphabetical order. }
procedure TbCoverageLists(ADoc, APreview, ABase, ANotShown, ADefaultLook: TStrings);

implementation

uses
  tyControls.Css.Parser, tyControls.Css.Catalog, tyControls.DefaultTheme;

type
  TTbPartRow = record
    U: string;   { the unit, as TClass.UnitName gives it }
    K: string;   { the typeKeys its code resolves, comma separated }
  end;

const
  { Checked against the sources by TTbCoverageTests.TestThePartTableMatchesTheSources: every
    typeKey a unit names in a string literal is in its row; what a row adds by hand (keys
    built by concatenation) must be a catalogue typeKey. }
  cTbPartRows: array[0..51] of TTbPartRow = (
    (U: 'tyControls.ActivityIndicator'; K: 'TyActivityIndicator,TyActivityIndicatorFill'),
    (U: 'tyControls.Alert'; K: 'TyAlert,TyAlertClose'),
    (U: 'tyControls.Badge'; K: 'TyBadge'),
    (U: 'tyControls.Base'; K: 'TyForm'),
    (U: 'tyControls.Breadcrumb'; K: 'TyBreadcrumb,TyBreadcrumbItem'),
    (U: 'tyControls.Button'; K: 'TyBadge,TyButton'),
    (U: 'tyControls.Calendar'; K: 'TyCalendar,TyCalendarCell,TyCalendarTitle,TyCalendarWeekday'),
    (U: 'tyControls.Card'; K: 'TyCard,TyCardActions,TyCardHeader'),
    (U: 'tyControls.CheckBox'; K: 'TyCheckBox,TyRadioButton'),
    (U: 'tyControls.CheckListBox'; K: 'TyCheckBox'),
    (U: 'tyControls.CircularProgress'; K: 'TyCircularProgress,TyCircularProgressFill'),
    (U: 'tyControls.ComboBox'; K: 'TyComboBox,TyListBox,TyTextHint'),
    (U: 'tyControls.DateTimePicker'; K: 'TyCalendar,TyCheckBox,TyDateTimePicker,TyTextSelection'),
    (U: 'tyControls.Divider'; K: 'TyDivider'),
    (U: 'tyControls.Edit'; K: 'TyEdit,TyTextHint,TyTextSelection'),
    (U: 'tyControls.Empty'; K: 'TyEmpty,TyEmptyImage'),
    (U: 'tyControls.ExPanel'; K: 'TyExPanel,TyExPanelHeader'),
    (U: 'tyControls.Form'; K: 'TyCaptionButton,TyForm,TyTitleBar'),
    (U: 'tyControls.FormSurface'; K: 'TyFormSurface'),
    (U: 'tyControls.GlyphButtons'; K: 'TyGlyphContainerButton,TySpeedButton'),
    (U: 'tyControls.Grid'; K: 'TyGrid,TyGridActiveCell,TyGridButton,TyGridCell,TyGridCellAlt,' +
      'TyGridCellMarked,TyGridCellSelectedInactive,TyGridCheckBox,TyGridCommentMark,' +
      'TyGridFilterRow,TyGridFixed,TyGridGroupRow,TyGridHeader,TyGridHeaderGroup,' +
      'TyGridHeaderSection,TyGridHyperlink,TyGridIndicator,TyGridLine,TyGridProgress,' +
      'TyGridProgressFill,TyGridRating,TyGridRatingEmpty,TyGridSelectionFrame,TyGridSummaryRow'),
    { not in the preview: in the table so its keys are known ones (the catalogue leaves them
      out -- the base deliberately does not define them) }
    (U: 'tyControls.GridPanel'; K: 'TyGridPanel,TyGridPanelCell'),
    (U: 'tyControls.GroupBox'; K: 'TyGroupBox'),
    (U: 'tyControls.HeaderControl'; K: 'TyHeaderControl,TyTreeHeaderSection'),
    (U: 'tyControls.LinkLabel'; K: 'TyLinkLabel,TyLinkLabelLink'),
    (U: 'tyControls.ListBox'; K: 'TyListBox,TyListItem'),
    (U: 'tyControls.ListView'; K: 'TyListView,TyListViewCheckBox,TyListViewGroupHeader,' +
      'TyListViewHeader,TyListViewHeaderSection,TyListViewItem,TyListViewLine,TyListViewMarquee'),
    (U: 'tyControls.Memo'; K: 'TyMemo,TyTextSelection'),
    (U: 'tyControls.Menu'; K: 'TyMenuBar,TyMenuItem,TyMenuPopup,TyMenuView'),
    (U: 'tyControls.Notification'; K: 'TyNotification,TyNotificationClose'),
    (U: 'tyControls.PageControl'; K: 'TyPageControl'),
    (U: 'tyControls.Panel'; K: 'TyPanel'),
    (U: 'tyControls.Popup'; K: 'TyListBox'),
    (U: 'tyControls.ProgressBar'; K: 'TyProgressBar,TyProgressFill,TyTextHint'),
    (U: 'tyControls.Rating'; K: 'TyRating,TyRatingStar'),
    (U: 'tyControls.ScrollBar'; K: 'TyScrollBar,TyScrollThumb'),
    (U: 'tyControls.ScrollBox'; K: 'TyScrollBox'),
    (U: 'tyControls.ScrollContent'; K: 'TyScrollContent'),
    (U: 'tyControls.SpinEdit'; K: 'TyButton,TySpinEdit,TyTextHint'),
    (U: 'tyControls.Splitter'; K: 'TySplitter'),
    (U: 'tyControls.StatusBar'; K: 'TyStatusBar'),
    (U: 'tyControls.TabSet'; K: 'TyTabSet'),
    (U: 'tyControls.TabSheet'; K: 'TyTabSheet'),
    (U: 'tyControls.TabStrip'; K: 'TyTab,TyTabClose'),
    (U: 'tyControls.Tag'; K: 'TyTag,TyTagClose'),
    (U: 'tyControls.ToggleSwitch'; K: 'TyToggleKnob,TyToggleSwitch'),
    (U: 'tyControls.ToolBar'; K: 'TyToolBar,TyToolSeparator'),
    (U: 'tyControls.TrackBar'; K: 'TyTrackBar,TyTrackGroove,TyTrackThumb'),
    (U: 'tyControls.TreeView'; K: 'TyTreeCheckBox,TyTreeHeader,TyTreeHeaderSection,TyTreeNode,TyTreeView'),
    (U: 'tyControls.TyLabel'; K: 'TyLabel'),
    (U: 'tyControls.UpDown'; K: 'TyButton,TyUpDown'),
    (U: 'tyControls.ValueListEditor'; K: 'TyListBox,TyValueListEditor,TyValueListEditorDivider,' +
      'TyValueListEditorExpander,TyValueListEditorKey,TyValueListEditorRow,TyValueListEditorValue'));

{ the position of AKey in AList, without case }
function IndexOfKey(AList: TStrings; const AKey: string): Integer;
var
  i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if SameText(AList[i], AKey) then
      Exit(i);
  Result := -1;
end;

function WordCountOf(const AKeys: string): Integer;
var
  i: Integer;
begin
  if AKeys = '' then Exit(0);
  Result := 1;
  for i := 1 to Length(AKeys) do
    if AKeys[i] = ',' then
      Inc(Result);
end;

{ the AIndex-th (1-based) comma-separated key }
function WordOf(const AKeys: string; AIndex: Integer): string;
var
  i, n, start: Integer;
begin
  Result := '';
  n := 1;
  start := 1;
  for i := 1 to Length(AKeys) + 1 do
    if (i > Length(AKeys)) or (AKeys[i] = ',') then
    begin
      if n = AIndex then
        Exit(Trim(Copy(AKeys, start, i - start)));
      Inc(n);
      start := i + 1;
    end;
end;

var
  GBaseKeys: TStringList = nil;

procedure TbDocTypeKeys(AScan: TTbCssScan; ADest: TStrings);
var
  b, s: Integer;
  blk: TTbBlock;
begin
  for b := 0 to AScan.Count - 1 do
  begin
    blk := AScan.Block(b);
    if blk.Kind <> tbkRule then Continue;
    for s := 0 to High(blk.Selectors) do
      if (blk.Selectors[s].TypeName <> '') and (IndexOfKey(ADest, blk.Selectors[s].TypeName) < 0) then
        ADest.Add(blk.Selectors[s].TypeName);
  end;
end;

procedure TbBaseTypeKeys(ADest: TStrings);
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
  r, s: Integer;
  rule: TTyCssRule;
  i: Integer;
begin
  if GBaseKeys = nil then
  begin
    GBaseKeys := TStringList.Create;
    GBaseKeys.CaseSensitive := False;
    GBaseKeys.Sorted := True;
    GBaseKeys.Duplicates := dupIgnore;
    p := TTyCssParser.Create(TyBuiltinThemeCss);
    try
      sheet := p.Parse;
      try
        for r := 0 to sheet.Rules.Count - 1 do
        begin
          rule := TTyCssRule(sheet.Rules[r]);
          { every selector of the list: a key that only ever comes second (TyUpDown) counts }
          for s := 0 to High(rule.Selectors) do
            GBaseKeys.Add(rule.Selectors[s].TypeName);
        end;
      finally
        sheet.Free;
      end;
    finally
      p.Free;
    end;
  end;
  for i := 0 to GBaseKeys.Count - 1 do
    if IndexOfKey(ADest, GBaseKeys[i]) < 0 then
      ADest.Add(GBaseKeys[i]);
end;

function TbPartKeysOfUnit(const AUnit: string): string;
var
  i: Integer;
begin
  for i := 0 to High(cTbPartRows) do
    if SameText(cTbPartRows[i].U, AUnit) then
      Exit(cTbPartRows[i].K);
  Result := '';
end;

procedure TbPartKeysOfClass(AClass: TClass; ADest: TStrings);
var
  c: TClass;
  keys: string;
  i, n: Integer;
  k: string;
begin
  c := AClass;
  while c <> nil do
  begin
    keys := TbPartKeysOfUnit(c.UnitName);
    if keys <> '' then
    begin
      n := WordCountOf(keys);
      for i := 1 to n do
      begin
        k := WordOf(keys, i);
        if IndexOfKey(ADest, k) < 0 then
          ADest.Add(k);
      end;
    end;
    c := c.ClassParent;
  end;
end;

function TbPartKeyUnits: TStringArray;
var
  i: Integer;
begin
  SetLength(Result, Length(cTbPartRows));
  for i := 0 to High(cTbPartRows) do
    Result[i] := cTbPartRows[i].U;
end;

var
  GKnownKeys: TStringList = nil;   { catalogue + base + part table, lower case, sorted }

function TbIsKnownTypeKey(const AKey: string; APreview: TStrings): Boolean;
var
  i, j, n: Integer;
  base: TStringList;
begin
  if GKnownKeys = nil then
  begin
    GKnownKeys := TStringList.Create;
    GKnownKeys.Sorted := True;
    GKnownKeys.Duplicates := dupIgnore;
    for i := 0 to High(TyCatalogTypeKeys) do
      GKnownKeys.Add(LowerCase(TyCatalogTypeKeys[i]));
    for i := 0 to High(cTbPartRows) do
    begin
      n := WordCountOf(cTbPartRows[i].K);
      for j := 1 to n do
        GKnownKeys.Add(LowerCase(WordOf(cTbPartRows[i].K, j)));
    end;
    base := TStringList.Create;
    try
      TbBaseTypeKeys(base);
      for i := 0 to base.Count - 1 do
        GKnownKeys.Add(LowerCase(base[i]));
    finally
      base.Free;
    end;
  end;
  if GKnownKeys.IndexOf(LowerCase(AKey)) >= 0 then
    Exit(True);
  Result := (APreview <> nil) and (IndexOfKey(APreview, AKey) >= 0);
end;

procedure SortKeys(AList: TStrings);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.CaseSensitive := False;
    sl.Assign(AList);
    sl.Sort;
    AList.Assign(sl);
  finally
    sl.Free;
  end;
end;

procedure TbCoverageLists(ADoc, APreview, ABase, ANotShown, ADefaultLook: TStrings);
var
  i: Integer;
begin
  ANotShown.Clear;
  ADefaultLook.Clear;
  for i := 0 to ADoc.Count - 1 do
    if (IndexOfKey(APreview, ADoc[i]) < 0) and (IndexOfKey(ANotShown, ADoc[i]) < 0) then
      ANotShown.Add(ADoc[i]);
  for i := 0 to APreview.Count - 1 do
    if (IndexOfKey(ADoc, APreview[i]) < 0) and (IndexOfKey(ABase, APreview[i]) < 0)
       and (IndexOfKey(ADefaultLook, APreview[i]) < 0) then
      ADefaultLook.Add(APreview[i]);
  SortKeys(ANotShown);
  SortKeys(ADefaultLook);
end;

finalization
  FreeAndNil(GBaseKeys);
  FreeAndNil(GKnownKeys);
end.
