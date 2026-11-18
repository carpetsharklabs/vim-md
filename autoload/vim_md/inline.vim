" vim-md: inline markdown parser.
"
" vim_md#inline#parse(text) -> {'t': plain, 'sp': [[col0, len, group]], 'links': [[col0, len, url]]}
"
" Columns are 0-based byte offsets into `t`. Spans are ordered by priority
" (later spans override earlier ones when attributes collide).

let s:refs = {}
let s:fn_labels = {}
let s:fn_order = []

function! vim_md#inline#set_refs(refs) abort
  let s:refs = a:refs
endfunction

" Footnote labels defined in the document ({label: 1}); resets the numbering.
function! vim_md#inline#set_footnotes(labels) abort
  let s:fn_labels = a:labels
  let s:fn_order = []
endfunction

" Labels in the order they were first referenced (this is their number - 1).
function! vim_md#inline#footnote_order() abort
  return s:fn_order
endfunction

let s:sup = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹']

function! vim_md#inline#superscript(n) abort
  let out = ''
  for d in split(string(a:n), '\zs')
    let out .= s:sup[str2nr(d)]
  endfor
  return out
endfunction

let s:emoji = {
      \ 'tada': '🎉', 'rocket': '🚀', 'warning': '⚠️', 'white_check_mark': '✅', 'heavy_check_mark': '✔️',
      \ 'x': '❌', 'bulb': '💡', 'memo': '📝', 'fire': '🔥', 'sparkles': '✨', 'bug': '🐛', 'zap': '⚡',
      \ 'star': '⭐', 'eyes': '👀', 'smile': '😄', 'grin': '😁', 'joy': '😂', 'wink': '😉', 'heart': '❤️',
      \ 'thinking': '🤔', 'cry': '😢', 'sob': '😭', 'sunglasses': '😎', 'blush': '😊', 'slightly_smiling_face': '🙂',
      \ '+1': '👍', '-1': '👎', 'thumbsup': '👍', 'thumbsdown': '👎', 'clap': '👏', 'pray': '🙏', 'muscle': '💪',
      \ 'wave': '👋', 'ok_hand': '👌', 'point_right': '👉', 'point_left': '👈', 'raised_hands': '🙌',
      \ 'book': '📖', 'books': '📚', 'bookmark': '🔖', 'link': '🔗', 'lock': '🔒', 'key': '🔑', 'mag': '🔍',
      \ 'gear': '⚙️', 'wrench': '🔧', 'hammer': '🔨', 'package': '📦', 'computer': '💻', 'keyboard': '⌨️',
      \ 'bell': '🔔', 'bomb': '💣', 'boom': '💥', 'construction': '🚧', 'no_entry': '⛔', 'stop_sign': '🛑',
      \ 'question': '❓', 'exclamation': '❗', 'information_source': 'ℹ️', 'recycle': '♻️', 'trophy': '🏆',
      \ 'art': '🎨', 'chart_with_upwards_trend': '📈', 'hourglass': '⌛', 'calendar': '📅',
      \ 'earth_africa': '🌍', 'sunny': '☀️', 'cloud': '☁️', 'snowflake': '❄️', 'coffee': '☕', 'pizza': '🍕',
      \ 'beer': '🍺', 'brazil': '🇧🇷',
      \ }

function! vim_md#inline#parse(text) abort
  return s:parse(a:text)
endfunction

function! s:new() abort
  return {'t': '', 'sp': [], 'links': []}
endfunction

function! s:wordch(ch) abort
  return a:ch !=# '' && (a:ch =~# '\w' || char2nr(a:ch) > 127)
endfunction

" Append `inner` to `res`. `groups` cover the whole inner text and rank below
" the inner spans.
function! s:append(res, inner, groups) abort
  let off = strlen(a:res.t)
  let len = strlen(a:inner.t)
  if len > 0
    for g in a:groups
      call add(a:res.sp, [off, len, g])
    endfor
  endif
  for s in a:inner.sp
    call add(a:res.sp, [s[0] + off, s[1], s[2]])
  endfor
  for l in a:inner.links
    call add(a:res.links, [l[0] + off, l[1], l[2]])
  endfor
  let a:res.t .= a:inner.t
endfunction

function! s:lit(res, str, groups) abort
  let inner = s:new()
  let inner.t = a:str
  call s:append(a:res, inner, a:groups)
endfunction

" Like s:append but also records a link; the outer link sorts before inner ones.
function! s:add_link(res, inner, groups, url) abort
  let off = strlen(a:res.t)
  let len = strlen(a:inner.t)
  let idx = len(a:res.links)
  call s:append(a:res, a:inner, a:groups)
  if len > 0 && a:url !=# ''
    call insert(a:res.links, [off, len, a:url], idx)
  endif
endfunction

function! s:find_code_close(text, from, k) abort
  let j = a:from
  while 1
    let j = match(a:text, '`\+', j)
    if j < 0
      return -1
    endif
    let m = strlen(matchstr(a:text, '^`\+', j))
    if m == a:k
      return j
    endif
    let j += m
  endwhile
