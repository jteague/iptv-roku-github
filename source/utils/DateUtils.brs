' Parse XMLTV timestamp "YYYYMMDDHHmmss +HHMM" to Unix epoch seconds (integer).
function parseXmltvTimestamp(ts as string) as integer
    ts = ts.trim()
    parts = ts.split(" ")
    dt = parts[0]

    year   = dt.left(4).toInt()
    month  = dt.mid(4, 2).toInt()
    day    = dt.mid(6, 2).toInt()
    hour   = dt.mid(8, 2).toInt()
    minute = dt.mid(10, 2).toInt()
    second = dt.mid(12, 2).toInt()

    tzOffsetSec = 0
    if parts.count() >= 2
        tz = parts[1]
        sign = 1
        if tz.left(1) = "-" then sign = -1
        tzH = tz.mid(1, 2).toInt()
        tzM = tz.mid(3, 2).toInt()
        tzOffsetSec = sign * (tzH * 3600 + tzM * 60)
    end if

    ' Days from 1970-01-01 to Jan 1 of given year (pure integer arithmetic)
    ey = year - 1
    leapsBefore = Int(ey / 4) - Int(ey / 100) + Int(ey / 400) - 477
    epochDays = (year - 1970) * 365 + leapsBefore

    ' Days from Jan 1 to start of given month (non-leap)
    if month = 1
        monthOffset = 0
    else if month = 2
        monthOffset = 31
    else if month = 3
        monthOffset = 59
    else if month = 4
        monthOffset = 90
    else if month = 5
        monthOffset = 120
    else if month = 6
        monthOffset = 151
    else if month = 7
        monthOffset = 181
    else if month = 8
        monthOffset = 212
    else if month = 9
        monthOffset = 243
    else if month = 10
        monthOffset = 273
    else if month = 11
        monthOffset = 304
    else
        monthOffset = 334
    end if
    isLeap = (year mod 4 = 0 and year mod 100 <> 0) or year mod 400 = 0
    if isLeap and month > 2 then monthOffset = monthOffset + 1
    epochDays = epochDays + monthOffset + day - 1

    return epochDays * 86400 + hour * 3600 + minute * 60 + second - tzOffsetSec
end function

function nowEpoch() as integer
    dt = CreateObject("roDateTime")
    return dt.AsSeconds()
end function

' Start of the half hour containing nowEpoch(): the guide window opens here so
' 9:45 shows 9:30 onwards and 10:04 shows 10:00 onwards. Every real time zone
' offset is a whole number of half hours, so flooring the UTC epoch is enough.
function currentHalfHour() as integer
    return Int(nowEpoch() / 1800) * 1800
end function

' Format epoch seconds to a local "Thu Sep 25" display string.
function epochToDateStr(epochSec as integer) as string
    dt = CreateObject("roDateTime")
    dt.FromSeconds(epochSec)
    dt.ToLocalTime()
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return Left(dt.GetWeekday(), 3) + " " + months[dt.GetMonth() - 1] + " " + dt.GetDayOfMonth().toStr()
end function

' Format epoch seconds to "H:MM AM/PM" display string.
function epochToTimeStr(epochSec as integer) as string
    dt = CreateObject("roDateTime")
    dt.FromSeconds(epochSec)
    dt.ToLocalTime()
    h = dt.GetHours()
    mi = dt.GetMinutes()
    ampm = "AM"
    if h >= 12
        ampm = "PM"
        if h > 12 then h = h - 12
    end if
    if h = 0 then h = 12
    minStr = mi.toStr()
    if mi < 10 then minStr = "0" + minStr
    return h.toStr() + ":" + minStr + " " + ampm
end function

' ISO 8601 "YYYY-MM-DDTHH:MM:SS[.fff](Z|+HH:MM)" (Dispatcharr's API) to epoch seconds.
function parseIsoTimestamp(iso as string) as integer
    if Len(iso) < 19 then return 0
    digits = Left(iso, 4) + Mid(iso, 6, 2) + Mid(iso, 9, 2) + Mid(iso, 12, 2) + Mid(iso, 15, 2) + Mid(iso, 18, 2)
    rest = Mid(iso, 20)
    while Left(rest, 1) = "." or (Len(rest) > 0 and Asc(rest) >= 48 and Asc(rest) <= 57)
        rest = Mid(rest, 2)
    end while
    tz = "+0000"
    if Left(rest, 1) = "+" or Left(rest, 1) = "-" then tz = Left(rest, 1) + Mid(rest, 2, 2) + Mid(rest, 5, 2)
    return parseXmltvTimestamp(digits + " " + tz)
end function
