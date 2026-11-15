# Live checks for the admin Users functions (migration 021). Creates temporary
# users (app user, super admin, support agent, content manager), deletes them.
# Run from apps/admin:  PYTHONIOENCODING=utf-8 python supabase/tests/live_users_check.py
import secrets, sys
sys.path.insert(0, "supabase/tests")
from _live import req, temp_admin, check, cleanup, SEC, _created

try:
    # A plain app user who signs up in the app (email confirmed, with a name).
    email = f"zz-app-{secrets.token_hex(4)}@xplayer.test"
    pw = secrets.token_urlsafe(16)
    s, u = req("POST", "/auth/v1/admin/users",
               {"email": email, "password": pw, "email_confirm": True, "user_metadata": {"display_name": "Live Tester"}}, key=SEC)
    _created.append(u["id"])
    APP = u["id"]
    app_tok = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": pw})[1]["access_token"]

    sa_id, SA = temp_admin("super_admin")
    _, SUP = temp_admin("support_agent")
    _, CM = temp_admin("content_manager")

    # Profile row made by the sign-up trigger, with the display name.
    s, d = req("GET", f"/rest/v1/profiles?select=id,display_name,status&id=eq.{APP}", tok=app_tok)
    check("sign-up created the profile with display name", s == 200 and d and d[0]["display_name"] == "Live Tester", (s, d))

    # Who may list users.
    s, d = req("POST", "/rest/v1/rpc/admin_list_users", {})
    check("anon cannot list users", s in (401, 403) or (isinstance(d, dict) and d.get("code") == "42501"), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_list_users", {}, tok=app_tok)
    check("app user cannot list users", isinstance(d, dict) and d.get("code") == "42501", (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_list_users", {}, tok=CM)
    check("content manager (no users.read) cannot", isinstance(d, dict) and d.get("code") == "42501", (s, d))

    s, d = req("POST", "/rest/v1/rpc/admin_list_users", {"p_search": email.split("@")[0].upper()}, tok=SUP)
    row = [r for r in (d or []) if r["id"] == APP] if isinstance(d, list) else []
    check("support agent finds the user by email search (case-insensitive)", len(row) == 1, (s, d))
    if row:
        r = row[0]
        check("row: email, name, active, confirmed, not admin",
              r["email"] == email and r["display_name"] == "Live Tester" and r["status"] == "active"
              and r["email_confirmed"] is True and r["is_admin"] is False, r)
    s, d = req("POST", "/rest/v1/rpc/admin_list_users", {"p_search": "Live Test"}, tok=SUP)
    check("search by display name", isinstance(d, list) and any(r["id"] == APP for r in d), (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_list_users", {"p_search": "%"}, tok=SUP)
    check("'%' is a literal, not a wildcard", isinstance(d, list) and not any(r["id"] == APP for r in d), (s, len(d) if isinstance(d, list) else d))

    # Paging: limit 1 then the next page via the cursor → different row.
    s, p1 = req("POST", "/rest/v1/rpc/admin_list_users", {"p_limit": 1}, tok=SUP)
    if isinstance(p1, list) and p1:
        s, p2 = req("POST", "/rest/v1/rpc/admin_list_users",
                    {"p_limit": 1, "p_before_created": p1[0]["created_at"], "p_before_id": p1[0]["id"]}, tok=SUP)
        check("keyset paging returns the next (older) row", isinstance(p2, list) and (not p2 or (p2[0]["id"] != p1[0]["id"] and p2[0]["created_at"] <= p1[0]["created_at"])), (p1, p2))
    s, d = req("POST", "/rest/v1/rpc/admin_list_users", {"p_status": "weird"}, tok=SUP)
    check("bad status filter rejected", isinstance(d, dict) and d.get("code") == "22023", (s, d))

    s, d = req("POST", "/rest/v1/rpc/admin_user_counts", {}, tok=SUP)
    check("counts readable with users.read", s == 200 and isinstance(d, list) and d[0]["total"] >= 1, (s, d))

    # Changing status: support agent (read only) cannot; super admin can.
    s, d = req("POST", "/rest/v1/rpc/admin_set_user_status", {"p_user": APP, "p_status": "banned"}, tok=SUP)
    check("support agent (no users.write) cannot ban", isinstance(d, dict) and d.get("code") == "42501", (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_set_user_status", {"p_user": APP, "p_status": "banned", "p_reason": "live test"}, tok=SA)
    check("super admin bans the user", s in (200, 204), (s, d))
    s, d = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": pw})
    check("banned user can no longer sign in (Supabase Auth)", s >= 400, (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_list_users", {"p_status": "banned", "p_search": email}, tok=SA)
    check("status filter shows the banned user", isinstance(d, list) and any(r["id"] == APP for r in d), (s, d))
    s, d = req("GET", f"/rest/v1/audit_logs?select=action,entity_id,after,meta&entity_id=eq.{APP}&action=eq.user.status", key=SEC)
    check("ban written to the audit log with the reason",
          isinstance(d, list) and any(a["after"] == {"status": "banned"} and (a.get("meta") or {}).get("reason") == "live test" for a in d), (s, d))

    s, d = req("POST", "/rest/v1/rpc/admin_set_user_status", {"p_user": APP, "p_status": "active"}, tok=SA)
    check("super admin re-activates", s in (200, 204), (s, d))
    s, d = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": pw})
    check("re-activated user can sign in again", s == 200 and "access_token" in (d or {}), (s, d))

    s, d = req("POST", "/rest/v1/rpc/admin_set_user_status", {"p_user": sa_id, "p_status": "suspended"}, tok=SA)
    check("cannot change yourself", isinstance(d, dict) and d.get("code") == "42501", (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_list_users", {"p_search": "zz-live-"}, tok=SA)
    sup_row = [r for r in (d or []) if r.get("is_admin")] if isinstance(d, list) else []
    if sup_row:
        target_admin = next(r["id"] for r in sup_row if r["id"] != sa_id)
        s, d = req("POST", "/rest/v1/rpc/admin_set_user_status", {"p_user": target_admin, "p_status": "banned"}, tok=SA)
        check("admin accounts can't be banned here (Admins page)", isinstance(d, dict) and d.get("code") == "42501", (s, d))
    s, d = req("POST", "/rest/v1/rpc/admin_set_user_status", {"p_user": APP, "p_status": "deleted"}, tok=SA)
    check("unknown status rejected", isinstance(d, dict) and d.get("code") == "22023", (s, d))

    # App user can still edit only their own allowed profile fields.
    s, d = req("PATCH", f"/rest/v1/profiles?id=eq.{APP}", {"status": "active"}, tok=app_tok, headers={"Prefer": "return=representation"})
    check("app user cannot set their own status", s >= 400, (s, d))
finally:
    cleanup()
