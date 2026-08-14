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
