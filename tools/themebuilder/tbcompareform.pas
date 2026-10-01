unit tbcompareform;
{ The AI comparison (spec §7.3, step 5): the editor's text on the left, the AI's version on
  the right, side by side and lined up (a line one side does not have is an empty filler
  row), changed and removed lines tinted on the left, changed and added ones on the right,
  the two sides scrolling together. Below, the problems the checks left. "Try it in the
  preview" swaps the preview to the AI's version until it is unticked or the window closes
  (OnTrial -- the main window does the swapping); Accept and Discard close the window.
  Accepting is allowed with problems left: the user decides (spec §7.3, step 4).

  The two text panes are read-only SynEdits -- the same control, highlighter and colours as
  the editor (tbeditorlook): the library has no Ty control that shows a thousand lines of
  code monospaced with per-line backgrounds, and this window shows exactly the editor's kind
  of text. This extends spec §6's one exception (the editor) to this window. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Graphics, LCLType,
  SynEdit, SynEditTypes, SynEditMiscClasses,
  tyControls.Controller, tyControls.Form, tyControls.FormSurface, tyControls.TyLabel,
  tyControls.Panel, tyControls.Button, tyControls.CheckBox, tyControls.ListBox,
  tyControls.Splitter, tyControls.Design.CssEditKit,
  tbeditorlook, tbdiff, tbaisession;

resourcestring
  rsTbCompareSummary = '%d changes. Problems left: %d.';
  rsTbCompareTrialFailed = 'The preview cannot show it: %s';

type
  TTbTrialEvent = procedure(Sender: TObject; AOn: Boolean; out AError: string) of object;

  TTbCompareForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    Summary: TTyLabel;
    Headers: TTyPanel;
    LeftTitle: TTyLabel;
    RightTitle: TTyLabel;
    Buttons: TTyPanel;
    BtnDiscard: TTyButton;
    BtnAccept: TTyButton;
    TrialCheck: TTyCheckBox;
    IssuesList: TTyListBox;
    LeftEdit: TSynEdit;
    Splitter: TTySplitter;
    RightEdit: TSynEdit;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormResize(Sender: TObject);
    procedure EditSpecialLineMarkup(Sender: TObject; Line: Integer; var Special: Boolean;
      Markup: TSynSelectedColor);
    procedure EditStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    procedure TrialCheckChange(Sender: TObject);
    procedure BtnAcceptClick(Sender: TObject);
  private
    FRows: TTbDiffRows;
    FLeftKinds, FRightKinds: array of Integer;   { per editor line: Ord(TTbDiffKind), or cFiller }
    FLook: TTbEditorColors;
    FKitLeft, FKitRight: TTyCssEditKit;
    FSyncing: Boolean;
    FUpdating: Boolean;
    FAccepted: Boolean;
    FTrialOn: Boolean;
    FSummaryBase: string;
    FOnTrial: TTbTrialEvent;
    procedure EndTrial;
  public
    procedure Prepare(const ABase, ACandidate: string; const AIssues: TTbAiIssues;
      const ALook: TTbEditorColors);
    { FOR THE TESTS: the kind of the row an editor line (1-based) shows; a filler answers
      with the other side's kind }
    function RowKindAt(ARight: Boolean; AEditorLine: Integer): TTbDiffKind;
    property Rows: TTbDiffRows read FRows;
    property Accepted: Boolean read FAccepted;
    property OnTrial: TTbTrialEvent read FOnTrial write FOnTrial;
  end;

implementation

{$R *.lfm}

const
  cFiller = 99;

procedure TTbCompareForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
  { the editor's highlighting; no completion in a read-only pane }
  FKitLeft := TTyCssEditKit.Create(Self);
  FKitLeft.AutoComplete := False;
  FKitLeft.FormatOnLineLeave := False;
  FKitLeft.Attach(LeftEdit, True);
  FKitRight := TTyCssEditKit.Create(Self);
  FKitRight.AutoComplete := False;
  FKitRight.FormatOnLineLeave := False;
  FKitRight.Attach(RightEdit, True);
end;

procedure TTbCompareForm.FormDestroy(Sender: TObject);
begin
  { a test frees the window without showing it: the trial still ends }
  EndTrial;
  FOnTrial := nil;
  LeftEdit.OnSpecialLineMarkup := nil;
  RightEdit.OnSpecialLineMarkup := nil;
  LeftEdit.OnStatusChange := nil;
  RightEdit.OnStatusChange := nil;
  if FKitLeft <> nil then FKitLeft.Detach;
  if FKitRight <> nil then FKitRight.Detach;
end;

procedure TTbCompareForm.EndTrial;
var
  err: string;
begin
  if not FTrialOn then Exit;
  FTrialOn := False;
  if Assigned(FOnTrial) then
    FOnTrial(Self, False, err);
end;

procedure TTbCompareForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  EndTrial;      { Accept, Discard, the title bar's close, Esc: the preview goes back }
end;

procedure TTbCompareForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    ModalResult := mrCancel;
  end;
end;

procedure TTbCompareForm.FormResize(Sender: TObject);
begin
  LeftEdit.Width := (Surface.ClientWidth - Splitter.Width) div 2;
  LeftTitle.Width := LeftEdit.Width - LeftTitle.Left;
  RightTitle.Left := LeftEdit.Width + Splitter.Width + LeftTitle.Left;
  RightTitle.Width := Headers.ClientWidth - RightTitle.Left;
end;

procedure TTbCompareForm.Prepare(const ABase, ACandidate: string; const AIssues: TTbAiIssues;
  const ALook: TTbEditorColors);
var
  a, b, leftLines, rightLines: TStringList;
  i: Integer;
  r: TTbDiffRow;
begin
  a := TStringList.Create;
  b := TStringList.Create;
  leftLines := TStringList.Create;
  rightLines := TStringList.Create;
  try
    TbSplitLines(ABase, a);
    TbSplitLines(ACandidate, b);
    FRows := TbDiffLines(a, b);
    SetLength(FLeftKinds, Length(FRows));
    SetLength(FRightKinds, Length(FRows));
    for i := 0 to High(FRows) do
    begin
      r := FRows[i];
      if r.Left >= 0 then
      begin
        leftLines.Add(a[r.Left]);
        FLeftKinds[i] := Ord(r.Kind);
      end
      else
      begin
        leftLines.Add('');
        FLeftKinds[i] := cFiller;
      end;
      if r.Right >= 0 then
      begin
        rightLines.Add(b[r.Right]);
        FRightKinds[i] := Ord(r.Kind);
      end
      else
      begin
        rightLines.Add('');
        FRightKinds[i] := cFiller;
      end;
    end;
    LeftEdit.Lines.Assign(leftLines);
    RightEdit.Lines.Assign(rightLines);
  finally
    a.Free;
    b.Free;
    leftLines.Free;
    rightLines.Free;
  end;
  FLook := ALook;
  TbApplyEditorColors(LeftEdit, FKitLeft.Highlighter, ALook);
  TbApplyEditorColors(RightEdit, FKitRight.Highlighter, ALook);
  FSummaryBase := Format(rsTbCompareSummary, [TbDiffChangeCount(FRows), TbIssueErrorCount(AIssues)]);
  Summary.Caption := FSummaryBase;
  IssuesList.Items.BeginUpdate;
  try
    IssuesList.Items.Clear;
    for i := 0 to High(AIssues) do
      IssuesList.Items.Add(TbAiIssueCaption(AIssues[i]));
  finally
    IssuesList.Items.EndUpdate;
  end;
  IssuesList.Visible := Length(AIssues) > 0;
  BtnAccept.Enabled := True;     { problems left or not, the user decides }
end;

function TTbCompareForm.RowKindAt(ARight: Boolean; AEditorLine: Integer): TTbDiffKind;
var
  i, k: Integer;
begin
  i := AEditorLine - 1;
  Result := tdkSame;
  if (i < 0) or (i > High(FRows)) then Exit;
  if ARight then k := FRightKinds[i] else k := FLeftKinds[i];
  if k = cFiller then
  begin
    if ARight then k := FLeftKinds[i] else k := FRightKinds[i];
  end;
  if k <> cFiller then
    Result := TTbDiffKind(k);
end;

procedure TTbCompareForm.EditSpecialLineMarkup(Sender: TObject; Line: Integer;
  var Special: Boolean; Markup: TSynSelectedColor);
var
  i, k: Integer;
  onRight: Boolean;
begin
  i := Line - 1;
  if (i < 0) or (i > High(FRows)) then Exit;
  onRight := Sender = RightEdit;
  if onRight then k := FRightKinds[i] else k := FLeftKinds[i];
  if k = cFiller then
  begin
    Special := True;
    Markup.Background := FLook.FillerLine;
  end
  else if (TTbDiffKind(k) = tdkChanged) or (onRight and (TTbDiffKind(k) = tdkAdded)) then
  begin
    Special := True;
    if onRight then
      Markup.Background := FLook.AddedLine
    else
      Markup.Background := FLook.RemovedLine;
  end
  else if (not onRight) and (TTbDiffKind(k) = tdkRemoved) then
  begin
    Special := True;
    Markup.Background := FLook.RemovedLine;
  end;
end;

procedure TTbCompareForm.EditStatusChange(Sender: TObject; Changes: TSynStatusChanges);
var
  other: TSynEdit;
begin
  if FSyncing or not (scTopLine in Changes) then Exit;
  if Sender = LeftEdit then other := RightEdit else other := LeftEdit;
  FSyncing := True;
  try
    other.TopLine := (Sender as TSynEdit).TopLine;
  finally
    FSyncing := False;
  end;
end;

procedure TTbCompareForm.TrialCheckChange(Sender: TObject);
var
  err: string;
begin
  if FUpdating then Exit;
  err := '';
  if Assigned(FOnTrial) then
    FOnTrial(Self, TrialCheck.Checked, err);
  FTrialOn := TrialCheck.Checked and (err = '');
  if err <> '' then
  begin
    { refused: the box goes back, without asking again }
    FUpdating := True;
    try
      TrialCheck.Checked := False;
    finally
      FUpdating := False;
    end;
    FTrialOn := False;
    Summary.Caption := FSummaryBase + ' ' + Format(rsTbCompareTrialFailed, [err]);
  end
  else
    Summary.Caption := FSummaryBase;
end;

procedure TTbCompareForm.BtnAcceptClick(Sender: TObject);
begin
  FAccepted := True;    { the .lfm's ModalResult closes the window }
end;

end.
