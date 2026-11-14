# Live RLS checks against the hosted project. Creates 2 temporary users
# (plain + content_manager), runs checks, deletes them. Needs .env.local with
# SUPABASE_SECRET_KEY. Run from apps/admin:  python supabase/tests/live_rls_check.py
import json, os, secrets, urllib.request, urllib.error
U="https://phkqmojtdyaohiixakvv.supabase.co"
env=dict(l.strip().split("=",1) for l in open(".env.local") if "=" in l and not l.startswith("#"))
PUB=env["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"]; SEC=env["SUPABASE_SECRET_KEY"]
def req(method, path, body=None, key=PUB, token=None, extra=None):
    h={"apikey":key,"Authorization":"Bearer "+(token or key),"Content-Type":"application/json"}
    h.update(extra or {})
    r=urllib.request.Request(U+path, data=None if body is None else json.dumps(body).encode(), method=method, headers=h)
    try:
        with urllib.request.urlopen(r) as resp:
            t=resp.read().decode(); return resp.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        t=e.read().decode()
        try: return e.code, json.loads(t)
        except: return e.code, t
users={}
try:
    for name in ["plain","cm"]:
        email=f"zz-test-{name}-{secrets.token_hex(3)}@xplayer.test"; pw=secrets.token_urlsafe(16)
        s,d=req("POST","/auth/v1/admin/users",{"email":email,"password":pw,"email_confirm":True},key=SEC)
        assert s==200, (s,d)
        users[name]={"id":d["id"],"email":email,"pw":pw}
    s,roles=req("GET","/rest/v1/admin_roles?select=id&key=eq.content_manager",key=SEC)
    s,d=req("POST","/rest/v1/admin_user_roles",{"user_id":users["cm"]["id"],"role_id":roles[0]["id"]},key=SEC)
    assert s in (200,201),(s,d)
    for u in users.values():
        s,d=req("POST","/auth/v1/token?grant_type=password",{"email":u["email"],"password":u["pw"]})
        u["tok"]=d["access_token"]
    P=users["plain"]["tok"]; C=users["cm"]["tok"]
    def check(label, cond, detail=""):
        print(("PASS " if cond else "FAIL ")+label+("" if cond else f"  -> {detail}"))
    # plain user
    s,d=req("POST","/rest/v1/rpc/my_permissions",{},token=P); check("plain: no permissions", s==200 and d==[], d)
    s,d=req("POST","/rest/v1/rpc/is_admin",{},token=P); check("plain: is_admin false", d is False, d)
    s,d=req("GET","/rest/v1/profiles?select=id",token=P); check("plain: sees only own profile", s==200 and len(d)==1 and d[0]["id"]==users["plain"]["id"], d)
    s,d=req("PATCH",f"/rest/v1/profiles?id=eq.{users['plain']['id']}",{"status":"banned"},token=P); check("plain: cannot change own status", s in (401,403), (s,d))
    s,d=req("PATCH",f"/rest/v1/profiles?id=eq.{users['plain']['id']}",{"display_name":"Plain"},token=P,extra={"Prefer":"return=representation"}); check("plain: can change own display name", s==200 and d and d[0]["display_name"]=="Plain", (s,d))
    s,d=req("POST","/rest/v1/admin_user_roles",{"user_id":users["plain"]["id"],"role_id":roles[0]["id"]},token=P); check("plain: cannot make self admin", s in (401,403), (s,d))
    s,d=req("GET","/rest/v1/app_settings?select=key",token=P); check("plain: cannot read admin config tables", s==200 and d==[], d)
    s,d=req("POST","/rest/v1/rpc/publish_app_config",{},token=P); check("plain: cannot publish", s in (401,403), (s,d))
    s,d=req("POST","/rest/v1/rpc/log_audit",{"p_action":"x","p_entity":"y"},token=P); check("plain: cannot write audit", s in (401,403), (s,d))
    # content manager
    s,d=req("POST","/rest/v1/rpc/my_permissions",{},token=C); check("cm: has customization.publish, not users.read", "customization.publish" in d and "users.read" not in d, d)
    s,d=req("GET","/rest/v1/profiles?select=id",token=C); check("cm: sees only own profile (no users.read)", len(d)==1, d)
    s,d=req("PATCH","/rest/v1/app_settings?key=eq.search.min_chars",{"value":9},token=C); check("cm: setting above max rejected", s>=400 and "maximum" in json.dumps(d), (s,d))
    s,d=req("PATCH","/rest/v1/app_settings?key=eq.auth.mode",{"value":"sometimes"},token=C); check("cm: enum setting validated", s>=400, (s,d))
    s,d=req("PATCH","/rest/v1/app_settings?key=eq.search.min_chars",{"value":3},token=C,extra={"Prefer":"return=representation"}); check("cm: valid setting saved", s==200 and d and d[0]["value"]==3 and d[0]["updated_by"]==users["cm"]["id"], (s,d))
    s,v=req("POST","/rest/v1/rpc/publish_app_config",{"p_notes":"RLS test (temporary)"},token=C); check("cm: publish works", s==200 and isinstance(v,int), (s,v))
    s,d=req("POST","/rest/v1/rpc/get_app_config",{"p_platform":"android"}); check("apps see new value", d["version"]==v and d["settings"]["search.min_chars"]==3, (d.get("version"),d.get("settings",{}).get("search.min_chars")))
    s,d=req("GET","/rest/v1/audit_logs?select=id",token=C); check("cm: cannot read audit log (no audit.read)", s==200 and d==[], d)
    s,d=req("GET",f"/rest/v1/audit_logs?select=action,entity,entity_id&actor_id=eq.{users['cm']['id']}&order=id",key=SEC); check("audit rows written for cm (update + publish)", [x["action"] for x in d]==["update","publish"], d)
    s,d=req("POST","/rest/v1/admin_roles",{"key":"hacker","name":"x"},token=C); check("cm: cannot create roles", s in (401,403), (s,d))
    # restore
    s,d=req("PATCH","/rest/v1/app_settings?key=eq.search.min_chars",{"value":2},token=C)
    s,v2=req("POST","/rest/v1/rpc/publish_app_config",{"p_notes":"RLS test cleanup"},token=C)
    s,d=req("POST","/rest/v1/rpc/get_app_config",{"p_platform":"android"}); check("restored and republished", d["settings"]["search.min_chars"]==2, d["settings"]["search.min_chars"])
finally:
    for u in users.values():
        s,_=req("DELETE",f"/auth/v1/admin/users/{u['id']}",key=SEC); print("deleted test user", s)
