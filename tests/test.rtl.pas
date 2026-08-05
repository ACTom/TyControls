unit test.rtl;
{ RTL MIRRORING -- the layout half of right-to-left support.

  Its sibling test.bidi.pas guards the TEXT half: word order, shaping, the paragraph's base
  direction. That half asks "which way does this SENTENCE read" and answers it from the
  string. This unit guards the other question, "which way does this FORM read", which is
  answered from the control's BiDiMode and moves BOXES, not glyphs. The two are independent
  on purpose -- an Arabic caption on a left-to-right form reorders its words and stays on the
  left; a Latin caption on a right-to-left form keeps its word order and moves to the right --
  and several of the tests below exist only to pin that independence.

  Scope, deliberately partial: phases 0 and 1 of plans/2026-08-04-rtl-mirroring-scope.md, i.e.
  the painter's alignment lever plus the five control families that already had a left/right
  switch built. Every control in that batch answers clicks over its WHOLE face, so paint and
  hit test cannot come apart -- which is the entire reason this is a safe cut to ship. The
  two controls in the same source files that DO hit-test internally are excluded, and the
  last two tests here pin that exclusion so a later mirroring commit has to face the hit test
  rather than walk past it.

  Everything is headless: pure geometry functions where there are any, and RenderTo into an
  off-screen bitmap where there are not. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls, fpcunit, testregistry, Forms,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  tyControls.TyLabel, tyControls.Divider, tyControls.CheckBox, tyControls.GroupBox,
  tyControls.CheckGroup, tyControls.RadioGroup, tyControls.Button, tyControls.GlyphButtons,
  tyControls.DropButtons, tyControls.ColorButton, tyControls.ButtonGroup, tyControls.Panel,
  tyControls.IconFont;

type
  { RenderTo is protected on every one of these; the tests must call it directly, because
    Paint is unreachable without a realised handle the headless runner never creates. }
  TLabelAccess       = class(TTyLabel) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TCheckAccess       = class(TTyCheckBox) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TRadioAccess       = class(TTyRadioButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TGroupBoxAccess    = class(TTyGroupBox) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TPanelAccess       = class(TTyPanel) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TButtonAccess      = class(TTyButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TGlyphBtnAccess    = class(TTyGlyphButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TColorBtnAccess    = class(TTyColorButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); end;
  TDropBtnAccess     = class(TTyDropDownButton) public procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); function ArrowW(APPI: Integer): Integer; end;

  { The painter lever itself: phase 0. One flag, set at BeginPaint, resolving every
    alignment the caller passes from a reading-order one to a physical one. }
  TRtlPainterTest = class(TTestCase)
  private
    { Draw AText into an AW x AH bitmap with the painter armed (or not) and return it. }
    function Draw(const AText: string; AW, AH: Integer; AHAlign: TAlignment;
      ARtl: Boolean; AMnemonicPos: Integer = 0): TBGRABitmap;
  published
    procedure UnarmedPainterLeavesAlignmentExactlyAsTheCallerWroteIt;
    procedure ArmedPainterMovesALeadingAlignedCaptionToTheRightEdge;
    procedure ArmedPainterMovesATrailingAlignedCaptionToTheLeftEdge;
    procedure CentredTextIsTheFixedPointOfMirroring;
    procedure MnemonicUnderlineTravelsWithTheMirroredCaption;
    procedure CaretQueryAnswersFromTheMirroredBlockNotTheUnmirroredOne;
    procedure CaretAndHitTestStayInversesUnderMirroring;
    procedure MirroringIsTheFormsDirectionNotTheScriptsDirection;
  end;

  { Phase 1, the controls that carry a caption in their WHOLE content rect: the painter
    flag is the entire change, so these guard the wiring rather than any new arithmetic. }
  TRtlCaptionTest = class(TTestCase)
  published
    procedure LabelCaptionMovesToTheRightEdge;
    procedure PanelCaptionMovesToTheRightEdge;
    procedure GroupBoxCaptionBandMovesToTheOtherEndOfTheFrame;
    procedure ButtonCaptionMovesButTheDefaultCentredOneDoesNot;
  end;

  { Phase 1, the check box / radio button pair: the indicator changes sides and the caption
    re-hugs it. The switch predates this work; only which way it points is new. }
  TRtlIndicatorTest = class(TTestCase)
  published
    procedure CheckBoxIndicatorMovesToTheRightEdge;
    procedure CheckBoxCaptionStaysHuggedToTheMirroredIndicator;
    procedure RadioButtonIndicatorMovesToTheRightEdge;
    procedure ExplicitAlignmentIsOverriddenNotIgnored;
    procedure MirroringNeverRewritesTheStoredAlignment;
  end;

  { Phase 1, the pure geometry functions. These are the cheapest and strongest guards in the
    unit: no painter, no handle, no theme -- just the arithmetic. }
  TRtlGeometryTest = class(TTestCase)
  published
    procedure DividerCaptionAndRuleSwapEnds;
    procedure DividerIndentCountsFromTheReadingStart;
    procedure DividerMirroringLeavesNoSeamBetweenCaptionAndRule;
    procedure DividerWithNoCaptionKeepsItsFullWidthRuleInRightRule;
    procedure CheckGroupColumnsFillFromTheRight;
    procedure RadioGroupColumnsFillFromTheRight;
    procedure MirroredColumnsStillTileTheClientRectFlush;
    procedure BadgeCornerFlipsHorizontallyAndNotVertically;
    procedure GlyphLayoutFlipsTheSidePairAndNotTheStackedPair;
  end;

  { Phase 1, the composite controls: real child controls, and the keyboard. }
  TRtlGroupTest = class(TTestCase)
  published
    procedure RadioGroupChildrenInheritTheGroupsDirection;
    procedure RadioGroupChildrenAreLaidOutRightToLeft;
    procedure CheckGroupChildrenAreLaidOutRightToLeft;
    procedure ArrowKeysFollowTheMirroredColumnsNotTheScreenEdges;
    procedure VerticalArrowKeysAreUntouchedByMirroring;
  end;

  { Phase 1, the button descendants that own a slot beside the caption. }
  TRtlButtonSlotTest = class(TTestCase)
  published
    procedure GlyphButtonCaptionMovesToTheOtherSideOfTheIcon;
    procedure ColorButtonSwatchMovesToTheRightEdge;
    procedure BadgeMovesToTheTrailingCornerWhichIsBottomLeftWhenMirrored;
  end;

  { The two controls in these same source files that are deliberately NOT mirrored, because
    they read x back out of a click. Pinned so that mirroring them later is a decision
    somebody makes on purpose, with the hit test in the same commit. }
  TRtlExclusionTest = class(TTestCase)
  published
    procedure DropDownArrowStaysWhereItsHitTestSaysItIs;
    procedure ButtonGroupSegmentsAreNotMirroredWhileSegmentAtReadsRawX;
  end;

implementation

const
  cInk = 40;   // alpha above which a pixel counts as ink (matches test.bidi.pas)

procedure TLabelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);      begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TCheckAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);      begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TRadioAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);      begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TGroupBoxAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);   begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TPanelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);      begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);     begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TGlyphBtnAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);   begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TColorBtnAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);   begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TDropBtnAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);    begin inherited RenderTo(ACanvas, ARect, APPI); end;
function  TDropBtnAccess.ArrowW(APPI: Integer): Integer;     begin Result := ArrowZoneWidth(APPI); end;

