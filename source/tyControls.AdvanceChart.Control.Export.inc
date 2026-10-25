{ Part of tyControls.AdvanceChart (included, not a unit): export and the loading effect.
  Moved out of the unit only to keep it readable; what the control is and why it is built
  the way it is, see the unit header. }

{ ==================== export and loading [Batch 106] ==================== }

function TTyAdvanceChart.ViewHidden(AView: TTyChartView): Boolean;
begin
  Result := FExporting and (AView in FExportExclude);
end;

procedure TTyAdvanceChart.ViewDrew(AView: TTyChartView);
begin
  Include(FViewsDrawn, AView);
end;

function TTyAdvanceChart.LastViewsDrawn: TTyChartViews;
begin
  Result := FViewsDrawn;
end;

procedure TTyAdvanceChart.ExportOptsOrRaise(const AJson: string;
  out AOpts: TTyChartExportOpts);
begin
  if not TyExportOptsOf(AJson, AOpts) then
    raise EArgumentException.Create(rsTyChartExportOptsBad);
end;

{ getDataURL's render. The background first -- the options', else the
  option's, else the skin's frame -- then the chart as an export draws it,
  straight onto a 32-bit bitmap so the alpha a transparent background leaves
  survives. A render at another size or PPI than the window's lays the chart
  out at that size, and the window's layout is put back afterwards: the
  legend, the dataZoom and the hit test answer from it. }
function TTyAdvanceChart.RenderExport(const AOpts: TTyChartExportOpts): TBGRABitmap;
var
  w, h, ppi, ppi0: Integer;
  bg: TTyExportBg;
  chosen, owned: TJSONData;
  P: TTyPainter;
  R: TRect;
  measurer: ITyTextMeasurer;
  el: TTyChartElement;
  drawn: TTyChartViews;
  scratch: TBGRABitmap;
