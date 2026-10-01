unit tbseedsframe;
{ The seeds page of the side bar: the six seeds (tbseeds), one column per mode -- light and
  dark for a document with @mode blocks, one column (and "Split into light and dark") for a
  document with a top-level :root only.

  Each cell shows what the seed comes to in that mode (TTbSeedEval: the document over the
  base, no density pack) and says where it comes from: nothing when the column's own block
  sets it, "from :root" when a two-mode document sets it once for both, "inherited" (greyed)
  when only the base theme does, "expression" when the value is not a plain colour (length).

  A change goes back into the text as one set of edits (tbseeds) handed to the window
  (OnEdits), which applies them as one undo step and refreshes -- and the refresh comes back
  here through UpdateFrom. So the panel never edits its own state: the text is the truth.
  Before working out an edit the panel asks the window to catch up (OnSync: the editor may
  be ahead of the last scan by a few keystrokes); before replacing an expression, or a seed
  both modes share, it asks (OnAsk). Setting a swatch or a spin box from code fires their
  change events, so every write from code is fenced with FUpdating. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Dialogs,
  tyControls.Types, tyControls.Panel, tyControls.TyLabel, tyControls.Button,
  tyControls.ColorButton, tyControls.SpinEdit, tyControls.ScrollBox,
  tbcssscan, tbseeds;

resourcestring
  rsTbSeedsBroken = 'Fix the errors in the problem list first.';
  rsTbSeedsSingleMode = 'One mode: the seeds of both light and dark.';
  rsTbSeedValue = 'Value';
  rsTbSeedLight = 'Light';
  rsTbSeedDark = 'Dark';
  rsTbSeedInherited = 'inherited';
  rsTbSeedShared = 'from :root';
  rsTbSeedExpression = 'expression';
  rsTbSeedSharedAsk = '%s is set in :root and shared by light and dark. Yes: change it there (both modes). No: add it to %s only.';
  rsTbSeedExprAsk = '%s is the expression %s. Replace it with %s?';

type
  TTbAskEvent = function(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult of object;
  TTbEditsEvent = procedure(Sender: TObject; const AText: string;
    const AEdits: TTbTextEdits) of object;

  TTbSeedsFrame = class(TFrame)
    ModeNote: TTyLabel;
    SplitButton: TTyButton;
    Scroll: TTyScrollBox;
    Header: TTyPanel;
    HdrLeft: TTyLabel;
    HdrRight: TTyLabel;
    RowAccent: TTyPanel;
    LblAccent: TTyLabel;
    SwAccentL: TTyColorButton;
    SwAccentR: TTyColorButton;
    NoteAccentL: TTyLabel;
    NoteAccentR: TTyLabel;
    RowSurface: TTyPanel;
    LblSurface: TTyLabel;
    SwSurfaceL: TTyColorButton;
    SwSurfaceR: TTyColorButton;
    NoteSurfaceL: TTyLabel;
    NoteSurfaceR: TTyLabel;
    RowOnSurface: TTyPanel;
    LblOnSurface: TTyLabel;
    SwOnSurfaceL: TTyColorButton;
    SwOnSurfaceR: TTyColorButton;
    NoteOnSurfaceL: TTyLabel;
    NoteOnSurfaceR: TTyLabel;
    RowBorder: TTyPanel;
    LblBorder: TTyLabel;
    SwBorderL: TTyColorButton;
    SwBorderR: TTyColorButton;
    NoteBorderL: TTyLabel;
    NoteBorderR: TTyLabel;
    RowDanger: TTyPanel;
    LblDanger: TTyLabel;
    SwDangerL: TTyColorButton;
    SwDangerR: TTyColorButton;
    NoteDangerL: TTyLabel;
    NoteDangerR: TTyLabel;
    RowRadius: TTyPanel;
    LblRadius: TTyLabel;
    SpnRadiusL: TTySpinEdit;
    SpnRadiusR: TTySpinEdit;
    NoteRadiusL: TTyLabel;
    NoteRadiusR: TTyLabel;
    procedure SwatchColorChange(Sender: TObject);
    procedure RadiusChange(Sender: TObject);
    procedure SplitButtonClick(Sender: TObject);
  private
    FScan: TTbCssScan;
    FEval: TTbSeedEval;
    FText, FEol: string;
    FColumns: TStringArray;
    FBroken: Boolean;
    FUpdating: Boolean;
    FSwatch: array[0..TbSeedCount - 1, 0..1] of TTyColorButton;   { nil for the radius }
    FNote: array[0..TbSeedCount - 1, 0..1] of TTyLabel;
    FSpin: array[0..1] of TTySpinEdit;
    FOnEdits: TTbEditsEvent;
    FOnAsk: TTbAskEvent;
    FOnSync: TNotifyEvent;
    procedure UpdateView;
    function Ask(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult;
    function ColumnName(AColumnIndex: Integer): string;
    function Hand(const AEdits: TTbTextEdits): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure UpdateFrom(const AText, ABaseDir: string; ABroken: Boolean);
    { the one way a value gets into the text: sync, confirm, compute, hand over. False: nothing changed }
    function ApplyValue(ASeed, AColumnIndex: Integer; const AValue: string): Boolean;
    function SplitModes: Boolean;
    function Cell(ASeed, AColumnIndex: Integer): TTbSeedCell;
    function ResolvedText(ASeed, AColumnIndex: Integer): string;  { '#RRGGBB' / '6px' / '' }
    function Swatch(ASeed, AColumnIndex: Integer): TTyColorButton;   { FOR THE TESTS }
    function Note(ASeed, AColumnIndex: Integer): TTyLabel;           { FOR THE TESTS }
    function RadiusSpin(AColumnIndex: Integer): TTySpinEdit;         { FOR THE TESTS }
    property Columns: TStringArray read FColumns;
    property Broken: Boolean read FBroken;
    property ScannedText: string read FText;
    property OnEdits: TTbEditsEvent read FOnEdits write FOnEdits;
    property OnAsk: TTbAskEvent read FOnAsk write FOnAsk;
    property OnSync: TNotifyEvent read FOnSync write FOnSync;
  end;

implementation

{$R *.lfm}

uses
  tbpreview;

constructor TTbSeedsFrame.Create(AOwner: TComponent);
var
  seed, col: Integer;
begin
  inherited Create(AOwner);
  FEval := TTbSeedEval.Create;
  FSwatch[0, 0] := SwAccentL;     FSwatch[0, 1] := SwAccentR;
  FSwatch[1, 0] := SwSurfaceL;    FSwatch[1, 1] := SwSurfaceR;
  FSwatch[2, 0] := SwOnSurfaceL;  FSwatch[2, 1] := SwOnSurfaceR;
  FSwatch[3, 0] := SwBorderL;     FSwatch[3, 1] := SwBorderR;
  FSwatch[4, 0] := SwDangerL;     FSwatch[4, 1] := SwDangerR;
  FSwatch[TbRadiusSeed, 0] := nil;
  FSwatch[TbRadiusSeed, 1] := nil;
  FNote[0, 0] := NoteAccentL;     FNote[0, 1] := NoteAccentR;
  FNote[1, 0] := NoteSurfaceL;    FNote[1, 1] := NoteSurfaceR;
  FNote[2, 0] := NoteOnSurfaceL;  FNote[2, 1] := NoteOnSurfaceR;
  FNote[3, 0] := NoteBorderL;     FNote[3, 1] := NoteBorderR;
  FNote[4, 0] := NoteDangerL;     FNote[4, 1] := NoteDangerR;
  FNote[5, 0] := NoteRadiusL;     FNote[5, 1] := NoteRadiusR;
  FSpin[0] := SpnRadiusL;
  FSpin[1] := SpnRadiusR;
  for seed := 0 to TbSeedCount - 1 do
    for col := 0 to 1 do
      if FSwatch[seed, col] <> nil then
        FSwatch[seed, col].Tag := seed * 2 + col;
  FSpin[0].Tag := 0;
  FSpin[1].Tag := 1;
  SetLength(FColumns, 1);
  FColumns[0] := '';
  FBroken := True;   { no text yet }
  UpdateView;
end;

destructor TTbSeedsFrame.Destroy;
begin
  FOnEdits := nil;
  FOnAsk := nil;
  FOnSync := nil;
  FreeAndNil(FScan);
  FreeAndNil(FEval);
  inherited Destroy;
end;

procedure TTbSeedsFrame.UpdateFrom(const AText, ABaseDir: string; ABroken: Boolean);
begin
  FText := AText;
  FreeAndNil(FScan);
  FScan := TbScanCss(AText);
  FEol := TbDetectEol(AText);
  FColumns := TbSeedColumns(FScan);
  { a text that does not parse or load: its value spans may no longer be what they look like }
  FBroken := ABroken or not FEval.Load(AText, ABaseDir);
  UpdateView;
end;

function TTbSeedsFrame.ColumnName(AColumnIndex: Integer): string;
begin
  if (AColumnIndex < 0) or (AColumnIndex > High(FColumns)) then
    Exit('');
  if FColumns[AColumnIndex] = 'dark' then
    Result := rsTbModeDark
  else
    Result := rsTbModeLight;
end;

procedure TTbSeedsFrame.UpdateView;
var
  seed, col, px: Integer;
  two, shown: Boolean;
  c: TTbSeedCell;
  clr: TTyColor;
  lbl: TTyLabel;
  where: string;
begin
  FUpdating := True;
  try
    two := Length(FColumns) = 2;
    if FBroken then
      ModeNote.Caption := rsTbSeedsBroken
    else if not two then
      ModeNote.Caption := rsTbSeedsSingleMode
    else
      ModeNote.Caption := '';
    SplitButton.Visible := (not FBroken) and not two;
    if two then
      HdrLeft.Caption := rsTbSeedLight
    else
      HdrLeft.Caption := rsTbSeedValue;
    HdrRight.Caption := rsTbSeedDark;
    HdrRight.Visible := two;
    Scroll.Enabled := not FBroken;
    for seed := 0 to TbSeedCount - 1 do
      for col := 0 to 1 do
      begin
        shown := (col = 0) or two;
        lbl := FNote[seed, col];
        if seed = TbRadiusSeed then
          FSpin[col].Visible := shown
        else
          FSwatch[seed, col].Visible := shown;
        lbl.Visible := shown;
        if not shown then Continue;
        c := Cell(seed, col);
        if seed = TbRadiusSeed then
        begin
          if (not FBroken) and FEval.Radius(FColumns[col], px) then
            FSpin[col].Value := px;
          FSpin[col].Hint := c.Raw;
          FSpin[col].ShowHint := c.Raw <> '';
        end
        else
        begin
          if (not FBroken) and FEval.Color(seed, FColumns[col], clr) then
            FSwatch[seed, col].SelectedColor := clr;
          where := ColumnName(col);
          if not two then where := rsTbSeedValue;
          FSwatch[seed, col].DialogCaption := '--' + TbSeedNames[seed] + ' (' + where + ')';
          FSwatch[seed, col].Hint := c.Raw;
          FSwatch[seed, col].ShowHint := c.Raw <> '';
        end;
        case c.Source of
          tssInherited: lbl.Caption := rsTbSeedInherited;
          tssShared: lbl.Caption := rsTbSeedShared;
        else
          if c.IsExpression then
            lbl.Caption := rsTbSeedExpression
          else
            lbl.Caption := '';
        end;
        if (c.Source = tssShared) and c.IsExpression then
          lbl.Caption := rsTbSeedShared + ', ' + rsTbSeedExpression;
        { inherited: the base's value, greyed -- a change adds the line }
        lbl.Enabled := c.Source <> tssInherited;
      end;
  finally
    FUpdating := False;
  end;
end;

function TTbSeedsFrame.Cell(ASeed, AColumnIndex: Integer): TTbSeedCell;
begin
  if (FScan = nil) or (AColumnIndex < 0) or (AColumnIndex > High(FColumns)) then
  begin
    Result := Default(TTbSeedCell);
    Result.Seed := ASeed;
    Result.Block := -1;
    Result.Decl := -1;
    Result.Source := tssInherited;
    Exit;
  end;
  Result := TbSeedCell(FScan, ASeed, FColumns[AColumnIndex]);
end;

function TTbSeedsFrame.ResolvedText(ASeed, AColumnIndex: Integer): string;
var
  clr: TTyColor;
  px: Integer;
begin
  Result := '';
  if (AColumnIndex < 0) or (AColumnIndex > High(FColumns)) then Exit;
  if ASeed = TbRadiusSeed then
  begin
    if FEval.Radius(FColumns[AColumnIndex], px) then
      Result := TbRadiusText(px);
  end
  else if FEval.Color(ASeed, FColumns[AColumnIndex], clr) then
    Result := TbColorText(clr);
end;

function TTbSeedsFrame.Swatch(ASeed, AColumnIndex: Integer): TTyColorButton;
begin
  Result := FSwatch[ASeed, AColumnIndex];
end;

function TTbSeedsFrame.Note(ASeed, AColumnIndex: Integer): TTyLabel;
begin
  Result := FNote[ASeed, AColumnIndex];
end;

function TTbSeedsFrame.RadiusSpin(AColumnIndex: Integer): TTySpinEdit;
begin
  Result := FSpin[AColumnIndex];
end;

function TTbSeedsFrame.Ask(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult;
begin
  if Assigned(FOnAsk) then
    Result := FOnAsk(AMsg, AButtons)
  else
    Result := mrCancel;   { nobody to ask: change nothing }
end;

function TTbSeedsFrame.Hand(const AEdits: TTbTextEdits): Boolean;
begin
  Result := False;
  if (Length(AEdits) = 0) or not Assigned(FOnEdits) then Exit;
  FOnEdits(Self, FText, AEdits);
  Result := True;
end;

function TTbSeedsFrame.ApplyValue(ASeed, AColumnIndex: Integer; const AValue: string): Boolean;
var
  c: TTbSeedCell;
  shared: Boolean;
begin
  Result := False;
  if Assigned(FOnSync) then
    FOnSync(Self);                        { the editor may be ahead of our scan }
  if FBroken or (FScan = nil) or (AColumnIndex < 0) or (AColumnIndex > High(FColumns)) then
    Exit;
  c := Cell(ASeed, AColumnIndex);
  shared := False;
  if c.Source = tssShared then
    case Ask(Format(rsTbSeedSharedAsk, ['--' + TbSeedNames[ASeed], ColumnName(AColumnIndex)]),
      [mbYes, mbNo, mbCancel]) of
      mrYes: shared := True;
      mrNo: shared := False;
    else
      Exit;
    end;
  { only a value that is REPLACED can be an expression lost; an added line loses nothing }
  if ((c.Source = tssOwn) or shared) and c.IsExpression then
    if Ask(Format(rsTbSeedExprAsk, ['--' + TbSeedNames[ASeed], c.Raw, AValue]),
      [mbYes, mbNo]) <> mrYes then
      Exit;
  Result := Hand(TbSeedSetEdits(FScan, FEol, ASeed, FColumns[AColumnIndex], AValue, shared));
end;

function TTbSeedsFrame.SplitModes: Boolean;
var
  values: array of string;
  seed: Integer;
  c: TTbSeedCell;
begin
  Result := False;
  if Assigned(FOnSync) then
    FOnSync(Self);
  if FBroken or (FScan = nil) or (Length(FColumns) <> 1) then Exit;
  SetLength(values, TbSeedCount);
  for seed := 0 to TbSeedCount - 1 do
  begin
    c := Cell(seed, 0);
    { what is written stays as written (an expression too); the rest is what it comes to }
    if c.Source = tssOwn then
      values[seed] := c.Raw
    else
      values[seed] := ResolvedText(seed, 0);
    if values[seed] = '' then Exit;
  end;
  { the dark block starts as a copy of the light one }
  Result := Hand(TbSplitModesEdits(FScan, FEol, values));
end;

procedure TTbSeedsFrame.SwatchColorChange(Sender: TObject);
var
  b: TTyColorButton;
begin
  if FUpdating then Exit;
  b := Sender as TTyColorButton;
  { not taken (no, cancel, nowhere to put it): the swatch goes back to what the text says }
  if not ApplyValue(b.Tag div 2, b.Tag mod 2, TbColorText(b.SelectedColor)) then
    UpdateView;
end;

procedure TTbSeedsFrame.RadiusChange(Sender: TObject);
var
  sp: TTySpinEdit;
begin
  if FUpdating then Exit;
  sp := Sender as TTySpinEdit;
  if not ApplyValue(TbRadiusSeed, sp.Tag, TbRadiusText(sp.Value)) then
    UpdateView;
end;

procedure TTbSeedsFrame.SplitButtonClick(Sender: TObject);
begin
  SplitModes;
end;

end.
