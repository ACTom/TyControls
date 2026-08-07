unit tyControls.Panel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Accel,
  tyControls.Controller;
type
  TTyPanel = class(TTyCustomControl)
  protected
    { protected, not private: a test drives the invalidation rule through it. }
    FPaintCache: TTyPaintCache;
  private
    FAlignment: TAlignment;
    FVerticalAlignment: TVerticalAlignment;
    FWordWrap: Boolean;
    FShowAccelChar: Boolean;
    { Repaint when Caption/Text changes -- the LCL hook that replaces our old setter. }
    procedure TextChanged; override;
    procedure SetAlignment(AValue: TAlignment);
    procedure SetVerticalAlignment(AValue: TVerticalAlignment);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetShowAccelChar(AValue: Boolean);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { BorderWidth's ONLY consumer. It is a TWinControl member the base class republishes,
      but TWinControl itself never reads it -- TWinControl.AdjustClientRect is an empty
      no-op (C:/lazarus/lcl/include/wincontrol.inc:2498) and SetBorderWidth only posts
      CM_BORDERCHANGED (:4225). In the LCL the inset is done here, by TCustomPanel
      (include/custompanel.inc:191-204), and nowhere else. So publishing it without this
      override left the Object Inspector offering a gutter the container ignored: the
      designer wrote BorderWidth = 8, the children stayed flush against the frame, and
      nothing said why. Same rect maths as TCustomPanel, minus the bevels we do not have. }
    procedure AdjustClientRect(var ARect: TRect); override;
  public
    destructor Destroy; override;
    procedure Invalidate; override;
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
  published
    { Caption is TControl's, not a second string of our own.

      It used to be a field-backed property shadowing TControl.Caption, so a control had
      TWO captions: `P.Caption := 'x'` set ours and left TControl.Text empty, while
      anything reading Text -- an action link, an accessibility query, TControl's own
      csSetCaption wiring, generic code that walks TControl -- saw ''. On LCL these are one
      string: Caption IS Text, routed through RealSetText, and a repaint is arranged by
      overriding TextChanged. That is what this does now. }
    property Caption;
    property Alignment: TAlignment read FAlignment write SetAlignment default taCenter;
    { The caption's VERTICAL placement. The horizontal Alignment has been here since the
      start and this axis was hardcoded to the middle, so a section-header band -- label at
      the top, children below -- could not be expressed with the panel's own Caption at all.

      THE TYPE IS THE PARITY CLAIM. TCustomPanel declares
        VerticalAlignment: TVerticalAlignment ... default taVerticalCenter  (extctrls.pp:1154)
      over the RTL's enum (taAlignTop, taAlignBottom, taVerticalCenter -- classesh.inc:94,
      ordinals 0/1/2, and the `default` directive below stores that ordinal). This property
      briefly shipped in-dev typed Graphics.TTextLayout: same name, wrong type, so
      `P.VerticalAlignment := taAlignBottom` did not compile and an .lfm written by a real
      TPanel ('VerticalAlignment = taAlignBottom') refused to load -- the exact collision
      class (LCL's name, not LCL's meaning) this library keeps removing. BREAKING for any
      .lfm saved by the three-day dev window that streamed `tlTop`/`tlBottom`: those now
      fail to read LOUDLY (never silently reinterpreted); the streamed DEFAULT wrote no
      line at all and is unaffected. The painter still thinks in TTextLayout -- RenderTo
      maps through LCL's own name-map (see VerticalAlignmentToTextLayout there). }
    property VerticalAlignment: TVerticalAlignment read FVerticalAlignment
      write SetVerticalAlignment default taVerticalCenter;
    { Wrap a long caption instead of ellipsising it. The painter has taken AMultiLine since
      multi-line text landed and the panel simply never passed it, so a banner/caption panel
      silently clipped its second line to "...". Default False = the behaviour every existing
      form already has. }
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    { Interpret '&' as a mnemonic marker: the '&' is eaten and the next character underlined
      while Alt is held. tyControls.Accel has done the parsing for ten other controls; the
      panel was the container that still painted the ampersand literally. Display only, as
      TCustomPanel's is -- a panel takes no focus, so there is nothing for Alt+letter to
      activate. Default False matches extctrls.pp:1153. }
    property ShowAccelChar: Boolean read FShowAccelChar write SetShowAccelChar default False;
    { Docking, republished exactly as TPanel does. Every member here is TWinControl's or
      TControl's own and the dock manager that drives them is LCL code we do not touch --
      the probe in tests/test.parity.container.pas docks a real control into a TTyPanel and
      asserts the reparent, the client list and the notifications, so this is republish and
      not re-implementation. DockSite/UseDockManager/OnDockDrop/OnDockOver/OnUnDock are
      public on TWinControl; OnGetSiteInfo/OnGetDockCaption and OnStartDock/OnEndDock are
      protected, which is why NO route reached them before -- not the designer, not code. }
    property DockSite;
    property UseDockManager;
    property OnDockDrop;
    property OnDockOver;
    property OnUnDock;
    property OnGetSiteInfo;
    property OnGetDockCaption;
    property OnStartDock;
    property OnEndDock;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;
