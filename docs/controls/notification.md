# TTyNotification

## 1. 概述

`TTyNotification` 是 TyControls 库中的主题化「角落浮出通知（toast）」组件，继承自 `TComponent`——**非可视组件**，像 `TTyHint` / `TTyBalloonHint` 一样丢到窗体上，代码调用 `Show` 弹出。它在屏幕某个角落浮出一张主题化卡片（语义标记 + 标题 + 正文 + 关闭 `x`），`Duration` 毫秒后自动消失。典型用途：后台任务完成 / 失败、自动保存成功、后台同步出错、任何「说一句就走、不打断用户」的播报。

**它填的是 `TTyMessage` 填不了的坑**：`TTyMessage` 是**模态对话框**——拦住用户、要一个回答。toast 谁也不拦、不要回答、自己会走。两者不是同一个东西的两种尺寸。

它**不是**内嵌控件而是**自带一个窗口**：toast 必须浮在一切之上，包括窗口化控件（画在窗体画布上的东西会被它们盖掉）——所以和 `TTyPopupSurface` / `TTyBalloonHint` 完全一样，它拥有一个无边框 `fsStayOnTop` 的 `TForm`，用 `TTyPainter` 画卡片，并把鼠标手势原样交回组件本身。

语义种类由 `NotificationType` 决定（`atInfo` / `atSuccess` / `atWarning` / `atError`），它同时挑选**标记字形**和**标记墨色**（经由 `TyNotification.<type>` 这个 StyleClass，见第 6 节）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Notification` |
| 卡片 typeKey | `'TyNotification'`（`background` / `border-*` / `color` / `font-*` / `padding` / `opacity`） |
| 关闭字形 typeKey | `'TyNotificationClose'`（`x` 的悬停底片取其 `background`，`x` 的笔色取其 `color`） |
| 基类 | `TComponent`（非可视组件；窗口是内部的 `TTyNotificationWindow`） |
| 类方法 | `TTyNotification.StyleTypeKey` / `TTyNotification.CloseStyleTypeKey` 返回上面两个键 |

```pascal
uses tyControls.Notification;
```

**为什么 typeKey 是类方法而不是 `ITyStyleable`？** 控制器的 styleable 注册表装的是 `TControl`，非可视组件不是控件，没有接口可实现——两个键因此以普通函数暴露，供测试和主题文档引用。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Title` | `string` | `''` | 标题，用卡片字体 + `--notification-title-weight` 绘制。空 = 无标题，正文独占整个文字列。 |
| `Message` | `string` | `''` | 正文。**只按换行符断行，不自动折行**——卡片是固定主题宽度，行末由作者决定（与 `TTyBalloonHint.Description` 同一约定）。 |
| `NotificationType` | `TTyNotificationType` | `atInfo` | `atInfo` / `atSuccess` / `atWarning` / `atError`。挑标记字形 + 标记墨色（第 6 节）。 |
| `Duration` | `Integer` | `4500`（= `TyNotificationDuration`，AntD 的 4.5 秒） | 自动消失延时（毫秒）。**`0` = 不自动消失**，只能由 `Hide` / `x` 关掉——所以 `Duration = 0` 时务必保持 `Closable = True`。负值被夹成 `0`。 |
| `Position` | `TTyNotificationPosition` | `npTopRight` | `npTopLeft` / `npTopRight` / `npBottomLeft` / `npBottomRight`——**屏幕工作区**的四角（不是窗体的角：toast 活得比弹它的那次点击长，用户可能早就切走了）。同角的 toast 按弹出顺序**堆叠**。 |
| `Closable` | `Boolean` | `True` | 显示并启用关闭（`x`）。默认开：关不掉的 toast 就是挡路的 toast。 |
| `ShowIcon` | `Boolean` | `True` | 显示语义标记。关掉 = 纯文字卡片（`NotificationType` 此时只影响主题）。 |
| `PauseOnHover` | `Boolean` | `True` | 指针停在卡片上时**冻结**倒计时，免得 toast 从正在读它（或正伸手去点 `x`）的人眼皮底下消失。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |
| `OnClose` | `TNotifyEvent` | `nil` | 见第 4 节。 |
| `OnClick` | `TNotifyEvent` | `nil` | 见第 4 节。 |

