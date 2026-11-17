" vim-md: rendered markdown inside Vim / Neovim.
"
" Two modes:
"   preview  a split that follows the markdown buffer you are editing: it
"            re-renders (debounced) on every change and scrolls with the cursor.
"   view     the rendered document replaces the source in the *current* window
"            (read-only); toggling back restores the source, its cursor line and
"            the window options.

let s:state = {'buf': -1, 'src': -1, 'timer': -1, 'res': {}, 'width': 0, 'sync_idx': -1}
let s:view = {}

" Window-local options we override and restore in view mode.
let s:win_opts = ['wrap', 'number', 'relativenumber', 'list', 'spell', 'foldenable',
      \ 'signcolumn', 'foldcolumn', 'colorcolumn', 'cursorline']

function! s:opt(name, default) abort
  return get(g:, 'vim_md_' . a:name, a:default)
endfunction

function! s:is_md(buf) abort
  return index(s:opt('filetypes', ['markdown']), getbufvar(a:buf, '&filetype')) >= 0
endfunction

function! s:preview_win() abort
  if s:state.buf < 0 || !bufexists(s:state.buf)
    return -1
  endif
  return bufwinid(s:state.buf)
endfunction

function! s:check() abort
  if !has('nvim') && !(has('textprop') && has('timers') && v:version >= 802)
    echohl ErrorMsg | echom 'vim-md: needs Vim 8.2+ with +textprop (or Neovim)' | echohl None
    return 0
  endif
  if !has('nvim') && &encoding !=# 'utf-8'
    echohl ErrorMsg | echom 'vim-md: requires ''encoding'' to be utf-8' | echohl None
    return 0
  endif
  return 1
endfunction

" ---------------------------------------------------------------- shared helpers

" The state (preview or view) whose buffer is current; used by navigation.
function! s:ctx() abort
  if !empty(s:view) && bufnr('%') == s:view.buf
    return s:view
  endif
  return s:state
endfunction

function! s:render_buf(src, width) abort
  return vim_md#block#render(getbufline(a:src, 1, '$'), max([a:width, 20]), 1)
endfunction

" Replace the contents (text + highlights) of the read-only render buffer.
function! s:fill(buf, res) abort
  call setbufvar(a:buf, '&modifiable', 1)
  call setbufline(a:buf, 1, empty(a:res.lines) ? [''] : a:res.lines)
  let total = getbufinfo(a:buf)[0].linecount
  if total > len(a:res.lines) && total > 1
    silent! call deletebufline(a:buf, max([len(a:res.lines), 1]) + 1, '$')
  endif
  call vim_md#hl#apply(a:buf, a:res.hl)
  call setbufvar(a:buf, '&modifiable', 0)
endfunction

" Rendered line index that corresponds to source line `ln`.
function! s:map_idx(res, ln) abort
  let idx = 1
  let k = 0
  for v in a:res.src
    let k += 1
    if v > a:ln
      break
    endif
    let idx = k
  endfor
  return idx
endfunction

" Put cursor on rendered line `idx`, roughly centered.
function! s:place(win, res, idx) abort
  let h = winheight(a:win)
  let total = len(a:res.src)
  let top = min([max([1, a:idx - h / 2]), max([1, total - h + 1])])
  call win_execute(a:win, 'call winrestview({"lnum": ' . a:idx . ', "topline": ' . top . ', "col": 0})')
endfunction

" Options for the current window (the render window).
function! s:setup_win() abort
  setlocal nowrap nonumber norelativenumber nolist nospell nofoldenable
  setlocal signcolumn=no foldcolumn=0 colorcolumn= cursorline
endfunction

