vim9script

const indicators = '▖▌▘▀▝▐▗▄'

var message_id = 0

export def Init(OnSubmit: func())
  setl buftype=nofile filetype=markdown foldlevel=1 foldtext=FoldText()

  b:askgpt_on_submit = OnSubmit

  nmap <silent><buffer> <Plug>(askgpt-submit) :<C-U>call askgpt#chatbuf#Submit()<CR>
  imap <silent><buffer> <Plug>(askgpt-submit) <C-O>:<C-U>call askgpt#chatbuf#Submit()<CR>

  if !exists('g:askgpt_use_default_maps') || g:askgpt_use_default_maps
    imap <buffer> <Return> <Plug>(askgpt-submit)
    nmap <buffer> <Return> <Plug>(askgpt-submit)
  endif

  prop_type_add('askgpt_message', {bufnr: bufnr()})
  prop_type_add('askgpt_user', {bufnr: bufnr(), highlight: 'DiffAdd'})
  prop_type_add('askgpt_assistant', {bufnr: bufnr(), highlight: 'DiffChange'})
  prop_type_add('askgpt_system', {bufnr: bufnr(), highlight: 'DiffText'})
  prop_type_add('askgpt_loading', {bufnr: bufnr(), highlight: 'DiffChange'})
  prop_type_add('askgpt_discard', {bufnr: bufnr(), highlight: 'Comment'})
  prop_type_add('askgpt_error', {bufnr: bufnr(), highlight: 'DiffDelete'})

  AppendPrompt()
  :1delete
  :$

  # clear undo history
  const old_ul = &undolevels
  setl undolevels=-1
  exe "norm a \<BS>\<Esc>"
  &undolevels = old_ul
enddef

export def RemoveAll()
  :%delete
  AppendPrompt()
  :1delete
  :$
enddef

export def Submit()
  const prompt = GetPrompt()
  if prompt.lnum > line('.')
    return
  endif

  const input =  getline(prompt.lnum + 1, '$')->join("\n")->trim()
  if len(input) == 0
    return
  endif

  deletebufline(bufnr(), prompt.lnum + 1, '$')
  setline(prompt.lnum + 1, split(input, "\n") + [''])

  exec ':' .. prompt.lnum .. ',$fold'
  exec ':' .. prompt.lnum .. 'foldopen'

  AppendPrompt()
  b:askgpt_on_submit()
enddef

def AppendPrompt(): dict<any>
  ++message_id

  append('$', ['__User__', ''])
  prop_add(line('$') - 1, 1, {
    id: message_id,
    type: 'askgpt_message',
  })
  prop_add(line('$') - 1, 1, {
    id: message_id,
    length: len(getline(line('$') - 1)),
    type: 'askgpt_user',
  })
  :$

  return {
    id: message_id,
    lnum: line('$') - 1,
    type: 'user',
  }
enddef

def AppendMessage(type: string, name: string, content: string, buf: number = 0): dict<any>
  ++message_id

  const pos = prop_find({bufnr: buf, type: 'askgpt_user', lnum: line('$')}, 'b')

  const contents = (content->trim("\n") .. "\n\n")->split("\n")

  appendbufline(buf ?? bufnr(), pos.lnum - 1, ['__' .. name .. '__'] + contents)
  prop_add(pos.lnum, 1, {
    bufnr: buf,
    id: message_id,
    type: 'askgpt_message',
  })
  prop_add(pos.lnum, 1, {
    bufnr: buf,
    id: message_id,
    length: len(getline(pos.lnum)),
    type: 'askgpt_' .. type,
  })

  win_execute(win_findbuf(buf ?? bufnr())[0], ':' .. pos.lnum .. ',' .. (pos.lnum + len(contents)) .. 'fold | :' .. pos.lnum .. 'foldopen')

  return {
    id: message_id,
    lnum: pos.lnum,
    type: type,
  }
enddef

export def AppendUser(content: string, buf: number = 0): dict<any>
  return AppendMessage('user', 'User', content, buf)
enddef

export def AppendAssistant(content: string, buf: number = 0): dict<any>
  return AppendMessage('assistant', 'Assistant', content, buf)
enddef

export def AppendSystem(name: string, content: string, buf: number = 0): dict<any>
  return AppendMessage('system', name, content, buf)
enddef

export def AppendError(content: string, buf: number = 0): dict<any>
  return AppendMessage('error', 'Error', content, buf)
enddef

export def AppendLoading(): dict<any>
  if !has('timers')
    return AppendMessage('loading', 'Assistant', 'thinking...')
  else
    const msg = AppendMessage('loading', 'Assistant', indicators[0])
    const bnr = bufnr()
    timer_start(100, (id: number) => UpdateIndicator(bnr, msg.id, 1))
    return msg
  endif
enddef