> **没有 `StyleClass`：** class 这条通道被 `NotificationType` **独占**（`TyNotification.info` / `.success` / `.warning` / `.error`），不开放第二个来源，避免两者打架。要做实例级微调用不上 class 的话，改主题令牌。

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnClose` | **每次消失触发一次**，不论起因：倒计时到、点 `x`、还是代码 `Hide`。**幂等**——对已经消失的 toast 再 `Hide` 不会再触发。组件被销毁时**不触发**（组件没了 ≠ 用户关了它）。 |
| `OnClick` | 点击卡片**除 `x` 以外**的区域。点 `x` 的手势**不会**触发它。**点击不会让 toast 消失**——一次点击是什么意思是宿主的事。 |

> **`OnClose` 里不要 `Free` 这个组件：** 超时消失是从**倒计时定时器自己的 tick** 里走到 `OnClose` 的，而那个定时器正属于你要 `Free` 的组件。要「弹完就不管」的 toast 请用 `TyNotify`（第 5 节），它自己回收。

---

## 5. 关键成员

### 纯规则 / 几何函数（单元级，可无组件无窗口直接调用）

```pascal
type
  TTyNotificationLayout = record
    IconRect: TRect;      // 语义标记槽位（空 => 不画标记）
    CloseRect: TRect;     // 关闭字形槽位（空 => 无 x）
    TitleRect: TRect;     // 标题行（空 => 不画）
    MessageRect: TRect;   // 正文块（空 => 不画）
  end;

function TyNotificationTypeGlyph(AType: TTyNotificationType): TTyGlyphKind;
function TyNotificationTypeClass(AType: TTyNotificationType): string;
function TyNotificationStacksDown(APosition: TTyNotificationPosition): Boolean;
function TyNotificationStackOffset(const APriorHeights: array of Integer; AGap: Integer): Integer;
function TyNotificationRect(APosition: TTyNotificationPosition; const AWorkArea: TRect;
  AW, AH, AMargin, AStackOffset: Integer): TRect;
function TyNotificationHeight(ATitleH, ALineH, ALineCount, APadT, APadB, AGap, AIconSize: Integer;
  AHasIcon, AHasTitle: Boolean): Integer;
function TyNotificationLayout(AClientWidth, AClientHeight: Integer;
  AHasIcon, AHasTitle, AClosable: Boolean;
  APadL, APadT, APadR, APadB, AIconSize, AGap, ACloseSize, ATitleH: Integer): TTyNotificationLayout;
function TyNotificationAdvance(AElapsedMs, AMs: Integer; APaused: Boolean): Integer;
function TyNotificationExpired(AElapsedMs, ADurationMs: Integer): Boolean;
```

全部整数 / 枚举入参、无组件状态、无窗口依赖，测试直接调用（`tests/test.notification.pas`）。要点：

- **堆叠方向**：栈永远朝着「第一张卡片贴的那条边」的**反方向**长——上面两个角往下堆，下面两个角往上堆，于是**最老的那张守住角落**，新来的绝不会把别人挤出屏幕。
- **堆叠偏移** = 同角、比我早进栈的每张卡片的 `高度 + AGap` 之和。高度 ≤ 0 的卡片什么都不占，因此也**不吃一个 gap**（不能为一张没人看得见的卡片推开栈）。
- **越界钳制**：栈比工作区还高 / 卡片比工作区还大 → 堆在远端那条边上，新卡片压住老卡片，而不是列队走出屏幕。
- **卡片高度**：`padT + [标题] + [gap] + 行数×行高 + padB`；gap **只存在于标题和正文之间**（没标题就没 gap）。标记在文字**旁边**，所以「内容高度」有一个 `AIconSize` 的**下限**——一行字的 toast 也得装得下标记。宽度**完全不量**：卡片就是主题宽度（`--notification-width`），于是一列 toast 是一列一样宽的卡片。
- **卡片内部的空间分配次序（close > 标记 > 文字）**：
  1. `x` 贴内容带**右上角**，**最先**占位——`Duration = 0` 时它是唯一的出口（和 `TTyTag` 的 `x` 优先同一个理由）；
  2. 标记贴内容带**左**边，还塞得下才占位；有标题时在**标题行**上垂直居中（比标题行高就顶对齐），没标题时在整条带上居中；
  3. 文字列是剩下的部分，因此是**唯一有弹性的**那块：窄到让它塌缩，说明 `--notification-width` 调坏了，不是布局该背的锅。
- `padding` 吃掉整张卡片 / 宽高 ≤ 0 → 四个矩形全空，绝不出现反向矩形。
- **倒计时**：`TyNotificationAdvance` 在 paused 时**完全不动**（是冻结，不是变慢），非正的 tick 也绝不倒退；`TyNotificationExpired` 里 `Duration = 0` **永不到期**。

### 公开成员

```pascal
class function StyleTypeKey: string;          // 'TyNotification'
class function CloseStyleTypeKey: string;     // 'TyNotificationClose'

