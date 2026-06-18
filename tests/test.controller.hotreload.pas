unit test.controller.hotreload;
{ E23 (DX) hot-reload. Drives the headless-testable seam Controller.PollThemeFile
  directly (no GUI loop / no live TTimer): write a theme file, load it via ThemeFile,
  mutate the file (content + bumped mtime), and assert PollThemeFile reloads and the new
  value resolves; that an unchanged file does NOT reload; that HotReload=False is a no-op;
  and that a broken reload keeps the previous theme (fail-fast contract) without crashing. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller;

type
  TControllerHotReloadTest = class(TTestCase)
  private
    FPath: string;
    procedure WriteTheme(const AContent: string; ABumpAge: Boolean = True);
    function ButtonColor(c: TTyStyleController): TTyColor;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPollReloadsOnChange;
    procedure TestPollNoChangeNoReload;
    procedure TestHotReloadOffIsNoOp;
    procedure TestPollMissingFileNoRaiseNoReload;
    procedure TestBrokenReloadKeepsPreviousTheme;
    procedure TestPollBeforeAnyThemeFileIsNoOp;
  end;

implementation

const
  // Each variant has a DISTINCT byte length so the size half of the change detector
  // trips deterministically regardless of FileAge's coarse (1-2s) resolution — the
  // mtime bump in WriteTheme is then belt-and-braces, not the sole signal.
  cRed   = 'TyButton { color: #FF0000; }';
  cGreen = 'TyButton { color: #00FF00; border-width: 1px; }';
  cBlue  = 'TyButton { color: #0000FF; border-width: 2px; padding: 3px; }';
  cBroken = 'TyButton { color: var(--no-such-var); border: 4px; }';

procedure TControllerHotReloadTest.WriteTheme(const AContent: string; ABumpAge: Boolean);
var
  sl: TStringList;
  prevAge: LongInt;
begin
  prevAge := -1;
  if FileExists(FPath) then prevAge := FileAge(FPath);
  sl := TStringList.Create;
  try
    sl.Text := AContent;
    sl.SaveToFile(FPath);
  finally
    sl.Free;
  end;
  // FileAge resolution is coarse (~1-2s on FAT/NTFS via the packed-DOS path); a fast
  // rewrite within the same tick can land on the same stamp. Force a strictly-later
  // stamp so the (age) half of the change detector reliably trips even if the byte
  // count happened to be identical.
  if ABumpAge then
    FileSetDate(FPath, FileAge(FPath) + 2 + Ord(prevAge >= 0));
end;

function TControllerHotReloadTest.ButtonColor(c: TTyStyleController): TTyColor;
var s: TTyStyleSet;
begin
  s := c.Model.ResolveStyle('TyButton', '', []);
  Result := s.TextColor;
end;

procedure TControllerHotReloadTest.SetUp;
begin
  FPath := GetTempDir(False) + 'ty_hotreload_' + IntToStr(PtrUInt(Self)) + '.tycss';
end;

procedure TControllerHotReloadTest.TearDown;
begin
  if (FPath <> '') and FileExists(FPath) then
    DeleteFile(FPath);
end;

procedure TControllerHotReloadTest.TestPollReloadsOnChange;
var c: TTyStyleController;
begin
  WriteTheme(cRed);
  c := TTyStyleController.Create(nil);
  try
    c.HotReload := True;
    c.ThemeFile := FPath;
    AssertEquals('initial red', Integer(TyRGB($FF, $00, $00)), Integer(ButtonColor(c)));
    // Change the file on disk, then poll: it must reload and the new value resolve.
    WriteTheme(cGreen);
    AssertTrue('PollThemeFile reports a reload', c.PollThemeFile);
    AssertEquals('reloaded green', Integer(TyRGB($00, $FF, $00)), Integer(ButtonColor(c)));
    // A second change (also size-different) reloads again.
    WriteTheme(cBlue);
    AssertTrue('PollThemeFile reloads second change', c.PollThemeFile);
    AssertEquals('reloaded blue', Integer(TyRGB($00, $00, $FF)), Integer(ButtonColor(c)));
  finally
    c.Free;
  end;
end;

procedure TControllerHotReloadTest.TestPollNoChangeNoReload;
var c: TTyStyleController;
begin
  WriteTheme(cRed);
  c := TTyStyleController.Create(nil);
  try
    c.HotReload := True;
    c.ThemeFile := FPath;
    // No file mutation between polls -> no reload (returns False), value unchanged.
    AssertFalse('no change -> no reload', c.PollThemeFile);
    AssertFalse('still no change on a second poll', c.PollThemeFile);
    AssertEquals('still red', Integer(TyRGB($FF, $00, $00)), Integer(ButtonColor(c)));
  finally
    c.Free;
  end;
end;

procedure TControllerHotReloadTest.TestHotReloadOffIsNoOp;
var c: TTyStyleController;
begin
  WriteTheme(cRed);
  c := TTyStyleController.Create(nil);
  try
    // HotReload left at its default (False).
    AssertFalse('HotReload default is False', c.HotReload);
    c.ThemeFile := FPath;
    AssertEquals('initial red', Integer(TyRGB($FF, $00, $00)), Integer(ButtonColor(c)));
    // Mutate the file; with HotReload off, PollThemeFile must be an inert no-op.
    WriteTheme(cGreen);
    AssertFalse('HotReload off -> Poll is a no-op', c.PollThemeFile);
    AssertEquals('unchanged (still red) while off', Integer(TyRGB($FF, $00, $00)), Integer(ButtonColor(c)));
  finally
    c.Free;
  end;
end;

procedure TControllerHotReloadTest.TestPollMissingFileNoRaiseNoReload;
var c: TTyStyleController;
begin
  WriteTheme(cRed);
  c := TTyStyleController.Create(nil);
  try
    c.HotReload := True;
    c.ThemeFile := FPath;
    // Delete the file out from under the watch (mid-save unlink). Poll must skip
    // silently (no raise, no reload) and keep the previously loaded theme.
    DeleteFile(FPath);
    AssertFalse('missing file -> no reload, no raise', c.PollThemeFile);
    AssertEquals('kept previous (red) on missing file', Integer(TyRGB($FF, $00, $00)), Integer(ButtonColor(c)));
    // When the file reappears with new content, the next poll picks it up.
    WriteTheme(cGreen);
    AssertTrue('reappeared file reloads', c.PollThemeFile);
    AssertEquals('now green', Integer(TyRGB($00, $FF, $00)), Integer(ButtonColor(c)));
  finally
    c.Free;
  end;
end;

procedure TControllerHotReloadTest.TestBrokenReloadKeepsPreviousTheme;
var c: TTyStyleController;
begin
  WriteTheme(cRed);
  c := TTyStyleController.Create(nil);
  try
    c.HotReload := True;
    c.ThemeFile := FPath;
    AssertEquals('initial red', Integer(TyRGB($FF, $00, $00)), Integer(ButtonColor(c)));
    // Replace with a theme that fails validation (undefined var). The reload must be
    // caught: previous theme stays, no crash, Poll returns False (no successful reload).
    WriteTheme(cBroken);
    AssertFalse('broken reload reports no successful reload', c.PollThemeFile);
    AssertEquals('kept previous (red) after broken reload', Integer(TyRGB($FF, $00, $00)), Integer(ButtonColor(c)));
    // The broken stamp was recorded, so re-polling the SAME broken content does nothing.
    AssertFalse('broken content not retried every tick', c.PollThemeFile);
    // A subsequent GOOD save reloads normally.
    WriteTheme(cGreen);
    AssertTrue('good save after broken reloads', c.PollThemeFile);
    AssertEquals('recovered to green', Integer(TyRGB($00, $FF, $00)), Integer(ButtonColor(c)));
  finally
    c.Free;
  end;
end;

procedure TControllerHotReloadTest.TestPollBeforeAnyThemeFileIsNoOp;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    c.HotReload := True;
    // No ThemeFile set yet -> nothing to watch; Poll is a no-op (returns False, no raise).
    AssertFalse('no ThemeFile -> Poll no-op', c.PollThemeFile);
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TControllerHotReloadTest);
end.
