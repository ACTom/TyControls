unit tbsnippetsform;
{ "File > Use it in a program...": the snippets of tbsnippets on three pages -- from a file,
  from a theme bundle (a folder and a zip), registered by name -- each in a read-only memo
  with a Copy button. The memos use the editor's monospace font (the tool theme's terminal
  font, tbeditorlook). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.FormSurface, tyControls.TyLabel,
  tyControls.Memo, tyControls.Button, tyControls.PageControl, tyControls.TabSheet;

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
  Clipbrd, tbsnippets, tbeditorlook;

procedure TTbSnippetsForm.FormCreate(Sender: TObject);
var
  font: string;
begin
  ApplyChromeTheme(TyDefaultController);
  font := TbEditorColors(TyDefaultController).FontName;
  MemoFile.Font.Name := font;
  MemoFolder.Font.Name := font;
  MemoZip.Font.Name := font;
  MemoRegister.Font.Name := font;
  BtnCopyFile.Tag := 0;
  BtnCopyFolder.Tag := 1;
  BtnCopyZip.Tag := 2;
  BtnCopyRegister.Tag := 3;
end;

procedure TTbSnippetsForm.Prepare(const AName, AFileName, ACss: string);
begin
  MemoFile.Lines.Text := TbSnippet(tsnFile, AName, AFileName, ACss);
  MemoFolder.Lines.Text := TbSnippet(tsnFolder, AName, AFileName, ACss);
  MemoZip.Lines.Text := TbSnippet(tsnZip, AName, AFileName, ACss);
  MemoRegister.Lines.Text := TbSnippet(tsnRegister, AName, AFileName, ACss);
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
