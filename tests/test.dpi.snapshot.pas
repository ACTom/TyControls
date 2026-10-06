unit test.dpi.snapshot;
{ A PICTURE of a designed form at a simulated scaling -- a diagnostic, not an assertion.

  Everything else in the DPI suites compares numbers. This one produces something a person
  can look at: an example's form file is read through a real TReader, the screen is
  simulated the way tests/test.dpi.measurefont simulates it, LCL's own DPI pass is run over
  the form, and the whole control tree is painted into one bitmap.

  IT DOES NOTHING UNLESS ASKED. Set TY_SNAPSHOT_DIR to a directory and run this suite; the
  pictures land there as PNG. Without the variable every test here passes immediately, so
  the suite costs an ordinary run nothing and leaves no files behind.

  WHAT THE PICTURE IS NOT. This runner has no window handles and therefore no align engine:
  a control keeps the bounds its form file gave it, scaled by the pass. That is what a real
  form does to everything that is not anchored to a moving edge, and it is enough to see a
  row of buttons running into the next one -- but it is not a screenshot. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Forms, Graphics, LCLType, LMessages, LResources,
  FileUtil,
  Menus, ExtCtrls, StdCtrls, ComCtrls, Dialogs, ActnList, DB,
  fpcunit, testregistry,
  test.version, test.designregistry, test.dpi.support,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Base, tyControls.Form, tyControls.Edit, tyControls.Memo, tyControls.ListBox,
  tyControls.Dialogs, tyControls.Dialogs.Color, tyControls.Dialogs.Font,
  tyControls.Dialogs.Find, tyControls.Dialogs.Progress, tyControls.Dialogs.About,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.FileDialog,
  tyControls.Dialogs.IconBrowser;

type
  TTyDpiSnapshotTest = class(TTestCase)
  private
    FSaveX, FSaveY: Integer;
    FSaveScaled: Boolean;
    FSaveFontName: string;
    FDir: string;
    FLog: TStringList;
    procedure SimulateScreen(APPI: Integer);
    function LoadExample(const ARelativeLfm: string; APPI: Integer): TTyForm;
    procedure Save(AForm: TCustomForm; const AName: string);
    function BuildDialog(AIndex: Integer; out AName: string): TTyDialog;
    procedure ReaderError(Reader: TReader; const AMessage: string; var Handled: Boolean);
    procedure ReaderFindMethod(Reader: TReader; const AMethodName: string;
      var Address: CodePointer; var Error: Boolean);
    procedure ReaderFindClass(Reader: TReader; const AClassName: string;
      var ComponentClass: TComponentClass);
    procedure ReaderPropertyNotFound(Reader: TReader; Instance: TPersistent;
      var PropName: string; IsPath: Boolean; var Handled, Skip: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestExamples;
    procedure TestDialogs;
  end;

implementation

type
  { Stands in for a class this runner never registered (a main menu, a timer, an image
    list): the form still reads, and what could not be built is simply not in the picture. }
  TSnapshotStandIn = class(TComponent);

  { Resize is protected: it is what places a dialog's buttons and content in the size the
    dialog settled at. }
  TSnapshotDialogAccess = class(TTyDialog);

{ ===== harness ============================================================== }

procedure TTyDpiSnapshotTest.SetUp;
begin
  inherited SetUp;
  FSaveX := ScreenInfo.PixelsPerInchX;
  FSaveY := ScreenInfo.PixelsPerInchY;
  FSaveScaled := Application.Scaled;
  FSaveFontName := TyFallbackFontName;
  FDir := GetEnvironmentVariable('TY_SNAPSHOT_DIR');
  FLog := TStringList.Create;
  TyRegisterBuiltinThemes;
  { The runner keeps the font name EMPTY for the sake of its pixel tests, and an empty name
    sends BGRA down the path that drops a caption's last glyph. A picture is for looking at,
    so it gets the font an application would have been given. }
  if (FDir <> '') and (Screen.SystemFont <> nil) and (Screen.SystemFont.Name <> '')
     and (Screen.SystemFont.Name <> 'default') then
    TyFallbackFontName := Screen.SystemFont.Name
  else if FDir <> '' then
    TyFallbackFontName := 'Segoe UI';
end;

procedure TTyDpiSnapshotTest.TearDown;
begin
  if (FDir <> '') and (FLog.Count > 0) then
    FLog.SaveToFile(IncludeTrailingPathDelimiter(FDir) + 'snapshot-log.txt');
  FLog.Free;
  TyFallbackFontName := FSaveFontName;
  Application.Scaled := FSaveScaled;
  ScreenInfo.PixelsPerInchX := FSaveX;
  ScreenInfo.PixelsPerInchY := FSaveY;
  Screen.UpdateScreen;
  TyInvalidateTextMeasureCache;
  inherited TearDown;
end;

procedure TTyDpiSnapshotTest.SimulateScreen(APPI: Integer);
begin
  TyTestSimulateScreen(APPI);
end;

procedure TTyDpiSnapshotTest.ReaderError(Reader: TReader; const AMessage: string;
  var Handled: Boolean);
begin
  FLog.Add('reader: ' + AMessage);
  Handled := True;
end;

procedure TTyDpiSnapshotTest.ReaderFindMethod(Reader: TReader; const AMethodName: string;
  var Address: CodePointer; var Error: Boolean);
begin
  { The example's event handlers live in its own form class, which is not linked here. }
  Address := nil;
  Error := False;
end;

procedure TTyDpiSnapshotTest.ReaderFindClass(Reader: TReader; const AClassName: string;
  var ComponentClass: TComponentClass);
var
  cls: TPersistentClass;
begin
  if ComponentClass <> nil then Exit;
  cls := GetClass(AClassName);
  if (cls <> nil) and cls.InheritsFrom(TComponent) then
    ComponentClass := TComponentClass(cls)
  else
  begin
    FLog.Add('class not registered, stood in for: ' + AClassName);
    ComponentClass := TSnapshotStandIn;
  end;
end;

procedure TTyDpiSnapshotTest.ReaderPropertyNotFound(Reader: TReader; Instance: TPersistent;
  var PropName: string; IsPath: Boolean; var Handled, Skip: Boolean);
begin
  Handled := True;
  Skip := True;
end;

function TTyDpiSnapshotTest.LoadExample(const ARelativeLfm: string;
  APPI: Integer): TTyForm;
var
  txt: TFileStream;
  bin: TMemoryStream;
  rd: TReader;
begin
  { Off while the form is created, so that AfterConstruction does not run a pass over the
    empty form; on for the read, because TCustomForm.Loaded only repairs the design fonts of
    a scaled application. See TestAFormDesignedAt96... in tests/test.dpi.measurefont. }
  Application.Scaled := False;
  SimulateScreen(APPI);
  Result := TTyForm.CreateNew(nil);
  Result.Font.PixelsPerInch := 96;
  Application.Scaled := True;
  txt := TFileStream.Create(RepoRoot + ARelativeLfm, fmOpenRead or fmShareDenyNone);
  bin := TMemoryStream.Create;
  try
    LRSObjectTextToBinary(txt, bin);
    bin.Position := 0;
    rd := TReader.Create(bin, 4096);
    try
      rd.OnError := @ReaderError;
      rd.OnFindMethod := @ReaderFindMethod;
      rd.OnFindComponentClass := @ReaderFindClass;
      rd.OnPropertyNotFound := @ReaderPropertyNotFound;
      rd.ReadRootComponent(Result);
    finally
      rd.Free;
    end;
  finally
    bin.Free;
    txt.Free;
  end;
  if APPI <> 96 then
    Result.AutoAdjustLayout(lapAutoAdjustForDPI, 96, APPI,
      Result.Width, MulDiv(Result.Width, APPI, 96));
  { Twice: a container's own layout can restyle its children (a flat tool bar hands its
    tools the ghost class), which moves what they would prefer to be. A real form settles
    the same way, over as many passes as it takes. }
  TyTestSettle(Result);
  TyTestSettle(Result);
end;

procedure TTyDpiSnapshotTest.Save(AForm: TCustomForm; const AName: string);
var
  bmp: TBitmap;
  png: TPortableNetworkGraphic;
  lst: TStringList;
begin
  lst := TStringList.Create;
  try
    { The same tree as numbers, so that two scalings can be compared control by control
      instead of by eye. }
    TyTestListTree(AForm, lst);
    lst.SaveToFile(IncludeTrailingPathDelimiter(FDir) + AName + '.txt');
  finally
    lst.Free;
  end;
  bmp := TBitmap.Create;
  png := TPortableNetworkGraphic.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(AForm.Width, AForm.Height);
    bmp.Canvas.Brush.Color := TColor($00FF00FF);
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    TyTestPaintTree(AForm, bmp, FLog);
    png.Assign(bmp);
    png.SaveToFile(IncludeTrailingPathDelimiter(FDir) + AName + '.png');
  finally
    png.Free;
    bmp.Free;
  end;
end;

{ ===== the pictures ========================================================= }

procedure TTyDpiSnapshotTest.TestExamples;
const
  CPPIs: array[0..2] of Integer = (96, 144, 168);
var
  e, p: Integer;
  frm: TTyForm;
  nm: string;
  found: TStringList;
  CExamples: array of string;
begin
  if FDir = '' then Exit;
  { Only when a picture was asked for: the class registry is process-wide, and a suite
    that did nothing must leave it as it found it. }
  RegisterClasses([TMainMenu, TPopupMenu, TMenuItem, TTimer, TPanel, TLabel, TButton,
    TEdit, TMemo, TImageList, TActionList, TAction, TTreeView, TListView, TListBox,
    TComboBox, TCheckBox, TRadioButton, TGroupBox, TPageControl, TTabSheet,
    { examples/dbcontrols: its data-aware controls point at these by type, so a stand-in would
      reach their DataSource setter as the wrong class. }
    TDataSource]);
  { Every example there is: a form file is the only thing this needs from one. }
  CExamples := nil;
  found := FindAllFiles(RepoRoot + 'examples', '*.lfm', True);
  try
    found.Sort;
    SetLength(CExamples, found.Count);
    for e := 0 to found.Count - 1 do
      CExamples[e] := StringReplace(
        ExtractRelativePath(ExpandFileName(RepoRoot), ExpandFileName(found[e])),
        '\', '/', [rfReplaceAll]);
  finally
    found.Free;
  end;
  for e := 0 to High(CExamples) do
  begin
    { TY_SNAPSHOT_ONLY narrows the run to the examples whose path contains it. }
    if (GetEnvironmentVariable('TY_SNAPSHOT_ONLY') <> '')
       and (Pos(GetEnvironmentVariable('TY_SNAPSHOT_ONLY'), CExamples[e]) = 0) then Continue;
    if Pos('/lib/', CExamples[e]) > 0 then Continue;   // build-output copies
    if not FileExists(RepoRoot + CExamples[e]) then
    begin
      FLog.Add('no such example: ' + CExamples[e]);
      Continue;
    end;
    for p := 0 to High(CPPIs) do
    begin
      frm := nil;
      try
        try
          frm := LoadExample(CExamples[e], CPPIs[p]);
          nm := StringReplace(ChangeFileExt(CExamples[e], ''), '/', '-', [rfReplaceAll]);
          Save(frm, Format('%s-%d', [nm, CPPIs[p]]));
        except
          on Ex: Exception do
            FLog.Add(Format('%s at %d: %s: %s',
              [CExamples[e], CPPIs[p], Ex.ClassName, Ex.Message]));
        end;
      finally
        frm.Free;
      end;
    end;
  end;
end;

function TTyDpiSnapshotTest.BuildDialog(AIndex: Integer; out AName: string): TTyDialog;
var
  e: TTyEdit;
  m: TTyMemo;
  l: TTyListBox;
  items: TStringList;
  fnt: TFont;
begin
  Result := nil;
  AName := '';
  case AIndex of
    0: begin
         AName := 'message';
         Result := TyBuildMessageDialog('The file has been changed on disk. Reload it and lose'
           + ' the changes made here, or keep editing this copy?', mtConfirmation,
           [mbYes, mbNo, mbCancel]);
       end;
    1: begin
         AName := 'input';
         Result := TyBuildInputDialog('Rename', 'New name:', 'old.txt', e);
       end;
    2: begin
         AName := 'text';
         Result := TyBuildTextDialog('Notes', 'Anything to add?', 'one' + LineEnding + 'two', m);
       end;
    3: begin
         AName := 'selectvalue';
         items := TStringList.Create;
         try
           items.Add('Alpha');
           items.Add('Beta');
           items.Add('Gamma');
           Result := TyBuildSelectValueDialog('Pick one', 'Which?', items, 1, l);
         finally
           items.Free;
         end;
       end;
    4: begin
         AName := 'color';
         Result := TyBuildColorDialog('Select Color', TyRGB(59, 130, 246));
       end;
    5: begin
         AName := 'font';
         items := TStringList.Create;
         fnt := TFont.Create;
         try
           items.Add('Arial');
           items.Add('Courier New');
           items.Add('Tahoma');
           Result := TyBuildFontDialog('Font', fnt, items);
         finally
           fnt.Free;
           items.Free;
         end;
       end;
    6: begin
         AName := 'find';
         Result := TTyFindForm.CreateNew(nil, 0);
         TTyFindForm(Result).Build(False);
       end;
    7: begin
         AName := 'replace';
         Result := TTyFindForm.CreateNew(nil, 0);
         TTyFindForm(Result).Build(True);
       end;
    8: begin
         AName := 'progress';
         Result := TTyProgressForm.CreateNew(nil, 0);
         TTyProgressForm(Result).Build(True);
         TTyProgressForm(Result).UpdateView(40, 0, 100, 'Copying 40 of 100...');
       end;
    9: begin
         AName := 'about';
         Result := TyBuildAboutDialog('About', 'TyControls', '3.0.0', 'Themed controls for'
           + ' Lazarus.' + LineEnding + 'One look on every platform.', '(c) the authors',
           'MIT', 'https://example.invalid');
       end;
    10: begin
          AName := 'selectpath';
          Result := TyBuildSelectPathDialog('Select a folder', '');
        end;
    11: begin
          AName := 'open';
          Result := TyBuildFileDialog(False, True, 'Open');
        end;
    12: begin
          AName := 'iconbrowser';
          Result := TyBuildIconBrowserDialog('Icons', nil);
        end;
  end;
end;

procedure TTyDpiSnapshotTest.TestDialogs;
const
  CPPIs: array[0..2] of Integer = (96, 144, 168);
var
  p, k: Integer;
  d: TTyDialog;
  nm: string;
begin
  if FDir = '' then Exit;
  for k := 0 to 12 do
    for p := 0 to High(CPPIs) do
    begin
      { A dialog is built by code AFTER its form was constructed, so the form is at the
        screen's PPI by then. An unscaled runner never runs the pass that gets it there; the
        font the form was born with says the same thing. }
      Application.Scaled := False;
      SimulateScreen(CPPIs[p]);
      d := nil;
      nm := IntToStr(k);
      try
        try
          d := BuildDialog(k, nm);
          if d = nil then Continue;
          TyTestSettle(d);
          TSnapshotDialogAccess(d).Resize;
          TyTestSettle(d);
          Save(d, Format('dialog-%s-%d', [nm, CPPIs[p]]));
        except
          on Ex: Exception do
            FLog.Add(Format('dialog %s at %d: %s: %s',
              [nm, CPPIs[p], Ex.ClassName, Ex.Message]));
        end;
      finally
        d.Free;
      end;
    end;
end;

initialization
  RegisterTest(TTyDpiSnapshotTest);

end.
