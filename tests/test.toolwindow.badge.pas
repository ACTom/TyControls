unit test.toolwindow.badge;
{$mode objfpc}{$H+}

{ 工具窗口的角标(spec §8.1,E 期):属性与 BadgeDisplay、侧栏图标上的角标、底栏标签后面的胶囊、
  溢出菜单。夹具在 test.toolwindow.bottom(底栏)—— 侧栏的用例用同一个夹具里的 FBar(默认左栏)。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, Menus, LCLType, LCLProc, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout, tyControls.StrConsts, tyControls.Painter, tyControls.Badge,
  tyControls.Icons.Lucide, test.toolwindow.window,
  test.toolwindow.bar, test.toolwindow.bottom;

type
  TTyToolWindowBadgeTests = class(TTyToolWindowBottomFixture)
  private
    { 侧栏用例:Explorer / Search / Git,当前页 Explorer。 }
    FSide: array of TProbeWindow;
    { OnBadgeDisplay 的行为开关和调用次数。 }
    FBadgeMode: Integer;
    FBadgeCalls: Integer;
    procedure HandleBadge(Sender: TObject; AValue: Integer; var AText: string;
      var AVisible: Boolean);
    procedure NewSideBar;
    { 按 ABar 的尺寸画出第 AIndex 格(栏坐标),调用方释放。 }
    function RenderCell(ABar: TBarAccess; AIndex: Integer): TBitmap;
    { 位图里颜色恰好是 AColor 的像素的外接框;没有时为空矩形。 }
    function SpanOf(ABmp: TBitmap; AColor: TColor): TRect;
  published
    { --- Task 5:属性、BadgeDisplay、侧栏图标上的角标 --- }
    procedure TestBadgeDisplayFollowsTheButtonRules;
    procedure TestTheEventIsNotAskedWhenTheBadgeIsOff;
    procedure TestTheBadgePropertiesStreamAndDefaultsStayOut;
    procedure TestTheStripBadgeSitsTopRightOfItsOwnCell;
    procedure TestTheStripBadgeMirrorsRightToLeft;
    procedure TestTheBadgeSizeFollowsTheTextAndTheDot;
    procedure TestTheBadgeIsPaintedOverTheIndicator;
    procedure TestACollapsedBarStillPaintsTheBadge;
    procedure TestChangingTheBadgeRepaintsTheBar;
    procedure TestTheBadgeTravelsWithItsWindow;
    procedure TestADisabledWindowKeepsItsBadgeColour;
    { --- Task 6:底栏标签的角标、溢出菜单(spec §7.3 / §8.1) --- }
    procedure TestABadgeWidensItsTabByTheGapAndThePill;
    procedure TestTheTabWidthCacheKeysOnTheBadge;
    procedure TestTheTabWidthCacheKeysOnTheEventsAnswer;
    procedure TestThePillFollowsTheCaption;
    procedure TestThePillLeadsTheCaptionRightToLeft;
    procedure TestATruncatedActiveTabKeepsItsPill;
    procedure TestABadgeOnAnotherPageRepaintsTheActivePage;
    procedure TestAWiderTabMovesTheActionsAndTheOverflow;
    procedure TestTheOverflowMenuCarriesTheBadge;
    procedure TestTheTabHintCarriesNoNumber;
  private
    { 一条底栏:Problems / Output / Terminal,当前页 Output;标签行钉色 + 角标哨兵。 }
    procedure NewBadgeBottomBar;
    { 测试这边照同一套公开函数现算的胶囊宽(数字模式),按 96 PPI。 }
    function ExpectedPillWidth(const AText: string): Integer;
    function TabWidth(AIndex: Integer): Integer;
    { ARect 里落在「品红底上盖一层 AInk」那条混合线上的像素的外接框(算法同 CountIn)。 }
    function InkSpan(ABmp: TBitmap; const ARect: TRect; AInk: TColor): TRect;
  end;

implementation

const
  { #FF7F00 (TColor 是 $BBGGRR):角标底色的哨兵。 }
  BadgeInk = TColor($007FFF);
  BadgeTheme = ' :root { --toolwindow-badge-bg: #FF7F00; }';

type
  { 流式化的根(同 test.toolwindow.window 的 TToolWindowHostForm,那一个在实现段里拿不到)。 }
  TBadgeHostForm = class(TForm)
  end;

procedure TTyToolWindowBadgeTests.HandleBadge(Sender: TObject; AValue: Integer;
  var AText: string; var AVisible: Boolean);
begin
  Inc(FBadgeCalls);
  case FBadgeMode of
    1: AVisible := False;
    2: AText := '';
    3: AText := 'new';
    4: AText := 'x';
    5: AText := 'many';
  end;
end;

procedure TTyToolWindowBadgeTests.NewSideBar;
const
  Names: array[0..2] of string = ('Explorer', 'Search', 'Git');
var
  i: Integer;
begin
  FCtl.StyleOverride := StripTheme + BadgeTheme;
  FSide := nil;
  SetLength(FSide, 3);
  for i := 0 to 2 do
  begin
    FSide[i] := NewWindow;
    FSide[i].Caption := Names[i];
  end;
  FBar.ActiveWindow := FSide[0];
end;

function TTyToolWindowBadgeTests.RenderCell(ABar: TBarAccess; AIndex: Integer): TBitmap;
var
  cell: TRect;
begin
  cell := ABar.StripItemRect(AIndex);
  AssertTrue(Format('前提:第 %d 格排上了图标条', [AIndex]),
    (cell.Right > cell.Left) and (cell.Bottom > cell.Top));
  Result := RenderRegion(ABar, ABar.ClientWidth, ABar.ClientHeight, cell, Wipe);
end;

function TTyToolWindowBadgeTests.SpanOf(ABmp: TBitmap; AColor: TColor): TRect;
var
  re: TBGRABitmap;
  k, px: TBGRAPixel;
  x, y: Integer;
  any: Boolean;
begin
  Result := Rect(0, 0, 0, 0);
  any := False;
  k := ColorToBGRA(ColorToRGB(AColor));
  re := TBGRABitmap.Create(ABmp);
  try
    for y := 0 to re.Height - 1 do
      for x := 0 to re.Width - 1 do
      begin
        px := re.GetPixel(x, y);
        if (px.red <> k.red) or (px.green <> k.green) or (px.blue <> k.blue) then Continue;
        if not any then
        begin
          Result := Rect(x, y, x + 1, y + 1);
          any := True;
        end
        else
        begin
          if x < Result.Left then Result.Left := x;
          if y < Result.Top then Result.Top := y;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
      end;
  finally
    re.Free;
  end;
end;

{ --- Task 5 --------------------------------------------------------------------- }

procedure TTyToolWindowBadgeTests.TestBadgeDisplayFollowsTheButtonRules;
var
  w: TProbeWindow;
  txt: string;
  dot: Boolean;

  procedure Check(const ATag: string; AWant: Boolean; const AText: string; ADot: Boolean);
  var
    got: Boolean;
  begin
    got := w.BadgeDisplay(txt, dot);
    AssertEquals(ATag + ':画不画', AWant, got);
    if AWant then
    begin
      AssertEquals(ATag + ':文字', AText, txt);
      AssertEquals(ATag + ':圆点', ADot, dot);
    end;
  end;

begin
  w := TProbeWindow.Create(FForm);
  Check('默认', False, '', False);
  w.ShowBadge := True;
  Check('开着就显示 0(照 TTyButton)', True, '0', False);
  w.BadgeValue := 5;
  Check('5', True, '5', False);
  w.BadgeValue := 99;
  Check('99', True, '99', False);
  w.BadgeValue := 100;
  Check('> 99', True, rsBadgeOverflow, False);
  w.BadgeValue := -3;
  Check('负数照原样', True, '-3', False);
  w.BadgeValue := 7;
  w.BadgeDot := True;
  Check('圆点', True, '', True);
  w.BadgeDot := False;
  w.OnBadgeDisplay := @HandleBadge;
  FBadgeMode := 1;
  Check('事件藏起来', False, '', False);
  FBadgeMode := 2;
  Check('事件把文字清空(数字模式)', False, '', False);
  FBadgeMode := 3;
  Check('事件改文字', True, 'new', False);
  w.BadgeDot := True;
  FBadgeMode := 4;
  Check('圆点模式不用文字', True, '', True);
end;

procedure TTyToolWindowBadgeTests.TestTheEventIsNotAskedWhenTheBadgeIsOff;
var
  w: TProbeWindow;
  txt: string;
  dot: Boolean;
begin
  w := TProbeWindow.Create(FForm);
  w.OnBadgeDisplay := @HandleBadge;
  FBadgeCalls := 0;
  AssertFalse('不开 ShowBadge:不画', w.BadgeDisplay(txt, dot));
  AssertEquals('事件没被调', 0, FBadgeCalls);
  w.ShowBadge := True;
  AssertTrue('开了:画', w.BadgeDisplay(txt, dot));
  AssertTrue('事件被调过(次数不钉:它会被频繁调用)', FBadgeCalls >= 1);
end;

procedure TTyToolWindowBadgeTests.TestTheBadgePropertiesStreamAndDefaultsStayOut;
var
  src, dst: TForm;
  ms: TMemoryStream;
  txt: TStringStream;
  bar, dbar: TTyToolWindowBar;
  w: TTyToolWindow;
  text: string;
begin
  w := TTyToolWindow.Create(nil);
  try
    AssertEquals('ShowBadge 的 default 等于构造值', Ord(w.ShowBadge),
      GetPropInfo(w, 'ShowBadge')^.Default);
    AssertEquals('BadgeValue 的 default 等于构造值', w.BadgeValue,
      GetPropInfo(w, 'BadgeValue')^.Default);
    AssertEquals('BadgeDot 的 default 等于构造值', Ord(w.BadgeDot),
      GetPropInfo(w, 'BadgeDot')^.Default);
  finally
    w.Free;
  end;
  src := TBadgeHostForm.CreateNew(nil);
  src.Name := 'HostForm1';
  dst := TBadgeHostForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    bar := TTyToolWindowBar.Create(src);
    bar.Name := 'Bar';
    bar.Parent := src;
    w := TTyToolWindow.Create(src);
    w.Name := 'W1';
    w.Parent := bar;
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    text := txt.DataString;
    AssertEquals('默认值不写:ShowBadge', 0, Pos('ShowBadge', text));
    AssertEquals('默认值不写:BadgeValue', 0, Pos('BadgeValue', text));
    AssertEquals('默认值不写:BadgeDot', 0, Pos('BadgeDot', text));
    w.ShowBadge := True;
    w.BadgeValue := 150;
    w.BadgeDot := True;
    ms.Clear;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    dbar := dst.FindComponent('Bar') as TTyToolWindowBar;
    AssertTrue('ShowBadge 读回', dbar.Windows[0].ShowBadge);
    AssertEquals('BadgeValue 读回', 150, dbar.Windows[0].BadgeValue);
    AssertTrue('BadgeDot 读回', dbar.Windows[0].BadgeDot);
  finally
    txt.Free;
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestTheStripBadgeSitsTopRightOfItsOwnCell;
var
  bmp: TBitmap;
  h: Integer;
begin
  NewSideBar;
  FSide[1].ShowBadge := True;
  FSide[1].BadgeValue := 5;
  bmp := RenderCell(FBar, 1);
  try
    h := bmp.Width div 2;
    AssertTrue('Search 格右上四分之一里有角标', ExactIn(bmp, Rect(h, 0, bmp.Width, bmp.Height div 2), BadgeInk) > 0);
    AssertEquals('左下四分之一里没有', 0, ExactIn(bmp, Rect(0, bmp.Height div 2, h, bmp.Height), BadgeInk));
    AssertEquals('左上四分之一里也没有(LTR)', 0, ExactIn(bmp, Rect(0, 0, h, bmp.Height div 2), BadgeInk));
  finally
    bmp.Free;
  end;
  bmp := RenderCell(FBar, 0);
  try
    AssertEquals('Explorer 格里没有(画到别的格就红)', 0, ExactIn(bmp, Rect(0, 0, bmp.Width, bmp.Height), BadgeInk));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestTheStripBadgeMirrorsRightToLeft;
var
  bmp: TBitmap;
  h: Integer;
begin
  NewSideBar;
  FSide[1].ShowBadge := True;
  FSide[1].BadgeValue := 5;
  FBar.BiDiMode := bdRightToLeft;
  AssertTrue('前提:栏从右往左', FBar.IsRightToLeft);
  bmp := RenderCell(FBar, 1);
  try
    h := bmp.Width div 2;
    AssertTrue('RTL:角标在左上', ExactIn(bmp, Rect(0, 0, h, bmp.Height div 2), BadgeInk) > 0);
    AssertEquals('RTL:右上没有', 0, ExactIn(bmp, Rect(h, 0, bmp.Width, bmp.Height div 2), BadgeInk));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestTheBadgeSizeFollowsTheTextAndTheDot;
var
  bmp: TBitmap;
  small, wide, dot: TRect;
  d: Integer;
begin
  NewSideBar;
  FSide[1].ShowBadge := True;
  FSide[1].BadgeValue := 5;
  bmp := RenderCell(FBar, 1);
  try
    small := SpanOf(bmp, BadgeInk);
  finally
    bmp.Free;
  end;
  FSide[1].BadgeValue := 150;
  bmp := RenderCell(FBar, 1);
  try
    wide := SpanOf(bmp, BadgeInk);
  finally
    bmp.Free;
  end;
  AssertTrue('99+ 的胶囊比 5 的宽', wide.Right - wide.Left > small.Right - small.Left);
  FSide[1].BadgeDot := True;
  bmp := RenderCell(FBar, 1);
  try
    dot := SpanOf(bmp, BadgeInk);
  finally
    bmp.Free;
  end;
  d := MulDiv(FCtl.Metric(TyBadgeDotSizeVar, TyBadgeDotSize), 96, 96);
  AssertTrue(Format('圆点横向约等于 --badge-dot-size(%d,量到 %d)', [d, dot.Right - dot.Left]),
    Abs((dot.Right - dot.Left) - d) <= 2);
  AssertTrue(Format('圆点纵向约等于 --badge-dot-size(%d,量到 %d)', [d, dot.Bottom - dot.Top]),
    Abs((dot.Bottom - dot.Top) - d) <= 2);
end;

procedure TTyToolWindowBadgeTests.TestTheBadgeIsPaintedOverTheIndicator;
var
  bmp: TBitmap;
begin
  NewSideBar;
  { 指示条(黑)调粗到压进角标所在的右上角。 }
  FCtl.StyleOverride := StripTheme + BadgeTheme + ' :root { --toolwindow-strip-indicator-size: 30px; }';
  FSide[0].ShowBadge := True;
  FSide[0].BadgeValue := 5;
  bmp := RenderCell(FBar, 0);
  try
    AssertTrue('前提:指示条画了', ExactIn(bmp, Rect(0, 0, bmp.Width, bmp.Height), clBlack) > 0);
    AssertTrue('当前页的格里,角标盖在指示条上面',
      ExactIn(bmp, Rect(bmp.Width div 2, 0, bmp.Width, bmp.Height div 2), BadgeInk) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestACollapsedBarStillPaintsTheBadge;
var
  bmp: TBitmap;
begin
  NewSideBar;
  FSide[1].ShowBadge := True;
  FSide[1].BadgeValue := 5;
  FBar.Collapsed := True;
  bmp := RenderCell(FBar, 1);
  try
    AssertTrue('收起的栏照画角标', ExactIn(bmp, Rect(0, 0, bmp.Width, bmp.Height), BadgeInk) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestChangingTheBadgeRepaintsTheBar;
var
  inv: Integer;
  b: TBarAccess;
  w: TProbeWindow;
begin
  NewSideBar;
  inv := FBar.Invalidates;
  FSide[1].ShowBadge := True;
  AssertTrue('ShowBadge:重画', FBar.Invalidates > inv);
  inv := FBar.Invalidates;
  FSide[1].BadgeValue := 6;
  AssertTrue('BadgeValue:重画', FBar.Invalidates > inv);
  inv := FBar.Invalidates;
  FSide[1].BadgeDot := True;
  AssertTrue('BadgeDot:重画', FBar.Invalidates > inv);
  b := NewDesignBar;
  w := NewWindowIn(b, FDesignOwner);
  inv := b.Invalidates;
  w.ShowBadge := True;
  AssertTrue('设计期:改了立刻看得到', b.Invalidates > inv);
end;

procedure TTyToolWindowBadgeTests.TestTheBadgeTravelsWithItsWindow;
var
  rb: TBarAccess;
  bmp: TBitmap;
begin
  NewSideBar;
  FSide[1].ShowBadge := True;
  FSide[1].BadgeValue := 5;
  rb := TBarAccess.Create(FForm);
  rb.Parent := FForm;
  rb.Controller := FCtl;
  rb.Font.PixelsPerInch := 96;
  rb.Placement := twpRight;
  rb.Height := 400;
  { 运行时同类栏之间直接改 Parent:跟 MoveWindow 同一条路(spec §3.2)。 }
  FSide[1].Parent := rb;
  AssertSame('前提:Search 到了右栏', rb, FSide[1].Bar);
  bmp := RenderCell(rb, 0);
  try
    AssertTrue('右栏的 Search 格里有角标', ExactIn(bmp, Rect(0, 0, bmp.Width, bmp.Height), BadgeInk) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestADisabledWindowKeepsItsBadgeColour;
var
  bmp: TBitmap;
begin
  NewSideBar;
  FSide[1].ShowBadge := True;
  FSide[1].BadgeValue := 5;
  FSide[1].Enabled := False;
  bmp := RenderCell(FBar, 1);
  try
    AssertTrue('禁用窗口的角标照常颜色(不跟着 :disabled)',
      ExactIn(bmp, Rect(0, 0, bmp.Width, bmp.Height), BadgeInk) > 0);
  finally
    bmp.Free;
  end;
end;

{ --- Task 6 --------------------------------------------------------------------- }

procedure TTyToolWindowBadgeTests.NewBadgeBottomBar;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme + BadgeTheme;
end;

function TTyToolWindowBadgeTests.ExpectedPillWidth(const AText: string): Integer;
var
  S: TTyStyleSet;
  fs, tw, th, rw, zw, zh, minPx: Integer;
  sz: TSize;
begin
  S := FCtl.Model.ResolveStyle(TyToolWindowBadgeKey, '', [tysNormal]);
  AssertTrue('前提:角标的字号由主题给', tpFontSize in S.Present);
  fs := S.FontSize;
  TyMeasureTextBlock(AText, S.FontName, fs, S.FontWeight, 96, 0, 0, tw, th);
  rw := TyMeasureRenderedTextWidth(AText, S.FontName, fs, S.FontWeight, 96);
  if rw > tw then tw := rw;
  TyMeasureTextBlock('0', S.FontName, fs, S.FontWeight, 96, 0, 0, zw, zh);
  minPx := FCtl.Metric(TyBadgeMinSizeVar, TyBadgeMinSize);
  sz := TyBadgeSize(tw, zh, S.Padding.Left, S.Padding.Top, minPx, False,
    FCtl.Metric(TyBadgeDotSizeVar, TyBadgeDotSize));
  Result := sz.cx;
end;

function TTyToolWindowBadgeTests.TabWidth(AIndex: Integer): Integer;
var
  r: TRect;
begin
  r := TabRectOf(ActiveGeom, AIndex);
  Result := r.Right - r.Left;
end;

function TTyToolWindowBadgeTests.InkSpan(ABmp: TBitmap; const ARect: TRect;
  AInk: TColor): TRect;
var
  re: TBGRABitmap;
  g, k, px: TBGRAPixel;
  x, y, c, best: Integer;
  gv, kv, pv: array[0..2] of Integer;
  a: Double;
  ok, any: Boolean;
begin
  Result := Rect(0, 0, 0, 0);
  any := False;
  g := ColorToBGRA(ColorToRGB(Ground));
  k := ColorToBGRA(ColorToRGB(AInk));
  gv[0] := g.red; gv[1] := g.green; gv[2] := g.blue;
  kv[0] := k.red; kv[1] := k.green; kv[2] := k.blue;
  best := 0;
  for c := 1 to 2 do
    if Abs(kv[c] - gv[c]) > Abs(kv[best] - gv[best]) then best := c;
  re := TBGRABitmap.Create(ABmp);
  try
    for y := ARect.Top to ARect.Bottom - 1 do
      for x := ARect.Left to ARect.Right - 1 do
      begin
        if (x < 0) or (y < 0) or (x >= re.Width) or (y >= re.Height) then Continue;
        px := re.GetPixel(x, y);
        pv[0] := px.red; pv[1] := px.green; pv[2] := px.blue;
        a := (pv[best] - gv[best]) / (kv[best] - gv[best]);
        if (a <= 0.01) or (a > 1.02) then Continue;
        ok := True;
        for c := 0 to 2 do
          if Abs(gv[c] + a * (kv[c] - gv[c]) - pv[c]) > 3 then ok := False;
        if not ok then Continue;
        if not any then
        begin
          Result := Rect(x, y, x + 1, y + 1);
          any := True;
        end
        else
        begin
          if x < Result.Left then Result.Left := x;
          if y < Result.Top then Result.Top := y;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
      end;
  finally
    re.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestABadgeWidensItsTabByTheGapAndThePill;
var
  w0, w1, w2: Integer;
begin
  NewBadgeBottomBar;
  w0 := TabWidth(0);
  w1 := TabWidth(1);
  w2 := TabWidth(2);
  FWins[0].ShowBadge := True;
  FWins[0].BadgeValue := 3;
  AssertEquals('Problems 宽 = 原宽 + header-gap + 胶囊宽(同一套量法)',
    w0 + FCtl.Metric(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef) + ExpectedPillWidth('3'),
    TabWidth(0));
  AssertEquals('Output 不变', w1, TabWidth(1));
  AssertEquals('Terminal 不变', w2, TabWidth(2));
end;

procedure TTyToolWindowBadgeTests.TestTheTabWidthCacheKeysOnTheBadge;
var
  w3: Integer;
begin
  NewBadgeBottomBar;
  FWins[0].ShowBadge := True;
  FWins[0].BadgeValue := 3;
  w3 := TabWidth(0);
  FWins[0].BadgeValue := 150;
  AssertTrue('只改 BadgeValue(标题不动):标签宽跟着变', TabWidth(0) > w3);
end;

procedure TTyToolWindowBadgeTests.TestTheTabWidthCacheKeysOnTheEventsAnswer;
var
  w3: Integer;
begin
  NewBadgeBottomBar;
  FWins[0].OnBadgeDisplay := @HandleBadge;
  FBadgeMode := 0;
  FWins[0].ShowBadge := True;
  FWins[0].BadgeValue := 3;
  w3 := TabWidth(0);
  FBadgeMode := 5;           { 事件把文字改成 'many',BadgeValue 没动 }
  FWins[0].Invalidate;
  AssertTrue('缓存键记的是事件之后的文字', TabWidth(0) > w3);
end;

procedure TTyToolWindowBadgeTests.TestThePillFollowsTheCaption;
var
  bmp: TBitmap;
  r, pill, ink: TRect;
  w: TProbeWindow;
begin
  NewBadgeBottomBar;
  FWins[0].ShowBadge := True;
  FWins[0].BadgeValue := 3;
  w := FWins[1];
  r := TabRectOf(ActiveGeom, 0);
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    pill := SpanOf(bmp, BadgeInk);
    ink := InkSpan(bmp, r, RestInk);
    AssertTrue('前提:胶囊画了', pill.Right > pill.Left);
    AssertTrue('前提:标题画了', ink.Right > ink.Left);
    AssertTrue('胶囊在 Problems 标签里', (pill.Left >= r.Left) and (pill.Right <= r.Right));
    AssertTrue('LTR:胶囊在标题右边', pill.Left > ink.Right - 1);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestThePillLeadsTheCaptionRightToLeft;
var
  bmp: TBitmap;
  r, pill, ink: TRect;
  w: TProbeWindow;
begin
  NewBadgeBottomBar;
  FWins[0].ShowBadge := True;
  FWins[0].BadgeValue := 3;
  w := FWins[1];
  w.BiDiMode := bdRightToLeft;
  AssertTrue('前提:当前页从右往左', w.IsRightToLeft);
  r := TabRectOf(ActiveGeom, 0);
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    pill := SpanOf(bmp, BadgeInk);
    ink := InkSpan(bmp, r, RestInk);
    AssertTrue('前提:胶囊画了', pill.Right > pill.Left);
    AssertTrue('前提:标题画了', ink.Right > ink.Left);
    AssertTrue('RTL:胶囊在标题左边', pill.Right < ink.Left + 1);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestATruncatedActiveTabKeepsItsPill;
var
  bmp: TBitmap;
  wide, r: TRect;
  w: TProbeWindow;
begin
  NewBadgeBottomBar;
  FWins[1].ShowBadge := True;
  FWins[1].BadgeValue := 7;
  wide := TabRectOf(ActiveGeom, 1);
  FBar.Width := 130;
  Relayout;
  w := FWins[1];
  r := TabRectOf(ActiveGeom, 1);
  AssertTrue('前提:当前页的标签被截了', r.Right - r.Left < wide.Right - wide.Left);
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertTrue('截标题,胶囊保留', ExactIn(bmp, r, BadgeInk) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBadgeTests.TestABadgeOnAnotherPageRepaintsTheActivePage;
begin
  NewBadgeBottomBar;
  FWins[0].ShowBadge := True;
  FWins[0].BadgeValue := 3;
  ArmActive(FWins[1]);
  FWins[0].BadgeValue := 4;
  AssertTrue('别的页的角标变了:当前页的标签行要重渲染',
    FWins[1].CacheWouldRender(FWins[1].ClientWidth, FWins[1].ClientHeight));
end;

procedure TTyToolWindowBadgeTests.TestAWiderTabMovesTheActionsAndTheOverflow;
var
  wdt, i: Integer;
  hidden: TTyToolWindowPlan;
  found: Boolean;
begin
  NewBadgeBottomBar;
  AddActionsKid(FWins[1], 30, 20);
  Relayout;
  { 找到「刚好放得下全部标签」的宽:再窄一个像素就有溢出。 }
  wdt := 600;
  repeat
    Dec(wdt);
    FBar.Width := wdt;
    Relayout;
  until (Length(FBar.OverflowWindows) > 0) or (wdt < 150);
  AssertTrue('前提:窄到出现溢出', Length(FBar.OverflowWindows) > 0);
  FBar.Width := wdt + 1;
  Relayout;
  AssertEquals('前提:宽一个像素就全放得下', 0, Length(FBar.OverflowWindows));
  FWins[1].AlignCount := 0;
  FWins[0].ShowBadge := True;
  FWins[0].BadgeValue := 150;
  hidden := FBar.OverflowWindows;
  found := False;
  for i := 0 to High(hidden) do
    if hidden[i] = 2 then found := True;
  AssertTrue('Problems 变宽:Terminal 挤进溢出', found);
  AssertFalse('溢出按钮出现', IsRectEmpty(ActiveGeom.Overflow));
  AssertTrue('当前页被请了重排(操作区跟上,不是只重画)', FWins[1].AlignCount > 0);
end;

procedure TTyToolWindowBadgeTests.TestTheOverflowMenuCarriesTheBadge;
var
  i: Integer;
  hidden: TTyToolWindowPlan;
  found: Boolean;

  function TerminalCaption: string;
  var
    k: Integer;
  begin
    Result := '<missing>';
    ClickAt(FWins[1], ActiveGeom.Overflow.CenterPoint);
    AssertNotNull('前提:建了菜单', FBar.OverflowMenu);
    for k := 0 to FBar.OverflowMenu.Items.Count - 1 do
      if FBar.OverflowMenu.Items[k].Tag = PtrInt(FWins[2]) then
        Result := FBar.OverflowMenu.Items[k].Caption;
  end;

begin
  NewBadgeBottomBar;
  FWins[2].ShowBadge := True;
  FWins[2].BadgeValue := 7;
  FBar.Width := 160;
  Relayout;
  hidden := FBar.OverflowWindows;
  found := False;
  for i := 0 to High(hidden) do
    if hidden[i] = 2 then found := True;
  AssertTrue('前提:Terminal 收进了溢出', found);
  AssertEquals('数字', 'Terminal (7)', TerminalCaption);
  FWins[2].BadgeDot := True;
  AssertEquals('圆点', 'Terminal ' + #$E2#$80#$A2, TerminalCaption);
  FWins[2].ShowBadge := False;
  AssertEquals('不显示角标', 'Terminal', TerminalCaption);
end;

procedure TTyToolWindowBadgeTests.TestTheTabHintCarriesNoNumber;
var
  txt: string;
  r: TRect;
begin
  NewBadgeBottomBar;
  FWins[0].ShowBadge := True;
  FWins[0].BadgeValue := 3;
  AssertTrue('标签上有提示', FBar.HeaderHint(FWins[1], TabCentre(0).X, TabCentre(0).Y, txt, r));
  AssertEquals('提示不带数字(仍是 StripHint / Caption)', 'Problems', txt);
end;

initialization
  RegisterClass(TBadgeHostForm);
  RegisterTest(TTyToolWindowBadgeTests);
end.