{ Press an arrow key the way a user does: on the FOCUSED CHILD. The group's navigation lives
  behind the OnKeyDown it wires onto every hosted radio (tyControls.RadioGroup.pas:311), so
  driving it from there exercises the whole route -- key to relay to MoveSelection -- rather
  than a private helper the keyboard might one day stop reaching. }
procedure PressArrow(AGroup: TTyRadioGroup; AChild: TControl; AKey: Word);
var
  k: Word;
  h: TKeyEvent;
begin
  k := AKey;
  h := TTyRadioButton(AChild).OnKeyDown;
  if Assigned(h) then h(AChild, k, []);
end;

{ ---------------------------------------------------------------- helpers -- }

{ The x-span of every pixel whose alpha clears cInk. L = -1 when there is no ink at all,
  which every caller asserts against before reading the span -- an empty bitmap otherwise
  compares "further right" than anything and turns a blank render into a pass. }
procedure InkSpanX(A: TBGRABitmap; out L, R: Integer);
var
  x, y: Integer;
begin
  L := A.Width; R := -1;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y).alpha > cInk then
      begin
        if x < L then L := x;
        if x > R then R := x;
      end;
  if R < 0 then L := -1;
end;

{ The x-span of pixels in which ONE channel dominates -- the way every control probe below
  finds its piece of a composite.

  Deliberately a dominance test rather than "matches this colour" or "is dark", because the
  host a control's RenderTo composites onto is not a reliable reference here: a pf32bit
  TBitmap round-tripped back through TBGRABitmap comes back with the GDI fill LOST (the
  background reads 0,0,0 whatever colour it was painted). That is the same class of trap the
  library's own notes record about BGRA/TPicture round-trips, and probing "dark ink" against
  it silently matches the whole bitmap. Channel dominance is true of a saturated theme colour
  and false of black, white and every grey, so it survives whatever the background turns out
  to be -- which is why the themes these tests load use pure red / green / blue. }
type
  TChannel = (chRed, chGreen, chBlue);

procedure ChannelSpanX(A: TBGRABitmap; ACh: TChannel; out L, R: Integer);
var
  x, y, mine, o1, o2: Integer;
  p: TBGRAPixel;
begin
  L := A.Width; R := -1;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      p := A.GetPixel(x, y);
      case ACh of
        chRed:   begin mine := p.red;   o1 := p.green; o2 := p.blue;  end;
        chGreen: begin mine := p.green; o1 := p.red;   o2 := p.blue;  end;
      else       begin mine := p.blue;  o1 := p.red;   o2 := p.green; end;
      end;
      if (mine > 150) and (o1 < 110) and (o2 < 110) then
      begin
        if x < L then L := x;
        if x > R then R := x;
      end;
    end;
  if R < 0 then L := -1;
end;

{ An AW x AH host bitmap for RenderTo. Its colour is not asserted on anywhere (see
  ChannelSpanX); it is filled only so the canvas is initialised. }