function! s:setup_buf(name, ft) abort
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted undolevels=-1 nomodifiable
  try
    execute 'silent keepalt file' fnameescape(a:name)
  catch
  endtry
  execute 'setlocal filetype=' . a:ft
  nnoremap <buffer><silent> <CR> :<C-u>call vim_md#follow()<CR>
  nnoremap <buffer><silent> gx :<C-u>call vim_md#follow()<CR>
  nnoremap <buffer><silent> ]] :<C-u>call vim_md#heading(1)<CR>
  nnoremap <buffer><silent> [[ :<C-u>call vim_md#heading(-1)<CR>
endfunction

" ---------------------------------------------------------------- preview (split)

function! vim_md#is_open() abort
  return s:preview_win() > 0
endfunction

function! vim_md#toggle() abort
  if vim_md#is_open()
    call vim_md#close()
  else
    call vim_md#open()
  endif
endfunction

function! vim_md#open() abort
  if !s:check()
    return
  endif
  let cur = bufnr('%')
  if cur == s:state.buf || (!empty(s:view) && cur == s:view.buf)
    return
  endif
  if s:state.buf >= 0 && !bufexists(s:state.buf)
    let s:state.buf = -1
  endif
  call vim_md#hl#setup()
  let s:state.src = cur
  call s:augroup()
  if s:preview_win() < 0
    call s:create_window()
  endif
  call s:render_now()
  call s:sync(1)
endfunction

function! vim_md#close() abort
  if s:state.buf >= 0 && bufexists(s:state.buf)
    silent! execute 'bwipeout' s:state.buf
  endif
  call s:stop_timer()
  let s:state.buf = -1
  let s:state.res = {}
  if empty(s:view)
    silent! autocmd! VimMd
  endif
endfunction

function! vim_md#refresh() abort
  call s:render_now()
  call s:sync(1)
endfunction

function! s:create_window() abort
  let cur = win_getid()
  let pos = s:opt('position', 'right')
  let size = s:opt('size', 0)
  if pos ==# 'left' || pos ==# 'right'
    let cmd = (pos ==# 'left' ? 'leftabove' : 'rightbelow') . ' vertical ' . (size ? size : winwidth(0) / 2) . 'new'
  else
    let cmd = (pos ==# 'above' ? 'leftabove' : 'rightbelow') . ' ' . (size ? size : winheight(0) / 2) . 'new'
  endif
  execute 'silent keepalt' cmd
  call s:setup_win()
  setlocal winfixwidth statusline=\ Markdown\ preview
  call s:setup_buf('[Markdown Preview]', 'vim_md_preview')
  let s:state.buf = bufnr('%')
  nnoremap <buffer><silent> q :<C-u>call vim_md#close()<CR>
  call win_gotoid(cur)
endfunction

function! s:render_now() abort
  let win = s:preview_win()
  if win < 0 || s:state.src < 0 || !bufloaded(s:state.src)
    return
  endif
  let s:state.width = winwidth(win)
  let res = s:render_buf(s:state.src, winwidth(win) - 2)
  call s:fill(s:state.buf, res)
  let s:state.res = res
endfunction

function! s:stop_timer() abort
  if s:state.timer != -1
    call timer_stop(s:state.timer)
    let s:state.timer = -1
  endif
endfunction

function! s:schedule() abort
  call s:stop_timer()
  let s:state.timer = timer_start(s:opt('debounce', 120), function('s:on_timer'))
endfunction

function! s:on_timer(id) abort
  let s:state.timer = -1
  try
    call s:render_now()
    call s:sync(1)
  catch
    echohl ErrorMsg | echom 'vim-md: ' . v:exception | echohl None
  endtry
endfunction

function! s:sync(force) abort
  let win = s:preview_win()
  if win < 0 || empty(s:state.res) || bufnr('%') != s:state.src
    return
  endif
  let idx = s:map_idx(s:state.res, line('.'))
  if !a:force && idx == s:state.sync_idx
    return
  endif
  let s:state.sync_idx = idx
  call s:place(win, s:state.res, idx)
endfunction

" ---------------------------------------------------------------- view (same window)

function! vim_md#view_is_open() abort
  return !empty(s:view) && bufexists(s:view.buf) && bufnr('%') == s:view.buf
endfunction

function! vim_md#view_toggle() abort
  if vim_md#view_is_open()
    call vim_md#view_close()
  else
    call vim_md#view_open()
  endif
endfunction

function! vim_md#view_open() abort
  if !s:check()
    return
  endif
  let cur = bufnr('%')
  if vim_md#view_is_open() || cur == s:state.buf
    return
  endif
  call vim_md#hl#setup()
  call s:augroup()
  let win = win_getid()
  let ln = line('.')
  let saved = {}
  for o in s:win_opts
    let saved[o] = getwinvar(win, '&' . o)
  endfor
  let res = s:render_buf(cur, winwidth(0) - 2)
  " 'hide' keeps a modified source buffer loaded; 'keepalt' leaves # untouched.
  silent keepalt hide enew
  call s:setup_win()
  call s:setup_buf('[Markdown View]', 'vim_md_view')
  nnoremap <buffer><silent> q :<C-u>call vim_md#view_close()<CR>
  let s:view = {'buf': bufnr('%'), 'src': cur, 'win': win, 'res': res, 'saved': saved, 'width': winwidth(0)}
  autocmd VimMd BufWinLeave <buffer> call s:view_leave()
  autocmd VimMd BufWipeout <buffer> call s:view_gone()
  call s:fill(s:view.buf, res)
  call s:place(win, res, s:map_idx(res, ln))
endfunction

function! vim_md#view_close() abort
  if !vim_md#view_is_open()
    return
  endif
  let v = s:view
  let sl = get(v.res.src, line('.') - 1, 1)
  if bufexists(v.src)
    execute 'silent keepalt hide buffer' v.src
  else
    silent keepalt hide enew
  endif
  call cursor(sl, 1)
  normal! zz
endfunction

" Restore the window options when the view buffer leaves its window (also covers
" `:e other` or `:q` inside the view).
function! s:view_leave() abort
  if empty(s:view)
    return
  endif
  for [o, val] in items(s:view.saved)
    silent! call setwinvar(s:view.win, '&' . o, val)
  endfor
endfunction

function! s:view_gone() abort
  let s:view = {}
  if s:state.buf < 0
    silent! autocmd! VimMd
  endif
endfunction

function! s:view_rerender() abort
  if !vim_md#view_is_open() || !bufexists(s:view.src) || winwidth(0) == s:view.width
    return
  endif
  let sl = get(s:view.res.src, line('.') - 1, 1)
  let res = s:render_buf(s:view.src, winwidth(0) - 2)
  let s:view.res = res
  let s:view.width = winwidth(0)
  call s:fill(s:view.buf, res)
  call s:place(win_getid(), res, s:map_idx(res, sl))
endfunction

" ---------------------------------------------------------------- autocmds

function! s:augroup() abort
  " Idempotent: re-running `autocmd!` would also drop the view's buffer-local ones.
  if exists('#VimMd#BufEnter')
    return
  endif
  augroup VimMd
    autocmd!
    autocmd TextChanged,TextChangedI,TextChangedP,InsertLeave,BufWritePost * call s:on_change()
    autocmd CursorMoved,CursorMovedI * call s:sync(0)
    autocmd BufEnter * call s:on_buf_enter()
    autocmd VimResized * call s:on_resize()
    if exists('##WinResized')
      autocmd WinResized * call s:on_resize()
    endif
    autocmd ColorScheme * call vim_md#hl#setup() | call s:schedule()
  augroup END
endfunction

function! s:on_change() abort
  if bufnr('%') == s:state.src
    call s:schedule()
  endif
endfunction

function! s:on_buf_enter() abort
  if s:state.buf < 0
    return
  endif
  if !bufexists(s:state.buf)
    " The preview window was closed by hand (:q): tear everything down.
    call vim_md#close()
    return
  endif
  let b = bufnr('%')
  if b == s:state.buf || b == s:state.src || !s:opt('follow', 1) || !s:is_md(b)
    return
  endif
  let s:state.src = b
  let s:state.sync_idx = -1
  call s:schedule()
endfunction

function! s:on_resize() abort
  let win = s:preview_win()
  if win > 0 && winwidth(win) != s:state.width
    call s:schedule()
  endif
  call s:view_rerender()
endfunction

" ---------------------------------------------------------------- navigation

function! vim_md#heading(dir) abort
  let cur = line('.')
  let target = -1
  for h in get(s:ctx().res, 'headings', [])
    if a:dir > 0 && h[0] > cur
      let target = h[0]
      break
    elseif a:dir < 0 && h[0] < cur
      let target = h[0]
    endif
  endfor
  if target > 0
    call cursor(target, 1)
  endif
endfunction

function! s:slug(text) abort
  let s = tolower(a:text)
  let s = substitute(s, '[!"#$%&''()*+,./:;<=>?@[\\\]^`{|}~]', '', 'g')
  return substitute(s, ' ', '-', 'g')
endfunction

function! vim_md#follow() abort
  let st = s:ctx()
  let lnum = line('.')
  let col = col('.')
  for lk in get(st.res, 'links', [])
    if lk[0] == lnum && col >= lk[1] && col < lk[1] + lk[2]
      return s:open_url(lk[3], st)
    endif
  endfor
  echo 'vim-md: no link under cursor'
endfunction

function! s:open_url(url, st) abort
  if a:url =~# '^#'
    let want = strpart(a:url, 1)
    for h in a:st.res.headings
      if s:slug(h[2]) ==# want
        call cursor(h[0], 1)
        return
      endif
    endfor
    echo 'vim-md: heading not found: ' . want
  elseif a:url =~# '^\a[a-zA-Z0-9+.-]*:'
    call s:open_external(a:url)
  else
    let path = substitute(a:url, '#.*$', '', '')
    let dir = fnamemodify(bufname(a:st.src), ':p:h')
    let full = path =~# '^/' ? path : dir . '/' . path
    if a:st is s:view
      call vim_md#view_close()
    else
      let w = bufwinid(a:st.src)
      if w > 0
        call win_gotoid(w)
      endif
    endif
    execute 'edit' fnameescape(full)
  endif
endfunction

function! s:open_external(url) abort
  if has('mac')
    let cmd = ['open', a:url]
  elseif has('win32')
    let cmd = ['cmd', '/c', 'start', '', a:url]
  else
    let cmd = ['xdg-open', a:url]
  endif
  if has('nvim')
    call jobstart(cmd, {'detach': 1})
  else
    call job_start(cmd, {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
  endif
endfunction
