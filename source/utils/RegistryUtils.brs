' ── Hidden channels ──────────────────────────────────────────────────────────
' Two registry sections keyed by channel id: "iptv_hidden" (hidden from the guide
' menu, permanent until unhidden in Settings) and "iptv_skip" (unsupported codec,
' expires after 14 days). Values are JSON { t, name, num } so Settings can list
' channels that are no longer loaded; older iptv_skip values are a bare
' timestamp and get their name the next time the channel is filtered.

function codecSkipTtl() as integer
    return 14 * 24 * 3600
end function

function hiddenValue(ch as object, t as integer) as string
    return FormatJson({ t: t, name: ch.name, num: ch.number })
end function

function hiddenEntry(value as string) as object
    e = { t: value.toInt(), name: "", num: "" }
    if Left(value, 1) <> "{" then return e
    parsed = ParseJson(value)
    if type(parsed) <> "roAssociativeArray" then return e
    if GetInterface(parsed.t, "ifInt") <> invalid then e.t = parsed.t
    if GetInterface(parsed.name, "ifString") <> invalid then e.name = parsed.name
    if GetInterface(parsed.num, "ifString") <> invalid then e.num = parsed.num
    return e
end function

' Unsupported codec (PlayerScene error -5): hidden for codecSkipTtl().
sub blacklistChannel(ch as object)
    section = CreateObject("roRegistrySection", "iptv_skip")
    section.Write(ch.id, hiddenValue(ch, CreateObject("roDateTime").AsSeconds()))
    section.Flush()
end sub

' Hidden by the user from the guide's long-press menu.
sub hideChannel(ch as object)
    section = CreateObject("roRegistrySection", "iptv_hidden")
    section.Write(ch.id, hiddenValue(ch, CreateObject("roDateTime").AsSeconds()))
    section.Flush()
end sub

function filterHiddenChannels(channels as object) as object
    hidden = CreateObject("roRegistrySection", "iptv_hidden")
    skip   = CreateObject("roRegistrySection", "iptv_skip")
    nowSec = CreateObject("roDateTime").AsSeconds()
    ttl = codecSkipTtl()
    result = []
    dirty = false
    for each ch in channels
        if hidden.Exists(ch.id)
            ' hidden by the user
        else if skip.Exists(ch.id)
            e = hiddenEntry(skip.Read(ch.id))
            if (nowSec - e.t) >= ttl
                skip.Delete(ch.id)
                dirty = true
                result.push(ch)
            else if e.name = ""
                skip.Write(ch.id, hiddenValue(ch, e.t))
                dirty = true
            end if
        else
            result.push(ch)
        end if
    end for
    if dirty then skip.Flush()
    if result.count() < channels.count() then print "[Hidden] hiding " + (channels.count() - result.count()).toStr() + " channels"
    return result
end function

' Every hidden channel for Settings: [{ id, name, num, kind: "user" | "codec",
' daysLeft }], the user's first, each group by name. Expired codec entries are
' left out (filterHiddenChannels deletes them).
function hiddenChannelList() as object
    hidden = CreateObject("roRegistrySection", "iptv_hidden")
    skip   = CreateObject("roRegistrySection", "iptv_skip")
    nowSec = CreateObject("roDateTime").AsSeconds()
    ttl = codecSkipTtl()
    users = []
    for each id in hidden.GetKeyList()
        e = hiddenEntry(hidden.Read(id))
        e.id = id
        e.kind = "user"
        e.daysLeft = 0
        users.push(e)
    end for
    codec = []
    for each id in skip.GetKeyList()
        e = hiddenEntry(skip.Read(id))
        remaining = ttl - (nowSec - e.t)
        if remaining > 0 and not hidden.Exists(id)
            e.id = id
            e.kind = "codec"
            e.daysLeft = Int((remaining + 86399) / 86400)
            codec.push(e)
        end if
    end for
    users.SortBy("name", "i")
    codec.SortBy("name", "i")
    users.append(codec)
    return users
end function

sub unhideChannel(id as string)
    for each name in ["iptv_hidden", "iptv_skip"]
        section = CreateObject("roRegistrySection", name)
        if section.Exists(id)
            section.Delete(id)
            section.Flush()
        end if
    end for
end sub

' Codec-hidden → hidden for good; keeps the stored name and number.
sub hideChannelPermanently(e as object)
    hideChannel({ id: e.id, name: e.name, number: e.num })
    skip = CreateObject("roRegistrySection", "iptv_skip")
    skip.Delete(e.id)
    skip.Flush()
