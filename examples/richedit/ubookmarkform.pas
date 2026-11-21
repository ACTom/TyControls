unit ubookmarkform;

{ The bookmark form: the document's bookmarks (Word's hidden ones, a table of contents'
  headings, with the box), a name, and Add / Delete / Rename / Go To - each the rich edit's
  own call (AddBookmark marks the selection or the caret's place; one undo step each). What
  the rich edit refuses (a name Word does not take, a place in a link's text, a read-only
  document) is told here in the rich edit's own words: its OnEditRefused is lent to the form
  while the form is open. Built from the package's controls (no native dialog). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, LCLType, tyControls.Controller, tyControls.Form,
  tyControls.FormSurface, tyControls.TyLabel, tyControls.Edit, tyControls.CheckBox,
  tyControls.ListBox, tyControls.Button, tyControls.RichEdit;

type
  TBookmarkForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    LblName: TTyLabel;
    EdtName: TTyEdit;
    LstBookmarks: TTyListBox;
    ChkHidden: TTyCheckBox;
    BtnAdd: TTyButton;
    BtnDelete: TTyButton;
    BtnRename: TTyButton;
    BtnGoTo: TTyButton;
    BtnClose: TTyButton;
    LblStatus: TTyLabel;
    procedure BtnAddClick(Sender: TObject);
    procedure BtnDeleteClick(Sender: TObject);
    procedure BtnGoToClick(Sender: TObject);
    procedure BtnRenameClick(Sender: TObject);
    procedure ChkHiddenChange(Sender: TObject);
    procedure EdtNameChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure LstBookmarksDblClick(Sender: TObject);
    procedure LstBookmarksSelectionChange(Sender: TObject; AUser: Boolean);
  private
    FRich: TTyCustomRichEdit;
    FRefused: string;
    procedure RichRefused(Sender: TObject; const AReason: string);
    procedure Fill(const ASelect: string);
    function Chosen: string;
    procedure Tell(const AText: string);
    procedure ShowButtons;
  public
    { Fills the form from ARich (its list, the buttons the document allows). }
    procedure Prepare(ARich: TTyCustomRichEdit);
  end;

{ The bookmark form for ARich, shown modal (its OnEditRefused lent to the form meanwhile). }
procedure ManageBookmarks(ARich: TTyRichEdit);

implementation

{$R *.lfm}

resourcestring
  rsBookmarkAdded   = 'Added: %s';
  rsBookmarkDeleted = 'Deleted: %s';
  rsBookmarkRenamed = 'Renamed to %s';
  rsBookmarkNotHere = 'No bookmark called %s.';

procedure ManageBookmarks(ARich: TTyRichEdit);
var
  f: TBookmarkForm;
  saved: TTyRichEditRefusedEvent;
begin
  f := TBookmarkForm.Create(Application);
  saved := ARich.OnEditRefused;
  try
    // the rich edit's reasons come to the form while it is open
    ARich.OnEditRefused := @f.RichRefused;
    f.Prepare(ARich);
    f.ShowModal;
  finally
    ARich.OnEditRefused := saved;
    f.Free;
  end;
end;

procedure TBookmarkForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
end;

procedure TBookmarkForm.Prepare(ARich: TTyCustomRichEdit);
begin
  FRich := ARich;
  ChkHidden.Checked := False;
  Fill('');
  Tell('');
end;

procedure TBookmarkForm.RichRefused(Sender: TObject; const AReason: string);
begin
  FRefused := AReason;
end;

procedure TBookmarkForm.Tell(const AText: string);
begin
  LblStatus.Caption := AText;
end;

{ The list, in the order of the bookmarks' places, ASelect selected. }
procedure TBookmarkForm.Fill(const ASelect: string);
var
  i: Integer;
begin
  LstBookmarks.Items.BeginUpdate;
  try
    LstBookmarks.Items.Clear;
    if FRich <> nil then
      for i := 0 to FRich.BookmarkCount(ChkHidden.Checked) - 1 do
        LstBookmarks.Items.Add(FRich.BookmarkName(i, ChkHidden.Checked));
  finally
    LstBookmarks.Items.EndUpdate;
  end;
  if ASelect <> '' then
  begin
    LstBookmarks.ItemIndex := LstBookmarks.Items.IndexOf(ASelect);
    EdtName.Text := ASelect;
  end
  else if LstBookmarks.Items.Count > 0 then
  begin
    LstBookmarks.ItemIndex := 0;
    EdtName.Text := LstBookmarks.Items[0];
  end;
  ShowButtons;
end;

function TBookmarkForm.Chosen: string;
begin
  if LstBookmarks.ItemIndex >= 0 then Result := LstBookmarks.Items[LstBookmarks.ItemIndex]
  else Result := '';
end;

{ Add and Rename need a name; Delete, Rename and Go To a bookmark in the list; the ones that
  change the document need a document that may be changed (the rich edit's own answer). }
procedure TBookmarkForm.ShowButtons;
var
  may, named, picked: Boolean;
begin
  may := (FRich <> nil) and FRich.CanEditBookmarks;
  named := Trim(EdtName.Text) <> '';
  picked := Chosen <> '';
  BtnAdd.Enabled := may and named;
  BtnDelete.Enabled := may and picked;
  BtnRename.Enabled := may and picked and named and (Trim(EdtName.Text) <> Chosen);
  BtnGoTo.Enabled := picked;
end;

procedure TBookmarkForm.ChkHiddenChange(Sender: TObject);
begin
  Fill(Chosen);
end;

procedure TBookmarkForm.EdtNameChange(Sender: TObject);
begin
  ShowButtons;
end;

procedure TBookmarkForm.LstBookmarksSelectionChange(Sender: TObject; AUser: Boolean);
begin
  if AUser and (Chosen <> '') then EdtName.Text := Chosen;
  ShowButtons;
end;

procedure TBookmarkForm.LstBookmarksDblClick(Sender: TObject);
begin
  BtnGoToClick(Sender);
end;

{ Add: the selection (or the caret's place) under the name; one of that name moves there. }
procedure TBookmarkForm.BtnAddClick(Sender: TObject);
var
  n: string;
begin
  n := Trim(EdtName.Text);
  FRefused := '';
  if FRich.AddBookmark(n) then
  begin
    // a name that begins with "_" is hidden: the list shows it while it is told
    if (n <> '') and (n[1] = '_') then ChkHidden.Checked := True;
    Fill(n);
    Tell(Format(rsBookmarkAdded, [n]));
  end
  else
    Tell(FRefused);
end;

procedure TBookmarkForm.BtnDeleteClick(Sender: TObject);
var
  n: string;
begin
  n := Chosen;
  FRefused := '';
  if FRich.DeleteBookmark(n) then
  begin
    Fill('');
    Tell(Format(rsBookmarkDeleted, [n]));
  end
  else
    Tell(FRefused);
end;

procedure TBookmarkForm.BtnRenameClick(Sender: TObject);
var
  n: string;
begin
  n := Trim(EdtName.Text);
  FRefused := '';
  if FRich.RenameBookmark(Chosen, n) then
  begin
    Fill(n);
    Tell(Format(rsBookmarkRenamed, [n]));
  end
  else
    Tell(FRefused);
end;

{ Go To: the caret to the bookmark, shown - a move, not an edit (a read-only document too). }
procedure TBookmarkForm.BtnGoToClick(Sender: TObject);
var
  n: string;
begin
  n := Chosen;
  if n = '' then Exit;
  if FRich.GoToBookmark(n) then Tell('')
  else Tell(Format(rsBookmarkNotHere, [n]));
end;

end.
