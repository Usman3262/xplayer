import { Star } from "lucide-react";
import { Suspense } from "react";

import { DataTable, type Column } from "@/components/data-table/data-table";
import { TableToolbar } from "@/components/data-table/toolbar";
import { PageHeader } from "@/components/layout/page-header";
import { CardsSkeleton, ErrorState } from "@/components/states";
import { Badge } from "@/components/ui/badge";
import { requirePermission } from "@/lib/auth";
import { fmtDateTime } from "@/lib/dates";
import { createClient } from "@/lib/supabase/server";
import { parseTableParams, type SearchParamsRecord } from "@/lib/table-params";
import { cn } from "@/lib/utils";

import { CompetitionToggle } from "./competition-toggles";
import { MatchRowActions, NewMatchButton, type MatchRow } from "./match-dialog";

export const metadata = { title: "Sports" };

export default function SportsPage({ searchParams }: PageProps<"/sports">) {
  return (
    <>
      <PageHeader title="Sports" description="Matches, scores, lineups and where to watch. Saved changes show in the apps right away." />
      <Suspense fallback={<CardsSkeleton count={4} />}>
        <SportsContent searchParams={searchParams} />
      </Suspense>
    </>
  );
}

function windowRange(w: string | undefined): { from?: string; to?: string; statuses?: string[] } {
  const now = new Date();
  const day = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  switch (w) {
    case "live":
      return { statuses: ["live", "halftime"] };
    case "today":
      return { from: day.toISOString(), to: new Date(day.getTime() + 864e5).toISOString() };
    case "upcoming":
      return { from: now.toISOString(), statuses: ["scheduled"] };
    case "recent":
      return { from: new Date(now.getTime() - 7 * 864e5).toISOString(), to: now.toISOString() };
    default:
      return {};
  }
}

const STATUS_TONE: Record<string, string> = {
  live: "bg-primary text-primary-foreground",
  halftime: "bg-primary/20 text-primary",
  finished: "bg-secondary text-muted-foreground",
  scheduled: "bg-secondary text-foreground",
};

