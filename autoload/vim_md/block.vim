" vim-md: block level markdown layout.
"
" vim_md#block#render(lines, width) -> {
"   'lines':    [text, ...],
"   'hl':       [[lnum, col, len, group], ...],   " 1-based, non overlapping
"   'links':    [[lnum, col, len, url], ...],
"   'src':      [source lnum for every rendered line],
"   'headings': [[lnum, level, text], ...],
" }

let s:fence_re = '^\s\{0,3}\(`\{3,}\|\~\{3,}\)'
let s:hr_re = '^\s\{0,3}\([-*_]\)\%(\s*\1\)\{2,}\s*$'
let s:atx_re = '^\s\{0,3}\(#\{1,6}\)\%(\s\+\(.*\)\)\=$'

let s:alerts = {
      \ 'NOTE': ['VimMdNote', '● '],
      \ 'TIP': ['VimMdTip', '✦ '],
      \ 'IMPORTANT': ['VimMdImportant', '◆ '],
      \ 'WARNING': ['VimMdWarning', '▲ '],
      \ 'CAUTION': ['VimMdCaution', '✖ '],
      \ }

function! vim_md#block#render(lines, width) abort
  let lines = map(copy(a:lines), 'substitute(v:val, "\t", "    ", "g")')
  let nums = range(1, len(lines))
  call vim_md#inline#set_refs(s:collect_refs(lines))
  let out = s:blocks(lines, nums, a:width, {'top': 1, 'item': 0, 'depth': 0})
  return s:finish(out)
endfunction

function! s:finish(out) abort
  let r = {'lines': [], 'hl': [], 'links': [], 'src': [], 'headings': []}
  let ln = 0
  for l in a:out
    let ln += 1
    call add(r.lines, l.t)
    call add(r.src, get(l, 'src', 1))
    for [col, len, name] in vim_md#hl#flatten(l.sp)
      call add(r.hl, [ln, col + 1, len, name])
    endfor
    for lk in l.links
      call add(r.links, [ln, lk[0] + 1, lk[1], lk[2]])
    endfor
    if has_key(l, 'h')
      call add(r.headings, [ln, l.h[0], l.h[1]])
    endif
  endfor
  return r
endfunction

function! s:collect_refs(lines) abort
  let refs = {}
  let in_fence = ''
  for l in a:lines
    let f = matchstr(l, s:fence_re)
    if f !=# ''
      let ch = f =~# '`' ? '`' : '~'
      if in_fence ==# ''
        let in_fence = ch
      elseif in_fence ==# ch
        let in_fence = ''
      endif
      continue
    endif
    if in_fence ==# ''
      let m = matchlist(l, '^\s\{0,3}\[\([^\]]\+\)\]:\s*<\=\(\S\+\)')
      if !empty(m)
        let refs[tolower(m[1])] = substitute(m[2], '>$', '', '')
      endif
    endif
  endfor
  return refs
endfunction

" ---------------------------------------------------------------- helpers

function! s:line(t, sp) abort
  return {'t': a:t, 'sp': a:sp, 'links': []}
endfunction

function! s:shift(l, off) abort
  for s in a:l.sp
    let s[0] += a:off
  endfor
  for k in a:l.links
    let k[0] += a:off
  endfor
endfunction

" Prepend text to rendered lines (first line gets `first`, the rest `rest`).
function! s:prefix(lines, first, rest, fgroup, rgroup) abort
  let k = 0
  for l in a:lines
    let p = k == 0 ? a:first : a:rest
    let g = k == 0 ? a:fgroup : a:rgroup
    let pl = strlen(p)
    call s:shift(l, pl)
    let l.t = p . l.t
    if g !=# '' && pl > 0
      call insert(l.sp, [0, pl, g], 0)
    endif
    let k += 1
  endfor
endfunction

function! s:is_hr(line) abort
  return a:line =~# s:hr_re
endfunction

