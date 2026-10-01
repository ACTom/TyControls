# Theme Builder

> 中文：[themebuilder.md](themebuilder.md)

`tools/themebuilder/` is a desktop tool for writing TyControls `.tycss` themes. You edit on the left and the preview on the right picks up every change; mistakes show up in a problem list with their line numbers. You can also connect a language model, describe the theme you want in a sentence, and let it draft or change the file — you see exactly what it changed before deciding whether to keep it.

It is a tool in the repository, not part of the library, and its code is not a public API.

## Building and running

No package needs installing first: the project uses the sources under `source/` and `designtime/` directly.

```bash
lazbuild -B tools/themebuilder/themebuilder.lpi
```

On Linux add the widgetset you want, for example `--ws=gtk2` or `--ws=qt6`; on macOS `--ws=cocoa`. The program ends up in `tools/themebuilder/lib/<cpu>-<os>/`.

The interface follows the system language (English and Chinese).

**Icon**: on Windows the icon is built into the program (`tools/themebuilder/themebuilder.ico`; the task bar and the left of the title bar show it). On Linux and macOS a program file carries no icon; if you want one, use `tools/themebuilder/icon/themebuilder-256.png` — on Linux as `Icon=<path to it>` in a `.desktop` file, on macOS to make the `.icns` of an `.app` bundle (the tool has no ready `.icns`). `scripts/gen-themebuilder-icon.ps1` renders the icon; after changing it, run that and rebuild the tool.

## The window

- **The side bar** on the left has three pages: Seeds, Problems and AI. The items of the same names in the View menu switch to a page, or fold the bar away when that page is already showing.
- **The editor** in the middle, with `.tycss` highlighting and completion.
- **The preview** on the right: eight pages of controls grouped by family, with switches along the top for dark mode, density (classic / modern) and "disable all". The window-chrome page opens a real window, to see the title bar and the shadow.

The editor's own colours are chosen in View → Editor appearance and have nothing to do with the theme being edited. The preview runs on a style controller of its own, so a broken theme only breaks the preview.

## Writing a theme

Stop typing for 0.3 seconds and the text is parsed, checked and loaded into the preview. If it does not parse, or the preview cannot draw it, the preview keeps the last version that worked and the problem list says why.

**New**: File → New offers a minimal theme (just the six seeds for light and dark, everything else from the base theme) or a copy of any built-in theme.

**Seeds page**: the six seeds (`--accent`, `--surface`, `--on-surface`, `--border`, `--danger`, `--radius`) feed most of the other colours, so they are the quickest way to change a theme. A file with `@mode light` and `@mode dark` blocks gets two columns; a single `:root` gets one, with a button that splits it into light and dark. Picking a colour rewrites that one value in the file and nothing else. If the value was an expression (`var()`, `darken()`, ...), you are asked first.

**Problems page**: parse errors, unknown properties, undefined variables, low contrast and so on, with line numbers. Double-click to jump there. Variables the base theme defines don't count as undefined.

**Ctrl+click a control in the preview** (Cmd+click on macOS) to jump to its rule. If the file has none, one is added in the right place. For a control without a variant the new rule starts as a copy of the base theme's rules — an empty rule would make the base theme step aside for that control entirely and leave it unstyled.

**Coverage check** (View → Coverage check): the controls your theme styles but the preview doesn't show, and the ones the preview shows that neither your theme nor the base theme styles specifically.

The language itself is described in [tycss-reference.en.md](tycss-reference.en.md).

## The Edit menu and keys

The Edit menu sits between File and View. Undo, Cut, Copy, Paste, Delete and Select all act on the text box that has the focus: the editor, or a Ty box such as the find box or the AI page's description. With the focus on a button or a list, their keys do nothing (the key goes to that control as usual), while choosing them from the menu acts on the editor. Cut, Copy and Delete are greyed with nothing selected, Undo with nothing to undo. Formatting and finding always act on the editor.

**Format document / Format selection**: one declaration a line, written `name: value;`, two spaces of indent a level, closing braces on lines of their own, several empty lines made one. Selectors (the colon of `TyButton:hover`), comments (a header comment over several lines too) and quoted strings are left as they are. Format selection tidies the lines the selection touches, indented for the level they are at. Each is one undo step.

