unit tyControls.Design.CssEditKit;
{ The SynEdit setup the tycss editors share (spec 4): the CSS highlighter, completion from
  the tycss catalog (Ctrl+Space, and as an identifier is typed), the caret kept on real
  text, and optionally the line the caret leaves tidied. Used by the design-time
  StyleOverride dialog and by tools/themebuilder. No IDE units.

  The kit does not build the editor: it attaches to a TSynEdit that exists already (the
  dialog creates one in code, the theme builder streams one from its .lfm). It hooks the
  editor through SynEdit's handler lists (status changes, key presses), so the host keeps
  OnStatusChange and OnKeyPress for itself; OnChange has no list, so the kit takes it and
  calls the one the editor already had after its own work. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Graphics, SynEdit, SynEditTypes, SynCompletion, SynHighlighterCss;

{ The monospace face the tycss editors use: Consolas on Windows (Courier New where it is not
  installed), Menlo on macOS, DejaVu Sans Mono elsewhere (fontconfig's "monospace" where that
  is missing too). }
function TyCssEditFontName: string;
{ Smooth text: ClearType on Windows, antialiased elsewhere. SynEdit's own default is
  fqNonAntialiased -- pixel text, the one control in the window that looked like it. }
function TyCssEditFontQuality: TFontQuality;

type
  TTyCssEditKit = class(TComponent)
  private
    FEdit: TSynEdit;
    FComplete: TSynCompletion;
    FHighlighter: TSynCssSyn;
    FSelectorMode: Boolean;
    FFormatOnLineLeave: Boolean;
    FAutoComplete: Boolean;
    FFormatting: Boolean;             // reentrancy guard for the in-place line format
    FWantComplete: Boolean;           // an ident key was typed -> pop completion after the insert
    FLastLine: Integer;               // for format-on-line-leave
    FPrevOnChange: TNotifyEvent;
    procedure EditChange(Sender: TObject);
    procedure BeforeKeyPress(Sender: TObject; var Key: char);
    procedure CompletionExecute(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { configure AEdit; an OnChange it already has keeps running, after the kit's }
    procedure Attach(AEdit: TSynEdit; ASelectorMode: Boolean);
    procedure Detach;
    { the lines above the caret and the caret line up to the caret }
    function TextBeforeCaret: string;
    { what Ctrl+Space puts in Completion.ItemList }
    procedure FillCompletion;
    { the kit's own status handler (registered on the edit); public FOR THE TESTS }
    procedure HandleStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    property Edit: TSynEdit read FEdit;
    property Highlighter: TSynCssSyn read FHighlighter;
    property Completion: TSynCompletion read FComplete;
    property SelectorMode: Boolean read FSelectorMode write FSelectorMode;
  published
    { tidy the line the caret just left into 'prop: value;' form (the design-time dialog);
      the theme builder turns it off -- theme files keep their own alignment }
    property FormatOnLineLeave: Boolean read FFormatOnLineLeave write FFormatOnLineLeave default True;
    { pop the completion list as an identifier is typed (Ctrl+Space works either way) }
    property AutoComplete: Boolean read FAutoComplete write FAutoComplete default True;
  end;

implementation

uses
  Math, Forms, tyControls.Css.Complete, tyControls.FontFamilies;

{ installed, by the library's one list of installed families (TyGetFontFamilies) }
function FontInstalled(const AName: string): Boolean;
var
  families: TStringList;
begin
  if Screen = nil then Exit(False);
  families := TStringList.Create;
  try
    TyGetFontFamilies(families, False);
    Result := families.IndexOf(AName) >= 0;
  finally
    families.Free;
  end;
end;

function TyCssEditFontName: string;
begin
  {$IF DEFINED(MSWINDOWS)}
  if FontInstalled('Consolas') then Result := 'Consolas' else Result := 'Courier New';
  {$ELSEIF DEFINED(DARWIN)}
  Result := 'Menlo';
  {$ELSE}
  if FontInstalled('DejaVu Sans Mono') then Result := 'DejaVu Sans Mono' else Result := 'monospace';
  {$ENDIF}
end;

function TyCssEditFontQuality: TFontQuality;
begin
  {$IFDEF MSWINDOWS}
  Result := fqCleartypeNatural;
  {$ELSE}
  Result := fqAntialiased;
  {$ENDIF}
end;

constructor TTyCssEditKit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFormatOnLineLeave := True;
  FAutoComplete := True;
  FLastLine := 1;
end;

destructor TTyCssEditKit.Destroy;
begin
  Detach;
  inherited Destroy;
end;

procedure TTyCssEditKit.Attach(AEdit: TSynEdit; ASelectorMode: Boolean);
begin
  Detach;
  if AEdit = nil then Exit;
  FEdit := AEdit;
  FSelectorMode := ASelectorMode;
  FEdit.FreeNotification(Self);
  { Clamp the caret to real text: clicking past a line's end puts it AT the last
    character, not in virtual space past it. }
  FEdit.Options := FEdit.Options - [eoScrollPastEol];
  { Smooth monospace text. A font the host has not chosen (still SynEdit's default face) gets
    the platform's code face at 10 pt -- in points, so it follows the font's PPI as a height
    in pixels would not. A host with its own face (the theme builder takes it from its
    theme) keeps it; the quality is set either way. }
  if FEdit.Font.Name = SynDefaultFontName then
  begin
    FEdit.Font.Name := TyCssEditFontName;
    FEdit.Font.Size := 10;
  end;
  FEdit.Font.Quality := TyCssEditFontQuality;
  { tycss is a CSS dialect: the stock CSS highlighter colours comments, selectors,
    properties, values, braces and hex well enough; --tokens and darken() fall back to
    its identifier / function colouring. }
  FHighlighter := TSynCssSyn.Create(Self);
  FEdit.Highlighter := FHighlighter;
  FComplete := TSynCompletion.Create(Self);
  FComplete.Editor := FEdit;
  FComplete.OnExecute := @CompletionExecute;
  FComplete.ShortCut := 16416;   { Ctrl+Space }
  { Typing any of these closes the popup (finished the token). Esc and selecting are built in. }
  FComplete.EndOfTokenChr := '{}()[]:;,+*/\ ''"=<>!%';
  FPrevOnChange := FEdit.OnChange;
  FEdit.OnChange := @EditChange;
  FEdit.RegisterStatusChangedHandler(@HandleStatusChange, [scCaretY]);
  FEdit.RegisterBeforeKeyPressHandler(@BeforeKeyPress);
  FLastLine := FEdit.CaretY;
end;

procedure TTyCssEditKit.Detach;
begin
  if FEdit = nil then Exit;
  FEdit.UnRegisterStatusChangedHandler(@HandleStatusChange);
  FEdit.UnregisterBeforeKeyPressHandler(@BeforeKeyPress);
  FEdit.OnChange := FPrevOnChange;
  FPrevOnChange := nil;
  if FEdit.Highlighter = FHighlighter then
    FEdit.Highlighter := nil;
  FreeAndNil(FComplete);
  FreeAndNil(FHighlighter);
  FEdit.RemoveFreeNotification(Self);
  FEdit := nil;
end;

procedure TTyCssEditKit.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FEdit) and (FEdit <> nil) then
  begin
    { the editor is going away: do not touch it again. The completion still points at it
      and goes with the kit (or with the next Attach). }
    FEdit := nil;
    FPrevOnChange := nil;
    if FComplete <> nil then
      FComplete.Editor := nil;
  end;
end;

procedure TTyCssEditKit.HandleStatusChange(Sender: TObject; Changes: TSynStatusChanges);
var
  formatted: string;
begin
  if FEdit = nil then Exit;
  if not FFormatOnLineLeave then
  begin
    FLastLine := FEdit.CaretY;
    Exit;
  end;
  { Format only the line the caret just LEFT -- replace that one line, never reflow the document
    (which would flicker the whole editor). }
  if FFormatting or not (scCaretY in Changes) then Exit;
  if (FEdit.CaretY <> FLastLine) and (FLastLine >= 1) and (FLastLine <= FEdit.Lines.Count) then
  begin
    formatted := TyCssFormatLine(FEdit.Lines[FLastLine - 1]);
    if formatted <> FEdit.Lines[FLastLine - 1] then
    begin
      FFormatting := True;
      try
        FEdit.Lines[FLastLine - 1] := formatted;
      finally
        FFormatting := False;
      end;
    end;
  end;
  FLastLine := FEdit.CaretY;
end;

procedure TTyCssEditKit.BeforeKeyPress(Sender: TObject; var Key: char);
begin
  { An identifier keystroke should pop the completion after it lands (done in EditChange, which
    fires post-insert). A '-' also matters -- it starts a --token. }
  FWantComplete := FAutoComplete and (Key in ['a'..'z', 'A'..'Z', '-']);
end;

procedure TTyCssEditKit.EditChange(Sender: TObject);
var
  before, word: string;
  i: Integer;
  p: TPoint;
begin
  { Auto-pop completion when an identifier was just typed (and it is not our own line-format edit,
    nor already showing). The popup filters itself as typing continues, closes on Esc / a token-end
    char (EndOfTokenChr) / selection. }
  if FWantComplete and not FFormatting and (FEdit <> nil) and (FComplete <> nil)
     and not FComplete.IsActive then
  begin
    FWantComplete := False;
    { the identifier run ending at the caret -- the popup opens pre-filtered by it }
    before := Copy(FEdit.LineText, 1, FEdit.CaretX - 1);
    i := Length(before);
    while (i >= 1) and (before[i] in ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) do Dec(i);
    word := Copy(before, i + 1, MaxInt);
    if word <> '' then
    begin
      { one row below the caret, in screen coords }
      p := FEdit.ClientToScreen(FEdit.RowColumnToPixels(Point(FEdit.CaretX, FEdit.CaretY + 1)));
      FComplete.Execute(word, p.X, p.Y);
    end;
  end;
  if Assigned(FPrevOnChange) then
    FPrevOnChange(Sender);
end;

function TTyCssEditKit.TextBeforeCaret: string;
var
  y, i: Integer;
  line: string;
begin
  Result := '';
  if FEdit = nil then Exit;
  y := FEdit.LogicalCaretXY.Y;
  for i := 0 to Min(y - 1, FEdit.Lines.Count) - 1 do
    Result := Result + FEdit.Lines[i] + LineEnding;
  if (y >= 1) and (y <= FEdit.Lines.Count) then
    line := FEdit.Lines[y - 1]
  else
    line := '';
  Result := Result + Copy(line, 1, FEdit.LogicalCaretXY.X - 1);
end;

procedure TTyCssEditKit.FillCompletion;
begin
  if FComplete = nil then Exit;
  FComplete.ItemList.Clear;
  { the text up to the caret: brace depth and the token boundary are what matter, and text
    AFTER the caret would put a caret inside a rule in the wrong context }
  TyCssCompletionItems(TextBeforeCaret, FSelectorMode, FComplete.ItemList);
end;

procedure TTyCssEditKit.CompletionExecute(Sender: TObject);
begin
  FillCompletion;
end;

end.