function NewHost(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(0, 0, AW, AH);
end;

{ ------------------------------------------------------------ TRtlPainterTest }

function TRtlPainterTest.Draw(const AText: string; AW, AH: Integer; AHAlign: TAlignment;
  ARtl: Boolean; AMnemonicPos: Integer = 0): TBGRABitmap;
var
  host: TBitmap;
  p: TTyPainter;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(AW, AH);
    p.BeginPaint(host.Canvas, Rect(0, 0, AW, AH), 96, ARtl);
    p.DrawText(Rect(0, 0, AW, AH), AText, 'Arial', 12, 400, TyRGBA(0, 0, 0, 255),
      AHAlign, tlCenter, False, AMnemonicPos);
    Result := TBGRABitmap.Create(AW, AH);
    Result.PutImage(0, 0, p.Bitmap, dmSet);
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
end;

{ The default, and the reason every one of the 5000-odd existing pixel assertions still
  holds: BidiFlipAlignment's False row is the identity, so an unarmed painter is the painter
  that was there before. Stated as its own test because "the default is False" is the whole
  safety property of making this a parameter instead of something read off the control. }
procedure TRtlPainterTest.UnarmedPainterLeavesAlignmentExactlyAsTheCallerWroteIt;
var
  bmp: TBGRABitmap;
  l, r: Integer;
begin
  bmp := Draw('Ag', 200, 30, taLeftJustify, False);
  try
    InkSpanX(bmp, l, r);
    AssertTrue('caption drew something', l >= 0);
    AssertTrue('left-aligned text starts near the left edge', l < 8);
    AssertTrue('and does not reach the right edge', r < 100);
  finally
    bmp.Free;
  end;
end;

{ Phase 0 itself. taLeftJustify means "the reading start", so on a right-to-left form it
  resolves to the RIGHT edge -- and because every DrawText in the library funnels through
  the one function that does this, arming a control mirrors all of its text at once. }
procedure TRtlPainterTest.ArmedPainterMovesALeadingAlignedCaptionToTheRightEdge;
var
  bmp: TBGRABitmap;
  l, r: Integer;
begin
  bmp := Draw('Ag', 200, 30, taLeftJustify, True);
  try
    InkSpanX(bmp, l, r);
    AssertTrue('caption drew something', l >= 0);
    AssertTrue('mirrored leading-aligned text ends near the right edge', r > 200 - 8);
    AssertTrue('and no longer touches the left edge', l > 100);
  finally
    bmp.Free;
  end;
end;

{ The other direction, so a mutant that hard-codes taRightJustify instead of flipping is
  caught rather than half-caught. }
procedure TRtlPainterTest.ArmedPainterMovesATrailingAlignedCaptionToTheLeftEdge;
var
  bmp: TBGRABitmap;
  l, r: Integer;
begin
  bmp := Draw('Ag', 200, 30, taRightJustify, True);
  try
    InkSpanX(bmp, l, r);
    AssertTrue('caption drew something', l >= 0);
    AssertTrue('mirrored trailing-aligned text starts near the left edge', l < 8);
    AssertTrue('and no longer reaches the right edge', r < 100);
  finally
    bmp.Free;
  end;
end;

{ taCenter has no reading direction, so it must survive the flip untouched -- which is also
  why the great majority of buttons in an existing UI render byte-identically when mirrored
  (TTyButton.Alignment defaults to taCenter). }
procedure TRtlPainterTest.CentredTextIsTheFixedPointOfMirroring;
var
  ltr, rtl: TBGRABitmap;
  ll, lr, rl, rr: Integer;
begin
  ltr := Draw('Ag', 200, 30, taCenter, False);
  rtl := Draw('Ag', 200, 30, taCenter, True);
  try
    InkSpanX(ltr, ll, lr);
    InkSpanX(rtl, rl, rr);
    AssertTrue('centred caption drew something', ll >= 0);
    AssertEquals('centred text does not move when mirrored (left edge)', ll, rl);
    AssertEquals('centred text does not move when mirrored (right edge)', lr, rr);
  finally
    ltr.Free;
    rtl.Free;
  end;
end;

{ The mnemonic underline is placed by a SECOND reading of the alignment, a few lines below
  the one that places the glyphs. Mirroring them from one resolved value is what keeps them
  together; this is the test that fails if a later change flips only the text. }
procedure TRtlPainterTest.MnemonicUnderlineTravelsWithTheMirroredCaption;
var
  plain, marked: TBGRABitmap;
  pl, pr, ml, mr: Integer;
begin
  { The same caption with and without an underline. The underline can only ADD ink, so if it
    landed at the unmirrored position the marked render's span would reach further LEFT than
    the plain one's -- a whole box away, not a pixel. }
  plain  := Draw('Save', 200, 30, taLeftJustify, True, 0);
  marked := Draw('Save', 200, 30, taLeftJustify, True, 1);
  try
    InkSpanX(plain, pl, pr);
    InkSpanX(marked, ml, mr);
    AssertTrue('both captions drew something', (pl >= 0) and (ml >= 0));
    { First: the underlined caption is mirrored AT ALL. Without this the two comparisons
      below are satisfied by an unmirrored pair just as well as by a mirrored one -- they
      only say the underline agrees with the text, not that either of them moved. }
    AssertTrue('the underlined caption is at the right edge like its plain twin',
      (mr > 200 - 8) and (ml > 100));
    AssertTrue('the underline did not land back at the unmirrored position',
      ml >= pl - 2);
    AssertTrue('and it stayed inside the mirrored caption', mr <= pr + 2);
  finally
    plain.Free;
    marked.Free;
  end;
end;

{ TextCaretX answers "where on screen is character N". It is the seam a text control will
  eventually use, and a caret computed from an UNmirrored block would point at a glyph that
  is no longer there -- the paint/hit-test split this project has been bitten by repeatedly,
  arriving through the one door nobody watches. }
procedure TRtlPainterTest.CaretQueryAnswersFromTheMirroredBlockNotTheUnmirroredOne;
var
  host: TBitmap;
  p: TTyPainter;
  xLtr, xRtl: Integer;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(200, 30);
    p.BeginPaint(host.Canvas, Rect(0, 0, 200, 30), 96, False);
    xLtr := p.TextCaretX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, 0);
    p.EndPaint;
    p.BeginPaint(host.Canvas, Rect(0, 0, 200, 30), 96, True);
    xRtl := p.TextCaretX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, 0);
    p.EndPaint;
    AssertTrue('unmirrored caret sits at the left edge', xLtr < 8);
    AssertTrue('mirrored caret moved with the text block', xRtl > 100);
  finally
    p.Free;
    host.Free;
  end;
end;

{ The pair has to be mirrored TOGETHER or not at all. TextCaretX says where character n is;
  TextCharIndexAtX says which character is at x. Mirror one and not the other and every click
  lands on the wrong glyph -- which is the paint/hit-test split in its purest form, and the
  reason both queries flip in the same commit as the drawing does. Asserted as the round
  trip, so it holds whatever the actual coordinates turn out to be. }
