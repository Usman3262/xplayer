"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

import { setUserStatus } from "./actions";

type Status = "active" | "suspended" | "banned";

const LABEL: Record<Status, string> = { active: "Re-activate", suspended: "Suspend", banned: "Ban" };
const HELP: Record<Status, string> = {
  active: "They can sign in again. Their data was kept.",
  suspended: "They are signed out and can't sign in until you re-activate them. Their panels on their devices are not touched.",
  banned: "Like suspend, for abuse. They can't sign in again until an admin re-activates them.",
};

/** Status buttons for one app user (only rendered for users.write). */
export function UserStatusActions({ userId, email, status }: { userId: string; email: string; status: Status }) {
  const next: Status[] = status === "active" ? ["suspended", "banned"] : ["active"];
  return (
    <div className="flex justify-end gap-2">
      {next.map((s) => (
        <StatusDialog key={s} userId={userId} email={email} target={s} />
      ))}
    </div>
  );
}

function StatusDialog({ userId, email, target }: { userId: string; email: string; target: Status }) {
  const [open, setOpen] = useState(false);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const danger = target !== "active";

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (!o) setError(null);
      }}
    >
      <DialogTrigger
        render={
          <Button
            size="sm"
            variant={danger ? "ghost" : "outline"}
            className={danger ? "text-destructive hover:text-destructive rounded-full" : "rounded-full"}
          />
        }
      >
        {LABEL[target]}
      </DialogTrigger>
      <DialogContent className="rounded-3xl sm:max-w-md">
        <form
          className="space-y-5"
          onSubmit={(e) => {
            e.preventDefault();
            const reason = String(new FormData(e.currentTarget).get("reason") ?? "");
            setError(null);
            start(async () => {
              const res = await setUserStatus({ userId, status: target, reason });
              if (!res.ok) {
                setError(res.error);
                return;
              }
              toast.success(target === "active" ? `${email} re-activated` : `${email} ${target}`);
              setOpen(false);
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>
              {LABEL[target]} {email}?
            </DialogTitle>
            <DialogDescription>{HELP[target]}</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor={`reason-${userId}-${target}`}>Reason (saved in the audit log)</Label>
            <Input id={`reason-${userId}-${target}`} name="reason" maxLength={500} autoFocus />
          </div>
          {error ? (
            <p role="alert" className="text-destructive text-sm">
              {error}
            </p>
          ) : null}
          <DialogFooter>
            <Button type="submit" variant={danger ? "destructive" : "default"} className="rounded-full" disabled={pending}>
              {pending ? "Saving…" : LABEL[target]}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
