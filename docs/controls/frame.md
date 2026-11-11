# TTyFrame — API 参考

## 1. 概述

`TTyFrame` 是可嵌入视图的设计器祖类，相当于 `TTyForm` 之于窗口：一块在设计器里画、带自己的 `.lfm`、运行时放进别的容器里的界面，让它的类从 `TTyFrame` 继承：

```pascal
type
  TSearchView = class(TTyFrame)   // File > New > TyControls Frame
    EdtQuery: TTyEdit;
    BtnGo: TTyButton;
  end;
```

用法和 LCL 的 `TFrame` 一样：在设计器里摆好控件，运行时创建出来、设好 `Parent`。

```pascal
FView := TSearchView.Create(Self);
FView.Parent := ToolWindow1;
FView.Align := alClient;
```

和 `TFrame` 不一样的地方只有一处：**它知道自己身后是什么**。

- 它自己没有背景（内置主题都不给 `TyFrame` 写规则），画的是宿主的主题背景，而且是它盖住的那一片：宿主是渐变时，frame 上看不出接缝。
- 放在它上面的控件透过它看到宿主。圆角按钮四个角外侧、透明的标签和分组框，取到的都是宿主的背景，不是 `clBtnFace`。
- 想让它自己成为一块面，在主题里给 `TyFrame` 写规则，或者给这一个 frame 设 `StyleClass` / `StyleOverride`。

普通的 `TFrame` 仍然可以用，只是它不参与主题：它画的是自己的 LCL 颜色，上面的 TyControls 控件四角取到的也是这个颜色。

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Frame` |
| 基类 | `TFrame` |
| `GetStyleTypeKey` 返回值 | `'TyFrame'`（虚方法，一族视图可以答自己的键） |
| 设计期可用 | 是（作为 frame 的祖类，从它继承；它不在调色板上） |

`TTyFrame` 没有拆成 `TTyCustomFrame` + `TTyFrame`：它和 `TTyForm` 一样站在 LCL 自己那个类的位置上，后代是在设计器里画出来的，不是注册到调色板的控件。

## 3. 属性

`TFrame` 发布的属性照旧（`Align`、`Anchors`、`AutoScroll`、`Color`、`Font`、`TabOrder`、各种事件……）。`TTyFrame` 另外发布四个，含义和每个 TyControls 控件上的一样：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Controller` | `TTyCustomStyleController` | `nil` | frame 自己从哪个样式控制器读主题；不设就用全局的 `TyDefaultController`。frame 上的控件各有各的 `Controller`，不随它走 |
| `StyleClass` | `string` | `''` | 变体名，对应 `.tycss` 里的 `TyFrame.名字 { … }` |
| `StyleOverride` | `string` | `''` | 只作用于这一个 frame 的 CSS 声明块，叠在主题之上，例如 `background: var(--surface);` |
| `Version` | `string` | — | 只读，库的版本号；设计期点 `...` 打开「关于」 |

protected 里留给后代的：

| 成员 | 说明 |
|------|------|
| `function GetStyleTypeKey: string; virtual;` | 换一个 typeKey |
| `function CurrentStyle: TTyStyleSet;` | 当前解析出的样式（主题规则 + `StyleOverride`；frame 没有悬停和焦点状态，只分正常和禁用） |
| `function OwnBackground(out AFill: TTyFill): Boolean; virtual;` | frame 自己的背景，给上面的控件问；返回 `False` 表示透出宿主 |
| `procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); virtual;` | 整块 frame 的绘制；要在背景上多画点东西就重写它 |
| `function IsDesignRoot: Boolean;` | 是不是设计器正在编辑的那个 frame |

## 4. 背景怎么来

| 情形 | frame 画什么 | 上面的控件看到什么 |
|------|-------------|-------------------|
| 没有自己的背景（默认），宿主是 TyControls 容器或 `TTyForm` | 宿主的主题背景，按 frame 所在位置取的那一片 | 同一份背景，按控件所在位置取 |
| 没有自己的背景，宿主是普通 LCL 容器 | 宿主的 LCL 颜色 | 同上 |
| 主题 / `StyleClass` / `StyleOverride` 给了纯色背景 | 这个颜色（连同样式里的边框、圆角、阴影） | 这个颜色 |
| 给了渐变背景 | 铺满 frame 的渐变 | 渐变里控件盖住的那一段 |
| 给了半透明背景 | 叠在宿主背景上 | 叠好之后的不透明颜色 |

frame 实现了 `ITyThemedBackground`，`ThemedBgColor` 回答「上面的控件身后是哪个颜色」：自己的纯色背景，或者宿主的纯色背景；身后是渐变时返回 `False`。库内部不靠它（控件走 `TyResolveParentBgFill`，能拿到渐变的切片），它是留给应用代码按这个名字问的。

主题里的写法：

```css
/* 所有 frame 都是一块面 */
TyFrame { background: var(--surface); }

/* 只有 StyleClass = 'side' 的 */
TyFrame.side { background: var(--surface-chrome); border-width: 1px; border-color: var(--border); }
```

## 5. 设计期

- 设计期包把 `TTyFrame` 注册成设计器祖类，`class(TTyFrame)` 在设计器里按 frame 打开，对象检视器里有上面四个属性。
- File > New 里有「TyControls Frame」模板：生成 `T<名字> = class(TTyFrame)` 和一个空的 `.lfm`，`uses` 里带 `tyControls.Frame`，工程自动加上 `tycontrols` 依赖；和 IDE 自带的 Frame 模板一样，不声明全局变量，也不往 `.lpr` 里加 `CreateForm`。
- frame 单独在设计器里打开时没有宿主，这时它画当前控制器的 `TyForm` 背景，设计面看起来就是它将来所在窗体的样子；上面的控件也按这个背景取色。把 frame 放到某个窗体上之后（设计期也一样），它画的是那个宿主。

## 6. 在代码里创建

`TTyFrame.Create(AOwner)` 可以直接用，得到一个空的 frame（默认 320×240），当作不带边框的透明容器。它的后代照 LCL 的规矩从 `.lfm` 构造：没有 `.lfm` 的后代类在创建时抛 `EResNotFound`，和 `TFrame` 的后代一样。

## 7. 注意事项

- frame 的绘制有缓存：子控件引起的重绘只贴缓存，不重画整块。frame 自己的样式、宿主的背景或 frame 的位置变了，下一次绘制会重画。
- 图片主题（窗体背景是图片）下，frame 画的是窗体照片在它所在位置的那一片，这种情况不走缓存。

## 8. 相关文档

- [ttyform.md](ttyform.md) —— 窗口的祖类
- [../tycss-reference.md](../tycss-reference.md) §8.4 —— `TyFrame` 是基础层刻意不定义的键
