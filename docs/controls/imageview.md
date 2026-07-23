# TTyImageView

## 概述

`TTyImageView` 是一个图片查看器控件:加载图片,**平移 / 缩放(平滑动画)**,以及非破坏性的 **BGRA 滤镜**
(灰度 / 模糊 / 锐化 / 反相 / 着色)。全程 BGRA,跨平台;信箱区(letterbox 衬底)用 `TyImageView` 这个**自有主题键**着色
(见下文《主题与 typeKey》)。承接文件对话框的图片预览 —— 用它做全功能的查看面板。

## 用法

```pascal
uses tyControls.ImageView, tyControls.Dialogs.FileDialog;

View := TTyImageView.Create(Self);
View.Parent := Panel1;
View.Align := alClient;

var fn: string;
if TyOpenPictureDialog(fn) then
  View.LoadFromFile(fn);        // 加载后自动适配窗口(AutoFit 默认 True)

View.Grayscale := True;          // 非破坏性滤镜:源图不变,重算显示
View.ZoomToActual;               // 平滑动画到 100%
```

## 属性 / 方法 / 事件

| 成员 | 说明 |
|---|---|
| `LoadFromFile(path)` / `Picture := pic` / `Clear` | 加载(BGRA 解码,失败清空不崩)/ 赋图 / 清空。 |
| `Zoom: Double`(只读) | 当前缩放(动画时是插值中间值)。 |
| `ZoomToFit` / `ZoomToActual` | 适配窗口 / 100%(都平滑动画)。 |
| `ZoomIn` / `ZoomOut` / `ZoomAt(factor, x, y)` | 放大/缩小(以视口中心为锚)/ 以 (x,y) 为锚缩放。 |
| `AutoFit: Boolean` | 加载/窗口变化时自动适配。默认 True;用户一缩放/平移就关掉。 |
| `ZoomMin` / `ZoomMax: Double` | 缩放下/上限。默认 0.05 / 20。 |
| `AnimationDuration: Integer` | 缩放动画时长(ms)。默认 180。 |
| `Grayscale` / `Sharpen` / `Invert: Boolean` | 灰度 / 锐化 / 反相(直接补色 255-x)。 |
| `BlurRadius: Integer` | 模糊半径,0=关。 |
| `TintColor: TColor` + `TintAmount: Integer` | 着色(0..100,100=全覆盖成该色)。 |
| `OnZoomChange` | 缩放变化(含动画每帧)。 |

**交互**:滚轮=以光标为中心缩放;拖拽=平移(放大到可平移时);双击=在适配 ↔ 100% 间切换。

## 关键设计

- **平滑动画**:缩放/平移过渡走 `TTyAnimator` 缓动内核(惰性 `TTimer`,仅动画时;照 `TTyExPanel`)。
  拖拽平移**不**动画(即时跟手)。
- **锚点缩放**:滚轮/`ZoomAt` 保持光标下的图像像素在缩放前后不动(纯函数 `TyImageViewAnchorOffset`)。
- **非破坏性滤镜**:源 `FSource` 永不改;滤镜按 `grayscale → blur → sharpen → invert → tint` 顺序产出缓存
  `FProcessed`(改设置才重算),再缩放平移绘制。全关 = 像素回到源。反相用 BGRA 的 `LinearNegative`(直接补色),
  非 `Negative`(那是伽马感知的摄影负片,反相 10 会得 254 不是 245)。
- **可无头测**:纯几何(fit 缩放 / 显示矩形 / 锚点 / 平移夹取)、滤镜像素、动画插值都抽成纯函数测;
  鼠标/timer/绘制靠真机。

## 主题与 typeKey

| 项目 | 值 |
|---|---|
| `GetStyleTypeKey` 返回值 | `'TyImageView'`(**自有 typeKey**) |
| 该键画什么 | `RenderTo` 用它走 `DrawFrame` 铺满整个控件——就是图片浮在其上的**信箱衬底(mat)**;图片本身随后叠加绘制。 |

它从前返回 `'TyPanel'`,于是 `TyImageView { background: #1e1e1e }` 这句话根本无从说起:看图器的衬底按惯例是近黑或棋盘格(好让照片跳出来),而面板是应用的浅色表面——两者要求相反,却只有一个键。想压暗衬底就只能压暗全应用的面板。现在它有自己的键(与 [`TTyScrollBox`](scrollbox.md) 早前从 `TyPanel` 拆出去的理由同一类)。`TyImageView` 已作为附加选择器并入主题里 `TyPanel` 的规则块,解析值与从前逐字节相同,**开钩子而不动像素**;第三方主题若只覆盖了 `TyPanel`,需要补上 `TyImageView`(主题层按 typeKey 全有全无地回落)。

**子部件 typeKey:没有。** 控件只解析这一个盒子样式;缩放动画、滤镜、平移都不产生额外的可着色部件。

## 消费者 / 关联

文件对话框的图片[预览框](previewbox.md)是轻量只读版;`TTyImageView` 是全功能查看器(缩放/平移/滤镜)。
见 `docs/superpowers/plans/2026-07-11-imageview.md`。
