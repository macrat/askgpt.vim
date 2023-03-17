vim9script

export def Request(id: number, endpoint: string, payload: dict<any>, Callback: func(number, number, string, number))
  Cancel()

  const cmd = GetCurlCommand(endpoint)
  #const cmd = ['sh', '-c', "sleep 1; echo '" .. '{"choices":[{"message":{"role":"assistant","content":"hello world ' .. id .. '"}}]}' .. "'"]
  #const cmd = ['sh', '-c', 'sleep 1; cat -; exit 1']

  var response = ''

  const buf = bufnr()
  b:askgpt_job = job_start(cmd, {
    callback: (ch: channel, resp: string) => {
      response = resp
    },
    exit_cb: (job: job, status: number) => {
      Callback(buf, id, response, status)
    },
    in_mode: 'json',
    out_mode: 'raw',
    err_mode: 'raw',
  })

  const channel = job_getchannel(b:askgpt_job)
  ch_sendraw(channel, json_encode(payload))
  ch_close_in(channel)
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
    '-H',
    'Content-Type: application/json',
    '-H',
    'Authorization: Bearer ' .. g:askgpt_api_key,
    '-d',
    '@-',
  ]
enddef