end sub

' ── Favorites ────────────────────────────────────────────────────────────────
' "iptv_fav": channels starred from the guide's long-press menu, keyed by channel
' id, value hiddenValue(). The guide's "Favorites" filter shows only these.

' "|p4_12|p4_40|": the favorite channel ids, for Instr lookups.
function favoriteIds() as string
    result = "|"
    for each id in CreateObject("roRegistrySection", "iptv_fav").GetKeyList()
        result = result + id + "|"
    end for
    return result
end function

sub setFavorite(ch as object, isFav as boolean)
    section = CreateObject("roRegistrySection", "iptv_fav")
    if isFav
        section.Write(ch.id, hiddenValue(ch, CreateObject("roDateTime").AsSeconds()))
    else
        section.Delete(ch.id)
    end if
    section.Flush()
end sub

' ── Reminders ────────────────────────────────────────────────────────────────
' "iptv_remind": future shows marked from the long-press menu, keyed
' "<channel id>@<start>" (reminderKey), value JSON { id, start, stop, title, name, num }.
' MainScene pops a dialog when one starts; the entry is deleted when it fires.

function reminderKey(chId as string, start as integer) as string
    return chId + "@" + start.toStr()
end function

' Every stored reminder, keyed like the registry. Ones whose show has ended
' (the app was off when it started) are deleted.
function readReminders() as object
    section = CreateObject("roRegistrySection", "iptv_remind")
    nowSec = CreateObject("roDateTime").AsSeconds()
    result = {}
    dirty = false
    for each key in section.GetKeyList()
        r = ParseJson(section.Read(key))
        if type(r) <> "roAssociativeArray" or GetInterface(r.stop, "ifInt") = invalid or r.stop <= nowSec
            section.Delete(key)
            dirty = true
        else
            result[key] = r
        end if
    end for
    if dirty then section.Flush()
    return result
end function

sub setReminder(ch as object, prog as object)
    section = CreateObject("roRegistrySection", "iptv_remind")
    value = { id: ch.id, start: prog.start, stop: prog.stop, title: prog.title, name: ch.name, num: ch.number }
    section.Write(reminderKey(ch.id, prog.start), FormatJson(value))
    section.Flush()
end sub

sub deleteReminder(key as string)
    section = CreateObject("roRegistrySection", "iptv_remind")
    section.Delete(key)
    section.Flush()
end sub

sub clearHiddenChannels()
    for each name in ["iptv_hidden", "iptv_skip"]
        section = CreateObject("roRegistrySection", name)
        for each key in section.GetKeyList()
            section.Delete(key)
        end for
        section.Flush()
    end for
end sub

function readSettings() as object
    section = CreateObject("roRegistrySection", "iptv")
    settings = {
        sources: [],                 ' guide order; see normalizeSource for the entry shape
        nextSourceId: 1,             ' ids are never reused, so stale data can't attach to a new source
        refreshIntervalMin: 120,
        guideHours: 4,   ' hours of programming across the guide (2..4)
        guideRows: 13,   ' channel rows on screen (5..15); sets the guide's height
        onLaunch: "guide"   ' "guide" | "resume" (last channel plays in the PIP)
    }
    if section.Exists("sources")
        parsed = ParseJson(section.Read("sources"))
        if type(parsed) = "roArray"
            for each src in parsed
                src = normalizeSource(src)
                if src <> invalid then settings.sources.push(src)
            end for
        end if
    end if
    if section.Exists("nextSourceId") then settings.nextSourceId = section.Read("nextSourceId").toInt()
    for each src in settings.sources
        n = Mid(src.id, 2).toInt()
        if n >= settings.nextSourceId then settings.nextSourceId = n + 1
    end for
    if section.Exists("refreshIntervalMin")
        val = section.Read("refreshIntervalMin").toInt()
        if val < 15 then val = 15
        settings.refreshIntervalMin = val
    end if
    if section.Exists("guideHours")
        val = section.Read("guideHours").toInt()
        if val < 2 then val = 2
        if val > 4 then val = 4
        settings.guideHours = val
    end if
    if section.Exists("guideRows")
        val = section.Read("guideRows").toInt()
        if val < 5 then val = 5
        if val > 15 then val = 15
        settings.guideRows = val
    end if
    if section.Read("onLaunch") = "resume" then settings.onLaunch = "resume"
    return settings
end function