procedure TRtlPainterTest.CaretAndHitTestStayInversesUnderMirroring;
var
  host: TBitmap;
  p: TTyPainter;
  i, x, back: Integer;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(200, 30);
    p.BeginPaint(host.Canvas, Rect(0, 0, 200, 30), 96, True);
    for i := 0 to 3 do
    begin
      { Probe the MIDDLE of each character rather than its leading edge: a caret sits on a
        boundary, and asking which character owns a boundary is ambiguous by construction. }
      x := (p.TextCaretX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, i)
          + p.TextCaretX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, i + 1)) div 2;
      back := p.TextCharIndexAtX(Rect(0, 0, 200, 30), 'Save', 'Arial', 12, 400, taLeftJustify, x);
      AssertEquals('the mirrored hit test inverts the mirrored caret', i, back);
    end;
    p.EndPaint;
  finally
    p.Free;
    host.Free;
  end;
end;

{ The independence the whole design rests on. An Arabic caption on a LEFT-to-right form
  keeps its words in bidi order AND stays on the left; the script does not get a vote on
  layout. Conflating the two would move every Arabic label in an otherwise English UI. }
procedure TRtlPainterTest.MirroringIsTheFormsDirectionNotTheScriptsDirection;
var
  bmp: TBGRABitmap;
  l, r: Integer;
begin
  { U+0628 U+062A -- BEH TEH, the pair test.bidi.pas uses. Right-to-left script, unarmed
    painter, leading alignment: it must sit on the LEFT. }
  bmp := Draw(#$D8#$A8#$D8#$AA, 200, 30, taLeftJustify, False);
  try
    InkSpanX(bmp, l, r);
    AssertTrue('the Arabic caption drew something', l >= 0);
    AssertTrue('right-to-left SCRIPT does not move a caption on a left-to-right FORM',
      l < 8);
  finally
    bmp.Free;
  end;
end;

{ ------------------------------------------------------------ TRtlCaptionTest }

procedure TRtlCaptionTest.LabelCaptionMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TLabelAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(200, 26);
  try
    Ctl.LoadThemeCss('TyLabel { color: #00FF00; padding: 0px; }');
    C := TLabelAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'Name';
    C.Alignment := taLeftJustify;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 200, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the label drew its caption', l >= 0);
      AssertTrue('a leading-aligned label caption sits at the RIGHT edge when mirrored',
        r > 200 - 10);
      AssertTrue('and has left the left edge', l > 100);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlCaptionTest.PanelCaptionMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TPanelAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(200, 26);
  try
    { A panel's Alignment defaults to taCenter, which mirroring deliberately leaves alone --
      so the property has to be set for there to be anything to see. }
    Ctl.LoadThemeCss('TyPanel { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    C := TPanelAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'Name';
    C.Alignment := taLeftJustify;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 200, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the panel drew its caption', l >= 0);
      AssertTrue('a leading-aligned panel caption sits at the RIGHT edge when mirrored',
        r > 200 - 10);
      AssertTrue('and has left the left edge', l > 100);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ The group box's caption is not merely aligned inside a box: it carries an ERASE BAND that
  breaks the top border, and the band's x is computed separately from the text's. Probing the
  caption ink catches both, because the text rect is derived from the band's left edge --
  leave the band unmirrored and the caption comes back a whole width, not a few pixels. }
procedure TRtlCaptionTest.GroupBoxCaptionBandMovesToTheOtherEndOfTheFrame;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TGroupBoxAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(200, 60);
  try
    Ctl.LoadThemeCss('TyGroupBox { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    C := TGroupBoxAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'Options';
    C.Alignment := taLeftJustify;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 200, 60), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the group box drew its caption', l >= 0);
      AssertTrue('the caption band moved to the right end of the frame', r > 200 - 20);
      AssertTrue('and vacated the left end', l > 100);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ Both halves of the button answer in one test, because the interesting fact about buttons
  is the negative one: taCenter is the default, taCenter is the fixed point, so mirroring a
  form full of ordinary buttons changes nothing at all. }
procedure TRtlCaptionTest.ButtonCaptionMovesButTheDefaultCentredOneDoesNot;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TButtonAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  cl, cr, ll, lr: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    C := TButtonAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'OK';
    C.BiDiMode := bdRightToLeft;

    host := NewHost(200, 26);                    // default Alignment = taCenter
    try
      C.RenderTo(host.Canvas, Rect(0, 0, 200, 26), 96);
      shot := TBGRABitmap.Create(host);
      try
        ChannelSpanX(shot, chGreen, cl, cr);
      finally
        shot.Free;
      end;
    finally
      host.Free;
    end;
    AssertTrue('the centred button drew its caption', cl >= 0);
    AssertTrue('a centred caption stays centred when mirrored',
      (cl > 60) and (cr < 140));

    C.Alignment := taLeftJustify;
    host := NewHost(200, 26);
    try
      C.RenderTo(host.Canvas, Rect(0, 0, 200, 26), 96);
      shot := TBGRABitmap.Create(host);
      try
        ChannelSpanX(shot, chGreen, ll, lr);
      finally
        shot.Free;
      end;
    finally
      host.Free;
    end;
    AssertTrue('the aligned button drew its caption', ll >= 0);
    AssertTrue('an explicitly leading-aligned caption moves to the right', lr > 200 - 10);
  finally
    Form.Free;
    Ctl.Free;
  end;
end;

{ ---------------------------------------------------------- TRtlIndicatorTest }

{ Shared setup for the indicator probes: an accent-blue indicator on a white control, so the
  box is findable by colour and the caption is not. }
const
  cCheckCss =
    'TyCheckBox { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyCheckBox:active { background: #0000FF; color: #FFFFFF; }' +
    'TyRadioButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyRadioButton:active { background: #0000FF; color: #FFFFFF; }';

procedure TRtlIndicatorTest.CheckBoxIndicatorMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TCheckAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(120, 24);
  try
    Ctl.LoadThemeCss(cCheckCss);
    C := TCheckAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := True;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chBlue, l, r);
      AssertTrue('the indicator was drawn', l >= 0);
      AssertTrue('the check indicator sits against the RIGHT edge when mirrored',
        r > 120 - 4);
      AssertTrue('and is no longer at the left edge', l > 80);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ The caption must follow the indicator across, not stay behind it. "Hugged" is the property
  that makes the pair read as one control instead of two things at opposite ends of a row. }
