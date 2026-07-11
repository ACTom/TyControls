# TTyPreviewBox

## 概述

`TTyPreviewBox` 是一个可复用的**预览控件**:给它一个文件路径,它按类型显示 —— 图片走内嵌
[TTyImage](image.md)(缩放适配)、文本走只读 [TTyMemo](memo.md)(可滚动)、其余显示"无法预览"占位。
也可由调用方**交出位图/文本**自定义显示,或用低层 `OnPaintPreview` 钩子完全自绘。

它是 Phase 7 文件对话框预览窗格的底座 —— 图片对话框和通用预览对话框([filedialog](filedialog.md))都用它。
**零新增主题 token**(`GetStyleTypeKey = 'TyPanel'`)。

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

## 消费者

[文件对话框](filedialog.md)的预览窗格:图片版(`AllowText=False`,图片-only)与通用预览版
(`AllowText=True`,图片+文本+`OnPreview` 自定义)都用它。
