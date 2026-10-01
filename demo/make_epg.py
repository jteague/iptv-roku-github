#!/usr/bin/env python3
"""Writes a demo XMLTV guide for demo/demo.m3u to stdout: today (UTC) plus the
next three days. The streams have no public EPG, so the schedule is made up;
it only has to keep the guide full for certification reviewers. Run daily
(.github/workflows/demo-pages.yml) so it never runs out."""
from datetime import datetime, timedelta, timezone
from xml.sax.saxutils import escape

DAYS = 4
DESC = "Demo guide data for testing GuideBox. The live stream plays whatever is on air."

# channel id, display name, [(minutes, title, category)] repeated through the day
CHANNELS = [
    ("dw-english", "DW English", [(30, "DW News", "News"), (30, "Focus on Europe", "Documentary")]),
    ("dw-espanol", "DW Español", [(30, "DW Noticias", "News"), (30, "Enfoque Europa", "Documentary")]),
    ("unified-demo", "Unified Streaming Demo", [(60, "Live Demo Stream", "Technology")]),
]


def ts(t):
    return t.strftime("%Y%m%d%H%M%S +0000")


def main():
    start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=DAYS)
    out = ['<?xml version="1.0" encoding="UTF-8"?>', '<tv generator-info-name="guidebox-demo">']
    for cid, name, _ in CHANNELS:
        out.append(f'  <channel id="{cid}"><display-name>{escape(name)}</display-name></channel>')
    for cid, _, blocks in CHANNELS:
        t, i = start, 0
        while t < end:
            mins, title, cat = blocks[i % len(blocks)]
            stop = t + timedelta(minutes=mins)
            out.append(f'  <programme start="{ts(t)}" stop="{ts(stop)}" channel="{cid}">'
                       f'<title>{escape(title)}</title><desc>{escape(DESC)}</desc>'
                       f'<category>{cat}</category></programme>')
            t, i = stop, i + 1
    out.append("</tv>")
    print("\n".join(out))


if __name__ == "__main__":
    main()