endfunction

" Index of the closing delimiter run (exactly `r` long) of char `c`, or -1.
function! s:find_close(text, from, c, r) abort
  let n = strlen(a:text)
  let j = a:from
  while j < n
    let ch = a:text[j]
    if ch ==# '\'
      let j += 2
      continue
    elseif ch ==# '`'
      let k = strlen(matchstr(a:text, '^`\+', j))
      let close = s:find_code_close(a:text, j + k, k)
      let j = close >= 0 ? close + k : j + k
      continue
    elseif ch ==# a:c
      let m = 0
      while a:text[j + m] ==# a:c
        let m += 1
      endwhile
      if m == a:r && j > a:from && a:text[j - 1] !~# '\s'
        if a:c !=# '_' || !s:wordch(a:text[j + m])
          return j
        endif
      endif
      let j += m
      continue
    endif
    let j += 1
  endwhile
  return -1
endfunction

function! s:dest_url(dest) abort
  let d = substitute(a:dest, '^\s*\|\s*$', '', 'g')
  if d =~# '^<'
    return matchstr(d, '^<\zs[^>]*\ze>')
  endif
  return matchstr(d, '^\S\+')
endfunction

" `i` points at '['. Returns {} or {'label', 'url', 'end'}.
function! s:match_link(text, i) abort
  let n = strlen(a:text)
  let depth = 0
  let j = a:i
  while j < n
    let c = a:text[j]
    if c ==# '\'
      let j += 2
      continue
    elseif c ==# '`'
      let k = strlen(matchstr(a:text, '^`\+', j))
      let close = s:find_code_close(a:text, j + k, k)
      let j = close >= 0 ? close + k : j + k
      continue
    elseif c ==# '['
      let depth += 1
    elseif c ==# ']'
      let depth -= 1
      if depth == 0
        break
      endif
    endif
    let j += 1
  endwhile
  if j >= n || depth != 0
    return {}
  endif
  let label = strpart(a:text, a:i + 1, j - a:i - 1)
  let after = j + 1
  if a:text[after] ==# '('
    let d = 0
    let k = after
    while k < n
      let c = a:text[k]
      if c ==# '\'
        let k += 2
        continue
      elseif c ==# '('
        let d += 1
      elseif c ==# ')'
        let d -= 1
        if d == 0
          break
        endif
      endif
      let k += 1
    endwhile
    if k >= n
      return {}
    endif
    return {'label': label, 'url': s:dest_url(strpart(a:text, after + 1, k - after - 1)), 'end': k + 1}
  elseif a:text[after] ==# '['
    let close = stridx(a:text, ']', after)
    if close > 0
      let ref = strpart(a:text, after + 1, close - after - 1)
      if ref ==# ''
        let ref = label
      endif
      return {'label': label, 'url': get(s:refs, tolower(ref), ''), 'end': close + 1}
    endif
  endif
  if has_key(s:refs, tolower(label))
    return {'label': label, 'url': s:refs[tolower(label)], 'end': after}
  endif
  return {}
endfunction

let s:entities = {'&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&nbsp;': ' ', '&#39;': "'", '&apos;': "'"}
let s:strip_tags = '^</\?\%(p\|div\|span\|b\|i\|u\|em\|strong\|small\|kbd\|sup\|sub\|mark\|center\|details\|summary\|a\|picture\|source\|h[1-6]\|ul\|ol\|li\|table\|tr\|td\|th\|thead\|tbody\|hr\|code\|pre\)\%(\s[^>]*\)\?/\?>'

