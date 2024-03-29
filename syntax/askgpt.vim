vim9script

if exists('b:current_syntax')
  finish
endif

runtime! syntax/markdown.vim
b:current_syntax = 'askgpt'

syn match askgptUser      /\C^\[__User__\]$/
syn match askgptAssistant /\C^\[__Assistant__\]$/
syn match askgptSystem    /\C^\[__\%(Share\|Prompt\)__\]$/
syn match askgptError     /\C^\[__Error__\]$/

syn match askgptDiscard /\C^\[\~\~\%(User\|Assistant\|Share\|Prompt\)\~\~\]\n\%(.\|\n\)\{-\}\n\ze\[\(__\|\~\~\)\%(User\|Assistant\|Share\|Prompt\|Error\)\1\]$/ keepend contains=markdownInline,markdownBlock

syn cluster askgptMarker contains=askgptUser,askgptAssistant,askgptSystem,askgptError,askgptDiscard

hi def link askgptUser      DiffAdd
hi def link askgptAssistant DiffChange
hi def link askgptSystem    DiffText
hi def link askgptError     DiffDelete
hi def link askgptDiscard   Comment
