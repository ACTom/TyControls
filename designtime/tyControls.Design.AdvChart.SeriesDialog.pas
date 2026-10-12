unit tyControls.Design.AdvChart.SeriesDialog;
{$mode objfpc}{$H+}

{ Design-time structured editor for TTyAdvanceChart.Option: the series as a
  list, the keys every series has as fields, the data as a grid, and a live
  preview -- reached from the option dialog's "Series && data" button and
  from the chart's context menu. [Batch 143]

  THIS UNIT MAKES NO DECISIONS, for the reason the option dialog next door
  gives: designtime/ is outside the test build. Every question -- which
  series there are and what to call them, which keys a type has, what a cell
  turns into, what deleting a category row deletes, what goes back into the
  text and what it costs -- is answered by tyControls.AdvChart.SeriesEdit,
  where tests/test.advchart.serieseditor.pas reaches it. That suite also
  reads THIS file and fails if it ever touches fcl-json or the patcher
  itself (TheSeriesDialogStaysAShell).

  WHAT GOES BACK. The model writes the edits into the user's own text,
  changing only what changed; everything it does not understand -- other
  keys, their order, comments, quoting -- stays as it was. When a write
  would drop comments (they sat inside something rewritten) or has to
  rewrite the whole text, OK asks first, and No leaves the dialog open. From
  the option dialog the result lands in the editor as one undoable change,
  so the text stays editable either way.

  Stock LCL widgets, as the option dialog and the CSS editor use: this is an
  IDE dialog, not the library's custom-drawn runtime UI. The preview is the
  library's own chart. Message boxes go through TyMessageDlg. }

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, ComCtrls, ExtCtrls, Grids,
  Graphics, Dialogs,
  tyControls.AdvChart.SeriesEdit, tyControls.AdvChart.Diagnose,
  tyControls.AdvanceChart;

type
  { In the interface for the same reason as TTyChartOptionDialog: a probe
    program can open it and drive it. }
  TTyChartSeriesDialog = class(TForm)
  private
    FModel: TTySeriesEditModel;
    FTable: TTyEditTable;
    FDsTable: TTyEditTable;
    FFieldPaths: TStringList;
    FLoading: Boolean;
    FList: TListBox;
    FAddType: TComboBox;
    FDeleteBtn, FUpBtn, FDownBtn: TButton;
    FType: TComboBox;
    FFields: TScrollBox;
    FFieldError: TLabel;
    FPages: TPageControl;
    FDataTab, FDatasetTab, FPreviewTab: TTabSheet;
    FGrid, FDsGrid: TStringGrid;
    FGridNote, FDsNote: TLabel;
    FAddRowBtn, FDelRowBtn, FAddColBtn, FDelColBtn: TButton;
    FDsAddRowBtn, FDsDelRowBtn, FDsAddColBtn, FDsDelColBtn: TButton;
    FDsPick: TComboBox;
    FIssues: TListBox;
    FWarn: TLabel;
    FPreview: TTyAdvanceChart;
    FTimer: TTimer;
    function Current: Integer;
    procedure FillList(ASelect: Integer);
    procedure Recaption(AIndex: Integer);
    procedure ShowSeries;
    procedure BuildFields;
    procedure LoadGrid(AGrid: TStringGrid; ATable: TTyEditTable);
    procedure ShowData;
    procedure ShowDataset;
    procedure UpdateButtons;
    procedure Changed;
    procedure ListSelect(Sender: TObject; User: Boolean);
    procedure AddClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure TypeChange(Sender: TObject);
    procedure FieldDone(Sender: TObject);
    procedure GridSetText(Sender: TObject; ACol, ARow: Integer; const Value: string);
    procedure DsGridSetText(Sender: TObject; ACol, ARow: Integer; const Value: string);
    procedure GridSelect(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
    procedure GridButton(Sender: TObject);
    procedure DsPickChange(Sender: TObject);
    procedure PageChange(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure OKClick(Sender: TObject);
    function NewButton(AParent: TWinControl; const ACaption: string;
      ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TButton;
  public
    constructor CreateFor; reintroduce;
    destructor Destroy; override;
    { Load AText into the dialog without showing it; False (Error says why)
      when it does not load. Execute's first half, public for a probe. }
    function Open(const AText: string): Boolean;
    function Error: string;
    { The text the dialog would write back now. }
    function ResultText: string;
    { False -- with a message shown -- when the text does not load; True when
      the user pressed OK, AText then carrying the edits. }
    function Execute(var AText: string): Boolean;
  end;

{ The dialog over AText; True when AText was changed. }
function TyEditChartSeries(var AText: string): Boolean;

resourcestring
  rsSerDlgTitle = 'Chart series and data';

implementation

uses
  tyControls.Dialogs;

resourcestring
  rsSerDlgSeries = 'Series';
  rsSerDlgAdd = 'Add';
  rsSerDlgDelete = 'Delete';
  rsSerDlgUp = 'Up';
  rsSerDlgDown = 'Down';
  rsSerDlgType = 'Type';
  rsSerDlgData = 'Data';
  rsSerDlgDataset = 'Dataset';
  rsSerDlgPreview = 'Preview';
  rsSerDlgAddRow = 'Add row';
  rsSerDlgDeleteRow = 'Delete row';
  rsSerDlgAddColumn = 'Add column';
  rsSerDlgDeleteColumn = 'Delete column';
  rsSerDlgHeaderRow = 'header';
  rsSerDlgNoDataset = 'This option has no dataset.';
  rsSerDlgNoSeries = 'Select a series to edit it.';
  rsSerDlgCannotOpen =
    'The option does not parse yet, so it cannot be edited as a structure: %s';
  rsSerDlgLosesComments =
    'Writing these changes back drops %d comment(s) that sat inside the parts '
    + 'being rewritten. Write them back anyway?';
  rsSerDlgRewritesWhole =
    'This option text cannot be patched piece by piece, so writing these '
    + 'changes back rewrites all of it: the layout goes, and %d comment(s) with '
    + 'it. Write it anyway?';
  rsSerDlgWarnLost = 'Writing back will drop %d comment(s).';
  rsSerDlgWarnWhole = 'Writing back will rewrite the whole text.';

const
  cFieldRow = 28;
  cFieldColWidth = 330;

function TyEditChartSeries(var AText: string): Boolean;
var
  dlg: TTyChartSeriesDialog;
  s: string;
begin
  s := AText;
  dlg := TTyChartSeriesDialog.CreateFor;
  try
    Result := dlg.Execute(s) and (s <> AText);
    if Result then AText := s;
  finally
    dlg.Free;
  end;
end;

function TTyChartSeriesDialog.NewButton(AParent: TWinControl;
  const ACaption: string; ALeft, ATop, AWidth: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

constructor TTyChartSeriesDialog.CreateFor;
var
  panel, pnlLeft, strip, pnlTop, pnlRight: TPanel;
  lbl: TLabel;
  types: TStringList;
  b: TButton;
begin
  inherited CreateNew(nil);
  Caption := rsSerDlgTitle;
  Width := 1000;
  Height := 700;
  Position := poScreenCenter;
  BorderStyle := bsSizeable;
  FModel := TTySeriesEditModel.Create;
  FFieldPaths := TStringList.Create;

  { ---- the bottom strip: issues / warn / buttons, top down. Ordered by Top,
    not by creation order -- lcl-code-created-align-order. ---- }
  FIssues := TListBox.Create(Self);
  FIssues.Name := 'IssueList';
  FIssues.Parent := Self;
  FIssues.Align := alBottom;
  FIssues.Top := 100;
  FIssues.Height := 80;

  FWarn := TLabel.Create(Self);
  FWarn.Name := 'WarnLabel';
  FWarn.Parent := Self;
  FWarn.Align := alBottom;
  FWarn.Top := 200;
  FWarn.WordWrap := True;
  FWarn.Font.Color := clRed;
  FWarn.BorderSpacing.Around := 6;
  FWarn.Caption := '';

  panel := TPanel.Create(Self);
  panel.Parent := Self;
  panel.Align := alBottom;
  panel.Top := 300;
  panel.Height := 40;
  panel.BevelOuter := bvNone;
  b := NewButton(panel, 'OK', panel.Width - 200, 8, 90, @OKClick);
  b.Anchors := [akTop, akRight];
  b.Default := True;
  b := NewButton(panel, 'Cancel', panel.Width - 100, 8, 90, nil);
  b.Anchors := [akTop, akRight];
  b.ModalResult := mrCancel;
  b.Cancel := True;

  { ---- left: the series list ---- }
  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 240;
  pnlLeft.BevelOuter := bvNone;

  lbl := TLabel.Create(Self);
  lbl.Parent := pnlLeft;
  lbl.Align := alTop;
  lbl.Caption := rsSerDlgSeries;
  lbl.BorderSpacing.Around := 4;

  strip := TPanel.Create(Self);
  strip.Parent := pnlLeft;
  strip.Align := alBottom;
  strip.Height := 68;
  strip.BevelOuter := bvNone;
  FAddType := TComboBox.Create(Self);
  FAddType.Name := 'AddType';
  FAddType.Parent := strip;
  FAddType.Left := 4;
  FAddType.Top := 4;
  FAddType.Width := 150;
  FAddType.Style := csDropDown;
  NewButton(strip, rsSerDlgAdd, 158, 4, 76, @AddClick);
  FDeleteBtn := NewButton(strip, rsSerDlgDelete, 4, 36, 76, @DeleteClick);
  FUpBtn := NewButton(strip, rsSerDlgUp, 81, 36, 76, @UpClick);
  FDownBtn := NewButton(strip, rsSerDlgDown, 158, 36, 76, @DownClick);

  FList := TListBox.Create(Self);
  FList.Name := 'SeriesList';
  FList.Parent := pnlLeft;
  FList.Align := alClient;
  FList.OnSelectionChange := @ListSelect;

  { ---- right: everything about the selected series. A panel of its own,
    because an alTop sibling of the list would take the form's full width,
    over the list. ---- }
  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := Self;
  pnlRight.Align := alClient;
  pnlRight.BevelOuter := bvNone;

  { ---- right top: type and the common fields ---- }
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := pnlRight;
  pnlTop.Align := alTop;
  pnlTop.Height := 210;
  pnlTop.BevelOuter := bvNone;

  strip := TPanel.Create(Self);
  strip.Parent := pnlTop;
  strip.Align := alTop;
  strip.Height := 32;
  strip.BevelOuter := bvNone;
  lbl := TLabel.Create(Self);
  lbl.Parent := strip;
  lbl.Caption := rsSerDlgType;
  lbl.Left := 8;
  lbl.Top := 8;
  FType := TComboBox.Create(Self);
  FType.Name := 'SeriesType';
  FType.Parent := strip;
  FType.Left := 140;
  FType.Top := 4;
  FType.Width := 200;
  FType.Style := csDropDown;
  FType.OnChange := @TypeChange;

  FFieldError := TLabel.Create(Self);
  FFieldError.Parent := pnlTop;
  FFieldError.Align := alBottom;
  FFieldError.Font.Color := clRed;
  FFieldError.BorderSpacing.Around := 4;
  FFieldError.Caption := '';

  FFields := TScrollBox.Create(Self);
  FFields.Name := 'Fields';
  FFields.Parent := pnlTop;
  FFields.Align := alClient;
  FFields.BorderStyle := bsNone;

  types := TStringList.Create;
  try
    TySeriesTypes(types);
    FAddType.Items.Assign(types);
    FType.Items.Assign(types);
  finally
    types.Free;
  end;
  if FAddType.Items.Count > 0 then FAddType.ItemIndex := 0;

  { ---- right: data / dataset / preview ---- }
  FPages := TPageControl.Create(Self);
  FPages.Parent := pnlRight;
  FPages.Align := alClient;
  FPages.OnChange := @PageChange;

  FDataTab := FPages.AddTabSheet;
  FDataTab.Caption := rsSerDlgData;
  FGridNote := TLabel.Create(Self);
  FGridNote.Parent := FDataTab;
  FGridNote.Align := alTop;
  FGridNote.WordWrap := True;
  FGridNote.BorderSpacing.Around := 4;
  strip := TPanel.Create(Self);
  strip.Parent := FDataTab;
  strip.Align := alBottom;
  strip.Height := 34;
  strip.BevelOuter := bvNone;
  FAddRowBtn := NewButton(strip, rsSerDlgAddRow, 4, 4, 110, @GridButton);
  FDelRowBtn := NewButton(strip, rsSerDlgDeleteRow, 118, 4, 110, @GridButton);
  FAddColBtn := NewButton(strip, rsSerDlgAddColumn, 232, 4, 110, @GridButton);
  FDelColBtn := NewButton(strip, rsSerDlgDeleteColumn, 346, 4, 110, @GridButton);
  FGrid := TStringGrid.Create(Self);
  FGrid.Name := 'DataGrid';
  FGrid.Parent := FDataTab;
  FGrid.Align := alClient;
  FGrid.OnSetEditText := @GridSetText;
  FGrid.OnSelectCell := @GridSelect;

  FDatasetTab := FPages.AddTabSheet;
  FDatasetTab.Caption := rsSerDlgDataset;
  FDsPick := TComboBox.Create(Self);
  FDsPick.Parent := FDatasetTab;
  FDsPick.Align := alTop;
  FDsPick.Style := csDropDownList;
  FDsPick.OnChange := @DsPickChange;
  FDsNote := TLabel.Create(Self);
  FDsNote.Parent := FDatasetTab;
  FDsNote.Align := alTop;
  FDsNote.Top := 100;
  FDsNote.WordWrap := True;
  FDsNote.BorderSpacing.Around := 4;
  strip := TPanel.Create(Self);
  strip.Parent := FDatasetTab;
  strip.Align := alBottom;
  strip.Height := 34;
  strip.BevelOuter := bvNone;
  FDsAddRowBtn := NewButton(strip, rsSerDlgAddRow, 4, 4, 110, @GridButton);
  FDsDelRowBtn := NewButton(strip, rsSerDlgDeleteRow, 118, 4, 110, @GridButton);
  FDsAddColBtn := NewButton(strip, rsSerDlgAddColumn, 232, 4, 110, @GridButton);
  FDsDelColBtn := NewButton(strip, rsSerDlgDeleteColumn, 346, 4, 110, @GridButton);
  FDsGrid := TStringGrid.Create(Self);
  FDsGrid.Name := 'DatasetGrid';
  FDsGrid.Parent := FDatasetTab;
  FDsGrid.Align := alClient;
  FDsGrid.OnSetEditText := @DsGridSetText;
  FDsGrid.OnSelectCell := @GridSelect;

  FPreviewTab := FPages.AddTabSheet;
  FPreviewTab.Caption := rsSerDlgPreview;
  FPreview := TTyAdvanceChart.Create(Self);
  FPreview.Parent := FPreviewTab;
  FPreview.Align := alClient;

  FPages.ActivePage := FDataTab;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 400;
  FTimer.OnTimer := @TimerTick;
end;

destructor TTyChartSeriesDialog.Destroy;
begin
  FreeAndNil(FTable);
  FreeAndNil(FDsTable);
  FreeAndNil(FFieldPaths);
  FreeAndNil(FModel);
  inherited Destroy;
end;

{ ---- the list ------------------------------------------------------------ }

function TTyChartSeriesDialog.Current: Integer;
begin
  Result := FList.ItemIndex;
  if Result >= FModel.SeriesCount then Result := -1;
end;

procedure TTyChartSeriesDialog.FillList(ASelect: Integer);
var i: Integer;
begin
  FLoading := True;
  try
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      for i := 0 to FModel.SeriesCount - 1 do
        FList.Items.Add(FModel.SeriesCaption(i));
    finally
      FList.Items.EndUpdate;
    end;
    if ASelect >= FList.Items.Count then ASelect := FList.Items.Count - 1;
    FList.ItemIndex := ASelect;
  finally
    FLoading := False;
  end;
  ShowSeries;
end;

procedure TTyChartSeriesDialog.Recaption(AIndex: Integer);
begin
  { replacing an item's text can drop the selection on some widgetsets;
    put it back without the selection handler rebuilding the panel }
  FLoading := True;
  try
    FList.Items[AIndex] := FModel.SeriesCaption(AIndex);
    FList.ItemIndex := AIndex;
  finally
    FLoading := False;
  end;
end;

procedure TTyChartSeriesDialog.ListSelect(Sender: TObject; User: Boolean);
begin
  if FLoading then Exit;
  ShowSeries;
end;

procedure TTyChartSeriesDialog.UpdateButtons;
var i: Integer;
begin
  i := Current;
  FDeleteBtn.Enabled := i >= 0;
  FUpBtn.Enabled := i > 0;
  FDownBtn.Enabled := (i >= 0) and (i < FModel.SeriesCount - 1);
  FType.Enabled := (i >= 0) and (FModel.SeriesNode(i) <> nil);
  FAddRowBtn.Enabled := (FTable <> nil) and FTable.Editable;
  FDelRowBtn.Enabled := (FTable <> nil) and FTable.Editable
    and (FGrid.Row >= 1) and (FGrid.Row <= FTable.RowCount);
  FAddColBtn.Enabled := (FTable <> nil) and FTable.CanAddColumn;
  FDelColBtn.Enabled := (FTable <> nil) and FTable.CanDeleteColumn(FGrid.Col - 1);
  FDsAddRowBtn.Enabled := (FDsTable <> nil) and FDsTable.Editable;
  FDsDelRowBtn.Enabled := (FDsTable <> nil) and FDsTable.Editable
    and (FDsGrid.Row >= 1) and (FDsGrid.Row <= FDsTable.RowCount);
  FDsAddColBtn.Enabled := (FDsTable <> nil) and FDsTable.CanAddColumn;
  FDsDelColBtn.Enabled := (FDsTable <> nil)
    and FDsTable.CanDeleteColumn(FDsGrid.Col - 1);
end;

procedure TTyChartSeriesDialog.ShowSeries;
var i: Integer;
begin
  i := Current;
  FLoading := True;
  try
    if i >= 0 then FType.Text := FModel.SeriesType(i) else FType.Text := '';
  finally
    FLoading := False;
  end;
  FFieldError.Caption := '';
  BuildFields;
  ShowData;
end;

procedure TTyChartSeriesDialog.AddClick(Sender: TObject);
begin
  FillList(FModel.AddSeries(FAddType.Text));
  Changed;
end;

procedure TTyChartSeriesDialog.DeleteClick(Sender: TObject);
var i: Integer;
begin
  i := Current;
  if i < 0 then Exit;
  FModel.DeleteSeries(i);
  FillList(i);
  Changed;
end;

procedure TTyChartSeriesDialog.UpClick(Sender: TObject);
var i: Integer;
begin
  i := Current;
  if i <= 0 then Exit;
  FModel.MoveSeries(i, i - 1);
  FillList(i - 1);
  Changed;
end;

procedure TTyChartSeriesDialog.DownClick(Sender: TObject);
var i: Integer;
begin
  i := Current;
  if (i < 0) or (i >= FModel.SeriesCount - 1) then Exit;
  FModel.MoveSeries(i, i + 1);
  FillList(i + 1);
  Changed;
end;

procedure TTyChartSeriesDialog.TypeChange(Sender: TObject);
var i: Integer;
begin
  if FLoading then Exit;
  i := Current;
  if i < 0 then Exit;
  FModel.SetSeriesType(i, FType.Text);
  Recaption(i);
  { the fields a type has are the catalog's to say }
  BuildFields;
  ShowData;
  Changed;
end;

{ ---- the fields ------------------------------------------------------------ }

procedure TTyChartSeriesDialog.BuildFields;
var
  i, k, x, y: Integer;
  f: TTySeriesFieldArray;
  lbl: TLabel;
  ed: TEdit;
  cb: TCheckBox;
begin
  FFields.DisableAutoSizing;
  try
    for k := FFields.ControlCount - 1 downto 0 do
      FFields.Controls[k].Free;
    FFieldPaths.Clear;
    i := Current;
    if (i < 0) or (FModel.SeriesNode(i) = nil) then
    begin
      lbl := TLabel.Create(Self);
      lbl.Parent := FFields;
      lbl.Left := 8;
      lbl.Top := 8;
      lbl.Caption := rsSerDlgNoSeries;
      Exit;
    end;
    f := FModel.Fields(i);
    for k := 0 to High(f) do
    begin
      FFieldPaths.Add(f[k].Path);
      x := 8 + (k mod 2) * cFieldColWidth;
      y := 4 + (k div 2) * cFieldRow;
      lbl := TLabel.Create(Self);
      lbl.Parent := FFields;
      lbl.Left := x;
      lbl.Top := y + 4;
      lbl.Caption := f[k].Path;
      if f[k].Kind = sfkBoolean then
      begin
        cb := TCheckBox.Create(Self);
        cb.Parent := FFields;
        cb.Left := x + 132;
        cb.Top := y + 2;
        cb.AllowGrayed := True;
        case FModel.FieldState(i, f[k].Path) of
          fsTrue: cb.State := cbChecked;
          fsFalse: cb.State := cbUnchecked;
        else
          cb.State := cbGrayed;
        end;
        cb.Tag := k;
        cb.OnClick := @FieldDone;
      end
      else
      begin
        ed := TEdit.Create(Self);
        ed.Parent := FFields;
        ed.Left := x + 132;
        ed.Top := y;
        ed.Width := cFieldColWidth - 150;
        ed.Text := FModel.FieldText(i, f[k].Path);
        ed.Tag := k;
        ed.OnEditingDone := @FieldDone;
      end;
    end;
  finally
    FFields.EnableAutoSizing;
  end;
end;

procedure TTyChartSeriesDialog.FieldDone(Sender: TObject);
var
  i: Integer;
  path, err: string;
begin
  i := Current;
  if (i < 0) or not (Sender is TControl) then Exit;
  if (TControl(Sender).Tag < 0) or (TControl(Sender).Tag >= FFieldPaths.Count) then Exit;
  path := FFieldPaths[TControl(Sender).Tag];
  err := '';
  if Sender is TCheckBox then
    case TCheckBox(Sender).State of
      cbChecked: FModel.SetFieldState(i, path, fsTrue);
      cbUnchecked: FModel.SetFieldState(i, path, fsFalse);
    else
      FModel.SetFieldState(i, path, fsAbsent);
    end
  else if Sender is TEdit then
    FModel.SetFieldText(i, path, TEdit(Sender).Text, err);
  FFieldError.Caption := err;
  Recaption(i);
  { an axis index decides which categories the grid shows }
  ShowData;
  Changed;
end;

{ ---- the grids -------------------------------------------------------------- }

procedure TTyChartSeriesDialog.LoadGrid(AGrid: TStringGrid; ATable: TTyEditTable);
var r, c: Integer;
begin
  FLoading := True;
  AGrid.BeginUpdate;
  try
    if (ATable = nil) or (ATable.ColCount = 0) then
    begin
      AGrid.RowCount := 1;
      AGrid.ColCount := 1;
      AGrid.Options := AGrid.Options - [goEditing];
      Exit;
    end;
    AGrid.ColCount := ATable.ColCount + 1;
    AGrid.RowCount := ATable.RowCount + 1;
    AGrid.FixedCols := 1;
    AGrid.FixedRows := 1;
    if ATable.Editable then AGrid.Options := AGrid.Options + [goEditing]
    else AGrid.Options := AGrid.Options - [goEditing];
    AGrid.Cells[0, 0] := '';
    for c := 0 to ATable.ColCount - 1 do
      AGrid.Cells[c + 1, 0] := ATable.ColCaption(c);
    for r := 0 to ATable.RowCount - 1 do
    begin
      if ATable.RowIsHeader(r) then AGrid.Cells[0, r + 1] := rsSerDlgHeaderRow
      else AGrid.Cells[0, r + 1] := IntToStr(r);
      for c := 0 to ATable.ColCount - 1 do
        AGrid.Cells[c + 1, r + 1] := ATable.Cells[c, r];
    end;
  finally
    AGrid.EndUpdate;
    FLoading := False;
  end;
end;

procedure TTyChartSeriesDialog.ShowData;
var i: Integer;
begin
  FreeAndNil(FTable);
  i := Current;
  if i >= 0 then
  begin
    FTable := FModel.SeriesTable(i);
    FGridNote.Caption := FTable.Note;
  end
  else
    FGridNote.Caption := rsSerDlgNoSeries;
  LoadGrid(FGrid, FTable);
  UpdateButtons;
end;

procedure TTyChartSeriesDialog.ShowDataset;
var i: Integer;
begin
  FreeAndNil(FDsTable);
  i := FDsPick.ItemIndex;
  if (i >= 0) and (i < FModel.DatasetCount) then
  begin
    FDsTable := FModel.DatasetTable(i);
    FDsNote.Caption := FDsTable.Note;
  end
  else
    FDsNote.Caption := rsSerDlgNoDataset;
  LoadGrid(FDsGrid, FDsTable);
  UpdateButtons;
end;

procedure TTyChartSeriesDialog.GridSetText(Sender: TObject; ACol, ARow: Integer;
  const Value: string);
begin
  if FLoading or (FTable = nil) or not FTable.Editable then Exit;
  if (ACol < 1) or (ARow < 1) or (ACol > FTable.ColCount) or (ARow > FTable.RowCount) then Exit;
  FTable.Cells[ACol - 1, ARow - 1] := Value;
  FModel.ApplySeriesTable(FTable);
  Changed;
end;

procedure TTyChartSeriesDialog.DsGridSetText(Sender: TObject; ACol, ARow: Integer;
  const Value: string);
begin
  if FLoading or (FDsTable = nil) or not FDsTable.Editable then Exit;
  if (ACol < 1) or (ARow < 1) or (ACol > FDsTable.ColCount)
    or (ARow > FDsTable.RowCount) then Exit;
  FDsTable.Cells[ACol - 1, ARow - 1] := Value;
  FModel.ApplyDatasetTable(FDsTable);
  Changed;
end;

procedure TTyChartSeriesDialog.GridSelect(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
begin
  CanSelect := True;
  UpdateButtons;
end;

procedure TTyChartSeriesDialog.GridButton(Sender: TObject);
var
  t: TTyEditTable;
  g: TStringGrid;
begin
  if (Sender = FAddRowBtn) or (Sender = FDelRowBtn) or (Sender = FAddColBtn)
    or (Sender = FDelColBtn) then
  begin
    t := FTable;
    g := FGrid;
  end
  else
  begin
    t := FDsTable;
    g := FDsGrid;
  end;
  if t = nil then Exit;
  if (Sender = FAddRowBtn) or (Sender = FDsAddRowBtn) then t.AppendRow
  else if (Sender = FDelRowBtn) or (Sender = FDsDelRowBtn) then t.DeleteRow(g.Row - 1)
  else if (Sender = FAddColBtn) or (Sender = FDsAddColBtn) then t.AppendColumn
  else t.DeleteColumn(g.Col - 1);
  if t = FTable then FModel.ApplySeriesTable(t) else FModel.ApplyDatasetTable(t);
  LoadGrid(g, t);
  UpdateButtons;
  Changed;
end;

procedure TTyChartSeriesDialog.DsPickChange(Sender: TObject);
begin
  ShowDataset;
end;

procedure TTyChartSeriesDialog.PageChange(Sender: TObject);
begin
  { a grid shows what the model says now: a dataset edit can change what a
    series' grid would show, and the other way round }
  if FPages.ActivePage = FDataTab then ShowData
  else if FPages.ActivePage = FDatasetTab then ShowDataset
  else if FPages.ActivePage = FPreviewTab then TimerTick(nil);
end;

{ ---- feedback ---------------------------------------------------------------- }

procedure TTyChartSeriesDialog.Changed;
begin
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TTyChartSeriesDialog.TimerTick(Sender: TObject);
var
  d: TTyOptDiagArray;
  i: Integer;
  s: string;
begin
  FTimer.Enabled := False;
  s := FModel.Text;
  if FModel.RewritesWhole then FWarn.Caption := rsSerDlgWarnWhole
  else if FModel.Lost > 0 then FWarn.Caption := Format(rsSerDlgWarnLost, [FModel.Lost])
  else FWarn.Caption := '';
  d := FModel.Diagnose;
  FIssues.Items.BeginUpdate;
  try
    FIssues.Items.Clear;
    for i := 0 to High(d) do FIssues.Items.Add(d[i].Text);
  finally
    FIssues.Items.EndUpdate;
  end;
  { the preview only while it is looked at: re-reading a large option on
    every pause in typing is paid for nothing otherwise }
  if FPages.ActivePage = FPreviewTab then FPreview.Option := s;
end;

procedure TTyChartSeriesDialog.OKClick(Sender: TObject);
var msg: string;
begin
  { a field still being typed in when Enter pressed OK: commit it first --
    writing the same text twice changes nothing }
  if (ActiveControl is TEdit) and (ActiveControl.Parent = FFields) then
    FieldDone(ActiveControl);
  FModel.Text;
  if FModel.NeedsConfirm then
  begin
    if FModel.RewritesWhole then msg := Format(rsSerDlgRewritesWhole, [FModel.Lost])
    else msg := Format(rsSerDlgLosesComments, [FModel.Lost]);
    { No leaves the dialog open: the edits are not thrown away }
    if TyMessageDlg(msg, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  end;
  ModalResult := mrOK;
end;

function TTyChartSeriesDialog.Error: string;
begin
  Result := FModel.Error;
end;

function TTyChartSeriesDialog.ResultText: string;
begin
  Result := FModel.Text;
end;

function TTyChartSeriesDialog.Open(const AText: string): Boolean;
var i: Integer;
begin
  Result := FModel.Load(AText);
  if not Result then Exit;
  FDsPick.Items.Clear;
  for i := 0 to FModel.DatasetCount - 1 do
    FDsPick.Items.Add('dataset[' + IntToStr(i) + ']');
  if FDsPick.Items.Count > 0 then FDsPick.ItemIndex := 0;
  FDatasetTab.TabVisible := FModel.DatasetCount > 0;
  FillList(0);
  ShowDataset;
  TimerTick(nil);
end;

function TTyChartSeriesDialog.Execute(var AText: string): Boolean;
begin
  Result := False;
  if not Open(AText) then
  begin
    TyMessageDlg(Format(rsSerDlgCannotOpen, [FModel.Error]), mtError, [mbOK], 0);
    Exit;
  end;
  Result := ShowModal = mrOK;
  if Result then AText := FModel.Text;
end;

end.
