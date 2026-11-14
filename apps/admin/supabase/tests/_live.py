"""Shared helpers for live checks against the hosted project.

temp_admin(role) creates a temporary user, gives it an admin role (or none),
enrolls TOTP 2FA and returns an aal2 access token. Always call cleanup().
Run scripts from apps/admin with PYTHONIOENCODING=utf-8 on Windows.
"""
import base64, hashlib, hmac, json, secrets, struct, time, urllib.request, urllib.error

U = "https://phkqmojtdyaohiixakvv.supabase.co"
env = dict(l.strip().split("=", 1) for l in open(".env.local") if "=" in l and not l.startswith("#"))
PUB, SEC = env["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"], env["SUPABASE_SECRET_KEY"]
_created = []
_fails = [0]


def req(method, path, body=None, key=PUB, tok=None, headers=None, raw=None, content_type="application/json"):
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    h = {"apikey": key, "Authorization": "Bearer " + (tok or key), "Content-Type": content_type}
    h.update(headers or {})
    r = urllib.request.Request(U + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r) as x:
            t = x.read().decode(errors="ignore")
            try:
                return x.status, (json.loads(t) if t else None)
            except Exception:
                return x.status, t
    except urllib.error.HTTPError as e:
        t = e.read().decode(errors="ignore")
        try:
            return e.code, json.loads(t)
        except Exception:
            return e.code, t


def totp(secret_b32):
    key = base64.b32decode(secret_b32.upper() + "=" * (-len(secret_b32) % 8))
    h = hmac.new(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
    o = h[-1] & 0x0F
    return f"{(struct.unpack('>I', h[o:o + 4])[0] & 0x7FFFFFFF) % 1_000_000:06d}"


def temp_admin(role=None, mfa=True):
    """Returns (user_id, aal2 token). role=None → plain user (no admin role)."""
    email = f"zz-live-{secrets.token_hex(4)}@xplayer.test"
    pw = secrets.token_urlsafe(16)
    s, u = req("POST", "/auth/v1/admin/users", {"email": email, "password": pw, "email_confirm": True}, key=SEC)
    _created.append(u["id"])
    if role:
        rid = req("GET", f"/rest/v1/admin_roles?select=id&key=eq.{role}", key=SEC)[1][0]["id"]
        req("POST", "/rest/v1/admin_user_roles", {"user_id": u["id"], "role_id": rid}, key=SEC)
    sess = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": pw})[1]
    tok = sess["access_token"]
    if mfa:
        s, f = req("POST", "/auth/v1/factors", {"factor_type": "totp", "friendly_name": "live"}, tok=tok)
        s, ch = req("POST", f"/auth/v1/factors/{f['id']}/challenge", {}, tok=tok)
        s, sess = req("POST", f"/auth/v1/factors/{f['id']}/verify", {"challenge_id": ch["id"], "code": totp(f["totp"]["secret"])}, tok=tok)
        tok = sess["access_token"]
    return u["id"], tok


def check(label, cond, detail=""):
    if not cond:
        _fails[0] += 1
    print(("PASS " if cond else "FAIL ") + label + ("" if cond else f"  -> {detail}"))


def cleanup():
    for uid in _created:
        req("DELETE", f"/auth/v1/admin/users/{uid}", key=SEC)
    print(f"temp users deleted ({len(_created)});", "ALL PASS" if _fails[0] == 0 else f"{_fails[0]} FAILED")
