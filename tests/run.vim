" Run with:  vim -u NONE -N -es --cmd 'set enc=utf-8' -S tests/run.vim
"       or:  nvim -u NONE -l ... (see Makefile)
set nocompatible
set encoding=utf-8
let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
execute 'set rtp^=' . fnameescape(s:root)
filetype on
syntax on
call vim_md#hl#setup()

let s:failed = 0
let s:passed = 0
let s:report = []

for s:file in sort(glob(s:root . '/tests/test_*.vim', 0, 1))
  execute 'source' fnameescape(s:file)
  redir => s:fns
  silent function /^Test_
  redir END
  for s:fn in map(split(s:fns, "\n"), 'matchstr(v:val, "Test_\\w\\+")')
    let v:errors = []
    try
      execute 'call ' . s:fn . '()'
    catch
      call add(v:errors, 'exception: ' . v:exception . ' @ ' . v:throwpoint)
    endtry
    if empty(v:errors)
      let s:passed += 1
    else
      let s:failed += 1
      call add(s:report, 'FAIL ' . fnamemodify(s:file, ':t') . ' ' . s:fn)
      call extend(s:report, map(copy(v:errors), '"  " . v:val'))
    endif
    execute 'delfunction ' . s:fn
  endfor
endfor

call add(s:report, printf('%d passed, %d failed', s:passed, s:failed))
let s:out = $VIM_MD_TEST_OUT !=# '' ? $VIM_MD_TEST_OUT : s:root . '/tests/results.txt'
call writefile(s:report, s:out)
if s:failed
  cquit
endif
qa!
