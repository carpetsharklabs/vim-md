let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')

function! Test_url_scheme_allowlist() abort
  for ok in ['https://a.b/c', 'HTTP://a.b', 'mailto:a@b.c']
    call assert_true(vim_md#url#allowed(ok), ok)
  endfor
  for bad in ['file:///etc/passwd', 'javascript:alert(1)', 'smb://h/share', 'C:\Windows\System32\calc.exe',
        \ 'data:text/html,x', 'vscode://x', 'ssh://h', 'ms-msdt:/id', '//host/x', 'not a url', '']
    call assert_false(vim_md#url#allowed(bad), bad)
  endfor
  let g:vim_md_open_schemes = ['gemini']
  call assert_true(vim_md#url#allowed('gemini://x'))
  call assert_false(vim_md#url#allowed('https://x'))
  unlet g:vim_md_open_schemes
endfunction

function! Test_url_encode() abort
  call assert_equal('https://a.b/?q=1&r=2#f', vim_md#url#encode('https://a.b/?q=1&r=2#f'))
  call assert_equal('https://a.b/%22&calc.exe', vim_md#url#encode('https://a.b/"&calc.exe'))
  call assert_equal('https://a.b/a%20b%3Cc%3E%5C%5E%7C%60%27', vim_md#url#encode("https://a.b/a b<c>\\^|`'"))
  call assert_equal('https://a.b/a%0Ab', vim_md#url#encode("https://a.b/a\nb"))
  call assert_equal('https://a.b/a%1Bb', vim_md#url#encode("https://a.b/a\<Esc>b"))
  call assert_equal('https://a.b/a%C3%A7%C3%A3o', vim_md#url#encode('https://a.b/ação'))
  call assert_equal('https://a.b/%41%2f', vim_md#url#encode('https://a.b/%41%2f'), 'existing escapes are kept')
endfunction

function! Test_url_command_per_platform() abort
  let u = 'https://a.b/x?y=1&z=2'
  call assert_equal(['xdg-open', u], vim_md#url#command(u, 'unix'))
  call assert_equal(['open', u], vim_md#url#command(u, 'mac'))
  call assert_equal(['rundll32', 'url.dll,FileProtocolHandler', u], vim_md#url#command(u, 'win'))
  call assert_equal([], vim_md#url#command('file:///etc/passwd', 'unix'))
  call assert_equal([], vim_md#url#command('C:\Windows\System32\calc.exe', 'win'))
endfunction

function! Test_url_windows_never_uses_cmd_and_is_neutralised() abort
  let evil = 'https://a.example/"&calc.exe'
  let cmd = vim_md#url#command(evil, 'win')
  call assert_equal('rundll32', cmd[0])
  call assert_equal(-1, index(cmd, 'cmd'))
  call assert_equal('https://a.example/%22&calc.exe', cmd[-1])
  call assert_equal(-1, stridx(cmd[-1], '"'))
endfunction

function! Test_url_spoofed_text() abort
  call assert_true(vim_md#url#spoofed('https://bank.example', 'https://evil.example'))
  call assert_true(vim_md#url#spoofed('www.bank.example', 'https://evil.example/x'))
  call assert_true(vim_md#url#spoofed('https://bank.example', 'https://bank.example@evil.example/'), 'userinfo trick')
  call assert_true(vim_md#url#spoofed('https://bank.example', 'https://bank.example.evil.io/'), 'look-alike suffix')
  call assert_false(vim_md#url#spoofed('https://github.com', 'https://github.com/a/b'))
  call assert_false(vim_md#url#spoofed('www.github.com', 'https://github.com:443/x'))
  call assert_false(vim_md#url#spoofed('HTTPS://GitHub.com/x', 'https://github.com/y'))
  call assert_false(vim_md#url#spoofed('click here', 'https://evil.example'))
  call assert_false(vim_md#url#spoofed('docs', 'mailto:a@b.c'))
endfunction

" End to end: follow links in the view with a test double in place of xdg-open.
function! s:click(doc, label) abort
  let log = tempname()
  let $VIMMD_LOG = log
  let $PATH = s:root . '/tests/fixtures/bin:' . s:path
  enew!
  call setline(1, a:doc)
  setlocal filetype=markdown
  call vim_md#view_open()
  call cursor(1, 1)
  call search('\V' . a:label, 'w')
  call vim_md#follow()
  let seen = []
  for i in range(15)
    execute 'sleep 100m'
    if filereadable(log)
      let seen = readfile(log)
      break
    endif
  endfor
  call vim_md#view_close()
  bwipeout!
  call delete(log)
  return seen
endfunction

let s:path = $PATH

function! Test_follow_refuses_dangerous_targets() abort
  if !has('unix') || has('mac')
    return
  endif
  for [target, label] in [['file:///etc/passwd', 'a'], ['javascript:alert(1)', 'b'], ['smb://h/share', 'c'],
        \ ['C:\Windows\System32\calc.exe', 'd'], ['vscode://x', 'e']]
    call assert_equal([], s:click(['[' . label . '](' . target . ')'], label), target)
  endfor
endfunction

function! Test_follow_opens_http_with_sanitised_url() abort
  if !has('unix') || has('mac')
    return
  endif
  call assert_equal(['https://x.io/?a=1&b=2'], s:click(['[ok](https://x.io/?a=1&b=2)'], 'ok'))
  call assert_equal(['https://a.example/%22&calc.exe'], s:click(['[q](https://a.example/"&calc.exe)'], 'q'))
endfunction
