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
