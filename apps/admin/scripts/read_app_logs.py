"""Read the diagnostic lines the apps uploaded (table app_logs).

Run from apps/admin (uses the service key in .env.local, read-only query):
  PYTHONIOENCODING=utf-8 python scripts/read_app_logs.py                 # last 30 min, all devices
  python scripts/read_app_logs.py --minutes 120 --model LE2115 --tag PANEL,SYNC
  python scripts/read_app_logs.py --device <install id> --limit 500
"""
import argparse, datetime as dt, json, urllib.parse, urllib.request

env = dict(l.strip().split("=", 1) for l in open(".env.local") if "=" in l and not l.startswith("#"))
URL, KEY = env["NEXT_PUBLIC_SUPABASE_URL"], env["SUPABASE_SECRET_KEY"]

ap = argparse.ArgumentParser()
ap.add_argument("--minutes", type=int, default=30)
ap.add_argument("--device")
ap.add_argument("--session")
ap.add_argument("--model", help="substring of the device model, e.g. LE2115")
ap.add_argument("--tag", help="comma list, e.g. PANEL,SYNC,ERR")
ap.add_argument("--limit", type=int, default=300)
a = ap.parse_args()

since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=a.minutes)).isoformat()
q = [("select", "logged_at,created_at,device_id,session_id,device_model,app_version,tag,message"),
     ("created_at", f"gte.{since}"), ("order", "logged_at.asc,id.asc"), ("limit", str(a.limit))]
if a.session:
    q.append(("session_id", f"eq.{a.session}"))
if a.device:
    q.append(("device_id", f"eq.{a.device}"))
if a.model:
    q.append(("device_model", f"ilike.*{a.model}*"))
if a.tag:
    q.append(("tag", f"in.({','.join(t.strip().upper() for t in a.tag.split(','))})"))
req = urllib.request.Request(f"{URL}/rest/v1/app_logs?{urllib.parse.urlencode(q)}",
                             headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"})
rows = json.loads(urllib.request.urlopen(req, timeout=30).read())
if not rows:
    print(f"no app log lines in the last {a.minutes} min")
last = None
for r in rows:
    head = (r["device_id"], r["session_id"])
    if head != last:
        print(f"\n=== install {r['device_id']} · session {r['session_id']} · {r['device_model'] or '?'} · v{r['app_version'] or '?'}")
        last = head
    t = r["logged_at"][11:19]
    print(f"{t} [{r['tag']}] {r['message']}")
