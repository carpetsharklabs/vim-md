syntax clear
syntax match vmtKeyword /\<def\>/
syntax match vmtPlain /\<plain\>/
highlight default link vmtKeyword Statement
highlight default link vmtPlain Normal
let b:current_syntax = 'vimmdtest'
