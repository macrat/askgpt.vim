vim9script

if exists('b:did_ftplugin')
  finish
endif
b:did_ftplugin = 1

try
  prop_type_add('askgpt_message', {bufnr: bufnr()})
  prop_type_add('askgpt_indicator', {bufnr: bufnr()})
catch
endtry

askgpt#TextChanged()


const marker_pattern = '\C^\[\(__\|\~\~\)\(User\|Assistant\|Share\|Prompt\|Error\)\1\]$'

nnoremap <silent><buffer> <Plug>(askgpt-submit) :call askgpt#chatbuf#Submit()<CR>
inoremap <silent><buffer> <Plug>(askgpt-submit) <C-G>u<C-O>:call askgpt#chatbuf#Submit()<CR>

const search_pattern = marker_pattern->substitute('|', '\\|', 'g')
exe "nnoremap <silent><buffer> <Plug>(askgpt-go-prev-message) m':call search('" .. search_pattern .. "', 'bW')<CR>"
exe "vnoremap <silent><buffer> <Plug>(askgpt-go-prev-message) <Esc>m':<C-U>exe \"normal! gv\"<Bar>call search('" .. search_pattern .. "', 'bW')<CR>"
exe "nnoremap <silent><buffer> <Plug>(askgpt-go-next-message) m':call search('" .. search_pattern .. "', 'W')<CR>"
exe "vnoremap <silent><buffer> <Plug>(askgpt-go-next-message) <Esc>m':<C-U>exe \"normal! gv\"<Bar>call search('" .. search_pattern .. "', 'W')<CR>"

if !exists('g:askgpt_use_default_maps') || g:askgpt_use_default_maps
  imap <buffer> <Return> <Plug>(askgpt-submit)
  nmap <buffer> <Return> <Plug>(askgpt-submit)

  nmap <buffer> ]] <Plug>(askgpt-go-next-message)
  vmap <buffer> ]] <Plug>(askgpt-go-next-message)
  nmap <buffer> [[ <Plug>(askgpt-go-prev-message)
  vmap <buffer> [[ <Plug>(askgpt-go-prev-message)
endif


command -buffer AskGPTRetry askgpt#Retry()


setl foldmethod=syntax foldlevel=2 foldtext=FoldText()
if getline(1) == '[__Prompt__]'
  :1foldclose
endif
:$

def FoldText(): string
  const line = getline(v:foldstart)
  if line =~ '\C^\[__[A-Z][a-z]\+__\]$'
    return substitute(line, '[\[_\]]', '', 'g') .. ' '
  elseif line =~ '^`\{3,\}'
    return '+-' .. v:folddashes .. '  ' .. (v:foldend - v:foldstart + 1) .. ' lines code block: ' .. substitute(line, '^`\+', '', '') .. ' '
  else
    return foldtext()
  endif
enddef
