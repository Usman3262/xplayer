"use client";

import { Pencil, Plus, Trash2 } from "lucide-react";
import { useId, useState, useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { toLocalInput } from "@/lib/dates";

import { deleteMatch, saveMatch, type MatchInput } from "./actions";

export type MatchRow = {
  id: string;
  kickoff_at: string;
  status: MatchInput["status"];
  minute: number | null;
  home_score: number | null;
  away_score: number | null;
  round: string | null;
  venue: string | null;
  is_featured: boolean;
  is_hidden: boolean;
  competition: { name: string } | null;
  home: { id: string; name: string };
  away: { id: string; name: string };
  sports_match_channels: { channel_match: string | null }[];
  sports_lineups: { team_id: string; formation: string | null; players: { name: string; number?: number; position?: string; starter?: boolean }[] }[];
  sports_events: { minute: number; extra_minute: number | null; type: string; team_id: string | null; player: string | null; assist: string | null }[];
};

const STATUS = { scheduled: "Scheduled", live: "Live", halftime: "Half-time", finished: "Finished", postponed: "Postponed", cancelled: "Cancelled", suspended: "Suspended" } as const;
const selectCls = "bg-secondary/70 focus:ring-primary/40 h-10 w-full rounded-full px-4 text-sm outline-none focus:ring-2";

function lineupText(players: MatchRow["sports_lineups"][number]["players"] = []) {
  const line = (p: (typeof players)[number]) => [p.number, p.name, p.position].filter(Boolean).join(" ");
  const starters = players.filter((p) => p.starter !== false).map(line);
  const bench = players.filter((p) => p.starter === false).map(line);
  return [...starters, ...(bench.length ? ["subs", ...bench] : [])].join("\n");
}

function draftOf(r: MatchRow | null): MatchInput {
  const lu = (teamId?: string) => r?.sports_lineups.find((l) => l.team_id === teamId);
  return {
    competition: r?.competition?.name ?? "",
    home: r?.home.name ?? "",
    away: r?.away.name ?? "",
    kickoff_at: toLocalInput(r?.kickoff_at),
    status: r?.status ?? "scheduled",
    minute: r?.minute ?? null,
    home_score: r?.home_score ?? null,
    away_score: r?.away_score ?? null,
    round: r?.round ?? "",
    venue: r?.venue ?? "",
    is_featured: r?.is_featured ?? false,
    is_hidden: r?.is_hidden ?? false,
    channels: (r?.sports_match_channels ?? []).map((c) => c.channel_match).filter(Boolean).join("\n"),
    home_formation: lu(r?.home.id)?.formation ?? "",
    away_formation: lu(r?.away.id)?.formation ?? "",
    home_lineup: lineupText(lu(r?.home.id)?.players),
    away_lineup: lineupText(lu(r?.away.id)?.players),
    events: (r?.sports_events ?? [])
      .map((e) => {
        const side = e.team_id === r?.home.id ? "home" : e.team_id === r?.away.id ? "away" : "";
        return [`${e.minute}${e.extra_minute ? `+${e.extra_minute}` : ""}`, e.type, side, e.player ?? "", e.assist ? `(${e.assist})` : ""].filter(Boolean).join(" ");
      })
      .join("\n"),
  };
}

export function NewMatchButton({ teams, competitions }: { teams: string[]; competitions: string[] }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <Button className="rounded-full" onClick={() => setOpen(true)}>
        <Plus /> Add match
      </Button>
      {open ? <MatchDialog row={null} teams={teams} competitions={competitions} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

export function MatchRowActions({ row, teams, competitions }: { row: MatchRow; teams: string[]; competitions: string[] }) {
  const [open, setOpen] = useState(false);
  const [pending, start] = useTransition();
  return (
    <span className="flex justify-end gap-1">
      <Button size="icon" variant="ghost" className="rounded-full" aria-label={`Edit ${row.home.name} vs ${row.away.name}`} onClick={() => setOpen(true)}>
        <Pencil />
      </Button>
      <Button
        size="icon"
        variant="ghost"
        className="text-destructive hover:text-destructive rounded-full"
        aria-label={`Delete ${row.home.name} vs ${row.away.name}`}
        disabled={pending}
        onClick={() =>
          window.confirm(`Delete ${row.home.name} vs ${row.away.name}?`) &&
          start(async () => {
            const res = await deleteMatch(row.id);
            if (res.ok) toast.success("Match deleted");
            else toast.error(res.error);
          })
        }
      >
        <Trash2 />
      </Button>
      {open ? <MatchDialog row={row} teams={teams} competitions={competitions} onClose={() => setOpen(false)} /> : null}
    </span>
  );
}

function MatchDialog({ row, teams, competitions, onClose }: { row: MatchRow | null; teams: string[]; competitions: string[]; onClose: () => void }) {
  const [d, setD] = useState<MatchInput>(draftOf(row));
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const teamList = useId();
  const compList = useId();
  const num = (v: string) => (v === "" ? null : Number(v));

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[92vh] overflow-y-auto rounded-3xl sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>{row ? "Edit match" : "Add match"}</DialogTitle>
          <DialogDescription>New team or competition names are created automatically. Changes show in the apps right away (no publish needed).</DialogDescription>
        </DialogHeader>
        <datalist id={teamList}>{teams.map((t) => <option key={t} value={t} />)}</datalist>
        <datalist id={compList}>{competitions.map((c) => <option key={c} value={c} />)}</datalist>

        <div className="grid gap-4 sm:grid-cols-3">
          <div className="space-y-2">
            <Label>Home team *</Label>
            <Input list={teamList} value={d.home} maxLength={80} onChange={(e) => setD({ ...d, home: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>Away team *</Label>
            <Input list={teamList} value={d.away} maxLength={80} onChange={(e) => setD({ ...d, away: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>Competition</Label>
            <Input list={compList} value={d.competition} maxLength={80} placeholder="e.g. Premier League" onChange={(e) => setD({ ...d, competition: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>Kickoff *</Label>
            <Input type="datetime-local" value={d.kickoff_at} onChange={(e) => setD({ ...d, kickoff_at: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>Status</Label>
            <select className={selectCls} value={d.status} onChange={(e) => setD({ ...d, status: e.target.value as MatchInput["status"] })}>
              {Object.entries(STATUS).map(([k, l]) => (
                <option key={k} value={k}>
                  {l}
                </option>
              ))}
            </select>
          </div>
          <div className="grid grid-cols-3 gap-2">
            <div className="space-y-2">
              <Label className="text-xs">Home</Label>
              <Input type="number" min={0} value={d.home_score ?? ""} disabled={d.status === "scheduled"} onChange={(e) => setD({ ...d, home_score: num(e.target.value) })} />
            </div>
            <div className="space-y-2">
              <Label className="text-xs">Away</Label>
              <Input type="number" min={0} value={d.away_score ?? ""} disabled={d.status === "scheduled"} onChange={(e) => setD({ ...d, away_score: num(e.target.value) })} />
            </div>
            <div className="space-y-2">
              <Label className="text-xs">Min.</Label>
              <Input type="number" min={0} max={200} value={d.minute ?? ""} disabled={d.status !== "live"} onChange={(e) => setD({ ...d, minute: num(e.target.value) })} />
            </div>
          </div>
          <div className="space-y-2">
            <Label>Round</Label>
            <Input value={d.round} maxLength={60} placeholder="e.g. Matchday 12" onChange={(e) => setD({ ...d, round: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>Venue</Label>
            <Input value={d.venue} maxLength={120} onChange={(e) => setD({ ...d, venue: e.target.value })} />
          </div>
          <div className="flex items-end gap-4">
            <label className="flex items-center gap-2 text-sm">
              <Switch checked={d.is_featured} onCheckedChange={(v) => setD({ ...d, is_featured: v })} /> Featured
            </label>
            <label className="flex items-center gap-2 text-sm">
              <Switch checked={d.is_hidden} onCheckedChange={(v) => setD({ ...d, is_hidden: v })} /> Hidden
            </label>
          </div>
        </div>

        <div className="space-y-2">
          <Label>Where to watch</Label>
          <Textarea rows={2} value={d.channels} placeholder={"One channel name per line, e.g.\nbeIN Sports 1"} onChange={(e) => setD({ ...d, channels: e.target.value })} />
          <p className="text-muted-foreground text-xs">Matched against channel names in each user&apos;s panel.</p>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          {(["home", "away"] as const).map((side) => (
            <div key={side} className="space-y-2">
              <div className="flex items-center gap-2">
                <Label className="flex-1">{side === "home" ? d.home || "Home" : d.away || "Away"} lineup</Label>
                <Input
                  className="h-8 w-24 text-xs"
                  placeholder="4-3-3"
                  value={side === "home" ? d.home_formation : d.away_formation}
                  onChange={(e) => setD(side === "home" ? { ...d, home_formation: e.target.value } : { ...d, away_formation: e.target.value })}
                />
              </div>
              <Textarea
                rows={7}
                className="font-mono text-xs"
                placeholder={"1 Alisson GK\n4 Van Dijk DF\n11 Salah FW\nsubs\n18 Gakpo FW"}
                value={side === "home" ? d.home_lineup : d.away_lineup}
                onChange={(e) => setD(side === "home" ? { ...d, home_lineup: e.target.value } : { ...d, away_lineup: e.target.value })}
              />
            </div>
          ))}
        </div>
        <div className="space-y-2">
          <Label>Events</Label>
          <Textarea rows={4} className="font-mono text-xs" placeholder={"12 goal home Salah (Szoboszlai)\n45+2 yellow away Rice\n67 substitution home Gakpo"} value={d.events} onChange={(e) => setD({ ...d, events: e.target.value })} />
          <p className="text-muted-foreground text-xs">minute[+extra] type home|away player (assist). Types: goal, own_goal, penalty_goal, penalty_miss, yellow, red, substitution, var, other.</p>
        </div>

        {error ? (
          <p role="alert" className="text-destructive text-sm">
            {error}
          </p>
        ) : null}
        <DialogFooter>
          <Button
            className="rounded-full"
            disabled={pending}
            onClick={() =>
              start(async () => {
                setError(null);
                const res = await saveMatch(row?.id ?? null, d);
                if (res.ok) {
                  toast.success("Match saved");
                  onClose();
                } else setError(res.error);
              })
            }
          >
            {pending ? "Saving…" : "Save match"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
