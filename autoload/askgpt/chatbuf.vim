vim9script

const indicators = '▖▌▘▀▝▐▗▄'

var message_id = 0

export const marker_pattern = '\C^\[__\(User\|Assistant\|Share\|Prompt\|Error\)__\]$'
export const all_marker_pattern = '\C^\[\(__\|\~\~\)\(User\|Assistant\|Share\|Prompt\|Error\)\1\]$'

export def RemoveAll()
  :%delete
  AppendUserPrompt(bufnr())
  :1delete
  :$
enddef

export def Submit()
  const prompt = GetUserPrompt(bufnr())
  if prompt.lnum > line('.')
    return
  endif

  const input =  getline(prompt.lnum + 1, '$')->join("\n")->trim()
  if len(input) == 0
    return
  endif

  deletebufline(bufnr(), prompt.lnum + 1, '$')
  setline(prompt.lnum + 1, split(input, "\n") + [''])

  AppendUserPrompt(bufnr())
  :$
  silent! exec ':' .. prompt.lnum .. ',' .. (line('$') - 2) .. 'fold | :' .. (prompt.lnum + 1) .. 'foldopen'
  askgpt#Submit()
enddef

def AppendUserPrompt(buf: number): dict<any>
  ++message_id

  final prompt = ['[__User__]', '']

  if getbufoneline(buf, GetLineCount(buf)) != ''
    insert(prompt, '')
  endif

  appendbufline(buf, GetLineCount(buf), prompt)
  SetProp(buf, GetLineCount(buf) - 1, message_id, 'message')

  return {
    id:   message_id,
    lnum: GetLineCount(buf) - 1,
    name: 'User',
  }
enddef

def SetProp(buf: number, lnum: number, id: number, type: string)
  try
    prop_type_add('askgpt_' .. type, {bufnr: buf})
  catch
  endtry

  prop_add(lnum, 1, {
    bufnr: buf,
    id:    message_id,
    type:  'askgpt_' .. type,
  })
enddef

def AppendMessage(buf: number, name: string, content: string): dict<any>
  const prompt = GetUserPrompt(buf)

  return WriteMessage(buf, prompt.lnum, name, content)
enddef

def WriteMessage(buf: number, lnum: number, name: string, content: string): dict<any>
  const contents = (content->trim("\n")->substitute(all_marker_pattern, '[ \1\2\1 ]', 'g') .. "\n\n")->split("\n")

  appendbufline(buf, lnum - 1, ['[__' .. name .. '__]'] + contents)

  ++message_id
  SetProp(buf, lnum, message_id, 'message')

  silent! exec ':' .. lnum .. ',' .. (lnum + len(contents)) .. 'fold | :' .. (lnum + 1) .. 'foldopen'

  while getbufline(buf, lnum + 1 + len(contents)) == ['']
    deletebufline(buf, lnum + 1 + len(contents))
  endwhile

  return {
    id:   message_id,
    lnum: lnum,
    name: name,
  }
enddef

export def AppendUser(buf: number, content: string): dict<any>
  return AppendMessage(buf, 'User', content)
enddef

export def AppendAssistant(buf: number, content: string): dict<any>
  return AppendMessage(buf, 'Assistant', content)
enddef

export def AppendShare(buf: number, content: string): dict<any>
  return AppendMessage(buf, 'Share', content)
enddef

export def AppendSystemPrompt(buf: number, content: string): dict<any>
  const lnum = getbufoneline(buf, 1) =~ 'vim:' ? 2 : 1
  const msg = WriteMessage(buf, lnum, 'Prompt', content)
  silent! exec ':' .. msg.lnum .. 'foldclose'
  return msg
enddef

export def AppendError(buf: number, content: string): dict<any>
  return AppendMessage(buf, 'Error', content)
enddef

export def AppendLoading(buf: number): dict<any>
  const prop = AppendMessage(buf, 'Assistant', indicators[get(b:, 'askgpt_indicator_phase', 0)])
  SetProp(buf, prop.lnum + 1, prop.id, 'indicator')

  b:askgpt_loading_text = getbufvar(buf, 'askgpt_loading_text', {})

  timer_start(100, (timer) => UpdateIndicator(buf, prop.id))

  return prop
enddef

export def UpdateLoading(buf: number, id: number, message: string)
  final texts = getbufvar(buf, 'askgpt_loading_text', {})
  texts[string(id)] = message
enddef

def UpdateTextProps(buf: number)
  var quote = 0
  for lnum in range(1, GetLineCount(buf))
    const line = getbufoneline(buf, lnum)
    if quote == 0 && line =~ all_marker_pattern
      UpdateOneTextProp(buf, lnum)
    else
      if quote == 0 && line =~ '^\s*`\{3,\}'
        quote = matchstr(line, '^\s*\zs`\{3,\}')->strchars()
      elseif quote > 0 && line =~ '^\s*`\{' .. quote .. '\}\s*$'
        quote = 0
      endif

      try
        prop_remove({bufnr: buf, types: ['askgpt_message']}, lnum)
      catch
      endtry
    endif
  endfor
enddef

def UpdateOneTextProp(buf: number, lnum: number): number
  const props = prop_list(lnum, {bufnr: buf, type: 'askgpt_message'})
  if len(props) > 0
    return props[0].id
  endif

  ++message_id
  SetProp(buf, lnum, message_id, 'message')
  return message_id
enddef