' settings: same shape as readSettings() returns.
sub writeSettings(settings as object)
    intervalMin = settings.refreshIntervalMin
    if intervalMin < 15 then intervalMin = 15
    section = CreateObject("roRegistrySection", "iptv")
    section.Write("sources", FormatJson(settings.sources))
    section.Write("nextSourceId", settings.nextSourceId.toStr())
    section.Write("refreshIntervalMin", intervalMin.toStr())
    section.Write("guideHours", settings.guideHours.toStr())
    section.Write("guideRows", settings.guideRows.toStr())
    section.Write("onLaunch", settings.onLaunch)
    section.Flush()
end sub

' Last channel opened in the player, for the "resume last channel" launch option.
' Kept out of readSettings/writeSettings: it changes on every tune, not on Save.
sub saveLastChannelId(id as string)
    section = CreateObject("roRegistrySection", "iptv")
    section.Write("lastChannelId", id)
    section.Flush()
end sub

function lastChannelId() as string
    return CreateObject("roRegistrySection", "iptv").Read("lastChannelId")
end function

' ── IPTV sources ─────────────────────────────────────────────────────────────
' A source: { id, name, m3uUrl, epgUrl, apiKey, enabled, tsToHls }. Its channel ids and
' program keys are prefixed "<id>_" (sourcePrefix), so the id must stay fixed
' when the source is renamed or moved. tsToHls rewrites .ts stream URLs to
' .m3u8?mode=segmenter (ErsatzTV). apiKey is a Dispatcharr API key: when set,
' the source's scheduled recordings are marked in the guide (RecordingsTask).

function normalizeSource(src as dynamic) as dynamic
    if type(src) <> "roAssociativeArray" then return invalid
    if GetInterface(src.id, "ifString") = invalid or src.id = "" then return invalid
    result = { id: src.id, name: "", m3uUrl: "", epgUrl: "", apiKey: "", enabled: true, tsToHls: false }
    ' FormatJson writes the keys lowercased ("m3uurl") and ParseJson's arrays match
    ' keys case-sensitively, so src["m3uUrl"] alone misses; fall back to lowercase.
    for each key in ["name", "m3uUrl", "epgUrl", "apiKey"]
        v = src[key]
        if v = invalid then v = src[LCase(key)]
        if GetInterface(v, "ifString") <> invalid then result[key] = v
    end for
    for each key in ["enabled", "tsToHls"]
        v = src[key]
        if v = invalid then v = src[LCase(key)]
        if GetInterface(v, "ifBoolean") <> invalid then result[key] = v
    end for
    return result
end function

function enabledSources(settings as object) as object
    result = []
    for each src in settings.sources
        if src.enabled and src.m3uUrl <> "" then result.push(src)
    end for
    return result
end function

function sourcePrefix(src as object) as string
    return src.id + "_"
end function

' Prefix ("<id>_") of a namespaced channel id or program key.
function idPrefixOf(id as string) as string
    i = Instr(1, id, "_")
    if i = 0 then return ""
    return Left(id, i)
end function

' Name to show for a source: its own name, else the M3U URL's host.
function sourceDisplayName(src as object) as string
    if src.name <> "" then return src.name
    host = src.m3uUrl
    i = Instr(1, host, "://")
    if i > 0 then host = Mid(host, i + 3)
    i = Instr(1, host, "/")
    if i > 0 then host = Left(host, i - 1)
    if host = "" then return "New source"
    return host
end function

' Guide geometry derived from settings. Row height is fixed; the row count sets
' the guide's height, and the guide is anchored to the bottom of the 1080 canvas.
' The PIP fills the space above it at 16:9, capped so the info panel keeps at
' least 700px; when capped the PIP sits against the guide rather than the top.
function guideGeometry(settings as object) as object
    rowHeight = 58
    headerH   = 40
    rows      = settings.guideRows
    guideH    = headerH + rows * rowHeight
    topH      = 1080 - guideH
    pipH = topH
    pipW = Int(pipH * 16 / 9)
    if pipW > 1920 - 700
        pipW = 1920 - 700
        pipH = Int(pipW * 9 / 16)
    end if
    return {
        rows:      rows,
        rowHeight: rowHeight,
        headerH:   headerH,
        guideH:    guideH,
        topH:      topH,
        pipW:      pipW,
        pipH:      pipH,
        pipX:      1920 - pipW,
        pipY:      topH - pipH,
        infoW:     1920 - pipW
    }
end function
