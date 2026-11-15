# Provider protocols — working notes

Reference for the provider adapters (`packages/data`, Phase 5). Sources are
community docs and real-panel behaviour, **not official specs**: panels differ, so
every adapter must be tolerant (strings vs numbers, missing fields, alternate
parameter names) and be tested against real panels. Never log credentials or full
stream URLs.

---

## 1. Xtream Codes API (Neo is an Xtream panel)

Base: `{scheme}://{host}[:port]/player_api.php?username={u}&password={p}`

### Login / account
`GET player_api.php?username&password` (no action)
```json
{ "user_info": { "auth": 1, "status": "Active", "exp_date": "1767225600",
    "is_trial": "0", "active_cons": "0", "max_connections": "1",
    "allowed_output_formats": ["m3u8","ts"] },
  "server_info": { "url": "host", "port": "80", "https_port": "443",
    "server_protocol": "http", "timezone": "Europe/London", "timestamp_now": 1731600000 } }
```
- `auth != 1` → invalid credentials. `status` (Active / Expired / Banned / Disabled) → our
  connection state. `exp_date` unix seconds as string or null (= unlimited).
- `max_connections` matters: most accounts allow **1 stream at a time** (stop the old
  player before starting a new one).

### Catalog actions (`&action=`)
| Action | Params | Returns |
|---|---|---|
| `get_live_categories` / `get_vod_categories` / `get_series_categories` | — | `[{category_id, category_name, parent_id}]` |
| `get_live_streams` | `category_id` (optional = all) | `[{num, name, stream_id, stream_icon, epg_channel_id, added, category_id, tv_archive, tv_archive_duration}]` |
| `get_vod_streams` | `category_id` optional | `[{stream_id, name, stream_icon, rating, added, category_id, container_extension, tmdb?}]` |
| `get_series` | `category_id` optional | `[{series_id, name, cover, plot, cast, director, genre, releaseDate, rating, backdrop_path[], last_modified, category_id, tmdb?}]` |
| `get_vod_info` | `vod_id` | `{info:{tmdb_id, name, plot, cast, director, genre, duration_secs, releasedate, backdrop_path[], youtube_trailer, rating}, movie_data:{stream_id, container_extension}}` |
| `get_series_info` | `series_id` (some panels: `series`) | `{info:{…}, seasons:[…], episodes:{"1":[{id, episode_num, title, container_extension, info:{duration_secs, plot, movie_image}}]}}` |
| `get_short_epg` | `stream_id`, `limit` | `{epg_listings:[{title(base64), description(base64), start, end, start_timestamp, stop_timestamp}]}` |
| `get_simple_data_table` | `stream_id` | full EPG for one channel (base64 titles) |

Other endpoints: XMLTV `xmltv.php?username&password` (big — stream/parse in isolate);
M3U export `get.php?username&password&type=m3u_plus&output=ts|m3u8`.

### Stream URLs (built on device, never stored globally)
- Live: `{scheme}://{host}/live/{u}/{p}/{stream_id}.{ts|m3u8}` — Neo tester: **`.ts` over
  http is the reliable live format**; `.m3u8` caused fragment errors in browsers.
- Movie: `{scheme}://{host}/movie/{u}/{p}/{stream_id}.{container_extension}`
- Episode: `{scheme}://{host}/series/{u}/{p}/{episode_id}.{container_extension}`
- Catch-up: `{scheme}://{host}/timeshift/{u}/{p}/{minutes}/{YYYY-MM-DD:HH-MM}/{stream_id}.ts`
- Output format must be one of `allowed_output_formats`.

### Gotchas
- Numbers often arrive as strings; ids may be int or string → parse leniently.
- Names starting with `#####` are separators/headers, not channels (skip).
- `category_id` can be null / "0"; uncategorised bucket needed.
- Fetching **all** VOD/series in one call can be tens of MB → stream + parse in an
  isolate, or fetch per category lazily.
- `added` / `last_modified` (unix) are the cheap way to detect new items (incremental sync).
- `tmdb` / `tmdb_id` present on some panels → direct match to the global catalog.

### Trial line (`*.wd.business-cloud-8.ru`, any subdomain), measured 2026-11-15
- Login 0.53 s; max 1 connection; ts/m3u8; `https_port` 443 but protocol http.
- **Full lists: live 57,136 (21 MB, 7.6 s), movies 187,449 (77 MB, 20 s), series 50,285
  (74 MB, 17 s)** — 921 / 447 / 388 categories; tmdb 92 % movies / 89 % series.
