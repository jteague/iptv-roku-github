sub init()
    m.top.functionName = "runTimer"
    m.port = CreateObject("roMessagePort")
end sub

sub onIntervalChange()
    ' Signal port to wake so timer loop picks up new interval.
    m.port.PostMessage("reset")
end sub

sub runTimer()
    while true
        intervalMs = m.top.intervalMin * 60 * 1000
        msg = wait(intervalMs, m.port)
        if msg = invalid
            ' Timer fired — toggle tick to signal MainScene.
            m.top.tick = not m.top.tick
        end if
        ' On "reset" message, loop restarts with updated intervalMin.
    end while
end sub
