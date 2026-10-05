unit tbfindbar;
{ The find bar over the editor ("Edit > Find..." Ctrl+F, "Replace..." Ctrl+H): a strip of Ty
  controls, not the platform's find dialog -- the find box, previous / next, match case, whole
  word, a line that says when nothing was found, and in replace mode a second row with the
  replacement and Replace / Replace all. Esc closes it, Enter finds the next one (Shift+Enter
  the previous); F3 / Shift+F3 are the Edit menu's.

  It searches with SynEdit's own SearchReplace: from the selection on (the next one starts
  where the last one found ends), round to the other end of the text when there is no more.
  Replace changes the selection when it is a match and goes on to the next; Replace all is one
  SearchReplace over the whole text, which SynEdit runs inside one undo block -- one Ctrl+Z
  takes it all back. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, SynEdit, SynEditTypes,
  tyControls.Panel, tyControls.Edit, tyControls.TyLabel, tyControls.CheckBox,
  tyControls.Button, tyControls.GlyphButtons, tyControls.Icons.Lucide;

resourcestring
  rsTbFindNotFound = 'Not found';
  rsTbFindReplaced = 'Replaced %d.';

type
  TTbFindBar = class(TFrame)
    FindRow: TTyPanel;
    EdtFind: TTyEdit;
    BtnPrev: TTySpeedButton;
    BtnNext: TTySpeedButton;
    ChkCase: TTyCheckBox;
    ChkWord: TTyCheckBox;
    BtnClose: TTySpeedButton;
    LblInfo: TTyLabel;
    ReplaceRow: TTyPanel;
    EdtReplace: TTyEdit;
    BtnReplace: TTyButton;
    BtnReplaceAll: TTyButton;
    FindIconFont: TTyLucideIconFont;
    procedure EdtFindChange(Sender: TObject);
    procedure OptionChange(Sender: TObject);
    procedure BtnPrevClick(Sender: TObject);
    procedure BtnNextClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure BtnReplaceClick(Sender: TObject);
    procedure BtnReplaceAllClick(Sender: TObject);
  private
    FEdit: TSynEdit;
    FOnClosed: TNotifyEvent;
    procedure FieldKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function Options: TSynSearchOptions;
    procedure SetInfo(const AText: string);
    procedure FitHeight;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    { the editor it searches }
    procedure Attach(AEdit: TSynEdit);
    { shown, the replace row with it when AReplace; the find box takes a one-line selection
      of the editor's and gets the focus (when it can) }
    procedure Open(AReplace: Boolean);
    procedure Close;
    { the next / previous match, round the end; False (and "Not found") when there is none }
    function FindNext: Boolean;
    function FindPrevious: Boolean;
    { the selection replaced when it is a match, then the next one found }
    function ReplaceNext: Boolean;
    { every match replaced, as one undo step; how many }
    function ReplaceAll: Integer;
    { the selection is a match of the find text (with the options) }
    function SelectionMatches: Boolean;
    function SearchText: string;
    { FOR THE TESTS: the keys the two boxes hear (Esc, Enter, Shift+Enter) }
    procedure KeyForTest(AKey: Word; AShift: TShiftState);
    property Edit: TSynEdit read FEdit;
    property OnClosed: TNotifyEvent read FOnClosed write FOnClosed;
  end;

implementation

{$R *.lfm}

uses
  LCLType, LazUTF8;

type
  { OnKeyDown is protected on TWinControl; TTyEdit fires it first thing in its KeyDown }
  TEditAccess = class(TTyEdit);

constructor TTbFindBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TEditAccess(EdtFind).OnKeyDown := @FieldKeyDown;
  TEditAccess(EdtReplace).OnKeyDown := @FieldKeyDown;
  FitHeight;
end;

procedure TTbFindBar.Attach(AEdit: TSynEdit);
begin
  if FEdit <> nil then
    FEdit.RemoveFreeNotification(Self);
  FEdit := AEdit;
  if FEdit <> nil then
    FEdit.FreeNotification(Self);
end;

procedure TTbFindBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FEdit) then
    FEdit := nil;
end;

procedure TTbFindBar.FitHeight;
begin
  if ReplaceRow.Visible then
    Height := FindRow.Height + ReplaceRow.Height
  else
    Height := FindRow.Height;
end;

function TTbFindBar.SearchText: string;
begin
  Result := EdtFind.Text;
end;

function TTbFindBar.Options: TSynSearchOptions;
begin
  Result := [];
  if ChkCase.Checked then
    Include(Result, ssoMatchCase);
  if ChkWord.Checked then
    Include(Result, ssoWholeWord);