**The find bar**: Ctrl+F opens it over the editor (a one-line selection goes into the find box), Ctrl+H opens it with a replace row as well. There are Match case and Whole word; Previous / Next go round to the other end; when nothing is found it says "Not found". Replace changes the selected match and finds the next; Replace all changes every one in one undo step and says how many. In the find box Enter finds the next one, Shift+Enter the previous; Esc closes the bar and goes back to the editor.

| Action | Keys |
|---|---|
| Undo / Redo | Ctrl+Z / Ctrl+Shift+Z |
| Cut / Copy / Paste | Ctrl+X / Ctrl+C / Ctrl+V |
| Delete the selection | Del |
| Select all | Ctrl+A |
| Format document | Ctrl+Shift+F |
| Format selection | (menu) |
| Find / Replace | Ctrl+F / Ctrl+H |
| Find next / previous | F3 / Shift+F3 |
| Completion | Ctrl+Space |

The editor also has SynEdit's own keys: Ctrl+Y deletes a line, Ctrl+I / Ctrl+U indent / unindent a block, Ctrl+Shift+digit sets a bookmark and Ctrl+digit goes to it.

## Saving and exporting

Saving writes back the line endings, BOM and final newline the file was read with; lines you didn't touch stay byte for byte the same. The repository's built-in theme files can be opened and saved directly — the status bar reminds you to rerun the matching generator script.

**Export theme bundle** (File menu): a folder bundle (`theme.tycss`, `theme.json` and the files the theme refers to), or a zip when the theme refers to no files. The result is read back and loaded once; if that fails, nothing is left behind.

**Use it in a program** (File menu): code to load the theme from a file, from a bundle, or registered as a named theme from text — ready to copy.

## AI

### Setting up a service

View → AI settings, or the gear at the top of the AI page. Add one of the presets:

| Preset | Format | Address | Model |
|---|---|---|---|
| OpenAI | OpenAI-compatible | `https://api.openai.com/v1` | `gpt-5` |
| DeepSeek | OpenAI-compatible | `https://api.deepseek.com/v1` | `deepseek-chat` |
| Anthropic | Anthropic | `https://api.anthropic.com/v1` | `claude-sonnet-5` |
| Local (Ollama) | OpenAI-compatible | `http://localhost:11434/v1` | `qwen2.5-coder:7b` |
| Custom | OpenAI-compatible | (yours) | (yours) |

A preset only fills in the address and model name; everything can be changed. Model names go out of date — if "Test connection" says "Wrong address or model name (404)", that is the usual reason.

- **Key**: not needed for a local model. On Windows it is encrypted for your user account (DPAPI) before it goes into the settings file; on Linux and macOS it is kept in a file only you can read (mode 0600). Keys never appear in messages or errors.
- **Maximum output**: 0 means the request does not set one and the service decides. OpenAI's newer models reject the old parameter, hence the 0; DeepSeek's `deepseek-chat` allows 8192 at most; Anthropic requires a value, 32000 by default.
- **Timeout**: how many seconds without any data count as a timeout. Writing a whole theme can take a minute or two, so there is no limit on the total time — Stop is always there.
- **Test connection** sends the smallest possible request, stops as soon as an answer starts, and tells you how it went.

The dialog also says it plainly: the theme text and your descriptions go to the service you set up here. With a local model they stay on your computer.

When the address is `http://` (not `https://`) and not on this computer — a service on your company network, or Ollama on another machine, say — the settings and the AI page show a "Not encrypted" warning: this address uses http, so the key and the theme text cross the network unencrypted. It is only a warning: the address works, with a key too — only you know whether that network can be trusted. When a service redirects the request somewhere else, the tool doesn't follow (the key would go along); it tells you which host it points to, and if that's right you change the address in the settings.

### Local models