procedure Show;      // 浮出到它的角落并开始倒计时；对已弹出的 toast 只是重置倒计时（不会堆两份自己）。设计期无效
procedure Hide;      // 立刻消失：停倒计时、退栈（下面的 toast 补上空位）、触发 OnClose。幂等
function AdvanceTime(AMs: Integer): Boolean;  // 倒计时推进 AMs，返回「本次 tick 是否让它消失了」
function MeasureAtPPI(APPI: Integer): TSize;  // 卡片自然尺寸（主题宽度 + 内容所需高度），设备像素
function SlotRectIn(const AWorkArea: TRect; APPI: Integer): TRect;  // 它该落在 AWorkArea 的哪里（已计入同角已有的堆叠）
function CloseRectIn(AClientW, AClientH, APPI: Integer): TRect;     // x 槽位（设备像素，(0,0)-local）；非 Closable 时为空
property Showing: Boolean;                    // 当前是否浮着
```

- **`AdvanceTime` 是可步进的测试缝**（和 `TTyButton.AdvanceAnimation` 同一套路，同一个理由）：运行期由那个懒创建的 `TTimer` 每 tick 调它，测试则直接调——**没有任何测试需要 sleep**。
- **`SlotRectIn` 把工作区当参数收**（而不是自己去读 `Screen.WorkAreaRect`），所以摆放规则不需要屏幕就能测；`Show` 传真的那个进去。

### 全局便捷函数

```pascal
procedure TyNotify(const ATitle, AMessage: string; AType: TTyNotificationType = atInfo;
  APosition: TTyNotificationPosition = npTopRight;
  ADurationMs: Integer = TyNotificationDuration);