implementation
constructor TTyPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Designer container: the IDE drops child controls INTO the panel.
  ControlStyle := ControlStyle + [csAcceptsControls];
  FAlignment := taCenter;
  FVerticalAlignment := taVerticalCenter;
  FWordWrap := False;
  FShowAccelChar := False;
  { A screen reader had nothing to announce a ty container as: every control in the library
    was left at TControl's larUnknown, so the structural landmarks a stock LCL form gives
    away for free (this region is a GROUP) were simply absent. TCustomPanel.Create sets the
    same role (include/custompanel.inc:45). The DESCRIPTION is deliberately not set here:
    LCL's is a resourcestring, and inventing a second translatable string for the same idea
    would need a .po round in both packages to say what the role already says. }
  AccessibleRole := larGroup;
  Width := 185;
  Height := 41;
end;

{ See the declaration: this is the only place BorderWidth is read. }
procedure TTyPanel.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  if BorderWidth > 0 then
  begin
    InflateRect(ARect, -BorderWidth, -BorderWidth);
    if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
    if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
  end;
end;
function TTyPanel.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;
procedure TTyPanel.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;
procedure TTyPanel.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyPanel.SetVerticalAlignment(AValue: TVerticalAlignment);
begin
  if FVerticalAlignment = AValue then Exit;
  FVerticalAlignment := AValue;
  Invalidate;
end;

procedure TTyPanel.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  Invalidate;
end;

procedure TTyPanel.SetShowAccelChar(AValue: Boolean);
begin
  if FShowAccelChar = AValue then Exit;
  FShowAccelChar := AValue;
  { Register only while the feature is ON. The underline appears while Alt is HELD, and the
    only thing that repaints on the Alt edge is the accel watcher's registry -- but that
    registry installs an Application-wide input hook and invalidates every member on each
    Alt press, so signing up every panel in the app for a feature that defaults off would
    be a permanent cost for nothing. }
  if FShowAccelChar then TyAccelRegister(Self) else TyAccelUnregister(Self);
  Invalidate;
