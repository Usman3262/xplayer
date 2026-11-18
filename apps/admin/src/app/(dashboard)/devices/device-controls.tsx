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

import { revokeDevice } from "./actions";

/** "Sign out" for one device (rendered only for devices.write). */
export function RevokeDeviceButton({ userId, deviceId, label }: { userId: string; deviceId: string; label: string }) {
  const [open, setOpen] = useState(false);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (!o) setError(null);
      }}
    >
      <DialogTrigger render={<Button size="sm" variant="ghost" className="text-destructive hover:text-destructive rounded-full" />}>
        Sign out
      </DialogTrigger>
      <DialogContent className="rounded-3xl sm:max-w-md">
        <form
          className="space-y-5"
          onSubmit={(e) => {
            e.preventDefault();
            const reason = String(new FormData(e.currentTarget).get("reason") ?? "");
            setError(null);
            start(async () => {
              const res = await revokeDevice({ userId, deviceId, reason });
              if (!res.ok) {
                setError(res.error);
                return;
              }
              toast.success(`${label} will be signed out`);
              setOpen(false);
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>Sign out {label}?</DialogTitle>
            <DialogDescription>
              The app on this device signs out of the account the next time it opens. The panels and the library on the
              device are not touched, and the user can sign in again.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="reason">Reason (kept in the audit log)</Label>
            <Input id="reason" name="reason" maxLength={500} placeholder="Optional" className="rounded-xl" />
          </div>
          {error ? <p className="text-destructive text-sm">{error}</p> : null}
          <DialogFooter>
            <Button type="submit" variant="destructive" disabled={pending} className="rounded-full">
              {pending ? "Signing out…" : "Sign out device"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
