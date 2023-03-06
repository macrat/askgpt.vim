vim9script

const indicators = '▖▌▘▀▝▐▗▄'

export def Open(query='', wipe=false, useRange=false, rangeFrom=0, rangeTo=0)
  const range = useRange ? NewRange(rangeFrom, rangeTo) : null_dict

  const existwin = bufwinnr('askgpt://')
  if existwin < 0
    silent new askgpt://
  else
    exec ':' .. existwin .. 'wincmd w'
  endif

  if wipe
    if exists('b:askgpt_history')
      unlet b:askgpt_history
    endif
    if exists('b:askgpt_job') && b:askgpt_job != null
      job_stop(b:askgpt_job)
      unlet b:askgpt_job
    endif
    :%delete
  endif

  Init(query, range)
enddef

export def Init(query='', range: dict<any> = null_dict)
  if !exists('g:askgpt_api_key')
    echoerr 'Please set g:askgpt_api_key before use AskGPT.vim.'
    return
  endif

  set filetype=markdown buftype=prompt bufhidden=delete

  # delete previous prompt.
  :$-1delete

  if query == ''
    ShareRange(bufnr(), line('$') - 1, range)
    append(line('$') - 1, '__User__')
  else
    append(line('$') - 1, ['__User__', query])
    PushHistory(bufnr(), 'user', query)

    if range != null
      append(line('$') - 1, '')
      ShareRange(bufnr(), line('$') - 1, range)
      :$-1delete
    endif

    Submit()
  endif

  prompt_setprompt(bufnr(), '')
  prompt_setcallback(bufnr(), OnInput)

  norm zb
enddef

export def Retry()
  Open()

  if b:askgpt_job != null && job_status(b:askgpt_job) == 'run'
    echoe 'Cannot retry while generating message.'
    return
  endif

  if len(b:askgpt_history) <= 1
    echoe 'There is nothing to retry.'
    return
  endif

  b:askgpt_history = b:askgpt_history[: -1]
  :$-1,$delete

  Submit()
  append(line('$') - 5, '*retry*')
enddef

def NewRange(from: number, to: number): dict<any>
  return {
    fname: expand('%'),
    ftype: &filetype,
    from: from,
    to: to,
    total: line('$'),
    content: getline(from, to),
  }
enddef

def PushHistory(buf: number, role: string, content: string)
  var hs = getbufvar(buf, 'askgpt_history', [])

  hs += [{
    role: role,
    content: content,
  }]

  const maxhs = GetHistorySize()
  if len(hs) > maxhs + 1
    # retain maxhs + 1 for :AskGPTRetry
    hs = hs[-maxhs - 1 :]
  endif

  setbufvar(buf, 'askgpt_history', hs)
enddef

def GetHistorySize(): number
  if exists('g:askgpt_history_size')
    return g:askgpt_history_size
  endif
  return 10
enddef

def ShareRange(buf: number, lnum: number, range: dict<any>)
  if range == null
    return
  endif

  const maxquote = range.content->join("\n")->matchlist('```\+')->map((_, x) => strchars(x))->max()
  const quote = repeat('`', max([3, maxquote + 1]))

  PushHistory(buf, 'system', join([
    'Answer question using the following information.',
    '',
    'source name: ' .. range.fname,
    'lines: from ' .. range.from .. ' to ' .. range.to .. ' out of ' .. range.total .. 'lines',
    '',
    'content:',
    quote .. range.ftype,
  ] + range.content + [
    quote,
  ], "\n"))

  append(max([0, lnum]), [
    '__Share__',
    'name: ' .. range.fname,
    'line: ' .. range.from .. '-' .. range.to .. '/' .. range.total,
    'content:',
    quote .. range.ftype,
  ] + range.content + [
    quote,
    '',
  ])

  exec ':' .. (lnum + 5) .. ',' .. (lnum + 6 + len(range.content)) .. 'fold'
  norm zb
enddef

def OnInput(text: string)
  const query = trim(text)
  if query == ''
    :$-1delete
    return
  endif

  if exists('b:askgpt_job') && b:askgpt_job != null
    job_stop(b:askgpt_job)
    unlet b:askgpt_job
    :$-5,$-3delete
    :$
  endif

  PushHistory(bufnr(), 'user', query)

  Submit()
