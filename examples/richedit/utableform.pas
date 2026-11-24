unit utableform;

{ The table properties form: the table's alignment and indent, the row's height and its rule,
  the column's width, the cell's vertical alignment and padding, the lines (which of them, their
  style, width and colour) and the shading - for the selected cells, else the caret's cell.

  The rich edit's TTyRichEditTableProperties asks it through OnBeforeExecute (the package has
  no such form of its own: this one is yours to copy). The form reads what it shows through the
  control's public members - SelectedCells, CaretCell, Document.CellProps and RowProps - and a
  value the selected cells do not share shows empty. On OK it hands back only what the person
  changed: the record's Valid names those fields, and the action applies them as ONE undo step
  (ApplyTableProperties). The lines are not in that record: a change of them is applied before
  it, through SetCellBorders, as an undo step of its own. Cancel changes nothing.

  Lengths are shown in centimetres (the control's are twips) through one pair of functions,
  TwipsToCm and CmToTwips; a field counts as changed only when the twips it gives differ from
  those it showed, so OK with nothing changed applies nothing and nothing drifts. Built from the
  package's controls (no native dialog). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, tyControls.Controller, tyControls.Form,
  tyControls.FormSurface, tyControls.TyLabel, tyControls.Edit, tyControls.ComboBox,
  tyControls.ColorBox, tyControls.GroupBox, tyControls.Button, tyControls.RichEdit.RowFormat,
  tyControls.RichEdit.TableProps, tyControls.RichEdit.TableSel, tyControls.RichEdit.Text,
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
    { Fills the form from ARich's selected cells (else the caret's cell). }
    procedure Prepare(ARich: TTyCustomRichEdit);
    { What the person changed: AProps' Valid names those fields (the others are left as
      they came); ALines True: the lines too, APreset with ALine. }
    procedure Collect(var AProps: TTyRichTableProperties; out ALines: Boolean;
      out APreset: TTyRichBorderPreset; out ALine: TTyRichBorder);
  end;

{ The table properties of ARich's selection, asked in the form: AProps in is what the action
  read at the caret (the record TTyRichEditTableProperties hands its OnBeforeExecute); out,
  Valid names only what was changed. ALines: the lines were changed (APreset, ALine). False:
  cancelled. }
function AskTableProperties(ARich: TTyCustomRichEdit; var AProps: TTyRichTableProperties;
  out ALines: Boolean; out APreset: TTyRichBorderPreset; out ALine: TTyRichBorder): Boolean;

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