- ⇒ **Phase 6 must not pull whole lists in one go on TV boxes**: browse per category (small, fast),
  background sync category by category straight into the local DB, keep memory flat.
- EPG: short EPG includes the programme on air now (unlike Neo).

### Neo, as measured live (2026-11-15, test account, `XtreamAdapter` LIVE test)
- Login ≈0.5–0.75 s; `max_connections` 1; formats `m3u8, ts, rtmp`; `server_info.https_port` empty → http only.
- **Full lists, no category filter (test line):** live 3,070 (67 `#####` headers) 1.1 MB 1.4 s;
  movies 14,703 6.0 MB 2.1 s (tmdb 96 %, mkv 73 % / mp4 27 %); series 10,063 19.9 MB 3.1 s
  (tmdb 82 %). Added last 7 d: 120 movies / 278 series. Whole catalog ≈27 MB ≈7 s → Phase 6 can
  pull full lists once in the background, then sync incrementally by `added` / `last_modified`.
- Streams: live `.ts` first bytes 0.99 s (MPEG-TS); movie `.mkv` 0.76 s. Plain http.
- 113 live / 90 movie / 95 series categories. First live category: 68 channels, all with logos,
  38 with `epg_channel_id`, none with catch-up. Movies: `tmdb` on ~95 %, `rating` as string.
- `get_series_info`: `seasons: []` — seasons exist only as `episodes` keys ("1": […]).
- Dates like `"2026-01-11 (مصر)"`; genres `"Drama / Comedy"` or `"Adventure, Family"`.
- EPG: many channels have an `epg_channel_id` but no listings. Where present, `get_short_epg`
  returns **upcoming** programmes (the one on air now may be missing) → show channel name as
  "now" in that case; `get_simple_data_table` has ≈5 days back + ≈5 days ahead. Timestamps are
  unix strings (UTC); titles base64.

---

## 2. M3U / M3U8 playlists

```
#EXTM3U url-tvg="http://epg.example/xmltv.xml"
#EXTINF:-1 tvg-id="bbc1.uk" tvg-name="BBC One" tvg-logo="http://…/bbc1.png" group-title="UK" tvg-chno="101" catchup="default" catchup-days="7",BBC One HD
#EXTVLCOPT:http-user-agent=Mozilla/5.0
http://host/live/u/p/123.ts
```
- Header attrs: `url-tvg` / `x-tvg-url` (EPG URL, may be comma-separated).
- `#EXTINF:` duration (`-1` live), attributes `key="value"`, title after the last comma.
- Per-item options: `#EXTVLCOPT:http-user-agent=…`, `http-referrer=…`, `#KODIPROP:…`,
  `#EXTGRP:` (group fallback).
- Kind detection: Xtream-style paths `/movie/` `/series/` or file extensions
  (`.mp4 .mkv .avi`) = VOD; else live.
- Parse in an isolate; dedupe by (url) then (tvg-id + name); keep source order.
- **Panel M3U exports are often disabled:** Neo and the trial line answer `get.php` with **HTTP 884**
  (403 with a browser User-Agent) → adapter reports `unsupported` ("use the Xtream login").
  **Never retry get.php in a loop** — Neo IP-blocked this PC (403 on everything, incl. login) right
  after 8 export attempts + 2 full catalog pulls (2026-11-15).
- Measured: 7.3 MB / 78k-entry playlist → grouped catalog in 3.6 s in an isolate (debug test VM).
- Sizes up to 100k+ lines → stream the download, don't hold multiple copies.

---

## 3. Stalker / Ministra portal (MAG, "MAC" login)

User gives **portal URL** + **MAC address** (format `00:1A:79:XX:XX:XX`).
API endpoint: usually `{portal}/portal.php` or `{portal}/stalker_portal/server/load.php`
(try both; `…/c/` in the URL is the web UI).

Headers on every call:
```
User-Agent: Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3
X-User-Agent: Model: MAG250; Link: WiFi
Cookie: mac={MAC}; stb_lang=en; timezone={IANA tz}
Authorization: Bearer {token}        (after handshake)
```
Flow (responses are wrapped in `{"js": …}`):
1. `?type=stb&action=handshake&JsHttpRequest=1-xml` → `js.token`.
2. `?type=stb&action=get_profile&…` (some portals need `sn`, `device_id`, `signature`
   derived from the MAC) → account/profile; failure = MAC not authorised.
