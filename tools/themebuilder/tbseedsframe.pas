unit tbseedsframe;
{ The seeds page of the side bar: the six seeds (tbseeds), one column per mode -- light and
  dark for a document with @mode blocks, one column (and "Split into light and dark") for a
  document with a top-level :root only.

  Each cell shows what the seed comes to in that mode (TTbSeedEval: the document over the
  base, no density pack) and says where it comes from: nothing when the column's own block
  sets it, "from :root" when a two-mode document sets it once for both, "inherited" (greyed)
  when only the base theme does, "from an imported file" (greyed) when a file the document
  @imports does, "overridden by an imported @mode" when the document's :root sets it but an
  imported @mode block wins over that (the swatch shows what wins; a change goes into the
  document's own block for the mode, which wins over the import -- no question asked),
  "expression" when the value is not a plain colour (length).

  --radius is the one seed the density pack sets too (modern: 8px, in a :root). Any @mode
  block wins over every :root, so a radius written into a mode's block wins over the density
  as well; splitting into two modes leaves --radius where it was, and a radius the column
  does not have of its own is asked about first: :root for both modes (the density still
  wins there), or the mode's block (it wins over the density there too).

  A change goes back into the text as one set of edits (tbseeds) handed to the window
  (OnEdits), which applies them as one undo step and refreshes -- and the refresh comes back
  here through UpdateFrom. So the panel never edits its own state: the text is the truth.
  Before working out an edit the panel asks the window to catch up (OnSync: the editor may
  be ahead of the last scan by a few keystrokes); before replacing an expression, or a seed
  both modes share, it asks (OnAsk). Setting a swatch or a spin box from code fires their
  change events, so every write from code is fenced with FUpdating.

  What a refresh costs here (the second style model loads the whole theme -- auto.tycss
  takes about as long as the preview's own load):
  - UpdateFrom only takes the text. The work (scan, the model, the twelve values, the
    controls) is done when the page can be seen -- at once when it is showing, else when
    it is shown (CatchUp, from the side bar window's OnShow) or when anything is asked of
    it (every public reader catches up first). A hidden page costs a refresh nothing.
  - The model is loaded again only when the text or the folder changed (FDoneKey); the
    files an @import brings are read with it -- one changed on disk under an unchanged text
    is seen at the next change of the text.
  - The values are worked out a column at a time: one mode switch per column, not one
    per cell (TTbSeedEval.Values).
  - The radius spin boxes wait 250 ms after the last step before writing (FRadiusTimer):
    holding an arrow down is one change, not one per step. Each write carries a merge key
    ('radius' + column), and the window folds radius writes that follow one another, with
    nothing else in between, into one undo step (TTbMainForm.ApplyEdits). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Dialogs, ExtCtrls,
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
  rsTbSeedImported = 'from an imported file';
  rsTbSeedOverridden = 'overridden by an imported @mode';
  rsTbSeedOverriddenHint = ':root says %s, but an @mode block in an imported file wins over it. A change goes into this file''s own @mode block, which wins over the import.';
  rsTbSeedSharedAsk = '%s is set in :root and shared by light and dark. Yes: change it there (both modes). No: add it to %s only.';
  rsTbSeedExprAsk = '%s is the expression %s. Replace it with %s?';
  rsTbSeedRadiusAsk = 'The %s block has no --radius of its own. Yes: set it in :root, for light and dark (the modern density still puts its own radius over it). No: set it in the %s block only, where it also wins over the modern density''s radius. Cancel: change nothing.';

type
  TTbAskEvent = function(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult of object;
  { False: not taken (the editor no longer has AText) -- the page shows the text's values again.
    AMergeKey: '' or the kind of change ('radius0' ...): the window may fold changes of the
    same kind that follow one another into one undo step }
  TTbEditsEvent = function(Sender: TObject; const AText: string;
    const AEdits: TTbTextEdits; const AMergeKey: string): Boolean of object;

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
    FImports: TTbCssScans;      { the files the text @imports, scanned (TbScanImports) }
    FEval: TTbSeedEval;
    FText, FEol, FBaseDir: string;
    FParseBroken: Boolean;      { what UpdateFrom was told: the text does not parse }
    FDirty: Boolean;            { UpdateFrom took a text CatchUp has not worked through }
    FDoneKey: string;           { text #0 folder #1 parse verdict, the last text worked through }
    FLoads: Integer;
    FValues: array[0..TbSeedCount - 1, 0..1] of string;   { ResolvedText, per column }
    FColumns: TStringArray;
    FBroken: Boolean;
    FUpdating: Boolean;
    FRadiusTimer: TTimer;
    FPendingRadius: array[0..1] of string;   { a spin box's value not written yet; '' none }
    FSwatch: array[0..TbSeedCount - 1, 0..1] of TTyColorButton;   { nil for the radius }
    FNote: array[0..TbSeedCount - 1, 0..1] of TTyLabel;
    FSpin: array[0..1] of TTySpinEdit;
    FOnEdits: TTbEditsEvent;
    FOnAsk: TTbAskEvent;
    FOnSync: TNotifyEvent;
    procedure UpdateView;
    function Ask(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult;
    function ColumnName(AColumnIndex: Integer): string;
    function DocRaw(const ACell: TTbSeedCell): string;
    function CellAt(ASeed, AColumnIndex: Integer): TTbSeedCell;
    function Hand(const AEdits: TTbTextEdits; const AMergeKey: string = ''): Boolean;
    function SetValue(ASeed, AColumnIndex: Integer; const AValue, AMergeKey: string): Boolean;
    function GetColumns: TStringArray;
    function GetBroken: Boolean;
    function PageShowing: Boolean;
    procedure RadiusTimerFire(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { takes the text; works it through now if the page is showing, else when it is shown }
    procedure UpdateFrom(const AText, ABaseDir: string; ABroken: Boolean);
    { work through the last text UpdateFrom took, if it has not been }
    procedure CatchUp;
    { a radius spin box's change still waiting for its 250 ms: written now }
    procedure FlushRadius;
    function RadiusPending: Boolean;                                 { FOR THE TESTS }
    property EvalLoads: Integer read FLoads;                         { FOR THE TESTS }
    { the one way a value gets into the text: sync, confirm, compute, hand over. False: nothing changed }
    function ApplyValue(ASeed, AColumnIndex: Integer; const AValue: string): Boolean;
    function SplitModes: Boolean;
    function Cell(ASeed, AColumnIndex: Integer): TTbSeedCell;
    function ResolvedText(ASeed, AColumnIndex: Integer): string;  { '#RRGGBB' / '6px' / '' }
    function Swatch(ASeed, AColumnIndex: Integer): TTyColorButton;   { FOR THE TESTS }
    function Note(ASeed, AColumnIndex: Integer): TTyLabel;           { FOR THE TESTS }
    function RadiusSpin(AColumnIndex: Integer): TTySpinEdit;         { FOR THE TESTS }
    property Columns: TStringArray read GetColumns;
    property Broken: Boolean read GetBroken;
    property ScannedText: string read FText;
    property OnEdits: TTbEditsEvent read FOnEdits write FOnEdits;
    property OnAsk: TTbAskEvent read FOnAsk write FOnAsk;
    property OnSync: TNotifyEvent read FOnSync write FOnSync;
  end;

implementation

{$R *.lfm}

uses
  tyControls.Css.Values, tbpreview;

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
  FRadiusTimer := TTimer.Create(Self);
  FRadiusTimer.Enabled := False;
  FRadiusTimer.Interval := 250;
  FRadiusTimer.OnTimer := @RadiusTimerFire;
  SetLength(FColumns, 1);
  FColumns[0] := '';
  FBroken := True;   { no text yet }
  UpdateView;
end;

destructor TTbSeedsFrame.Destroy;
begin
  if FRadiusTimer <> nil then
    FRadiusTimer.Enabled := False;   { a pending radius is dropped, not written into a window going away }
  FOnEdits := nil;
  FOnAsk := nil;
  FOnSync := nil;
  FreeAndNil(FScan);
  TbFreeScans(FImports);
  FreeAndNil(FEval);
  inherited Destroy;
end;

procedure TTbSeedsFrame.UpdateFrom(const AText, ABaseDir: string; ABroken: Boolean);
begin
  FText := AText;
  FBaseDir := ABaseDir;
  FParseBroken := ABroken;
  FDirty := True;
  if PageShowing then
    CatchUp;
end;

{ a page in a window can be seen only when it and every parent are visible; one built
  without a parent (the tests) is worked through at once }
function TTbSeedsFrame.PageShowing: Boolean;
begin
  Result := (Parent = nil) or IsVisible;
end;

procedure TTbSeedsFrame.CatchUp;
var
  key: string;
  col, seed: Integer;
  vals: TTbSeedValues;
begin
  if not FDirty then Exit;
  FDirty := False;
  key := FText + #0 + FBaseDir;
  { the same text, folder and verdict as last time: all of it is as it was }
  if (key + #1 + BoolToStr(FParseBroken, True)) = FDoneKey then Exit;
  FDoneKey := key + #1 + BoolToStr(FParseBroken, True);
  FreeAndNil(FScan);
  FScan := TbScanCss(FText);
  FEol := TbDetectEol(FText);
  TbFreeScans(FImports);
  if FParseBroken then
    FBroken := True        { nothing to load: the text does not parse }
  else
  begin
    { a text that does not load: its value spans may no longer be what they look like }
    FBroken := not FEval.Load(FText, FBaseDir);
    Inc(FLoads);
    FImports := TbScanImports(FText, FBaseDir);
  end;
  { the model says whether there are modes: an imported file may bring them all }
  if FBroken then
    FColumns := TbSeedColumns(FScan)
  else
    FColumns := TbSeedColumnsFor(FEval.HasModes);
  for col := 0 to 1 do
  begin
    if FBroken or (col > High(FColumns)) then
      for seed := 0 to TbSeedCount - 1 do
        vals[seed] := ''
    else
      FEval.Values(FColumns[col], vals);    { one mode switch per column }
    for seed := 0 to TbSeedCount - 1 do
      FValues[seed, col] := vals[seed];
  end;
  UpdateView;
end;

function TTbSeedsFrame.GetColumns: TStringArray;
begin
  CatchUp;
  Result := FColumns;
end;

function TTbSeedsFrame.GetBroken: Boolean;
begin
  CatchUp;
  Result := FBroken;
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
        c := CellAt(seed, col);
        if seed = TbRadiusSeed then
        begin
          { a value still waiting to be written is the user's: left alone }
          px := StrToIntDef(Copy(FValues[seed, col], 1, Length(FValues[seed, col]) - 2), -1);
          if (FPendingRadius[col] = '') and (px >= 0) then
            FSpin[col].Value := px;
          FSpin[col].Hint := c.Raw;
          FSpin[col].ShowHint := c.Raw <> '';
        end
        else
        begin
          if FValues[seed, col] <> '' then
            FSwatch[seed, col].SelectedColor := TyParseColor(FValues[seed, col]);
          where := ColumnName(col);
          if not two then where := rsTbSeedValue;
          FSwatch[seed, col].DialogCaption := '--' + TbSeedNames[seed] + ' (' + where + ')';
          if c.Overridden then
            FSwatch[seed, col].Hint := Format(rsTbSeedOverriddenHint, [DocRaw(c)])
          else
            FSwatch[seed, col].Hint := c.Raw;
          FSwatch[seed, col].ShowHint := FSwatch[seed, col].Hint <> '';
        end;
        case c.Source of
          tssInherited: lbl.Caption := rsTbSeedInherited;
          tssShared: lbl.Caption := rsTbSeedShared;
          tssImported:
            if c.Overridden then
              lbl.Caption := rsTbSeedOverridden
            else
              lbl.Caption := rsTbSeedImported;
        else
          if c.IsExpression then
            lbl.Caption := rsTbSeedExpression
          else
            lbl.Caption := '';
        end;
        if (c.Source = tssShared) and c.IsExpression then
          lbl.Caption := rsTbSeedShared + ', ' + rsTbSeedExpression;
        { not in this file (the base's, an imported file's): greyed -- a change adds the line }
        lbl.Enabled := (c.Source <> tssInherited) and ((c.Source <> tssImported) or c.Overridden);
      end;
  finally
    FUpdating := False;
  end;
end;

function TTbSeedsFrame.Cell(ASeed, AColumnIndex: Integer): TTbSeedCell;
begin
  CatchUp;
  Result := CellAt(ASeed, AColumnIndex);
end;

{ Cell without catching up: UpdateView's (it runs inside CatchUp) }
function TTbSeedsFrame.CellAt(ASeed, AColumnIndex: Integer): TTbSeedCell;
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
  Result := TbSeedCellIn(FScan, FImports, ASeed, FColumns[AColumnIndex]);
end;

{ the document's own (overridden) value of an Overridden cell }
function TTbSeedsFrame.DocRaw(const ACell: TTbSeedCell): string;
begin
  if (FScan <> nil) and (ACell.Block >= 0) then
    Result := FScan.DeclValue(ACell.Block, ACell.Decl)
  else
    Result := '';
end;

function TTbSeedsFrame.ResolvedText(ASeed, AColumnIndex: Integer): string;
begin
  CatchUp;
  Result := '';
  if (AColumnIndex < 0) or (AColumnIndex > High(FColumns)) then Exit;
  Result := FValues[ASeed, AColumnIndex];
end;

function TTbSeedsFrame.Swatch(ASeed, AColumnIndex: Integer): TTyColorButton;
begin
  CatchUp;
  Result := FSwatch[ASeed, AColumnIndex];
end;

function TTbSeedsFrame.Note(ASeed, AColumnIndex: Integer): TTyLabel;
begin
  CatchUp;
  Result := FNote[ASeed, AColumnIndex];
end;

function TTbSeedsFrame.RadiusSpin(AColumnIndex: Integer): TTySpinEdit;
begin
  CatchUp;
  Result := FSpin[AColumnIndex];
end;

function TTbSeedsFrame.Ask(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult;
begin
  if Assigned(FOnAsk) then
    Result := FOnAsk(AMsg, AButtons)
  else
    Result := mrCancel;   { nobody to ask: change nothing }
end;

function TTbSeedsFrame.Hand(const AEdits: TTbTextEdits; const AMergeKey: string): Boolean;
begin
  Result := False;
  if (Length(AEdits) = 0) or not Assigned(FOnEdits) then Exit;
  Result := FOnEdits(Self, FText, AEdits, AMergeKey);
end;

function TTbSeedsFrame.ApplyValue(ASeed, AColumnIndex: Integer; const AValue: string): Boolean;
begin
  Result := SetValue(ASeed, AColumnIndex, AValue, '');
end;

function TTbSeedsFrame.SetValue(ASeed, AColumnIndex: Integer; const AValue, AMergeKey: string): Boolean;
var
  c: TTbSeedCell;
  shared: Boolean;
begin
  Result := False;
  if Assigned(FOnSync) then
    FOnSync(Self);                        { the editor may be ahead of our scan }
  CatchUp;                                { what the sync handed over, worked through }
  if FBroken or (FScan = nil) or (AColumnIndex < 0) or (AColumnIndex > High(FColumns)) then
    Exit;
  c := Cell(ASeed, AColumnIndex);
  shared := False;
  { --radius in a mode's block wins over the modern density's radius (the density pack is a
    :root): one the column does not have of its own goes to :root unless asked otherwise }
  if (ASeed = TbRadiusSeed) and (FColumns[AColumnIndex] <> '')
     and (c.Source in [tssShared, tssInherited]) then
    case Ask(Format(rsTbSeedRadiusAsk, [ColumnName(AColumnIndex), ColumnName(AColumnIndex)]),
      [mbYes, mbNo, mbCancel]) of
      mrYes: shared := True;
      mrNo: shared := False;
    else
      Exit;
    end
  else if c.Source = tssShared then
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
  Result := Hand(TbSeedSetEdits(FScan, FEol, ASeed, FColumns[AColumnIndex], AValue, shared),
    AMergeKey);
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
  CatchUp;
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

{ a step of a spin box: written 250 ms after the last one (holding an arrow is one change) }
procedure TTbSeedsFrame.RadiusChange(Sender: TObject);
var
  sp: TTySpinEdit;
begin
  if FUpdating then Exit;
  sp := Sender as TTySpinEdit;
  FPendingRadius[sp.Tag] := TbRadiusText(sp.Value);
  FRadiusTimer.Enabled := False;      { restart }
  FRadiusTimer.Enabled := True;
end;

procedure TTbSeedsFrame.RadiusTimerFire(Sender: TObject);
begin
  FlushRadius;
end;

procedure TTbSeedsFrame.FlushRadius;
var
  col: Integer;
  v: string;
begin
  FRadiusTimer.Enabled := False;
  for col := 0 to 1 do
    if FPendingRadius[col] <> '' then
    begin
      v := FPendingRadius[col];
      FPendingRadius[col] := '';
      { not taken: the spin box goes back to what the text says }
      if not SetValue(TbRadiusSeed, col, v, 'radius' + IntToStr(col)) then
        UpdateView;
    end;
end;

function TTbSeedsFrame.RadiusPending: Boolean;
begin
  Result := (FPendingRadius[0] <> '') or (FPendingRadius[1] <> '');
end;

procedure TTbSeedsFrame.SplitButtonClick(Sender: TObject);
begin
  SplitModes;
end;

end.
