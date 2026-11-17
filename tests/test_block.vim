let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')

function! s:r(lines, ...) abort
  return vim_md#block#render(a:lines, a:0 ? a:1 : 40)
endfunction

function! Test_heading_levels() abort
  let r = s:r(['# One', '', '## Two', '', '### Three'], 20)
  call assert_equal(['One', repeat('═', 20), '', 'Two', repeat('─', 20), '', '▌ Three'], r.lines)
  call assert_equal([[1, 1, 'One'], [4, 2, 'Two'], [7, 3, 'Three']], r.headings)
endfunction

function! Test_setext_heading() abort
  let r = s:r(['Title', '=====', 'text'], 10)
  call assert_equal(['Title', repeat('═', 10), '', 'text'], r.lines)
endfunction

function! Test_paragraph_wrap_and_hard_break() abort
  let r = s:r(['aaa bbb ccc ddd eee', 'fff  ', 'ggg'], 10)
  call assert_equal(['aaa bbb', 'ccc ddd', 'eee fff', 'ggg'], r.lines)
endfunction

function! Test_lists() abort
  let r = s:r(['- a', '- b', '  - c', '    - d', '', '1. x', '2. y'], 30)
  call assert_equal(['• a', '• b', '  ◦ c', '    ▪ d', '', '1. x', '2. y'], r.lines)
endfunction

function! Test_ordered_alignment_and_tasks() abort
  let lines = map(range(1, 10), 'v:val . ". i" . v:val')
  let r = s:r(lines, 30)
  call assert_equal(' 1. i1', r.lines[0])
  call assert_equal('10. i10', r.lines[9])
  let r = s:r(['- [ ] open', '- [x] done'], 30)
  call assert_equal(['☐ open', '☑ done'], r.lines)
endfunction

function! Test_list_item_wrap_hanging_indent() abort
  let r = s:r(['- aaa bbb ccc ddd'], 9)
  call assert_equal(['• aaa bbb', '  ccc ddd'], r.lines)
endfunction

function! Test_list_item_with_paragraphs_and_code() abort
  let r = s:r(['- one', '', '  two', '', '  ```', '  x', '  ```'], 20)
  call assert_equal('• one', r.lines[0])
  call assert_equal('  two', r.lines[2])
  call assert_match('^   x', r.lines[5])
endfunction

function! Test_blockquote_and_alert() abort
  let r = s:r(['> hello', '> world'], 20)
  call assert_equal(['▎ hello world'], r.lines)
  let r = s:r(['> [!NOTE]', '> be careful'], 20)
  call assert_equal(['▎ ● Note', '▎ be careful'], r.lines)
endfunction

function! Test_code_fence() abort
  let r = s:r(['```vim', 'echo 1', '```'], 12)
  call assert_equal(3, len(r.lines))
  call assert_match('^ vim\s*$', r.lines[0])
  call assert_match('^ echo 1\s*$', r.lines[1])
  call assert_equal(12, strdisplaywidth(r.lines[1]))
endfunction

function! Test_indented_code_and_front_matter() abort
  let r = s:r(['text', '', '    code here'], 20)
  call assert_match('code here', r.lines[3])
  let r = s:r(['---', 'a: 1', '---', '', 'body'], 20)
  call assert_match('front matter', r.lines[0])
  call assert_match('a: 1', r.lines[1])
  call assert_equal('body', r.lines[-1])
endfunction

function! Test_table() abort
  let r = s:r(['| A | B |', '|:--|--:|', '| x | `y` |', '| long cell | z |'], 40)
  call assert_equal([
        \ '┌───────────┬───┐',
        \ '│ A         │ B │',
        \ '├───────────┼───┤',
        \ '│ x         │ y │',
        \ '│ long cell │ z │',
        \ '└───────────┴───┘'], r.lines)
endfunction