export def GetPrompt(buf: number = 0): dict<any>
  const prop = prop_find({bufnr: buf, type: 'askgpt_user', lnum: line('$')}, 'b')
  if len(prop) == 0
    return null_dict
  endif

  return {
    id: prop.id,
    lnum: prop.lnum,
    type: 'user',
  }
enddef

export def GetLastOfType(type: string, buf: number = 0): dict<any>
  const prompt_lnum = GetPrompt(buf).lnum
  const prop = prop_find({bufnr: buf, type: 'askgpt_' .. type, lnum: prompt_lnum, skipstart: true}, 'b')
  if len(prop) == 0
    return null_dict
  endif

  return {
    id: prop.id,
    lnum: prop.lnum,
    type: type,
  }
enddef

def GetNeighbor(orient: string, id: number, buf: number = 0): dict<any>
  const base = prop_find({bufnr: buf, id: id, lnum: line('$')}, 'b').lnum
  const prop = prop_find({bufnr: buf, type: 'askgpt_message', lnum: base, skipstart: true}, orient)
  if len(prop) == 0
    return null_dict
  endif

  return {
    id: prop.id,
    lnum: prop.lnum,
    type: GetType(prop.lnum),
  }
enddef

export def GetNearest(buf: number = 0): dict<any>
  const prop = prop_find({bufnr: buf, type: 'askgpt_message'}, 'b')
  return {
    id: prop.id,
    lnum: prop.lnum,
    type: GetType(prop.lnum),
  }
enddef

export def GetPrev(id: number, buf: number = 0): dict<any>
  return GetNeighbor('b', id, buf)
enddef

export def GetNext(id: number, buf: number = 0): dict<any>
  return GetNeighbor('f', id, buf)
enddef

export def Delete(id: number, buf: number = 0): bool
  const start = prop_find({bufnr: buf, id: id, type: 'askgpt_message', both: true, lnum: line('$')}, 'b')
  if len(start) == 0
    return false
  endif

  final end = prop_find({bufnr: buf, type: 'askgpt_message', lnum: start.lnum, skipstart: true}, 'f')
  if len(end) == 0
    end['lnum'] = line('$')
    defer AppendPrompt()
  endif

  deletebufline(buf ?? bufnr(), start.lnum, end.lnum - 1)

  return true
enddef

export def DeleteLoadings(buf: number = 0): number
  var count = 0
  while true
    const msg = GetLastOfType('loading', buf)
    if msg == null_dict
      return count
    endif

    Delete(msg.id, buf)
    ++count
  endwhile
  return count
enddef

export def Discard(id: number, buf: number = 0)
  prop_remove({
    bufnr: buf,
    id: id,
    types: ['askgpt_user', 'askgpt_assistant', 'askgpt_system', 'askgpt_discard'],
    both: true,
    all: true,
  })

  const first_line = prop_find({bufnr: buf, id: id, type: 'askgpt_message', both: true, lnum: line('$')}, 'b').lnum
  const last_line = prop_find({bufnr: buf, type: 'askgpt_message', lnum: first_line, skipstart: true}, 'f').lnum - 1
  prop_add(first_line, 1, {
    bufnr: buf,
    id: id,
    end_lnum: last_line,
    type: 'askgpt_discard',
  })
enddef

export def GetHistory(max: number): list<dict<string>>
  var lnum = GetPrompt().lnum

  final msgs: list<dict<string>> = []

  while len(msgs) < max
    const prop = prop_find({type: 'askgpt_message', lnum: lnum, skipstart: true}, 'b')
    if len(prop) == 0
      break
    endif

    const type = GetType(prop.lnum)
    if index(['user', 'assistant', 'system'], type) < 0
      lnum = prop.lnum
      continue
    endif

    insert(msgs, {
      role: type,
      content: getline(prop.lnum + 1, lnum - 1)->join("\n")->trim("\n"),
    })

    lnum = prop.lnum
  endwhile

  return msgs
enddef

def GetType(lnum: number): string
  const types = prop_list(lnum, {types: ['askgpt_user', 'askgpt_assistant', 'askgpt_system', 'askgpt_loading', 'askgpt_discard', 'askgpt_error']})
  if len(types) == 0
    return ''
  endif

  return substitute(types[0].type, 'askgpt_', '', '')
enddef

def FoldText(): string
  const line = getline(v:foldstart)
  if line =~ '__[A-Z][a-z]\+__'
    return substitute(line, '__', '', 'g') .. ' '
  endif
  return '+' .. v:folddashes .. '  ' .. (v:foldend - v:foldstart + 1) .. ' lines: ' .. line
enddef

def UpdateIndicator(buf: number, id: number, offset: number)
  const prop = prop_find({bufnr: buf, id: id, type: 'askgpt_loading', both: true, lnum: 1})
  if !prop || len(prop) == 0
    return
  endif

  setbufline(buf, prop.lnum + 1, indicators[offset])

  timer_start(100, (_: number) => UpdateIndicator(buf, id, (offset + 1) % strchars(indicators)))
enddef
