" vim-md: highlight groups and applying highlights to the preview buffer.
"
" Overlapping spans (e.g. bold inside a heading) are flattened into
" non-overlapping segments whose group is a generated "combo" group that merges
" the attributes of every group covering the segment. This works the same in
" Vim (text properties) and Neovim (buffer highlights).

let s:links = {
      \ 'VimMdH1': 'Title',
      \ 'VimMdH2': 'Function',
      \ 'VimMdH3': 'Identifier',
      \ 'VimMdH4': 'Type',
      \ 'VimMdH5': 'Constant',
      \ 'VimMdH6': 'Comment',
      \ 'VimMdCode': 'String',
      \ 'VimMdCodeBlock': 'ColorColumn',
      \ 'VimMdCodeLang': 'Comment',
      \ 'VimMdLink': 'Underlined',
      \ 'VimMdUrl': 'Comment',
      \ 'VimMdImage': 'Special',
      \ 'VimMdQuote': 'Comment',
      \ 'VimMdBullet': 'Special',
      \ 'VimMdCheck': 'Special',
      \ 'VimMdChecked': 'String',
      \ 'VimMdRule': 'Comment',
      \ 'VimMdTableBorder': 'Comment',
      \ 'VimMdNote': 'Identifier',
      \ 'VimMdTip': 'String',
      \ 'VimMdImportant': 'Special',
      \ 'VimMdWarning': 'WarningMsg',
      \ 'VimMdCaution': 'ErrorMsg',
      \ }

let s:combos = {}
let s:defined = {}
let s:ns = 0

function! vim_md#hl#setup() abort
  let s:defined = {}
  highlight default VimMdBold gui=bold cterm=bold
  highlight default VimMdItalic gui=italic cterm=italic
  highlight default VimMdStrike gui=strikethrough cterm=strikethrough
  for [name, target] in items(s:links)
    execute 'highlight default link' name target
  endfor
endfunction

function! s:attrs(group) abort
  let id = synIDtrans(hlID(a:group))
  let r = {}
  for mode in ['gui', 'cterm']
    for what in ['fg', 'bg', 'sp']
      let v = synIDattr(id, what, mode)
      if v !=# '' && v !~# '\s'
        let r[mode . what] = v
      endif
    endfor
    let flags = []
    for f in ['bold', 'italic', 'underline', 'undercurl', 'strikethrough', 'reverse', 'standout']
      if synIDattr(id, f, mode)
        call add(flags, f)
      endif
    endfor
    let r[mode] = flags
  endfor
  return r
endfunction

function! s:define_combo(name) abort
  let merged = {'gui': [], 'cterm': []}
  for g in s:combos[a:name]
    let a = s:attrs(g)
    for [k, v] in items(a)
      if k ==# 'gui' || k ==# 'cterm'
        for f in v
          if index(merged[k], f) < 0
            call add(merged[k], f)
          endif
        endfor
      else
        let merged[k] = v
      endif
    endfor
  endfor
  let cmd = 'highlight ' . a:name
  for [k, v] in items(merged)
    if k ==# 'gui' || k ==# 'cterm'
      let cmd .= ' ' . k . '=' . (empty(v) ? 'NONE' : join(v, ','))
    else
      let cmd .= ' ' . k . '=' . v
    endif
  endfor
  execute cmd
endfunction

function! s:ensure(name) abort
  if has_key(s:defined, a:name)
    return
  endif
  if has_key(s:combos, a:name)
    call s:define_combo(a:name)
  endif
  let s:defined[a:name] = 1
endfunction

function! s:combo(groups) abort
  let name = 'VimMdX_' . join(map(copy(a:groups), 'substitute(v:val, "^VimMd", "", "")'), '_')
  let s:combos[name] = copy(a:groups)
  return name
endfunction

" [[col0, len, group], ...] (overlapping, priority ordered)
"   -> [[col0, len, group_or_combo], ...] (non overlapping)
function! vim_md#hl#flatten(sp) abort
  let spans = filter(copy(a:sp), 'v:val[1] > 0')
  if empty(spans)
    return []
  endif
  if len(spans) == 1
    return [copy(spans[0])]
  endif
  let pts = {}
  for s in spans
    let pts[s[0]] = 1
    let pts[s[0] + s[1]] = 1
  endfor
  let bounds = sort(map(keys(pts), 'str2nr(v:val)'), 'n')
  let out = []
  for k in range(len(bounds) - 1)
    let lo = bounds[k]
    let hi = bounds[k + 1]
    let gs = []
    for s in spans
      if s[0] <= lo && s[0] + s[1] >= hi && index(gs, s[2]) < 0
        call add(gs, s[2])
      endif
    endfor
    if empty(gs)
      continue
    endif
    let name = len(gs) == 1 ? gs[0] : s:combo(gs)
    if !empty(out) && out[-1][2] ==# name && out[-1][0] + out[-1][1] == lo
      let out[-1][1] += hi - lo
    else
      call add(out, [lo, hi - lo, name])
    endif
  endfor
  return out
endfunction

" hl: [[lnum, col, len, group], ...] (1-based lnum / byte col)
function! vim_md#hl#apply(buf, hl) abort
  if has('nvim')
    if !s:ns
      let s:ns = nvim_create_namespace('vim_md')
    endif
    call nvim_buf_clear_namespace(a:buf, s:ns, 0, -1)
    for [lnum, col, len, name] in a:hl
      call s:ensure(name)
      call nvim_buf_add_highlight(a:buf, s:ns, name, lnum - 1, col - 1, col - 1 + len)
    endfor
  else
    call prop_clear(1, max([1, getbufinfo(a:buf)[0].linecount]), {'bufnr': a:buf})
    for [lnum, col, len, name] in a:hl
      call s:ensure(name)
      if empty(prop_type_get(name))
        call prop_type_add(name, {'highlight': name, 'priority': 10})
      endif
      call prop_add(lnum, col, {'bufnr': a:buf, 'length': len, 'type': name})
    endfor
  endif
endfunction