function! s:parse(text) abort
  let res = s:new()
  let n = strlen(a:text)
  let i = 0
  while i < n
    let c = a:text[i]

    if c ==# '\'
      let nx = a:text[i + 1]
      if nx =~# '^[!-/:-@\[-`{-~]$'
        let res.t .= nx
        let i += 2
        continue
      endif

    elseif c ==# '`'
      let k = strlen(matchstr(a:text, '^`\+', i))
      let close = s:find_code_close(a:text, i + k, k)
      if close >= 0
        let code = substitute(strpart(a:text, i + k, close - i - k), "\n", ' ', 'g')
        if code =~# '^ .* $' && code =~# '[^ ]'
          let code = strpart(code, 1, strlen(code) - 2)
        endif
        call s:lit(res, code, ['VimMdCode'])
        let i = close + k
      else
        let res.t .= repeat('`', k)
        let i += k
      endif
      continue

    elseif c ==# '!' && a:text[i + 1] ==# '['
      let lk = s:match_link(a:text, i + 1)
      if !empty(lk)
        let alt = s:parse(lk.label)
        if alt.t ==# ''
          let alt.t = fnamemodify(lk.url, ':t')
          if alt.t ==# ''
            let alt.t = 'image'
          endif
        endif
        let img = s:new()
        let img.t = '◩ '
        call s:append(img, alt, [])
        call s:add_link(res, img, ['VimMdImage'], lk.url)
        let i = lk.end
        continue
      endif

    elseif c ==# '['
      let fm = matchstr(a:text, '^\[\^[^\]]\+\]', i)
      if fm !=# '' && has_key(s:fn_labels, strpart(fm, 2, strlen(fm) - 3))
        let label = strpart(fm, 2, strlen(fm) - 3)
        let idx = index(s:fn_order, label)
        if idx < 0
          call add(s:fn_order, label)
          let idx = len(s:fn_order) - 1
        endif
        call s:lit(res, vim_md#inline#superscript(idx + 1), ['VimMdFootnote'])
        let i += strlen(fm)
        continue
      endif
      let lk = s:match_link(a:text, i)
      if !empty(lk)
        let inner = s:parse(lk.label)
        call s:add_link(res, inner, ['VimMdLink'], lk.url)
        if get(g:, 'vim_md_show_urls', 0) && lk.url !=# '' && lk.url !=# inner.t
          call s:lit(res, ' (' . lk.url . ')', ['VimMdUrl'])
        endif
        let i = lk.end
        continue
      endif

    elseif c ==# '<'
      let m = matchstr(a:text, '^<\%(https\?\|ftp\|mailto\):[^ >]\+>', i)
      if m !=# ''
        let url = strpart(m, 1, strlen(m) - 2)
        let inner = s:new()
        let inner.t = substitute(url, '^mailto:', '', '')
        call s:add_link(res, inner, ['VimMdLink'], url)
        let i += strlen(m)
        continue
      endif
      let m = matchstr(a:text, '^<br\s*/\?>', i)
      if m !=# ''
        let res.t .= "\n"
        let i += strlen(m)
        continue
      endif
      let m = matchstr(a:text, '^<!--.\{-}-->', i)
      if m !=# ''
        let i += strlen(m)
        continue
      endif
      let m = matchstr(a:text, '^<img\s[^>]*>', i)
      if m !=# ''
        let alt = matchstr(m, 'alt=["'']\zs[^"'']*')
        let src = matchstr(m, 'src=["'']\zs[^"'']*')
        let img = s:new()
        let img.t = '◩ ' . (alt !=# '' ? alt : 'image')
        call s:add_link(res, img, ['VimMdImage'], src)
        let i += strlen(m)
        continue
      endif
      let m = matchstr(a:text, s:strip_tags, i)
      if m !=# ''
        let i += strlen(m)
        continue
      endif

    elseif c ==# ':' && get(g:, 'vim_md_emoji', 1)
      let m = matchstr(a:text, '^:[a-z0-9_+-]\+:', i)
      let e = m ==# '' ? '' : get(s:emoji, strpart(m, 1, strlen(m) - 2), '')
      if e !=# ''
        let res.t .= e
        let i += strlen(m)
        continue
      endif

    elseif c ==# '&'
      let m = matchstr(a:text, '^&\%(amp\|lt\|gt\|quot\|nbsp\|#39\|apos\);', i)
      if m !=# ''
        let res.t .= s:entities[m]
        let i += strlen(m)
        continue
      endif

    elseif c ==# 'h' && strpart(a:text, i, 8) =~# '^https\?://'
      let prev = i > 0 ? matchstr(a:text, '.\%' . (i + 1) . 'c') : ''
      if !s:wordch(prev)
        let url = matchstr(a:text, '^https\?://[^[:space:]<>]\+', i)
        let url = substitute(url, '[]),.;:!?*_~''"]\+$', '', '')
        let inner = s:new()
        let inner.t = url
        call s:add_link(res, inner, ['VimMdLink'], url)
        let i += strlen(url)
        continue
      endif

    elseif c ==# '~' && a:text[i + 1] ==# '~' && a:text[i + 2] !=# '~'
      let nxt = a:text[i + 2]
      if nxt !=# '' && nxt !~# '\s'
        let close = s:find_close(a:text, i + 2, '~', 2)
        if close >= 0
          call s:append(res, s:parse(strpart(a:text, i + 2, close - i - 2)), ['VimMdStrike'])
          let i = close + 2
          continue
        endif
      endif

    elseif c ==# '*' || c ==# '_'
      let r = 0
      while a:text[i + r] ==# c
        let r += 1
      endwhile
      let prev = i > 0 ? matchstr(a:text, '.\%' . (i + 1) . 'c') : ''
      let nxt = a:text[i + r]
      let ok = r <= 3 && nxt !=# '' && nxt !~# '\s'
      if ok && c ==# '_' && s:wordch(prev)
        let ok = 0
      endif
      if ok
        let close = s:find_close(a:text, i + r, c, r)
        if close >= 0
          let inner = s:parse(strpart(a:text, i + r, close - i - r))
          let groups = r == 1 ? ['VimMdItalic'] : r == 2 ? ['VimMdBold'] : ['VimMdBold', 'VimMdItalic']
          call s:append(res, inner, groups)
          let i = close + r
          continue
        endif
      endif
      let res.t .= repeat(c, r)
      let i += r
      continue
    endif

    let res.t .= c
    let i += 1
  endwhile
  return res
endfunction
