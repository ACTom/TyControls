# TTyImageView 实施计划(Phase 9)

> 路线图:`docs/superpowers/specs/2026-07-05-controls-expansion-roadmap.md` Phase 9 ——
> "Image viewer with pan/zoom + basic effect filters (blur/tint/grayscale) via BGRA"。
> 用户决定 v1 **一并**包含平滑缩放/平移动画。承接刚做完的文件对话框图片预览。
> **零新增主题 token**;全程 BGRA(跨平台);无原生控件。

## 交付物

| # | 产物 |
|---|---|
| 1 | `source/tyControls.ImageView.pas` —— `TTyImageView = class(TTyCustomControl)` + 纯几何/滤镜函数 |
| 2 | `tests/test.imageview.pas` —— 无头:纯几何函数 + 滤镜像素 + 动画插值(TTyAnimator 无时钟可测) |
| 3 | 集成:`tycontrols.lpk`、`tytests.lpr`、`designtime/tyControls.Design.pas`(注册进 **TyControls Containers**)、调色板图标(141→142) |
| 4 | `docs/controls/imageview.md` + README 索引;`examples/imageview` demo(用 TTyOpenPictureDialog 选图打开) |

## 基础(复用,勿改)

- `source/tyControls.Image.pas`:`TyImageFitRect(srcW,srcH,dstW,dstH,stretch,proportional,center): TRect`(contain-fit 数学);TTyImage 经 `TBitmap` 桥接 BGRA(BGRA 3.2.2 无 `Create(TGraphic)`)。
- `source/tyControls.Animation.pas`:`TTyAnimator`(record,`TyAnimatorInit(durMs,easing)`,`Advance(ms):Boolean`,`.Eased:Single`,`.Running`);`TyLerpF(a,b,t)`/`TyLerpI`。**无时钟**——`Advance(ms)` 显式推进,可无头测。消费者用惰性 `TTimer` 驱动(仅动画时),照 `tyControls.ExPanel`(FTimer/EnsureTimer/HandleTimer/StartHeightAnimation)。
- BGRA 滤镜:`TBGRABitmap.FilterGrayscale`、`FilterBlurRadial(radius, rbFast/rbNormal)`、`FilterSharpen`、`.Negative`(反相);tint 用半透明色 `FillRect(dmDrawWithTransparency)` 或按 amount 混合。这些返回**新 bitmap**(非原地)——注意释放。

## 契约

`TTyImageView = class(TTyCustomControl)` —— 图片查看器:加载图片,平移/缩放(平滑动画),非破坏性 BGRA 滤镜。
`GetStyleTypeKey := 'TyPanel'`(信箱区用主题表面色,零新 token)。

### 状态

```pascal
private
  FSource:    TBGRABitmap;   { owned;原始解码图 }
  FProcessed: TBGRABitmap;   { owned;滤镜产出(FProcDirty 时按 FSource 重算);绘制用它 }
  FProcDirty: Boolean;
  { view }
  FZoom:      Double;        { 当前显示缩放(动画时=插值中间值)}
  FAutoFit:   Boolean;       { True:加载/resize 时 ZoomToFit;用户缩放/平移后置 False }
  FZoomMin, FZoomMax: Double;
  FOffX, FOffY: Double;      { 平移(图像坐标像素,已夹取)}
  { smooth animation }
  FAnim:      TTyAnimator;
  FFromZoom, FToZoom: Double;
  FFromOffX, FFromOffY, FToOffX, FToOffY: Double;
  FTimer:     TTimer;        { 惰性,仅动画时 }
  FAnimMs:    Integer;       { 时长,默认 180 }
  { filters }
  FGrayscale: Boolean;
  FBlurRadius: Integer;      { 0=关 }
  FSharpen:   Boolean;
  FInvert:    Boolean;
  FTintColor: TColor;
  FTintAmount: Integer;      { 0..100,0=关 }
```

### 纯函数(**唯一可无头测的几何**,导出到接口)

```pascal
{ 把 src 完整装进 view 的缩放(contain);src 或 view 退化(<=0)-> 1.0 }
function TyImageViewFitZoom(ASrcW, ASrcH, AViewW, AViewH: Integer): Double;
{ 夹取到 [lo,hi] }
function TyImageViewClamp(AValue, ALo, AHi: Double): Double;
{ 图像以 AZoom、平移 (AOffX,AOffY) 在 view 里绘制的设备矩形(居中 + 平移)}
function TyImageViewDestRect(ASrcW, ASrcH, AViewW, AViewH: Integer;
  AZoom, AOffX, AOffY: Double): TRect;
{ 缩放时保持锚点(光标)在 view 里的图像像素不动 -> 新平移。返回经 out 参数 }
procedure TyImageViewAnchorOffset(AOldZoom, ANewZoom: Double;
  AAnchorX, AAnchorY, AViewW, AViewH: Integer;
  AOldOffX, AOldOffY: Double; out ANewOffX, ANewOffY: Double);
{ 平移夹取:图像小于视口 -> 居中(off=0);大于 -> 不露出超过一半的空白(off 限制在 ±(scaled-view)/2)}
procedure TyImageViewClampOffset(ASrcW, ASrcH, AViewW, AViewH: Integer;
  AZoom: Double; var AOffX, AOffY: Double);
```
这些逐条钉死在测试里(退化尺寸、居中、锚点缩放前后光标图像坐标一致、夹取边界)。

### 滤镜(非破坏性,导出一个纯函数便于测)

