# TTyTrackEdit

## 1. 概述

TTyTrackEdit 是**数值编辑框 + 内嵌迷你滑块**,继承自 [TTyNumericEdit](numericedit.md)。在编辑框尾部保留一小块区域画一条滑轨 + 圆形滑块,**拖动滑块设置 `Value`**(范围 `MinValue..MaxValue`,默认 `0..100`),编辑框里的数字实时回显;也可以直接键入数字。复用 NumericEdit 的 `Value` / 格式化 / 输入过滤,以及 TTyEdit 的 `RightReserve` / `PaintTrailing` 钩子来预留并绘制滑块。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.TrackEdit` |
| `GetStyleTypeKey` | `'TyEdit'`(经继承);滑块 accent 取 `'TyGaugeFill'` |

无新增 `.tycss`。

```pascal
uses tyControls.TrackEdit;
```

---

## 3. 属性

继承 [TTyNumericEdit](numericedit.md) 的 `Value` / `Decimals`(TrackEdit 默认 `0`)/ `MinValue`(默认 `0`)/ `MaxValue`(默认 `100`)/ `UseThousands`,以及 TTyEdit 的全部已发布属性。

滑块把 `Value` 映射到 `[MinValue, MaxValue]`——所以这两个要设成一个有意义的区间(默认已给 0..100)。

---

## 4. 行为

- 尾部滑块区(`RightReserve` 预留、`PaintTrailing` 画轨+滑块)按下 / 拖动 → 按 X 位置算出 `Value` 并回显。
- 纯函数 `TyTrackEditValueAt`(x→值)/ `TyTrackEditThumbX`(值→x)承载映射,已单元测试。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.TrackEdit;

TyDefaultController.LoadTheme('themes/light.tycss');

var T: TTyTrackEdit;
T := TTyTrackEdit.Create(Self);
T.Parent := Self;
T.SetBounds(20, 20, 200, 28);
T.MinValue := 0; T.MaxValue := 255;   // 例如一个 0..255 的通道值
T.Value := 128;
```

---

## 6. 注意事项

- **需要范围:** 滑块依赖 `MinValue < MaxValue`(默认 0..100);相等时滑块停在左端。
- **拖动是真机验证项:** 纯映射函数可 headless 测,鼠标拖动路径需在真机上验证。
- **数字+滑块二选一:** 既能拖滑块也能直接键入(继承数值输入过滤 + 失焦格式化)。