end;
procedure TTyPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
const
  { LCL's own map, verbatim (custompanel.inc:147) -- and it maps by NAME, not by ordinal:
    the two enums order their members differently ((top, BOTTOM, centre) on the RTL side,
    (top, CENTRE, bottom) on the painter's), so a Delphi-style typecast here would swap
    bottom and centre and compile clean. This array is the single seam between the
    published LCL-typed axis and the painter's TTextLayout; paint has no other source. }
  VerticalAlignmentToTextLayout: array[TVerticalAlignment] of TTextLayout =
    (tlTop, tlBottom, tlCenter);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect: TRect;
  Disp: string;
  MnPos: Integer;
  Meas: TBitmap;
  Lines: TStringList;
begin
  P := TTyPainter.Create;
  try
    { MIRRORING: the Caption, and nothing else -- deliberately. The panel's own CHILDREN are
      not mirrored, because LCL's align engine does not mirror either (the only BiDi branch
      in wincontrol.inc is the ChildSizing TABLE path, :1551, which TTyPanel republishes and
      therefore gets for free). Mirroring alLeft here would make a ty panel lay out
      differently from every native container next to it and misplace any ported .lfm.
      See plans/2026-08-04-rtl-mirroring-scope.md §6.3. No internal hit test. }
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    S := CurrentStyle;
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, ContentRect, S);
    // Inset content by padding
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    if Caption <> '' then
    begin
      { Mnemonic: strip the '&' and remember which character it marked. Off, the caption
        goes to the painter untouched, so a caption that really contains an ampersand still
        paints one -- the same either/or TCustomPanel's TS.ShowPrefix gives. }
      if FShowAccelChar then
        TyParseMnemonic(Caption, Disp, MnPos)
      else
      begin
        Disp := Caption;
        MnPos := 0;
      end;
      { Wrapping is done HERE, not by the painter's AMultiLine: AMultiLine only honours line
        breaks the caption already contains, and a caption that needs wrapping by definition
        has none. TyWrapTextCJK is the library's one greedy wrap kernel (it breaks between
        CJK codepoints as well as at spaces, so a Chinese caption wraps instead of running
        off the edge) and it needs a canvas carrying the resolved font to measure against.
        The wrapped lines then go back through AMultiLine, which anchors the block by
        FVerticalAlignment and draws each line in its own box.

        The mnemonic underline survives only on the single-line path -- the painter's
        multi-line loop has no per-line mnemonic offset. Wrapping a caption AND underlining
        an access key in it is a combination TCustomPanel does not really serve either
        (its ShowPrefix is a single TTextStyle flag over the whole block), and the '&' is
        still consumed, so the caption reads correctly; only the underline is absent. }
      if FWordWrap then
      begin
        Meas := TBitmap.Create;
        Lines := TStringList.Create;
        try
          Meas.SetSize(1, 1);
          TyConfigureMeasureFont(Meas.Canvas, S.FontName, ResolveFontSize(S),
            S.FontWeight, APPI);
          TyWrapTextCJK(Disp, ContentRect.Right - ContentRect.Left, Meas.Canvas, Lines);
          Disp := Lines.Text;
        finally
          Lines.Free;
          Meas.Free;
        end;
      end;
      { Ellipsis and wrapping are the two halves of "the caption does not fit": wrapping ON
        means the text may use more lines, so it must NOT also be cut at one. }
      P.DrawText(ContentRect, Disp, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, FAlignment, VerticalAlignmentToTextLayout[FVerticalAlignment],
        not FWordWrap,
        TyAccelGatePos(MnPos), False, FWordWrap, TyLineHeight(ActiveController));
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;
destructor TTyPanel.Destroy;
begin
  { Only ever registered while ShowAccelChar was on; unregistering an absent control is a
    no-op, so this needs no flag test and cannot leave a dangling entry behind. }
  TyAccelUnregister(Self);
  FPaintCache.Free;
  inherited Destroy;
end;

procedure TTyPanel.Invalidate;
begin
  { The one thing the cache keys on: our OWN look changed. A child's damage never reaches
    here, which is exactly why the cache survives it. }
  if FPaintCache <> nil then FPaintCache.Drop;
  inherited Invalidate;
end;

procedure TTyPanel.Paint;
var
  w, h: Integer;
begin
  { Nothing here fires OnPaint, and nothing here should: the base fires it from PaintWindow,
    AFTER this method has returned. That is what keeps an application's overlay out of the
    cache -- baked in, it would be frozen at the frame it was drawn on and then replayed by
    every child-damage blit. }
  { The designer repaints rarely and streams while it does, so cache only at runtime. }
  if csDesigning in ComponentState then
  begin
      RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
    Exit;
  end;
  w := ClientWidth; h := ClientHeight;
  if (w <= 0) or (h <= 0) then Exit;
  if FPaintCache = nil then FPaintCache := TTyPaintCache.Create;
  if FPaintCache.NeedsRender(w, h) then
    RenderTo(FPaintCache.Canvas, Rect(0, 0, w, h), Font.PixelsPerInch);
  FPaintCache.Blit(Canvas);
end;

end.