```pascal
{ 按各滤镜开关产出一张新 bitmap(caller-owned)。ASource 不变。顺序:grayscale -> blur ->
  sharpen -> invert -> tint。全关 -> 返回 ASource 的副本。}
function TyImageViewApplyFilters(ASource: TBGRABitmap; AGrayscale: Boolean;
  ABlurRadius: Integer; ASharpen, AInvert: Boolean;
  ATintColor: TColor; ATintAmount: Integer): TBGRABitmap;
```
测试:小图应用灰度后每像素 `r=g=b`;反相后 `r'=255-r`;tint amount=100 全覆盖成 tint 色;全关=像素等同源。控件里 `FProcessed` 由它按 `FProcDirty` 重算。

### 公开 API

```pascal
public
  procedure LoadFromFile(const APath: string);   { BGRA 解码;失败清空不崩 }
  procedure Clear;
  procedure ZoomToFit;                            { AutoFit:=True;动画到 fit }
  procedure ZoomToActual;                         { 100%;动画;AutoFit:=False }
  procedure ZoomIn; procedure ZoomOut;            { ×/÷ 1.25,以视口中心为锚,动画 }
  procedure ZoomAt(AFactor: Double; AX, AY: Integer);  { 以 (AX,AY) 为锚缩放,动画 }
  property  Zoom: Double read FZoom;              { 只读;当前(可能动画中)缩放 }
published
  property Picture: TPicture write SetPicture;    { 赋值 -> 转 BGRA 源;读用 LoadFromFile/内部 }
  property AutoFit: Boolean read FAutoFit write SetAutoFit default True;
  property ZoomMin: Double ...; property ZoomMax: Double ...;   { 默认 0.05 / 20 }
  property AnimationDuration: Integer read FAnimMs write FAnimMs default 180;
  property Grayscale: Boolean ...; property BlurRadius: Integer ...;
  property Sharpen: Boolean ...; property Invert: Boolean ...;
  property TintColor: TColor ...; property TintAmount: Integer ...;   { setter 置 FProcDirty + Invalidate }
  property OnZoomChange: TNotifyEvent ...;
  property Align; property Anchors; property Visible; property Enabled;
  property StyleClass; property Controller;
```

### 交互(真机验;几何走纯函数)

- 滚轮:`ZoomAt(1.15^delta, cursor)`(以光标为锚,平滑动画)。
- 拖拽(ssLeft + 已放大到可平移):平移 `FOffX/Y`,经 `TyImageViewClampOffset` 夹取,`AutoFit:=False`,即时(拖拽不动画)。
- 双击:在 fit ↔ 100% 间切换(动画)。
- resize:`AutoFit` 时重算 fit zoom(不动画,跟随窗口)。

### 平滑动画(照 ExPanel)

- 缩放/平移的目标变化 -> `FFromZoom:=FZoom; FToZoom:=target; FFrom/ToOff...; FAnim := TyAnimatorInit(FAnimMs, teEaseOutCubic); EnsureTimer`。
- `HandleTimer`:`FAnim.Advance(dt)`;`t := FAnim.Eased`;`FZoom := TyLerpF(FFromZoom,FToZoom,t)`;`FOffX := TyLerpF(...)`;`Invalidate`;`OnZoomChange`;`FAnim.Running=False` 时停 timer。
- 拖拽平移**不**动画(即时跟手)。

### 绘制

- `RenderTo`:填主题表面(信箱底);`if FProcDirty then 重算 FProcessed`;`dst := TyImageViewDestRect(...)`;`P.Bitmap.StretchPutImage(dst, FProcessed, dmDrawWithTransparency)`(dst=源尺寸时用 PutImage)。裁剪到控件矩形。

## 无头测试要点

- 纯几何 5 个函数逐条(退化、居中、锚点缩放不变、夹取边界、fit 计算)。
- `TyImageViewApplyFilters` 像素断言(灰度/反相/tint/全关)。
- 动画插值:`TyAnimatorInit` + 手动 `Advance(半程)` -> `TyLerpF(from,to,eased)` 在 (from,to) 之间且单调;`Advance` 到时长后 `Running=False` 且值=to。
- 控件的鼠标/timer/绘制**不建窗口测**(窗口化撞 win32 基线)——真机 `examples/imageview`。

## 对抗式审查清单

1. **几何正确**:锚点缩放真的让光标下的图像像素不动(缩放前后 unproject 一致);fit 居中;夹取不把图像弄丢。
2. **生命周期**:`FSource`/`FProcessed` owned + 释放;`TyImageViewApplyFilters` 中间 bitmap 全释放(BGRA 滤镜返回新图);`FTimer` 惰性建、析构释放;重复 LoadFromFile 不泄漏旧源。
3. **非破坏性**:滤镜改设置只重算 `FProcessed`,`FSource` 不变;关掉所有滤镜像素回到源。
4. **动画**:拖拽平移不进动画;缩放动画结束停 timer;`FZoom` 只读对外(动画中是插值)。
5. **零新 token**:`GetStyleTypeKey='TyPanel'`,无新 .tycss;受保护文件零改。

## 验收

- 全量测试 0 失败(基线 2820 + 新增)。
- 零新 token;受保护文件零改;调色板漂移守卫过(142 类)。
- `examples/imageview` 双击可跑;真机验平移/缩放/滚轮/双击/平滑动画/滤镜。
- 过 [[pre-merge-checklist]](合并回 main 时统一 i18n / README 中英)。
