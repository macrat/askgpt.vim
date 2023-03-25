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

  const existwin = getwininfo()
    ->filter((idx, val) => getwinvar(val.winnr, '&filetype') == 'askgpt')
    ->sort((x, y) => getbufinfo(y.bufnr)->get('lastused', 0) - getbufinfo(x.bufnr)->get('lastused', 0))
    ->get(0, {})
    ->get('winnr', -1)
  if existwin < 0
    exec 'new ' .. strftime('%Y%m%d%H%M%S.askgpt.md')
    :$
  else
    exec ':' .. existwin .. 'wincmd w'
  endif

  if wipe
    askgpt#api#Cancel()
    askgpt#chatbuf#RemoveAll()

    SetSystemPrompt()
  endif

  if prompt != ''
    askgpt#chatbuf#AppendUser(bufnr(), prompt)
    ShareRange(bufnr(), range)
    Submit()
  else
    ShareRange(bufnr(), range)
  endif
enddef

export def TextChanged()
  # make sure that system prompt exists.
  if askgpt#chatbuf#FindLast(['Prompt']) == null_dict
    SetSystemPrompt()
  endif

  # make sure that user prompt exists.
  askgpt#chatbuf#GetUserPrompt(bufnr())
enddef

def SetSystemPrompt()
  const default_prompt = "You are AskGPT.vim, an AI conversation assistant.\n"
                      .. "Answer very concise and clear, shorter than 80 chars per line.\n"
                      .. "Chat syntax: markdown\n"
                      .. "File types user is editing: {filetypes}"
  askgpt#chatbuf#AppendSystemPrompt(bufnr(), get(g:, 'askgpt_prompt', default_prompt))
enddef

export def Retry()
  if !CheckSettingAndFeatures()
    return
  endif

  if askgpt#api#IsRunning()
    echoerr 'Cannot retry while generating message.'
    return
  endif

  const prompt = askgpt#chatbuf#GetUserPrompt(bufnr())

  var msg = askgpt#chatbuf#FindLast(['Assistant', 'Error'])
  if msg != null_dict
    while msg != null_dict && msg.id != prompt.id
      askgpt#chatbuf#Discard(bufnr(), msg.id)
      msg = askgpt#chatbuf#FindNext(bufnr(), msg.id)
    endwhile
  endif

  if askgpt#chatbuf#FindLast(['User']) == null_dict
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

  const contents = QuoteCodeBlock(range.ftype, range.content->join("\n"))-> split("\n")

  const msg = askgpt#chatbuf#AppendShare(bufnr(), join([
    'User has shared a part of file to Assistant.',
    '',
    'name: ' .. range.fname,
    'line: from ' .. range.from .. ' to ' .. range.to .. ' out of ' .. range.total,
    'content:',
  ] + contents + [
    '',
  ], "\n"))

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

export def Submit()
  if !CheckSettingAndFeatures()
    return
  endif

  const indicator = askgpt#chatbuf#AppendLoading(bufnr())

  const prompt = [{
    role: 'system',
    content: GeneratePrompt(),
  }]

  askgpt#api#RequestChat(
    indicator.id,
    g:askgpt_model,
    prompt + askgpt#chatbuf#GetHistory(g:askgpt_history_size),
    OnUpdate,
    OnFinish,
    OnError,
  )
enddef

def GeneratePrompt(): string
  var prompt = askgpt#chatbuf#GetSystemPrompt(bufnr())

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

final cancelled_ids = {}

def OnUpdate(buf: number, indicator: number, message: string)
  if has_key(cancelled_ids, string(indicator))
    return
  endif

  try
    askgpt#chatbuf#UpdateLoading(buf, indicator, message)
  catch
    cancelled_ids[string(indicator)] = 1
    askgpt#api#Cancel()
    echow 'Cancel generating'
  endtry
enddef

def OnFinish(buf: number, indicator: number, message: string)
  const deleted = askgpt#chatbuf#Delete(buf, indicator)
  if deleted
    askgpt#chatbuf#AppendAssistant(buf, message)
  endif
enddef

def OnError(buf: number, indicator: number, resp: string, status: number)
  const deleted = askgpt#chatbuf#Delete(buf, indicator)

  if !deleted || status < 0
    return
  endif

  try
    const error: dict<string> = json_decode(resp).error
    askgpt#chatbuf#AppendError(buf, '**' .. error.type .. '**: ' .. error.message)
  catch
    var resptype = 'json'
    try
      json_decode(resp)
    catch
      resptype = ''
    endtry
    askgpt#chatbuf#AppendError(buf, QuoteCodeBlock(resptype, resp) .. "\nStatus code: " .. status)
  endtry
enddef
