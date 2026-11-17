# vim-md

Rendered markdown preview **inside Vim / Neovim** — no browser, no external
tools. Pure Vimscript.

`:MdPreview` opens a split with the document already rendered: headings,
emphasis, lists, task lists, block quotes, GitHub alerts, tables (box
drawing), syntax-highlighted code blocks, links and images — without the `#`, `**`, `` ` `` noise.
The preview updates while you type and follows your cursor.

```
 # Title                        |  Title
                                |  ════════════════════════
 Some **bold** and `code`       |  Some bold and code
 - [x] done                     |  ☑ done
 | a | b |                      |  ┌───┬───┐
 |---|---|                      |  │ a │ b │
```

## Requirements

* Vim 8.2+ with `+textprop +timers`, **or** Neovim 0.5+
* `'encoding'` = `utf-8` (default in Neovim)
* A terminal font with box-drawing characters

## Install

```vim
Plug 'carpetsharklabs/vim-md'
```

or any plugin manager / `:packadd` / a copy in `~/.vim/pack/*/start/vim-md`.

## Usage

| Command             | Action                                 |
|---------------------|----------------------------------------|
| `:MdPreview`        | toggle the preview window              |
| `:MdPreviewOpen`    | open it                                |
| `:MdPreviewClose`   | close it                               |
| `:MdPreviewRefresh` | force a re-render                      |
| `:MdView`           | render **in the current window** (toggle) |
| `:MdViewOpen` / `:MdViewClose` | enter / leave that view      |

`:MdPreview` shows the rendering in a split next to the source. `:MdView`
replaces the source with the rendering in the *same* window, read-only: the
cursor line is carried over in both directions, the source buffer stays
loaded and untouched (even with unsaved changes), and leaving restores your
window options. Press `q` (or run `:MdView` again) to go back.

Suggested mappings:
`nmap <leader>mp <Plug>(vim-md-toggle)` and `nmap <leader>mv <Plug>(vim-md-view)`

Inside the preview / view: `q` close · `<CR>`/`gx` follow link under cursor
(`#anchor` jumps to the heading, `http(s)://` opens externally, relative paths
open in the source window) · `]]` / `[[` next / previous heading.

## Options

```vim
let g:vim_md_position = 'right'   " right | left | above | below
let g:vim_md_size = 0             " columns/lines; 0 = half of the window
let g:vim_md_debounce = 120       " ms to wait after typing before re-render
let g:vim_md_follow = 1           " preview follows the markdown buffer you enter
let g:vim_md_filetypes = ['markdown']
let g:vim_md_show_urls = 0        " append (url) after link text
let g:vim_md_code_syntax = 1      " syntax-highlight fenced code blocks
let g:vim_md_heading_icons = ['', '', '▌ ', '▸ ', '· ', '· ']
```

Colors are `VimMd*` highlight groups, linked to standard groups by default
(`VimMdH1`..`VimMdH6`, `VimMdCode`, `VimMdCodeBlock`, `VimMdLink`, `VimMdQuote`,
`VimMdBullet`, `VimMdTableBorder`, …) so they follow your colorscheme. Override
with `highlight VimMdH1 guifg=...` (e.g. `highlight VimMdCodeBlock guibg=#1e1e2e`).
Code blocks use Vim's own syntax files for the fence language (` ```python `), so
they need `syntax on` and follow your colorscheme. See `:help vim-md`.

## Not supported (yet)

Footnotes, inline HTML beyond a few
common tags, images as pixels.

## Development

```
make test        # runs tests/ in Vim (and Neovim if installed)
```
