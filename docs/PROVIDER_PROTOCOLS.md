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
