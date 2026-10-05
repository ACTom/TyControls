unit test.themebuilder.editkit;
{ TTyCssEditKit (theme builder, phase 1): the tycss SynEdit setup moved out of the
  design-time StyleOverride dialog so the theme builder can share it. Checked headless on a
  parentless TSynEdit: what Attach sets up, completion from the text BEFORE the caret (not
  the whole document), the host's OnChange still running, format-on-line-leave and its
  switch, surviving the editor's destruction -- and, by reading the sources, that the unit
  pulls in no IDE unit and that the dialog really uses it. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, SynEdit, SynEditTypes,
  tyControls.Design.CssEditKit;

type
  TTbCssEditKitTests = class(TTestCase)
  private
    FEdit: TSynEdit;
    FKit: TTyCssEditKit;
    FChanges: Integer;
    procedure CountChange(Sender: TObject);
    function ReadRepoFile(const ARel: string): string;
    function UsesClauses(const ASource: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAttachSetsTheEditorUp;
    procedure TestCompletionReadsTheTextBeforeTheCaret;
    procedure TestCompletionAtTheStartOffersTypeKeys;
    procedure TestTheHostOnChangeStillRuns;
    procedure TestLeavingALineTidiesItUnlessTurnedOff;
    procedure TestTheStatusHandlerIsRegistered;
    procedure TestTheEditorCanGoFirst;
    procedure TestTheUnitNeedsNoIde;
    procedure TestTheDialogUsesTheKit;
    { acceptance feedback }
    procedure TestTheTextIsSmooth;
  end;

implementation

uses
  Forms, Graphics, SynHighlighterCss, tyControls.Css.Complete, test.themebuilder.golden;

{ TSynCompletion builds its popup form when it is created, and that needs the widgetset
  (the tool and the IDE always have one; this console runner does not until asked). Asked
  once, the first time a test here needs it -- these suites run after the rest. }
var
  GWidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if GWidgetSetReady then Exit;
  Forms.Application.Initialize;
  GWidgetSetReady := True;
end;

procedure TTbCssEditKitTests.SetUp;
begin
  NeedWidgetSet;
  FEdit := TSynEdit.Create(nil);
  FKit := TTyCssEditKit.Create(nil);
  FChanges := 0;
end;

procedure TTbCssEditKitTests.TearDown;
begin
  FreeAndNil(FKit);
  FreeAndNil(FEdit);
end;

procedure TTbCssEditKitTests.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

function TTbCssEditKitTests.ReadRepoFile(const ARel: string): string;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(TbRepoDir + ARel);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

{ the text of every 'uses ... ;' clause, lower case, comments not stripped (the unit has
  none inside its uses) }
function TTbCssEditKitTests.UsesClauses(const ASource: string): string;
var
  lo: string;
  p, q: Integer;
begin
  Result := '';
  lo := LowerCase(ASource);
  p := Pos(#10'uses', lo);
  while p > 0 do
  begin
    q := p + 5;
    while (q <= Length(lo)) and (lo[q] <> ';') do Inc(q);
    Result := Result + ' ' + Copy(lo, p + 5, q - p - 5) + ',';
    Delete(lo, 1, q);
    p := Pos(#10'uses', lo);
  end;
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, ' ', '', [rfReplaceAll]);
end;

procedure TTbCssEditKitTests.TestAttachSetsTheEditorUp;
begin
  FEdit.Options := FEdit.Options + [eoScrollPastEol];
  FKit.Attach(FEdit, True);
  AssertTrue('K1: the CSS highlighter', FEdit.Highlighter is TSynCssSyn);
  AssertTrue('K1: the kit''s highlighter', FEdit.Highlighter = FKit.Highlighter);
  AssertTrue('K1: completion on this editor', FKit.Completion.Editor = FEdit);
  AssertEquals('K1: Ctrl+Space', 16416, FKit.Completion.ShortCut);
  AssertFalse('K1: no scrolling past the line end', eoScrollPastEol in FEdit.Options);
  AssertTrue('K1: FormatOnLineLeave defaults on', FKit.FormatOnLineLeave);
  AssertTrue('K1: AutoComplete defaults on', FKit.AutoComplete);
end;

procedure TTbCssEditKitTests.TestCompletionReadsTheTextBeforeTheCaret;
var
  items: TStrings;
begin
  FKit.Attach(FEdit, True);
  { after the caret the rule closes and a selector starts: the whole document ends outside
    any rule, the text before the caret inside one }
  FEdit.Lines.Text := 'TyButton {'#10'  bac'#10'}'#10'TyE';
  FEdit.LogicalCaretXY := Point(6, 2);
  AssertEquals('the caret is after "bac"', '  bac', Copy(FEdit.Lines[1], 1, 5));
  AssertEquals('K2: the text before the caret', 'TyButton {' + LineEnding + '  bac',
    FKit.TextBeforeCaret);
  FKit.FillCompletion;
  items := FKit.Completion.ItemList;
  AssertTrue('K2: a property is offered', items.IndexOf('background') >= 0);
  AssertTrue('K2: no typeKey inside a rule', items.IndexOf('TyButton') < 0);
end;

procedure TTbCssEditKitTests.TestCompletionAtTheStartOffersTypeKeys;
begin
  FKit.Attach(FEdit, True);
  FEdit.Lines.Text := 'TyButton {'#10'  bac';
  FEdit.LogicalCaretXY := Point(1, 1);
  FKit.FillCompletion;
  AssertTrue('K3: a typeKey before any rule', FKit.Completion.ItemList.IndexOf('TyButton') >= 0);
end;

procedure TTbCssEditKitTests.TestTheHostOnChangeStillRuns;
var
  prev: TNotifyEvent;
begin
  FEdit.OnChange := @CountChange;
  prev := FEdit.OnChange;
  FKit.Attach(FEdit, True);
  AssertTrue('the kit took OnChange', TMethod(FEdit.OnChange).Code <> TMethod(prev).Code);
  FEdit.OnChange(FEdit);
  AssertEquals('K4: the host''s OnChange ran once', 1, FChanges);
  FKit.Detach;
  AssertTrue('K4: Detach gives OnChange back',
    (TMethod(FEdit.OnChange).Code = TMethod(prev).Code)
    and (TMethod(FEdit.OnChange).Data = TMethod(prev).Data));
end;

procedure TTbCssEditKitTests.TestLeavingALineTidiesItUnlessTurnedOff;
const
  cLine = 'TyButton{color:red}';
var
  tidy: string;
begin
  tidy := TyCssFormatLine(cLine);
  AssertTrue('the line is untidy to begin with', tidy <> cLine);
  FKit.Attach(FEdit, True);
  FEdit.Lines.Text := cLine + #10'x';
  FEdit.CaretY := 1;
  FKit.HandleStatusChange(FEdit, [scCaretY]);
  FEdit.CaretY := 2;
  FKit.HandleStatusChange(FEdit, [scCaretY]);
  AssertEquals('K5: the line left behind is tidied', tidy, FEdit.Lines[0]);

  FEdit.Lines.Text := cLine + #10'x';
  FKit.FormatOnLineLeave := False;
  FEdit.CaretY := 1;
  FKit.HandleStatusChange(FEdit, [scCaretY]);
  FEdit.CaretY := 2;
  FKit.HandleStatusChange(FEdit, [scCaretY]);
  AssertEquals('K5: switched off, the line stays as written', cLine, FEdit.Lines[0]);
end;

procedure TTbCssEditKitTests.TestTheStatusHandlerIsRegistered;
const
  cLine = 'TyButton{color:red}';
begin
  { the real path: moving the caret reaches the kit through SynEdit's handler list. SynEdit
    records a caret move and reports it with the next status change (a keystroke's paint
    lock ends one); toggling ReadOnly is a status change that flushes it here. }
  FEdit.Lines.Text := cLine + #10'x';
  FEdit.CaretY := 1;
  FKit.Attach(FEdit, True);
  FEdit.CaretY := 2;
  FEdit.ReadOnly := True;
  FEdit.ReadOnly := False;
  AssertEquals('K5: moving the caret off the line tidied it',
    TyCssFormatLine(cLine), FEdit.Lines[0]);
end;

procedure TTbCssEditKitTests.TestTheEditorCanGoFirst;
begin
  FKit.Attach(FEdit, True);
  FreeAndNil(FEdit);
  AssertTrue('K6: the kit forgot the editor', FKit.Edit = nil);
  FreeAndNil(FKit);   { must not touch the freed editor }
end;

procedure TTbCssEditKitTests.TestTheUnitNeedsNoIde;
const
  cIde: array[0..5] of string = ('propedits', 'componenteditors', 'lazideintf', 'ideintf',
    'formeditingintf', 'tycontrols.dialogs');
var
  u: string;
  i: Integer;
begin
  u := UsesClauses(ReadRepoFile('designtime' + PathDelim + 'tyControls.Design.CssEditKit.pas'));
  AssertTrue('the uses clauses were found: ' + u, Pos(',synedit,', ',' + u) > 0);
  for i := 0 to High(cIde) do
    AssertTrue('K7: no ' + cIde[i] + ' in ' + u, Pos(',' + cIde[i] + ',', ',' + u) = 0);
end;

procedure TTbCssEditKitTests.TestTheDialogUsesTheKit;
var
  lpk, dlg: string;
begin
  lpk := ReadRepoFile('tycontrols_dt.lpk');
  AssertTrue('K8: the package lists the unit',
    Pos('<UnitName Value="tyControls.Design.CssEditKit"/>', lpk) > 0);
  dlg := ReadRepoFile('designtime' + PathDelim + 'tyControls.Design.Css.Editor.pas');
  AssertTrue('K8: the dialog builds a kit', Pos('TTyCssEditKit.Create', dlg) > 0);
  AssertTrue('K8: and attaches it', Pos('.Attach(', dlg) > 0);
  AssertTrue('K8: no completion of its own', Pos('TSynCompletion.Create', dlg) = 0);
  AssertTrue('K8: no highlighter of its own', Pos('TSynCssSyn.Create', dlg) = 0);
end;

{ The editor's text is smooth (SynEdit's own default is fqNonAntialiased: pixel text) and in a
  code face: Consolas on Windows where it is installed (it is on every Windows since Vista),
  at 10 pt -- a size in points, which follows the PPI. A host that chose its own face keeps it;
  the quality is set either way. }
procedure TTbCssEditKitTests.TestTheTextIsSmooth;
var
  own: TSynEdit;
  kit: TTyCssEditKit;
begin
  FKit.Attach(FEdit, False);
  {$IFDEF MSWINDOWS}
  AssertTrue('ClearType', FEdit.Font.Quality = fqCleartypeNatural);
  AssertEquals('Consolas', 'Consolas', FEdit.Font.Name);
  {$ELSE}
  AssertTrue('antialiased', FEdit.Font.Quality = fqAntialiased);
  {$ENDIF}
  AssertTrue('the shared quality', FEdit.Font.Quality = TyCssEditFontQuality);
  AssertEquals('the shared face', TyCssEditFontName, FEdit.Font.Name);
  AssertEquals('10 pt', 10, FEdit.Font.Size);
  own := TSynEdit.Create(nil);
  kit := TTyCssEditKit.Create(nil);
  try
    own.Font.Name := 'Lucida Console';
    own.Font.Size := 13;
    kit.Attach(own, True);
    AssertEquals('a face of the host''s own is kept', 'Lucida Console', own.Font.Name);
    AssertEquals('and its size', 13, own.Font.Size);
    AssertTrue('smooth all the same', own.Font.Quality = TyCssEditFontQuality);
  finally
    kit.Free;
    own.Free;
  end;
end;

initialization
  RegisterTest(TTbCssEditKitTests);
end.
