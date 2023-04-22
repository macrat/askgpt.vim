vim9script

def Request(id: number, endpoint: string, payload: dict<any>, OnMessage: func(number, number, string), OnExit: func(number, number, list<string>, number))
  Cancel()

  const cmd = GetCurlCommand(endpoint)
  #const cmd = ['sh', '-c', "sleep 1; echo '" .. '{"choices":[{"message":{"role":"assistant","content":"hello world ' .. id .. '"}}]}' .. "'"]
  #const cmd = ['sh', '-c', 'sleep 1; cat -; exit 1']

  final responses: list<string> = []

  const buf = bufnr()
  b:askgpt_job = job_start(cmd, {
    callback: (ch: channel, resp: string) => {
      for r in resp->split('\(^\|\n\)data: ')
        if r =~ '^\[DONE\]\n*$'
          continue
        endif
        responses->add(r)
        OnMessage(buf, id, r)
      endfor
    },
    exit_cb: (job: job, status: number) => {
      OnExit(buf, id, responses, status)
    },
    in_mode: 'json',
    out_mode: 'raw',
    err_mode: 'raw',
  })

  const channel = job_getchannel(b:askgpt_job)
  ch_sendraw(channel, json_encode(payload))
  ch_close_in(channel)
enddef

export def RequestChat(id: number, model: string, temperature: float, top_p: float, messages: list<dict<string>>, OnUpdate: func(number, number, string), OnFinish: func(number, number, string), OnError: func(number, number, string, number))
  var response = ''

  Request(id, '/v1/chat/completions', {
    model:       model,
    messages:    messages,
    temperature: temperature,
    top_p:       top_p,
    stream:      true,
  }, (buf, id_, resp) => {
    try
      const r: dict<string> = json_decode(resp).choices[0].delta
      if has_key(r, 'content')
        response ..= r.content
        OnUpdate(buf, id_, response)
      endif
    catch
      OnError(buf, id_, resp, -1)
    endtry
  }, (buf, id_, rs, status) => {
    if status != 0 && response == ''
      OnError(buf, id_, rs->join("\n"), status)
    else
      OnFinish(buf, id_, response)
    endif
  })
enddef

export def Cancel()
  if exists('b:askgpt_job')
    job_stop(b:askgpt_job)
  endif
enddef

export def IsRunning(): bool
  return exists('b:askgpt_job') && job_status(b:askgpt_job) == 'run'
enddef

def GetCurlCommand(endpoint: string): list<string>
  return g:askgpt_curl_command + [
    'https://api.openai.com' .. endpoint,
    '--silent',
    '--no-buffer',
    '-H',
    'Content-Type: application/json',
    '-H',
    'Authorization: Bearer ' .. g:askgpt_api_key,
    '-d',
    '@-',
  ]
enddef
