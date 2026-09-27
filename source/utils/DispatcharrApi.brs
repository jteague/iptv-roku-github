' Dispatcharr REST calls (RecordingsTask, DvrTask). Authenticated with the
' source's API key in X-API-Key. Blocking: only call from a Task thread.

' "http://host:port/output/m3u" -> "http://host:port"
function urlOrigin(url as string) as string
    i = Instr(1, url, "://")
    if i = 0 then return url
    j = Instr(i + 3, url, "/")
    if j = 0 then return url
    return Left(url, j - 1)
end function

' GET a JSON array; invalid on any failure. Accepts a paginated { results } too.
function apiGetList(url as string, apiKey as string) as dynamic
    data = apiGet(url, apiKey)
    if type(data) = "roAssociativeArray" and type(data.results) = "roArray" then data = data.results
    if type(data) <> "roArray" then return invalid
    return data
end function

' GET parsed JSON; invalid on any failure.
function apiGet(url as string, apiKey as string) as dynamic
    res = apiRequest("GET", url, apiKey, invalid)
    if res.code <> 200 then return invalid
    return ParseJson(res.body)
end function

' POST a JSON body. Returns { code, body } (code 0: timeout / could not start).
function apiPost(url as string, apiKey as string, body as object) as object
    return apiRequest("POST", url, apiKey, body)
end function

function apiRequest(method as string, url as string, apiKey as string, body as dynamic) as object
    http = CreateObject("roUrlTransfer")
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.EnableEncodings(true)
    http.RetainBodyOnError(true)
    http.AddHeader("X-API-Key", apiKey)
    http.AddHeader("Accept", "application/json")
    port = CreateObject("roMessagePort")
    http.SetMessagePort(port)
    if body = invalid
        started = http.AsyncGetToString()
    else
        http.SetRequest(method)
        http.AddHeader("Content-Type", "application/json")
        started = http.AsyncPostFromString(FormatJson(body))
    end if
    if not started then return { code: 0, body: "" }
    msg = wait(15000, port)
    if type(msg) <> "roUrlEvent"
        http.AsyncCancel()
        print "[Dispatcharr] timeout " + method + " " + url
        return { code: 0, body: "" }
    end if
    code = msg.GetResponseCode()
    if code < 200 or code >= 300 then print "[Dispatcharr] HTTP " + code.toStr() + " " + method + " " + url + " " + Left(msg.GetString(), 200)
    return { code: code, body: msg.GetString() }
end function

' Epoch seconds -> "YYYY-MM-DDTHH:MM:SSZ"
function epochToIso(epochSec as integer) as string
    dt = CreateObject("roDateTime")
    dt.FromSeconds(epochSec)
    return dt.ToISOString()
end function
