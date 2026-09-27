sub init()
    m.clock = m.top.findNode("clock")
    m.secs  = m.top.findNode("secs")
    m.anim  = m.top.findNode("anim")

    m.LIT   = &h96BBBBFF   ' Ash Grey: time still left
    m.SPENT = &h414535FF   ' Charcoal: time used

    ' Ticks are radial Rectangles around the centre, created once. SceneGraph
    ' rotation is counterclockwise, so a clockwise angle a is rotation -a.
    m.N = 40
    D = 64
    tickW = 4
    tickH = 12
    r = D / 2 - tickH / 2
    m.ticks = []
    for i = 0 to m.N - 1
        a = 2 * 3.14159265 * i / m.N
        t = m.top.createChild("Rectangle")
        t.width  = tickW
        t.height = tickH
        t.color  = m.LIT
        t.scaleRotateCenter = [tickW / 2, tickH / 2]
        t.rotation = -a
        t.translation = [D / 2 + r * Sin(a) - tickW / 2, D / 2 - r * Cos(a) - tickH / 2]
        m.ticks.push(t)
    end for
    m.spent = 0
    m.clock.observeField("opacity", "onClockTick")
end sub

sub onControl()
    if m.top.control = "start"
        m.anim.control = "stop"
        for each t in m.ticks
            t.color = m.LIT
        end for
        m.spent = 0
        m.clock.opacity = 1.0
        m.secs.text = Int(m.top.duration + 0.999).toStr()
        m.anim.duration = m.top.duration
        m.anim.control = "start"
    else if m.top.control = "stop"
        m.anim.control = "stop"
    end if
end sub

' Fires every frame while the animation runs; only touches ticks and the
' label when they actually change.
sub onClockTick()
    left = m.clock.opacity
    spent = Int((1.0 - left) * m.N)
    if spent > m.N then spent = m.N
    while m.spent < spent
        m.ticks[m.spent].color = m.SPENT
        m.spent = m.spent + 1
    end while
    s = Int(left * m.top.duration + 0.999).toStr()
    if m.secs.text <> s then m.secs.text = s
end sub
