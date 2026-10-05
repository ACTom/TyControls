unit tbsnippetsform;
{ "File > Use it in a program...": the snippets of tbsnippets on three pages -- from a file,
  from a theme bundle (a folder and a zip), registered by name -- each in a read-only memo
  with a Copy button. The memos use the editor's monospace font (the tool theme's terminal
  font, tbeditorlook).

  A theme that refers to other files by a relative path (@import, url()) cannot be handed to
  the library as text: a registered text and a zip have no folder those paths could be found
  in (the library's registry takes no base folder, its zip reader reads no @import or
  picture). For such a theme those two snippets are greyed, their Copy buttons too, and the
  line above each says why, naming the first such file (the hint lists them all). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.FormSurface, tyControls.TyLabel,
  tyControls.Memo, tyControls.Button, tyControls.PageControl, tyControls.TabSheet;

resourcestring
  rsTbSnippetZipNeedsFiles = 'Not for this theme: a zip cannot carry %s. Export a folder bundle.';
  rsTbSnippetRegisterNeedsFiles = 'Not for this theme: a theme registered as text finds no %s. Load it from a file or a folder bundle.';

type
  TTbSnippetsForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    Pages: TTyPageControl;
    TabFile: TTyTabSheet;
    LblFile: TTyLabel;
    MemoFile: TTyMemo;
    BtnCopyFile: TTyButton;
    TabBundle: TTyTabSheet;
    LblFolder: TTyLabel;
    MemoFolder: TTyMemo;
    BtnCopyFolder: TTyButton;
    LblZip: TTyLabel;
    MemoZip: TTyMemo;
    BtnCopyZip: TTyButton;
    TabRegister: TTyTabSheet;
    LblRegister: TTyLabel;
    MemoRegister: TTyMemo;
    BtnCopyRegister: TTyButton;
    BtnClose: TTyButton;
    procedure FormCreate(Sender: TObject);
    procedure BtnCopyClick(Sender: TObject);
  public
    procedure Prepare(const AName, AFileName, ACss: string);
  end;

implementation

{$R *.lfm}

uses
  Clipbrd, tbsnippets, tbeditorlook, tbexport;

procedure TTbSnippetsForm.FormCreate(Sender: TObject);
var
  mono: string;
begin
  ApplyChromeTheme(TyDefaultController);
  mono := TbEditorColors(TyDefaultController).FontName;
  MemoFile.Font.Name := mono;
  MemoFolder.Font.Name := mono;
  MemoZip.Font.Name := mono;
  MemoRegister.Font.Name := mono;
  BtnCopyFile.Tag := 0;
  BtnCopyFolder.Tag := 1;
  BtnCopyZip.Tag := 2;
  BtnCopyRegister.Tag := 3;
end;

procedure TTbSnippetsForm.Prepare(const AName, AFileName, ACss: string);
var
  refs: TStringArray;
  usable: Boolean;
  all: string;
  i: Integer;
begin
  MemoFile.Lines.Text := TbSnippet(tsnFile, AName, AFileName, ACss);
  MemoFolder.Lines.Text := TbSnippet(tsnFolder, AName, AFileName, ACss);
  MemoZip.Lines.Text := TbSnippet(tsnZip, AName, AFileName, ACss);
  MemoRegister.Lines.Text := TbSnippet(tsnRegister, AName, AFileName, ACss);
  refs := TbRelativeReferences(ACss);
  usable := Length(refs) = 0;
  MemoZip.Enabled := usable;
  BtnCopyZip.Enabled := usable;
  MemoRegister.Enabled := usable;
  BtnCopyRegister.Enabled := usable;
  if usable then Exit;
  all := '';
  for i := 0 to High(refs) do
  begin
    if all <> '' then all := all + LineEnding;
    all := all + refs[i];
  end;
  LblZip.Caption := Format(rsTbSnippetZipNeedsFiles, [refs[0]]);
  LblZip.Hint := all;
  LblZip.ShowHint := True;
  LblRegister.Caption := Format(rsTbSnippetRegisterNeedsFiles, [refs[0]]);
  LblRegister.Hint := all;
  LblRegister.ShowHint := True;
end;

procedure TTbSnippetsForm.BtnCopyClick(Sender: TObject);
var
  memo: TTyMemo;
begin
  case (Sender as TComponent).Tag of
    1: memo := MemoFolder;
    2: memo := MemoZip;
    3: memo := MemoRegister;
  else
    memo := MemoFile;
  end;
  Clipboard.AsText := memo.Lines.Text;
end;

end.
