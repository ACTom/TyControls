unit umain;

{ TTyMenuBar + TTyMenuEx + window roll-up demo (TTyForm custom-drawn frame + title bar):
    - TTyMenuBar: top menu bar, bound to a standard LCL TMainMenu (File / Edit / View)
        · Align=alTop docks it below the title bar; Alt+mnemonic (&File -> Alt+F) opens the dropdown
    - TTyMenuEx: enhanced context menu (descends from TTyPopupMenu), attached to the panel's PopupMenu, popped up on right-click
        · Section header: Caption='-Clipboard' -> rendered as a non-clickable "Clipboard" section header (a bare '-' is still a separator)
        · Icon column: an item's ImageIndex draws an icon in the left slot from Images (TTyVirtualImageList, here backed by a TTyImageCollection
          that draws three rounded squares on the fly); checked items show a check mark (the check mark takes priority over the icon)
    - Window roll-up: CaptionAction=tcaRollUp -> double-clicking the title bar collapses the window down to just the title bar, double-click again restores
  All colors/borders/corners/highlights come from theme rules. The window, both menus, the menu bar, the target
  panel and the live theme switcher are designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event
  handlers + theme setup + the procedural icon bitmaps that can't live in the .lfm. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Menus, BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ImageCollection, tyControls.Menu, tyControls.Panel, tyControls.TyLabel,
  tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    TyMenuBar1: TTyMenuBar;
    HintPanel: TTyPanel;
    StatusLabel: TTyLabel;
    MainMenu1: TMainMenu;
    MnuFile: TMenuItem;
    MnuFileNew: TMenuItem;
    MnuFileOpen: TMenuItem;
    MnuFileSave: TMenuItem;
    MnuFileSep1: TMenuItem;
    MnuFileExit: TMenuItem;
    MnuEdit: TMenuItem;
    MnuEditUndo: TMenuItem;
    MnuEditRedo: TMenuItem;
    MnuEditSep1: TMenuItem;
    MnuEditCut: TMenuItem;
    MnuEditCopy: TMenuItem;
    MnuEditPaste: TMenuItem;
    MnuView: TMenuItem;
    MnuViewZoomIn: TMenuItem;
    MnuViewZoomOut: TMenuItem;
    MnuViewSep1: TMenuItem;
    MnuViewFull: TMenuItem;
    Popup: TTyMenuEx;              // enhanced context menu: section headers + icon column
    PopHdrClip: TMenuItem;
    PopCut: TMenuItem;
    PopCopy: TMenuItem;
    PopPaste: TMenuItem;
    PopSep1: TMenuItem;
    PopHdrView: TMenuItem;
    PopGrid: TMenuItem;
    PopRefresh: TMenuItem;
    PopSep2: TMenuItem;
    PopProps: TMenuItem;
    IconColl: TTyImageCollection;    // icon bitmap source
    MenuImages: TTyVirtualImageList; // Images for the menu's icon column
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    { Generic menu-item click: echo the item's Caption to the status label }
    procedure MenuItemClicked(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ Draw a 16px rounded-square icon (in the given color) and add it to the collection; AddBitmap stores a copy, the caller keeps ownership }
procedure AddIcon(AColl: TTyImageCollection; const AName: string; AColor: TBGRAPixel);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(16, 16, BGRAPixelTransparent);
  try
    bmp.FillRoundRectAntialias(1.5, 1.5, 14.5, 14.5, 4, 4, AColor);
    AColl.AddBitmap(AName, bmp);
  finally
    bmp.Free;
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // The enhanced context menu's icon column: draw the three rounded-square icons into the
  // (designed) IconColl at runtime -- procedural bitmaps can't be expressed in the .lfm.
  // MenuImages.Collection + Names are wired in the .lfm; here we only fill the bitmaps.
  AddIcon(IconColl, 'cut',   BGRA(220, 70, 70));    // red
  AddIcon(IconColl, 'copy',  BGRA(80, 170, 90));    // green
  AddIcon(IconColl, 'paste', BGRA(70, 120, 220));   // blue
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.MenuItemClicked(Sender: TObject);
var
  Item: TMenuItem;
begin
  if not (Sender is TMenuItem) then Exit;
  Item := TMenuItem(Sender);
  // echo with the mnemonic '&' stripped (StripHotkey is provided by the Menus unit)
  StatusLabel.Caption := Format('已选择菜单命令：%s', [StripHotkey(Item.Caption)]);
end;

end.