function! Test_table_wraps_to_width() abort
  let r = s:r(['| a | b |', '|---|---|', '| one two three four | five six seven |'], 24)
  for l in r.lines
    call assert_true(strdisplaywidth(l) <= 24, l)
  endfor
  call assert_true(len(r.lines) > 5)
endfunction

function! Test_hr_comment_refdef() abort
  let r = s:r(['a', '', '***', '', '<!-- c -->', '', '[x]: http://x', '', 'b'], 8)
  call assert_equal(['a', '', repeat('─', 8), '', 'b'], r.lines)
endfunction

function! Test_source_map_is_monotonic() abort
  let r = s:r(['# T', '', 'a b c', 'd', '', '- x', '- y', '', '> q'], 30)
  call assert_equal(len(r.lines), len(r.src))
  let prev = 0
  for s in r.src
    call assert_true(s >= prev)
    let prev = s
  endfor
  call assert_equal(1, r.src[0])
endfunction

function! Test_link_positions() abort
  let r = s:r(['go [here](http://h) now'], 40)
  call assert_equal([[1, 4, 4, 'http://h']], r.links)
endfunction

function! Test_highlights_flattened() abort
  let r = s:r(['# Hi **there**'], 40)
  " Heading text is covered by non overlapping segments
  let prev_end = 0
  for h in filter(copy(r.hl), 'v:val[0] == 1')
    call assert_true(h[1] >= prev_end)
    let prev_end = h[1] + h[2]
  endfor
  call assert_true(len(filter(copy(r.hl), 'v:val[3] =~# "VimMdX_"')) > 0)
endfunction

function! Test_empty_and_unicode() abort
  call assert_equal([], s:r([]).lines)
  let r = s:r(['日本語 テキスト ' . repeat('あ', 5)], 12)
  for l in r.lines
    call assert_true(strdisplaywidth(l) <= 12 || l !~# ' ', l)
  endfor
endfunction

function! Test_demo_renders_without_error() abort
  let r = s:r(readfile(s:root . '/examples/demo.md'), 60)
  call assert_true(len(r.lines) > 30)
endfunction

function! Test_code_block_syntax_highlight() abort
  let r = s:r(['```python', 'def f():', '    return "x"  # hi', '```'], 40)
  " Highlight combos merge the code background with the syntax group colors.
  let names = map(copy(r.hl), 'v:val[3]')
  call assert_true(len(filter(copy(names), 'v:val =~# "^VimMdX_CodeBlock_"')) > 0, string(names))
  " The "def" keyword (line 2, col 2) is highlighted differently from the background.
  let at_def = filter(copy(r.hl), 'v:val[0] == 2 && v:val[1] == 2')
  call assert_equal(1, len(at_def))
  call assert_match('^VimMdX_CodeBlock_', at_def[0][3])
  " A string literal and a comment get distinct groups. The string group is
  " Constant in Vim (String links to it) but String itself in Neovim.
  let strs = filter(copy(r.hl), 'v:val[0] == 3 && v:val[3] =~# "_\\(Constant\\|String\\)$"')
  let cmts = filter(copy(r.hl), 'v:val[0] == 3 && v:val[3] =~# "_Comment$"')
  call assert_equal(1, len(strs))
  call assert_equal(1, len(cmts))
endfunction

function! Test_code_syntax_unknown_lang_and_disabled() abort
  let r = s:r(['```nosuchlang', 'x = 1', '```'], 20)
  call assert_equal([], filter(copy(r.hl), 'v:val[3] =~# "^VimMdX_CodeBlock_" && v:val[3] !~# "CodeLang"'))
  let g:vim_md_code_syntax = 0
  let r = s:r(['```python', 'def f(): pass', '```'], 20)
  unlet g:vim_md_code_syntax
  call assert_equal([], filter(copy(r.hl), 'v:val[3] =~# "^VimMdX_CodeBlock_" && v:val[3] !~# "CodeLang"'))
endfunction