function! s:item_start(line) abort
  let m = matchlist(a:line, '^\(\s*\)\([-*+]\)\%(\(\s\+\)\|$\)')
  if !empty(m)
    let sp = strlen(m[3])
    let sp = (sp == 0 || sp > 4) ? 1 : sp
    return {'indent': strlen(m[1]), 'ordered': 0, 'num': 0, 'marker': m[2], 'coff': strlen(m[1]) + 1 + sp}
  endif
  let m = matchlist(a:line, '^\(\s*\)\(\d\{1,9}\)\([.)]\)\%(\(\s\+\)\|$\)')
  if !empty(m)
    let sp = strlen(m[4])
    let sp = (sp == 0 || sp > 4) ? 1 : sp
    return {'indent': strlen(m[1]), 'ordered': 1, 'num': str2nr(m[2]), 'marker': m[3], 'coff': strlen(m[1]) + strlen(m[2]) + 1 + sp}
  endif
  return {}
endfunction

function! s:split_row(line) abort
  let l = substitute(a:line, '^\s*\|\s*$', '', 'g')
  let l = substitute(l, '^|', '', '')
  let l = substitute(l, '\\\@<!|$', '', '')
  let out = []
  for c in split(l, '\\\@<!|', 1)
    let c = substitute(c, '^\s*\|\s*$', '', 'g')
    call add(out, substitute(c, '\\|', '|', 'g'))
  endfor
  return out
endfunction

function! s:is_delim_row(line) abort
  if a:line !~# '-'
    return 0
  endif
  for c in s:split_row(a:line)
    if c !~# '^:\=-\+:\=$'
      return 0
    endif
  endfor
  return 1
endfunction

function! s:is_table_start(lines, j) abort
  if a:j + 1 >= len(a:lines) || a:lines[a:j] !~# '|'
    return 0
  endif
  if !s:is_delim_row(a:lines[a:j + 1])
    return 0
  endif
  return len(s:split_row(a:lines[a:j])) == len(s:split_row(a:lines[a:j + 1]))
endfunction

" Does this line begin a block that can interrupt a paragraph?
function! s:starts_block(line) abort
  return a:line =~# s:fence_re
        \ || a:line =~# s:atx_re
        \ || a:line =~# '^\s\{0,3}>'
        \ || a:line =~# '^\s*<!--'
        \ || s:is_hr(a:line)
        \ || !empty(s:item_start(a:line))
endfunction

" Word-wrap an inline result to `width` display cells.
function! s:wrap(inl, width) abort
  let t = a:inl.t
  let width = max([a:width, 1])
  let ranges = []
  let ca = -1
  let cb = -1
  let pos = 0
  while 1
    let ws = match(t, '[^ \t\n]', pos)
    if ws < 0
      break
    endif
    let we = matchend(t, '[^ \t\n]\+', ws)
    if ca < 0
      let ca = ws
      let cb = we
    elseif strpart(t, pos, ws - pos) =~# "\n" || strdisplaywidth(strpart(t, ca, we - ca)) > width
      call add(ranges, [ca, cb])
      let ca = ws
      let cb = we
    else
      let cb = we
    endif
    let pos = we
  endwhile
  if ca >= 0
    call add(ranges, [ca, cb])
  endif
  let out = []
  for [a, b] in ranges
    let l = s:line(strpart(t, a, b - a), [])
    for s in a:inl.sp
      let s0 = max([s[0], a])
      let e0 = min([s[0] + s[1], b])
      if e0 > s0
        call add(l.sp, [s0 - a, e0 - s0, s[2]])
      endif
    endfor
    for k in a:inl.links
      let s0 = max([k[0], a])
      let e0 = min([k[0] + k[1], b])
      if e0 > s0
        call add(l.links, [s0 - a, e0 - s0, k[2]])
      endif
    endfor
    call add(out, l)
  endfor
  return out
endfunction

function! s:lerp(sn, en, k, n) abort
  return min([a:en, a:sn + ((a:en - a:sn + 1) * a:k) / max([a:n, 1])])
endfunction

" ---------------------------------------------------------------- renderers

