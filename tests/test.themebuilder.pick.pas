unit test.themebuilder.pick;
{ Ctrl+click in the theme builder's preview (phase 2), through the real path: the mouse
  message is Performed on the control, which is what the widgetset (a windowed control) or
  the parent (a graphic one) does -- so it goes through WindowProc, where the hook is. The
  pick is reported, the control never sees the press; a press without Ctrl goes through.
  The coverage check follows in the second half. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Controls, Forms, LMessages, LCLType, tbpreview;

type
  TTbPickTests = class(TTestCase)
  private
    FFrame: TTbPreviewFrame;
    FPicks: Integer;
    FKey, FCls: string;
    FClicks: Integer;
    FUps: Integer;
    FHost: TForm;
    procedure HostFrame;
    procedure PickStub(Sender: TObject; const ATypeKey, AStyleClass: string);
    procedure ClickStub(Sender: TObject);
    procedure UpStub(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CtrlDown(AControl: TControl; AX: Integer = 0; AY: Integer = 0);
    procedure PlainDown(AControl: TControl);
    procedure Up(AControl: TControl);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestACtrlPressIsAPickAndNotAPress;
    procedure TestAPlainPressGoesThrough;
    procedure TestTheReleaseAfterAPickIsSwallowed;
    procedure TestADisabledLabel;
    procedure TestAControlWithoutATypeKey;
    procedure TestTheSampleWindow;
    procedure TestTheStripIsNotHooked;
    procedure TestUnhooking;
    procedure TestTheFrameGoesCleanly;
    procedure TestAReleaseThatWentElsewhereIsNotWaitedFor;
    procedure TestACtrlDoubleClickPicksOnce;
  end;

  { the coverage check (tbcoverage): the three sets, the two lists, the part table held to
    the sources, the dialog }
  TTbCoverageTests = class(TTestCase)
  private
    function NewList: TStringList;
  published
    procedure TestTheBaseKeys;
    procedure TestTheTwoLists;
    procedure TestWhatThePreviewShows;
    procedure TestThePartTableMatchesTheSources;
    procedure TestEndToEnd;
    procedure TestTheDocumentKeys;
    procedure TestTheDialog;
    procedure TestWhatIsAKnownTypeKey;
    procedure TestEveryLibraryKeyIsKnown;
  end;

implementation

uses
  ExtCtrls, tyControls.Base, tyControls.Button, tyControls.Dialogs, tyControls.Notification,
  tyControls.Css.Catalog, tbpick, tbsamplewin, tbcssscan, tbcoverage, tbcoverageform, tbtemplates,
  test.themebuilder.golden;

type
  TTyCustomControlAccess = class(TTyCustomControl);

procedure TTbPickTests.SetUp;
begin
  FFrame := TTbPreviewFrame.Create(nil);
  FFrame.OnPick := @PickStub;
  FPicks := 0;
  FKey := '';
  FCls := '';
  FClicks := 0;
end;

procedure TTbPickTests.TearDown;
begin
  FreeAndNil(FFrame);
  FreeAndNil(FHost);
end;

{ A press that goes through to the control makes it capture the mouse, which takes a window
  handle all the way up: the frame goes on a form (never shown) and the widgetset is
  initialised once (the console runner does not do it). }
var
  GPickWidgetSet: Boolean = False;

procedure TTbPickTests.HostFrame;
begin
  if not GPickWidgetSet then
  begin
    Forms.Application.Initialize;
    GPickWidgetSet := True;
  end;
  FHost := TForm.CreateNew(nil);
  FHost.SetBounds(0, 0, 640, 720);
  FFrame.Parent := FHost;
end;

procedure TTbPickTests.PickStub(Sender: TObject; const ATypeKey, AStyleClass: string);
begin
  Inc(FPicks);
  FKey := ATypeKey;
  FCls := AStyleClass;
end;

procedure TTbPickTests.ClickStub(Sender: TObject);
begin
  Inc(FClicks);
end;

procedure TTbPickTests.UpStub(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  Inc(FUps);
end;

procedure TTbPickTests.CtrlDown(AControl: TControl; AX: Integer; AY: Integer);
begin
  AControl.Perform(LM_LBUTTONDOWN, MK_LBUTTON or MK_CONTROL, LPARAM((AY shl 16) or (AX and $FFFF)));
end;

procedure TTbPickTests.PlainDown(AControl: TControl);
begin
  AControl.Perform(LM_LBUTTONDOWN, MK_LBUTTON, 0);
end;

procedure TTbPickTests.Up(AControl: TControl);
begin
  AControl.Perform(LM_LBUTTONUP, 0, 0);
end;

procedure TTbPickTests.TestACtrlPressIsAPickAndNotAPress;
begin
  FFrame.BtnPrimary.OnClick := @ClickStub;
  CtrlDown(FFrame.BtnPrimary);
  AssertEquals('P1: one pick', 1, FPicks);
  AssertEquals('P1: the typeKey', 'TyButton', FKey);
  AssertEquals('P1: the variant', 'primary', FCls);
  AssertFalse('P1: the button was not pressed', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  Up(FFrame.BtnPrimary);
  AssertEquals('P1: and not clicked', 0, FClicks);
end;

procedure TTbPickTests.TestAPlainPressGoesThrough;
begin
  HostFrame;
  PlainDown(FFrame.BtnPrimary);
  AssertEquals('P2: no pick', 0, FPicks);
  AssertTrue('P2: the button was pressed', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  Up(FFrame.BtnPrimary);
  AssertFalse('P2: and released', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
end;

procedure TTbPickTests.TestTheReleaseAfterAPickIsSwallowed;
begin
  HostFrame;
  FFrame.BtnPrimary.OnClick := @ClickStub;
  FFrame.BtnPrimary.OnMouseUp := @UpStub;
  FUps := 0;
  CtrlDown(FFrame.BtnPrimary);
  Up(FFrame.BtnPrimary);      { Ctrl let go before the button: still the pick's release }
  AssertEquals('P3: the release never reached the button', 0, FUps);
  AssertEquals('P3: not clicked', 0, FClicks);
  AssertFalse('P3: not pressed', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  PlainDown(FFrame.BtnPrimary);
  AssertTrue('P3: the next plain press goes through', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  Up(FFrame.BtnPrimary);
  AssertEquals('P3: and its release too', 1, FUps);
end;

procedure TTbPickTests.TestADisabledLabel;
var
  lbl: TControl;
begin
  lbl := FFrame.LblDisabled;
  AssertFalse('disabled', lbl.Enabled);
  CtrlDown(lbl.Parent, lbl.Left + lbl.Width div 2, lbl.Top + lbl.Height div 2);
  AssertEquals('P4: one pick', 1, FPicks);
  AssertEquals('P4: the label', 'TyLabel', FKey);
  AssertEquals('P4: no variant', '', FCls);
end;

procedure TTbPickTests.TestAControlWithoutATypeKey;
var
  shape: TShape;
begin
  shape := TShape.Create(nil);
  try
    shape.SetBounds(4, 4, 20, 20);
    shape.Parent := FFrame.PnlSample;
    FFrame.Picker.HookTree(FFrame.PnlSample);
    CtrlDown(shape);
    AssertEquals('P5: one pick', 1, FPicks);
    AssertEquals('P5: the nearest Ty control', 'TyPanel', FKey);
    AssertEquals('P5: no variant', '', FCls);
  finally
    shape.Free;
  end;
end;

procedure TTbPickTests.TestTheSampleWindow;
var
  win: TTbSampleForm;
begin
  win := FFrame.BuildSampleWindow;
  CtrlDown(win.BtnOk);
  AssertEquals('P6: one pick', 1, FPicks);
  AssertEquals('P6: the typeKey', 'TyButton', FKey);
  AssertEquals('P6: the variant', 'primary', FCls);
end;

procedure TTbPickTests.TestTheStripIsNotHooked;
begin
  HostFrame;
  CtrlDown(FFrame.DarkSwitch);
  Up(FFrame.DarkSwitch);
  AssertEquals('P7: the strip is the tool''s', 0, FPicks);
end;

procedure TTbPickTests.TestUnhooking;
var
  b: TTyButton;
  p: TTbPicker;
  before: TWndMethod;
begin
  b := TTyButton.Create(nil);
  p := TTbPicker.Create(nil);
  try
    before := b.WindowProc;
    p.HookTree(b);
    AssertEquals('P8: one hook', 1, p.HookCount);
    AssertFalse('P8: hooked', TMethod(b.WindowProc).Code = TMethod(before).Code);
    p.UnhookAll;
    AssertEquals('P8: none', 0, p.HookCount);
    AssertTrue('P8: the old one is back (code)', TMethod(b.WindowProc).Code = TMethod(before).Code);
    AssertTrue('P8: the old one is back (data)', TMethod(b.WindowProc).Data = TMethod(before).Data);
  finally
    b.Free;
    p.Free;
  end;
  { the control goes first: the hook forgets it, the picker goes without touching it }
  b := TTyButton.Create(nil);
  p := TTbPicker.Create(nil);
  try
    p.HookTree(b);
    FreeAndNil(b);
    AssertEquals('P8: the freed control is forgotten', 0, p.HookCount);
  finally
    b.Free;
    p.Free;
  end;
end;

procedure TTbPickTests.TestTheFrameGoesCleanly;
begin
  FFrame.BuildSampleWindow;
  CtrlDown(FFrame.BtnPrimary);
  AssertEquals('a pick', 1, FPicks);
  FreeAndNil(FFrame);
  AssertNull('P9: gone', FFrame);
end;

{ The review found it: a Ctrl+press whose release lands on something not hooked (the editor,
  outside the window) left the picker waiting for a release -- and it ate the release of the
  next ordinary click on the control, which stayed pressed, held the mouse and never
  clicked. (The capture itself is the widgetset's to let go on a real release -- a press
  Performed here keeps it either way, so the button's own state is what is checked.) }
procedure TTbPickTests.TestAReleaseThatWentElsewhereIsNotWaitedFor;
begin
  HostFrame;
  FFrame.BtnPrimary.OnClick := @ClickStub;
  FFrame.BtnPrimary.OnMouseUp := @UpStub;
  FUps := 0;
  CtrlDown(FFrame.BtnPrimary);
  AssertEquals('a pick', 1, FPicks);
  { its release went to the editor: no message here }
  PlainDown(FFrame.BtnPrimary);
  AssertTrue('P10: the next press reaches the button', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  Up(FFrame.BtnPrimary);
  AssertEquals('P10: and so does its release', 1, FUps);
  AssertEquals('P10: one click', 1, FClicks);
  AssertFalse('P10: not left pressed', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
end;

{ Ctrl+double click: down, up, double click, up. One gesture, one pick -- the second press
  used to pick again and go to the next rule. A Ctrl+double click right after a plain click
  (the first press was the control's own) still picks once. }
procedure TTbPickTests.TestACtrlDoubleClickPicksOnce;
var
  b: TControl;
begin
  HostFrame;
  b := FFrame.BtnPrimary;
  FFrame.BtnPrimary.OnClick := @ClickStub;
  b.Perform(LM_LBUTTONDOWN, MK_LBUTTON or MK_CONTROL, 0);
  b.Perform(LM_LBUTTONUP, MK_CONTROL, 0);
  b.Perform(LM_LBUTTONDBLCLK, MK_LBUTTON or MK_CONTROL, 0);
  b.Perform(LM_LBUTTONUP, MK_CONTROL, 0);
  AssertEquals('P11: one pick', 1, FPicks);
  AssertEquals('P11: no click', 0, FClicks);
  AssertFalse('P11: not pressed', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  PlainDown(b);
  Up(b);
  AssertEquals('a plain click', 1, FClicks);
  b.Perform(LM_LBUTTONDBLCLK, MK_LBUTTON or MK_CONTROL, 0);
  b.Perform(LM_LBUTTONUP, MK_CONTROL, 0);
  AssertEquals('P11: a Ctrl+double click after a plain click picks', 2, FPicks);
  AssertEquals('P11: and does not click', 1, FClicks);
end;

{ ---- coverage ---- }

function TTbCoverageTests.NewList: TStringList;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
end;

function Has(AList: TStrings; const AKey: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if SameText(AList[i], AKey) then
      Exit(True);
  Result := False;
end;

procedure TTbCoverageTests.TestTheBaseKeys;
var
  base: TStringList;
begin
  base := NewList;
  try
    TbBaseTypeKeys(base);
    AssertTrue('CV1: TyButton', Has(base, 'TyButton'));
    AssertTrue('CV1: TyTab', Has(base, 'TyTab'));
    AssertTrue('CV1: TyScrollThumb', Has(base, 'TyScrollThumb'));
    AssertTrue('CV1: TyUpDown, never first in its list', Has(base, 'TyUpDown'));
    AssertFalse('CV1: not TyFormSurface', Has(base, 'TyFormSurface'));
    AssertFalse('CV1: not TyListViewLine', Has(base, 'TyListViewLine'));
    AssertTrue('CV1: many: ' + IntToStr(base.Count), base.Count >= 150);
  finally
    base.Free;
  end;
end;

procedure TTbCoverageTests.TestTheTwoLists;
var
  doc, prev, base, notShown, def: TStringList;
begin
  doc := NewList;
  prev := NewList;
  base := NewList;
  notShown := TStringList.Create;
  def := TStringList.Create;
  try
    { TyCard: shown and styled by the document, not by the base -- it keeps no built-in look }
    doc.CommaText := 'TyButton,TyRibbon,TyButon,TyCard';
    prev.CommaText := 'TyButton,TyTab,TyFormSurface,TyCard';
    base.CommaText := 'TyButton,TyTab';
    TbCoverageLists(doc, prev, base, notShown, def);
    AssertEquals('CV2: not shown', 'TyButon,TyRibbon', notShown.CommaText);
    AssertEquals('CV2: the default look', 'TyFormSurface', def.CommaText);
  finally
    doc.Free;
    prev.Free;
    base.Free;
    notShown.Free;
    def.Free;
  end;
end;

procedure TTbCoverageTests.TestWhatThePreviewShows;
const
  cIn: array[0..7] of string = ('TyButton', 'TyTab', 'TyScrollThumb', 'TyMenuItem',
    'TyNotificationClose', 'TyCaptionButton', 'TyTitleBar', 'TyToggleKnob');
  cOut: array[0..2] of string = ('TyRibbon', 'TyTerminal', 'TyAdvChart');
var
  frame: TTbPreviewFrame;
  prev: TStringList;
  i: Integer;
begin
  frame := TTbPreviewFrame.Create(nil);
  prev := NewList;
  try
    frame.CollectTypeKeys(prev);
    for i := 0 to High(cIn) do
      AssertTrue('CV3: shows ' + cIn[i], Has(prev, cIn[i]));
    for i := 0 to High(cOut) do
      AssertFalse('CV3: does not show ' + cOut[i], Has(prev, cOut[i]));
  finally
    prev.Free;
    frame.Free;
  end;
end;

{ the typeKeys a unit names in string literals: comments stripped (braces nest in FPC),
  every quoted string that is a whole Ty[A-Z]... identifier, TyControls left out }
function LiteralKeys(const AUnit: string): TStringList;
var
  sl: TStringList;
  t, lit: string;
  i, n, depth: Integer;

  procedure Take(const S: string);
  var
    k: Integer;
    ok: Boolean;
  begin
    ok := (Length(S) >= 3) and (S[1] = 'T') and (S[2] = 'y') and (S[3] in ['A'..'Z']);
    if ok then
      for k := 4 to Length(S) do
        if not (S[k] in ['A'..'Z', 'a'..'z', '0'..'9']) then
          ok := False;
    if ok and (S <> 'TyControls') and not Has(Result, S) then
      Result.Add(S);
  end;

begin
  Result := TStringList.Create;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(TbRepoDir + 'source' + PathDelim + AUnit + '.pas');
    t := sl.Text;
  finally
    sl.Free;
  end;
  n := Length(t);
  i := 1;
  depth := 0;
  while i <= n do
  begin
    if depth > 0 then
    begin
      if t[i] = '{' then Inc(depth)
      else if t[i] = '}' then Dec(depth);
      Inc(i);
      Continue;
    end;
    if t[i] = '{' then
    begin
      depth := 1;
      Inc(i);
      Continue;
    end;
    if (t[i] = '(') and (i < n) and (t[i + 1] = '*') then
    begin
      i := i + 2;
      while (i < n) and not ((t[i] = '*') and (t[i + 1] = ')')) do Inc(i);
      i := i + 2;
      Continue;
    end;
    if (t[i] = '/') and (i < n) and (t[i + 1] = '/') then
    begin
      while (i <= n) and not (t[i] in [#10, #13]) do Inc(i);
      Continue;
    end;
    if t[i] = '''' then
    begin
      lit := '';
      Inc(i);
      while i <= n do
      begin
        if t[i] = '''' then
        begin
          if (i < n) and (t[i + 1] = '''') then
          begin
            lit := lit + '''';
            i := i + 2;
            Continue;
          end;
          Break;
        end;
        lit := lit + t[i];
        Inc(i);
      end;
      Inc(i);
      Take(lit);
      Continue;
    end;
    Inc(i);
  end;
end;

function IsCatalogKey(const AKey: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(TyCatalogTypeKeys) do
    if SameText(TyCatalogTypeKeys[i], AKey) then
      Exit(True);
  Result := False;
end;

procedure TTbCoverageTests.TestThePartTableMatchesTheSources;
var
  frame: TTbPreviewFrame;
  units, row, lits: TStringList;
  d: TTyDialog;
  i, k: Integer;
  rowUnits: TStringArray;

  procedure AddClass(AClass: TClass);
  begin
    while AClass <> nil do
    begin
      if (Copy(AClass.UnitName, 1, 11) = 'tyControls.') and not Has(units, AClass.UnitName) then
        units.Add(AClass.UnitName);
      AClass := AClass.ClassParent;
    end;
  end;

  procedure Walk(AControl: TControl);
  var
    j: Integer;
  begin
    AddClass(AControl.ClassType);
    if AControl is TWinControl then
      for j := 0 to TWinControl(AControl).ControlCount - 1 do
        Walk(TWinControl(AControl).Controls[j]);
  end;

begin
  frame := TTbPreviewFrame.Create(nil);
  units := TStringList.Create;
  row := TStringList.Create;
  try
    Walk(frame.Root);
    Walk(frame.BuildSampleWindow);
    d := frame.BuildSampleDialog;
    try
      Walk(d);
    finally
      d.Free;
    end;
    d := frame.BuildSampleInput;
    try
      Walk(d);
    finally
      d.Free;
    end;
    AddClass(frame.SamplePopup.ClassType);
    AddClass(TTyNotification);
    AssertTrue('CV4: units were met', units.Count > 30);
    for i := 0 to units.Count - 1 do
    begin
      lits := LiteralKeys(units[i]);
      try
        row.CommaText := TbPartKeysOfUnit(units[i]);
        for k := 0 to lits.Count - 1 do
          AssertTrue('CV4: ' + units[i] + ' names ' + lits[k] + ', its row does not have it',
            Has(row, lits[k]));
      finally
        lits.Free;
      end;
    end;
    rowUnits := TbPartKeyUnits;
    for i := 0 to High(rowUnits) do
    begin
      lits := LiteralKeys(rowUnits[i]);
      try
        row.CommaText := TbPartKeysOfUnit(rowUnits[i]);
        AssertTrue('CV4: a row with keys: ' + rowUnits[i], row.Count > 0);
        for k := 0 to row.Count - 1 do
          AssertTrue('CV4: ' + rowUnits[i] + ' has ' + row[k] +
            ', which is neither in its source nor a catalogue key',
            Has(lits, row[k]) or IsCatalogKey(row[k]));
      finally
        lits.Free;
      end;
    end;
  finally
    row.Free;
    units.Free;
    frame.Free;
  end;
end;

procedure TTbCoverageTests.TestEndToEnd;
var
  frame: TTbPreviewFrame;
  doc, prev, base, notShown, def: TStringList;
  s: TTbCssScan;

  procedure Run(const AText: string);
  begin
    doc.Clear;
    s := TbScanCss(AText);
    try
      TbDocTypeKeys(s, doc);
    finally
      s.Free;
    end;
    TbCoverageLists(doc, prev, base, notShown, def);
  end;

begin
  frame := TTbPreviewFrame.Create(nil);
  doc := NewList;
  prev := NewList;
  base := NewList;
  notShown := TStringList.Create;
  def := TStringList.Create;
  try
    frame.CollectTypeKeys(prev);
    TbBaseTypeKeys(base);
    Run(TbMinimalTemplate);
    AssertEquals('CV5: nothing styled is missing', 0, notShown.Count);
    AssertTrue('CV5: TyFormSurface keeps its look', Has(def, 'TyFormSurface'));
    AssertTrue('CV5: TyListViewLine keeps its look', Has(def, 'TyListViewLine'));
    AssertFalse('CV5: the base styles TyButton', Has(def, 'TyButton'));
    Run('TyRibbon { }');
    AssertEquals('CV5: a ribbon is not shown', 'TyRibbon', notShown.CommaText);
  finally
    doc.Free;
    prev.Free;
    base.Free;
    notShown.Free;
    def.Free;
    frame.Free;
  end;
end;

procedure TTbCoverageTests.TestTheDocumentKeys;
var
  doc: TStringList;
  s: TTbCssScan;
begin
  doc := NewList;
  s := TbScanCss('TyButton.primary:hover, TyEdit { }'#10'@mode dark { :root { --a: #111; } }');
  try
    TbDocTypeKeys(s, doc);
    AssertEquals('CV6', 'TyButton,TyEdit', doc.CommaText);
  finally
    s.Free;
    doc.Free;
  end;
end;

procedure TTbCoverageTests.TestTheDialog;
var
  f: TTbCoverageForm;
  notShown, def: TStringList;
begin
  notShown := TStringList.Create;
  def := TStringList.Create;
  f := TTbCoverageForm.Create(nil);
  try
    notShown.CommaText := 'TyButon,TyRibbon';
    def.CommaText := 'TyFormSurface';
    f.Fill(notShown, def);
    AssertEquals('CV7: two entries', 2, f.LstNotShown.Items.Count);
    AssertTrue('CV7: a typo is marked', Pos(rsTbCovUnknownKey, f.LstNotShown.Items[0]) > 0);
    AssertTrue('CV7: a real key is not', Pos(rsTbCovUnknownKey, f.LstNotShown.Items[1]) = 0);
    AssertEquals('CV7: the second list', 1, f.LstDefault.Items.Count);
    f.LstNotShown.ItemIndex := 0;
    f.LstNotShown.OnDblClick(f.LstNotShown);
    AssertEquals('CV7: the key, not the caption', 'TyButon', f.Chosen);
    AssertEquals('CV7: closes with OK', Ord(mrOk), Ord(f.ModalResult));
  finally
    f.Free;
    notShown.Free;
    def.Free;
  end;
end;

{ The review found it: the dialog marked every key outside the catalogue "not a known
  typeKey" -- TyFormSurface (in the second list on every theme) and TyGridPanel among them;
  the catalogue leaves out what the base deliberately does not define. Known = catalogue,
  base rules, the part table, what the preview shows. }
procedure TTbCoverageTests.TestWhatIsAKnownTypeKey;
var
  f: TTbCoverageForm;
  notShown, def, prev: TStringList;
begin
  notShown := TStringList.Create;
  def := TStringList.Create;
  prev := TStringList.Create;
  f := TTbCoverageForm.Create(nil);
  try
    notShown.CommaText := 'TyButon,TyGridPanel,TyGridPanelCell,TyShownOnly';
    def.CommaText := 'TyFormSurface,TyListViewLine';
    prev.CommaText := 'TyShownOnly';
    f.Fill(notShown, def, prev);
    AssertTrue('CV8: a typo is marked', Pos(rsTbCovUnknownKey, f.LstNotShown.Items[0]) > 0);
    AssertTrue('CV8: TyGridPanel is not', Pos(rsTbCovUnknownKey, f.LstNotShown.Items[1]) = 0);
    AssertTrue('CV8: TyGridPanelCell is not', Pos(rsTbCovUnknownKey, f.LstNotShown.Items[2]) = 0);
    AssertTrue('CV8: what the preview shows is not', Pos(rsTbCovUnknownKey, f.LstNotShown.Items[3]) = 0);
    AssertTrue('CV8: TyFormSurface is not', Pos(rsTbCovUnknownKey, f.LstDefault.Items[0]) = 0);
    AssertTrue('CV8: TyListViewLine is not', Pos(rsTbCovUnknownKey, f.LstDefault.Items[1]) = 0);
    AssertFalse('CV8: no preview, no such key', TbIsKnownTypeKey('TyShownOnly', nil));
    AssertTrue('CV8: case does not matter', TbIsKnownTypeKey('tyformsurface', nil));
  finally
    f.Free;
    notShown.Free;
    def.Free;
    prev.Free;
  end;
end;

{ Every typeKey a library unit names in a string literal is a known one -- or the start of
  catalogue keys it builds by adding to it ('TyTerminalAnsi' + a number). A new control
  whose key is in no catalogue and no row turns this red: give its unit a row. }
procedure TTbCoverageTests.TestEveryLibraryKeyIsKnown;
var
  sr: TSearchRec;
  lits: TStringList;
  i, k: Integer;
  u: string;
  prefix: Boolean;
  units: Integer;
begin
  units := 0;
  if FindFirst(TbRepoDir + 'source' + PathDelim + 'tyControls.*.pas', faAnyFile, sr) = 0 then
  try
    repeat
      u := ChangeFileExt(sr.Name, '');
      Inc(units);
      lits := LiteralKeys(u);
      try
        for i := 0 to lits.Count - 1 do
        begin
          if TbIsKnownTypeKey(lits[i], nil) then Continue;
          prefix := False;
          for k := 0 to High(TyCatalogTypeKeys) do
            if (Length(TyCatalogTypeKeys[k]) > Length(lits[i]))
               and SameText(Copy(TyCatalogTypeKeys[k], 1, Length(lits[i])), lits[i]) then
              prefix := True;
          AssertTrue('CV9: ' + u + ' names ' + lits[i] + ', which is not a known typeKey', prefix);
        end;
      finally
        lits.Free;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertTrue('CV9: the units were read: ' + IntToStr(units), units > 100);
end;

initialization
  RegisterTest(TTbPickTests);
  RegisterTest(TTbCoverageTests);
end.