```

弹完就不管：自己造一个 toast、弹出、并由单元负责回收（沿用 `tyControls.Dialogs` 的 `TyShowMessage` / `TyMessageDlg` 那套全局函数惯例）。**回收发生在下一次 `TyNotify` 调用**（以及单元 finalization），**不是**在 toast 自己的关闭路径上——那条路径正跑在要被 `Free` 的那个组件的定时器 tick / 鼠标处理里。

---

## 6. 状态与主题

### 支持的伪类状态

- **卡片**（`TyNotification`）：`:hover`（指针在卡片上）/ `:normal`。toast 没有 enabled / focus / press 状态可言，唯一值得主题反应的就是「指针停在上面」（比如浮起一点）。
- **`x`**（`TyNotificationClose`）：状态取的是**字形自己的**——指针精确落在 `x` 上才是 `:hover`，按下去是 `:active`，所以 `x` 独立于卡片亮起（与 `TTyTag` / TabStrip 的关闭按钮同一套路）。解析时带上**当前 type 的 class**，因此 `TyNotificationClose.error` 可以给错误 toast 的 `x` 单独换色。

### 一个 typeKey 扛两种墨色

卡片只有**一条**规则，但要出两种墨色（标题/正文是中性的，标记是语义色）。约定是这样切的：

| 解析 | 取什么 |
|------|--------|
| `TyNotification`（**不带 class**） | **只**取 `color` = **标题 + 正文**的墨色 |
| `TyNotification.<type>`（带 type class） | 卡片的**一切**（`background` / `border-*` / `radius` / `padding` / `font-*`）**以及** `color` = **标记**的墨色 |

**优雅降级是自动的**：主题没写 `TyNotification.<type>` 规则时，带 class 的那次解析会落回基础规则，于是标记**直接取卡片自己的墨色**——绝不回退到任何硬编码颜色。反过来，type 变体想给整张卡片上色（`background` / `border-color`）也是现成的，因为卡片正是从带 class 的那次解析里出来的。

> **type 只给标记上色（外加可选的卡片着色），不碰文字**：这是刻意的——通篇按语义色刷正文是 `TTyAlert`（内联警告条）的活，toast 的卡片保持中性、只有标记出彩（AntD 的 notification 也正是这么干的）。

### 主题令牌摘要

```css
/* 卡片。形状照 TyCard（最近的同类：也是一张有标题的表面）逐条对齐。 */
TyNotification {
  background: var(--surface);
  color: var(--on-surface);              /* 标题 + 正文的墨色 */
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 12px 14px;
  font-size: var(--font-size-base);
}
TyNotification:hover { border-color: var(--border-hover); }
/* 语义变体：其 color 是「标记」的墨色。四个 class 名就是控件与主题之间的全部约定。 */
TyNotification.info    { color: var(--accent); }   /* info 不需要新 seed：这套词汇里 info 就是品牌色 */
TyNotification.success { color: var(--success); }
TyNotification.warning { color: var(--warning); }
TyNotification.error   { color: var(--danger); }

/* 与已发布的 TyTagClose 规则逐字对齐：两处 x 是同一枚字形，不该长得不一样。 */
TyNotificationClose       { color: var(--muted); }
TyNotificationClose:hover { background: var(--overlay-hover); color: var(--on-surface);
                            border-radius: var(--radius-sm); }
```

> 控件也会解析 `TyNotificationClose:active`（按下 `x` 时），但**上面的规范块刻意不写它**——现有调色板里没有 `--overlay-active` 这类令牌，而**控件绝不发明颜色**。想要按下反馈的主题自己加一条即可；不写就是不画底片（降级路径见下）。

`TyNotificationClose` **未定义时优雅降级**：无 `background` → 不画底片；无 `color` → `x` 用卡片自己的墨色。**不会**回退到任何硬编码颜色。
`TyNotification` 整条规则**没有 `background`** → **什么都不画**（不是画一张硬编码的卡片）。

### 尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--notification-width` | `340`（= `TyNotificationWidth`） | 卡片固定宽度（**不量文字**） |
| `--notification-icon-size` | `24`（= `TyNotificationIconSize`） | 语义标记的方形槽位（`TyDrawGlyph` 会留白，实际字形约 16px） |
| `--notification-close-size` | `14`（= `TyNotificationCloseSize`，与 `TyTagCloseSize` / `TyTabCloseSize` 一致，三处 `x` 观感统一） | `x` 方形槽位边长 |
| `--notification-gap` | `8`（= `TyNotificationGap`） | 标记↔文字列、标题↔正文 的间隙 |
| `--notification-margin` | `16`（= `TyNotificationMargin`） | 距工作区角落的内缩 |
| `--notification-stack-gap` | `8`（= `TyNotificationStackGap`） | 两张堆叠卡片之间的间隙 |
| `--notification-title-weight` | `700`（= `TyNotificationTitleWeight`） | 标题字重。主题**应当**写成 `--notification-title-weight: var(--font-weight-bold);`——`Metric()` 会解析 `var()` 引用，于是标题字重跟着全局那一个字重令牌走，不各自漂移 |