function! s:render_code(content, label, width, ft) abort
  let maxw = 0
  for l in a:content
    let maxw = max([maxw, strdisplaywidth(l)])
  endfor
  let w = max([a:width, maxw + 2])
  let hl = vim_md#syntax#spans(a:content, a:ft)
  let out = []
  let head = ' ' . a:label
  let h = s:line(head . repeat(' ', w - strdisplaywidth(head)), [[0, w, 'VimMdCodeBlock']])
  if a:label !=# ''
    call add(h.sp, [1, strlen(a:label), 'VimMdCodeLang'])
  endif
  call add(out, h)
  for k in range(len(a:content))
    let t = ' ' . a:content[k]
    let pad = w - strdisplaywidth(t)
    let l = s:line(t . repeat(' ', pad), [[0, strlen(t) + pad, 'VimMdCodeBlock']])
    if k < len(hl)
      for sp in hl[k]
        call add(l.sp, [sp[0] + 1, sp[1], sp[2]])
      endfor
    endif
    call add(out, l)
  endfor
  call add(out, s:line(repeat(' ', w), [[0, w, 'VimMdCodeBlock']]))
  return out
endfunction

function! s:render_heading(level, text, width) abort
  let icons = get(g:, 'vim_md_heading_icons', ['', '', '▌ ', '▸ ', '· ', '· '])
  let icon = get(icons, a:level - 1, '')
  let inl = vim_md#inline#parse(a:text)
  let wl = s:wrap(inl, a:width - strdisplaywidth(icon))
  if empty(wl)
    return []
  endif
  let grp = 'VimMdH' . a:level
  for l in wl
    call insert(l.sp, [0, strlen(l.t), 'VimMdBold'], 0)
    call insert(l.sp, [0, strlen(l.t), grp], 1)
  endfor
  if icon !=# ''
    call s:prefix(wl, icon, repeat(' ', strdisplaywidth(icon)), grp, '')
  endif
  let wl[0].h = [a:level, substitute(substitute(inl.t, "\n", ' ', 'g'), '^\s*\|\s*$', '', 'g')]
  if a:level <= 2
    let ch = a:level == 1 ? '═' : '─'
    call add(wl, s:line(repeat(ch, a:width), [[0, strlen(ch) * a:width, grp]]))
  endif
  return wl
endfunction

function! s:border(widths, l, m, r) abort
  return a:l . join(map(copy(a:widths), 'repeat("─", v:val + 2)'), a:m) . a:r
endfunction

