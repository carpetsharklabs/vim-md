" vim-md: rendered markdown preview inside Vim / Neovim.
"
" One preview window follows the markdown buffer you are editing: it re-renders
" (debounced) whenever the text changes and scrolls to match the cursor.

let s:state = {'buf': -1, 'src': -1, 'timer': -1, 'res': {}, 'width': 0, 'sync_idx': -1}

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

" ---------------------------------------------------------------- public API

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
  if !has('nvim') && !(has('textprop') && has('timers') && v:version >= 802)
    echohl ErrorMsg | echom 'vim-md: needs Vim 8.2+ with +textprop (or Neovim)' | echohl None
    return
  endif
  if !has('nvim') && &encoding !=# 'utf-8'
    echohl ErrorMsg | echom 'vim-md: requires ''encoding'' to be utf-8' | echohl None
    return
  endif
  let cur = bufnr('%')
  if cur == s:state.buf
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
  silent! autocmd! VimMd
endfunction

function! vim_md#refresh() abort
  call s:render_now()
  call s:sync(1)
endfunction

" ---------------------------------------------------------------- window

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
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted undolevels=-1
  setlocal nowrap nonumber norelativenumber nolist nospell nofoldenable
  setlocal signcolumn=no foldcolumn=1 colorcolumn= cursorline winfixwidth
  setlocal nomodifiable
  setlocal statusline=\ Markdown\ preview
  try
    silent keepalt file [Markdown\ Preview]
  catch
  endtry
  setlocal filetype=vim_md_preview
  let s:state.buf = bufnr('%')
  nnoremap <buffer><silent> q :<C-u>call vim_md#close()<CR>
  nnoremap <buffer><silent> <CR> :<C-u>call vim_md#follow()<CR>
  nnoremap <buffer><silent> gx :<C-u>call vim_md#follow()<CR>
  nnoremap <buffer><silent> ]] :<C-u>call vim_md#heading(1)<CR>
  nnoremap <buffer><silent> [[ :<C-u>call vim_md#heading(-1)<CR>
  call win_gotoid(cur)
endfunction

" ---------------------------------------------------------------- rendering

function! s:render_now() abort
  let win = s:preview_win()
  if win < 0 || s:state.src < 0 || !bufloaded(s:state.src)
    return
  endif
  let width = max([winwidth(win) - 2, 20])
  let s:state.width = winwidth(win)
  let res = vim_md#block#render(getbufline(s:state.src, 1, '$'), width)
  let b = s:state.buf
  call setbufvar(b, '&modifiable', 1)
  call setbufline(b, 1, empty(res.lines) ? [''] : res.lines)
  let total = getbufinfo(b)[0].linecount
  if total > len(res.lines) && total > 1
    silent! call deletebufline(b, max([len(res.lines), 1]) + 1, '$')
  endif
  call vim_md#hl#apply(b, res.hl)
  call setbufvar(b, '&modifiable', 0)
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

" ---------------------------------------------------------------- scroll sync

function! s:sync(force) abort
  let win = s:preview_win()
  if win < 0 || empty(s:state.res) || bufnr('%') != s:state.src
    return
  endif
  let map = s:state.res.src
  let ln = line('.')
  let idx = 1
  let k = 0
  for v in map
    let k += 1
    if v > ln
      break
    endif
    let idx = k
  endfor
  if !a:force && idx == s:state.sync_idx
    return
  endif
  let s:state.sync_idx = idx
  let h = winheight(win)
  let total = len(map)
  let top = min([max([1, idx - h / 2]), max([1, total - h + 1])])
  call win_execute(win, 'call winrestview({"lnum": ' . idx . ', "topline": ' . top . ', "col": 0})')
endfunction

" ---------------------------------------------------------------- autocmds

function! s:augroup() abort
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
endfunction

" ---------------------------------------------------------------- navigation

function! vim_md#heading(dir) abort
  let cur = line('.')
  let target = -1
  for h in get(s:state.res, 'headings', [])
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
  let lnum = line('.')
  let col = col('.')
  for lk in get(s:state.res, 'links', [])
    if lk[0] == lnum && col >= lk[1] && col < lk[1] + lk[2]
      return s:open_url(lk[3])
    endif
  endfor
  echo 'vim-md: no link under cursor'
endfunction

function! s:open_url(url) abort
  if a:url =~# '^#'
    let want = strpart(a:url, 1)
    for h in s:state.res.headings
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
    let dir = fnamemodify(bufname(s:state.src), ':p:h')
    let full = path =~# '^/' ? path : dir . '/' . path
    let w = bufwinid(s:state.src)
    if w > 0
      call win_gotoid(w)
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
