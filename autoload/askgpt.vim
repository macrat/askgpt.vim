vim9script

def CheckSettingAndFeatures(): bool
  if !exists('g:askgpt_api_key')
    echoerr 'Please set g:askgpt_api_key before use AskGPT.vim.'
    return false
  endif
  if !has('job') || !has('channel')
    echoerr 'AskGPT.vim requires +job and +channel features.'
    return false
  endif
  return true
enddef

export def Open(prompt='', wipe=false, useRange=false, rangeFrom=0, rangeTo=0)
  if !CheckSettingAndFeatures()
    return
  endif

  const range = useRange ? NewRange(rangeFrom, rangeTo) : null_dict

  const existwin = bufwinnr('askgpt://')
  if existwin < 0
    silent new askgpt://
  else
    exec ':' .. existwin .. 'wincmd w'
  endif

  if wipe
    CancelJob()
    askgpt#chatbuf#RemoveAll()
  endif

  if prompt != ''
    askgpt#chatbuf#AppendUser(prompt)
    ShareRange(bufnr(), range)
    Submit()
  else
    ShareRange(bufnr(), range)
  endif
enddef

export def Init()
  if !CheckSettingAndFeatures()
    return
  endif

  askgpt#chatbuf#Init(Submit)
enddef

export def Retry()
  Open()

  if exists('b:askgpt_job') && b:askgpt_job != null && job_status(b:askgpt_job) == 'run'
    echoerr 'Cannot retry while generating message.'
    return
  endif

  const prompt = askgpt#chatbuf#GetPrompt()

  var msg = askgpt#chatbuf#GetLastOfType('assistant')
  if msg != null_dict
    while msg != null_dict && msg.id != prompt.id
      if msg.type != 'error' && msg.type != 'discard'
        askgpt#chatbuf#Discard(msg.id)
      endif
      msg = askgpt#chatbuf#GetNext(msg.id)
    endwhile
  endif

  if askgpt#chatbuf#GetLastOfType('user') == null_dict
    echoerr 'There is nothing to retry.'
  endif

  Submit()
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

def GetHistorySize(): number
  if exists('g:askgpt_history_size')
    return g:askgpt_history_size
  endif
  return 10
enddef

def ShareRange(buf: number, range: dict<any>)
  if range == null_dict
    return
  endif

  const content = QuoteCodeBlock(range.ftype, range.content->join("\n"))

  const msg = askgpt#chatbuf#AppendSystem('Share', join([
    'User has shared a part of file to Assistant.',
    '',
    'name: ' .. range.fname,
    'line: from ' .. range.from .. ' to ' .. range.to .. ' out of ' .. range.total,
    'content:',
  ] + content->split("\n") + [
    '',
  ], "\n"))

  exec ':' .. (msg.lnum + 6) .. ',' .. (msg.lnum + 7 + len(range.content)) .. 'fold'
  norm Gzb
enddef

def QuoteCodeBlock(filetype: string, code: string): string
  const maxquote = code
    ->matchlist('```\+')
    ->map((_, x) => strchars(x))
    ->max()

  const quote = repeat('`', max([3, maxquote + 1]))

  return quote .. filetype .. "\n" .. code .. "\n" .. quote
enddef

def CancelJob()
  if exists('b:askgpt_job') && b:askgpt_job != null
    job_stop(b:askgpt_job)
    unlet b:askgpt_job

    askgpt#chatbuf#DeleteLoadings()
  endif
enddef

def Submit()
  CancelJob()
  const indicator = askgpt#chatbuf#AppendLoading()

  const cmd = GetCurlCommand('/v1/chat/completions')
  #const cmd = ['sh', '-c', "sleep 1; echo '" .. '{"choices":[{"message":{"role":"assistant","content":"hello world"}}]}' .. "'"]
  #const cmd = ['sh', '-c', 'sleep 1; cat -; exit 1']

  const buf = bufnr()
  b:askgpt_job = job_start(cmd, {
    callback: (ch: channel, resp: string) => OnResponse(buf, indicator.id, resp),
    exit_cb: (job: job, status: number) => OnExit(buf, indicator.id, status),
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
      'File types that user is editing: ' .. GetEditingFileTypes()->join(', '),
      'Current date: ' .. strftime('%Y-%m-%d %A'),
    ], "\n"),
  }]

  const channel = job_getchannel(b:askgpt_job)
  ch_sendraw(channel, json_encode({
    model: 'gpt-3.5-turbo',
    messages: prompt + askgpt#chatbuf#GetHistory(GetHistorySize()),
  }))
  ch_close_in(channel)
enddef

def GetCurlCommand(endpoint: string): list<string>
  var curl = ['curl']
  if exists('g:askgpt_curl_command')
    curl = g:askgpt_curl_command
  endif

  return curl + [
    'https://api.openai.com' .. endpoint,
    '--silent',
    '-H',
    'Content-Type: application/json',
    '-H',
    'Authorization: Bearer ' .. g:askgpt_api_key,
    '-d',
    '@-',
  ]
enddef

def GetEditingFileTypes(): list<string>
  return getwininfo()
    ->filter((_, win) => bufname(win.bufnr) !~ '^askgpt://')
    ->map((_, win) => getwinvar(win.winid, '&ft'))
    ->sort()
    ->uniq()
enddef

def OnResponse(buf: number, indicator: number, resp: string)
  askgpt#chatbuf#Delete(indicator, buf)

  try
    const msg: dict<string> = json_decode(resp).choices[0].message

    askgpt#chatbuf#AppendAssistant(msg.content, buf)
  catch
    var resptype = 'json'
    try
      json_decode(resp)
    catch
      resptype = ''
    endtry
    askgpt#chatbuf#AppendError(QuoteCodeBlock(resptype, resp), buf)
  endtry

  setbufvar(buf, 'askgpt_job', null)
enddef

def OnExit(buf: number, indicator: number, status: number)
  const job = getbufvar(buf, 'askgpt_job', null_job)

  if status >= 0
    const deleted = askgpt#chatbuf#Delete(indicator)
    if deleted
      askgpt#chatbuf#AppendError('Status code: ' .. status, buf)
    endif
  endif

  if job != null && job_status(job) != 'run'
    setbufvar(buf, 'askgpt_job', null)
  endif
enddef
