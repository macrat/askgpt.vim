vim9script

const indicators = '▖▌▘▀▝▐▗▄'

export def Init()
  if !exists('g:askgpt_api_key')
    echoerr 'Please set g:askgpt_api_key before use this plugin.'
    return
  endif

  const winid = win_getid()
  exec 'vert rightb new askgpt://' .. winid
  b:askgpt_winid = winid
  if winwidth(0) > 40
    vert resize 40
  endif

  set filetype=markdown buftype=prompt

  if !exists('b:askgpt_history')
    b:askgpt_history = []
  endif

  append(0, '__User__')
  prompt_setprompt(bufnr(), '')
  prompt_setcallback(bufnr(), OnInput)
enddef

def PushHistory(buf: number, role: string, content: string)
  var hs = getbufvar(buf, 'askgpt_history', [])

  hs += [{
    role: role,
    content: content,
  }]

  if len(hs) > 6
    hs = hs[len(hs) - 6 :]
  endif

  setbufvar(buf, 'askgpt_history', hs)
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

  const buf = bufnr()
  b:askgpt_job = job_start(cmd, {
    callback: (ch: channel, resp: string) => OnResponse(buf, resp),
  })

  const prompt = [{
    role: 'system',
    content: "You are an AI assistant embedded in a text editor Vim.\nYou help your user with short and clear responses in Markdown syntax.\nYour user normally ask about the content around the cursor line.",
  }, {
    role: 'system',
    content: join([
      'current file name is: ' .. trim(win_execute(b:askgpt_winid, ':echo expand("%")')),
      '',
      'cursor position is: line=' .. line('.', b:askgpt_winid) .. ' column=' .. charcol('.', b:askgpt_winid) .. ':',
      '> ' .. getbufoneline(winbufnr(b:askgpt_winid), line('.', b:askgpt_winid)),
      '',
      'file content is:',
      '```' .. getwinvar(b:askgpt_winid, '&filetype'),
    ] + getbufline(winbufnr(b:askgpt_winid), 0, '$') + [
      '```',
    ], "\n"),
  }]

  const channel = job_getchannel(b:askgpt_job)
  ch_sendraw(channel, json_encode({
    model: 'gpt-3.5-turbo',
    messages: prompt + b:askgpt_history,
  }))
  ch_close_in(channel)
enddef

def OnResponse(buf: number, resp: string)
  var content = ''

  try
    const msg = json_decode(resp)['choices'][0]['message']

    content = msg['content']
    PushHistory(buf, msg['role'], content)
  catch
    content = "Unexpected response:\n```json\n" .. resp .. "\n```"
  endtry

  const lastline = getbufinfo(buf)[0]['linecount']
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
