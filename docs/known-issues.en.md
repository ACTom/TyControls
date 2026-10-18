# Known issues

> 中文版见 [known-issues.md](known-issues.md)。

Known issues in the current release, grouped by platform. Platforms not listed here are fully functional. If you hit something not on this list, please open an issue.

## GTK3 (Wayland sessions only)

GTK3 is fully functional under X11. The following issues appear only in **Wayland** sessions; they are rooted in the Wayland window model and upstream LCL-GTK3 and cannot be worked around at the library level:

- **Modal dialogs cannot be dragged.** LCL creates a borderless modal form as a Wayland `xdg_popup`, which has no move request.
- **Menus do not dismiss on empty-space clicks.** Clicking a focusable control (a button, an edit, …) or pressing `Esc` closes them; dropdowns are unaffected and close on any outside click.
- **Popup corners are square.** Wayland has no XShape, so dropdowns, menus, and balloons cannot be given a rounded mask.
- **Semi-transparent effects show the desktop through.** Disabled-state dimming and `Transparent` labels blend against the desktop instead of the form background.

**Recommendation:** use an X11 session with GTK3, or use Qt5 / Qt6.

## GTK3 (built with Lazarus before 4.99)

**A long input-method commit is cut short.** When an input method commits a whole phrase at once, the control receives only its first character or two. LCL-GTK3 passes each commit through a character parameter of at most 7 bytes; only the GTK3 backend of Lazarus trunk (4.99) also keeps the whole string, which the library reads back from there. Released versions before it keep no copy, so the library has nothing to read. X11 and Wayland alike.

**Recommendation:** for Chinese and other input methods under GTK3, build with Lazarus 4.99 or later, or use GTK2 / Qt5 / Qt6.

## GTK2 / GTK3 (following the OS appearance)

`Controller.Follow := tfFollowSystem` cannot read the desktop's light/dark or accent colour under GTK: the theme keeps its current mode and the `system` theme falls back to its built-in neutral blue. This applies to X11 and Wayland alike.

The cause is in LCL. GTK2 does read the real GTK style, but only once, when the widgetset is constructed, and never refreshes it; GTK3 hardcodes several system colours outright and the widgetset says so itself. A stale or hardcoded value is worse than admitting we do not know, so the library does not read them.

**Recommendation:** use Qt5 / Qt6 if you need the app to follow the OS appearance — there the values come from the live Qt palette and track a desktop colour-scheme change.

## Qt6 / GTK3 (integer desktop scaling)

With the desktop scaled by a whole factor such as 200%, the interface looks soft: controls are drawn at one times and the system enlarges them. macOS Retina screens are already drawn at their real pixels; Qt6 / GTK3 are not wired up yet.

**Recommendation:** keep the desktop scaling at 100% and enlarge the interface with a higher font DPI instead.

## macOS (compiling the library from source)

A project that puts `source/` on its own search path and asks for DWARF3 debug information does not build on macOS: `tyControls.CocoaWS.pas ... Internal error 200609171`. This is an FPC 3.2 bug: its DWARF3 writer does not handle Objective-C classes. Projects that use the package are not affected.

**Recommendation:** use the `tycontrols` package, or set the project's debug information to DWARF2 or Automatic.

## Windows (several monitors at different scaling)

A form dragged onto a monitor with different scaling lays itself out again for that monitor's DPI. Popups (dropdown lists, menus, hint balloons) do not follow: they are drawn at the DPI of the form they belong to, and come out too large or too small when they open on the other monitor.

**Recommendation:** keep controls that open a popup away from the screen edge, so the popup lands on the same monitor as its form.
