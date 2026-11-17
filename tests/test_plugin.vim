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
  call assert_equal('Title', getbufline(pb, 1)[0])
  call assert_equal('some bold text', getbufline(pb, 4)[0])
  call assert_equal(0, getbufvar(pb, '&modifiable'))
  if !has('nvim')
    call assert_true(len(prop_list(1, {'bufnr': pb})) > 0)
    call assert_true(len(prop_list(4, {'bufnr': pb})) > 0)
  endif

  call setline(3, 'now *changed*')
  call vim_md#refresh()
  call assert_equal('now changed', getbufline(pb, 4)[0])

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
  call cursor(1, 1)
  call vim_md#follow()
  call assert_equal('Second part', getline('.'))
  call vim_md#close()
  bwipeout!
endfunction

function! Test_view_in_same_window() abort
  enew!
  call setline(1, ['# Title', '', 'some **bold** text', '', '## Two', '', 'tail para'])
  setlocal filetype=markdown wrap number
  let src = bufnr('%')
  let win = win_getid()
  let nwin = winnr('$')
  call cursor(7, 1)                        " modified buffer, cursor on "tail para"
  call vim_md#view_open()
  call assert_true(vim_md#view_is_open())
  call assert_equal(nwin, winnr('$'), 'no extra window')
  call assert_equal(win, win_getid())
  call assert_notequal(src, bufnr('%'))
  call assert_equal('Title', getline(1))
  call assert_equal('some bold text', getline(4))
  call assert_equal(0, &modifiable)
  call assert_equal(0, &wrap)
  call assert_equal(0, &number)
  call assert_equal('tail para', getline('.'), 'cursor mapped into the view')
  call assert_true(bufloaded(src), 'source stays loaded')

  call cursor(4, 1)                        " move in the view, then go back
  call vim_md#view_toggle()
  call assert_false(vim_md#view_is_open())
  call assert_equal(src, bufnr('%'))
  call assert_equal(3, line('.'), 'cursor mapped back to the source')
  call assert_equal(1, &wrap)
  call assert_equal(1, &number)
  call assert_equal(0, &foldcolumn)
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
  call cursor(1, 1)
  call vim_md#follow()
  call assert_equal('Two', getline('.'))
  call vim_md#heading(-1)
  call assert_equal('One', getline('.'))
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
