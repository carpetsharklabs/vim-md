function! s:p(text) abort
  return vim_md#inline#parse(a:text)
endfunction

function! s:groups(r) abort
  return map(copy(a:r.sp), 'v:val[2] . ":" . strpart(a:r.t, v:val[0], v:val[1])')
endfunction

function! Test_plain_and_escapes() abort
  call assert_equal('hello world', s:p('hello world').t)
  call assert_equal('*not bold*', s:p('\*not bold\*').t)
  call assert_equal('a * b * c', s:p('a * b * c').t)
  call assert_equal('snake_case_name', s:p('snake_case_name').t)
endfunction

function! Test_emphasis() abort
  let r = s:p('a **b** *c* ***d*** ~~e~~')
  call assert_equal('a b c d e', r.t)
  call assert_equal(['VimMdBold:b', 'VimMdItalic:c', 'VimMdBold:d', 'VimMdItalic:d', 'VimMdStrike:e'], s:groups(r))
endfunction

function! Test_nested_emphasis() abort
  let r = s:p('**bold *and italic* text**')
  call assert_equal('bold and italic text', r.t)
  call assert_equal(['VimMdBold:bold and italic text', 'VimMdItalic:and italic'], s:groups(r))
endfunction

function! Test_code_span() abort
  let r = s:p('use `**x**` and ``a`b``')
  call assert_equal('use **x** and a`b', r.t)
  call assert_equal(['VimMdCode:**x**', 'VimMdCode:a`b'], s:groups(r))
endfunction

function! Test_links() abort
  let r = s:p('see [the *docs*](https://x.io/a_b "title") now')
  call assert_equal('see the docs now', r.t)
  call assert_equal([[4, 8, 'https://x.io/a_b']], r.links)
  let r = s:p('<https://a.b/c> and https://d.e/f.')
  call assert_equal('https://a.b/c and https://d.e/f.', r.t)
  call assert_equal(['https://a.b/c', 'https://d.e/f'], map(copy(r.links), 'v:val[2]'))
endfunction

function! Test_image_and_badge() abort
  let r = s:p('![alt text](img.png)')
  call assert_equal('◩ alt text', r.t)
  let r = s:p('[![build](b.svg)](https://ci)')
  call assert_equal('◩ build', r.t)
  call assert_equal('https://ci', r.links[0][2])
endfunction

function! Test_reference_links() abort
  call vim_md#inline#set_refs({'ref': 'https://r.io'})
  let r = s:p('[text][ref] and [ref]')
  call assert_equal('text and ref', r.t)
  call assert_equal(['https://r.io', 'https://r.io'], map(copy(r.links), 'v:val[2]'))
  call vim_md#inline#set_refs({})
endfunction

function! Test_html_and_entities() abort
  call assert_equal("a\nb", s:p('a<br>b').t)
  call assert_equal('x <y> & z', s:p('x &lt;y&gt; &amp; z').t)
  call assert_equal('hi', s:p('<kbd>hi</kbd>').t)
  call assert_equal('ab', s:p('a<!-- hidden -->b').t)
endfunction

function! Test_multibyte() abort
  let r = s:p('olá **mundão** ação')
  call assert_equal('olá mundão ação', r.t)
  call assert_equal(['VimMdBold:mundão'], s:groups(r))
endfunction

function! Test_footnote_refs() abort
  call vim_md#inline#set_footnotes({'1': 1, 'note': 1})
  let r = s:p('a[^1] b[^note] c[^zzz] d[^1]')
  call assert_equal('a¹ b² c[^zzz] d¹', r.t, 'unknown labels stay literal, numbers follow first use')
  call assert_equal(['1', 'note'], vim_md#inline#footnote_order())
  call assert_equal(['VimMdFootnote:¹', 'VimMdFootnote:²', 'VimMdFootnote:¹'], s:groups(r))
  call vim_md#inline#set_footnotes({})
  call assert_equal('a[^1]', s:p('a[^1]').t, 'no definition, no footnote')
endfunction

function! Test_superscript_numbers() abort
  call assert_equal('¹', vim_md#inline#superscript(1))
  call assert_equal('¹⁰', vim_md#inline#superscript(10))
  call assert_equal('¹²³⁴⁵⁶⁷⁸⁹⁰', vim_md#inline#superscript(1234567890))
endfunction

function! Test_emoji_shortcodes() abort
  call assert_equal('🎉 x ✅', s:p(':tada: x :white_check_mark:').t)
  call assert_equal(':nope: 12:30:45 a:b:c', s:p(':nope: 12:30:45 a:b:c').t, 'unknown names and clock times stay')
  call assert_equal('👍👎', s:p(':+1::-1:').t)
  let g:vim_md_emoji = 0
  call assert_equal(':tada:', s:p(':tada:').t)
  unlet g:vim_md_emoji
endfunction