3. `?type=account_info&action=get_main_info` → expiry (`phone`/`end_date` field varies).
4. Live: `type=itv&action=get_genres`; `type=itv&action=get_all_channels` (or
   `get_ordered_list&genre={id}&p={page}`) → `{id, name, number, logo, cmd, tv_genre_id}`.
5. Play: `type=itv&action=create_link&cmd={url-encoded cmd}` → `js.cmd` like
   `ffmpeg http://…` → strip the `ffmpeg ` prefix. Links are short-lived → resolve
   right before playback.
6. VOD: `type=vod&action=get_categories`, `get_ordered_list&category={id}&p={page}`,
   `create_link&cmd=…`. Series: `type=series&…` (portal-dependent).
7. EPG: `type=itv&action=get_short_epg&ch_id={id}` or `get_epg_info&period={hours}`.
- Paginated lists: `js.total_items`, `js.max_page_items` (often 14) → fetch pages in
  parallel with a small concurrency limit.
- Token expires → on 401/`Authorization failed` re-handshake once, then retry.
- Only use MACs the user is authorised for (their own device / provider-issued).

### Measured on a real portal (user's MAG trial, `*.wd.business-cloud-8.ru/c/`, 2026-11-15)
- Endpoint `/portal.php` (first candidate). Handshake 0.7 s → token; `get_profile` `status: 0`, `blocked: "0"`.
- **Expiry is in `account_info.get_main_info` → `phone`**: `"November 16, 2026, 9:29 am"`.
- `get_genres` 922 entries incl. `{"id":"*","title":"All"}` (drop it). Pages of **14**.
- Live: list `cmd` = `ffmpeg http://…/play/live.php?mac=…&stream={id}&extension=ts&play_token=…`.
  **`create_link` with that cmd returns `stream=` EMPTY (connection reset)**; with
  `cmd=ffmpeg http://localhost/ch/{id}_` it returns a full fresh link → MPEG-TS in 0.8 s. Adapter tries
  the list cmd, falls back to the localhost form.
- VOD: `cmd` is base64 JSON `{"type":"movie","stream_id":…}`; list items already carry description,
  actors, director, `genres_str`, `time` (minutes), `rating_imdb`, `tmdb_id`, `added` "YYYY-MM-DD hh:mm:ss".
  `create_link type=vod` → `/play/movie.php` (MKV plays).
- Series: list item id `"49938:49938"`, `is_series: 1`, no cmd. Seasons = `type=series&action=get_ordered_list
  &movie_id={id}&season_id=0&episode_id=0` → items id `"49938:1"`, `cmd`, `series: [1,2,…]` (episode numbers).
  Play = `create_link type=vod cmd={season cmd} series={n}`. No per-episode titles.
- Same provider as the trial Xtream line (same 921/447/388 categories) — Stalker is a front-end to it.
- MAC is only a cookie value → works on any network; never the device's real (randomised) Wi-Fi MAC.

---

## 4. "Connect in seconds" strategy (all adapters)
1. Validate input locally (URL format, MAC format) — instant feedback.
2. One **account/auth call** with a short timeout (≈5–8 s) → show success / clear error.
3. Immediately open Home with whatever is cheap: categories + first page of live
   channels; continue syncing VOD/series/EPG **in the background** (isolate parsing).
4. Cache everything locally (Drift); next launch shows cached data instantly and
   refreshes in the background (incremental using `added`/`last_modified`/counts).
5. Parallel requests with a concurrency cap (providers rate-limit / ban bursts).
6. Respect `max_connections`: one active stream; stop previews before playing.

## Sources consulted (2026-11-14)
- Xtream endpoint references (community): drm-free.duckdns.org/thegame_1980/xtream-codes-api-documentation,
  tv.astra.ps/docs/XTREAM_CODES_API_DOCUMENTATION.md, mintlify.wiki/euzu/tuliprox/api/xtream
- Stalker client reference: docs.rs/crate/crispy-stalker (portal discovery, MAC auth, pagination, create_link)
- Local: `neo-channel-tester.html` (git-ignored, contains real credentials)
