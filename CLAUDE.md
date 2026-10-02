# iptv-roku

Native BrightScript / SceneGraph Roku app: M3U playlist + XMLTV EPG → guide grid with PIP, fullscreen HLS player.
No JS frameworks, no abstraction layers. Keep it plain BrightScript.

## Repo policy

- **Public repo.** Never commit provider URLs, account keys, device IPs or dev passwords
  (`.vscode/launch.json` is gitignored for that reason).
- No test suite. Verify with the compiler and on a device.

## Build, check, deploy

```bash
# Static check (BrighterScript, no output package). Must be clean before calling work done.
node_modules/.bin/bsc --rootDir . --createPackage false --copyToStaging false \
  --files manifest "source/**/*.brs" "components/**/*.brs" "components/**/*.xml"

# Manual deploy: zip and upload via http://<roku-ip> (user rokudev, your dev password)
zip -r guidebox.zip manifest source components images

# Debug console (print output)
telnet <roku-ip> 8085
```

## Roku certification

Kept store-ready (Roku's certification criteria), so don't regress these.
- Roku's static analysis (Channel Store upload) must stay warning-free: no deprecated manifest keys (`subtitle`),
  memory monitoring in main.brs, `StandardKeyboardDialog` not `KeyboardDialog`.
- Deep links with no playlist added play the built-in sample (`SAMPLE_ID` "big-buck-bunny", MainScene): Big Buck Bunny,
  CC BY 3.0, built by `demo/make_sample.sh` and published with the demo playlist (`demo/sample.html` has the credit).
  Roku's automated deep-link and play-performance tests run on a clean install and depend on it.
- Manifest: `rsg_version=1.3` (required from 2026-10-01), `supports_input_launch=1`, `minimum_firmware_version=15.0` (Roku compares major and minor separately, so 15.1 refuses OS 16.0.x), focus icons 290x218 (hd) and
  540x405 (fhd), colours clamped to broadcast-safe 16..235. Bump `build_version` for every submitted build.
- `AppLaunchComplete` beacon (`launchComplete`, MainScene) fires once when the guide, Settings or the error screen is
  first up; an error dialog before it is wrapped in `AppDialogInitiate`/`AppDialogComplete`.
- Back must lead out of the app: the guide is the home screen, and Back there opens MainScene's exit dialog
  ("Watch <channel>" / Exit, or Exit / Cancel). It never jumps straight back to the player.
- Deep links: `contentId` is a channel id, with or without the `<source>_` prefix (`applyDeepLink`); the channel
  plays fullscreen over the guide. Test with `curl -d '' "http://<roku-ip>:8060/launch/dev?contentId=dw-english&mediaType=live"`.
- `demo/`: a playlist of legal public live streams + `make_epg.py` (made-up 4-day XMLTV).
  `.github/workflows/demo-pages.yml` republishes them to Pages daily; give those URLs to certification reviewers.

## Resolution: fhd only, always

- `manifest` declares `ui_resolutions=fhd` **only**. Every layout coordinate is in 1920x1080 space.
- Never add `hd` back. With `hd` declared the 1920x1080 layout is drawn into a 1280x720 canvas and
  only the top-left section of the screen shows. This bit us once on a 1080p TV (some non-4K Roku
  models run their UI at 720p even on a 1080p panel). With `fhd` only, Roku scales the scene itself.
- Use `roDeviceInfo.GetUIResolution()` (design space), never `GetDisplaySize()` (physical panel).

## Architecture

```
source/main.brs                 roSGScreen bootstrap; passes deep links (launch args `contentId`, roInput) to
                                MainScene.deepLink and ends the app when MainScene sets `exitApp`; logs memory limit and
                                low-memory events (roAppMemoryMonitor + roDeviceInfo, which certification's static analysis checks for)
source/utils/M3UParser.brs      #EXTINF → { id, number, name, logoUrl, group, streamUrl } (group = group-title, "" if none)
source/utils/XmltvParser.brs    XMLTV → programs keyed by channel id, sorted by start; keeps subtitle/rating/episode/year/genres,
                                plus `cats` (every category, lowercased, "|a|b|") for the filters
source/utils/DateUtils.brs      XMLTV timestamp → epoch; epoch → "H:MM AM"
source/utils/ProgramFilters.brs "on now" filter rules (News, Kids, Game Shows, Football, …; array order = picker order): categories, title, channel name,
                                group-title regexes + exclude/skipCat vetoes. Some providers' channels have no <category> tags, so
                                title/channel rules carry them. Tune against real data before changing (see note below)
source/utils/RegistryUtils.brs  settings (section "iptv", sources as a JSON list) + hidden channels: "iptv_hidden" (user,
                                permanent) and "iptv_skip" (unsupported codec, 14 days), values JSON { t, name, num } so
                                Settings can name channels that aren't loaded (old bare-timestamp values still read).
                                `lastChannelId` (written on every tune, outside readSettings/writeSettings) feeds the
                                `onLaunch` = "resume" setting. "iptv_fav" (favorite channel ids, value like hidden) and
                                "iptv_remind" (reminders keyed "<channel id>@<start>", JSON { id, start, stop, title, name, num },
                                ended ones pruned by `readReminders`)
components/MainScene            owns all state (channels, programs, current/previous channel); routes scenes.
                                `allChannels` is every fetched channel; `channels` = allChannels minus hidden
                                (`filterHiddenChannels`), recomputed after a fetch, a hide, and whenever Settings closes.
                                First guide open (`m.launched`): `resumeLastChannel` sets currentChannel so it plays in
                                the PIP (never fullscreen) with the cursor on it. Hands Settings `epgInfo()` for About.
                                Reminders: `markReminders` sets `remind = true` on reminded programmes (InfoPanel REMINDER
                                badge); `remindTimer` (15s) pops a Dialog a minute before the start (Watch Now / Dismiss,
                                deferred while Settings, the loading screen or another dialog is up) and deletes the entry
components/GuideScene           guide grid (bottom-anchored) + InfoPanel (top-left, fills space left of PIP) + PIP Video (top-right, 16:9, fills space above guide) + toast
                                + "on now" filters: guideData carries every channel, GuideScene passes the grid only the
                                channels whose current show matches the active filter (a view; MainScene's state is
                                untouched, it only keeps `filterKey` across rebuilds). Replay (↺) opens FilterPicker with
                                live counts; a 60s Timer re-applies it and drops back to all channels when nothing matches.
                                A pill top-right of the InfoPanel names the filter. "favorites" is a filter key too, but
                                not a ProgramFilters rule: it keeps the channels in `guideData.favs` whatever is on.
                                OK selects on release: holding it 0.8s (okTimer) opens ChannelMenu for the focused
                                channel instead, and the pick goes to MainScene as `menuAction` { action, channel }
components/ChannelMenu          long-press OK popup (centred, sized to its items): "Record…" (only for a show that hasn't ended
                                on a source with a Dispatcharr `apiKey`, `guideData.dvr`), "Set/Cancel Reminder" (only for a
                                show that hasn't started), "Add to/Remove from Favorites", "Hide Channel", "Filter…" (opens FilterPicker) and "Settings…" (same as *; both handled in GuideScene). "Record…" reopens
                                it as This Episode / Series: All / Series: New. Keys forwarded via `keyEvent`; emits `chosen`
                                and hides itself
components/FilterPicker         filter list over the left of the guide (rows aligned with guide rows, pooled, scrolls);
                                keys forwarded via `keyEvent`; emits `chosen` and hides itself
components/GuideGrid            virtual grid: pooled GuideRow nodes (58px), cursor; window hours + row count from settings;
                                clock + now line ticked by a 5s Timer (paused while the guide is hidden).
                                Per-show cursor: an anchor time on the focused row selects the show covering it;
                                Left/Right step shows (window jumps when the show is off-window), Up/Down keep the
                                anchor; the anchor follows now until Left/Right picks a show not on now
components/GuideRow             one channel row; pooled program cells; highlights the cell covering `selTime`
components/PlayerScene          fullscreen Video, NowPlayingPanel on Up (10s auto-hide), retry/blacklist logic
components/CountdownRing        64px ring of 40 ticks that go dark clockwise + seconds left; NowPlayingPanel's
                                auto-hide countdown (visual only; PlayerScene's panelTimer still hides the panel)
components/SettingsScene        left nav (IPTV Sources / Guide / Options / Remote / Hidden Channels / About) + content pages; source list with
                                a per-source editor page; StandardKeyboardDialog for text entry. Hidden Channels lists both kinds
                                (colour strip + status: Deep Teal "Hidden by you", Camel "Unsupported, N days left"), pooled
                                rows like the source list; Unhide / Hide Permanently / Unhide All write the registry at
                                once rather than on Save. Retry (codec rows) plays the stream in a preview overlay
                                (`streamUrls` from MainScene; 2 attempts, 20s timeout): playing → unhidden, else it stays. Back from the nav with edits pending (`hasUnsavedChanges`,
                                compares against the registry) asks Save / Discard / Keep Editing. Remote is a read-only key reference (`renderRemote`; update it when a key handler changes). About is read-only:
                                roAppInfo/roDeviceInfo plus the `epgInfo` field MainScene sets
components/tasks/FetchDataTask  parallel HTTP fetch of every enabled source, parse, per-source failure flags;
                                `progress` { fraction, msg } drives the loading-screen bar (foreground fetch only)
components/tasks/RefreshTimerTask  ticks every N minutes → MainScene runs a background fetch
components/tasks/RecordingsTask    Dispatcharr DVR: for each enabled source with an `apiKey`, GETs /api/channels/recordings/
                                (+ /api/channels/channels/ for id → uuid) with X-API-Key. MainScene runs it every 5 min
                                (`recTimer`) and after each fetch; `markRecordings` sets `rec = true` on programmes a recording
                                covers ≥ half of (recordings are padded), matched by the uuid at the end of the proxy stream URL.
                                GuideRow draws a red dot (images/rec_dot.png tinted), InfoPanel a REC badge
components/tasks/DvrTask        long-press Record → Dispatcharr: one airing = POST /api/channels/recordings/ with the programme's
                                own times (Dispatcharr pads them itself); series = POST /api/channels/series-rules/ with the EPG's
                                tvg_id + epg_source (channel → epg_data_id → /api/epg/epgdata/{id}/), mode all|new, pinned to
                                the channel. REST helpers shared with RecordingsTask live in source/utils/DispatcharrApi.brs
```

Data flow: FetchDataTask → MainScene (`mergeFetchResult`, blacklist filter) → `guideScene.guideData`
→ `guideGrid.guideData` → `row.rowData`. MainScene is the only place that mutates channel/program state.

## Conventions and gotchas (learned the hard way)

- **Field observers don't fire on same-value sets.** Any "action"-style string field that can be sent
  twice in a row (`action`, `refreshUrl`, `scrollToChannelId`) must have `alwaysNotify="true"`.
- **Bundle related inputs into one assocarray field** (`guideData`, `rowData`) instead of several
  fields with the same onChange handler. Array/assocarray fields notify on every set, so separate
  fields mean N rebuilds per update.
- **One video decoder.** PIP (GuideScene) and fullscreen (PlayerScene) never play at once. Whoever
  becomes visible must stop the other first, and going back to the player must restart playback.
- **Node creation is the expensive operation.** Pool and reuse nodes (GuideRow cells, GuideGrid rows,
  header labels); update fields rather than remove/create.
- **Sources are a user-ordered list** (`sources` in the registry, JSON): `{ id, name, m3uUrl, epgUrl, apiKey, enabled,
  tsToHls }` (`apiKey`: Dispatcharr API key for recordings). A fresh install has no sources and opens Settings. List order is guide order. Every channel id and program key is prefixed `<id>_` (`sourcePrefix`,
  `idPrefixOf`), so a source's `id` never changes and is never reused (`nextSourceId`); that keeps blacklist keys
  and kept-on-failure data attached to the right source across reorders. `tsToHls` rewrites `.ts` URLs to
  `.m3u8?mode=segmenter` (ErsatzTV). An HDHomeRun's raw `lineup.m3u` uses `channel-id`/`channel-number` in its
  `#EXTINF` lines, which M3UParser reads as fallbacks.
- **Stream tokens expire** (`e=`/`st=` params, ~12h). On a playback error the player asks MainScene
  for an M3U-only re-fetch (`tokenExpired`), up to 2 retries per channel. Video error code -5 means
  unsupported codec → one re-fetch + retry (`codecRetried`, a proxy's error stream also reads as -5), then the
  channel is blacklisted for 14 days in the registry.
- **Per-source failure flags** (FetchDataTask `failed`: `{ <id>: { m3u, epg } }`) let MainScene keep a
  source's previous data, in its place in the order, when its fetch fails or is skipped.
- **BrightScript names are case-insensitive**, including `m.` members: `m.ROWS` and `m.rows` are the same slot.
  Never tell two members (or locals) apart by case alone.
- **JSON round trips lowercase the keys.** `FormatJson` writes `{ m3uUrl }` as `"m3uurl"`, and the arrays `ParseJson`
  returns match keys case-sensitively, so `obj["m3uUrl"]` misses (dot access is lowercased and works). Read
  registry JSON with lowercase keys (see `normalizeSource`); this once dropped every source's URLs and API key.
- Debug `print` lines are fine but keep them to one-line status messages; no per-item dumps.
- **Calling a function on another component** needs `<function name="…" />` in its `<interface>` and
  `node.callFunc("name", arg)`; `node.name(arg)` does not work on an roSGNode.
- **Never give a TextEditBox focus.** It swallows Down (clears text) and Left/Right (cursor), so the
  scene's `onKeyEvent` stops seeing them. SettingsScene keeps focus on itself, highlights the field's
  border rect, and opens a `StandardKeyboardDialog` via `m.top.getScene().dialog` on OK.
- Adding a setting: add nodes to a page `<Group>` in SettingsScene.xml, add a row (`[id]`, or several ids for
  items side by side) to that page's `rows` in `m.pages`, and register it in `m.inputBoxes` (+ `m.inputTitles`), `m.choosers` (pill row:
  `<prefix>N` rect + `<prefix>LabelN` label per option, plus a focus-ring rect) or `m.buttonColors`.
  Then read/write it in `readSettings`/`writeSettings` (RegistryUtils) and include it in `trySave`.
  A new nav section is a `navBg`/`navBar`/`navLabel` triple plus a page group and an `m.pages` entry.
  The IPTV Sources page is the exception: its rows come from `m.sources` (`currentRows`), its row nodes are
  pooled in `renderSourceList`, and while a source is open `pageSourceEdit` replaces it (`m.editIdx`).
  Source edits live in a working copy and reach the registry only on Save.
- Settings save emits `saved` when any source changed (added, removed, moved or edited) (MainScene re-fetches) or `savedLocal` when
  only guide/refresh options changed (MainScene just reopens the guide). GuideGrid reads `guideHours`
  and `guideRows` from the registry in `init` and pushes a `layout` assocarray into each pooled
  GuideRow. `guideGeometry()` (RegistryUtils) is the single source for row height (58), guide height,
  the space above it and the PIP/InfoPanel rectangles; GuideScene and GuideGrid only apply its numbers.
  Fixed row geometry (58px, 40px logo, fonts) lives in GuideRow.xml; `layout` carries only the window.
  A layout change requires recreating GuideScene, which `openGuide` always does.
- InfoPanel.brs is shared by InfoPanel and NowPlayingPanel (same node ids; NowPlayingPanel is a fixed 1920x420 overlay with larger fonts). It takes a `panelSize`
  assocarray (InfoPanel only), reflows label widths, lets the description fill the remaining height
  (`numLines = 0`), shows the programme poster (2:3, left, from `<icon src>` or `<image type="poster">`)
  shifting the text column right only once `loadStatus = "ready"` (so dead URLs never jitter), and draws
  pooled badge nodes (rating, NEW, episode, year, up to 3 genres) after the time text, measured with
  `boundingRect()` and dropped when they would overflow. The title is a `ScrollingLabel` (marquee on
  overflow); the description Label sits in a `clippingRect` Group and an Animation scrolls it
  (pause, glide, pause, loop) only when `boundingRect().height` exceeds the clip. Animations stop
  while the panel is not visible.

## Tuning the programme filters

Rules are regexes, so false positives creep in ("World Series of Darts" in Baseball, a cricket "Caribbean Premier
League" in Soccer, *Avatar* tagged "Martial Arts" in Combat Sports). Check a change against real data before
shipping: fetch a full M3U + XMLTV and run the same rules over every programme
(Python `re` is close enough to roRegex's PCRE), looking at what each filter picks up and why (cat/title/chan/group).

## Colour palette

All UI colours come from this set (hex RRGGBB, used as `0xRRGGBBAA` in XML/BRS):

| Role | Colour | Hex |
|---|---|---|
| Primary text | Pearl Beige | `F2E3BC` |
| Secondary text, focus rings, focused buttons, genre badges | Ash Grey | `96BBBB` (dimmed via alpha `AA`/`66` for descriptions/hints) |
| Accent: selected nav/pill, Save, NEW badge, row focus bar | Deep Teal | `618985` |
| Borders, channel column, unselected pills, quiet buttons | Charcoal Brown | `414535` |
| Warm accent: channel name, errors, toast, reset, rating badge, now line | Camel | `C19875` |
| Backgrounds (darker tints of Charcoal) | page `1F2119`, panels/cards `2F3227`, program cells `4A4F3D` | |
| Recording dot / REC badge (the one exception to the palette) | DVR Red | `D0463B` |

Text on a Camel or Ash Grey surface is Charcoal, never Beige.

## Known open issues

- Guide keeps stale stream URLs after a token-expired re-fetch (only the player gets the fresh one).
- Player retry count never resets after a successful play.
- XMLTV detail parsing (badges/poster) roughly doubles per-programme parse work; not yet timed on a
  device with a large provider EPG.
- Programme runs under 7 minutes are one cell and one cursor step. The rule exists twice
  (GuideRow `collapseShortPrograms`, GuideGrid `showEnd`); change both together.
- The guide window starts on the current half hour (`currentHalfHour()`, DateUtils) when the guide is
  opened or the player hands back to it, but it does not advance while the guide stays open. The now
  line and clock keep ticking, so after a few hours the line simply leaves the window.