end;

procedure TTbFindBar.SetInfo(const AText: string);
begin
  LblInfo.Caption := AText;
end;

procedure TTbFindBar.Open(AReplace: Boolean);
var
  sel: string;
begin
  if (FEdit <> nil) and FEdit.SelAvail then
  begin
    sel := FEdit.SelText;
    if (sel <> '') and (Pos(#10, sel) = 0) and (Pos(#13, sel) = 0) then
      EdtFind.Text := sel;
  end;
  ReplaceRow.Visible := AReplace;
  FitHeight;
  SetInfo('');
  Visible := True;
  EdtFind.SelectAll;
  if EdtFind.CanSetFocus then
    EdtFind.SetFocus;
end;

procedure TTbFindBar.Close;
begin
  Visible := False;
  SetInfo('');
  if Assigned(FOnClosed) then
    FOnClosed(Self);
end;

function TTbFindBar.FindNext: Boolean;
var
  opts: TSynSearchOptions;
begin
  Result := False;
  SetInfo('');
  if (FEdit = nil) or (SearchText = '') then Exit;
  opts := Options;
  Result := FEdit.SearchReplace(SearchText, '', opts + [ssoFindContinue]) > 0;
  if not Result then
    { round the end: from the start of the text }
    Result := FEdit.SearchReplace(SearchText, '', opts + [ssoEntireScope]) > 0;
  if not Result then
    SetInfo(rsTbFindNotFound);
end;

function TTbFindBar.FindPrevious: Boolean;
var
  opts: TSynSearchOptions;
begin
  Result := False;
  SetInfo('');
  if (FEdit = nil) or (SearchText = '') then Exit;
  opts := Options + [ssoBackwards];
  Result := FEdit.SearchReplace(SearchText, '', opts + [ssoFindContinue]) > 0;
  if not Result then
    { round the start: from the end of the text }
    Result := FEdit.SearchReplace(SearchText, '', opts + [ssoEntireScope]) > 0;
  if not Result then
    SetInfo(rsTbFindNotFound);
end;

function TTbFindBar.SelectionMatches: Boolean;
var
  sel: string;
begin
  Result := False;
  if (FEdit = nil) or not FEdit.SelAvail or (SearchText = '') then Exit;
  sel := FEdit.SelText;
  if ChkCase.Checked then
    Result := sel = SearchText
  else
    Result := UTF8LowerCase(sel) = UTF8LowerCase(SearchText);
end;

function TTbFindBar.ReplaceNext: Boolean;
begin
  Result := False;
  if (FEdit = nil) or FEdit.ReadOnly or (SearchText = '') then Exit;
  if SelectionMatches then
  begin
    { from the selection's start: SynEdit replaces the match it finds there -- this one }
    FEdit.SearchReplaceEx(SearchText, EdtReplace.Text, Options + [ssoReplace], FEdit.BlockBegin);
    Result := True;
  end;
  FindNext;
end;

function TTbFindBar.ReplaceAll: Integer;
begin
  Result := 0;
  SetInfo('');
  if (FEdit = nil) or FEdit.ReadOnly or (SearchText = '') then Exit;
  Result := FEdit.SearchReplace(SearchText, EdtReplace.Text,
    Options + [ssoReplaceAll, ssoEntireScope]);
  if Result = 0 then
    SetInfo(rsTbFindNotFound)
  else
    SetInfo(Format(rsTbFindReplaced, [Result]));
end;

procedure TTbFindBar.FieldKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      begin
        Key := 0;
        Close;
      end;
    VK_RETURN:
      begin
        Key := 0;
        if Sender = EdtReplace then
          ReplaceNext
        else if ssShift in Shift then
          FindPrevious
        else
          FindNext;
      end;
  end;
end;

procedure TTbFindBar.KeyForTest(AKey: Word; AShift: TShiftState);
begin
  FieldKeyDown(EdtFind, AKey, AShift);
end;

procedure TTbFindBar.EdtFindChange(Sender: TObject);
begin
  SetInfo('');
end;

procedure TTbFindBar.OptionChange(Sender: TObject);
begin
  SetInfo('');
end;

procedure TTbFindBar.BtnPrevClick(Sender: TObject);
begin
  FindPrevious;
end;

procedure TTbFindBar.BtnNextClick(Sender: TObject);
begin
  FindNext;
end;

procedure TTbFindBar.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TTbFindBar.BtnReplaceClick(Sender: TObject);
begin
  ReplaceNext;
end;

procedure TTbFindBar.BtnReplaceAllClick(Sender: TObject);
begin
  ReplaceAll;
end;

end.
