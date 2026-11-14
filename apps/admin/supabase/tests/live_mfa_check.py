# Live check: admin 2FA is enforced in the DATABASE (migration 015).
# Temporary super admin enrolls TOTP via the Auth API (codes computed here),
# then permissions are checked with aal1 vs aal2 sessions. User deleted after.
# Run from apps/admin:  python supabase/tests/live_mfa_check.py
import base64, hashlib, hmac, json, secrets, struct, time, urllib.request, urllib.error
U = "https://phkqmojtdyaohiixakvv.supabase.co"
env = dict(l.strip().split("=", 1) for l in open(".env.local") if "=" in l and not l.startswith("#"))
PUB, SEC = env["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"], env["SUPABASE_SECRET_KEY"]

def req(m, p, b=None, key=PUB, tok=None):
    r = urllib.request.Request(U + p, data=None if b is None else json.dumps(b).encode(), method=m,
                               headers={"apikey": key, "Authorization": "Bearer " + (tok or key), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r) as x:
            t = x.read().decode(); return x.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try: return e.code, json.loads(t)
        except Exception: return e.code, t

def totp(secret_b32):
    key = base64.b32decode(secret_b32.upper() + "=" * (-len(secret_b32) % 8))
    h = hmac.new(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
    o = h[-1] & 0x0F
    return f"{(struct.unpack('>I', h[o:o+4])[0] & 0x7FFFFFFF) % 1_000_000:06d}"

fails = 0
def check(label, cond, detail=""):
    global fails
    fails += 0 if cond else 1
    print(("PASS " if cond else "FAIL ") + label + ("" if cond else f"  -> {detail}"))

email = f"zz-mfa-{secrets.token_hex(3)}@xplayer.test"; pw = secrets.token_urlsafe(16)
s, u = req("POST", "/auth/v1/admin/users", {"email": email, "password": pw, "email_confirm": True}, key=SEC)
try:
    rid = req("GET", "/rest/v1/admin_roles?select=id&key=eq.super_admin", key=SEC)[1][0]["id"]
    req("POST", "/rest/v1/admin_user_roles", {"user_id": u["id"], "role_id": rid}, key=SEC)
    tok1 = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": pw})[1]["access_token"]
    perm = lambda t: req("POST", "/rest/v1/rpc/has_permission", {"perm": "users.read"}, tok=t)[1]

    check("no 2FA yet: permissions work with password only", perm(tok1) is True)
    s, f = req("POST", "/auth/v1/factors", {"factor_type": "totp", "friendly_name": "test"}, tok=tok1)
    check("enroll authenticator", s == 200 and f.get("totp", {}).get("secret"), (s, f))
    fid, secret = f["id"], f["totp"]["secret"]
    s, ch = req("POST", f"/auth/v1/factors/{fid}/challenge", {}, tok=tok1)
    s, sess2 = req("POST", f"/auth/v1/factors/{fid}/verify", {"challenge_id": ch["id"], "code": totp(secret)}, tok=tok1)
    check("verify code → aal2 session", s == 200 and sess2.get("access_token"), (s, sess2))
    tok2 = sess2["access_token"]

    check("old password-only (aal1) session: permission DENIED", perm(tok1) is False, perm(tok1))
    s, d = req("POST", "/rest/v1/rpc/my_permissions", {}, tok=tok1)
    check("aal1: my_permissions empty", d == [], d)
    s, d = req("POST", "/rest/v1/rpc/admin_security_state", {}, tok=tok1)
    check("aal1: state says has_2fa + aal1", d and d["has_2fa"] and d["aal"] == "aal1", d)
    check("aal2 session: permission granted", perm(tok2) is True, perm(tok2))

    tok3 = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": pw})[1]["access_token"]
    check("new sign-in with password only (stolen password): DENIED", perm(tok3) is False)
    s, ch = req("POST", f"/auth/v1/factors/{fid}/challenge", {}, tok=tok3)
    s, bad = req("POST", f"/auth/v1/factors/{fid}/verify", {"challenge_id": ch["id"], "code": "000000" if totp(secret) != "000000" else "111111"}, tok=tok3)
    check("wrong code rejected", s >= 400, (s, bad))
    s, d = req("GET", "/rest/v1/app_settings?select=key&key=eq.admin.require_two_factor", tok=tok2)
    check("aal2 admin can read the require-2FA setting", s == 200 and len(d) == 1, d)
finally:
    req("DELETE", f"/auth/v1/admin/users/{u['id']}", key=SEC)
    print("temp admin deleted;", "ALL PASS" if fails == 0 else f"{fails} FAILED")
