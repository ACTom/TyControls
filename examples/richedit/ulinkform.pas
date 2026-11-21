unit ulinkform;

{ The link form: the address of a link and the text it shows, or a place in this document
  picked from its bookmarks ("#name"). The rich edit's TTyRichEditInsertLink asks it through
  its OnGetLink (a new link, or the one at the caret to change); the form only asks, the action
  makes the link. Built from the package's controls (no native dialog). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, LCLType, tyControls.Controller, tyControls.Form,
  tyControls.FormSurface, tyControls.TyLabel, tyControls.Edit, tyControls.CheckBox, tyControls.ListBox,
  tyControls.Button, tyControls.RichEdit;

type
  TLinkForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    LblAddress: TTyLabel;
    EdtAddress: TTyEdit;
    LblText: TTyLabel;
    EdtText: TTyEdit;
    LblPlaces: TTyLabel;
    LstPlaces: TTyListBox;
    ChkHidden: TTyCheckBox;
    BtnOk: TTyButton;
    BtnCancel: TTyButton;
    procedure ChkHiddenChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure LstPlacesSelectionChange(Sender: TObject; AUser: Boolean);
  private
    FRich: TTyCustomRichEdit;
    procedure FillPlaces;
  public
    { Fills the form: the address and the text, ARich's bookmarks (hidden ones shown when the
      address is one of them, selected). }
    procedure Prepare(ARich: TTyCustomRichEdit; const AURL, AText: string);
  end;

{ Asks for a link's address and text in ARich (AURL / AText in: the link's own, or '' and the
  selected text); False: cancelled. }
function AskLink(ARich: TTyCustomRichEdit; var AURL, AText: string): Boolean;

implementation

{$R *.lfm}

function AskLink(ARich: TTyCustomRichEdit; var AURL, AText: string): Boolean;
var
  f: TLinkForm;
begin
  f := TLinkForm.Create(Application);
  try
    f.Prepare(ARich, AURL, AText);
    Result := f.ShowModal = mrOk;
    if Result then
    begin
      AURL := Trim(f.EdtAddress.Text);
      AText := f.EdtText.Text;
    end;
  finally
    f.Free;
  end;
end;

procedure TLinkForm.Prepare(ARich: TTyCustomRichEdit; const AURL, AText: string);
begin
  FRich := ARich;
  EdtAddress.Text := AURL;
  EdtText.Text := AText;
  // a place of the document in the address: its bookmark is in the list (and hidden ones
  // shown when it is one of them)
  ChkHidden.Checked := (Length(AURL) > 1) and (AURL[1] = '#') and (AURL[2] = '_');
  FillPlaces;
end;

procedure TLinkForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
end;

{ The document's bookmarks, Word's hidden ones (a table of contents' headings) with the box. }
procedure TLinkForm.FillPlaces;
var
  i: Integer;
  url: string;
begin
  url := Trim(EdtAddress.Text);
  LstPlaces.Items.BeginUpdate;
  try
    LstPlaces.Items.Clear;
    if FRich <> nil then
      for i := 0 to FRich.BookmarkCount(ChkHidden.Checked) - 1 do
        LstPlaces.Items.Add(FRich.BookmarkName(i, ChkHidden.Checked));
  finally
    LstPlaces.Items.EndUpdate;
  end;
  if (url <> '') and (url[1] = '#') then
    LstPlaces.ItemIndex := LstPlaces.Items.IndexOf(Copy(url, 2, MaxInt));
end;

procedure TLinkForm.ChkHiddenChange(Sender: TObject);
begin
  FillPlaces;
end;

{ A place picked: the address is that bookmark ("#name"). }
procedure TLinkForm.LstPlacesSelectionChange(Sender: TObject; AUser: Boolean);
begin
  if AUser and (LstPlaces.ItemIndex >= 0) then
    EdtAddress.Text := '#' + LstPlaces.Items[LstPlaces.ItemIndex];
end;

end.