{ The cells a format door takes (the selected ones, else the caret's), with the caret's cell. }
function TargetCells(ARich: TTyCustomRichEdit; out APos: TTyRichPos; out AR0, AC0, AR1,
  AC1: Integer): Boolean;
var
  rng: TTyRichCellRange;
begin
  rng := ARich.SelectedCells;
  if rng.InTable then
  begin
    APos := rng.TablePos;
    AR0 := rng.Row0;
    AC0 := rng.Col0;
    AR1 := rng.Row1;
    AC1 := rng.Col1;
    Exit(True);
  end;
  Result := ARich.CaretCell(APos, AR0, AC0);
  AR1 := AR0;
  AC1 := AC0;
end;

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

function AskTableProperties(ARich: TTyCustomRichEdit; var AProps: TTyRichTableProperties;
  out ALines: Boolean; out APreset: TTyRichBorderPreset; out ALine: TTyRichBorder): Boolean;
var
  f: TTableForm;
begin
  ALines := False;
  APreset := rbpAll;
  ALine := TyRichBorder(rbsSingle, 10);
  f := TTableForm.Create(Application);
  try
    f.Prepare(ARich);
    Result := f.ShowModal = mrOk;
    if Result then f.Collect(AProps, ALines, APreset, ALine);
  finally
    f.Free;
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

procedure TTableForm.Prepare(ARich: TTyCustomRichEdit);
const
  CMixed = Low(Integer);
var
  pos, cpos: TTyRichPos;
  r0, c0, r1, c1, r, c, n, cr, cc: Integer;
  rp: TTyRichRowProps;
  cp: TTyRichCellProps;
  sd: TTyRowCellSide;
  tAlign, tLeft, rHeight, valign: Integer;
  pad: array[TTyRowCellSide] of Integer;
  shade: TColor;
  shadeMixed, lineMixed, first, firstLine: Boolean;
  line: TTyRichBorder;
  w: Integer;

  procedure Take(var AAt: Integer; AValue: Integer; AFirst: Boolean);
  begin
    if AFirst then AAt := AValue
    else if AAt <> AValue then AAt := CMixed;
  end;

begin
  FRich := ARich;
  FFilling := True;
  try
    tAlign := CMixed;
    tLeft := CMixed;
    rHeight := CMixed;
    valign := CMixed;
    for sd := Low(sd) to High(sd) do pad[sd] := CMixed;
    shade := clNone;
    shadeMixed := True;
    lineMixed := True;
    line := TyRichBorder(rbsSingle, 10);
    FWidth := -1;
    if TargetCells(ARich, pos, r0, c0, r1, c1) then
    begin
      first := True;
      firstLine := True;
      lineMixed := False;
      shadeMixed := False;
      n := 0;
      for r := r0 to r1 do
      begin
        rp := ARich.Document.RowProps(pos, r);
        if rp.Valid = [] then Continue;
        Take(tAlign, Ord(rp.Align), r = r0);
        Take(tLeft, rp.LeftTwips, r = r0);
        Take(rHeight, rp.HeightTwips, r = r0);
        for c := c0 to c1 do
        begin
          cp := ARich.Document.CellProps(pos, r, c);
          if cp.Valid = [] then Break;
          Inc(n);
          Take(valign, Ord(cp.VAlign), first);
          for sd := Low(sd) to High(sd) do Take(pad[sd], cp.Pad[sd], first);
          if first then shade := cp.Shading
          else if shade <> cp.Shading then shadeMixed := True;
          first := False;
          for sd := Low(sd) to High(sd) do
            if firstLine then
            begin
              line := cp.Borders[sd];
              firstLine := False;
            end
            else if not TyRichSameBorder(line, cp.Borders[sd]) then lineMixed := True;
        end;
      end;
      if n = 0 then shadeMixed := True;
      // the column's width: the caret cell's (the column ApplyTableProperties sets)
      if ARich.CaretCell(cpos, cr, cc) then
      begin
        cp := ARich.Document.CellProps(cpos, cr, cc);
        if cp.Valid <> [] then FWidth := cp.WidthTwips;
      end;
      LblScope.Caption := Format(rsTpApplies, [TableSelectionText(ARich)]);
    end;
    // the table
    if tAlign = CMixed then FAlign := -1 else FAlign := tAlign;
    CboTableAlign.ItemIndex := FAlign;
    if tLeft = CMixed then tLeft := -1;
    ShowLength(EdtIndent, tLeft, FIndent);
    // the row: 0 as high as its content, > 0 at least, < 0 exactly
    if rHeight = CMixed then
    begin
      FRule := -1;
      ShowLength(EdtRowHeight, -1, FHeight);
    end
    else
    begin
      if rHeight = 0 then FRule := 0 else if rHeight > 0 then FRule := 1 else FRule := 2;
      if rHeight = 0 then ShowLength(EdtRowHeight, -1, FHeight)
      else ShowLength(EdtRowHeight, Abs(rHeight), FHeight);
    end;
    CboRowRule.ItemIndex := FRule;
    // the column
    w := FWidth;
    ShowLength(EdtColWidth, w, FWidth);
    // the cell
    if valign = CMixed then FVAlign := -1 else FVAlign := valign;
    CboVAlign.ItemIndex := FVAlign;
    for sd := Low(sd) to High(sd) do
    begin
      if pad[sd] = CMixed then pad[sd] := -1;
      ShowLength(PadEdit(sd), pad[sd], FPad[sd]);
    end;
    // the shading: a colour the list lacks is added under its number
    FShadingShown := not shadeMixed;
    FShading := shade;
    if shadeMixed then ClrShading.ItemIndex := -1
    else
    begin
      ClrShading.Selected := shade;
      if ClrShading.Selected <> shade then
      begin
        ClrShading.AddColor(Format('#%.6x', [ColorToRGB(shade)]), shade);
        ClrShading.Selected := shade;
      end;
    end;
    // the lines: what every side of every cell has, else nothing shown
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

{ A line's style, width or colour changed with the lines "as they are": all of them. }
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

procedure TTableForm.Collect(var AProps: TTyRichTableProperties; out ALines: Boolean;
  out APreset: TTyRichBorderPreset; out ALine: TTyRichBorder);
var
  t: Integer;
  sd: TTyRowCellSide;
  padChanged: Boolean;
begin
  AProps.Valid := [];
  // the table: its alignment and its indent go together (the record's one field pair)
  if ((CboTableAlign.ItemIndex >= 0) and (CboTableAlign.ItemIndex <> FAlign)) or
    LengthChanged(EdtIndent, FIndent, t) then
  begin
    Include(AProps.Valid, tpfAlign);
    if CboTableAlign.ItemIndex >= 0 then AProps.Align := TTyRowAlign(CboTableAlign.ItemIndex);
    if LengthChanged(EdtIndent, FIndent, t) then AProps.Indent := t;
  end;
  // the row
  if ((CboRowRule.ItemIndex >= 0) and (CboRowRule.ItemIndex <> FRule)) or
    ((CboRowRule.ItemIndex > 0) and LengthChanged(EdtRowHeight, FHeight, t)) then
  begin
    Include(AProps.Valid, tpfRowHeight);
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
    Include(AProps.Valid, tpfColumnWidth);
    AProps.ColumnWidth := t;
  end;
  // the cell
  if (CboVAlign.ItemIndex >= 0) and (CboVAlign.ItemIndex <> FVAlign) then
  begin
    Include(AProps.Valid, tpfVAlign);
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
  if padChanged then Include(AProps.Valid, tpfPadding);
  // the shading
  if (ClrShading.ItemIndex >= 0) and
    (not FShadingShown or (ClrShading.Selected <> FShading)) then
  begin
    Include(AProps.Valid, tpfShading);
    AProps.Shading := ClrShading.Selected;
  end;
  // the lines: their own door
  ALines := CboLines.ItemIndex > 0;
  APreset := rbpAll;
  ALine := TyRichBorder(rbsSingle, 10);
  if ALines then
  begin
    APreset := TTyRichBorderPreset(CboLines.ItemIndex - 1);
    if CboLineStyle.ItemIndex >= 0 then ALine.Style := TTyRichBorderStyle(CboLineStyle.ItemIndex);
    if CboLineWidth.ItemIndex >= 0 then ALine.WidthTwips := CLineWidths[CboLineWidth.ItemIndex];
    if ClrLine.ItemIndex >= 0 then ALine.Color := ClrLine.Selected else ALine.Color := clDefault;
  end;
end;

end.
