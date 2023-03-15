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

  const range = useRange ? CaptureRange(rangeFrom, rangeTo) : null_dict

  const existwin = bufwinnr('askgpt://')
  if existwin < 0
    silent new askgpt://
  else
    exec ':' .. existwin .. 'wincmd w'
  endif

  if wipe
    askgpt#api#Cancel()
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

  if askgpt#api#IsRunning()
    echoerr 'Cannot retry while generating message.'
    return
  endif

  const prompt = askgpt#chatbuf#GetPrompt()

  var msg = askgpt#chatbuf#GetLastOfTypes(['assistant', 'error'])
  if msg != null_dict
    while msg != null_dict && msg.id != prompt.id
      if msg.type != 'discard'
        askgpt#chatbuf#Discard(msg.id)
      endif
      msg = askgpt#chatbuf#GetNext(msg.id)
    endwhile
  endif

  if askgpt#chatbuf#GetLastOfType('user') == null_dict
    echoerr 'There is nothing to retry.'
    return
  endif

  Submit()
enddef

def CaptureRange(from: number, to: number): dict<any>
  return {
    fname: expand('%'),
    ftype: &filetype,
    from: from,
    to: to,
    total: line('$'),
    content: getline(from, to),
  }
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

def Submit()
  const indicator = askgpt#chatbuf#AppendLoading()

  const prompt = [{
    role: 'system',
    content: GeneratePrompt(),
  }]

  askgpt#api#Request(indicator.id, '/v1/chat/completions', {
    model: 'gpt-3.5-turbo',
    messages: prompt + askgpt#chatbuf#GetHistory(GetHistorySize()),
  }, OnResponse)
enddef

def GeneratePrompt(): string
  const default_prompt = "You are AskGPT.vim, an AI conversation assistant.\n"
    .. "Answer very concise and clear, shorter than 80 chars per line.\n"
    .. "Chat syntax: markdown\n"
    .. "File types user is editing: {filetypes}"
  var prompt = get(g:, 'askgpt_prompt', default_prompt)

  if prompt =~ '{filetypes}'
    prompt = substitute(prompt, '{filetypes}', GetEditingFileTypes()->join(', '), 'g')
  endif

  if prompt =~ '{date}'
    prompt = substitute(prompt, '{date}', strftime('%Y-%m-%d'), 'g')
  endif
  if prompt =~ '{weekday}'
    prompt = substitute(prompt, '{weekday}', strftime('%A'), 'g')
  endif
  if prompt =~ '{time}'
    prompt = substitute(prompt, '{time}', strftime('%H:%M'), 'g')
  endif

  return prompt
enddef

def GetEditingFileTypes(): list<string>
  return getwininfo()
    ->filter((_, win) => bufname(win.bufnr) !~ '^askgpt://')
    ->map((_, win) => getwinvar(win.winid, '&ft'))
    ->sort()
    ->uniq()
enddef

def GetHistorySize(): number
  if exists('g:askgpt_history_size')
    return g:askgpt_history_size
  endif
  return 10
enddef

def OnResponse(buf: number, indicator: number, resp: string, status: number)
  const deleted = askgpt#chatbuf#Delete(indicator, buf)

  if !deleted || status < 0
    return
  endif

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
    askgpt#chatbuf#AppendError(QuoteCodeBlock(resptype, resp) .. "\nStatus code: " .. status, buf)
  endtry
enddef
