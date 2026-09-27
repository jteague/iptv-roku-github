sub init()
    m.top.functionName = "execute"
end sub

' Scheduled (and in-progress) Dispatcharr recordings, keyed by the channel's
' uuid, which is the last path part of its proxy stream URL in the M3U.
sub execute()
    recs = {}
    ok = true
    cutoff = nowEpoch() - 3600
    for each src in m.top.sources
        base = urlOrigin(src.m3uUrl)
        list = apiGetList(base + "/api/channels/recordings/", src.apiKey)
        if list = invalid
            ok = false
        else
            upcoming = []
            for each r in list
                span = recordingSpan(r)
                if span <> invalid and span.stop > cutoff
                    span.channel = r.channel
                    upcoming.push(span)
                end if
            end for
            ' The channel list is large; only fetch it when there is something to map.
            if upcoming.count() > 0
                channels = apiGetList(base + "/api/channels/channels/", src.apiKey)
                if channels = invalid
                    ok = false
                else
                    uuids = {}
                    for each ch in channels
                        if ch.id <> invalid and ch.uuid <> invalid then uuids[ch.id.toStr()] = ch.uuid
                    end for
                    for each span in upcoming
                        uuid = uuids[span.channel.toStr()]
                        if uuid <> invalid
                            key = sourcePrefix(src) + uuid
                            if not recs.doesExist(key) then recs[key] = []
                            recs[key].push({ start: span.start, stop: span.stop })
                        end if
                    end for
                end if
            end if
        end if
    end for
    print "[RecordingsTask] ok=" + ok.toStr() + " channels with recordings=" + recs.count().toStr()
    m.top.result = { ok: ok, recs: recs }
end sub

' The programme's own times when Dispatcharr kept them (the recording itself is
' padded a minute before and a few after), else the recording's.
function recordingSpan(r as object) as dynamic
    if r.channel = invalid then return invalid
    s = r.start_time
    e = r.end_time
    cp = r.custom_properties
    if type(cp) = "roAssociativeArray" and type(cp.program) = "roAssociativeArray"
        if cp.program.start_time <> invalid and cp.program.end_time <> invalid
            s = cp.program.start_time
            e = cp.program.end_time
        end if
    end if
    if GetInterface(s, "ifString") = invalid or GetInterface(e, "ifString") = invalid then return invalid
    return { start: parseIsoTimestamp(s), stop: parseIsoTimestamp(e) }
end function
