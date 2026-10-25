unit test.popup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Forms, FileUtil,
  fpcunit, testregistry,
  tyControls.Popup, tyControls.ListBox, tyControls.PlatformWS;

type
  { Pure geometry tests for TyPopupRect. }
  TPopupGeomTest = class(TTestCase)
  published
    procedure TestDropsBelowWhenRoom;
    procedure TestFlipsAboveWhenNoRoom;
  end;

  { Smoke test for TTyDropdownPopup: Create/Destroy + IsOpen, no real window. }
  TPopupSmokeTest = class(TTestCase)
  private
    FCloses: Integer;
    procedure OnClose(Sender: TObject);
  published
    procedure TestCreateDestroyNoRaise;
    procedure TestCloseOnHiddenIsNoOp;
    procedure TestSetContentSwaps;
  end;

  { #104: the window level TyRaisePopupWindow gives a popup about to show, run against the
    platform seam (the macOS answers come from PutLevel), and the places that show one. }
  TPopupLevelTest = class(TTestCase)
  private
    FPopup, FMain, FDialog: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAPopupOverAModalDialogGoesAboveIt;
    procedure TestOverOrdinaryWindowsItKeepsTheFloatingLevel;
    procedure TestAPopupOverAnotherPopupGoesAboveIt;
    procedure TestItsOwnEarlierLevelDoesNotCount;
    procedure TestEveryPopupWindowIsRaisedBeforeItShows;
  end;

implementation

procedure TPopupGeomTest.TestDropsBelowWhenRoom;
var
  r: TRect;
begin
  // Anchor at y=100..120 on a 1000px-tall screen; 200px content → drops below at y=120.
  r := TyPopupRect(Rect(50, 100, 250, 120), 200, 200, 1000);
  AssertEquals('top below anchor', 120, r.Top);
  AssertEquals('height', 200, r.Bottom - r.Top);
  AssertEquals('left aligned', 50, r.Left);
  AssertEquals('width', 200, r.Right - r.Left);
end;

procedure TPopupGeomTest.TestFlipsAboveWhenNoRoom;
var
  r: TRect;
begin
  // Anchor near the bottom (y=900..920), 200px content, 1000px screen →
  // not enough room below (920+200=1120>1000), room above (900-200=700≥0) → flip above.
  r := TyPopupRect(Rect(50, 900, 250, 920), 200, 200, 1000);
  AssertEquals('bottom at anchor top', 900, r.Bottom);
  AssertEquals('top = anchor.top - height', 700, r.Top);
end;

procedure TPopupSmokeTest.TestCreateDestroyNoRaise;
var
  p: TTyDropdownPopup;
begin
  p := TTyDropdownPopup.Create;
  try
    AssertFalse('not open initially', p.IsOpen);
  finally
    p.Free;
  end;
end;

procedure TPopupSmokeTest.OnClose(Sender: TObject);
begin
  Inc(FCloses);
end;

procedure TPopupSmokeTest.TestCloseOnHiddenIsNoOp;
var
  p: TTyDropdownPopup;
begin
  // Close is idempotent: closing a popup that was never shown must NOT fire OnClose
  // (a pick that commits+closes could otherwise re-fire it via a trailing deactivate).
  FCloses := 0;
  p := TTyDropdownPopup.Create;
  try
    p.OnClose := @OnClose;
    p.Close;
    p.Close;
    AssertEquals('no OnClose for a never-open popup', 0, FCloses);
  finally
    p.Free;
  end;
end;

procedure TPopupSmokeTest.TestSetContentSwaps;
var
  p: TTyDropdownPopup;
  a, b: TTyListBox;
begin
  // SetContent must SWAP (not latch the first control) so one popup can host an enum list then a
  // colour list — TTyValueListEditor relies on this.
  p := TTyDropdownPopup.Create;
  a := TTyListBox.Create(nil);
  b := TTyListBox.Create(nil);
  try
    p.SetContent(a);
    AssertTrue('a hosted in the popup form', a.Parent = p.Form);
    p.SetContent(b);
    AssertTrue('b now hosted', b.Parent = p.Form);
    AssertTrue('a un-parented on swap', a.Parent = nil);
    p.SetContent(b);   // same control -> no-op
    AssertTrue('b still hosted after re-set', b.Parent = p.Form);
  finally
    a.Free; b.Free; p.Free;
  end;
end;

{ TPopupLevelTest }

var
  GLevelForms: array of TCustomForm;
  GLevels: array of PtrInt;