procedure TRtlIndicatorTest.CheckBoxCaptionStaysHuggedToTheMirroredIndicator;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TCheckAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  boxL, boxR, capL, capR: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(160, 24);
  try
    Ctl.LoadThemeCss(cCheckCss);
    C := TCheckAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'Enable';
    C.Checked := True;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 160, 24), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chBlue, boxL, boxR);
      ChannelSpanX(shot, chGreen, capL, capR);
      AssertTrue('indicator and caption both drew', (boxL >= 0) and (capL >= 0));
      AssertTrue('the caption is on the indicator''s left when mirrored', capR < boxL);
      { Hugged, not merely on that side: the gap is the themed --checkbox-gap, a handful of
        pixels, so anything approaching half the control means the caption stayed put and
        only the box moved. }
      AssertTrue('the caption hugs the indicator rather than the far edge',
        boxL - capR < 24);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlIndicatorTest.RadioButtonIndicatorMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TRadioAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(120, 24);
  try
    Ctl.LoadThemeCss(cCheckCss);
    C := TRadioAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := True;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chBlue, l, r);
      AssertTrue('the dot was drawn', l >= 0);
      AssertTrue('the radio indicator sits against the RIGHT edge when mirrored',
        r > 120 - 4);
      AssertTrue('and is no longer at the left edge', l > 80);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ THE design decision, made assertable.

  Alignment is a property the author can set, so mirroring had two possible meanings: flip
  the DEFAULT the author did not write, or OVERRIDE whatever they did write. This library
  takes the second, because LCL does (grids.pas:4006 flips a column's own alignment;
  checklst.pas:199 flips the indicator side unconditionally) and because the first is not
  expressible: TLeftRight has no "unset" member, so taRightJustify-because-it-is-the-default
  and taRightJustify-because-the-author-typed-it are the same value.

  So: an author who moved the indicator to the right in a left-to-right form gets it on the
  LEFT in a right-to-left one. Both ends of the switch flip. }
procedure TRtlIndicatorTest.ExplicitAlignmentIsOverriddenNotIgnored;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TCheckAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(120, 24);
  try
    Ctl.LoadThemeCss(cCheckCss);
    C := TCheckAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := True;
    C.Alignment := taLeftJustify;   // "indicator on the RIGHT", in a left-to-right form
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chBlue, l, r);
      AssertTrue('the indicator was drawn', l >= 0);
      AssertTrue('an explicitly right-side indicator mirrors to the LEFT', l < 4);
      AssertTrue('and has vacated the right edge', r < 40);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ Overriding happens per FRAME. The stored property is what the author wrote and what the
  streamer must write back out -- a mirroring pass that rewrote it would corrupt the .lfm the
  first time a right-to-left form was saved from the designer. }
procedure TRtlIndicatorTest.MirroringNeverRewritesTheStoredAlignment;
var
  Form: TForm;
  C: TCheckAccess;
  host: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  host := NewHost(120, 24);
  try
    C := TCheckAccess.Create(Form);
    C.Parent := Form;
    C.Font.PixelsPerInch := 96;
    C.Alignment := taLeftJustify;
    C.BiDiMode := bdRightToLeft;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    AssertTrue('Alignment still reads back what the author set',
      C.Alignment = taLeftJustify);
    C.BiDiMode := bdLeftToRight;
    C.RenderTo(host.Canvas, Rect(0, 0, 120, 24), 96);
    AssertTrue('and is unchanged after a left-to-right frame too',
      C.Alignment = taLeftJustify);
  finally
    host.Free;
    Form.Free;
  end;
end;

{ ----------------------------------------------------------- TRtlGeometryTest }

procedure TRtlGeometryTest.DividerCaptionAndRuleSwapEnds;
var
  ltr, rtl: TTyDividerLayout;
begin
  ltr := TyDividerLayout(200, 20, 40, taLeftJustify, TyDividerIndentAuto, 6, 4, 1, False);
  rtl := TyDividerLayout(200, 20, 40, taLeftJustify, TyDividerIndentAuto, 6, 4, 1, True);
  AssertEquals('left-to-right: caption starts at the left edge', 0, ltr.CaptionRect.Left);
  AssertEquals('left-to-right: the rule runs to the right edge', 200, ltr.RightRule.Right);
  AssertTrue('left-to-right: no left rule segment', ltr.LeftRule.Right <= ltr.LeftRule.Left);

  AssertEquals('mirrored: caption ends at the right edge', 200, rtl.CaptionRect.Right);
  AssertEquals('mirrored: caption is the same width', 40,
    rtl.CaptionRect.Right - rtl.CaptionRect.Left);
  AssertEquals('mirrored: the rule now runs from the left edge', 0, rtl.LeftRule.Left);
  AssertTrue('mirrored: no right rule segment', rtl.RightRule.Right <= rtl.RightRule.Left);
end;

{ LeftIndent keeps its name and changes its meaning to "from the reading start". Renaming it
  would break every .lfm that carries one, so the behaviour moves and the name does not --
  plans/2026-08-04-rtl-mirroring-scope.md §6.3 item 6. }
procedure TRtlGeometryTest.DividerIndentCountsFromTheReadingStart;
var
  rtl: TTyDividerLayout;
begin
  rtl := TyDividerLayout(200, 20, 40, taLeftJustify, 30, 6, 4, 1, True);
  AssertEquals('an indent of 30 leaves 30px between the caption and the RIGHT edge',
    170, rtl.CaptionRect.Right);
  AssertEquals('and the caption keeps its width', 40,
    rtl.CaptionRect.Right - rtl.CaptionRect.Left);
end;

{ A reflection of a flush layout is flush. Asserted rather than argued because the obvious
  alternative implementation -- flipping an index and re-running the arithmetic -- is exactly
  where a one-pixel seam or overlap appears, and a hairline seam in a divider is invisible in
  review and obvious on screen. }
