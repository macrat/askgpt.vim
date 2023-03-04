vim9script

const indicators = '▖▌▘▀▝▐▗▄'

export def Open(query='', wipe=false, useRange=false, rangeFrom=0, rangeTo=0)
  const range = useRange ? NewRange(rangeFrom, rangeTo) : null_dict

  const existwin = bufwinnr('askgpt://')
  if existwin < 0
    exec 'silent new askgpt://'
  else
    exec ':' .. existwin .. 'wincmd w'
  endif

  if wipe
    if exists('b:askgpt_history')
      unlet b:askgpt_history
    endif
    exec ':%delete'
  endif

  Init(query, range)
enddef

export def Init(query='', range: dict<any> = null_dict)
  if !exists('g:askgpt_api_key')
    echoerr 'Please set g:askgpt_api_key before use AskGPT.vim.'
    return
  endif

  set filetype=markdown buftype=prompt

  if range != null
    ShareRange(bufnr(), range)
  endif

  # delete previous prompt.
  exec ':$-1delete'

  append(line('$') - 1, '__User__')

  if query != ''
    append(line('$') - 1, query)
    PushHistory(bufnr(), 'user', query)
    OnInput(query)
  endif

  prompt_setprompt(bufnr(), '')
  prompt_setcallback(bufnr(), OnInput)
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
  if len(hs) > maxhs
    hs = hs[len(hs) - maxhs :]
  endif

  setbufvar(buf, 'askgpt_history', hs)
enddef

def GetHistorySize(): number
  if exists('g:askgpt_history_size')
    return g:askgpt_history_size
  endif
  return 10
enddef

def ShareRange(buf: number, range: dict<any>)
  PushHistory(buf, 'system', join([
    'User has shared you a part of current editing file.',
    'You can ask user to provide more if you needed.',
    '',
    'source file name: ' .. range.fname,
    '',
    'shared range: from line ' .. range.from .. ' to line ' .. range.to .. ' out of ' .. range.total .. 'lines',
    '',
    'content:',
    '```' .. range.ftype,
  ] + range.content + [
    '```',
  ], "\n"))

  const lnum = line('$') - 2
  append(max([0, lnum]), [
    '__Share__',
    'name: ' .. range.fname,
    'line: ' .. range.from .. '-' .. range.to .. '/' .. range.total,
    '',
    '```' .. range.ftype,
  ] + range.content + [
    '```',
    '',
  ] + (lnum < 0 ? [''] : []))
enddef

def OnInput(text: string)
  const query = trim(text)
  if query == ''
    exec ':$-1delete'
    return
  endif

  if exists('b:askgpt_job') && b:askgpt_job != null
    job_stop(b:askgpt_job)
    exec ':$-5,$-3delete'
    exec ':$'
  endif

  PushHistory(bufnr(), 'user', query)

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

  const cmd = ['curl', 'https://api.openai.com/v1/chat/completions', '--silent', '-H', 'Content-Type: application/json', '-H', 'Authorization: Bearer ' .. g:askgpt_api_key, '-d', '@-']
  #const cmd = ['sh', '-c', "sleep 1; echo '" .. '{"choices":[{"message":{"role":"assistant","content":"hello world"}}]}' .. "'"]
  #const cmd = ['cat', '-']

  const buf = bufnr()
  b:askgpt_job = job_start(cmd, {
    callback: (ch: channel, resp: string) => OnResponse(buf, resp),
  })

  const prompt = [{
    role: 'system',
    content: join([
      'You are an AI chat assistant embedded in a text editor Vim.',
      'You help your user with brief and clear responses.',
      'The chat is written in Markdown syntax.',
    ], "\n"),
  }, {
    role: 'system',
    content: join([
      'File types that user is editing now: ' .. GetEditingFileTypes()->join(', '),
    ], "\n"),
  }]

  const channel = job_getchannel(b:askgpt_job)
  ch_sendraw(channel, json_encode({
    model: 'gpt-3.5-turbo',
    messages: prompt + b:askgpt_history,
  }))
  ch_close_in(channel)
enddef

def GetEditingFileTypes(): list<string>
  return getwininfo()->map((_, win) => getwinvar(win['winid'], '&ft'))->sort()->uniq()
enddef

def OnResponse(buf: number, resp: string)
  const lastline = getbufinfo(buf)[0]['linecount']

  var content = ''

  try
    const msg = json_decode(resp)['choices'][0]['message']

    content = msg['content']
    PushHistory(buf, msg['role'], content)
  catch
    setbufline(buf, lastline - 4, '__Error__')
    content = "Unexpected response:\n```json\n" .. resp .. "\n```"
  endtry

  deletebufline(buf, lastline - 3)
  appendbufline(buf, lastline - 4, split(content, "\n"))

  setbufvar(buf, 'askgpt_job', null)
enddef

def UpdateIndicator(buf: number)
    if getbufvar(buf, 'askgpt_job', null) == null
      setbufvar(buf, 'askgpt_indicator_count', null)
      return
    endif

    const i = (getbufvar(buf, 'askgpt_indicator_count', 0) + 1) % strchars(indicators)
    setbufvar(buf, 'askgpt_indicator_count', i)

    const lastline = getbufinfo(buf)[0]['linecount']
    setbufline(buf, lastline - 3, indicators[i])

    timer_start(100, (id: number) => UpdateIndicator(buf))
enddef
