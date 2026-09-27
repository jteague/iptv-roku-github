sub init()
    m.top.functionName = "execute"
end sub

' Schedule one recording, or add a series rule (Dispatcharr evaluates it at once
' and schedules every matching airing). Dispatcharr pads the times itself.
sub execute()
    req  = m.top.request
    prog = req.program
    ch = findChannel(req.base, req.apiKey, req.uuid)
    if ch = invalid
        finish(false, "Couldn't find this channel in Dispatcharr.")
        return
    end if

    if req.kind = "once"
        info = { title: prog.title, start_time: epochToIso(prog.start), end_time: epochToIso(prog.stop) }
        if prog.subtitle <> invalid then info.sub_title = prog.subtitle
        if prog.desc <> invalid then info.description = prog.desc
        body = { channel: ch.id, start_time: info.start_time, end_time: info.end_time, custom_properties: { program: info } }
        res = apiPost(req.base + "/api/channels/recordings/", req.apiKey, body)
        if res.code >= 200 and res.code < 300
            finish(true, "Recording " + prog.title + ".")
        else
            finish(false, "Dispatcharr refused the recording" + codeText(res.code))
        end if
        return
    end if

    ' Series rules match on the EPG's own tvg_id and source, not the channel's.
    epgId = ch.effective_epg_data_id
    if epgId = invalid then epgId = ch.epg_data_id
    if epgId = invalid
        finish(false, "This channel has no guide data in Dispatcharr.")
        return
    end if
    epg = apiGet(req.base + "/api/epg/epgdata/" + epgId.toStr() + "/", req.apiKey)
    if type(epg) <> "roAssociativeArray" or GetInterface(epg.tvg_id, "ifString") = invalid
        finish(false, "Couldn't read this channel's guide data from Dispatcharr.")
        return
    end if
    body = { tvg_id: epg.tvg_id, title: prog.title, title_mode: "exact", mode: req.kind, channel_id: ch.id }
    if epg.epg_source <> invalid then body.epg_source_id = epg.epg_source
    res = apiPost(req.base + "/api/channels/series-rules/", req.apiKey, body)
    if res.code >= 200 and res.code < 300
        if req.kind = "new"
            finish(true, "Recording new episodes of " + prog.title + ".")
        else
            finish(true, "Recording every episode of " + prog.title + ".")
        end if
    else
        finish(false, "Dispatcharr refused the series rule" + codeText(res.code))
    end if
end sub

function findChannel(base as string, apiKey as string, uuid as string) as dynamic
    channels = apiGetList(base + "/api/channels/channels/", apiKey)
    if channels = invalid then return invalid
    for each ch in channels
        if GetInterface(ch.uuid, "ifString") <> invalid and ch.uuid = uuid then return ch
    end for
    return invalid
end function

function codeText(code as integer) as string
    if code = 0 then return " (no response)."
    return " (HTTP " + code.toStr() + ")."
end function

sub finish(ok as boolean, msg as string)
    print "[DvrTask] ok=" + ok.toStr() + " " + msg
    m.top.result = { ok: ok, msg: msg }
end sub
