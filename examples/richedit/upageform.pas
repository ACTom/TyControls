unit upageform;

{ The page built from code (upagesample) shown the two ways a page is shown:
  - Help page: a rich edit that is ReadOnly with no caret (CaretWhenReadOnly False) - the text can
    be selected and copied, a plain click follows a link, it scrolls by itself;
  - Home page: a rich edit inside a scroll box that cannot be selected (AllowSelection False),
    never takes the focus (FocusOnClick False, TabStop False), has no bars of its own
    (ScrollBars ssNone) and is as tall as its content (AutoHeight, Align alTop: the box gives
    its width, the content its height): the scroll box scrolls the whole page as one. A "#name" link there scrolls the box (OnFollowLink): the
    rich edit itself has nothing to scroll.
  Every setting is in upageform.lfm; Append a line and Rebuild the page show the content
  changing at run time (AppendContent, SetContent). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Types, LCLIntf, Forms, Controls, tyControls.Controller,
  tyControls.Form, tyControls.FormSurface, tyControls.Button, tyControls.Panel,
  tyControls.PageControl, tyControls.TabSheet, tyControls.ScrollBox, tyControls.IconFont,
  tyControls.Icons.Lucide, tyControls.RichEdit.Text, tyControls.RichEdit.Builder,
  tyControls.RichEdit, upagesample;

type
  TPageForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    Buttons: TTyPanel;
    BtnAppend: TTyButton;
    BtnRebuild: TTyButton;
    Pages: TTyPageControl;
    TabHelp: TTyTabSheet;
    HelpRich: TTyRichEdit;
    TabHome: TTyTabSheet;
    HomeBox: TTyScrollBox;
    HomeRich: TTyRichEdit;
    PageIcons: TTyLucideIconFont;
    procedure BtnAppendClick(Sender: TObject);
    procedure BtnRebuildClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure HomeFollowLink(Sender: TObject; const AName: string; var AAllow: Boolean);
    procedure RichLinkClick(Sender: TObject; const AURL: string; AButton: TMouseButton);
  public
    { Both pages made from the start (SetContent). }
    procedure Rebuild;
    { The skin or its mode changed: the page again, its picture in the new accent (text and
      links follow by themselves; a picture is pixels). What was appended is gone with it. }
    procedure ThemeChanged;
  end;

{ The page form, made the first time and shown (not modal: the skin can be switched with it
  open). }
procedure ShowPageForm;

implementation

{$R *.lfm}

var
  PageForm: TPageForm;

procedure ShowPageForm;
begin
  if PageForm = nil then PageForm := TPageForm.Create(Application);
  PageForm.Show;
end;

procedure TPageForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
  Rebuild;
end;

{ The page into a rich edit: a builder with the rich edit's defaults, the page, SetContent. }
procedure Fill(ARich: TTyRichEdit; AIcons: TTyCustomIconFont);
var
  B: TTyRichBuilder;
begin
  B := ARich.NewBuilder;
  try
    BuildPage(B, AIcons);
    ARich.SetContent(B);
  finally
    B.Free;
  end;
end;

procedure TPageForm.Rebuild;
begin
  Fill(HelpRich, PageIcons);
  Fill(HomeRich, PageIcons);
end;

procedure TPageForm.ThemeChanged;
begin
  Rebuild;
end;

procedure TPageForm.BtnRebuildClick(Sender: TObject);
begin
  Rebuild;
end;

{ One line at the end of both pages: AppendContent, one undo step, one paint. }
procedure TPageForm.BtnAppendClick(Sender: TObject);
var
  B: TTyRichBuilder;
begin
  B := HelpRich.NewBuilder;
  try
    BuildStamp(B);
    HelpRich.AppendContent(B);
    HomeRich.AppendContent(B);
  finally
    B.Free;
  end;
end;

{ A web or mail address opens in the system's handler; "#name" the rich edit follows itself. }
procedure TPageForm.RichLinkClick(Sender: TObject; const AURL: string; AButton: TMouseButton);
begin
  if AButton <> mbLeft then Exit;
  if StartsText('http://', AURL) or StartsText('https://', AURL) or StartsText('mailto:', AURL) then
    OpenURL(AURL);
end;

{ The home page is as tall as its content: the scroll box around it is what scrolls, so the
  bookmark's heading is brought to the box's top here. }
procedure TPageForm.HomeFollowLink(Sender: TObject; const AName: string; var AAllow: Boolean);
var
  s, e: TTyRichPos;
  r: TRect;
begin
  AAllow := False;
  if not HomeRich.FindBookmark(AName, s, e) then Exit;
  r := HomeRich.PositionRect(s);
  // (the rich edit's Top is where the box's scroll put it: ScrollY above the content's start)
  HomeBox.ScrollTo(0, HomeBox.ScrollY + HomeRich.Top + r.Top);
end;

end.
