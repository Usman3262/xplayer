"""Live checks for 8.1 user_library (RLS + newest-wins RPCs).
Two temporary plain users; deleted afterwards. Run from apps/admin:
  PYTHONIOENCODING=utf-8 python supabase/tests/live_library_check.py"""
import sys
sys.path.insert(0, "supabase/tests")
from _live import req, temp_admin, check, cleanup

try:
    a_id, A = temp_admin(None, mfa=False)
    b_id, B = temp_admin(None, mfa=False)
    P = "xtream:panel.example"
    item = {"id": "101", "kind": "movie", "title": "Dune", "my_list": True, "progress": 0.4, "pos": 600, "dur": 1500,
            "at": "2026-11-10T10:00:00Z"}

    s, d = req("POST", "/rest/v1/rpc/library_push", {"p_panel": P, "p_items": [item]})
    check("anon cannot push", s in (401, 403, 404), (s, d))
    s, d = req("POST", "/rest/v1/rpc/library_push", {"p_panel": P, "p_items": [item]}, tok=A)
    check("user A pushes 1 row", s == 200 and d == 1, (s, d))
    s, d = req("POST", "/rest/v1/rpc/library_pull", {"p_panel": P}, tok=A)
    check("A pulls own row", s == 200 and len(d) == 1 and d[0]["title"] == "Dune" and d[0]["pos"] == 600, (s, d))
    s, d = req("POST", "/rest/v1/rpc/library_pull", {"p_panel": P}, tok=B)
    check("B sees nothing of A", s == 200 and d == [], (s, d))
    s, d = req("GET", "/rest/v1/user_library?select=item_id", tok=B)
    check("B table read: no A rows", s == 200 and d == [], (s, d))
    s, d = req("POST", "/rest/v1/user_library", {"user_id": a_id, "panel_key": P, "item_id": "x", "kind": "movie",
                                                 "changed_at": "2026-11-10T10:00:00Z"}, tok=B)
    check("B cannot write a row for A", s in (401, 403), (s, d))

    older = dict(item, title="Old name", progress=0.1, at="2026-11-10T09:00:00Z")
    s, d = req("POST", "/rest/v1/rpc/library_push", {"p_panel": P, "p_items": [older]}, tok=A)
    check("older change ignored (newest wins)", s == 200 and d == 0, (s, d))
    newer = dict(item, title="", progress=0.9, at="2026-11-10T11:00:00Z")
    s, d = req("POST", "/rest/v1/rpc/library_push", {"p_panel": P, "p_items": [newer]}, tok=A)
    s, d = req("POST", "/rest/v1/rpc/library_pull", {"p_panel": P}, tok=A)
    check("newer change applied, empty title keeps the name", d and abs(d[0]["progress"] - 0.9) < 1e-6 and d[0]["title"] == "Dune", d)
    s, d = req("POST", "/rest/v1/rpc/library_pull", {"p_panel": P, "p_since": "2026-11-10T12:00:00Z"}, tok=A)
    check("pull since: only newer rows", s == 200 and d == [], (s, d))
    s, d = req("POST", "/rest/v1/rpc/library_push", {"p_panel": P, "p_items": [item] * 301}, tok=A)
    check("batch over 300 refused", s == 400, (s, d))
finally:
    cleanup()
