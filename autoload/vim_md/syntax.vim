" vim-md: syntax highlighting for fenced code blocks.
"
" The code is loaded into a scratch buffer that is displayed in a hidden popup
" (Vim) / unfocusable float (Neovim), so no visible window is touched. The
" buffer's 'syntax' is set and every byte is classified with synID().
"
" vim_md#syntax#spans(lines, lang) -> per line: [[col0, len, group], ...]
" Returns [] when highlighting is disabled/unavailable.

let s:alias = {
      \ 'js': 'javascript', 'jsx': 'javascript', 'mjs': 'javascript',
      \ 'ts': 'typescript', 'tsx': 'typescript',
      \ 'py': 'python', 'python3': 'python',
      \ 'shell': 'sh', 'bash': 'sh', 'console': 'sh', 'shellsession': 'sh',
      \ 'yml': 'yaml', 'c++': 'cpp', 'rs': 'rust', 'md': 'markdown',
      \ 'vimscript': 'vim', 'viml': 'vim', 'nvim': 'vim',
      \ 'golang': 'go', 'rb': 'ruby', 'kt': 'kotlin', 'csharp': 'cs',
      \ 'jsonc': 'json', 'json5': 'json', 'docker': 'dockerfile',
      \ 'powershell': 'ps1', 'text': '', 'txt': '', 'plain': '', 'plaintext': '',
      \ }

let s:ft_ok = {}
let s:cache = {}
let s:out = []

function! s:ft(lang) abort
  let l = tolower(a:lang)
  let l = get(s:alias, l, l)
  if l ==# '' || l !~# '^[a-z0-9_+.-]\+$'
    return ''
  endif
  if !has_key(s:ft_ok, l)
    let s:ft_ok[l] = !empty(globpath(&runtimepath, 'syntax/' . l . '.vim'))
  endif
  return s:ft_ok[l] ? l : ''
endfunction

" Runs inside the scratch window; fills s:out.
function! vim_md#syntax#collect() abort
  let s:out = []
  for lnum in range(1, line('$'))
    let n = strlen(getline(lnum))
    let spans = []
    let cur = ''
    let start = 1
    for c in range(1, n + 1)
      let g = ''
      if c <= n
        let id = synID(lnum, c, 1)
        if id
          let g = synIDattr(synIDtrans(id), 'name')
          " Normal has its own background, which would punch a hole in the code block.
          if g ==# 'Normal'
            let g = ''
          endif
        endif
      endif
      if g !=# cur
        if cur !=# ''
          call add(spans, [start - 1, c - start, cur])
        endif
        let cur = g
        let start = c
      endif
    endfor
    call add(s:out, spans)
  endfor
endfunction

function! s:scratch_win(buf) abort
  if has('nvim')
    return nvim_open_win(a:buf, v:false, {
          \ 'relative': 'editor', 'row': 0, 'col': 0, 'width': 20, 'height': 3,
          \ 'focusable': v:false, 'style': 'minimal', 'noautocmd': v:true})
  endif
  return popup_create(a:buf, {'hidden': 1, 'line': 1, 'col': 1, 'minwidth': 20, 'minheight': 3})
endfunction

function! s:close_win(win) abort
  if has('nvim')
    call nvim_win_close(a:win, v:true)
  else
    call popup_close(a:win)
  endif
endfunction

function! vim_md#syntax#spans(lines, lang) abort
  if !get(g:, 'vim_md_code_syntax', 1) || !exists('g:syntax_on') || empty(a:lines)
    return []
  endif
  let ft = s:ft(a:lang)
  if ft ==# ''
    return []
  endif
  let key = ft . "\n" . join(a:lines, "\n")
  if has_key(s:cache, key)
    return s:cache[key]
  endif
  let result = []
  let buf = bufadd('')
  let win = 0
  try
    call bufload(buf)
    call setbufvar(buf, '&buftype', 'nofile')
    call setbufvar(buf, '&swapfile', 0)
    call setbufvar(buf, '&bufhidden', 'hide')
    call setbufline(buf, 1, a:lines)
    let win = s:scratch_win(buf)
    call win_execute(win, 'setlocal syntax=' . ft)
    call win_execute(win, 'call vim_md#syntax#collect()')
    let result = s:out
  catch
    let result = []
  finally
    if win
      silent! call s:close_win(win)
    endif
    silent! execute 'bwipeout!' buf
  endtry
  if len(s:cache) > 200
    let s:cache = {}
  endif
  let s:cache[key] = result
  return result
endfunction
