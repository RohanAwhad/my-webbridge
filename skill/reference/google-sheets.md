# Google Sheets Automation via WebBridge

This covers patterns for reading/writing Google Sheets data through WebBridge.
Sheets has behavior quirks that make naive approaches fail silently.

## Core architecture

Sheets renders the grid on an HTML5 canvas. Individual cells have no DOM elements.
Interaction happens through:

| Component | Selector | Role |
|-----------|----------|------|
| Name Box | `#t-name-box` | Navigate to a cell (type ref + Enter). Not the canvas. |
| Formula bar | `#t-formula-bar-input` | Contenteditable div. **Always type here**, never into the inline cell editor. |
| Inline cell editor | `#waffle-rich-text-editor` | Contenteditable div. Avoid — same content, different event handling. |

## Trusted Types constraint

Google Sheets enforces [Trusted Types](https://web.dev/trusted-types/).

**Never:**
```js
el.innerHTML = "";  // throws — blocked by Trusted Types
el.innerHTML = "<span>text</span>";  // same
```

**Always:**
```js
el.focus();
document.execCommand("selectAll");
document.execCommand("insertText", false, "your value");
```

## Typing values into cells

**Wrong approach:** Click cell (canvas), type characters into inline editor, press Tab/Enter.
- `$` signs (e.g. `$1,500`) get parsed as absolute cell references → Tab jumps to wrong cell.
- Autocomplete on repeated values (e.g. "Boston Roommates" in every row) corrupts subsequent rows when Tab accepts the ghost suggestion.
- `insertText` via the inline editor doesn't put Sheets into edit mode — values get discarded on next action.

**Right approach:** Click cell to select → click formula bar → insert text → press Enter.

### Reliable cell population pattern

Process **per-column**, not per-row. Enter moves down one cell — leverage this.

```python
# For each column, start at row 1, type, Enter (moves to next row), repeat.
# This avoids Tab entirely and sidesteps autocomplete on repeated column values.

fb_x, fb_y, fb_w, fb_h = formula_bar_coords()

for col in cols:
    for ri in range(num_rows):
        val = data[ri][col_idx]
        goto_cell(f"{col}{ri+1}")
        click(fb_x + fb_w/2, fb_y + fb_h/2)  # click formula bar
        type(val)                              # insertText via webbridge type tool
        cdp_enter()                            # commit and move down
```

### Why per-column?

Autocomplete appears when a column has repeated values. If you Tab through a row (columns B→C→D...), autocomplete in column C fires when you type a value matching a previous row. But when processing per-column (rows 1→2→3 in the same column), the values are different per row (different names, budgets, etc.), so autocomplete doesn't trigger.

## Name Box navigation

The Name Box is at fixed toolbar position. Mouse clicks can miss it because:
- The `Tables` sidebar panel overlays the right portion of the toolbar.
- Row-height changes from text wrapping shift the grid and confuse pixel-based coords.

**Use `execCommand` instead of mouse clicks:**

```python
def goto_cell(ref):
    code = (
        f"var el=document.querySelector('#t-name-box');"
        f"el.focus();el.select();"
        f"document.execCommand('selectAll');"
        f"document.execCommand('insertText',false,'{ref}');"
        f"el.dispatchEvent(new KeyboardEvent('keydown',{{key:'Enter',code:'Enter',keyCode:13,bubbles:true}}))"
    )
    evaluate(code)
    sleep(0.3)
```

## CDP key event types

Sheets ignores `rawKeyDown` for Enter and Tab. Use `keyDown` with `text`:

| Key | type | windowsVirtualKeyCode | text | unmodifiedText |
|-----|------|-----------------------|------|----------------|
| Enter | `keyDown` | 13 | `\r` | `\r` |
| Tab | `keyDown` | 9 | `\t` | `\t` |
| Delete | `rawKeyDown` | 46 | (omit) | (omit) |
| Escape | `rawKeyDown` | 27 | (omit) | (omit) |

```python
def cdp_enter():
    cdp("Input.dispatchKeyEvent", {"type":"keyDown","windowsVirtualKeyCode":13,
        "key":"Enter","code":"Enter","text":"\r","unmodifiedText":"\r"})
    cdp("Input.dispatchKeyEvent", {"type":"keyUp","windowsVirtualKeyCode":13,
        "key":"Enter","code":"Enter"})
```

## Cmd+V paste — doesn't work

On macOS, dispatching Meta+V via CDP does not paste content into Sheets.
Chrome sandboxes the clipboard; `navigator.clipboard.writeText()` requires a user gesture.
Use the formula-bar typing approach instead.

## Date auto-formatting

Sheets auto-detects dates. Values like "September 2026" get reformatted to "9/1/2026".
**Workaround:** Use ambiguous forms like "Sept 2026" instead of "September 2026".
A trailing space (e.g. "September 2026 ") does **not** prevent auto-formatting.

## The `$` sign problem

`$` typed into a cell is interpreted as an absolute reference modifier.
Typing `$1,500-$2,500` then pressing Tab confuses Sheets' navigation.
**Fix:** Type via the formula bar, not the inline cell editor. The formula bar
treats `$` as plain text until Enter commits the value.

## Reading cell values

```python
def read_cell(ref):
    goto_cell(ref)
    r = evaluate("document.querySelector('#t-formula-bar-input').innerText")
    return r.rstrip('\n')
```

## Clearing cells

Select a cell range via Name Box, then Delete:

```python
goto_cell("A1")
# Select range A1:J10
evaluate("var el=document.querySelector('#t-name-box');el.focus();el.select();"
         "document.execCommand('selectAll');document.execCommand('insertText',false,'A1:J10');")
cdp_enter()
cdp_raw_key(46, 'Delete', 'Delete')  # Delete key
```

## Summary: default approach

1. **Navigate cells:** `goto_cell()` using `execCommand` on Name Box
2. **Write values:** click formula bar → `type` tool (insertText) → CDP `keyDown` Enter
3. **Read values:** formula bar `.innerText`
4. **Clear range:** Name Box → range ref → Delete key
5. **Process order:** per-column (Enter moves down), not per-row (Tab moves right)
