# TTyURLEdit

## 1. 概述

TTyURLEdit 是**带"打开"按钮的 URL 编辑框**,继承自 [TTyEdit](edit.md)。在编辑框右侧保留一小块区域画一个箭头(`→`)按钮,点击用默认浏览器打开当前文本。复用 TTyEdit 的文本引擎与 `'TyEdit'` 主题,靠新增的 `RightReserve` / `PaintTrailing` 钩子在文本区右侧预留并绘制按钮(文本区自动让出这块宽度,光标/滚动/选区都不会跑到按钮下面)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.URLEdit` |
| `GetStyleTypeKey` | `'TyEdit'`(继承)|

无新增 `.tycss`。

```pascal
uses tyControls.URLEdit;
```

---

## 3. 属性 / 方法

继承 [TTyEdit](edit.md) 的全部已发布属性(`Text` / `TextHint`(默认 `https://…`)/ `OnChange` …)。

| 方法 | 说明 |
|------|------|
| `OpenURL` | 用默认浏览器打开当前 `Text`(空文本不打开);点击尾部按钮也会调用。 |

---

## 4. 行为

- 右侧按钮区(`RightReserve` 预留、`PaintTrailing` 画 `→`)点击 → `OpenURL`(经 `LCLIntf.OpenURL`)。
- 点在按钮区不落光标、不起选区(被按钮消费)。

---

## 5. 代码示例

```pascal
uses tyControls.Controller, tyControls.URLEdit;

TyDefaultController.LoadTheme('themes/light.tycss');

var U: TTyURLEdit;
U := TTyURLEdit.Create(Self);
U.Parent := Self;
U.SetBounds(20, 20, 240, 28);
U.Text := 'https://gitee.com/';   // 点右侧 → 在浏览器打开
```

---

## 6. 注意事项

- **v1 未做超链接着色:** 文本按普通编辑框颜色显示;"打开"按钮是主要可视线索(后续可加 accent+下划线着色)。
- **跨平台:** 打开用 `LCLIntf.OpenURL`(Win/macOS/Linux 各走系统默认浏览器)。
- **尾部钩子:** `RightReserve` / `PaintTrailing` 默认 0/空,普通 `TTyEdit` 字节一致;URLEdit / [TTyComboEdit](comboedit.md) 是它们的首批用户。