enddef

def Submit()
  append(line('$') - 1, [
    '',
    '__Assistant__',
    has('timers') ? indicators[0] : 'loading...',
    '',
    '__User__',
  ])

  if has('timers') && (!exists('b:askgpt_indicator_count') || b:askgpt_indicator_count == null)
    const buf = bufnr()
    setbufvar(buf, 'askgpt_indicator_count', 0)
    timer_start(100, (id: number) => UpdateIndicator(buf))
  endif

  const cmd = GetCurlCommand() + ['https://api.openai.com/v1/chat/completions', '--silent', '-H', 'Content-Type: application/json', '-H', 'Authorization: Bearer ' .. g:askgpt_api_key, '-d', '@-']
  #const cmd = ['sh', '-c', "sleep 1; echo '" .. '{"choices":[{"message":{"role":"assistant","content":"hello world"}}]}' .. "'"]
  #const cmd = ['sh', '-c', 'sleep 1; cat -; exit 1']

  const buf = bufnr()
  b:askgpt_job = job_start(cmd, {
    callback: (ch: channel, resp: string) => OnResponse(buf, resp),
    exit_cb: (job: job, status: number) => OnExit(buf, status),
    in_mode: 'json',
    out_mode: 'raw',
    err_mode: 'raw',
  })

  const prompt = [{
    role: 'system',
    content: join([
      'You are AskGPT.vim, an AI assistant for conversation.',
      'Answer very succinctly and clearly, in Markdown.',
      'Keep answer shorter than 80 characters per line.',
      '',
      'Usage of AskGPT.vim: see `:help askgpt`',
      'File types that user is editing: ' .. GetEditingFileTypes()->join(', '),
      'Current date: ' .. strftime('%Y-%m-%d %A'),
    ], "\n"),
  }]

  const channel = job_getchannel(b:askgpt_job)
  ch_sendraw(channel, json_encode({
    model: 'gpt-3.5-turbo',
    messages: prompt + b:askgpt_history[-min([len(b:askgpt_history), GetHistorySize()]) : ],
  }))
  ch_close_in(channel)
enddef

def GetCurlCommand(): list<string>
  if exists('g:askgpt_curl_command')
    return g:askgpt_curl_command
  endif
  return ['curl']
enddef

def GetEditingFileTypes(): list<string>
  return getwininfo()->filter((_, win) => bufname(win.bufnr) !~ '^askgpt://')->map((_, win) => getwinvar(win.winid, '&ft'))->sort()->uniq()
enddef

def OnResponse(buf: number, resp: string)
  const lastline = getbufinfo(buf)[0].linecount

  var content = ''

  try
    const msg: dict<string> = json_decode(resp).choices[0].message

    content = msg.content
    PushHistory(buf, msg.role, content)
  catch
    setbufline(buf, lastline - 4, '__Error__')
    var resptype = 'json'
    try
      json_decode(resp)
    catch
      resptype = ''
    endtry
    content = "Unexpected response:\n```" .. resptype .. "\n" .. resp .. "\n```"
  endtry

  deletebufline(buf, lastline - 3)
  appendbufline(buf, lastline - 4, split(content, "\n"))

  setbufvar(buf, 'askgpt_job', null)
enddef

def OnExit(buf: number, status: number)
  const job = getbufvar(buf, 'askgpt_job', null_job)

  if status > 0
    const lastline = getbufinfo(buf)[0].linecount

    appendbufline(buf, lastline - 3, 'Exit status: ' .. status)
    if job != null && job_status(job) != 'run'
      deletebufline(buf, lastline - 3)
    endif
  endif

  if job != null && job_status(job) != 'run'
    setbufvar(buf, 'askgpt_job', null)
  endif
enddef

def UpdateIndicator(buf: number)
  if getbufvar(buf, 'askgpt_job', null) == null
    setbufvar(buf, 'askgpt_indicator_count', null)
    return
  endif

  const i = (getbufvar(buf, 'askgpt_indicator_count', 0) + 1) % strchars(indicators)
  setbufvar(buf, 'askgpt_indicator_count', i)

  const lastline = getbufinfo(buf)[0].linecount
  setbufline(buf, lastline - 3, indicators[i])

  timer_start(100, (id: number) => UpdateIndicator(buf))
enddef
