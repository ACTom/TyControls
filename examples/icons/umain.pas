unit umain;

{ Icons & images demo:
  · TTyImage —— one (code-generated) bitmap shown in Stretch / Proportional / Center modes (works out of the box).
  · TTyIconFont + TTyCharImage —— icon-font structure demo; to actually see a glyph point FontFile at an
    icon .ttf (e.g. FontAwesome) —— see the note label below.
  Main window is a TTyForm + TTyTitleBar, built purely in code (no .lfm). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics,
  tyControls.Types, tyControls.Controller, tyControls.Form,
  tyControls.TyLabel, tyControls.Image, tyControls.IconFont, tyControls.CharImage;

type
  TMainForm = class(TTyForm)
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

function ThemesDir: string;
var Dir: string; i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

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

procedure AddImage(AOwner: TWinControl; AX: Integer; const ACaption: string;
  ABmp: TBitmap; AStretch, AProportional, ACenter: Boolean);
var
  cap: TTyLabel;
  img: TTyImage;
begin
  cap := TTyLabel.Create(AOwner);
  cap.Parent := AOwner;
  cap.SetBounds(AX, 52, 120, 20);
  cap.Caption := ACaption;

  img := TTyImage.Create(AOwner);
  img.Parent := AOwner;
  img.SetBounds(AX, 74, 120, 100);
  img.Transparent := False;               // paint the TyPanel surface behind it
  img.Stretch := AStretch;
  img.Proportional := AProportional;
  img.Center := ACenter;
  img.Picture.Bitmap.Assign(ABmp);
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  Bmp: TBitmap;
  Icons: TTyIconFont;
  Ch: TTyCharImage;
  Note: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Icons & Images 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 460, 320);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'Icons & Images  · TyControls';

  Bmp := MakeSampleBitmap;
  try
    AddImage(Self, 16,  '拉伸 Stretch',       Bmp, True,  False, True);
    AddImage(Self, 168, '等比 Proportional',  Bmp, False, True,  True);
    AddImage(Self, 320, '居中 Center',        Bmp, False, False, True);
  finally
    Bmp.Free;
  end;

  // Icon-font structure. Point FontFile at a real icon .ttf (e.g. FontAwesome) and
  // FontFamily at its family name to see the glyph — otherwise CharImage is blank.
  Icons := TTyIconFont.Create(Self);
  Icons.MapGlyph('star', $2605);          // a BMP star; renders if the family has it
  Icons.FontFamily := 'Segoe UI Symbol';  // a commonly-present family on Windows

  Ch := TTyCharImage.Create(Self);
  Ch.Parent := Self;
  Ch.SetBounds(16, 196, 40, 40);
  Ch.IconFont := Icons;
  Ch.GlyphName := 'star';
  Ch.GlyphColor := TyRGB($3B, $82, $F6);

  Note := TTyLabel.Create(Self);
  Note.Parent := Self;
  Note.SetBounds(64, 196, 380, 60);
  Note.WordWrap := True;
  Note.Caption := 'TTyIconFont/TTyCharImage:把 FontFile 指向图标 .ttf(如 FontAwesome)、'
    + 'FontFamily 设为其族名,再用 name→codepoint 映射即可渲染矢量图标。左侧尝试用系统符号字体'
    + '渲染一个星形(★),不同平台字体族不同,显示效果可能不一。';

  ApplyChromeTheme(TyDefaultController);
end;

end.