function! s:render_table(rows, aligns, width) abort
  let nc = len(a:aligns)
  let cells = []
  for r in range(len(a:rows))
    let row = []
    for c in range(nc)
      call add(row, vim_md#inline#parse(get(a:rows[r], c, '')))
    endfor
    call add(cells, row)
  endfor
  let widths = repeat([1], nc)
  let minw = repeat([3], nc)
  for row in cells
    for c in range(nc)
      let segw = 0
      let wordw = 0
      for seg in split(row[c].t, "\n")
        let seg = substitute(seg, '^\s*\|\s*$', '', 'g')
        let segw = max([segw, strdisplaywidth(seg)])
        for word in split(seg, '\s\+')
          let wordw = max([wordw, strdisplaywidth(word)])
        endfor
      endfor
      let widths[c] = max([widths[c], segw])
      let minw[c] = max([minw[c], wordw])
    endfor
  endfor
  let total = 3 * nc + 1
  for w in widths
    let total += w
  endfor
  while total > a:width
    let idx = -1
    for c in range(nc)
      if widths[c] > minw[c] && (idx < 0 || widths[c] > widths[idx])
        let idx = c
      endif
    endfor
    if idx < 0
      break
    endif
    let widths[idx] -= 1
    let total -= 1
  endwhile

  let bar = 'VimMdTableBorder'
  let out = []
  let top = s:border(widths, '┌', '┬', '┐')
  call add(out, s:line(top, [[0, strlen(top), bar]]))
  for r in range(len(cells))
    let wrapped = []
    let height = 1
    for c in range(nc)
      let wl = s:wrap(cells[r][c], widths[c])
      call add(wrapped, wl)
      let height = max([height, len(wl)])
    endfor
    for h in range(height)
      let t = '│'
      let l = s:line('', [[0, 3, bar]])
      for c in range(nc)
        let cl = h < len(wrapped[c]) ? wrapped[c][h] : s:line('', [])
        let pad = max([widths[c] - strdisplaywidth(cl.t), 0])
        let al = a:aligns[c]
        let lp = al ==# 'right' ? pad : al ==# 'center' ? pad / 2 : 0
        let rp = pad - lp
        let t .= ' ' . repeat(' ', lp)
        let off = strlen(t)
        call s:shift(cl, off)
        if r == 0 && cl.t !=# ''
          call add(l.sp, [off, strlen(cl.t), 'VimMdBold'])
        endif
        call extend(l.sp, cl.sp)
        call extend(l.links, cl.links)
        let t .= cl.t . repeat(' ', rp) . ' '
        call add(l.sp, [strlen(t), 3, bar])
        let t .= '│'
      endfor
      let l.t = t
      call add(out, l)
    endfor
    if r == 0
      let sep = s:border(widths, '├', '┼', '┤')
      call add(out, s:line(sep, [[0, strlen(sep), bar]]))
    endif
  endfor
  let bot = s:border(widths, '└', '┴', '┘')
  call add(out, s:line(bot, [[0, strlen(bot), bar]]))
  return out
endfunction

" Returns [lines, next_index].
function! s:render_list(lines, nums, i, width, ctx) abort
  let n = len(a:lines)
  let first = s:item_start(a:lines[a:i])
  let items = []
  let j = a:i
  while 1
    let st = s:item_start(a:lines[j])
    let ilines = [strpart(a:lines[j], st.coff)]
    let inums = [a:nums[j]]
    let k = j + 1
    let pend = []
    let last = j
    while k < n
      let l = a:lines[k]
      if l =~# '^\s*$'
        call add(pend, k)
        let k += 1
        continue
      endif
      let ind = strlen(matchstr(l, '^\s*'))
      if ind > st.indent && !s:is_hr(l)
        for p in pend
          call add(ilines, '')
          call add(inums, a:nums[p])
        endfor
        let pend = []
        call add(ilines, strpart(l, min([ind, st.coff])))
        call add(inums, a:nums[k])
        let last = k
      elseif empty(pend) && !s:starts_block(l)
        call add(ilines, substitute(l, '^\s*', '', ''))
        call add(inums, a:nums[k])
        let last = k
      else
        break
      endif
      let k += 1
    endwhile
    call add(items, {'st': st, 'lines': ilines, 'nums': inums})
    let q = last + 1
    while q < n && a:lines[q] =~# '^\s*$'
      let q += 1
    endwhile
    let nx = q < n ? s:item_start(a:lines[q]) : {}
    if !empty(nx) && nx.ordered == first.ordered && nx.indent >= first.indent && !s:is_hr(a:lines[q])
      let j = q
    else
      let j = last + 1
      break
    endif
  endwhile

  let digits = 0
  if first.ordered
    let digits = strlen(first.num + len(items) - 1)
  endif
  let out = []
  let idx = 0
  for it in items
    let task = matchlist(it.lines[0], '^\[\([ xX]\)\]\%(\s\+\|$\)')
    let mgroup = 'VimMdBullet'
    if !empty(task)
      let it.lines[0] = strpart(it.lines[0], strlen(task[0]))
      let marker = task[1] ==# ' ' ? '☐' : '☑'
      let mgroup = task[1] ==# ' ' ? 'VimMdCheck' : 'VimMdChecked'
    elseif first.ordered
      let marker = printf('%*d', digits, first.num + idx) . it.st.marker
    else
      let marker = ['•', '◦', '▪'][a:ctx.depth % 3]
    endif
    let mw = strdisplaywidth(marker)
    let inner = s:blocks(it.lines, it.nums, a:width - mw - 1, {'top': 0, 'item': 1, 'depth': a:ctx.depth + 1})
    if empty(inner)
      let inner = [s:line('', [])]
      let inner[0].src = it.nums[0]
    endif
    call s:prefix(inner, marker . ' ', repeat(' ', mw + 1), mgroup, '')
    call extend(out, inner)
    let idx += 1
  endfor
  return [out, j]
endfunction

function! s:render_quote(lines, nums, i, width, ctx) abort
  let n = len(a:lines)
  let q = []
  let qn = []
  let j = a:i
  while j < n
    let l = a:lines[j]
    if l =~# '^\s\{0,3}>'
      call add(q, substitute(l, '^\s\{0,3}>\s\=', '', ''))
    elseif l !~# '^\s*$' && !empty(q) && q[-1] !~# '^\s*$' && !s:starts_block(l) && !s:is_table_start(a:lines, j)
      call add(q, l)
    else
      break
    endif
    call add(qn, a:nums[j])
    let j += 1
  endwhile
  let group = 'VimMdQuote'
  let title = {}
  let am = matchlist(q[0], '^\[!\(\u\+\)\]\s*$')
  if !empty(am) && has_key(s:alerts, am[1])
    let [group, icon] = s:alerts[am[1]]
    let title = s:line(icon . toupper(strpart(am[1], 0, 1)) . tolower(strpart(am[1], 1)), [])
    call add(title.sp, [0, strlen(title.t), group])
    call add(title.sp, [0, strlen(title.t), 'VimMdBold'])
    let title.src = qn[0]
    call remove(q, 0)
    call remove(qn, 0)
  endif
  let inner = s:blocks(q, qn, a:width - 2, {'top': 0, 'item': 0, 'depth': a:ctx.depth})
  if !empty(title)
    call insert(inner, title, 0)
  endif
  if empty(inner)
    let inner = [s:line('', [])]
    let inner[0].src = a:nums[a:i]
  endif
  call s:prefix(inner, '▎ ', '▎ ', group, group)
  return [inner, j]
endfunction

" ---------------------------------------------------------------- main loop

function! s:blocks(lines, nums, width, ctx) abort
  let out = []
  let n = len(a:lines)
  let width = max([a:width, 4])
  let i = 0
  let prev = ''
  while i < n
    let line = a:lines[i]
    if line =~# '^\s*$'
      let i += 1
      continue
    endif
    let start = i
    let kind = ''
    let blk = []

    if a:ctx.top && i == 0 && line =~# '^---\s*$'
      let j = 1
      while j < n && a:lines[j] !~# '^\(---\|\.\.\.\)\s*$'
        let j += 1
      endwhile
      if j < n
        let blk = s:render_code(a:lines[1 : j - 1], 'front matter', width, 'yaml')
        let kind = 'code'
        let i = j + 1
      endif
    endif

    if kind ==# '' && line =~# s:fence_re
      let fence = matchstr(line, s:fence_re)
      let fence = substitute(fence, '^\s*', '', '')
      let lang = matchstr(substitute(line, s:fence_re, '', ''), '^\s*\zs[^ `]*')
      let close_re = '^\s\{0,3}' . (fence =~# '`' ? '`' : '\~') . '\{' . strlen(fence) . ',}\s*$'
      let ind = strlen(matchstr(line, '^\s*'))
      let content = []
      let j = i + 1
      while j < n && a:lines[j] !~# close_re
        call add(content, substitute(a:lines[j], '^\s\{0,' . ind . '}', '', ''))
        let j += 1
      endwhile
      let blk = s:render_code(content, lang, width, lang)
      let kind = 'code'
      let i = j + 1

    elseif kind ==# '' && s:is_hr(line)
      let blk = [s:line(repeat('─', width), [[0, 3 * width, 'VimMdRule']])]
      let kind = 'hr'
      let i += 1

    elseif kind ==# '' && line =~# s:atx_re
      let m = matchlist(line, s:atx_re)
      let text = substitute(m[2], '\s\+#\+\s*$', '', '')
      let text = substitute(text, '^#\+$', '', '')
      let blk = s:render_heading(strlen(m[1]), text, width)
      let kind = 'h'
      let i += 1

    elseif kind ==# '' && line =~# '^\s\{0,3}>'
      let [blk, i] = s:render_quote(a:lines, a:nums, i, width, a:ctx)
      let kind = 'quote'

    elseif kind ==# '' && !empty(s:item_start(line))
      let [blk, i] = s:render_list(a:lines, a:nums, i, width, a:ctx)
      let kind = 'list'

    elseif kind ==# '' && s:is_table_start(a:lines, i)
      let aligns = []
      for c in s:split_row(a:lines[i + 1])
        call add(aligns, c =~# '^:.*:$' ? 'center' : c =~# ':$' ? 'right' : 'left')
      endfor
      let rows = [s:split_row(a:lines[i])]
      let j = i + 2
      while j < n && a:lines[j] !~# '^\s*$' && !s:starts_block(a:lines[j])
        call add(rows, s:split_row(a:lines[j]))
        let j += 1
      endwhile
      let blk = s:render_table(rows, aligns, width)
      let kind = 'table'
      let i = j

    elseif kind ==# '' && line =~# '^\s*<!--'
      let j = i
      while j < n && a:lines[j] !~# '-->'
        let j += 1
      endwhile
      let i = j + 1

    elseif kind ==# '' && line =~# '^\s\{0,3}\[[^\]]\+\]:\s*\S'
      let i += 1

    elseif kind ==# '' && line =~# '^    '
      let content = []
      let j = i
      while j < n && (a:lines[j] =~# '^    ' || a:lines[j] =~# '^\s*$')
        call add(content, strpart(a:lines[j], 4))
        let j += 1
      endwhile
      while !empty(content) && content[-1] =~# '^\s*$'
        call remove(content, -1)
        let j -= 1
      endwhile
      let blk = s:render_code(content, '', width, '')
      let kind = 'code'
      let i = j

    elseif kind ==# ''
      " paragraph / setext heading
      let parts = [line]
      let setext = 0
      let j = i + 1
      while j < n
        let l = a:lines[j]
        if l =~# '^\s*$'
          break
        elseif l =~# '^\s\{0,3}=\+\s*$'
          let setext = 1
          let j += 1
          break
        elseif l =~# '^\s\{0,3}-\+\s*$'
          let setext = 2
          let j += 1
          break
        elseif s:starts_block(l) || s:is_table_start(a:lines, j)
          break
        endif
        call add(parts, l)
        let j += 1
      endwhile
      let texts = []
      for k in range(len(parts))
        let t = substitute(parts[k], '^\s\+', '', '')
        if k < len(parts) - 1
          if t =~# '  $'
            let t = substitute(t, '\s\+$', '', '') . "\n"
          elseif t =~# '[^\\]\\$'
            let t = strpart(t, 0, strlen(t) - 1) . "\n"
          endif
        endif
        call add(texts, substitute(t, '[ ]\+$', '', ''))
      endfor
      let text = join(texts, ' ')
      if setext
        let blk = s:render_heading(setext, text, width)
        let kind = 'h'
      else
        let blk = s:wrap(vim_md#inline#parse(text), width)
        let kind = 'p'
      endif
      let i = j
    endif

    if !empty(blk)
      let en = a:nums[max([i - 1, start])]
      let sn = a:nums[start]
      for k in range(len(blk))
        if !has_key(blk[k], 'src')
          let blk[k].src = s:lerp(sn, en, k, len(blk))
        endif
      endfor
      if !empty(out) && !(a:ctx.item && prev ==# 'p' && kind ==# 'list')
        let sep = s:line('', [])
        let sep.src = blk[0].src
        call add(out, sep)
      endif
      call extend(out, blk)
      let prev = kind
    endif
  endwhile
  return out
endfunction
