unit tyControls.AdvChart.Measure;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the bridge between the pure layout layer and the painter.

  This is the ONLY AdvChart unit allowed to reach the painter, and therefore the
  only one that pulls in the LCL. Everything upstream of it (Types, Scale, Coord,
  Layout) stays free of Controls/Graphics so that its arithmetic can be tested
  headlessly and deterministically. Two things cross the line here:

    * ITyTextMeasurer, backed by the painter's real font metrics;
    * the anchor enums, converted to the LCL's TAlignment / TTextLayout.

  WHY THE MEASURER TAKES THE LARGER OF TWO WIDTHS. The painter documents (in the
  header above TyMeasureRenderedTextWidth) that its two measurement paths are two
  different rasterisers and disagree by about a pixel -- on that machine "New" is
  26 by the LCL canvas and 27 by the BGRA renderer -- and states the rule:

      any control whose size floor feeds a clip must take the LARGER of the two.

  An axis label is exactly that case. The layout reserves room from this number
  and the text is then drawn by BGRA; measure one pixel short and the label the
  axis just made room for gets ellipsised. So: width is the max of both paths,
  height comes from the block measurement, which is the one that knows about
  line boxes. }
interface
uses
  SysUtils, Math, Graphics, Classes,
  tyControls.AdvChart.Types, tyControls.Painter;

type
  { A measurer bound to one PPI. The chart makes one per paint, because PPI is
    fixed for the duration of a frame and threading it through every call would
    only give callers a way to disagree about it. }
  TTyPainterTextMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  private
    FPPI: Integer;
  public
    constructor Create(APPI: Integer);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    property PPI: Integer read FPPI;
  end;

{ Anchor enums -> the LCL's, for handing a placement to DrawTextRotated. }
function TyAnchorToAlignment(A: TTyTextAnchorH): TAlignment;
function TyAnchorToLayout(A: TTyTextAnchorV): TTextLayout;

implementation

constructor TTyPainterTextMeasurer.Create(APPI: Integer);
begin
  inherited Create;
  if APPI <= 0 then
    APPI := 96;
  FPPI := APPI;
end;

procedure TTyPainterTextMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var
  blockW, blockH, renderW: Integer;
begin
  AW := 0;
  AH := 0;
  if AText = '' then
  begin
    { An empty label still has a line box -- an axis with one blank tick must not
      collapse its gutter to nothing and then re-expand when the value returns. }
    TyMeasureTextBlock('Ag', AFontName, AFontSizeLogical, AWeight, FPPI, 0, 0,
                       blockW, blockH);
    AH := blockH;
    Exit;
  end;
  TyMeasureTextBlock(AText, AFontName, AFontSizeLogical, AWeight, FPPI, 0, 0,
                     blockW, blockH);
  renderW := TyMeasureRenderedTextWidth(AText, AFontName, AFontSizeLogical,
                                        AWeight, FPPI);
  { The larger of the two -- see the unit header. }
  AW := Max(blockW, renderW);
  AH := blockH;
end;

function TyAnchorToAlignment(A: TTyTextAnchorH): TAlignment;
begin
  case A of
    tahCentre: Result := taCenter;
    tahRight:  Result := taRightJustify;
  else
    Result := taLeftJustify;
  end;
end;

function TyAnchorToLayout(A: TTyTextAnchorV): TTextLayout;
begin
  case A of
    tavMiddle: Result := tlCenter;
    tavBottom: Result := tlBottom;
  else
    Result := tlTop;
  end;
end;

end.