procedure TRtlGeometryTest.DividerMirroringLeavesNoSeamBetweenCaptionAndRule;
var
  ltr, rtl: TTyDividerLayout;
begin
  ltr := TyDividerLayout(201, 20, 41, taCenter, TyDividerIndentAuto, 6, 4, 1, False);
  rtl := TyDividerLayout(201, 20, 41, taCenter, TyDividerIndentAuto, 6, 4, 1, True);
  { Odd width and odd caption on purpose: that is where the integer halving of taCenter
    puts the rounding, and where a reflection that is off by one shows up. }
  AssertEquals('the gap from the left rule to the caption is preserved',
    ltr.CaptionRect.Left - ltr.LeftRule.Right,
    rtl.CaptionRect.Left - rtl.LeftRule.Right);
  AssertEquals('the gap from the caption to the right rule is preserved',
    ltr.RightRule.Left - ltr.CaptionRect.Right,
    rtl.RightRule.Left - rtl.CaptionRect.Right);
  AssertEquals('both rule segments keep their lengths (left)',
    ltr.LeftRule.Right - ltr.LeftRule.Left, rtl.RightRule.Right - rtl.RightRule.Left);
  AssertEquals('both rule segments keep their lengths (right)',
    ltr.RightRule.Right - ltr.RightRule.Left, rtl.LeftRule.Right - rtl.LeftRule.Left);
end;

{ The captionless case returns its full-width rule in RightRule by a documented convention,
  and a full-width band is its own reflection -- so mirroring must leave that convention
  alone rather than shuffle the band into LeftRule for right-to-left dividers only. }
procedure TRtlGeometryTest.DividerWithNoCaptionKeepsItsFullWidthRuleInRightRule;
var
  rtl: TTyDividerLayout;
begin
  rtl := TyDividerLayout(200, 20, 0, taLeftJustify, TyDividerIndentAuto, 6, 4, 1, True);
  AssertEquals('the full-width rule still arrives in RightRule (left)', 0, rtl.RightRule.Left);
  AssertEquals('the full-width rule still arrives in RightRule (right)', 200, rtl.RightRule.Right);
  AssertTrue('LeftRule stays empty', rtl.LeftRule.Right <= rtl.LeftRule.Left);
end;

procedure TRtlGeometryTest.CheckGroupColumnsFillFromTheRight;
var
  c0, c1: TRect;
begin
  { 4 items, 2 columns, row-major: items 0 and 1 share the first row. }
  c0 := TyCheckGroupCellRect(Rect(0, 0, 200, 100), 4, 2, 0, 24, clHorizontalThenVertical, True);
  c1 := TyCheckGroupCellRect(Rect(0, 0, 200, 100), 4, 2, 1, 24, clHorizontalThenVertical, True);
  AssertEquals('item 0 takes the RIGHTMOST column', 200, c0.Right);
  AssertEquals('item 1 follows it leftwards', 0, c1.Left);
  AssertTrue('item 1 is entirely left of item 0', c1.Right <= c0.Left);
  AssertEquals('rows are not mirrored -- item 0 is still on the first row', c0.Top, c1.Top);
end;

procedure TRtlGeometryTest.RadioGroupColumnsFillFromTheRight;
var
  c0, c1: TRect;
begin
  c0 := TyRadioGroupCellRect(Rect(0, 0, 200, 100), 4, 2, 0, 22, clHorizontalThenVertical, True);
  c1 := TyRadioGroupCellRect(Rect(0, 0, 200, 100), 4, 2, 1, 22, clHorizontalThenVertical, True);
  AssertEquals('item 0 takes the RIGHTMOST column', 200, c0.Right);
  AssertEquals('item 1 follows it leftwards', 0, c1.Left);
  AssertTrue('item 1 is entirely left of item 0', c1.Right <= c0.Left);
  AssertEquals('rows are not mirrored', c0.Top, c1.Top);
end;

{ The remainder-absorbing last column exists so the cells tile [Left, Right) with no gap and
  no overlap. A mirrored layout owes the same guarantee, and an odd width is where it would
  be lost. }
procedure TRtlGeometryTest.MirroredColumnsStillTileTheClientRectFlush;
var
  i: Integer;
  cell, prev: TRect;
begin
  prev := Rect(0, 0, 0, 0);
  for i := 0 to 2 do
  begin
    cell := TyCheckGroupCellRect(Rect(0, 0, 101, 100), 3, 3, i, 24, clHorizontalThenVertical, True);
    if i = 0 then
      AssertEquals('the first item reaches the right edge', 101, cell.Right)
    else
      AssertEquals('each cell starts exactly where the previous one ended',
        prev.Left, cell.Right);
    prev := cell;
  end;
  AssertEquals('the last item reaches the left edge', 0, prev.Left);
end;

procedure TRtlGeometryTest.BadgeCornerFlipsHorizontallyAndNotVertically;
begin
  AssertTrue('unflipped is the identity',
    TyBidiFlipBadgePosition(bpBottomRight, False) = bpBottomRight);
  AssertTrue('the default trailing corner becomes bottom-left',
    TyBidiFlipBadgePosition(bpBottomRight, True) = bpBottomLeft);
  AssertTrue('and back again',
    TyBidiFlipBadgePosition(bpBottomLeft, True) = bpBottomRight);
  AssertTrue('the top pair flips the same way',
    TyBidiFlipBadgePosition(bpTopLeft, True) = bpTopRight);
  AssertTrue('top stays top',
    TyBidiFlipBadgePosition(bpTopRight, True) = bpTopLeft);
end;

