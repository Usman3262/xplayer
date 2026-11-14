# Render an admin page as a TEMPORARY admin (created + deleted with the secret key).
# The temp admin enrolls TOTP 2FA and uses an aal2 session (works with require_two_factor on).
# Start `npx next dev -p 3920` in apps/admin first, then from apps/admin:
#   python scripts/render_check.py <path> <role_key> [expected text ...]
# Prints status, final URL and FOUND/MISSING per expected text. Exit 1 if anything is missing.
import base64, hashlib, hmac, json, secrets, struct, sys, time, urllib.request, urllib.error

U = "https://phkqmojtdyaohiixakvv.supabase.co"
REF = "phkqmojtdyaohiixakvv"
BASE = "http://localhost:3920"
env = dict(l.strip().split("=", 1) for l in open(".env.local") if "=" in l and not l.startswith("#"))
PUB, SEC = env["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"], env["SUPABASE_SECRET_KEY"]

def api(m, p, b=None, key=PUB, tok=None):
    r = urllib.request.Request(U + p, data=None if b is None else json.dumps(b).encode(), method=m,
                               headers={"apikey": key, "Authorization": "Bearer " + (tok or key), "Content-Type": "application/json"})
    with urllib.request.urlopen(r) as x:
        t = x.read().decode()
        return json.loads(t) if t else None

def totp(secret_b32):
    key = base64.b32decode(secret_b32.upper() + "=" * (-len(secret_b32) % 8))
    h = hmac.new(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
    o = h[-1] & 0x0F
    return f"{(struct.unpack('>I', h[o:o+4])[0] & 0x7FFFFFFF) % 1_000_000:06d}"

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None

path, role = sys.argv[1], sys.argv[2]
needles = sys.argv[3:]
email = f"zz-render-{secrets.token_hex(3)}@xplayer.test"
pw = secrets.token_urlsafe(16)
u = api("POST", "/auth/v1/admin/users", {"email": email, "password": pw, "email_confirm": True}, key=SEC)
ok = True
try:
    rid = api("GET", f"/rest/v1/admin_roles?select=id&key=eq.{role}", key=SEC)[0]["id"]
    api("POST", "/rest/v1/admin_user_roles", {"user_id": u["id"], "role_id": rid}, key=SEC)
    sess = api("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": pw})
    # Admins may be required to use 2FA → enroll an authenticator and use an aal2 session.
    tok = sess["access_token"]
    f = api("POST", "/auth/v1/factors", {"factor_type": "totp", "friendly_name": "render-check"}, tok=tok)
    ch = api("POST", f"/auth/v1/factors/{f['id']}/challenge", {}, tok=tok)
    sess = api("POST", f"/auth/v1/factors/{f['id']}/verify", {"challenge_id": ch["id"], "code": totp(f["totp"]["secret"])}, tok=tok)
    val = "base64-" + base64.urlsafe_b64encode(json.dumps(sess).encode()).decode().rstrip("=")
    name = f"sb-{REF}-auth-token"
    chunks = [val[i:i + 3180] for i in range(0, len(val), 3180)]
    cookie = "; ".join([f"{name}={chunks[0]}"] if len(chunks) == 1 else [f"{name}.{i}={c}" for i, c in enumerate(chunks)])
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(urllib.request.Request(BASE + path, headers={"Cookie": cookie}), timeout=120) as x:
            code, html, loc = x.status, x.read().decode(), ""
    except urllib.error.HTTPError as e:
        code, html, loc = e.code, e.read().decode(), e.headers.get("location", "")
    print("status", code, ("-> " + loc) if loc else "", "bytes", len(html))
    for n in needles:
        hit = n in html
        ok &= hit
        print(("FOUND " if hit else "MISSING ") + n)
finally:
    api("DELETE", f"/auth/v1/admin/users/{u['id']}", key=SEC)
    print("temp admin deleted")
sys.exit(0 if ok else 1)
