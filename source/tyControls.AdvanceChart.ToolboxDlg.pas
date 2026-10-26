unit tyControls.AdvanceChart.ToolboxDlg;
{$mode objfpc}{$H+}
{ The toolbox's two dialogs, in the library's own dialog family [Batch 125,
  C16].

  dataView: upstream lays a panel over the chart -- a heading, a textarea
  with the table text and two buttons, Refresh (left out when `readOnly`)
  and Close. Here it is a TTyDialog with the same parts: the heading is the
  dialog's caption, Refresh the default button (mrOK) and Close the cancel
  one. The colours upstream reads off the feature (backgroundColor,
  textColor, textareaColor, buttonColor ...) are the skin's here, as every
  dialog's are.

  The text sits on two pages of a TTyPageControl [spec 232]: Table (first,
  shown by default) lays each block of the text out as a TTyStringGrid --
  the header row of an axis block as the grid's header, a list block's
  first line (the series' name) as a heading above its grid, every other
  line a row and every tab a cell boundary -- and Text is the monospaced
  TTyMemo upstream's textarea is. Both pages edit the same text: switching
  pages carries the edits across, and Refresh takes the page the user is
  on, so the chart reads back the same text whichever page was used. The
  split is lossless (TyDvSplitTable / TyDvJoinTable): a text that is not a
  clean grid -- ragged rows, blank lines, a separator written by hand --
  shows as rows of different lengths and joins back byte for byte.

  saveAsImage: upstream makes the browser download the file; here the
  library's save dialog asks where, seeded with the name upstream would
  download as.

  TyBuildDataViewDialog makes the dialog without showing it, so a test can
  look at it; the Show calls are the thin layer the chart calls through its
  virtual seams (TTyCustomAdvanceChart.ToolboxShowDataView /
  ToolboxAskFileName).

  [spec 237] An optionToContent's content (TTyChartDataViewContent) gets
  the same dialog with the pages it calls for: Table when it holds tables
  (an html content's <table>s, or a table content's), each a grid as an
  axis block is -- its header row the grid's header, its caption the
  heading above it; Text for a text content's text, or for the text an
  html content holds outside its tables (read as the tooltip reads html,
  without its styles; never editable). A control content is shown in place
  of the pages. The pages do not carry edits across here: each holds its
  own part, and Refresh reads every part back into the content
  (TyBuildDataViewContentDialog / TyShowDataViewContentDialog, the seam
  TTyCustomAdvanceChart.ToolboxShowDataViewContent). }
interface
uses
  Classes, SysUtils, Controls, Forms, StdCtrls,
  tyControls.Dialogs, tyControls.Memo, tyControls.PageControl,
  tyControls.TabSheet, tyControls.Grid, tyControls.ScrollBox,
  tyControls.TyLabel, tyControls.AdvanceChart.Types,
  tyControls.AdvanceChart.Handlers;

type
  TTyDvRows = TTyChartDataViewRows;

  { One block of the data view's text as the table page holds it. Glue,
    First and the rows' cells joined by tabs and newlines are the block's
    text exactly. }
  TTyDvTableBlock = record
    { the separator in front of the block, as written ('' for the first) }
    Glue: string;
    { parseContents reads it as a table: First is the header row (the axis
      case); else First is the series' name }
    IsTable: Boolean;
    { the first line, as written }
    First: string;
    { every other line, split at each tab }
    Rows: TTyDvRows;
    { [spec 237] a content's table: its header row's cells (IsTable when
      there are any; First is unused) and the heading above it (HasHeading:
      Heading, none when it is ''); the text's blocks leave these empty }
    Header: TTyStringArray;
    HasHeading: Boolean;
    Heading: string;
  end;
  TTyDvTableBlockArray = array of TTyDvTableBlock;

  { The data view's pages: what TyBuildDataViewDialog hands a test, and the
    piece that keeps the two pages in step. Owned by the dialog. }
  TTyDataViewPages = class(TComponent)
  private
    FDialog: TTyDialog;
    FPages: TTyPageControl;
    FTablePage, FTextPage: TTyTabSheet;
    FMemo: TTyMemo;
    FBox: TTyScrollBox;
    FGrids: array of TTyStringGrid;
    FHeadings: array of TTyLabel;
    FBlocks: TTyDvTableBlockArray;
    FReadOnly: Boolean;
    { the text both pages showed when they were last put in step }
    FSynced: string;
    FFitting: Boolean;
    { [spec 237] a content's pages (no carrying edits across), and the
      content's control }
    FCustom: Boolean;
    FControl: TControl;
    procedure ClearTable;
    { the grids, one a block, from FBlocks }
    procedure LoadBlocks;
    { block AIndex's rows as its grid holds them now }
    function GridRows(AIndex: Integer): TTyDvRows;
    { several blocks: each grid as tall as its header and rows, at most the
      box -- again after every pass that lays the box's children out, when
      the grids' widths (and so their horizontal bars) are final }
    procedure FitHeights;
    procedure PagesChanging(Sender: TObject; ANewIndex: Integer;
      var AllowChange: Boolean);
    procedure DialogShow(Sender: TObject);
    function GetGrid(AIndex: Integer): TTyStringGrid;
    function GetHeading(AIndex: Integer): TTyLabel;
    function GetBlock(AIndex: Integer): TTyDvTableBlock;
  public
    { lays the table page out afresh from AText }
    procedure LoadTable(const AText: string);
    { the columns fitted to their cells and, with several blocks, each grid
      as tall as its rows (at most the page) -- again when the dialog shows,
      as the skin it adopts then sets the fonts and the row height }
    procedure FitTable;
    { the grids' cells joined back into the text (an open cell editor
      committed first) }
    function TableText: string;
    { the memo's lines joined by bare newlines, as a textarea's value is --
      no break after the last }
    function MemoText: string;
    { the content of the page the user is on }
    function Text: string;
    { [spec 237] a content's tables as the grids hold them now }
    function ReadTables: TTyChartDataViewTables;
    { [spec 237] what the user left: a text content's text from the memo,
      the tables from the grids -- an html content's html with the changed
      cells rewritten (TyHtmlSetCells) -- a control as it is }
    procedure ReadBack(var AContent: TTyChartDataViewContent);
    property Dialog: TTyDialog read FDialog;
    property Pages: TTyPageControl read FPages;
    property TablePage: TTyTabSheet read FTablePage;
    property TextPage: TTyTabSheet read FTextPage;
    property Memo: TTyMemo read FMemo;
    { several blocks: the headings and grids stacked in it; nil for one }
    property ScrollBox: TTyScrollBox read FBox;
    function GridCount: Integer;
    property Grids[AIndex: Integer]: TTyStringGrid read GetGrid;
    { the heading above grid AIndex, nil where there is none }
    property Headings[AIndex: Integer]: TTyLabel read GetHeading;
    property Blocks[AIndex: Integer]: TTyDvTableBlock read GetBlock;
    { [spec 237] a control content's control (nil otherwise) }
    property Control: TControl read FControl;
  end;

{ The data view's text as the table page splits it, and back. Lossless:
  TyDvJoinTable(TyDvSplitTable(S)) = S for every S. }
function TyDvSplitTable(const AText: string): TTyDvTableBlockArray;
function TyDvJoinTable(const ABlocks: TTyDvTableBlockArray): string;

{ The data view, not shown: both pages hold AText, the table page shown. }
function TyBuildDataViewDialog(const ATitle, AText: string; AReadOnly: Boolean;
  const ACloseCaption, ARefreshCaption: string; out APages: TTyDataViewPages): TTyDialog; overload;
{ the same, handing back only the text page's memo }
function TyBuildDataViewDialog(const ATitle, AText: string; AReadOnly: Boolean;
  const ACloseCaption, ARefreshCaption: string; out AMemo: TTyMemo): TTyDialog; overload;
{ The data view, modal: True when Refresh closed it, with the content of the
  page the user was on in AText. }
function TyShowDataViewDialog(const ATitle: string; var AText: string;
  AReadOnly: Boolean; const ACloseCaption, ARefreshCaption: string): Boolean;
{ [spec 237] An optionToContent's content, not shown: the pages it calls
  for (Table for its tables, Text for its text -- an html content's text
  outside its tables, read-only), or its control. AReadOnly: no Refresh
  (upstream's readOnly); AEditable: the cells and a text content's text
  can be edited (something reads them back). An html content's Tables are
  the caller's (TyHtmlTables of its Text). }
function TyBuildDataViewContentDialog(const ATitle: string;
  const AContent: TTyChartDataViewContent; AReadOnly, AEditable: Boolean;
  const ACloseCaption, ARefreshCaption: string; out APages: TTyDataViewPages): TTyDialog;
{ the same, modal: True when Refresh closed it, AContent then as the user
  left it (ReadBack). A control content's control is taken off the dialog
  before it goes, whichever button closed it. }
function TyShowDataViewContentDialog(const ATitle: string;
  var AContent: TTyChartDataViewContent; AReadOnly, AEditable: Boolean;
  const ACloseCaption, ARefreshCaption: string): Boolean;
{ The save dialog for saveAsImage: AFileName the suggested name in, the
  chosen path out. }
function TyAskImageFileName(var AFileName: string; const AType: string): Boolean;

implementation

uses tyControls.StrConsts, tyControls.Dialogs.FileDialog, tyControls.Columns,
  tyControls.AdvanceChart.Toolbox, tyControls.AdvanceChart.TipHtml;

const
  { the pages, logical px }
  cDvWidth = 560;
  cDvHeight = 360;

type
  { the grid's own measures of its chrome and header band }
  TDvGridAccess = class(TTyStringGrid);

  { the blocks' box: refits the grids' heights once its children are laid
    out. A grid's own OnResize comes too early -- inside the box's pass, which
    then sets the bounds it had worked out, and before the grid has settled
    its bars }
  TDvScrollBox = class(TTyScrollBox)
  protected
    procedure ControlsAligned; override;
  end;

{ ---- the split ---- }

{ S.split('\t') / S.split('\n'): every separator a boundary, so the pieces
  join back to S }
function SplitAll(const S: string; ASep: Char): TTyStringArray;
var
  i, start: Integer;
begin
  Result := nil;
  start := 1;
  for i := 1 to Length(S) do
    if S[i] = ASep then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Copy(S, start, i - start);
      start := i + 1;
    end;
  SetLength(Result, Length(Result) + 1);
  Result[High(Result)] := Copy(S, start, Length(S) - start + 1);
end;

function TyDvSplitTable(const AText: string): TTyDvTableBlockArray;
var
  blocks, glue, lines: TTyStringArray;
  b, i: Integer;
begin
  Result := nil;
  blocks := TyDataViewSplitBlocks(AText, glue);
  SetLength(Result, Length(blocks));
  for b := 0 to High(blocks) do
  begin
    Result[b].Glue := glue[b];
    Result[b].IsTable := TyDataViewIsTable(blocks[b]);
    lines := SplitAll(blocks[b], #10);
    Result[b].First := lines[0];
    SetLength(Result[b].Rows, High(lines));
    for i := 1 to High(lines) do
      Result[b].Rows[i - 1] := SplitAll(lines[i], #9);
  end;
end;

function TyDvJoinTable(const ABlocks: TTyDvTableBlockArray): string;
var
  b, i, j: Integer;
begin
  Result := '';
  for b := 0 to High(ABlocks) do
  begin
    Result := Result + ABlocks[b].Glue + ABlocks[b].First;
    for i := 0 to High(ABlocks[b].Rows) do
    begin
      Result := Result + #10;
      for j := 0 to High(ABlocks[b].Rows[i]) do
      begin
        if j > 0 then Result := Result + #9;
        Result := Result + ABlocks[b].Rows[i][j];
      end;
    end;
  end;
end;

{ ---- the pages ---- }

function TTyDataViewPages.GridCount: Integer;
begin
  Result := Length(FGrids);
end;

function TTyDataViewPages.GetGrid(AIndex: Integer): TTyStringGrid;
begin
  Result := FGrids[AIndex];
end;

function TTyDataViewPages.GetHeading(AIndex: Integer): TTyLabel;
begin
  Result := FHeadings[AIndex];
end;

function TTyDataViewPages.GetBlock(AIndex: Integer): TTyDvTableBlock;
begin
  Result := FBlocks[AIndex];
end;

procedure TTyDataViewPages.ClearTable;
var
  i: Integer;
  gs: array of TTyStringGrid;
  hs: array of TTyLabel;
begin
  { out of the lists first: freeing a child realigns the box, which refits
    what the lists still name }
  gs := FGrids;
  hs := FHeadings;
  FGrids := nil;
  FHeadings := nil;
  for i := 0 to High(gs) do
  begin
    gs[i].Free;
    hs[i].Free;
  end;
  FreeAndNil(FBox);
end;

procedure TTyDataViewPages.LoadTable(const AText: string);
begin
  ClearTable;
  FBlocks := TyDvSplitTable(AText);
  FSynced := AText;
  LoadBlocks;
end;

procedure TTyDataViewPages.LoadBlocks;
var
  host: TWinControl;
  b, i, j, cols, y: Integer;
  g: TTyStringGrid;
  lb: TTyLabel;
  head: TTyStringArray;
  heading: string;
  several, labelled: Boolean;
begin
  several := Length(FBlocks) > 1;
  host := FTablePage;
  if several then
  begin
    FBox := TDvScrollBox.Create(Self);
    FBox.Controller := FPages.Controller;
    FBox.Parent := FTablePage;
    FBox.Align := alClient;
    host := FBox;
  end;
  SetLength(FGrids, Length(FBlocks));
  SetLength(FHeadings, Length(FBlocks));
  { stacked top to bottom: the alTop controls are placed in the order of
    their Tops when the alignment runs, once, at the end }
  host.DisableAlign;
  try
  y := 0;
  for b := 0 to High(FBlocks) do
  begin
    { the header row's cells; a list block's name stays out of the grid }
    if Length(FBlocks[b].Header) > 0 then head := FBlocks[b].Header
    else if FBlocks[b].IsTable then head := SplitAll(FBlocks[b].First, #9)
    else head := nil;
    { a heading for each block of several (an axis block's: the series it
      holds), and always for a list block, whose name is nowhere else; a
      content's table has its caption, if any }
    lb := nil;
    if FBlocks[b].HasHeading then labelled := FBlocks[b].Heading <> ''
    else labelled := several or not FBlocks[b].IsTable;
    if labelled then
    begin
      if FBlocks[b].HasHeading then
        heading := FBlocks[b].Heading
      else if FBlocks[b].IsTable then
      begin
        heading := '';
        for j := 1 to High(head) do
        begin
          if heading <> '' then heading := heading + ', ';
          heading := heading + Trim(head[j]);
        end;
      end
      else
        heading := FBlocks[b].First;
      lb := TTyLabel.Create(Self);
      lb.Controller := FPages.Controller;
      lb.Caption := heading;
      lb.Top := y;
      Inc(y);
      lb.Parent := host;
      lb.Align := alTop;
    end;
    FHeadings[b] := lb;
    g := TTyStringGrid.Create(Self);
    g.Controller := FPages.Controller;
    g.Top := y;
    Inc(y);
    g.Parent := host;
    if several then
    begin
      g.Align := alTop;
      if b < High(FBlocks) then g.BorderSpacing.Bottom := FDialog.Px(TyDlgPad);
    end
    else
      g.Align := alClient;
    g.ReadOnly := FReadOnly;
    { the rows' order and the columns' are the text's: no sorting, no
      dragging columns about }
    g.Header.Options := g.Header.Options - [hoHeaderClickAutoSort, hoDrag];
    if FBlocks[b].IsTable then
      g.Header.Options := g.Header.Options + [hoVisible]
    else
      g.Header.Options := g.Header.Options - [hoVisible];
    cols := Length(head);
    for i := 0 to High(FBlocks[b].Rows) do
      if Length(FBlocks[b].Rows[i]) > cols then cols := Length(FBlocks[b].Rows[i]);
    for j := 0 to cols - 1 do
    begin
      g.Header.Columns.Add;
      if j <= High(head) then
        TTyColumn(g.Header.Columns.Items[j]).Text := head[j];
    end;
    g.RowCount := Length(FBlocks[b].Rows);
    for i := 0 to High(FBlocks[b].Rows) do
      for j := 0 to High(FBlocks[b].Rows[i]) do
        g.Cells[j, i] := FBlocks[b].Rows[i][j];
    g.Modified := False;
    FGrids[b] := g;
  end;
  finally
    host.EnableAlign;
  end;
  FitTable;
end;

procedure TTyDataViewPages.FitTable;
var
  b, j: Integer;
  g: TDvGridAccess;
begin
  for b := 0 to High(FGrids) do
  begin
    g := TDvGridAccess(FGrids[b]);
    for j := 0 to g.Header.Columns.Count - 1 do g.AutoFitColumnWidth(j);
  end;
  FitHeights;
end;

procedure TTyDataViewPages.FitHeights;
var
  b, need, cap: Integer;
  g: TDvGridAccess;
begin
  if (FBox = nil) or FFitting or (csDestroying in ComponentState) then Exit;
  FFitting := True;
  try
    cap := FBox.ClientHeight;
    for b := 0 to High(FGrids) do
    begin
      g := TDvGridAccess(FGrids[b]);
      { the chrome round the viewport (frame, a horizontal bar), the header
        band and the rows }
      need := g.Height - g.ViewportH + g.GridHeight;
      if hoVisible in g.Header.Options then Inc(need, g.HeaderHeightPx);
      if (cap > 0) and (need > cap) then need := cap;
      if need <> g.Height then g.Height := need;
    end;
  finally
    FFitting := False;
  end;
end;

procedure TDvScrollBox.ControlsAligned;
begin
  inherited ControlsAligned;
  if Owner is TTyDataViewPages then TTyDataViewPages(Owner).FitHeights;
end;

function TTyDataViewPages.GridRows(AIndex: Integer): TTyDvRows;
var
  i, j, n: Integer;
  g: TTyStringGrid;
begin
  g := FGrids[AIndex];
  if g.EditorMode then g.EditorMode := False;
  { a row keeps the cells it had and grows to its last filled one: an
    untouched row is its line again, an empty cell typed into past its
    end lengthens it }
  Result := nil;
  SetLength(Result, g.RowCount);
  for i := 0 to g.RowCount - 1 do
  begin
    n := 0;
    if i <= High(FBlocks[AIndex].Rows) then n := Length(FBlocks[AIndex].Rows[i]);
    for j := g.Header.Columns.Count - 1 downto n do
      if g.Cells[j, i] <> '' then
      begin
        n := j + 1;
        Break;
      end;
    SetLength(Result[i], n);
    for j := 0 to n - 1 do Result[i][j] := g.Cells[j, i];
  end;
end;

function TTyDataViewPages.TableText: string;
var
  bl: TTyDvTableBlockArray;
  b: Integer;
begin
  bl := Copy(FBlocks);
  for b := 0 to High(bl) do bl[b].Rows := GridRows(b);
  Result := TyDvJoinTable(bl);
end;

function TTyDataViewPages.ReadTables: TTyChartDataViewTables;
var b: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FGrids));
  for b := 0 to High(FGrids) do
  begin
    Result[b].Caption := FBlocks[b].Heading;
    Result[b].Header := Copy(FBlocks[b].Header);
    Result[b].Rows := GridRows(b);
  end;
end;

procedure TTyDataViewPages.ReadBack(var AContent: TTyChartDataViewContent);
begin
  case AContent.Kind of
    cdvText:
      if FMemo <> nil then AContent.Text := MemoText;
    cdvHtml:
      if FTablePage <> nil then
      begin
        AContent.Tables := ReadTables;
        { the html as the edited DOM would be: the changed cells rewritten }
        AContent.Text := TyHtmlSetCells(AContent.Text, AContent.Tables);
      end;
    cdvTable:
      if FTablePage <> nil then AContent.Tables := ReadTables;
  else
    { a control is read by whoever made it }
  end;
end;

function TTyDataViewPages.MemoText: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FMemo.Lines.Count - 1 do
  begin
    if i > 0 then Result := Result + #10;
    Result := Result + FMemo.Lines[i];
  end;
end;

function TTyDataViewPages.Text: string;
begin
  if FCustom then
  begin
    { a content's pages are not one text: the text page's, if any }
    if FMemo <> nil then Result := MemoText else Result := '';
  end
  else if FPages.ActivePage = FTextPage then Result := MemoText
  else Result := TableText;
end;

procedure TTyDataViewPages.PagesChanging(Sender: TObject; ANewIndex: Integer;
  var AllowChange: Boolean);
var t: string;
begin
  { the page being left hands its content to the one coming up -- only when
    it changed, so an untouched page keeps its scroll place and undo }
  if (FPages.ActivePage = FTablePage) and (ANewIndex = FTextPage.PageIndex) then
  begin
    t := TableText;
    if t <> FSynced then
    begin
      FMemo.Text := t;
      FSynced := t;
    end;
  end
  else if (FPages.ActivePage = FTextPage) and (ANewIndex = FTablePage.PageIndex) then
  begin
    t := MemoText;
    if t <> FSynced then LoadTable(t);
  end;
end;

procedure TTyDataViewPages.DialogShow(Sender: TObject);
begin
  FitTable;
end;

{ ---- the dialogs ---- }

function TyBuildDataViewDialog(const ATitle, AText: string; AReadOnly: Boolean;
  const ACloseCaption, ARefreshCaption: string; out APages: TTyDataViewPages): TTyDialog;
var
  pad, w, h: Integer;
  v: TTyDataViewPages;
begin
  Result := TTyDialog.CreateNew(Application);
  Result.Caption := ATitle;
  pad := Result.Px(TyDlgPad);
  w := Result.Px(cDvWidth);
  h := Result.Px(cDvHeight);
  v := TTyDataViewPages.Create(Result);
  v.FDialog := Result;
  v.FReadOnly := AReadOnly;
  v.FPages := TTyPageControl.Create(v);
  v.FPages.Parent := Result;
  v.FPages.SetBounds(Result.ContentRect.Left + pad, Result.ContentRect.Top + pad, w, h);
  v.FTablePage := v.FPages.AddPage(rsTyChartToolboxDataViewTable);
  v.FTextPage := v.FPages.AddPage(rsTyChartToolboxDataViewText);
  v.FMemo := TTyMemo.Create(v);
  v.FMemo.Parent := v.FTextPage;
  v.FMemo.Align := alClient;
  v.FMemo.ScrollBars := ssAutoBoth;
  v.FMemo.WordWrap := False;
  v.FMemo.Font.Name := 'Courier New';
  v.FMemo.Text := AText;
  v.FMemo.ReadOnly := AReadOnly;
  v.FPages.ActivePageIndex := 0;
  v.LoadTable(AText);
  v.FPages.OnChanging := @v.PagesChanging;
  Result.OnShow := @v.DialogShow;
  { upstream floats Refresh, then Close, to the right: Refresh is the
    rightmost }
  if not AReadOnly then Result.AddButton(ARefreshCaption, mrOK, True, False);
  Result.AddButton(ACloseCaption, mrCancel, AReadOnly, True);
  Result.AutoSizeToContent(w + 2 * pad, h + 2 * pad);
  APages := v;
end;

function TyBuildDataViewDialog(const ATitle, AText: string; AReadOnly: Boolean;
  const ACloseCaption, ARefreshCaption: string; out AMemo: TTyMemo): TTyDialog;
var v: TTyDataViewPages;
begin
  Result := TyBuildDataViewDialog(ATitle, AText, AReadOnly, ACloseCaption,
    ARefreshCaption, v);
  AMemo := v.Memo;
end;

function TyShowDataViewDialog(const ATitle: string; var AText: string;
  AReadOnly: Boolean; const ACloseCaption, ARefreshCaption: string): Boolean;
var
  d: TTyDialog;
  v: TTyDataViewPages;
begin
  d := TyBuildDataViewDialog(ATitle, AText, AReadOnly, ACloseCaption, ARefreshCaption, v);
  try
    Result := (d.ShowModal = mrOK) and not AReadOnly;
    if Result then AText := v.Text;
  finally
    d.Free;
  end;
end;

function TyBuildDataViewContentDialog(const ATitle: string;
  const AContent: TTyChartDataViewContent; AReadOnly, AEditable: Boolean;
  const ACloseCaption, ARefreshCaption: string; out APages: TTyDataViewPages): TTyDialog;
var
  pad, w, h, t: Integer;
  v: TTyDataViewPages;
  outside, txt: string;
  hasText: Boolean;
begin
  Result := TTyDialog.CreateNew(Application);
  Result.Caption := ATitle;
  pad := Result.Px(TyDlgPad);
  w := Result.Px(cDvWidth);
  h := Result.Px(cDvHeight);
  v := TTyDataViewPages.Create(Result);
  v.FDialog := Result;
  v.FReadOnly := not AEditable;
  v.FCustom := True;
  if AContent.Kind = cdvControl then
  begin
    { the author's own control, in place of the pages }
    if AContent.Control is TControl then
    begin
      v.FControl := TControl(AContent.Control);
      v.FControl.Parent := Result;
      v.FControl.SetBounds(Result.ContentRect.Left + pad, Result.ContentRect.Top + pad, w, h);
    end;
  end
  else
  begin
    { the text the content shows: a text content's, or what an html
      content holds outside its tables }
    hasText := False;
    txt := '';
    if AContent.Kind = cdvText then
    begin
      hasText := True;
      txt := AContent.Text;
    end
    else if AContent.Kind = cdvHtml then
    begin
      TyHtmlTables(AContent.Text, outside);
      txt := TyHtmlPlainText(outside);
      hasText := (Trim(txt) <> '') or (Length(AContent.Tables) = 0);
    end;
    v.FPages := TTyPageControl.Create(v);
    v.FPages.Parent := Result;
    v.FPages.SetBounds(Result.ContentRect.Left + pad, Result.ContentRect.Top + pad, w, h);
    if (AContent.Kind in [cdvHtml, cdvTable]) and (Length(AContent.Tables) > 0) then
    begin
      v.FTablePage := v.FPages.AddPage(rsTyChartToolboxDataViewTable);
      SetLength(v.FBlocks, Length(AContent.Tables));
      for t := 0 to High(AContent.Tables) do
      begin
        v.FBlocks[t].IsTable := Length(AContent.Tables[t].Header) > 0;
        v.FBlocks[t].Header := Copy(AContent.Tables[t].Header);
        v.FBlocks[t].Rows := Copy(AContent.Tables[t].Rows);
        v.FBlocks[t].HasHeading := True;
        v.FBlocks[t].Heading := AContent.Tables[t].Caption;
      end;
      v.LoadBlocks;
    end;
    if hasText then
    begin
      v.FTextPage := v.FPages.AddPage(rsTyChartToolboxDataViewText);
      v.FMemo := TTyMemo.Create(v);
      v.FMemo.Parent := v.FTextPage;
      v.FMemo.Align := alClient;
      v.FMemo.ScrollBars := ssAutoBoth;
      v.FMemo.WordWrap := False;
      v.FMemo.Font.Name := 'Courier New';
      v.FMemo.Text := txt;
      { the text of html is a reading of it, not something to edit }
      v.FMemo.ReadOnly := not AEditable or (AContent.Kind <> cdvText);
    end;
    v.FPages.ActivePageIndex := 0;
    Result.OnShow := @v.DialogShow;
  end;
  if not AReadOnly then Result.AddButton(ARefreshCaption, mrOK, True, False);
  Result.AddButton(ACloseCaption, mrCancel, AReadOnly, True);
  Result.AutoSizeToContent(w + 2 * pad, h + 2 * pad);
  APages := v;
end;

function TyShowDataViewContentDialog(const ATitle: string;
  var AContent: TTyChartDataViewContent; AReadOnly, AEditable: Boolean;
  const ACloseCaption, ARefreshCaption: string): Boolean;
var
  d: TTyDialog;
  v: TTyDataViewPages;
begin
  d := TyBuildDataViewContentDialog(ATitle, AContent, AReadOnly, AEditable,
    ACloseCaption, ARefreshCaption, v);
  try
    Result := (d.ShowModal = mrOK) and not AReadOnly;
    if Result then v.ReadBack(AContent);
  finally
    { the control outlives the dialog: its maker reads it, the chart frees
      it }
    if v.Control <> nil then v.Control.Parent := nil;
    d.Free;
  end;
end;

function TyAskImageFileName(var AFileName: string; const AType: string): Boolean;
var ext: string;
begin
  if AType = 'jpeg' then ext := 'jpeg' else ext := AType;
  Result := TySaveDialog(AFileName, rsTyChartToolboxImageFilter, ext);
end;

end.