export def GetUserPrompt(buf: number): dict<any>
  UpdateTextProps(buf)

  const prop = prop_find({
    bufnr: buf,
    type:  'askgpt_message',
    lnum:  GetLineCount(buf),
  }, 'b')

  if len(prop) == 0 || getbufoneline(buf, prop.lnum) != '[__User__]'
    return AppendUserPrompt(bufnr())
  endif

  return {
    id:   prop.id,
    lnum: prop.lnum,
    name: 'User',
  }
enddef

def GetLineCount(buf: number = 0): number
  return getbufinfo(buf ?? bufnr())->get(0, {})->get('linecount', 0)
enddef

export def FindLast(names: list<string>): dict<any>
  const view = winsaveview()
  defer winrestview(view)

  :$
  search('\C^\[__User__\]$', 'bW')

  var lnum = 0
  var name = ''
  for n in names
    const l = search('\C^\[__' .. n .. '__\]$', 'bnW')
    if 0 < l && lnum < l
      lnum = l
      name = n
    endif
  endfor
  if lnum == 0
    return null_dict
  endif

  const id = UpdateOneTextProp(bufnr(), lnum)

  return {
    id:   id,
    lnum: lnum,
    name: name,
  }
enddef

export def FindNext(buf: number, id: number): dict<any>
  const base = prop_find({bufnr: buf, id: id, type: 'askgpt_message', both: true, lnum: 1}, 'f')
  if len(base) == 0
    return null_dict
  endif

  while true
    const next = prop_find({bufnr: buf, type: 'askgpt_message', lnum: base.lnum, skipstart: true}, 'f')
    if len(next) == 0
      return null_dict
    endif

    const line = getbufoneline(bufnr(), next.lnum)
    if line =~ marker_pattern
      return {
        id:   next.id,
        lnum: next.id,
        name: line->substitute(marker_pattern, '\1', ''),
      }
    endif
  endwhile

  return null_dict
enddef

export def Delete(buf: number, id: number): bool
  const start = prop_find({bufnr: buf, id: id, type: 'askgpt_message', both: true, lnum: 1}, 'f')
  if len(start) == 0
    return false
  endif

  final end = prop_find({bufnr: buf, type: 'askgpt_message', lnum: start.lnum, skipstart: true}, 'f')
  if len(end) == 0
    end['lnum'] = GetLineCount(buf)
    defer AppendUserPrompt(bufnr())
  endif

  deletebufline(buf ?? bufnr(), start.lnum, end.lnum - 1)

  return true
enddef

export def Discard(buf: number, id: number): bool
  const prop = prop_find({bufnr: buf, id: id, type: 'askgpt_message', both: true, lnum: 1}, 'f')
  if len(prop) == 0
    return false
  endif

  const ln = getbufoneline(buf, prop.lnum)
  if ln !~ marker_pattern
    return false
  endif

  ln->substitute(marker_pattern, '[~~\1~~]', '')->setbufline(buf, prop.lnum)
  SetProp(buf, prop.lnum, id, 'message')

  return true
enddef

export def GetSystemPrompt(buf: number): string
  const prop = FindLast(['Prompt'])
  if prop == null_dict
    return ''
  endif

  const next = prop_find({bufnr: buf, type: 'askgpt_message', lnum: prop.lnum + 1}, 'f')

  return getbufline(buf, prop.lnum + 1, (get(next, 'lnum', 1) - 1) ?? '$')->join("\n")->trim("\n")
enddef

export def GetHistory(max: number): list<dict<string>>
  UpdateTextProps(bufnr())

  var lnum = prop_find({type: 'askgpt_message', lnum: line('$')}, 'b').lnum

  final msgs: list<dict<string>> = []

  while len(msgs) < max
    const prop = prop_find({type: 'askgpt_message', lnum: lnum, skipstart: true}, 'b')
    if len(prop) == 0
      break
    endif

    const name = getbufoneline(bufnr(), prop.lnum)->substitute('\C^\[__\(User\|Assistant\|Share\)__\]$', '\1', '')
    if index(['User', 'Assistant', 'Share'], name) < 0
      lnum = prop.lnum
      continue
    endif

    const role = {
      'User':      'user',
      'Assistant': 'assistant',
      'Share':     'system',
    }[name]

    insert(msgs, {
      role:    role,
      content: getline(prop.lnum + 1, lnum - 1)->join("\n")->trim("\n"),
    })

    lnum = prop.lnum
  endwhile

  return msgs
enddef

def UpdateIndicator(buf: number, id: number)
  const start = prop_find({bufnr: buf, id: id, type: 'askgpt_message', both: true, lnum: 1}, 'f')
  const end = prop_find({bufnr: buf, id: id, type: 'askgpt_indicator', both: true, lnum: get(start, 'lnum', 1) + 1}, 'f')
  if len(start) == 0 || len(end) == 0
    final texts = getbufvar(buf, 'askgpt_loading_text', {})
    try
      remove(texts, string(id))
    catch
    endtry
    return
  endif

  const phase = (getbufvar(buf, 'askgpt_indicator_phase', 0) + 1) % strchars(indicators)
  setbufvar(buf, 'askgpt_indicator_phase', phase)

  const text = get(getbufvar(buf, 'askgpt_loading_text', {}), string(id), '')

  var contents = [indicators[phase]]
  if text != ''
    contents = split(text .. ' ' .. indicators[phase], "\n")
  endif

  deletebufline(buf, start.lnum + 1, end.lnum)
  appendbufline(buf, start.lnum, contents)

  SetProp(buf, start.lnum + len(contents), id, 'indicator')

  timer_start(100, (timer) => UpdateIndicator(buf, id))
enddef
