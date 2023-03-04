vim9script

command -nargs=? -range -bang AskGPT askgpt#Open(<q-args>, "<bang>" != "", <range> != 0, <line1>, <line2>)

augroup askgpt-internal
  au BufNewFile askgpt:// askgpt#Init()
augroup END
