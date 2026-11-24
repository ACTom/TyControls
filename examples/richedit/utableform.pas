unit utableform;

{ The table properties form: the table's alignment and indent, the row's height and its rule,
  the column's width, the cell's vertical alignment and padding, the lines (which of them, their
  style, width and colour) and the shading - for the selected cells, else the caret's cell.

  The rich edit's TTyRichEditTableProperties asks it through OnBeforeExecute (the package has
  no such form of its own: this one is yours to copy). The action hands over the selection's
  values - its lines too: the outline's four sides and the inner lines - and the fields alike
  over all of it (Uniform; the control's GetTableProperties); a value the selected cells do not
  share shows empty. On OK the form names what the person changed (Changed) and the action
  applies only that, lines and all, as ONE undo step; nothing changed, nothing is done. Cancel
  changes nothing.

  Lengths are shown in centimetres (the control's are twips) through one pair of functions,
  TwipsToCm and CmToTwips; a field counts as changed only when the twips it gives differ from
  those it showed, so OK with nothing changed applies nothing and nothing drifts. Built from the
  package's controls (no native dialog). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, tyControls.Controller, tyControls.Form,
  tyControls.FormSurface, tyControls.TyLabel, tyControls.Edit, tyControls.ComboBox,
  tyControls.ColorBox, tyControls.GroupBox, tyControls.Button, tyControls.RichEdit.Text,
  tyControls.RichEdit;

type
  TTableForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    GrpTable: TTyGroupBox;
    LblTableAlign: TTyLabel;
    CboTableAlign: TTyComboBox;
    LblIndent: TTyLabel;
    EdtIndent: TTyEdit;
    GrpRow: TTyGroupBox;
    LblRowRule: TTyLabel;
    CboRowRule: TTyComboBox;
    LblRowHeight: TTyLabel;
    EdtRowHeight: TTyEdit;
    GrpColumn: TTyGroupBox;
    LblColWidth: TTyLabel;
    EdtColWidth: TTyEdit;
    GrpShading: TTyGroupBox;
    LblShading: TTyLabel;
    ClrShading: TTyColorBox;
    GrpCell: TTyGroupBox;
    LblVAlign: TTyLabel;
    CboVAlign: TTyComboBox;
    LblPadLR: TTyLabel;
    EdtPadLeft: TTyEdit;
    EdtPadRight: TTyEdit;
    LblPadTB: TTyLabel;
    EdtPadTop: TTyEdit;
    EdtPadBottom: TTyEdit;
    GrpBorders: TTyGroupBox;
    LblLines: TTyLabel;
    CboLines: TTyComboBox;
    LblLineStyle: TTyLabel;
    CboLineStyle: TTyComboBox;
    LblLineWidth: TTyLabel;
    CboLineWidth: TTyComboBox;
    LblLineColor: TTyLabel;
    ClrLine: TTyColorBox;
    LblScope: TTyLabel;
    BtnOk: TTyButton;
    BtnCancel: TTyButton;
    procedure BtnOkClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure LineChanged(Sender: TObject);
    procedure LinesChanged(Sender: TObject);
  private
    FRich: TTyCustomRichEdit;
    FFilling: Boolean;
    // what the form showed, to tell what the person changed (-1: an empty field)
    FAlign, FRule, FVAlign: Integer;
    FIndent, FHeight, FWidth: Integer;
    FPad: array[TTyRowCellSide] of Integer;
    FShading: TColor;
    FShadingShown: Boolean;
    function PadEdit(ASide: TTyRowCellSide): TTyEdit;
    procedure FillLists;
    procedure ShowLength(AEdit: TTyEdit; ATwips: Integer; var AShown: Integer);
    function LengthChanged(AEdit: TTyEdit; AShown: Integer; out ATwips: Integer): Boolean;
    procedure Refuse(AEdit: TTyEdit);
  public
    { Fills the form: AProps as the action hands it over (the values, Uniform what is alike);
      ARich for the words saying what is selected. }
    procedure Prepare(ARich: TTyCustomRichEdit; const AProps: TTyRichTableProperties);
    { What the person changed: AProps' values and Changed naming them. }
    procedure Collect(var AProps: TTyRichTableProperties);
  end;

{ The table properties of ARich's selection, asked in the form: AProps in is what the action
  hands its OnBeforeExecute (the values, Uniform); out, Changed names what the person changed.
  False: cancelled. }
function AskTableProperties(ARich: TTyCustomRichEdit; var AProps: TTyRichTableProperties): Boolean;

{ The lines a border preset names (the outline's sides, the inner lines). }
function PresetLines(APreset: TTyRichBorderPreset): TTyRichCellLines;

{ Twips (1440 an inch) as centimetres with two decimals, and back (False: no number there). The
  one pair every length of the form goes through. }
function TwipsToCm(ATwips: Integer): string;
function CmToTwips(const AText: string; out ATwips: Integer): Boolean;

{ What is selected in ARich's table, in a few words ("2 × 3 cells", "Row 4", "Column 2",
  "The table"; the caret alone: its row and column); '' outside a table. Reads the ends of the
  selection only. }
function TableSelectionText(ARich: TTyCustomRichEdit): string;

{ The ten presets' names, in the order of TTyRichBorderPreset. }
function BorderPresetName(APreset: TTyRichBorderPreset): string;

implementation

{$R *.lfm}

resourcestring
  rsTpLeft        = 'Left';
  rsTpCenter      = 'Center';
  rsTpRight       = 'Right';
  rsTpAuto        = 'Automatic';
  rsTpAtLeast     = 'At least';
  rsTpExactly     = 'Exactly';
  rsTpTop         = 'Top';
  rsTpMiddle      = 'Middle';
  rsTpBottom      = 'Bottom';
  rsTpAsTheyAre   = '(as they are)';
  rsTpAll         = 'All lines';
  rsTpOutside     = 'Outside lines';
  rsTpInside      = 'Inside lines';
  rsTpNoLines     = 'No lines';
  rsTpTopLine     = 'Top line';
  rsTpBottomLine  = 'Bottom line';
  rsTpLeftLine    = 'Left line';
  rsTpRightLine   = 'Right line';
  rsTpInsideH     = 'Inside horizontal lines';
  rsTpInsideV     = 'Inside vertical lines';
  rsTpStyleNone   = '(no line)';
  rsTpSingle      = 'Single line';
  rsTpDouble      = 'Double line';
  rsTpDotted      = 'Dotted line';
  rsTpDashed      = 'Dashed line';
  rsTpPoints      = '%s pt';
  rsTpAutoColor   = 'Automatic';
  rsTpNoColor     = 'No color';
  rsTpBlack       = 'Black';
  rsTpGray        = 'Gray';
  rsTpLightGray   = 'Light gray';
  rsTpWhite       = 'White';
  rsTpRed         = 'Red';
  rsTpOrange      = 'Orange';
  rsTpYellow      = 'Yellow';
  rsTpLightYellow = 'Light yellow';
  rsTpGreen       = 'Green';
  rsTpLightGreen  = 'Light green';
  rsTpBlue        = 'Blue';
  rsTpLightBlue   = 'Light blue';
  rsTpPurple      = 'Purple';
  rsTpCells       = '%d × %d cells';
  rsTpCell        = 'Row %d, column %d';
  rsTpRowOne      = 'Row %d';
  rsTpRows        = 'Rows %d–%d';
  rsTpColumnOne   = 'Column %d';
  rsTpColumns     = 'Columns %d–%d';
  rsTpTable       = 'The table (%d × %d)';
  rsTpApplies     = 'For: %s';
  rsTpBadLength   = 'Give a length in centimetres, for example 1.5.';
  rsTpNoHeight    = 'Give the row''s height.';

const
  // Word's line widths, twips (½, ¾, 1, 1½, 2¼, 3 points)
  CLineWidths: array[0..5] of Integer = (10, 15, 20, 30, 45, 60);

{ ---- units ---- }

function TwipsToCm(ATwips: Integer): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FormatFloat('0.00', ATwips * 2.54 / 1440, fs);
end;

function CmToTwips(const AText: string; out ATwips: Integer): Boolean;
var
  fs: TFormatSettings;
  v: Double;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := TryStrToFloat(Trim(StringReplace(AText, ',', '.', [])), v, fs) and (v >= 0) and
    (v < 600);
  if Result then ATwips := Round(v * 1440 / 2.54) else ATwips := 0;
end;

function PointsText(ATwips: Integer): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := Format(rsTpPoints, [FormatFloat('0.##', ATwips / 20, fs)]);
end;

function BorderPresetName(APreset: TTyRichBorderPreset): string;
begin
  case APreset of
    rbpAll: Result := rsTpAll;
    rbpOutside: Result := rsTpOutside;
    rbpInside: Result := rsTpInside;
    rbpNone: Result := rsTpNoLines;
    rbpTop: Result := rsTpTopLine;
    rbpBottom: Result := rsTpBottomLine;
    rbpLeft: Result := rsTpLeftLine;
    rbpRight: Result := rsTpRightLine;
    rbpInsideH: Result := rsTpInsideH;
  else
    Result := rsTpInsideV;
  end;
end;

{ ---- what is selected ---- }

{ How many cells row ARow has (CellProps answers Valid empty past the last). }
function CellCount(ARich: TTyCustomRichEdit; APos: TTyRichPos; ARow: Integer): Integer;
begin
  Result := 0;
  while ARich.Document.CellProps(APos, ARow, Result).Valid <> [] do Inc(Result);
end;

function TableSelectionText(ARich: TTyCustomRichEdit): string;
var
  rng: TTyRichCellRange;
  pos: TTyRichPos;
  r, c, rows, cols: Integer;
begin
  Result := '';
  rng := ARich.SelectedCells;
  if not rng.InTable then
  begin
    if ARich.CaretCell(pos, r, c) then Result := Format(rsTpCell, [r + 1, c + 1]);
    Exit;
  end;
  if not ARich.Document.TableRowIndex(ARich.Document.Text.ParaOfPos(rng.TablePos), r, rows) then
    rows := rng.Row1 + 1;
  cols := CellCount(ARich, rng.TablePos, rng.Row1);
  if rng.WholeTable or ((rng.Row0 = 0) and (rng.Row1 = rows - 1) and (rng.Col0 = 0) and
    (rng.Col1 = cols - 1)) then
    Result := Format(rsTpTable, [rows, cols])
  else if (rng.Col0 = 0) and (rng.Col1 = cols - 1) and (cols > 1) then
  begin
    if rng.Row0 = rng.Row1 then Result := Format(rsTpRowOne, [rng.Row0 + 1])
    else Result := Format(rsTpRows, [rng.Row0 + 1, rng.Row1 + 1]);
  end
  else if (rng.Row0 = 0) and (rng.Row1 = rows - 1) and (rows > 1) then
  begin
    if rng.Col0 = rng.Col1 then Result := Format(rsTpColumnOne, [rng.Col0 + 1])
    else Result := Format(rsTpColumns, [rng.Col0 + 1, rng.Col1 + 1]);
  end
  else if (rng.Row0 = rng.Row1) and (rng.Col0 = rng.Col1) then
    Result := Format(rsTpCell, [rng.Row0 + 1, rng.Col0 + 1])
  else
    Result := Format(rsTpCells, [rng.Row1 - rng.Row0 + 1, rng.Col1 - rng.Col0 + 1]);
end;

{ ---- the form ---- }

function AskTableProperties(ARich: TTyCustomRichEdit; var AProps: TTyRichTableProperties): Boolean;
var
  f: TTableForm;
begin
  f := TTableForm.Create(Application);
  try
    f.Prepare(ARich, AProps);
    Result := f.ShowModal = mrOk;
    if Result then f.Collect(AProps);
  finally
    f.Free;
  end;
end;

{ Two lines alike (no line: its width and colour say nothing). }
function SameLine(const A, B: TTyRichBorder): Boolean;
begin
  if (A.Style = rbsNone) and (B.Style = rbsNone) then Exit(True);
  Result := (A.Style = B.Style) and (A.WidthTwips = B.WidthTwips) and (A.Color = B.Color);
end;

function LineField(ALine: TTyRichCellLine): TTyRichTablePropField;
const
  Fields: array[TTyRichCellLine] of TTyRichTablePropField = (tpfLineLeft, tpfLineTop,
    tpfLineRight, tpfLineBottom, tpfLineInsideH, tpfLineInsideV);
begin
  Result := Fields[ALine];
end;

function PresetLines(APreset: TTyRichBorderPreset): TTyRichCellLines;
begin
  case APreset of
    rbpAll, rbpNone: Result := [rclLeft, rclTop, rclRight, rclBottom, rclInsideH, rclInsideV];
    rbpOutside: Result := [rclLeft, rclTop, rclRight, rclBottom];
    rbpInside: Result := [rclInsideH, rclInsideV];
    rbpTop: Result := [rclTop];
    rbpBottom: Result := [rclBottom];
    rbpLeft: Result := [rclLeft];
    rbpRight: Result := [rclRight];
    rbpInsideH: Result := [rclInsideH];
  else
    Result := [rclInsideV];
  end;
end;

procedure TTableForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
  FillLists;
end;

procedure TTableForm.FillLists;
var
  pr: TTyRichBorderPreset;
  w: Integer;

  procedure Colors(ABox: TTyColorBox; AFirst: TColor; const AFirstName: string);
  begin
    ABox.Style := [cbCustomColors];
    ABox.ClearColors;
    ABox.AddColor(AFirstName, AFirst);
    ABox.AddColor(rsTpBlack, clBlack);
    ABox.AddColor(rsTpGray, TColor($808080));
    ABox.AddColor(rsTpLightGray, TColor($D9D9D9));
    ABox.AddColor(rsTpWhite, clWhite);
    ABox.AddColor(rsTpRed, TColor($0000C0));
    ABox.AddColor(rsTpOrange, TColor($3399FF));
    ABox.AddColor(rsTpYellow, TColor($00FFFF));
    ABox.AddColor(rsTpLightYellow, TColor($CCF2FF));
    ABox.AddColor(rsTpGreen, TColor($50B000));
    ABox.AddColor(rsTpLightGreen, TColor($DAEFE2));
    ABox.AddColor(rsTpBlue, TColor($C07000));
    ABox.AddColor(rsTpLightBlue, TColor($F7EBDD));
    ABox.AddColor(rsTpPurple, TColor($A03070));
  end;

begin
  CboTableAlign.Items.Text := rsTpLeft + LineEnding + rsTpCenter + LineEnding + rsTpRight;
  CboRowRule.Items.Text := rsTpAuto + LineEnding + rsTpAtLeast + LineEnding + rsTpExactly;
  CboVAlign.Items.Text := rsTpTop + LineEnding + rsTpMiddle + LineEnding + rsTpBottom;
  CboLines.Items.Clear;
  CboLines.Items.Add(rsTpAsTheyAre);
  for pr := Low(TTyRichBorderPreset) to High(TTyRichBorderPreset) do
    CboLines.Items.Add(BorderPresetName(pr));
  CboLineStyle.Items.Text := rsTpStyleNone + LineEnding + rsTpSingle + LineEnding + rsTpDouble +
    LineEnding + rsTpDotted + LineEnding + rsTpDashed;
  CboLineWidth.Items.Clear;
  for w in CLineWidths do CboLineWidth.Items.Add(PointsText(w));
  Colors(ClrShading, clNone, rsTpNoColor);
  Colors(ClrLine, clDefault, rsTpAutoColor);
  // the swatches of "no colour" and "automatic": the ground and the text as the theme has them
  ClrShading.NoneColorColor := clWindow;
  ClrLine.DefaultColorColor := clWindowText;
end;

function TTableForm.PadEdit(ASide: TTyRowCellSide): TTyEdit;
begin
  case ASide of
    rcsLeft: Result := EdtPadLeft;
    rcsTop: Result := EdtPadTop;
    rcsRight: Result := EdtPadRight;
  else
    Result := EdtPadBottom;
  end;
end;

procedure TTableForm.ShowLength(AEdit: TTyEdit; ATwips: Integer; var AShown: Integer);
begin
  AShown := ATwips;
  if ATwips < 0 then AEdit.Text := '' else AEdit.Text := TwipsToCm(ATwips);
end;

{ The edit gives other twips than it showed (an empty field left empty: no). }
function TTableForm.LengthChanged(AEdit: TTyEdit; AShown: Integer; out ATwips: Integer): Boolean;
begin
  ATwips := AShown;
  if Trim(AEdit.Text) = '' then Exit(False);
  if not CmToTwips(AEdit.Text, ATwips) then Exit(False);
  Result := ATwips <> AShown;
end;

procedure TTableForm.Prepare(ARich: TTyCustomRichEdit; const AProps: TTyRichTableProperties);
var
  n: Integer;
  sd: TTyRowCellSide;
  ln: TTyRichCellLine;
  lineMixed, seen: Boolean;
  line: TTyRichBorder;

  function Alike(AField: TTyRichTablePropField): Boolean;
  begin
    Result := AField in AProps.Uniform;
  end;

begin
  FRich := ARich;
  seen := False;
  FFilling := True;
  try
    // the table
    if Alike(tpfAlign) then FAlign := Ord(AProps.Align) else FAlign := -1;
    CboTableAlign.ItemIndex := FAlign;
    if Alike(tpfIndent) then ShowLength(EdtIndent, AProps.Indent, FIndent)
    else ShowLength(EdtIndent, -1, FIndent);
    // the row: 0 as high as its content, else at least or exactly
    if not Alike(tpfRowHeight) then
    begin
      FRule := -1;
      ShowLength(EdtRowHeight, -1, FHeight);
    end
    else if AProps.RowHeight = 0 then
    begin
      FRule := 0;
      ShowLength(EdtRowHeight, -1, FHeight);
    end
    else
    begin
      if AProps.RowExact then FRule := 2 else FRule := 1;
      ShowLength(EdtRowHeight, AProps.RowHeight, FHeight);
    end;
    CboRowRule.ItemIndex := FRule;
    // the column (the caret's: the one ApplyTableProperties sets)
    if Alike(tpfColumnWidth) then ShowLength(EdtColWidth, AProps.ColumnWidth, FWidth)
    else ShowLength(EdtColWidth, -1, FWidth);
    // the cell
    if Alike(tpfVAlign) then FVAlign := Ord(AProps.VAlign) else FVAlign := -1;
    CboVAlign.ItemIndex := FVAlign;
    for sd := Low(sd) to High(sd) do
      if Alike(tpfPadding) then ShowLength(PadEdit(sd), AProps.Pad[sd], FPad[sd])
      else ShowLength(PadEdit(sd), -1, FPad[sd]);
    // the shading: a colour the list lacks is added under its number
    FShadingShown := Alike(tpfShading);
    FShading := AProps.Shading;
    if not FShadingShown then ClrShading.ItemIndex := -1
    else
    begin
      ClrShading.Selected := FShading;
      if ClrShading.Selected <> FShading then
      begin
        ClrShading.AddColor(Format('#%.6x', [ColorToRGB(FShading)]), FShading);
        ClrShading.Selected := FShading;
      end;
    end;
    // the lines: shown when every line the selection has is alike, else nothing shown
    lineMixed := False;
    line := TyRichBorder(rbsSingle, 10);
    for ln := Low(TTyRichCellLine) to High(TTyRichCellLine) do
      if LineField(ln) in AProps.Uniform then
        if not seen then
        begin
          line := AProps.Lines[ln];
          seen := True;
        end
        else if not SameLine(line, AProps.Lines[ln]) then lineMixed := True;
    // the outline's sides are in every selection: one of them mixed, the lines are
    for ln := rclLeft to rclBottom do
      if not (LineField(ln) in AProps.Uniform) then lineMixed := True;
    LblScope.Caption := Format(rsTpApplies, [TableSelectionText(ARich)]);
    CboLines.ItemIndex := 0;
    if lineMixed then
    begin
      CboLineStyle.ItemIndex := -1;
      CboLineWidth.ItemIndex := -1;
      ClrLine.ItemIndex := -1;
    end
    else
    begin
      // (a style of the file's that the control does not draw: shown as none of the list's)
      if Ord(line.Style) < CboLineStyle.Items.Count then
        CboLineStyle.ItemIndex := Ord(line.Style)
      else
        CboLineStyle.ItemIndex := -1;
      CboLineWidth.ItemIndex := -1;
      for n := 0 to High(CLineWidths) do
        if CLineWidths[n] = line.WidthTwips then CboLineWidth.ItemIndex := n;
      ClrLine.Selected := line.Color;
      if (line.Color <> clDefault) and (ClrLine.Selected <> line.Color) then
      begin
        ClrLine.AddColor(Format('#%.6x', [ColorToRGB(line.Color)]), line.Color);
        ClrLine.Selected := line.Color;
      end;
    end;
  finally
    FFilling := False;
  end;
end;

procedure TTableForm.LineChanged(Sender: TObject);
begin
  if FFilling then Exit;
  if CboLines.ItemIndex <= 0 then CboLines.ItemIndex := 1 + Ord(rbpAll);
end;

{ Lines picked (not "none"): a style, a width and a colour to draw them with. }
procedure TTableForm.LinesChanged(Sender: TObject);
begin
  if FFilling or (CboLines.ItemIndex <= 0) then Exit;
  if CboLineStyle.ItemIndex < 0 then CboLineStyle.ItemIndex := Ord(rbsSingle);
  if CboLineWidth.ItemIndex < 0 then CboLineWidth.ItemIndex := 0;
  if ClrLine.ItemIndex < 0 then ClrLine.ItemIndex := 0;
end;

procedure TTableForm.Refuse(AEdit: TTyEdit);
begin
  LblScope.Caption := rsTpBadLength;
  if AEdit.CanFocus then AEdit.SetFocus;
end;

{ OK: every length must be a number (or left empty); the row's height must be given for a
  rule that has one. }
procedure TTableForm.BtnOkClick(Sender: TObject);
var
  lengths: array[0..2] of TTyEdit;
  e: TTyEdit;
  t: Integer;
  sd: TTyRowCellSide;
begin
  lengths[0] := EdtIndent;
  lengths[1] := EdtRowHeight;
  lengths[2] := EdtColWidth;
  for e in lengths do
    if (Trim(e.Text) <> '') and not CmToTwips(e.Text, t) then
    begin
      Refuse(e);
      Exit;
    end;
  for sd := Low(sd) to High(sd) do
    if (Trim(PadEdit(sd).Text) <> '') and not CmToTwips(PadEdit(sd).Text, t) then
    begin
      Refuse(PadEdit(sd));
      Exit;
    end;
  if (CboRowRule.ItemIndex > 0) and (CboRowRule.ItemIndex <> FRule) and
    (Trim(EdtRowHeight.Text) = '') then
  begin
    LblScope.Caption := rsTpNoHeight;
    if EdtRowHeight.CanFocus then EdtRowHeight.SetFocus;
    Exit;
  end;
  ModalResult := mrOk;
end;

procedure TTableForm.Collect(var AProps: TTyRichTableProperties);
var
  t: Integer;
  sd: TTyRowCellSide;
  padChanged: Boolean;
  ln: TTyRichCellLine;
  line: TTyRichBorder;
begin
  AProps.Changed := [];
  // the table
  if (CboTableAlign.ItemIndex >= 0) and (CboTableAlign.ItemIndex <> FAlign) then
  begin
    Include(AProps.Changed, tpfAlign);
    AProps.Align := TTyRowAlign(CboTableAlign.ItemIndex);
  end;
  if LengthChanged(EdtIndent, FIndent, t) then
  begin
    Include(AProps.Changed, tpfIndent);
    AProps.Indent := t;
  end;
  // the row
  if ((CboRowRule.ItemIndex >= 0) and (CboRowRule.ItemIndex <> FRule)) or
    ((CboRowRule.ItemIndex > 0) and LengthChanged(EdtRowHeight, FHeight, t)) then
  begin
    Include(AProps.Changed, tpfRowHeight);
    if CboRowRule.ItemIndex = 0 then
    begin
      AProps.RowHeight := 0;
      AProps.RowExact := False;
    end
    else
    begin
      if not CmToTwips(EdtRowHeight.Text, t) then t := FHeight;
      AProps.RowHeight := t;
      AProps.RowExact := CboRowRule.ItemIndex = 2;
    end;
  end;
  // the column
  if LengthChanged(EdtColWidth, FWidth, t) and (t > 0) then
  begin
    Include(AProps.Changed, tpfColumnWidth);
    AProps.ColumnWidth := t;
  end;
  // the cell
  if (CboVAlign.ItemIndex >= 0) and (CboVAlign.ItemIndex <> FVAlign) then
  begin
    Include(AProps.Changed, tpfVAlign);
    AProps.VAlign := TTyRowCellVAlign(CboVAlign.ItemIndex);
  end;
  padChanged := False;
  for sd := Low(sd) to High(sd) do
    if LengthChanged(PadEdit(sd), FPad[sd], t) then
    begin
      AProps.Pad[sd] := t;
      padChanged := True;
    end
    else
      AProps.Pad[sd] := -1;   // a side as it is
  if padChanged then Include(AProps.Changed, tpfPadding);
  // the shading
  if (ClrShading.ItemIndex >= 0) and
    (not FShadingShown or (ClrShading.Selected <> FShading)) then
  begin
    Include(AProps.Changed, tpfShading);
    AProps.Shading := ClrShading.Selected;
  end;
  // the lines the preset names, each to the style, width and colour shown
  if CboLines.ItemIndex > 0 then
  begin
    line := TyRichBorder(rbsSingle, 10);
    if CboLineStyle.ItemIndex >= 0 then line.Style := TTyRichBorderStyle(CboLineStyle.ItemIndex);
    if CboLineWidth.ItemIndex >= 0 then line.WidthTwips := CLineWidths[CboLineWidth.ItemIndex];
    if ClrLine.ItemIndex >= 0 then line.Color := ClrLine.Selected else line.Color := clDefault;
    if TTyRichBorderPreset(CboLines.ItemIndex - 1) = rbpNone then line := TyRichBorder(rbsNone, 0);
    for ln in PresetLines(TTyRichBorderPreset(CboLines.ItemIndex - 1)) do
    begin
      AProps.Lines[ln] := line;
      Include(AProps.Changed, LineField(ln));
    end;
  end;
end;

end.