Install [Ollama](https://ollama.com), pull a 7–8B code model (`ollama pull qwen2.5-coder:7b`), and **set the context length before starting Ollama**:

```bash
OLLAMA_CONTEXT_LENGTH=32768 ollama serve
```

By default Ollama keeps only a few thousand tokens of context and silently drops the start of a longer request. Every request starts with a reference of several thousand tokens, so that is what gets dropped, and the model starts guessing. The settings dialog reminds you of this when the address is local.

### A generation

Write what you want on the AI page — "warm colours, rounder corners" — and press Generate:

1. The answer streams into the box below. Stop ends it at any time. With a model that thinks first, the status line says so until the text starts.
2. When the answer is complete, the `tycss` code block is taken out of it and checked the way the editor checks your own text: does it parse, are the properties known, are the variables defined, can the preview draw it in light and in dark mode. Errors go back to the model with a request to fix them, at most twice. Hints such as low contrast don't.
3. The comparison window opens (if another dialog is open at that moment it doesn't; the status line points you to "Show the comparison"): the editor's text as it is now on the left, the model's version on the right, changed lines tinted, both sides scrolling together, any remaining problems listed below. Tick "Try it in the preview" to see the model's version in the preview; untick it or close the window to go back.
4. Accept puts the model's version into the editor — one Ctrl+Z takes it back. Discard changes nothing. "Show the comparison..." on the AI page opens the window again.

If you edit the file after the request went out, Accept asks first, because your edits would be replaced too.

With "Include the problem list" ticked, the editor's current problems go along with the request. It ticks itself while the file has errors and unticks when they are gone, until you set it yourself for that document.

### Conversations

Within one document the tool remembers your earlier requests and whether their results were accepted, so "a bit darker" follows on from the last one. Earlier answers are not sent again — only the current file — so requests don't grow as the conversation goes on. A new or another opened document starts afresh; so does "New conversation".

The rules and the syntax reference sent to the model are in English, which models follow best. Your description is sent as you wrote it, and the model writes its one-line remark before the code block in your language.

### When something goes wrong

| Status line | What it means |
|---|---|
| Cannot connect to ... Is the service running, or does it need a proxy? | Nothing answers at that address, or the network is down |
| Cannot find the host ... | The host name does not resolve |
| The key was refused (401) | Wrong or expired key |
| Wrong address or model name (404) | A path segment too many or too few, or a misspelt model |
| Too many requests (429) | Rate limited; try again shortly |
| No reply from ... for N seconds | The timeout in the settings ran out |
| The reply reached the maximum output length and was cut off | Raise the maximum output |
| The reply is not in the expected format | The address is not a service of that format |
| The reply has no tycss code block | The model did not follow the rules; its text is in the output box |
| The reply is not complete: it ended inside its code block | The service said it was done, but the code block wasn't |
| The service answered with a redirect ... to ... | The address moved; the tool doesn't follow — check it and change the settings |
| The proxy asks for a user name and password (407) | Set them in the system's proxy settings |

Whatever happens, the editor is not affected.

### Linux and macOS

AI uses the system's libcurl, loaded at run time. If it can't be found, the AI page lists the library names it tried and greys out Generate; everything else works as usual. On Debian and Ubuntu install the `libcurl4` package; on a distribution with an unusual library name, point to it:

```bash
THEMEBUILDER_LIBCURL=/usr/lib64/libcurl.so.4 ./themebuilder
```

### Proxies

On Windows the system's proxy settings are used. On Linux and macOS the usual `https_proxy`, `http_proxy` and `no_proxy` environment variables apply. A local address (a local model) never goes through a proxy.

## Where the settings live

The tool's settings, recent files and AI services are in the user configuration folder:

| System | Folder |
|---|---|
| Windows | `%LOCALAPPDATA%\themebuilder\` |
| Linux / macOS | `~/.config/themebuilder/` |

`themebuilder.ini` holds the tool's settings, `themebuilder-ai.ini` the AI services, and on Linux and macOS `themebuilder-ai.keys` the keys. Delete them to start over.

## Known limitations

- The editor and the comparison window use SynEdit, whose borders and scroll bars are native and don't follow the editor appearance.
- The AI always returns the whole file, even to change one colour.
- On macOS (Apple silicon) the way libcurl is called has not been tried on real hardware yet.
- On Linux and macOS, Stop does not take effect while the host name is being looked up (DNS): libcurl doesn't check for it then, so it waits for the lookup to finish or for the connect timeout (15 seconds).
- For the same reason, closing the tool on Linux or macOS while a host name is being looked up (or closing the AI settings during "Test connection") can take up to about 15 seconds: closing waits for that request to end.
- On Linux and macOS, if the system's libcurl is too old to accept an option the AI needs, nothing is sent and the status line names the option; a newer libcurl fixes it.
