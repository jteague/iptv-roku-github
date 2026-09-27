sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    m.top.error = ""
    m.top.channels = []
    m.top.programs = {}
    m.top.failed = {}

    sources  = m.top.sources
    fetchEpg = not m.top.m3uOnly
    channels = []
    programs = {}
    failed   = {}
    errors   = []

    ' Issue every request at once; total wait is bounded by the slowest one.
    requests = {}
    for each src in sources
        requests["m3u_" + src.id] = src.m3uUrl
        if fetchEpg and src.epgUrl <> "" then requests["epg_" + src.id] = src.epgUrl
    end for
    reportProgress(0, "Downloading channels and guide…")
    responses = httpGetAll(requests)

    ' Parsing time follows download size, so each source gets a share of the
    ' bar proportional to its bytes.
    sizes = {}
    totalSize = 0
    for each key in responses
        if responses[key] <> invalid then size = Len(responses[key].body) else size = 0
        sizes[key] = size
        totalSize = totalSize + size
    end for
    if totalSize = 0 then totalSize = 1
    base = DOWNLOAD_SHARE()

    ' Channels are appended in source order, which is the guide order.
    for each src in sources
        name   = sourceDisplayName(src)
        prefix = sourcePrefix(src)
        f = { m3u: false, epg: false }
        m3uSpan = (1 - DOWNLOAD_SHARE()) * sizes["m3u_" + src.id] / totalSize
        epgSpan = 0
        if sizes.doesExist("epg_" + src.id) then epgSpan = (1 - DOWNLOAD_SHARE()) * sizes["epg_" + src.id] / totalSize
        reportProgress(base, "Reading channels: " + name)
        r = parseM3UResponse(responses["m3u_" + src.id])
        if r.error <> ""
            print "[FetchTask] " + src.id + " m3u failed: " + r.error
            errors.push(name + ": " + r.error)
            f.m3u = true
            f.epg = (src.epgUrl <> "")
        else
            print "[FetchTask] " + src.id + " m3u parsed, channels=" + r.channels.count().toStr()
            list = r.channels
            if src.tsToHls then list = rewriteTsToHls(list)
            for each ch in list
                ch.id = prefix + ch.id
                channels.push(ch)
            end for
            if src.epgUrl <> ""
                epgResult = invalid
                if fetchEpg
                    report = { node: m.top, base: base + m3uSpan, span: epgSpan, name: name }
                    epgResult = parseXmltvResponse(responses["epg_" + src.id], report)
                end if
                if epgResult = invalid
                    if fetchEpg then print "[FetchTask] " + src.id + " epg failed (non-fatal)"
                    f.epg = true
                else
                    print "[FetchTask] " + src.id + " epg parsed ok, program keys=" + epgResult.programs.count().toStr()
                    for each key in epgResult.programs
                        programs[prefix + key] = epgResult.programs[key]
                    end for
                end if
            end if
        end if
        failed[src.id] = f
        base = base + m3uSpan + epgSpan
    end for
    reportProgress(1, "Building guide…")

    m.top.failed = failed
    if errors.count() > 0 then m.top.error = errors.Join(chr(10))

    if channels.count() = 0 then return

    m.top.channels = channels
    m.top.programs = programs
    print "[FetchTask] done channels=" + channels.count().toStr()
end sub

function rewriteTsToHls(channels as object) as object
    for each ch in channels
        url = ch.streamUrl
        if Right(LCase(url), 3) = ".ts"
            ch.streamUrl = Left(url, Len(url) - 3) + ".m3u8?mode=segmenter"
        end if
    end for
    return channels
end function

function parseM3UResponse(result as object) as object
    if result = invalid or result.code = 0
        return {channels: [], error: "Connection timed out"}
    end if
    if result.code < 200 or result.code >= 300
        return {channels: [], error: "HTTP " + result.code.toStr() + " - " + httpErrorLabel(result.code)}
    end if
    if result.body = ""
        return {channels: [], error: "Empty response from server"}
    end if
    channels = parseM3U(result.body)
    if channels = invalid or channels.count() = 0
        return {channels: [], error: "No channels found in playlist"}
    end if
    return {channels: channels, error: ""}
end function

function parseXmltvResponse(result as object, report as object) as object
    if result = invalid or result.body = "" then return invalid
    return parseXmltv(result.body, report)
end function

function DOWNLOAD_SHARE() as float
    return 0.4
end function

sub reportProgress(fraction as float, msg as string)
    m.top.progress = { fraction: fraction, msg: msg }
end sub

' Fetch every URL in parallel. requests is { key: url }; the result is
' { key: { body, code } } with code 0 for a timeout or a request that never
' started. A non-2xx response has an empty body.
function httpGetAll(requests as object) as object
    TIMEOUT_MS = 15000
    port = CreateObject("roMessagePort")
    pending = {}   ' transfer identity → { key, http }; also keeps the transfers alive
    results = {}

    for each key in requests
        http = createHttpClient(requests[key])
        http.SetMessagePort(port)
        if http.AsyncGetToString()
            pending[http.GetIdentity().toStr()] = { key: key, http: http }
        else
            print "[FetchTask] HTTP could not start url=" + requests[key]
            results[key] = { body: "", code: 0 }
        end if
    end for

    timer = CreateObject("roTimespan")
    while pending.count() > 0
        remainingMs = TIMEOUT_MS - timer.TotalMilliseconds()
        msg = invalid
        if remainingMs > 0 then msg = wait(remainingMs, port)
        if msg = invalid
            for each id in pending
                print "[FetchTask] HTTP timeout url=" + requests[pending[id].key]
                pending[id].http.AsyncCancel()
                results[pending[id].key] = { body: "", code: 0 }
            end for
            exit while
        end if
        if type(msg) = "roUrlEvent"
            id = msg.GetSourceIdentity().toStr()
            if pending.doesExist(id)
                key  = pending[id].key
                code = msg.GetResponseCode()
                print "[FetchTask] HTTP " + code.toStr() + " url=" + requests[key]
                body = ""
                if code >= 200 and code < 300 then body = msg.GetString()
                results[key] = { body: body, code: code }
                pending.delete(id)
                done = requests.count() - pending.count()
                reportProgress(DOWNLOAD_SHARE() * done / requests.count(), "Downloading channels and guide… " + done.toStr() + " of " + requests.count().toStr())
            end if
        end if
    end while

    return results
end function

function httpErrorLabel(code as integer) as string
    if code = 400 then return "Bad request — check your M3U URL"
    if code = 401 then return "Unauthorized — check your credentials"
    if code = 403 then return "Forbidden — subscription may be expired or IP blocked"
    if code = 404 then return "Not found — URL may have changed"
    if code = 408 then return "Request timeout"
    if code = 429 then return "Too many requests — try again later"
    if code = 500 then return "Internal server error"
    if code = 502 then return "Bad gateway"
    if code = 503 then return "Service unavailable"
    if code = 504 then return "Gateway timeout"
    if code >= 400 and code < 500 then return "Client error — check URL and credentials"
    if code >= 500 then return "Server error — try again later"
    return "Unexpected error"
end function

function createHttpClient(url as string) as object
    http = CreateObject("roUrlTransfer")
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.EnableEncodings(true)
    http.AddHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
    return http
end function