begin
  Result := nil;
  if (Width <= 0) or (Height <= 0) then Exit;
  ppi0 := Font.PixelsPerInch;
  if ppi0 <= 0 then ppi0 := 96;
  TyExportImageSize(Width, Height, ppi0, AOpts.PixelRatio, w, h, ppi);
  if (w <= 0) or (h <= 0) then Exit;
  { `opts.backgroundColor || model.get('backgroundColor')`, and then the
    painter's own: the skin's }
  owned := nil;
  chosen := nil;
  try
    if AOpts.HasBackground then
    begin
      owned := GetJSON(AOpts.BackgroundJson);
      chosen := owned;
    end
    else if FOption <> nil then
    begin
      chosen := FOption.Find('backgroundColor');
      if not TyJsTruthy(chosen) then chosen := nil;
    end;
    bg := TyExportBackgroundOf(chosen);
  finally
    owned.Free;
  end;
  Result := TBGRABitmap.Create(w, h, BGRAPixelTransparent);
  R := Rect(0, 0, w, h);
  measurer := NewTextMeasurer(ppi);
  P := NewPainter;
  FExporting := True;
  FExportBare := bg.Kind <> ebkTheme;
  FExportExclude := AOpts.Exclude;
  try
    StApplyChanged;
    P.BeginPaintOn(nil, R, ppi, Result);
    { Layer.clear: the whole image, before anything is drawn }
    case bg.Kind of
      ebkSolid, ebkBlack:
        begin
          if bg.Kind = ebkBlack then bg.Color := $FF000000;
          P.BeginPath;
          P.RectPath(0, 0, w, h);
          P.FillPath(TTyColor(bg.Color));
        end;
      ebkGradient, ebkPattern:
        begin
          el := TyChartElement(TyShapeRect(TyRectF(0, 0, w, h)));
          el.Style.HasFill := True;
          el.Style.Alpha := 1;
          if bg.Kind = ebkGradient then el.Style.FillGradient := bg.Gradient
          else el.Style.FillPattern := bg.Pattern;
          TyRenderElement(P, el);
        end;
    end;
    PaintStatic(P, R, ppi, measurer);
    PaintDynamic(P, R, ppi, measurer);
    P.EndPaint;
  finally
    FExportExclude := [];
    P.Free;
    { and back: FExporting stays on through the window's own layout below,
      so that render arms, binds and steps nothing either }
    drawn := FViewsDrawn;
    try
      if (w <> Width) or (h <> Height) or (ppi <> ppi0) then
      begin
        FExportBare := True;
        scratch := TBGRABitmap.Create(Width, Height);
        P := NewPainter;
        try
          measurer := NewTextMeasurer(ppi0);
          P.BeginPaintOn(nil, Rect(0, 0, Width, Height), ppi0, scratch);
          PaintStatic(P, Rect(0, 0, Width, Height), ppi0, measurer);
          P.EndPaint;
        finally
          P.Free;
          scratch.Free;
        end;
        { the list is the window's again; the cached picture is not }
        StaticDrop;
      end
      else
        { the list was built for the export (its views excluded, nothing bound):
          the window builds its own }
        DropStatic;
    finally
      FExporting := False;
      FExportBare := False;
      FViewsDrawn := drawn;
    end;
    InvalidateFrame;
  end;
end;

procedure TTyAdvanceChart.WriteExport(AStream: TStream; ABmp: TBGRABitmap;
  AType: TTyExportImageType);
var
  jpg: TBGRABitmap;
  writer: TFPWriterJPEG;
begin
  if AType <> eitJpeg then
  begin
    ABmp.SaveToStreamAsPng(AStream);
    Exit;
  end;
  { A CANVAS MAKES A JPEG OF ITS PIXELS OVER OPAQUE BLACK -- the format has
    no alpha -- at its default quality, 0.92 }
  jpg := TBGRABitmap.Create(ABmp.Width, ABmp.Height, BGRABlack);
  writer := TFPWriterJPEG.Create;
  try
    jpg.PutImage(0, 0, ABmp, dmDrawWithTransparency);
    writer.CompressionQuality := 92;
    TFPCustomImage(jpg).SaveToStream(AStream, writer);
  finally
    writer.Free;
    jpg.Free;
  end;
end;

function TTyAdvanceChart.RenderToBitmap(const AOptsJson: string): TBGRABitmap;
var prev: TComponent; prevRes: TTyChartImageUrlResolver;
begin
  prev := TyChartImageScopeEnter(Owner);
  prevRes := TyChartImageResolverEnter(@ResolveImageUrl);
  try
    Result := RenderToBitmapBody(AOptsJson);
  finally
    TyChartImageResolverLeave(prevRes);
    TyChartImageScopeLeave(prev);
  end;
end;

function TTyAdvanceChart.RenderToBitmapBody(const AOptsJson: string): TBGRABitmap;
var o: TTyChartExportOpts;
begin
  ExportOptsOrRaise(AOptsJson, o);
  Result := RenderExport(o);
end;

procedure TTyAdvanceChart.SaveToStream(AStream: TStream; const AOptsJson: string);
var
  o: TTyChartExportOpts;
  bmp: TBGRABitmap;
begin
  ExportOptsOrRaise(AOptsJson, o);
  bmp := RenderExport(o);
  if bmp = nil then Exit;
  try
    WriteExport(AStream, bmp, o.ImageType);
  finally
    bmp.Free;
  end;
end;

function TTyAdvanceChart.SaveToBytes(const AOptsJson: string): TBytes;
var ms: TMemoryStream;
begin
  Result := nil;
  ms := TMemoryStream.Create;
  try
    SaveToStream(ms, AOptsJson);
    SetLength(Result, ms.Size);
    if ms.Size > 0 then Move(ms.Memory^, Result[0], ms.Size);
  finally
    ms.Free;
  end;
end;

procedure TTyAdvanceChart.SaveToFile(const AFileName: string; const AOptsJson: string);
var
  o: TTyChartExportOpts;
  bmp: TBGRABitmap;
  fs: TFileStream;
  ext: string;
begin
  ExportOptsOrRaise(AOptsJson, o);
  if not o.HasType then
  begin
    ext := LowerCase(ExtractFileExt(AFileName));
    if (ext = '.jpg') or (ext = '.jpeg') then o.ImageType := eitJpeg;
  end;
  bmp := RenderExport(o);
  if bmp = nil then Exit;
  try
    fs := TFileStream.Create(AFileName, fmCreate);
    try
      WriteExport(fs, bmp, o.ImageType);
    finally
      fs.Free;
    end;
  finally
    bmp.Free;
  end;
end;

function TTyAdvanceChart.GetDataURL(const AOptsJson: string): string;
var
  o: TTyChartExportOpts;
  bmp: TBGRABitmap;
  ms: TMemoryStream;
  raw: RawByteString;
begin
  ExportOptsOrRaise(AOptsJson, o);
  bmp := RenderExport(o);
  if bmp = nil then Exit('data:,');
  ms := TMemoryStream.Create;
  try
    WriteExport(ms, bmp, o.ImageType);
    SetLength(raw, ms.Size);
    if ms.Size > 0 then Move(ms.Memory^, raw[1], ms.Size);
  finally
    ms.Free;
    bmp.Free;
  end;
  if o.ImageType = eitJpeg then Result := 'data:image/jpeg;base64,'
  else Result := 'data:image/png;base64,';
  Result := Result + EncodeStringBase64(raw);
end;

procedure TTyAdvanceChart.SaveToPng(const AFileName: string);
var
  o: TTyChartExportOpts;
  bmp: TBGRABitmap;
  fs: TFileStream;
begin
  { the export with no options, a PNG whatever the name says }
  o := Default(TTyChartExportOpts);
  o.ImageType := eitPng;
  bmp := RenderExport(o);
  if bmp = nil then Exit;
  try
    fs := TFileStream.Create(AFileName, fmCreate);
    try
      WriteExport(fs, bmp, eitPng);
    finally
      fs.Free;
    end;
  finally
    bmp.Free;
  end;
end;

{ ---- the loading effect ---- }

function TTyAdvanceChart.LoadLive: Boolean;
begin
  Result := FLoadShown and (FLoadAnim <> nil) and (FLoadAnim.ClipCount > 0)
    and (FAnimMode <> camOff);
end;

procedure TTyAdvanceChart.LoadDrop;
begin
  { freeing the element takes its clips off the driver }
  FreeAndNil(FLoadArc);
end;

procedure TTyAdvanceChart.ShowLoading(const ACfgJson: string);
begin
  ShowLoading('', ACfgJson);
end;

procedure TTyAdvanceChart.ShowLoading(const AName, ACfgJson: string);
var cfg: TTyLoadingCfg;
begin
  if not TyLoadingCfgOf(ACfgJson, rsTyChartLoading, cfg) then
    raise EArgumentException.Create(rsTyChartLoadingCfgBad);
  { hideLoading first, then the name: an unknown one has hidden the old
    effect and shows nothing }
  HideLoading;
  if (AName <> '') and (AName <> 'default') then Exit;
  FLoadCfg := cfg;
  FLoadShown := True;
  if FLoadCfg.ShowSpinner then
  begin
    if FLoadAnim = nil then FLoadAnim := NewAnimDriver;
    FLoadArc := TTyAnimBag.Create;
    FLoadArc.Animation := FLoadAnim;
    { the clips start at their first step: the next tick, upstream's next
      frame }
    TyLoadingStartSpinner(FLoadArc);
  end;
  AnimArmTimer;
  InvalidateFrame;
end;

procedure TTyAdvanceChart.HideLoading;
begin
  if not FLoadShown and (FLoadArc = nil) then Exit;
  LoadDrop;
  FLoadShown := False;
  FLoadGeoValid := False;
  AnimArmTimer;
  InvalidateFrame;
end;

function TTyAdvanceChart.LoadingGeometry(out AGeo: TTyLoadingGeometry): Boolean;
begin
  AGeo := FLoadGeo;
  Result := FLoadShown and FLoadGeoValid;
end;

function TTyAdvanceChart.LoadingCfg: TTyLoadingCfg;
begin
  Result := FLoadCfg;
end;

function TTyAdvanceChart.LoadingArcAngles(out AStart, AEnd: Double): Boolean;
begin
  AStart := NaN;
  AEnd := NaN;
  Result := FLoadShown and (FLoadArc <> nil);
  if not Result then Exit;
  AStart := FLoadArc.Num('shape.startAngle');
  AEnd := FLoadArc.Num('shape.endAngle');
end;

function TTyAdvanceChart.LoadingClipCount: Integer;
begin
  if FLoadAnim = nil then Result := 0 else Result := FLoadAnim.ClipCount;
end;

{ default.ts, drawn: the mask over the whole chart, the text hung left /
  middle off its anchor, the arc clockwise from its start to its end with
  round caps. Measured in device px and laid out in CSS px, as upstream's
  numbers are -- at 96 PPI the two are the same bits. }
procedure TTyAdvanceChart.PaintLoading(APainter: TTyPainter; const ARect: TRect;
  APPI: Integer; const AMeasurer: ITyTextMeasurer);
var
  st, spin: TTyStyleSet;
  s, devW, devH, tw, th, cx, cy, r, sweep, a0: Double;
  fontName: string;
  fontSize, weight: Integer;
  ink: TTyColor;
  path: TTyZrPath;
  box: TRect;
begin
  if not FLoadShown then Exit;
  st := ActiveController.Model.ResolveStyle('TyAdvChartLoading', '', []);
  spin := ActiveController.Model.ResolveStyle('TyAdvChartLoadingSpinner', '', []);
  fontName := st.FontName;
  if FLoadCfg.FontFamily <> '' then fontName := FLoadCfg.FontFamily;
  fontSize := ResolveFontSize(st);
  if FLoadCfg.HasFontSize then fontSize := FLoadCfg.FontSizeLogical;
  weight := st.FontWeight;
  if FLoadCfg.HasFontWeight then weight := FLoadCfg.FontWeight;
  if APPI > 0 then s := APPI / 96 else s := 1;
  devW := ARect.Right - ARect.Left;
  devH := ARect.Bottom - ARect.Top;
  tw := 0;
  th := 0;
  if FLoadCfg.Text <> '' then
    AMeasurer.MeasureLine(FLoadCfg.Text, fontName, fontSize, weight, tw, th);
  TyLoadingLayout(devW / s, devH / s, tw / s, FLoadCfg.ShowSpinner,
    FLoadCfg.SpinnerRadius, FLoadGeo);
  FLoadGeoValid := True;

  { the mask }
  case FLoadCfg.MaskColor.Kind of
    likColour: ink := TTyColor(FLoadCfg.MaskColor.Colour);
    likNone: ink := 0;
  else
    if tpBackground in st.Present then ink := st.Background.Color else ink := 0;
  end;
  if TyAlphaOf(ink) > 0 then
  begin
    APainter.BeginPath;
    APainter.RectPath(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
    APainter.FillPath(ink);
  end;

  { the text, its left edge on the anchor and its middle on the line }
  case FLoadCfg.TextColor.Kind of
    likColour: ink := TTyColor(FLoadCfg.TextColor.Colour);
    likNone: ink := 0;
  else
    ink := st.TextColor;
  end;
  if (FLoadCfg.Text <> '') and (TyAlphaOf(ink) > 0) then
  begin
    box.Left := ARect.Left + Round(FLoadGeo.TextX * s);
    box.Top := ARect.Top + Round(FLoadGeo.TextY * s - th / 2);
    { to the edge: a left-aligned run needs no right, and a box one pixel
      short would cut its last glyph }
    box.Right := Max(box.Left + Ceil(tw) + 1, ARect.Right);
    box.Bottom := box.Top + Ceil(th);
    APainter.DrawText(box, TyInkText(FLoadCfg.Text), fontName, fontSize, weight,
      ink, taLeftJustify, tlCenter, False, 0, False, Pos(#10, FLoadCfg.Text) > 0);
  end;

  { the spinner: PathProxy's arc, its angles normalised as a canvas takes
    them -- an end behind the start goes the long way round }
  if (not FLoadCfg.ShowSpinner) or (FLoadArc = nil) then Exit;
  case FLoadCfg.Color.Kind of
    likColour: ink := TTyColor(FLoadCfg.Color.Colour);
    likNone: ink := 0;
  else
    if tpBorderColor in spin.Present then ink := spin.BorderColor else ink := 0;
  end;
  r := FLoadGeo.R * s;
  if (TyAlphaOf(ink) = 0) or (FLoadCfg.LineWidth <= 0) or not (r > 0) then Exit;
  cx := ARect.Left + FLoadGeo.CX * s;
  cy := ARect.Top + FLoadGeo.CY * s;
  path := nil;
  TyZrArc(path, cx, cy, r, FLoadArc.Num('shape.startAngle'),
    FLoadArc.Num('shape.endAngle'), False);
  if Length(path) = 0 then Exit;
  a0 := path[0].V[4];
  sweep := path[0].V[5];
  if IsNan(a0) or IsNan(sweep) then Exit;
  APainter.SaveState;
  try
    APainter.SetLineDash([]);
    APainter.SetLineCap(tlcRound);
    APainter.BeginPath;
    APainter.ArcTo(cx, cy, r, a0, a0 + sweep, False);
    APainter.StrokePath(ink, FLoadCfg.LineWidth);
  finally
    APainter.RestoreState;
  end;
end;
