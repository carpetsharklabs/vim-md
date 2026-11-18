function! Test_open_refresh_close() abort
  enew!
  call setline(1, ['# Title', '', 'some **bold** text', '', '- a', '- b'])
  setlocal filetype=markdown
  let src = bufnr('%')
  call vim_md#open()
  call assert_true(vim_md#is_open())
  let pb = winbufnr(bufwinid('Markdown Preview'))
  call assert_true(pb > 0)
  call assert_equal(src, bufnr('%'), 'focus stays in source')
  call assert_equal(' Title', getbufline(pb, 1)[0], 'rendered with a 1 column margin')
  call assert_equal(' some bold text', getbufline(pb, 4)[0])
  call assert_equal(0, getbufvar(pb, '&modifiable'))
  if !has('nvim')
    call assert_true(len(prop_list(1, {'bufnr': pb})) > 0)
    call assert_true(len(prop_list(4, {'bufnr': pb})) > 0)
  endif

  call setline(3, 'now *changed*')
  call vim_md#refresh()
  call assert_equal(' now changed', getbufline(pb, 4)[0])

  call vim_md#toggle()
  call assert_false(vim_md#is_open())
  call assert_equal(0, bufexists(pb))
  bwipeout!
endfunction

function! Test_follow_anchor_link() abort
  enew!
  call setline(1, ['[go](#second-part)', '', '# First', '', '# Second part'])
  setlocal filetype=markdown
  call vim_md#open()
  let w = bufwinid('Markdown Preview')
  call win_gotoid(w)
  call cursor(1, 2)
  call vim_md#follow()
  call assert_equal(' Second part', getline('.'))
  call vim_md#close()
  bwipeout!
endfunction

function! Test_view_in_same_window() abort
  enew!
  call setline(1, ['# Title', '', 'some **bold** text', '', '## Two', '', 'tail para'])
  setlocal filetype=markdown wrap number foldcolumn=2
  let src = bufnr('%')
  let win = win_getid()
  let nwin = winnr('$')
  call cursor(7, 1)                        " modified buffer, cursor on "tail para"
  call vim_md#view_open()
  call assert_true(vim_md#view_is_open())
  call assert_equal(nwin, winnr('$'), 'no extra window')
  call assert_equal(win, win_getid())
  call assert_notequal(src, bufnr('%'))
  call assert_equal(' Title', getline(1))
  call assert_equal(' some bold text', getline(4))
  call assert_equal(0, &modifiable)
  call assert_equal(0, &wrap)
  call assert_equal(0, &number)
  call assert_equal(' tail para', getline('.'), 'cursor mapped into the view')
  call assert_true(bufloaded(src), 'source stays loaded')

  call cursor(4, 1)                        " move in the view, then go back
  call vim_md#view_toggle()
  call assert_false(vim_md#view_is_open())
  call assert_equal(src, bufnr('%'))
  call assert_equal(3, line('.'), 'cursor mapped back to the source')
  call assert_equal(1, &wrap)
  call assert_equal(1, &number)
  call assert_equal(2, str2nr(&foldcolumn), 'restored')   " string in Neovim, number in Vim
  call assert_equal(0, &cursorline)
  call assert_equal(['# Title', '', 'some **bold** text', '', '## Two', '', 'tail para'], getline(1, '$'))
  call assert_equal(1, &modified, 'source stays modified, untouched')
  bwipeout!
endfunction

function! Test_view_follow_anchor_and_headings() abort
  enew!
  call setline(1, ['[go](#two)', '', '# One', '', '# Two'])
  setlocal filetype=markdown
  call vim_md#view_open()
  call cursor(1, 2)
  call vim_md#follow()
  call assert_equal(' Two', getline('.'))
  call vim_md#heading(-1)
  call assert_equal(' One', getline('.'))
  call vim_md#view_close()
  bwipeout!
endfunction

function! Test_view_and_preview_coexist() abort
  enew!
  call setline(1, ['# A', '', 'text'])
  setlocal filetype=markdown
  call vim_md#open()
  call vim_md#view_open()
  call assert_true(vim_md#view_is_open())
  call assert_true(vim_md#is_open())
  call vim_md#view_close()
  call assert_true(vim_md#is_open(), 'preview survives closing the view')
  call vim_md#close()
  bwipeout!
endfunction

" ---------------------------------------------------------------- tasks, links, outline, folds

function! s:goto(text) abort
  call cursor(1, 1)
  call assert_true(search('\V' . a:text, 'w') > 0, 'not found: ' . a:text)
endfunction

function! s:new_doc(lines) abort
  enew!
  call setline(1, a:lines)
  setlocal filetype=markdown
  return bufnr('%')
endfunction

function! Test_toggle_task_in_view() abort
  let src = s:new_doc(['# T', '', '- [ ] one', '- [x] two', '- plain', '1. [X] up', '> - [ ] quoted'])
  call vim_md#view_open()
  call s:goto('☐ one')
  call vim_md#toggle_task()
  call assert_equal('- [x] one', getbufline(src, 3)[0])
  call assert_match('☑ one', getline('.'), 'view re-rendered')
  call vim_md#toggle_task()
  call assert_equal('- [ ] one', getbufline(src, 3)[0], 'toggles back')
  call s:goto('☑ two')
  call vim_md#toggle_task()
  call assert_equal('- [ ] two', getbufline(src, 4)[0])
  call s:goto('☑ up')
  call vim_md#toggle_task()
  call assert_equal('1. [ ] up', getbufline(src, 6)[0], 'uppercase X, ordered list')
  call s:goto('☐ quoted')
  call vim_md#toggle_task()
  call assert_equal('> - [x] quoted', getbufline(src, 7)[0], 'inside a block quote')
  let before = getbufline(src, 1, '$')
  call s:goto('plain')
  call vim_md#toggle_task()
  call assert_equal(before, getbufline(src, 1, '$'), 'a plain line is left alone')
  call vim_md#view_close()
  call assert_equal(1, getbufvar(src, '&modified'))
  bwipeout!
endfunction

function! Test_toggle_task_in_preview() abort
  let src = s:new_doc(['- [ ] a', '- [ ] b'])
  call vim_md#open()
  let pw = bufwinid('Markdown Preview')
  call win_gotoid(pw)
  call s:goto('☐ b')
  call vim_md#toggle_task()
  call assert_equal(['- [ ] a', '- [x] b'], getbufline(src, 1, '$'))
  call assert_match('☑ b', getline('.'), 'preview re-rendered')
  call vim_md#close()
  call win_gotoid(bufwinid(src))
  bwipeout!
endfunction

function! Test_stale_task_is_not_corrupted() abort
  let src = s:new_doc(['- [ ] a'])
  call vim_md#view_open()
  call s:goto('☐ a')
  call setbufline(src, 1, '- [x] a')       " source changed behind the view's back
  call vim_md#toggle_task()
  call assert_equal('- [x] a', getbufline(src, 1)[0], 'refused instead of writing a wrong state')
  call vim_md#view_close()
  bwipeout!
endfunction

function! Test_link_jump_and_goto_source() abort
  let src = s:new_doc(['[a](#x) text [b](http://b.example)', '', '[c](http://c.example)', '', '# X'])
  call vim_md#view_open()
  call cursor(1, 1)
  let got = []
  for i in range(4)
    call vim_md#link_jump(1)
    call add(got, getline('.')[col('.') - 1])
  endfor
  call assert_equal(['a', 'b', 'c', 'a'], got, 'forward, wrapping at the end')
  let got = []
  for i in range(3)
    call vim_md#link_jump(-1)
    call add(got, getline('.')[col('.') - 1])
  endfor
  call assert_equal(['c', 'b', 'a'], got, 'backward, wrapping at the start')
  call s:goto('X')
  call search('\VX', 'w')
  call cursor(search('^ X$', 'nw'), 2)
  call vim_md#goto_source()
  call assert_equal(src, bufnr('%'))
  call assert_equal(5, line('.'), 'gs from the view lands on the heading line')
  bwipeout!
endfunction

function! Test_goto_source_from_preview() abort
  let src = s:new_doc(['intro', '', '# Head', '', 'body'])
  call vim_md#open()
  call win_gotoid(bufwinid('Markdown Preview'))
  call cursor(search('^ Head$', 'nw'), 2)
  call vim_md#goto_source()
  call assert_equal(src, bufnr('%'), 'back in the source window')
  call assert_equal(3, line('.'))
  call vim_md#close()
  bwipeout!
endfunction

function! Test_outline_location_list() abort
  let src = s:new_doc(['# One', '', 'text', '', '## Two', '', '### Three', '', '# Four'])
  call vim_md#outline()
  let items = getloclist(0)
  call assert_equal([1, 5, 7, 9], map(copy(items), 'v:val.lnum'))
  call assert_equal(['One', '  Two', '    Three', 'Four'], map(copy(items), 'v:val.text'))
  call assert_equal([src, src, src, src], map(copy(items), 'v:val.bufnr'))
  lclose
  call setloclist(0, [], 'f')
  bwipeout!
endfunction

function! Test_outline_from_preview_uses_the_source_window() abort
  let src = s:new_doc(['# One', '', '# Two'])
  let sw = bufwinid(src)
  call vim_md#open()
  let pw = bufwinid('Markdown Preview')
  call win_gotoid(pw)
  call vim_md#outline()
  " The list belongs to the source window, so jumping never replaces the preview.
  call assert_equal([1, 3], map(getloclist(sw), 'v:val.lnum'))
  call assert_equal([], getloclist(pw))
  lclose
  call setloclist(sw, [], 'f')
  call vim_md#close()
  call win_gotoid(sw)
  bwipeout!
endfunction

function! Test_folds_by_heading() abort
  call s:new_doc(['# A', '', 'a1', '', '## B', 'b1', '', '# C', 'c1'])
  call vim_md#view_open()
  " rendered: A, rule, '', a1, '', B, rule, '', b1, '', C, rule, '', c1
  call s:goto('A')
  call assert_equal([1, 1, 1], [foldlevel(line('.')), foldlevel(line('.') + 1), foldlevel(line('.') + 3)])
  call s:goto('B')
  call assert_equal(2, foldlevel(line('.')))
  call s:goto('C')
  call assert_equal(1, foldlevel(line('.')))
  call assert_equal(-1, foldclosed(line('.')), 'everything starts open')
  call s:goto('B')
  normal! zc
  call assert_equal(line('.'), foldclosed(line('.')))
  call assert_match('⋯ \d\+ lines', foldtextresult(line('.')))
  normal! zR
  call assert_equal(-1, foldclosed(line('.')))
  call vim_md#view_close()
  bwipeout!
endfunction

function! Test_closed_sections_survive_a_rerender() abort
  let src = s:new_doc(['# A', '- [ ] t', '', '# B', 'text'])
  call vim_md#view_open()
  call s:goto('B')
  normal! zc
  let b = line('.')
  call assert_equal(b, foldclosed(b))
  call s:goto('☐ t')
  call vim_md#toggle_task()               " forces a re-render of the view
  call assert_equal(b, foldclosed(b), 'section B is still closed')
  call assert_equal(-1, foldclosed(line('.')), 'section A is still open')
  call vim_md#view_close()
  bwipeout!
endfunction

function! Test_view_restores_fold_options() abort
  call s:new_doc(['# A', 'x'])
  setlocal foldmethod=indent foldlevel=2
  call vim_md#view_open()
  call assert_equal('expr', &foldmethod)
  call vim_md#view_close()
  call assert_equal('indent', &foldmethod)
  call assert_equal(2, str2nr(&foldlevel))
  call assert_equal('', &foldexpr =~# 'vim_md' ? 'leaked' : '')
  bwipeout!
endfunction

function! Test_closed_section_follows_its_heading_when_text_is_inserted_above() abort
  let src = s:new_doc(['# A', 'text', '# B', 'body'])
  let sw = win_getid()
  call vim_md#open()
  let pw = bufwinid('Markdown Preview')
  call win_gotoid(pw)
  call s:goto('B')
  normal! zc
  call assert_equal(line('.'), foldclosed(line('.')))
  call win_gotoid(sw)
  call append(1, ['more', '', 'lines', '', 'here'])      " pushes B further down
  call vim_md#refresh()
  call win_gotoid(pw)
  call s:goto('B')
  call assert_equal(line('.'), foldclosed(line('.')), 'B is still closed at its new position')
  call s:goto('A')
  call assert_equal(-1, foldclosed(line('.')), 'A stays open')
  call vim_md#close()
  call win_gotoid(sw)
  bwipeout!
endfunction