async function SportsContent({ searchParams }: { searchParams: Promise<SearchParamsRecord> }) {
  const admin = await requirePermission("sports.read", "/sports");
  const canWrite = admin.can("sports.write");
  const sp = await searchParams;
  const { page, pageSize, q, filters } = parseTableParams(sp, { filterKeys: ["window"], defaultPageSize: 25 });
  const supabase = await createClient();

  const range = windowRange(filters.window);
  let query = supabase
    .from("sports_matches")
    .select(
      "id,kickoff_at,status,minute,home_score,away_score,round,venue,is_featured,is_hidden," +
        "competition:sports_competitions(name),home:sports_teams!sports_matches_home_team_id_fkey(id,name),away:sports_teams!sports_matches_away_team_id_fkey(id,name)," +
        "sports_match_channels(channel_match),sports_lineups(team_id,formation,players),sports_events(minute,extra_minute,type,team_id,player,assist)",
    )
    .order("kickoff_at", { ascending: filters.window === "upcoming" || filters.window === "today" })
    .range((page - 1) * pageSize, page * pageSize);
  if (range.from) query = query.gte("kickoff_at", range.from);
  if (range.to) query = query.lt("kickoff_at", range.to);
  if (range.statuses) query = query.in("status", range.statuses);

  let teamIds: string[] | null = null;
  if (q) {
    const { data: t } = await supabase.from("sports_teams").select("id").ilike("name", `%${q.replace(/[%_]/g, "")}%`).limit(50);
    teamIds = (t ?? []).map((x) => x.id);
    if (teamIds.length === 0) teamIds = ["00000000-0000-0000-0000-000000000000"];
    query = query.or(`home_team_id.in.(${teamIds.join(",")}),away_team_id.in.(${teamIds.join(",")})`);
  }

  const [matches, teams, comps] = await Promise.all([
    query,
    supabase.from("sports_teams").select("name").order("name").limit(500),
    supabase.from("sports_competitions").select("id,name,country,is_enabled,is_featured").order("sort_order").order("name"),
  ]);
  if (matches.error || teams.error || comps.error) return <ErrorState description="Sports data could not be loaded." />;

  const all = (matches.data ?? []) as unknown as MatchRow[];
  const rows = all.slice(0, pageSize);
  const teamNames = (teams.data ?? []).map((t) => t.name);
  const compNames = (comps.data ?? []).map((c) => c.name);

  const columns: Column<MatchRow>[] = [
    { key: "when", header: "Kickoff", className: "w-44 whitespace-nowrap", cell: (r) => <span className="text-sm tabular-nums">{fmtDateTime(r.kickoff_at)}</span> },
    {
      key: "match",
      header: "Match",
      cell: (r) => (
        <div className="min-w-0">
          <p className="flex items-center gap-2 text-sm font-medium">
            {r.is_featured ? <Star className="text-brand-gold size-3.5 fill-current" /> : null}
            {r.home.name} <span className="text-muted-foreground">vs</span> {r.away.name}
            {r.is_hidden ? <Badge className="bg-secondary text-muted-foreground rounded-full font-normal">hidden</Badge> : null}
          </p>
          <p className="text-muted-foreground truncate text-xs">
            {[r.competition?.name, r.round, r.sports_match_channels.length ? `📺 ${r.sports_match_channels.map((c) => c.channel_match).join(", ")}` : null].filter(Boolean).join(" · ")}
          </p>
        </div>
      ),
    },
    {
      key: "score",
      header: "Score",
      className: "w-40",
      cell: (r) => (
        <span className="flex items-center gap-2">
          <Badge className={cn("rounded-full", STATUS_TONE[r.status] ?? "bg-secondary text-muted-foreground")}>
            {r.status === "live" && r.minute != null ? `${r.minute}'` : r.status}
          </Badge>
          {r.home_score != null ? <span className="font-semibold tabular-nums">{r.home_score}–{r.away_score}</span> : null}
        </span>
      ),
    },
    ...(canWrite ? [{ key: "actions", header: "", className: "w-24", cell: (r: MatchRow) => <MatchRowActions row={r} teams={teamNames} competitions={compNames} /> }] : []),
  ];

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <TableToolbar
          searchPlaceholder="Search team"
          filters={[
            {
              key: "window",
              label: "Show",
              options: [
                { value: "live", label: "Live now" },
                { value: "today", label: "Today" },
                { value: "upcoming", label: "Upcoming" },
                { value: "recent", label: "Last 7 days" },
              ],
            },
          ]}
        />
        {canWrite ? <NewMatchButton teams={teamNames} competitions={compNames} /> : null}
      </div>
      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(r) => r.id}
        path="/sports"
        searchParams={sp}
        page={page}
        pageSize={pageSize}
        hasNext={all.length > pageSize}
        emptyTitle="No matches"
        emptyDescription="Add matches by hand now; they'll be filled automatically once a sports data provider is connected."
      />

      <section className="bg-card/60 space-y-3 rounded-[28px] border p-6">
        <h2 className="font-semibold">Competitions</h2>
        {(comps.data ?? []).length === 0 ? (
          <p className="text-muted-foreground text-sm">Competitions appear here when you add a match with one.</p>
        ) : (
          <ul className="divide-y">
            {(comps.data ?? []).map((c) => (
              <li key={c.id} className="flex items-center gap-4 py-3 text-sm">
                <span className="flex-1 font-medium">{c.name}</span>
                <span className="text-muted-foreground flex items-center gap-2 text-xs">
                  Featured <CompetitionToggle id={c.id} field="is_featured" value={c.is_featured} label={`${c.name} featured`} disabled={!canWrite} />
                </span>
                <span className="text-muted-foreground flex items-center gap-2 text-xs">
                  Shown <CompetitionToggle id={c.id} field="is_enabled" value={c.is_enabled} label={`${c.name} shown`} disabled={!canWrite} />
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
