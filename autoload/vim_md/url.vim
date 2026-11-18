" vim-md: safe handling of link targets.
"
" Links come from the document being previewed, which may be untrusted, so a
" URL is never handed to the system opener as-is:
"   * only schemes in g:vim_md_open_schemes are opened (http, https, mailto);
"     file:, javascript:, smb:, custom protocol handlers, "C:\..." etc. are refused
"   * every byte that is not valid in a URL (space, control characters, quotes,
"     <>\^|`{} and non-ASCII) is percent-encoded
"   * on Windows the opener is rundll32, never `cmd /c start`, whose parsing
"     of & | ^ " would turn a crafted URL into command execution
"   * a link whose visible text is a URL for another host is flagged as
"     spoofed so the caller can ask for confirmation

function! vim_md#url#scheme(url) abort
  return tolower(matchstr(a:url, '^\a[a-zA-Z0-9+.-]*\ze:'))
endfunction

function! vim_md#url#allowed(url) abort
  let schemes = map(copy(get(g:, 'vim_md_open_schemes', ['http', 'https', 'mailto'])), 'tolower(v:val)')
  let s = vim_md#url#scheme(a:url)
  return s !=# '' && index(schemes, s) >= 0
endfunction

" Percent-encode everything outside the RFC 3986 URL characters. Existing %XX
" sequences are kept. The apostrophe is encoded too although the RFC allows it.
function! vim_md#url#encode(url) abort
  let out = ''
  for i in range(strlen(a:url))
    let ch = a:url[i]
    if ch =~# '^[]A-Za-z0-9._~:/?#@!$&()*+,;=%[-]$'
      let out .= ch
    else
      let out .= printf('%%%02X', char2nr(ch))
    endif
  endfor
  return out
endfunction

" Command (list) that opens `url`, or [] when the URL must not be opened.
" `platform` ('mac', 'win', 'unix') is only meant for tests.
function! vim_md#url#command(url, ...) abort
  let u = vim_md#url#encode(a:url)
  if !vim_md#url#allowed(u)
    return []
  endif
  let platform = a:0 ? a:1 : (has('mac') ? 'mac' : has('win32') ? 'win' : 'unix')
  if platform ==# 'mac'
    return ['open', u]
  elseif platform ==# 'win'
    return ['rundll32', 'url.dll,FileProtocolHandler', u]
  endif
  return ['xdg-open', u]
endfunction

function! s:host(url) abort
  let s = substitute(tolower(a:url), '^\a[a-z0-9+.-]*://', '', '')
  let auth = matchstr(s, '^[^/?#]*')
  let auth = substitute(auth, '^.*@', '', '')
  let auth = substitute(auth, ':\d*$', '', '')
  return substitute(auth, '^www\.', '', '')
endfunction

" True when the visible link text looks like a URL for a different host than the
" real target, e.g. [https://bank.example](https://evil.example).
function! vim_md#url#spoofed(text, url) abort
  let t = substitute(a:text, '^\s*\|\s*$', '', 'g')
  if t !~? '^\(https\?://\|www\.\)'
    return 0
  endif
  return s:host(t) !=# s:host(a:url)
endfunction
