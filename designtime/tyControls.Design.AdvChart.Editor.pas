unit tyControls.Design.AdvChart.Editor;
{$mode objfpc}{$H+}

{ Design-time editor for TTyAdvanceChart.Option: a SynEdit dialog with
  catalog-driven completion, a browsable reference tree and a live diagnostics
  list, so a 2,455-node option tree is written with help rather than blind into
  a bare string box. Design-time ONLY -- the runtime library never sees SynEdit.

  THIS UNIT MAKES NO DECISIONS. Every question worth getting right -- what may
  be completed here, what a completion inserts, where a diagnostic points, what
  the status line says, whether a name is close enough to suggest -- is answered
  by a function in source/, where tests can reach it. designtime/ is not in the
  test build, so anything decided in here would be decided with nothing behind
  it. What is left below is layout and event plumbing, and that is the point:
  the file should be boring, and its boringness is checked by a guard in
  tests/test.designeditors.pas.

  Stock LCL widgets throughout. The library's no-raw-LCL rule governs its own
  custom-drawn runtime UI; this is an IDE dialog, and the precedent it follows
  -- Design.Css.Editor -- is stock TForm/TSynEdit/TTreeView. Message boxes still
  go through TyMessageDlg, as that precedent does. }

interface

uses
  { The dialog class is in the interface (see the note on it), so the widget
    types it is built from have to be too. Everything the BODY needs -- the
    catalog, the diagnostics, the descriptions -- stays in the implementation
    uses, where it belongs. }
  Classes, SysUtils, Controls, Forms, StdCtrls, ComCtrls, ExtCtrls, Graphics,
  SynEdit, SynCompletion, LCLType,
  PropEdits, ComponentEditors,
  tyControls.AdvChart.Complete, tyControls.AdvChart.Diagnose;