procedure TRtlGeometryTest.GlyphLayoutFlipsTheSidePairAndNotTheStackedPair;
begin
  AssertTrue('unflipped is the identity', TyBidiFlipGlyphLayout(glLeft, False) = glLeft);
  AssertTrue('glyph-left becomes glyph-right', TyBidiFlipGlyphLayout(glLeft, True) = glRight);
  AssertTrue('and back again', TyBidiFlipGlyphLayout(glRight, True) = glLeft);
  AssertTrue('glyph-top is unaffected -- up is not a reading direction',
    TyBidiFlipGlyphLayout(glTop, True) = glTop);
  AssertTrue('nor is glyph-bottom', TyBidiFlipGlyphLayout(glBottom, True) = glBottom);
end;

{ -------------------------------------------------------------- TRtlGroupTest }

{ The groups lean on LCL propagating BiDiMode down to children that have ParentBiDiMode on,
  because that is what makes each hosted check box flip its OWN indicator without the group
  reaching inside it. If this ever stopped holding, the columns would reverse and every
  indicator would stay on the left -- so it is asserted, not assumed. }
procedure TRtlGroupTest.RadioGroupChildrenInheritTheGroupsDirection;
var
  Form: TForm;
  G: TTyRadioGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyRadioGroup.Create(Form);
    G.Parent := Form;
    G.Items.Add('A');
    G.Items.Add('B');
    G.BiDiMode := bdRightToLeft;
    AssertTrue('the group reads right-to-left', G.IsRightToLeft);
    AssertTrue('and so does its first child', G.Buttons[0].IsRightToLeft);
    AssertTrue('and its second', G.Buttons[1].IsRightToLeft);
  finally
    Form.Free;
  end;
end;

procedure TRtlGroupTest.RadioGroupChildrenAreLaidOutRightToLeft;
var
  Form: TForm;
  G: TTyRadioGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyRadioGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 120);
    G.Columns := 2;
    G.Items.Add('A');
    G.Items.Add('B');
    G.BiDiMode := bdRightToLeft;
    AssertTrue('item 0 sits in the right half', G.Buttons[0].Left > 80);
    AssertTrue('item 1 sits to its left', G.Buttons[1].Left < G.Buttons[0].Left);
  finally
    Form.Free;
  end;
end;

procedure TRtlGroupTest.CheckGroupChildrenAreLaidOutRightToLeft;
var
  Form: TForm;
  G: TTyCheckGroup;
  a, b: TTyCheckBox;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyCheckGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 120);
    G.Columns := 2;
    G.Items.Add('A');
    G.Items.Add('B');
    G.BiDiMode := bdRightToLeft;
    a := G.Buttons[0];
    b := G.Buttons[1];
    AssertTrue('both hosted boxes exist', (a <> nil) and (b <> nil));
    AssertTrue('item 0 sits in the right half', a.Left > 80);
    AssertTrue('item 1 sits to its left', b.Left < a.Left);
    AssertTrue('and each hosted box reads right-to-left itself', a.IsRightToLeft);
  finally
    Form.Free;
  end;
end;

{ The keyboard half, and the one most likely to be left behind: every instance of this bug
  is a single missing minus sign, invisible in review, and it makes the left arrow walk the
  selection backwards for exactly the users who cannot tell you why. }
procedure TRtlGroupTest.ArrowKeysFollowTheMirroredColumnsNotTheScreenEdges;
var
  Form: TForm;
  G: TTyRadioGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyRadioGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 120);
    G.Columns := 2;
    G.Items.Add('A');
    G.Items.Add('B');
    G.ItemIndex := 0;
    G.BiDiMode := bdRightToLeft;
    { Item 0 is on the right, item 1 to its left. The LEFT arrow must therefore move
      FORWARD, to item 1 -- the direction the eye travels, not the direction x grows. }
    PressArrow(G, G.Buttons[0], VK_LEFT);
    AssertEquals('the left arrow steps towards the next item when mirrored', 1, G.ItemIndex);
    PressArrow(G, G.Buttons[1], VK_RIGHT);
    AssertEquals('and the right arrow steps back', 0, G.ItemIndex);
  finally
    Form.Free;
  end;
end;

{ Only the horizontal axis has a reading direction. Mirroring the vertical one would be the
  same class of error as mirroring Home/End. }
procedure TRtlGroupTest.VerticalArrowKeysAreUntouchedByMirroring;
var
  Form: TForm;
  G: TTyRadioGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyRadioGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 120);
    G.Columns := 1;
    G.Items.Add('A');
    G.Items.Add('B');
    G.ItemIndex := 0;
    G.BiDiMode := bdRightToLeft;
    PressArrow(G, G.Buttons[0], VK_DOWN);
    AssertEquals('down still means down', 1, G.ItemIndex);
    PressArrow(G, G.Buttons[1], VK_UP);
    AssertEquals('and up still means up', 0, G.ItemIndex);
  finally
    Form.Free;
  end;
end;

{ --------------------------------------------------------- TRtlButtonSlotTest }

{ No glyph FAMILY is installed in a headless run, so the icon itself renders as an empty
  transparent square -- but the SPLIT still happens, and the caption lands in whatever is
  left. So the caption's position is the readable evidence that the glyph slot changed
  sides. }
