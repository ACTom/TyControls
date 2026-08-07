unit umain;

{ Icons & images demo:
  · TTyImage —— one (code-generated) bitmap shown in Stretch / Proportional / Center / Center=False
    modes, plus the Transparent (default) vs opaque pair and an AutoSize box (works out of the box).
  · TTyIconFont + TTyCharImage —— GlyphSize 12/24/40 against the 0 = auto-fit default, and an explicit
    GlyphColor beside one left unset (which follows the theme text colour —— try the Dark switch).
  · TTyGlyphImageList —— one icon font as an ordered list, drawn twice at two sizes (vectors on demand).
  · FontFile —— load any .ttf PRIVATE to this process (no OS install) and re-render every glyph above.
  The window, every control and the live theme switcher are designed in umain.lfm (a TTyForm + TTyTitleBar);
  the code here is theme setup, the code-generated sample bitmap, the glyph colours and the handlers. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, BGRABitmap,
  tyControls.Types, tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Painter, tyControls.TyLabel, tyControls.Image, tyControls.IconFont,
  tyControls.CharImage, tyControls.GlyphImageList, tyControls.PaintPanel,
  tyControls.Button, tyControls.Edit, tyControls.Dialogs.FileDialog,
  tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    Cap1: TTyLabel;
    Img1: TTyImage;
    Cap2: TTyLabel;
    Img2: TTyImage;
    Cap3: TTyLabel;
    Img3: TTyImage;
    Cap4: TTyLabel;
    Img5: TTyImage;             // native size anchored top-left (Center = False)
    LblTrans: TTyLabel;
    Img4: TTyImage;             // Transparent = True (the default): no surface drawn
    Img7: TTyImage;             // the same picture with Transparent = False
    LblAuto: TTyLabel;
    Img6: TTyImage;             // AutoSize: shrinks to the picture's native 120x80
    Icons: TTyIconFont;
    GlyphList: TTyGlyphImageList;
    LblIcon: TTyLabel;
    Ch: TTyCharImage;
    ChThemed: TTyCharImage;     // GlyphColor left unset -> theme TextColor
    Note: TTyLabel;
    LblColor: TTyLabel;
    LblSizes: TTyLabel;
    ChS1: TTyCharImage;         // GlyphSize 12
    ChS2: TTyCharImage;         // GlyphSize 24
    ChS3: TTyCharImage;         // GlyphSize 40
    LblList: TTyLabel;
    GlyphStrip: TTyPaintPanel;  // owner-draw strip fed by GlyphList
    LblFontFile: TTyLabel;
    FontFamilyEdit: TTyEdit;
    BtnLoadFont: TTyButton;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure IconClick(Sender: TObject);
    procedure GlyphStripPaint(Sender: TObject; APainter: TTyPainter;
      const AContent: TRect);
    procedure FontFamilyEditChange(Sender: TObject);
    procedure BtnLoadFontClick(Sender: TObject);
  private
    { TTyIconFont has no change notification, so every consumer of the font is
      repainted by hand after FontFamily / FontFile changes. }
    procedure RefreshGlyphs;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsClickedFmt = 'Clicked: %s';
  rsFontFilter = 'Font files|*.ttf;*.otf|All files|*.*';

{ A small colorful source bitmap drawn in code (so the demo needs no asset file). }
function MakeSampleBitmap: TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(120, 80);
  Result.Canvas.Brush.Color := $E0A060;   // sky
  Result.Canvas.FillRect(0, 0, 120, 80);
  Result.Canvas.Brush.Color := clWhite;    // sun
  Result.Canvas.Pen.Color := clWhite;
  Result.Canvas.Ellipse(10, 8, 40, 38);
  Result.Canvas.Brush.Color := $3B8B4B;    // hill
  Result.Canvas.Pen.Color := $3B8B4B;
  Result.Canvas.Polygon([Point(0, 80), Point(55, 34), Point(120, 80)]);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  Bmp: TBitmap;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // The sample bitmap is generated in code, so feed it into every designed image.
  // Img6 is AutoSize -> assigning the picture shrinks its box to the native 120x80.
  Bmp := MakeSampleBitmap;
  try
    Img1.Picture.Bitmap.Assign(Bmp);
    Img2.Picture.Bitmap.Assign(Bmp);
    Img3.Picture.Bitmap.Assign(Bmp);
    Img4.Picture.Bitmap.Assign(Bmp);
    Img5.Picture.Bitmap.Assign(Bmp);
    Img6.Picture.Bitmap.Assign(Bmp);
    Img7.Picture.Bitmap.Assign(Bmp);
  finally
    Bmp.Free;
  end;

  // GlyphColor is an ARGB TTyColor value computed at runtime. ChThemed is deliberately
  // left at TyGlyphColorDefault so it tracks the theme's TextColor instead.
  Ch.GlyphColor := TyRGB($3B, $82, $F6);
  GlyphList.DefaultColor := TyRGB($3B, $82, $F6);
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

procedure TMainForm.RefreshGlyphs;
begin
  Ch.Invalidate;
  ChThemed.Invalidate;
  ChS1.Invalidate;
  ChS2.Invalidate;
  ChS3.Invalidate;
  GlyphStrip.Invalidate;
end;

{ OnClick is the only event TTyImage and TTyCharImage publish — both are meant to be
  usable as plain clickable icons. }
procedure TMainForm.IconClick(Sender: TObject);
begin
  LblStatus.Caption := Format(rsClickedFmt, [TComponent(Sender).Name]);
end;

{ TTyGlyphImageList renders vectors on demand rather than holding a fixed-resolution raster
  set, so the SAME list is drawn twice here at two different sizes and both stay crisp.
  Drawing goes through the live painter — never straight onto the canvas, whose GDI output
  the painter's EndPaint would overwrite. }
procedure TMainForm.GlyphStripPaint(Sender: TObject; APainter: TTyPainter;
  const AContent: TRect);

  { One left-to-right, bottom-aligned pass over the whole list. Returns the next free x. }
  function DrawRow(AX, ASizeLogical: Integer): Integer;
  var
    i, sz: Integer;
    bmp: TBGRABitmap;
  begin
    sz := APainter.Scale(ASizeLogical);
    for i := 0 to GlyphList.Count - 1 do
    begin
      // RenderIndex never returns nil, so no glyph / no font simply draws nothing.
      bmp := GlyphList.RenderIndex(i, sz, GlyphList.DefaultColor);
      try
        APainter.DrawGlyphBitmap(
          Rect(AX, AContent.Bottom - sz, AX + sz, AContent.Bottom), bmp);
      finally
        bmp.Free;
      end;
      Inc(AX, sz + APainter.Scale(10));
    end;
    Result := AX;
  end;

var
  x: Integer;
begin
  x := DrawRow(AContent.Left, GlyphList.DefaultSize);
  DrawRow(x + APainter.Scale(24), GlyphList.DefaultSize div 2);
end;

procedure TMainForm.FontFamilyEditChange(Sender: TObject);
begin
  // FontFamily is a plain string write with no notification, so repaint by hand.
  Icons.FontFamily := Trim(FontFamilyEdit.Text);
  RefreshGlyphs;
end;

procedure TMainForm.BtnLoadFontClick(Sender: TObject);
var
  FileName: string;
begin
  FileName := '';
  if not TyOpenDialog(FileName, rsFontFilter) then Exit;
  // Setting FontFile registers the file PRIVATE to this process (Windows
  // AddFontResourceEx/FR_PRIVATE, Qt addApplicationFont, Cocoa CTFontManager,
  // GTK2 fontconfig) — the font never has to be installed on the machine. The
  // family name still has to match what the file declares, hence the edit box.
  Icons.FontFile := FileName;
  Icons.FontFamily := Trim(FontFamilyEdit.Text);
  RefreshGlyphs;
  LblStatus.Caption := Format('FontFile = %s   ·   FontFamily = %s',
    [ExtractFileName(FileName), Icons.FontFamily]);
end;

end.
