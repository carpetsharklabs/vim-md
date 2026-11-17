" vim-md - rendered markdown preview inside Vim / Neovim
" Maintainer: carpetsharklabs
" License: MIT

if exists('g:loaded_vim_md') || &compatible
  finish
endif
let g:loaded_vim_md = 1

command! -bar MdPreview        call vim_md#toggle()
command! -bar MdPreviewOpen    call vim_md#open()
command! -bar MdPreviewClose   call vim_md#close()
command! -bar MdPreviewRefresh call vim_md#refresh()

command! -bar MdView           call vim_md#view_toggle()
command! -bar MdViewOpen       call vim_md#view_open()
command! -bar MdViewClose      call vim_md#view_close()

nnoremap <silent> <Plug>(vim-md-view) :<C-u>call vim_md#view_toggle()<CR>
nnoremap <silent> <Plug>(vim-md-toggle) :<C-u>call vim_md#toggle()<CR>
