vim9script

command -nargs=? -range -bang AskGPT if "<bang>" == "" | askgpt#Open(<q-args>, <range> != 0, <line1>, <line2>) | else | askgpt#Create(<q-args>, <range> != 0, <line1>, <line2>) | endif

g:askgpt_api_key      = get(g:, 'askgpt_api_key', '')
g:askgpt_history_size = get(g:, 'askgpt_history_size', 10)
g:askgpt_model        = get(g:, 'askgpt_model', 'gpt-3.5-turbo')
g:askgpt_prompt       = get(g:, 'askgpt_prompt', join([
  "You are AskGPT.vim, an AI conversation assistant.",
  "Answer very concisely and clearly.",
  "",
  "Chat syntax: markdown",
  "File types user is editing: {filetypes}",
], "\n"))

g:askgpt_file_name        = get(g:, 'askgpt_file_name', 'askgpt-%Y%m%dT%H%M%S.md')
g:askgpt_use_default_maps = get(g:, 'askgpt_use_default_maps', true)

g:askgpt_curl_command = get(g:, 'askgpt_curl_command', has('win32') ? ['curl.exe'] : ['curl'])