{ AForm's window is on screen at ALevel; a form never put here has none. }
procedure PutLevel(AForm: TCustomForm; ALevel: PtrInt);
begin
  SetLength(GLevelForms, Length(GLevelForms) + 1);
  SetLength(GLevels, Length(GLevels) + 1);
  GLevelForms[High(GLevelForms)] := AForm;
  GLevels[High(GLevels)] := ALevel;
end;

function FakeLevelOf(AForm: TCustomForm; out ALevel: PtrInt): Boolean;
var
  i: Integer;
begin
  ALevel := 0;
  for i := 0 to High(GLevelForms) do
    if GLevelForms[i] = AForm then
    begin
      ALevel := GLevels[i];
      Exit(True);
    end;
  Result := False;
end;

procedure TPopupLevelTest.SetUp;
begin
  TyResetTestPlatform;
  TyTestPlatform.Active := True;
  TyTestPlatform.FloatingLevel := 3;   // kCGFloatingWindowLevel
  TyTestPlatform.LevelOf := @FakeLevelOf;
  SetLength(GLevelForms, 0);
  SetLength(GLevels, 0);
  FPopup := TForm.CreateNew(nil);
  FMain := TForm.CreateNew(nil);
  FDialog := TForm.CreateNew(nil);
end;

procedure TPopupLevelTest.TearDown;
begin
  FreeAndNil(FDialog);
  FreeAndNil(FMain);
  FreeAndNil(FPopup);
  SetLength(GLevelForms, 0);
  SetLength(GLevels, 0);
  TyResetTestPlatform;
end;

procedure TPopupLevelTest.TestAPopupOverAModalDialogGoesAboveIt;
begin
  PutLevel(FMain, 0);
  PutLevel(FDialog, 8);   // kCGModalPanelWindowLevel
  TyRaisePopupWindow(FPopup);
  AssertEquals('one level set', 1, TyTestPlatform.LevelSets);
  AssertTrue('on the popup', TyTestPlatform.LastLevelForm = FPopup);
  AssertEquals('one above the dialog', 9, TyTestPlatform.LastLevel);
end;

procedure TPopupLevelTest.TestOverOrdinaryWindowsItKeepsTheFloatingLevel;
begin
  PutLevel(FMain, 0);   // the dialog is not on screen
  TyRaisePopupWindow(FPopup);
  AssertEquals('floating, as fsStayOnTop gives it', 3, TyTestPlatform.LastLevel);
end;

procedure TPopupLevelTest.TestAPopupOverAnotherPopupGoesAboveIt;
begin
  PutLevel(FMain, 0);
  PutLevel(FDialog, 3);   // say a menu this one is the submenu of
  TyRaisePopupWindow(FPopup);
  AssertEquals('at its level counts too', 4, TyTestPlatform.LastLevel);
end;

procedure TPopupLevelTest.TestItsOwnEarlierLevelDoesNotCount;
begin
  PutLevel(FPopup, 9);   // still up from a show over a dialog that has closed since
  PutLevel(FMain, 0);
  TyRaisePopupWindow(FPopup);
  AssertEquals('back to floating', 3, TyTestPlatform.LastLevel);
end;

{ Nothing here runs Cocoa, so the wiring is read off the source: every window shown as a popup
  (an fsStayOnTop form) is raised on the line before its Show. }
procedure TPopupLevelTest.TestEveryPopupWindowIsRaisedBeforeItShows;
const
  Units: array[0..5] of string = ('tyControls.Popup.pas', 'tyControls.Menu.pas',
    'tyControls.PopupSurface.pas', 'tyControls.Popover.pas', 'tyControls.Notification.pas',
    'tyControls.BalloonHint.pas');
  Wins: array[0..5] of string = ('FForm', 'FForm', 'Self', 'FWin', 'FWin', 'FWin');
var
  dir: string;
  files: TStringList;
  i: Integer;

  function Listed(const AName: string): Boolean;
  var k: Integer;
  begin
    for k := 0 to High(Units) do
      if SameText(Units[k], AName) then Exit(True);
    Result := False;
  end;

  procedure Check(const AUnit, AWin: string);
  var
    sl: TStringList;
    k, j, shows: Integer;
    stmt, prev: string;
  begin
    if AWin = 'Self' then stmt := 'Show;' else stmt := AWin + '.Show;';
    sl := TStringList.Create;
    try
      sl.LoadFromFile(dir + AUnit);
      shows := 0;
      for k := 0 to sl.Count - 1 do
        if Trim(sl[k]) = stmt then
        begin
          Inc(shows);
          j := k - 1;
          while (j >= 0) and (Trim(sl[j]) = '') do Dec(j);
          prev := '';
          if j >= 0 then prev := Trim(sl[j]);
          AssertTrue(Format('%s:%d raises %s first (the line before: %s)',
            [AUnit, k + 1, AWin, prev]), Pos('TyRaisePopupWindow(' + AWin + ');', prev) = 1);
        end;
      AssertTrue(AUnit + ' shows its window', shows > 0);
    finally
      sl.Free;
    end;
  end;

  function SetsStayOnTop(const AFile: string): Boolean;
  var
    sl: TStringList;
    k: Integer;
  begin
    Result := False;
    sl := TStringList.Create;
    try
      sl.LoadFromFile(AFile);
      for k := 0 to sl.Count - 1 do
        if (Pos(':=', sl[k]) > 0) and (Pos('fsStayOnTop;', sl[k]) > 0) then Exit(True);
    finally
      sl.Free;
    end;
  end;

begin
  dir := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'source' + PathDelim;
  for i := 0 to High(Units) do
    Check(Units[i], Wins[i]);
  { and a popup window added later is not missed: these are all there is }
  files := FindAllFiles(dir, '*.pas', False);
  try
    for i := 0 to files.Count - 1 do
      if SetsStayOnTop(files[i]) then
        AssertTrue(ExtractFileName(files[i]) + ' makes a popup window this test does not check',
          Listed(ExtractFileName(files[i])));
  finally
    files.Free;
  end;
end;

initialization
  RegisterTest(TPopupGeomTest);
  RegisterTest(TPopupSmokeTest);
  RegisterTest(TPopupLevelTest);
end.
