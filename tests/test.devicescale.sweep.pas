unit test.devicescale.sweep;
{$mode objfpc}{$H+}

{ #83: every control on the palette, drawn at the device scale.

  The painter's own methods are pinned pixel for pixel (test.devicescale.painter). What they
  cannot see is a control that draws on the painter's layer DIRECTLY -- FillRect, PutImage, a
  clip rect -- in layout coordinates: on a layer S times larger that drawing lands at half its
  position and half its size. This sweep draws each palette control at S = 2 and compares it with
  the same control at twice the size and PPI 192 (test.devicescale.support).

  THE LIST IS A RATCHET. CKnownUnported names the classes that fail today; the assertion is that
  the failing set is EXACTLY that list -- a new failure is a regression, and a class that passes
  while still listed means a port landed and the list was not shortened. Each porting task
  removes its classes; the list ends empty.

  Every class's score is written to <temp>/tydevicescale-sweep.txt, for looking at. }

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.IconFont, tyControls.Dialogs.IconBrowser,
  test.designregistry, test.devicescale.support;

type
  TDeviceScaleSweepTest = class(TTestCase)
  private
    FClass: TControlClass;
    function BuildCurrent(AParent: TWinControl; APPI: Integer): TControl;
    function BuildIconGrid(AParent: TWinControl; APPI: Integer): TControl;
  private
    FIconFont: TTyIconFont;
  published
    procedure TestEveryPaletteControlDrawsAtTheDeviceScale;
    { The icon browser's grid renders its glyphs for the layer (Task 5): not on the palette,
      and blank with no font, so it gets its own check with a font that has ink. }
    procedure TestIconGridAtTheDeviceScale;
  end;

const
  { The score (unmatched ink + mismatched blocks, test.devicescale.support) above which a
    control counts as not drawing at the device scale. Measured when this was set (2026-10-17):
    every control that draws only through the painter's methods scored at most 6 (TTyCalendar,
    all blocks); the lowest-scoring control still drawing in layout coordinates was TTyBevel
    at 144 (two 1-px lines). 20 sits clear of both. }
  CMaxMismatch = 20;

  { Classes known not to draw at the device scale yet. Each porting task removes its own:
    the colour and font list boxes (ListBox's clip), the shell tree (TreeView), and the
    panels whose paint cache is still one-times (TTyPaintCache). }
  CKnownUnported: array of string = ('TTyColorListBox', 'TTyFontListBox', 'TTyShellTreeView',
    'TTyPanel', 'TTyRelativePanel', 'TTyCoolBar', 'TTyControlBar');

implementation

type
  TControlAccess = class(TControl);

function TDeviceScaleSweepTest.BuildCurrent(AParent: TWinControl; APPI: Integer): TControl;
begin
  Result := FClass.Create(AParent);
  Result.Parent := AParent;
  TControlAccess(Result).Font.PixelsPerInch := APPI;
end;

{ Pixels that are not the white the surface started as: whether the control drew at all. }
function InkOf(B: TBGRABitmap): Integer;
var
  x, y: Integer;
  p: PBGRAPixel;
begin
  Result := 0;
  for y := 0 to B.Height - 1 do
  begin
    p := B.ScanLine[y];
    for x := 0 to B.Width - 1 do
      if (p[x].red < 250) or (p[x].green < 250) or (p[x].blue < 250) then Inc(Result);
  end;
end;

function InList(const AName: string; const AList: array of string): Boolean;
var
  s: string;
begin
  for s in AList do
    if SameText(s, AName) then Exit(True);
  Result := False;
end;

procedure TDeviceScaleSweepTest.TestEveryPaletteControlDrawsAtTheDeviceScale;
var
  names, report, failing: TStringList;
  i, w, h, score: Integer;
  cls: TPersistentClass;
  probe: TForm;
  c: TControl;
  newFails, staleListed, errors: string;
  picA, picB, diff: TBGRABitmap;
  inkScore, blocks: Integer;
  k: Integer;
  ink: Integer;
  s: string;
begin
  names := TStringList.Create;
  report := TStringList.Create;
  failing := TStringList.Create;
  try
    CollectPaletteClassNames(names);
    names.Sort;
    newFails := '';
    errors := '';
    for i := 0 to names.Count - 1 do
    begin
      cls := GetClass(names[i]);
      if (cls = nil) or not cls.InheritsFrom(TControl) or cls.InheritsFrom(TCustomForm) then
        Continue;
      FClass := TControlClass(cls);
      { The default size, clamped and even. }
      probe := TForm.CreateNew(nil);
      try
        c := FClass.Create(probe);
        c.Parent := probe;
        w := c.Width;
        h := c.Height;
      finally
        probe.Free;
      end;
      if w > 320 then w := 320;
      if h > 240 then h := 240;
      if w < 8 then w := 8;
      if h < 8 then h := 8;
      w := w and not 1;
      h := h and not 1;
      try
        score := TyDeviceScaleMismatchPictures(@BuildCurrent, w, h, picA, picB, inkScore, blocks);
        ink := InkOf(picB);
        { TY_SWEEP_DIR set: keep both pictures of a failing class (of every class with
          TY_SWEEP_ALL), and the ink difference, to look at. }
        if ((score > CMaxMismatch) or (GetEnvironmentVariable('TY_SWEEP_ALL') <> '')) and
          (GetEnvironmentVariable('TY_SWEEP_DIR') <> '') then
        begin
          picA.SaveToFile(IncludeTrailingPathDelimiter(GetEnvironmentVariable('TY_SWEEP_DIR')) +
            names[i] + '-s2.png');
          picB.SaveToFile(IncludeTrailingPathDelimiter(GetEnvironmentVariable('TY_SWEEP_DIR')) +
            names[i] + '-ref.png');
          diff := TyInkMismatchImage(picA, picB, CFuzzyRadius);
          diff.SaveToFile(IncludeTrailingPathDelimiter(GetEnvironmentVariable('TY_SWEEP_DIR')) +
            names[i] + '-diff.png');
          diff.Free;
        end;
        FreeAndNil(picA);
        FreeAndNil(picB);
      except
        on E: Exception do
        begin
          report.Add(Format('%-28s %4dx%-4d ERROR %s: %s', [names[i], w, h, E.ClassName, E.Message]));
          report.Add('    at ' + BackTraceStrFunc(ExceptAddr));
          for k := 0 to ExceptFrameCount - 1 do
            report.Add('    ' + BackTraceStrFunc(ExceptFrames[k]));
          errors := errors + ' ' + names[i];
          Continue;
        end;
      end;
      report.Add(Format('%-28s %4dx%-4d %8d  (ink %d, blocks %d)  drawn %d', [names[i], w, h, score,
        inkScore, blocks, ink]));
      if score > CMaxMismatch then
      begin
        failing.Add(names[i]);
        if not InList(names[i], CKnownUnported) then newFails := newFails + ' ' + names[i];
      end;
    end;
    report.SaveToFile(GetTempDir(False) + 'tydevicescale-sweep.txt');
    staleListed := '';
    for s in CKnownUnported do
      if failing.IndexOf(s) < 0 then staleListed := staleListed + ' ' + s;
    AssertEquals('controls that could not be painted:' + errors, '', errors);
    AssertEquals('controls that do not draw at the device scale and are not listed:' + newFails,
      '', newFails);
    AssertEquals('listed as unported but drawing correctly now -- shorten CKnownUnported:' +
      staleListed, '', staleListed);
  finally
    failing.Free;
    report.Free;
    names.Free;
  end;
end;

function TDeviceScaleSweepTest.BuildIconGrid(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyIconGrid;
  names: TStringList;
  i: Integer;
begin
  g := TTyIconGrid.Create(AParent);
  g.Parent := AParent;
  TControlAccess(g).Font.PixelsPerInch := APPI;
  g.IconFont := FIconFont;
  names := TStringList.Create;
  try
    for i := 0 to 11 do names.Add('glyph' + IntToStr(i));
    g.SetNames(names);
  finally
    names.Free;
  end;
  Result := g;
end;

procedure TDeviceScaleSweepTest.TestIconGridAtTheDeviceScale;
var
  i, score: Integer;
begin
  FIconFont := TTyIconFont.Create(nil);
  try
    FIconFont.FontFamily := 'Arial';
    for i := 0 to 11 do
      FIconFont.MapGlyph('glyph' + IntToStr(i), Ord('A') + i);   // letters: a font with ink
    score := TyDeviceScaleMismatch(@BuildIconGrid, 240, 160);
    AssertTrue(Format('the icon grid draws at the device scale (unmatched ink %d > %d)',
      [score, CMaxMismatch]), score <= CMaxMismatch);
  finally
    FreeAndNil(FIconFont);
  end;
end;

initialization
  RegisterTest(TDeviceScaleSweepTest);

end.
