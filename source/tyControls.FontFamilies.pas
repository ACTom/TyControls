unit tyControls.FontFamilies;
{$mode objfpc}{$H+}
{$macro on}
{$ifdef WinCE}
  {$define extdecl := cdecl}
{$else}
  {$define extdecl := stdcall}
{$endif}

{ Which installed font families are fixed-pitch, and which are scalable -- as the SYSTEM says.

  Both answers come from LCL's EnumFontFamiliesEx and nothing else: no glyph is measured. One
  request shape works on every widgetset, because each of them answers it its own way:

    - win32 hands the request to EnumFontFamiliesExW, which ignores the pitch in it; the
      callback's lfPitchAndFamily carries the font's real pitch bits, and FontType carries
      RASTER_FONTTYPE for a bitmap font (win32winapi.inc).
    - gtk2 / gtk3 / qt filter on the requested pitch themselves (pango_font_family_is_monospace,
      QFontDatabase::isFixedPitch) and copy the requested value into the callback. Their
      default enumeration (pitch 0) reports FontType 0 -- never a bitmap font.
    - cocoa does not filter; it calls back once per member font with FIXED_PITCH when the member
      has NSFontMonoSpaceTrait, and always reports TrueType.

  So: ask for FIXED_PITCH and keep the names whose callback says FIXED_PITCH; ask with pitch 0
  and keep the names whose FontType lacks RASTER_FONTTYPE. Where the system's flag is wrong for
  some font, the system wins -- the same answer every other program on that machine shows.

  Nothing is cached: the lists are read only when a caller asks for a filtered list, at about
  the cost of the plain Screen.Fonts enumeration, and a font installed since then shows up. }

interface

uses
  Classes, SysUtils, Forms, LCLType, LCLIntf;

{ Fills ADest with the installed families, in Screen.Fonts order and spelling, keeping only
  those the system reports as fixed-pitch (AFixedPitchOnly) and/or not a bitmap font
  (AScalableOnly). With neither flag ADest is a copy of Screen.Fonts. }
procedure TyGetFontFamilies(ADest: TStrings; AFixedPitchOnly: Boolean;
  AScalableOnly: Boolean = False);

implementation

function CollectFixedPitch(var ELogFont: TEnumLogFontEx; var Metric: TNewTextMetricEx;
  FontType: Longint; Data: LParam): Longint; extdecl;
begin
  if (ELogFont.elfLogFont.lfPitchAndFamily and 3) = FIXED_PITCH then
    TStringList(PtrUInt(Data)).Add(ELogFont.elfLogFont.lfFaceName);
  Result := 1;
end;

function CollectScalable(var ELogFont: TEnumLogFontEx; var Metric: TNewTextMetricEx;
  FontType: Longint; Data: LParam): Longint; extdecl;
begin
  if (FontType and RASTER_FONTTYPE) = 0 then
    TStringList(PtrUInt(Data)).Add(ELogFont.elfLogFont.lfFaceName);
  Result := 1;
end;

{ One enumeration of every family (DEFAULT_CHARSET, no face name) with the given pitch request,
  each callback deciding whether its family goes into AInto. }
procedure Enumerate(APitch: Byte; ACallback: FontEnumExProc; AInto: TStringList);
var
  lf: TLogFont;
  dc: HDC;
begin
  lf := Default(TLogFont);
  lf.lfCharSet := DEFAULT_CHARSET;
  lf.lfFaceName := '';
  lf.lfPitchAndFamily := APitch;
  dc := GetDC(0);
  try
    EnumFontFamiliesEx(dc, @lf, ACallback, LParam(PtrUInt(AInto)), 0);
  finally
    ReleaseDC(0, dc);
  end;
end;

function NewNameSet: TStringList;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  Result.CaseSensitive := True;   // Screen.Fonts' spelling is what is matched
end;

procedure TyGetFontFamilies(ADest: TStrings; AFixedPitchOnly: Boolean;
  AScalableOnly: Boolean);
var
  fixed, scalable: TStringList;
  i: Integer;
  name: string;
begin
  if not (AFixedPitchOnly or AScalableOnly) then
  begin
    ADest.Assign(Screen.Fonts);
    Exit;
  end;
  fixed := nil;
  scalable := nil;
  try
    if AFixedPitchOnly then
    begin
      fixed := NewNameSet;
      Enumerate(FIXED_PITCH, @CollectFixedPitch, fixed);
    end;
    if AScalableOnly then
    begin
      scalable := NewNameSet;
      Enumerate(0, @CollectScalable, scalable);
    end;
    ADest.BeginUpdate;
    try
      ADest.Clear;
      for i := 0 to Screen.Fonts.Count - 1 do
      begin
        name := Screen.Fonts[i];
        if (fixed <> nil) and (fixed.IndexOf(name) < 0) then Continue;
        if (scalable <> nil) and (scalable.IndexOf(name) < 0) then Continue;
        ADest.Add(name);
      end;
    finally
      ADest.EndUpdate;
    end;
  finally
    fixed.Free;
    scalable.Free;
  end;
end;

end.
