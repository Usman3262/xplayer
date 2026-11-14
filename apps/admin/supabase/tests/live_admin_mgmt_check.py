# Live checks for admin management RPCs (migration 014). Creates temporary users
# (super admin, target, content manager), runs checks, deletes them.
# Run from apps/admin:  python supabase/tests/live_admin_mgmt_check.py
import json, secrets, urllib.request, urllib.error
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

users = {}
fails = 0
def check(label, cond, detail=""):
    global fails
    fails += 0 if cond else 1
    print(("PASS " if cond else "FAIL ") + label + ("" if cond else f"  -> {detail}"))

try:
    for n in ["sa", "target", "cm"]:
        email = f"zz-mgmt-{n}-{secrets.token_hex(3)}@xplayer.test"; pw = secrets.token_urlsafe(16)
        s, d = req("POST", "/auth/v1/admin/users", {"email": email, "password": pw, "email_confirm": True}, key=SEC)
        users[n] = {"id": d["id"], "email": email, "pw": pw}
    roles = {r["key"]: r["id"] for r in req("GET", "/rest/v1/admin_roles?select=id,key", key=SEC)[1]}
    req("POST", "/rest/v1/admin_user_roles", {"user_id": users["sa"]["id"], "role_id": roles["super_admin"]}, key=SEC)
    req("POST", "/rest/v1/admin_user_roles", {"user_id": users["cm"]["id"], "role_id": roles["content_manager"]}, key=SEC)
    for u in users.values():
        u["tok"] = req("POST", "/auth/v1/token?grant_type=password", {"email": u["email"], "password": u["pw"]})[1]["access_token"]
    SA, CM, T = users["sa"]["tok"], users["cm"]["tok"], users["target"]["id"]

    s, d = req("POST", "/rest/v1/rpc/admin_find_user", {"p_email": users["target"]["email"].upper()}, tok=SA)
    check("find user by email (case-insensitive)", d == T, d)
    s, d = req("POST", "/rest/v1/rpc/admin_set_role", {"p_user": T, "p_role_key": "analyst"}, tok=SA)
    check("super admin: give target a role", s in (200, 204), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_set_role", {"p_user": T, "p_role_key": "support_agent"}, tok=SA)
    s, d = req("POST", "/rest/v1/rpc/admin_list_admins", {}, tok=SA)
    mine = [a for a in d if a["user_id"] == T]
    check("change role keeps ONE role", len(mine) == 1 and mine[0]["role_key"] == "support_agent", mine)
    check("list includes emails", all(a["email"] for a in d), d[:2])
    s, d = req("POST", "/rest/v1/rpc/admin_set_role", {"p_user": T, "p_role_key": "hacker"}, tok=SA)
    check("unknown role rejected", s >= 400 and "Unknown role" in json.dumps(d), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_set_role", {"p_user": users["sa"]["id"], "p_role_key": "analyst"}, tok=SA)
    check("cannot change own role", s >= 400 and "own role" in json.dumps(d), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_set_active", {"p_user": users["sa"]["id"], "p_active": False}, tok=SA)
    check("cannot deactivate self", s >= 400 and "yourself" in json.dumps(d), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_set_active", {"p_user": T, "p_active": False}, tok=SA)
    s2, d2 = req("POST", "/rest/v1/rpc/admin_list_admins", {}, tok=SA)
    check("deactivate target", any(a["user_id"] == T and not a["is_active"] for a in d2), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_set_role", {"p_user": T, "p_role_key": "admin"}, tok=CM)
    check("content manager cannot set roles", s in (401, 403), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_list_admins", {}, tok=CM)
    check("content manager cannot list admins", s in (401, 403), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_set_role", {"p_user": T, "p_role_key": "admin"}, tok=PUB)
    check("anonymous cannot set roles", s in (401, 403), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_remove", {"p_user": T}, tok=SA)
    s2, d2 = req("POST", "/rest/v1/rpc/admin_list_admins", {}, tok=SA)
    check("remove admin access", s in (200, 204) and not any(a["user_id"] == T for a in d2), (s, d))
    s, d = req("GET", f"/rest/v1/audit_logs?select=action,entity&actor_id=eq.{users['sa']['id']}&entity=eq.admin_user_roles&order=id", key=SEC)
    check("role changes audited", len(d) >= 4 and {"insert", "update", "delete"} <= {x["action"] for x in d}, d)
finally:
    for u in users.values():
        req("DELETE", f"/auth/v1/admin/users/{u['id']}", key=SEC)
    print("temp users deleted;", "ALL PASS" if fails == 0 else f"{fails} FAILED")