> **`--notification-title-weight` 为什么是 metric 而不是样式属性？** 一个 typeKey 要扛两种文字角色：`TyNotification` 规则自己的 `font-weight` 是**正文**的，标题就需要第二个数，而这个数仍然必须归主题管。它是**字重不是长度**，因此调用点**不缩放**它（`Metric()` 只是主题的整数令牌解析器，`700` 这样的无单位数照样解析）。

标记与 `x` 字形本身还支持图标字体覆盖（`--glyph-info` / `--glyph-success` / `--glyph-warning` / `--glyph-error` / `--glyph-close`，v3/C5）。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Notification;

TyDefaultController.LoadTheme('themes/light.tycss');
```

弹完就不管（最常见的用法）：

```pascal
TyNotify('已保存', '3 个文件已写入磁盘。', atSuccess);
TyNotify('同步失败', '连不上服务器。' + LineEnding + '将在 5 分钟后重试。',
         atError, npBottomRight, 0);   // Duration=0：留着，直到用户点 x
```

放在窗体上的组件（可挂事件、可复用）：

```pascal
// .lfm 里丢一个 TTyNotification（Name = Toast），或代码创建：
Toast := TTyNotification.Create(Self);
Toast.Title := '后台任务完成';
Toast.Message := '导出了 1,204 行。';
Toast.NotificationType := atSuccess;
Toast.Position := npTopRight;
Toast.Duration := 4500;
Toast.OnClick := @HandleToastClick;
Toast.OnClose := @HandleToastClose;
...
Toast.Show;     // 同一个组件可以反复 Show：每次重新开始倒计时
```

点击 toast 打开详情（点击**不会**让它消失，所以自己 `Hide`）：

```pascal
procedure TForm1.HandleToastClick(Sender: TObject);
begin
  ShowExportLog;
  (Sender as TTyNotification).Hide;   // 用完了就自己收掉
end;
```

---

## 8. 注意事项

- **`TTyNotification` 不是 `TTyMessage` 的轻量版：** 后者是模态对话框（拦住用户、要回答），toast 谁也不拦、不要回答、自己会走。要一个**行内**常驻的警告条，那是 `TTyAlert`。
- **两个手势互不串味：** 点 `x` **只**触发 `OnClose`，绝不触发 `OnClick`；按下 `x` 拖开再抬起 = 取消（不关闭，也不产生 `OnClick`——这次按下从来就不属于卡片）。
- **`OnClose` 里不要 `Free` 组件**（见第 4 节）；要「弹完就不管」用 `TyNotify`。
- **正文不自动折行：** 只按换行符断行。卡片是固定的 `--notification-width`，行末由作者决定；放不下的行按省略号截断，装不下的行直接不画（绝不溢出卡片）。
- **窗口被裁成卡片的圆角轮廓**（`SetWindowRgn`），所以主题给 `TyNotification` 写的 `shadow` **看不见**——阴影会连同轮廓外的一切被裁掉。顶层窗口的「浮起感」是 OS 的活。**Wayland 上没有 XShape**，`setMask` 会被静默忽略 → 卡片退化成直角（与 `TTyBalloonHint` 同样的降级）；窗口的 `Color` 会被设成卡片的表面色，所以那些切不掉的像素读起来仍然是卡片，而不是一块黑角（暗色 OS 上 LCL 默认的 `clBtnFace` 就是近黑）。
- **`Position` 是屏幕工作区的角，不是窗体的角：** toast 活得比弹它的那次点击长，用户可能早就切走了。当前用**主显示器**的工作区（`Screen.WorkAreaRect`）。
- **堆叠是按角分开的**：只有同一个角的 toast 才互相让位；中间那张消失后，下面的会自动补上空位。
- **设计期 `Show` 无效**：toast 是一次运行期事件，不是可预览的外观。
- **可无窗口驱动的部分**：卡片的绘制、命中、手势、倒计时、堆叠全都不需要窗口（组件持有状态，窗口只是把自己的 client 尺寸递进来），因此这些规则全部有 headless 测试守护。真正需要真机验证的只有「把窗口摆上屏幕」这一步和最终观感。
