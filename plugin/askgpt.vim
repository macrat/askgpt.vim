vim9script

command -nargs=? -range -bang AskGPT askgpt#Open(<q-args>, "<bang>" != "", <range> != 0, <line1>, <line2>)
command AskGPTRetry askgpt#Retry()

augroup askgpt-internal
  au BufReadCmd  askgpt:// askgpt#Init()
  au TextChanged askgpt:// askgpt#ScanAndFix()
augroup END

g:askgpt_model        = get(g:, 'askgpt_model', 'gpt-3.5-turbo')
g:askgpt_history_size = get(g:, 'askgpt_history_size', 10)
g:askgpt_curl_command = get(g:, 'askgpt_curl_command', has('win32') ? ['curl.exe'] : ['curl'])
