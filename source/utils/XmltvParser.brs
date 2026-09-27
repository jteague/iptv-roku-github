' Parse XMLTV XML string into:
'   channels: assocarray keyed by channel id → { id, name }
'   programs: assocarray keyed by channel id → array of
'     { title, desc, start, stop, subtitle, rating, episode, year, isNew, genres, cats, poster }
'   (subtitle/rating/episode/year/poster are "" and genres is [] when the feed lacks them)
'   cats is every <category>, lowercased, as "|series|comedy|" ("" when none); the
'   guide's programme filters (ProgramFilters.brs) match against it.
' Each channel's programme array is sorted by start. Programmes that ended more
' than 4 hours ago are dropped; everything later is kept so the guide can page
' forward in time.
' report (optional): { node, base, span, name } — node.progress is set to
' { fraction, msg } as parsing moves from base to base + span.
function parseXmltv(xmlStr as string, report = invalid as dynamic) as object
    result = { channels: {}, programs: {} }

    ' Building the DOM is one native call with no progress of its own; give it
    ' the first 30% of the span and the element loop the rest.
    reportXmltvProgress(report, 0)
    xml = CreateObject("roXMLElement")
    if not xml.Parse(xmlStr) then return result
    children = xml.GetChildElements()
    childCount = children.count()
    if childCount = 0 then childCount = 1
    index = 0

    totalChannels = 0
    totalProgrammes = 0
    dropped = 0
    cutoffSec = nowEpoch() - 4 * 3600

    for each child in children
        index = index + 1
        if index mod 1000 = 0 then reportXmltvProgress(report, 0.3 + 0.7 * index / childCount)
        tag = child.GetName()

        if tag = "channel"
            totalChannels = totalChannels + 1
            attrs = child.GetAttributes()
            id = attrs.Lookup("id")
            if id = invalid or id = "" then
                ' skip
            else
                name = ""
                nameEls = child.GetNamedElements("display-name")
                if nameEls.count() > 0 then name = nameEls[0].GetText()
                result.channels[id] = { id: id, name: name }
            end if

        else if tag = "programme"
            totalProgrammes = totalProgrammes + 1
            attrs = child.GetAttributes()
            startStr = attrs.Lookup("start")
            stopStr  = attrs.Lookup("stop")
            chanId   = attrs.Lookup("channel")

            if startStr = invalid or stopStr = invalid or chanId = invalid then
                ' skip malformed
            else if parseXmltvTimestamp(stopStr) <= cutoffSec then
                dropped = dropped + 1
            else
                startSec = parseXmltvTimestamp(startStr)
                stopSec  = parseXmltvTimestamp(stopStr)

                titleEl = child.GetNamedElements("title")
                title = ""
                if titleEl.count() > 0 then title = titleEl[0].GetText()

                descEl = child.GetNamedElements("desc")
                desc = ""
                if descEl.count() > 0 then desc = descEl[0].GetText()

                prog = { title: title, desc: desc, start: startSec, stop: stopSec }
                addProgrammeDetails(prog, child)

                if not result.programs.doesExist(chanId)
                    result.programs[chanId] = []
                end if
                result.programs[chanId].push(prog)
            end if
        end if
    end for

    for each chanId in result.programs
        result.programs[chanId].SortBy("start")
    end for

    print "[XMLTV] totalChannels=" + totalChannels.toStr() + " totalProgrammes=" + totalProgrammes.toStr() + " droppedPast=" + dropped.toStr()

    return result
end function

sub reportXmltvProgress(report as dynamic, done as float)
    if report = invalid then return
    report.node.progress = {
        fraction: report.base + report.span * done,
        msg: "Reading guide: " + report.name + "… " + Int(done * 100).toStr() + "%"
    }
end sub

' Optional per-programme details used by the info panel badges. Everything is
' optional in XMLTV, so each lookup tolerates a missing element.
sub addProgrammeDetails(prog as object, el as object)
    prog.subtitle = firstText(el, "sub-title")
    prog.year     = Left(firstText(el, "date"), 4)
    prog.isNew    = (el.GetNamedElements("new").count() > 0) or (el.GetNamedElements("premiere").count() > 0)

    ' Artwork: <icon src="..."/> first, then <image type="poster">url</image>.
    ' Some feeds wrap the image text in stray quotes, so strip them.
    prog.poster = ""
    iconEls = el.GetNamedElements("icon")
    if iconEls.count() > 0
        src = iconEls[0].GetAttributes().Lookup("src")
        if src <> invalid then prog.poster = src.trim()
    end if
    if prog.poster = ""
        for each img in el.GetNamedElements("image")
            imgType = img.GetAttributes().Lookup("type")
            if imgType <> invalid
                if imgType = "poster"
                    prog.poster = img.GetText().trim().replace(Chr(34), "")
                    exit for
                end if
            end if
        end for
    end if

    prog.rating = ""
    ratingEls = el.GetNamedElements("rating")
    if ratingEls.count() > 0 then prog.rating = firstText(ratingEls[0], "value")

    ' Prefer the human-readable form (S23E01); fall back to the first entry.
    prog.episode = ""
    for each ep in el.GetNamedElements("episode-num")
        system = ep.GetAttributes().Lookup("system")
        if system <> invalid
            if system = "onscreen"
                prog.episode = ep.GetText().trim()
                exit for
            end if
        end if
    end for

    ' "Series"/"Show" describe the type rather than the genre; skip them.
    prog.genres = []
    prog.cats   = ""
    for each cat in el.GetNamedElements("category")
        text = cat.GetText().trim()
        if text <> ""
            prog.cats = prog.cats + "|" + LCase(text)
            if text <> "Series" and text <> "Show" and prog.genres.count() < 3 then prog.genres.push(text)
        end if
    end for
    if prog.cats <> "" then prog.cats = prog.cats + "|"
end sub

function firstText(el as object, name as string) as string
    els = el.GetNamedElements(name)
    if els.count() = 0 then return ""
    return els[0].GetText().trim()
end function
