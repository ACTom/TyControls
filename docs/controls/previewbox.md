# TTyPreviewBox

## 概述

`TTyPreviewBox` 是一个可复用的**预览控件**:给它一个文件路径,它按类型显示 —— 图片走内嵌
[TTyImage](image.md)(缩放适配)、文本走只读 [TTyMemo](memo.md)(可滚动)、其余显示"无法预览"占位。
也可由调用方**交出位图/文本**自定义显示,或用低层 `OnPaintPreview` 钩子完全自绘。

它是 Phase 7 文件对话框预览窗格的底座 —— 图片对话框和通用预览对话框([filedialog](filedialog.md))都用它。
主题上它有**自有 typeKey** `'TyPreviewBox'`(见下文《主题与 typeKey》)。

## 用法

```pascal
uses tyControls.PreviewBox;

Box := TTyPreviewBox.Create(Self);
Box.Parent := Panel1;
Box.Align := alClient;

Box.PreviewFile('C:\photos\cat.png');   // 内建分派:图片/文本/占位
// 或手动:
Box.ShowImageFile('logo.png');
Box.ShowTextFile('readme.md');
Box.ShowImage(myBGRABitmap);             // 交出位图
Box.ShowText('自定义内容');
Box.ShowMessage('无法预览');
Box.Clear;
```

## 属性 / 方法

| 成员 | 说明 |
|---|---|
| `PreviewFile(path)` | 内建分派:图片 → `ShowImageFile`;文本(且 `AllowText`)→ `ShowTextFile`;否则占位。加载失败也回落占位。 |
| `ShowImageFile(path): Boolean` | 加载图片文件;成功显示图片,失败返回 False。 |
| `ShowTextFile(path): Boolean` | 读前 64 KB 文本显示;失败返回 False。 |
| `ShowImage(bmp: TBGRABitmap)` | 调用方交出的位图(`nil` 清空)。 |
| `ShowText(s)` / `ShowMessage(s)` | 交出文本 / 居中占位消息。 |
| `ShowCustom` | 进自定义画模式 → `Paint` 调 `OnPaintPreview`。 |
| `Clear` | 清空。 |
| `AllowText: Boolean` | 是否允许文本预览。默认 True;图片场景设 False → `PreviewFile` 对文本也显示占位。 |
| `OnPaintPreview: TTyPaintSurfaceEvent` | 低层自绘钩子(同 `TTyPaintPanel.OnPaintSurface`),仅自定义画模式下触发。 |

## 关键设计

- **子控件切换**:`FImage`/`FMemo` 都 `alClient` 且都被 box 拥有释放,但**同时最多一个可见**(LCL 只对可见控件对齐)。
  内部 `csNoDesignVisible`,不漏进 IDE 设计器。
- **`SetController` 下推**:box 的 per-instance Controller 会推给内嵌图片/文本控件,独立使用时主题一致。
- **加载安全**:图片/文本加载都包 `try/except`,坏文件回落占位,不崩。`ShowImage` 经 `TBitmap` 桥接进
  `TTyImage.Picture`(BGRA 3.2.2 无 `Create(TGraphic)`)。
- **纯分类** `TyPreviewClassify(name): (pkImage, pkText, pkOther)` 按扩展名(大小写无关)分类,可无头测。

## 主题与 typeKey

| 项目 | 值 |
|---|---|
| `GetStyleTypeKey` 返回值 | `'TyPreviewBox'`(**自有 typeKey**) |
| 该键画什么 | 预览井的**框**(`DrawFrame`:背景 + 边框 + 圆角 + 阴影)、按 `padding` 内缩出的内容矩形,以及居中的**占位文字**("无法预览")——后者用该键的 `color` / `font-name` / `font-size` / `font-weight`。 |

它从前返回 `'TyPanel'`。这个控件画的图元(一个框 + 一行居中文字)确实和面板一样,但它的**角色**不同:它是文件对话框的预览井,那行字是**空状态**文案。空状态按惯例要比正文更淡,而在借用面板键的年代,把它调淡就等于把全应用面板的标题一起调淡。现在 `TyPreviewBox { color: var(--muted); }` 只作用于这里。`TyPreviewBox` 已作为附加选择器并入主题里 `TyPanel` 的规则块,解析值与从前逐字节相同,**开钩子而不动像素**;第三方主题若只覆盖了 `TyPanel`,需要补上 `TyPreviewBox`(主题层按 typeKey 全有全无地回落)。

**子部件 typeKey:没有,也不需要。** 占位文字是本控件绘制的唯一文本,它的 `color` 已经由盒子键直接寻址;内嵌的图片 / 文本预览是真正的 [`TTyImage`](image.md) / [`TTyMemo`](memo.md) 子控件,各走各自的键。

> 对照:[`TTyPaintPanel`](paintpanel.md) 刻意仍用 `TyPanel`——它就是一个面板,只是把画笔交给了调用方;预览井不是。

## 消费者

[文件对话框](filedialog.md)的预览窗格:图片版(`AllowText=False`,图片-only)与通用预览版
(`AllowText=True`,图片+文本+`OnPreview` 自定义)都用它。
