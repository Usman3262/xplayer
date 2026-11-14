"use client";

import { Copy, UserPlus } from "lucide-react";
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

import { addAdmin, changeRole, removeAdmin, setAdminActive } from "./actions";

export type RoleOption = { key: string; name: string };

const selectCls =
  "bg-secondary/70 focus:ring-primary/40 h-10 rounded-full px-4 text-sm outline-none focus:ring-2 disabled:opacity-50";

export function AddAdminDialog({ roles }: { roles: RoleOption[] }) {
  const [open, setOpen] = useState(false);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<{ email: string; password: string } | null>(null);

  const reset = () => {
    setError(null);
    setCreated(null);
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (!o) reset();
      }}
    >
      <DialogTrigger render={<Button className="rounded-full" />}>
        <UserPlus /> Add admin
      </DialogTrigger>
      <DialogContent className="rounded-3xl sm:max-w-md">
        {created ? (
          <>
            <DialogHeader>
              <DialogTitle>Account created</DialogTitle>
              <DialogDescription>
                Share this temporary password with {created.email} privately. It is shown only once.
              </DialogDescription>
            </DialogHeader>
            <div className="bg-secondary/70 flex items-center gap-2 rounded-2xl p-3 font-mono text-sm">
              <span className="flex-1 break-all">{created.password}</span>
              <Button
                size="icon"
                variant="ghost"
                aria-label="Copy password"
                onClick={() => {
                  void navigator.clipboard.writeText(created.password);
                  toast.success("Copied");
                }}
              >
                <Copy />
              </Button>
            </div>
            <DialogFooter>
              <Button className="rounded-full" onClick={() => setOpen(false)}>
                Done
              </Button>
            </DialogFooter>
          </>
        ) : (
          <form
            className="space-y-5"
            onSubmit={(e) => {
              e.preventDefault();
              const fd = new FormData(e.currentTarget);
              setError(null);
              start(async () => {
                const res = await addAdmin({ email: String(fd.get("email") ?? ""), role: String(fd.get("role") ?? "") });
                if (!res.ok) {
                  setError(res.error);
                  return;
                }
                if (res.data?.tempPassword) {
                  setCreated({ email: res.data.email, password: res.data.tempPassword });
                } else {
                  toast.success(`${res.data?.email} is now an admin`);
                  setOpen(false);
                }
              });
            }}
          >
            <DialogHeader>
              <DialogTitle>Add admin</DialogTitle>
              <DialogDescription>
                An existing account gets the role. For a new email an account is created with a temporary password.
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-2">
              <Label htmlFor="admin-email">Email</Label>
              <Input id="admin-email" name="email" type="email" required autoFocus />
            </div>
            <div className="space-y-2">
              <Label htmlFor="admin-role">Role</Label>
              <select id="admin-role" name="role" defaultValue="content_manager" className={`${selectCls} w-full`}>
                {roles.map((r) => (
                  <option key={r.key} value={r.key}>
                    {r.name}
                  </option>
                ))}
              </select>
            </div>
            {error ? (
              <p role="alert" className="text-destructive text-sm">
                {error}
              </p>
            ) : null}
            <DialogFooter>
              <Button type="submit" className="rounded-full" disabled={pending}>
                {pending ? "Adding…" : "Add admin"}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}

export function RoleSelect({ userId, value, roles, disabled }: { userId: string; value: string; roles: RoleOption[]; disabled?: boolean }) {
  const [pending, start] = useTransition();
  const [current, setCurrent] = useState(value);
  return (
    <select
      aria-label="Role"
      value={current}
      disabled={disabled || pending}
      className={selectCls}
      onChange={(e) => {
        const next = e.target.value;
        const prev = current;
        setCurrent(next);
        start(async () => {
          const res = await changeRole(userId, next);
          if (res.ok) toast.success("Role updated");
          else {
            setCurrent(prev);
            toast.error(res.error);
          }
        });
      }}
    >
      {roles.map((r) => (
        <option key={r.key} value={r.key}>
          {r.name}
        </option>
      ))}
    </select>
  );
}

export function AdminRowActions({ userId, email, active }: { userId: string; email: string; active: boolean }) {
  const [pending, start] = useTransition();
  return (
    <div className="flex justify-end gap-2">
      <Button
        size="sm"
        variant="outline"
        className="rounded-full"
        disabled={pending}
        onClick={() =>
          start(async () => {
            const res = await setAdminActive(userId, !active);
            if (res.ok) toast.success(active ? `${email} deactivated` : `${email} reactivated`);
            else toast.error(res.error);
          })
        }
      >
        {active ? "Deactivate" : "Activate"}
      </Button>
      <Button
        size="sm"
        variant="ghost"
        className="text-destructive hover:text-destructive rounded-full"
        disabled={pending}
        onClick={() => {
          if (!window.confirm(`Remove admin access for ${email}? Their account stays.`)) return;
          start(async () => {
            const res = await removeAdmin(userId);
            if (res.ok) toast.success(`${email} is no longer an admin`);
            else toast.error(res.error);
          });
        }}
      >
        Remove
      </Button>
    </div>
  );
}
