vim9script

command -nargs=? -range -bang AskGPT if "<bang>" == "" | askgpt#Open(<q-args>, <range> != 0, <line1>, <line2>) | else | askgpt#Create(<q-args>, <range> != 0, <line1>, <line2>) | endif

g:askgpt_model        = get(g:, 'askgpt_model', 'gpt-3.5-turbo')
g:askgpt_history_size = get(g:, 'askgpt_history_size', 10)
g:askgpt_curl_command = get(g:, 'askgpt_curl_command', has('win32') ? ['curl.exe'] : ['curl'])