type
  { THE DIALOG ITSELF, in the interface rather than tucked into the
    implementation the way the CSS editor keeps its own.

    The reason is verification. Everything else in this feature is reachable
    from tests/; the dialog is the one piece that is not, because designtime/ is
    outside the test build -- and it is also the piece whose failures are
    layout, caret arithmetic and completion wiring against a real SynEdit, none
    of which a headless assertion could see anyway. Exposing it lets a probe
    program open it on Windows and drive it, which is the difference between a
    checklist a human works through and a program that already looked. }
  TTyChartOptionDialog = class(TForm)
  private
    FEdit: TSynEdit;
    FComplete: TSynCompletion;
    FTree: TTreeView;
    FFilter: TEdit;
    FDoc: TMemo;
    FIssues: TListBox;
    FWarn: TLabel;
    FPath: TLabel;
    FTimer: TTimer;
    { Set by a keystroke that could start a completion; consumed by OnChange,
      which fires AFTER the character has landed. }
    FWantComplete: Boolean;
    FDiags: TTyOptDiagArray;
    function TextBeforeCaret: string;
    procedure AddTreeRoots;
    procedure TreeExpanding(Sender: TObject; ANode: TTreeNode;
      var AllowExpansion: Boolean);
    procedure TreeChange(Sender: TObject; ANode: TTreeNode);
    procedure TreeDblClick(Sender: TObject);
    procedure IssuesDblClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure EditKeyPress(Sender: TObject; var Key: char);
    procedure EditStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    procedure CompletionExecute(Sender: TObject);
    function CompletionPaint(const AKey: string; ACanvas: TCanvas;
      X, Y: Integer; Selected: Boolean; Index: Integer): Boolean;
    procedure CompletionInsert(var Value: string; SourceValue: string;
      var SourceStart, SourceEnd: TPoint; KeyChar: TUTF8Char;
      Shift: TShiftState);
    procedure TimerTick(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure FormatClick(Sender: TObject);
  public
    constructor CreateFor; reintroduce;
    function Execute(var AText: string): Boolean;
  end;


  { paDialog editor for the Option string. '...' opens the chart dialog. }
  TTyChartOptionProperty = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  { Double-clicking the chart opens the same dialog. One verb, one code path --
    a second entry point that assembled the dialog differently is how the two
    drift apart. }
  TTyAdvanceChartEditor = class(TComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

implementation

uses
  Dialogs, TypInfo,
  SynEditTypes, SynHighlighterJScript,
  tyControls.AdvanceChart,
  tyControls.AdvChart.Catalog,
  tyControls.Design.AdvChart.Descs,
  tyControls.Dialogs;

resourcestring
  { WHICH CATALOGUE IS LOADED, by the idiom StrConsts documents at length for
    rsTyDateTimeNamesLang: a sentinel every shipped catalogue translates to its
    own language code, so a value differing from the compile-time one means
    exactly "someone loaded a catalogue". It lives in THIS unit's catalogue on
    purpose -- the help text then follows the same one as the buttons beside
    it, which is what was actually wrong: a Chinese IDE showed Chinese buttons
    and English help. }
  rsOptEdCatalogLang = '__locale__';
  rsOptEdTitle = 'Chart option (ECharts)';
  rsOptEdValidate = 'Validate';
  rsOptEdFormat = 'Format';
  rsOptEdFilter = 'Filter the reference';
  rsOptEdNoIssues = 'Nothing to report.';
  rsOptEdFormatDropsComments =
    'Formatting re-writes the option from its parsed form, which drops the '
    + 'comments and the original quoting. Continue?';

const
  { The detail rides inside the item string after a tab, not in a parallel
    array: SynCompletion re-filters and re-orders ItemList as typing continues,
    so anything kept alongside by index stops lining up. }
  cDetailSep = #9;
  { A catalog node index, parked on a tree node. Nothing is owned, so nothing
    leaks; the PATH is reconstructed by walking Parent. }
  cPlaceholder = '...';

constructor TTyChartOptionDialog.CreateFor;
var
  panel: TPanel;
  b: TButton;
  splitter: TSplitter;
begin
  inherited CreateNew(nil);
  Caption := rsOptEdTitle;
  Width := 900;
  Height := 600;
  Position := poScreenCenter;
  BorderStyle := bsSizeable;

  { ---- right: the reference, filter over tree over documentation ---- }
  FTree := TTreeView.Create(Self);
  FTree.Name := 'RefTree';
  FTree.Parent := Self;
  FTree.Align := alRight;
  FTree.Width := 300;
  FTree.ReadOnly := True;
  FTree.OnExpanding := @TreeExpanding;
  FTree.OnChange := @TreeChange;
  FTree.OnDblClick := @TreeDblClick;

  FFilter := TEdit.Create(Self);
  FFilter.Name := 'RefFilter';
  FFilter.Parent := FTree;
  FFilter.Align := alTop;
  FFilter.TextHint := rsOptEdFilter;
  FFilter.OnChange := @FilterChange;

  FDoc := TMemo.Create(Self);
  FDoc.Name := 'RefDoc';
  FDoc.Parent := FTree;
  FDoc.Align := alBottom;
  FDoc.Height := 150;
  FDoc.ReadOnly := True;
  FDoc.WordWrap := True;
  FDoc.ScrollBars := ssAutoVertical;

  splitter := TSplitter.Create(Self);
  splitter.Parent := Self;
  splitter.Align := alRight;

  { ---- the bottom strip: issues / warn / path / buttons, top down.

    ORDERED BY Top, NOT BY CREATION ORDER. Same-align siblings built in code all
    start at Top = 0, and what the aligner then does with them is not worth
    predicting -- built in the obvious order this strip came out warn / path /
    buttons / issues, putting the buttons in the middle of the form. For
    alBottom the largest Top sits lowest, so the numbers below are ordering
    keys and nothing else; the aligner overwrites them on the first layout.
    Repo memory: lcl-code-created-align-order. ---- }
  FIssues := TListBox.Create(Self);
  FIssues.Name := 'IssueList';
  FIssues.Parent := Self;
  FIssues.Align := alBottom;
  FIssues.Top := 100;
  FIssues.Height := 110;
  FIssues.OnDblClick := @IssuesDblClick;

  FWarn := TLabel.Create(Self);
  FWarn.Name := 'WarnLabel';
  FWarn.Parent := Self;
  FWarn.Align := alBottom;
  FWarn.Top := 200;
  FWarn.WordWrap := True;
  FWarn.Font.Color := clRed;
  FWarn.BorderSpacing.Around := 6;

  FPath := TLabel.Create(Self);
  FPath.Name := 'PathLabel';
  FPath.Parent := Self;
  FPath.Align := alBottom;
  FPath.Top := 300;
  FPath.BorderSpacing.Around := 6;

  panel := TPanel.Create(Self);
  panel.Parent := Self;
  panel.Align := alBottom;
  panel.Top := 400;
  panel.Height := 40;
  panel.BevelOuter := bvNone;

  b := TButton.Create(Self);
  b.Parent := panel;
  b.Caption := rsOptEdValidate;
  b.Left := 6;
  b.Top := 8;
  b.Width := 90;
  b.OnClick := @ValidateClick;

  b := TButton.Create(Self);
  b.Parent := panel;
  b.Caption := rsOptEdFormat;
  b.Left := 102;
  b.Top := 8;
  b.Width := 90;
  b.OnClick := @FormatClick;

  b := TButton.Create(Self);
  b.Parent := panel;
  b.Caption := 'OK';
  b.Anchors := [akTop, akRight];
  b.Left := panel.Width - 200;
  b.Top := 8;
  b.Width := 90;
  b.ModalResult := mrOK;
  b.Default := True;

  b := TButton.Create(Self);
  b.Parent := panel;
  b.Caption := 'Cancel';
  b.Anchors := [akTop, akRight];
  b.Left := panel.Width - 100;
  b.Top := 8;
  b.Width := 90;
  b.ModalResult := mrCancel;
  b.Cancel := True;

  { ---- the editor fills what is left ---- }
  FEdit := TSynEdit.Create(Self);
  FEdit.Name := 'OptionEdit';
  FEdit.Parent := Self;
  FEdit.Align := alClient;
  FEdit.Gutter.Visible := True;
  { Clicking past the end of a line must put the caret on the last real
    character: the slice handed to the completion is measured in bytes from the
    line start, and virtual space has no bytes. }
  FEdit.Options := FEdit.Options - [eoScrollPastEol];
  FEdit.OnChange := @EditChange;
  FEdit.OnKeyPress := @EditKeyPress;
  FEdit.OnStatusChange := @EditStatusChange;
  { A relaxed option tree IS a JavaScript object literal -- unquoted keys,
    single quotes, comments, trailing commas -- so the JS highlighter is the
    honest choice. There is no JSON highlighter in SynEdit, and a JSON one
    would flag the very spellings the reader accepts. }
  FEdit.Highlighter := TSynJScriptSyn.Create(Self);

  FComplete := TSynCompletion.Create(Self);
  FComplete.Editor := FEdit;
  FComplete.OnExecute := @CompletionExecute;
  FComplete.OnPaintItem := @CompletionPaint;
  FComplete.OnCodeCompletion := @CompletionInsert;
  FComplete.ShortCut := 16416;   { Ctrl+Space }
  FComplete.EndOfTokenChr := '{}()[]:;,+*/\ ''"=<>!%';

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 200;
  FTimer.OnTimer := @TimerTick;

  AddTreeRoots;
end;

function TTyChartOptionDialog.TextBeforeCaret: string;
begin
  { LogicalCaretXY, never CaretXY: CaretXY.X is a SCREEN column and
    LogicalCaretXY.X is a byte offset, and the slice is measured in bytes. In a
    library whose own demos carry CJK labels, the difference is a when and not
    an if. }
  Result := TyOptSliceBefore(FEdit.Text,
    FEdit.LogicalCaretXY.Y, FEdit.LogicalCaretXY.X);
end;

{ ---- the reference tree ---------------------------------------------------- }

procedure AddEdgeNodes(ATree: TTreeView; AParent: TTreeNode; ANode: Integer);
var
  edges: TTyOptEdgeArray;
  i: Integer;
  n: TTreeNode;
  cap: string;
begin
  edges := TyOptEdgesOf(ANode);
  for i := 0 to High(edges) do
  begin
    case edges[i].Kind of
      { A union member reads as the thing you would write to get it, so the
        twenty-three series shapes are discoverable by browsing rather than by
        knowing they exist. }
      oekVariant: cap := 'type = ' + edges[i].Name;
      oekArrayItem: cap := '[ ]';
    else
      cap := edges[i].Name;
    end;
    n := ATree.Items.AddChild(AParent, cap);
    n.Data := Pointer(PtrInt(edges[i].Node));
    if TyOptEdgesOf(edges[i].Node) <> nil then
      ATree.Items.AddChild(n, cPlaceholder);
  end;
end;

procedure TTyChartOptionDialog.AddTreeRoots;
begin
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    AddEdgeNodes(FTree, nil, TyOptRoot);
  finally
    FTree.Items.EndUpdate;
  end;
end;

procedure TTyChartOptionDialog.TreeExpanding(Sender: TObject; ANode: TTreeNode;
  var AllowExpansion: Boolean);
begin
  AllowExpansion := True;
  { Lazy: 2,455 nodes built up front would cost a visible pause every time the
    dialog opens, for a tree nobody expands more than a few branches of. }
  if (ANode.Count = 1) and (ANode.Items[0].Text = cPlaceholder) then
  begin
    FTree.Items.BeginUpdate;
    try
      ANode.Items[0].Delete;
      AddEdgeNodes(FTree, ANode, Integer(PtrInt(ANode.Data)));
    finally
      FTree.Items.EndUpdate;
    end;
  end;
end;

procedure TTyChartOptionDialog.TreeChange(Sender: TObject; ANode: TTreeNode);
var
  node: Integer;
  s: string;
begin
  FDoc.Clear;
  if ANode = nil then Exit;
  node := Integer(PtrInt(ANode.Data));
  s := TyOptSummary(node);
  if s <> '' then FDoc.Lines.Add(s);
  { The sentinel differs from its compile-time value exactly when a catalogue
    was loaded, and its msgstr names which one -- so the help text follows the
    same catalogue as the buttons around it. }
  s := TyOptDesc(node, Copy(LowerCase(rsOptEdCatalogLang), 1, 2) = 'zh');
  if s <> '' then FDoc.Lines.Add(s);
end;

procedure TTyChartOptionDialog.TreeDblClick(Sender: TObject);
var
  edges: TTyOptEdgeArray;
  kind: TTyOptEdgeKind;
  parentNode, i, dot: Integer;
  edgeName, tail, rowText: string;
begin
  if FTree.Selected = nil then Exit;
  rowText := FTree.Selected.Text;

  { A FILTER RESULT IS A PATH, NOT A KEY. Search hits are added as parentless
    rows rowTexted with the whole dotted path, and a parentless row otherwise
    means a child of the root -- so this took `xAxis.axisLabel` as an edge name
    and inserted `xAxis.axisLabel: `. A '.' is not a name character:
    AdvChart.Locate says so in its own comment, because `a.b: 1` is a spelling
    fcl-json cannot parse unquoted. Every filter hit below the top level
    inserted text the option reader rejects.

    The last segment is the key; the rest says where it lives, which is all the
    parent was ever wanted for. }
  dot := 0;
  for i := Length(rowText) downto 1 do
    if rowText[i] = '.' then begin dot := i; Break; end;

  if (FTree.Selected.Parent = nil) and (dot > 0) then
  begin
    parentNode := TyOptFind(Copy(rowText, 1, dot - 1)).Node;
    if parentNode < 0 then parentNode := TyOptRoot;
    rowText := Copy(rowText, dot + 1, MaxInt);
  end
  else if FTree.Selected.Parent = nil then
    parentNode := TyOptRoot
  else
    parentNode := Integer(PtrInt(FTree.Selected.Parent.Data));

  { Which edge of the parent this row is, so the inserted text can carry the
    right punctuation. }
  kind := oekProperty;
  edgeName := rowText;
  edges := TyOptEdgesOf(parentNode);
  for i := 0 to High(edges) do
    if Integer(PtrInt(FTree.Selected.Data)) = edges[i].Node then
    begin
      kind := edges[i].Kind;
      if kind <> oekArrayItem then edgeName := edges[i].Name;
      Break;
    end;

  if (FEdit.CaretY >= 1) and (FEdit.CaretY <= FEdit.Lines.Count) then
    tail := Copy(FEdit.Lines[FEdit.CaretY - 1], FEdit.CaretX, MaxInt)
  else
    tail := '';
  FEdit.InsertTextAtCaret(TyOptTreeInsert(parentNode, edgeName, kind, tail));
  FEdit.SetFocus;
end;

{ ---- diagnostics ----------------------------------------------------------- }

procedure TTyChartOptionDialog.TimerTick(Sender: TObject);
var i: Integer;
begin
  FTimer.Enabled := False;
  FDiags := TyOptDiagnose(FEdit.Text);
  FIssues.Items.BeginUpdate;
  try
    FIssues.Items.Clear;
    for i := 0 to High(FDiags) do
      FIssues.Items.Add(FDiags[i].Text);
    if Length(FDiags) = 0 then FIssues.Items.Add(rsOptEdNoIssues);
  finally
    FIssues.Items.EndUpdate;
  end;
  FWarn.Caption := '';
  for i := 0 to High(FDiags) do
    if FDiags[i].Kind = odkParseError then
    begin
      FWarn.Caption := FDiags[i].Text;
      Break;
    end;
end;

procedure TTyChartOptionDialog.IssuesDblClick(Sender: TObject);
var i: Integer;
begin
  i := FIssues.ItemIndex;
  if (i < 0) or (i > High(FDiags)) then Exit;
  if FDiags[i].Line <= 0 then Exit;
  FEdit.LogicalCaretXY := Point(FDiags[i].Col, FDiags[i].Line);
  FEdit.SetFocus;
end;

{ ---- the editor ------------------------------------------------------------ }

procedure TTyChartOptionDialog.EditKeyPress(Sender: TObject; var Key: char);
begin
  { A colon is in the set because it is what makes a value position -- and an
    enum list offerable -- so the popup should come up on it too. }
  FWantComplete := (Key in ['a'..'z', 'A'..'Z', '0'..'9', '_', '$', '-',
    '''', '"', ':']);
end;

procedure TTyChartOptionDialog.FilterChange(Sender: TObject);
var
  hits: TStringList;
  i: Integer;
  nd: TTreeNode;
begin
  { Empty means "show me the tree again", not "show me nothing". }
  if Trim(FFilter.Text) = '' then
  begin
    AddTreeRoots;
    Exit;
  end;

  hits := TStringList.Create;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    { Capped. A one-letter filter matches most of a 2,455-node catalog, and a
      list that long is not an answer -- it is the tree again, flattened. }
    TyOptSearch(FFilter.Text, hits, 200);
    for i := 0 to hits.Count - 1 do
    begin
      nd := FTree.Items.AddChild(nil, hits[i]);
      { Results are flat, dotted paths -- no lazy placeholder, because there is
        nothing to expand and a node that offered to expand into nothing is
        worse than one that does not offer.

        The node comes from the search, not from handing the path back to
        TyOptFind: two producers of the same path string is how a spelling
        mismatch gets in. }
      nd.Data := Pointer(PtrInt(hits.Objects[i]));
    end;
  finally
    FTree.Items.EndUpdate;
    hits.Free;
  end;
end;

procedure TTyChartOptionDialog.EditChange(Sender: TObject);
var
  before: string;
  list: TStringList;
  p: TPoint;
begin
  FTimer.Enabled := False;
  FTimer.Enabled := True;

  if not FWantComplete then Exit;
  FWantComplete := False;
  if (FComplete = nil) or FComplete.IsActive then Exit;

  before := TextBeforeCaret;
  list := TStringList.Create;
  try
    if not TyOptCompletionsAt(before, list) then
      if not TyOptVariantHelpAt(before, list) then Exit;
    if list.Count = 0 then Exit;
  finally
    list.Free;
  end;
  p := FEdit.ClientToScreen(
    FEdit.RowColumnToPixels(Point(FEdit.CaretX, FEdit.CaretY + 1)));
  FComplete.Execute(TyOptPartialAt(before), p.X, p.Y);
end;

procedure TTyChartOptionDialog.EditStatusChange(Sender: TObject;
  Changes: TSynStatusChanges);
begin
  if not (scCaretX in Changes) and not (scCaretY in Changes) then Exit;
  FPath.Caption := TyOptStatusAt(TextBeforeCaret);
end;

procedure TTyChartOptionDialog.CompletionExecute(Sender: TObject);
var
  before: string;
  list: TStringList;
  i: Integer;
  detail: string;
begin
  before := TextBeforeCaret;
  list := TStringList.Create;
  try
    if not TyOptCompletionsAt(before, list) then
      TyOptVariantHelpAt(before, list);
    FComplete.ItemList.BeginUpdate;
    try
      FComplete.ItemList.Clear;
      for i := 0 to list.Count - 1 do
      begin
        detail := TyOptCompletionDetail(before, list[i]);
        if detail <> '' then
          FComplete.ItemList.Add(list[i] + cDetailSep + detail)
        else
          FComplete.ItemList.Add(list[i]);
      end;
    finally
      FComplete.ItemList.EndUpdate;
    end;
  finally
    list.Free;
  end;
end;

function TTyChartOptionDialog.CompletionPaint(const AKey: string;
  ACanvas: TCanvas; X, Y: Integer; Selected: Boolean; Index: Integer): Boolean;
var
  p: Integer;
  { NOT `name`: TComponent.Name is in scope inside a method of a TForm
    descendant, and shadowing it is a duplicate-identifier error. }
  itemName, detail: string;
begin
  Result := True;
  p := Pos(cDetailSep, AKey);
  if p = 0 then
  begin
    ACanvas.TextOut(X, Y, AKey);
    Exit;
  end;
  itemName := Copy(AKey, 1, p - 1);
  detail := Copy(AKey, p + 1, MaxInt);
  ACanvas.TextOut(X, Y, itemName);
  ACanvas.Font.Color := clGrayText;
  ACanvas.TextOut(X + ACanvas.TextWidth(itemName) + 12, Y, detail);
end;

procedure TTyChartOptionDialog.CompletionInsert(var Value: string;
  SourceValue: string; var SourceStart, SourceEnd: TPoint;
  KeyChar: TUTF8Char; Shift: TShiftState);
var
  p, back: Integer;
  ins: string;
begin
  p := Pos(cDetailSep, Value);
  if p > 0 then Value := Copy(Value, 1, p - 1);
  if TyOptCompletionInsert(TextBeforeCaret, Value, ins, back) then
  begin
    Value := ins;
    if back > 0 then
      { The caret goes back INSIDE the punctuation the insert brought with it --
        between the braces, inside the quotes -- because that is where the next
        thing gets typed. }
      FEdit.LogicalCaretXY := Point(FEdit.LogicalCaretXY.X - back,
        FEdit.LogicalCaretXY.Y);
  end;
end;

{ ---- the buttons ----------------------------------------------------------- }

procedure TTyChartOptionDialog.ValidateClick(Sender: TObject);
var
  d: TTyOptDiagArray;
  s: string;
  i: Integer;
begin
  d := TyOptDiagnose(FEdit.Text);
  if Length(d) = 0 then
  begin
    TyMessageDlg(rsOptEdNoIssues, mtInformation, [mbOK], 0);
    Exit;
  end;
  s := '';
  for i := 0 to High(d) do
    s := s + d[i].Text + LineEnding;
  TyMessageDlg(s, mtInformation, [mbOK], 0);
end;

procedure TTyChartOptionDialog.FormatClick(Sender: TObject);
var
  outp, src: string;
begin
  src := FEdit.Text;
  { Formatting re-serialises the parsed tree, so comments and the original
    quoting do not survive it. Ask before destroying something the author
    typed on purpose. }
  if ((Pos('//', src) > 0) or (Pos('/*', src) > 0))
    and (TyMessageDlg(rsOptEdFormatDropsComments, mtConfirmation,
      [mbYes, mbNo], 0) <> mrYes) then Exit;
  if TyOptFormat(src, outp) then FEdit.Text := outp;
end;

function TTyChartOptionDialog.Execute(var AText: string): Boolean;
begin
  FEdit.Text := AText;
  TimerTick(nil);
  Result := ShowModal = mrOK;
  { The text goes back whatever state it is in. OK is never disabled: the
    control's Option property reads back what was written, so committing
    half-finished text loses nothing -- and the commonest thing anyone does
    here is paste an ECharts config that needs one edit before it parses. }
  if Result then AText := TrimRight(FEdit.Text);
end;

{ ---- the property and component editors ------------------------------------ }

function TTyChartOptionProperty.GetAttributes: TPropertyAttributes;
begin
  Result := inherited GetAttributes + [paDialog, paRevertable];
end;

procedure TTyChartOptionProperty.Edit;
var
  dlg: TTyChartOptionDialog;
  s: string;
begin
  s := GetStrValue;
  dlg := TTyChartOptionDialog.CreateFor;
  try
    if dlg.Execute(s) then SetStrValue(s);
  finally
    dlg.Free;
  end;
end;

function TTyAdvanceChartEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TTyAdvanceChartEditor.GetVerb(Index: Integer): string;
begin
  Result := rsOptEdTitle + '...';
end;

procedure TTyAdvanceChartEditor.ExecuteVerb(Index: Integer);
var
  dlg: TTyChartOptionDialog;
  chart: TTyAdvanceChart;
  s: string;
begin
  if not (GetComponent is TTyAdvanceChart) then Exit;
  chart := TTyAdvanceChart(GetComponent);
  s := chart.Option;
  dlg := TTyChartOptionDialog.CreateFor;
  try
    if dlg.Execute(s) then
    begin
      chart.Option := s;
      Modified;
    end;
  finally
    dlg.Free;
  end;
end;

end.