procedure TRtlButtonSlotTest.GlyphButtonCaptionMovesToTheOtherSideOfTheIcon;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TGlyphBtnAccess;
  F: TTyIconFont;
  host: TBitmap;
  shot: TBGRABitmap;
  ltrL, ltrR, rtlL, rtlR: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  F := TTyIconFont.Create(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    F.MapGlyph('save', $F0C7);
    B := TGlyphBtnAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.IconFont := F;
    B.GlyphName := 'save';
    B.Caption := 'Save';
    B.GlyphSize := 16;
    B.GlyphLayout := glLeft;

    host := NewHost(160, 26);
    try
      B.RenderTo(host.Canvas, Rect(0, 0, 160, 26), 96);
      shot := TBGRABitmap.Create(host);
      try
        ChannelSpanX(shot, chGreen, ltrL, ltrR);
      finally
        shot.Free;
      end;
    finally
      host.Free;
    end;

    B.BiDiMode := bdRightToLeft;
    host := NewHost(160, 26);
    try
      B.RenderTo(host.Canvas, Rect(0, 0, 160, 26), 96);
      shot := TBGRABitmap.Create(host);
      try
        ChannelSpanX(shot, chGreen, rtlL, rtlR);
      finally
        shot.Free;
      end;
    finally
      host.Free;
    end;

    AssertTrue('the caption drew both ways', (ltrL >= 0) and (rtlL >= 0));
    AssertTrue('a glyph-left button puts its caption right of the icon slot', ltrL >= 16);
    AssertTrue('mirrored, the icon slot moves right and the caption follows it left',
      rtlL < ltrL);
    AssertTrue('and the caption now clears the icon slot on the other side',
      rtlR <= 160 - 16);
  finally
    F.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlButtonSlotTest.ColorButtonSwatchMovesToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TColorBtnAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r, capL, capR: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(160, 26);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    B := TColorBtnAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'Colour';
    B.SelectedColor := TyRGBA(255, 0, 0, 255);
    B.BiDiMode := bdRightToLeft;
    B.RenderTo(host.Canvas, Rect(0, 0, 160, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chRed, l, r);
      ChannelSpanX(shot, chGreen, capL, capR);
      AssertTrue('the swatch was drawn', l >= 0);
      AssertTrue('the swatch sits against the RIGHT edge when mirrored', r > 160 - 6);
      AssertTrue('and has vacated the left edge', l > 100);
      { The caption is asserted separately from the swatch on purpose: the swatch rect and
        the caption rect are two expressions, and moving one without the other leaves the
        caption in a rect that starts past the right edge -- which draws NOTHING at all, and
        would pass a test that only ever looked at the swatch. }
      AssertTrue('the caption was drawn', capL >= 0);
      AssertTrue('the caption moved to the swatch''s left', capR < l);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ The badge names a corner, and a corner has a reading-order meaning: bpBottomRight is "the
  trailing corner", which is bottom-LEFT on a mirrored button. Rendered rather than only
  table-tested, because a lookup nobody calls is not a behaviour. }
procedure TRtlButtonSlotTest.BadgeMovesToTheTrailingCornerWhichIsBottomLeftWhenMirrored;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TButtonAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(160, 40);
  try
    Ctl.LoadThemeCss(
      'TyButton { background: #FFFFFF; color: #101010; border-width: 0px; padding: 0px; }' +
      'TyBadge { background: #E01B24; color: #FFFFFF; padding: 0px 4px; }');
    B := TButtonAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := '';
    B.ShowBadge := True;
    B.BadgeValue := 7;
    B.BiDiMode := bdRightToLeft;
    B.RenderTo(host.Canvas, Rect(0, 0, 160, 40), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chRed, l, r);
      AssertTrue('the badge was drawn', l >= 0);
      AssertTrue('the default trailing corner is the LEFT one when mirrored', l < 8);
      AssertTrue('and the badge has vacated the right corner', r < 80);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ ---------------------------------------------------------- TRtlExclusionTest }

{ TTyDropDownButton splits its face into a caption zone and an arrow zone, and decides which
  one was pressed by reading the x of the click back through TyDropArrowHit
  (tyControls.DropButtons.pas:170). That makes it the one control in this batch that is NOT
  safe to mirror in the paint path alone: an arrow drawn on the left while the hit test still
  answers on the right is "drawn right, answers wrong", which this library has already shipped
  three times (TTyShape's bounding box, TTyTreeView.GetNodeAt, the date picker's year field).

  So the arrow stays on the right for now, and this test pins BOTH halves together: whoever
  mirrors it has to move the paint and the hit test in the same commit, because moving either
  one alone turns this red. }
procedure TRtlExclusionTest.DropDownArrowStaysWhereItsHitTestSaysItIs;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TDropBtnAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(160, 26);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
    B := TDropBtnAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 160, 26);
    B.Caption := '';
    B.BiDiMode := bdRightToLeft;
    B.RenderTo(host.Canvas, Rect(0, 0, 160, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the divider and chevron drew', l >= 0);
      AssertTrue('the arrow zone is still painted on the right', l > 80);
    finally
      shot.Free;
    end;
    { And the hit test agrees with the paint, which is the point. }
    AssertTrue('a click near the right edge still opens the drop-down',
      TyDropArrowHit(158, 160, B.ArrowW(96)));
    AssertTrue('and a click near the left edge is still the primary action',
      not TyDropArrowHit(2, 160, B.ArrowW(96)));
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ TTyButtonGroup maps a click's raw x straight onto a segment index (TySegmentAt, called
  from MouseDown and MouseMove). Reversing the segments in the paint alone would select the
  segment at the mirror-image position of the one under the pointer -- the same defect as
  above, and worse for being silent on a control whose whole purpose is choosing. Excluded
  for now; pinned here so the exclusion is a decision rather than an oversight. }
procedure TRtlExclusionTest.ButtonGroupSegmentsAreNotMirroredWhileSegmentAtReadsRawX;
var
  Form: TForm;
  G: TTyButtonGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := TTyButtonGroup.Create(Form);
    G.Parent := Form;
    G.SetBounds(0, 0, 200, 26);
    G.Items.Add('One');
    G.Items.Add('Two');
    G.BiDiMode := bdRightToLeft;
    AssertEquals('the leftmost pixels still belong to segment 0',
      0, TySegmentAt(4, 200, 2));
    AssertEquals('and the rightmost to segment 1',
      1, TySegmentAt(196, 200, 2));
  finally
    Form.Free;
  end;
end;

initialization
  RegisterTest(TRtlPainterTest);
  RegisterTest(TRtlCaptionTest);
  RegisterTest(TRtlIndicatorTest);
  RegisterTest(TRtlGeometryTest);
  RegisterTest(TRtlGroupTest);
  RegisterTest(TRtlButtonSlotTest);
  RegisterTest(TRtlExclusionTest);
end.
