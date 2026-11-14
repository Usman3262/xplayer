"use client";

import { ShieldCheck, ShieldOff } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

import { changePassword } from "./actions";

export function PasswordForm() {
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return (
    <form
      className="grid max-w-md gap-4"
      onSubmit={(e) => {
        e.preventDefault();
        const form = e.currentTarget;
        const fd = new FormData(form);
        setError(null);
        start(async () => {
          const res = await changePassword({
            current: String(fd.get("current") ?? ""),
            next: String(fd.get("next") ?? ""),
            confirm: String(fd.get("confirm") ?? ""),
          });
          if (res.ok) {
            form.reset();
            toast.success("Password changed");
          } else setError(res.error);
        });
      }}
    >
      <div className="space-y-2">
        <Label htmlFor="current">Current password</Label>
        <Input id="current" name="current" type="password" autoComplete="current-password" required />
      </div>
      <div className="space-y-2">
        <Label htmlFor="next">New password</Label>
        <Input id="next" name="next" type="password" autoComplete="new-password" minLength={12} required />
        <p className="text-muted-foreground text-xs">At least 12 characters.</p>
      </div>
      <div className="space-y-2">
        <Label htmlFor="confirm">Repeat new password</Label>
        <Input id="confirm" name="confirm" type="password" autoComplete="new-password" required />
      </div>
      {error ? (
        <p role="alert" className="text-destructive text-sm">
          {error}
        </p>
      ) : null}
      <Button type="submit" className="w-fit rounded-full" disabled={pending}>
        {pending ? "Saving…" : "Change password"}
      </Button>
    </form>
  );
}

type Enrollment = { factorId: string; qr: string; secret: string };

/** Turn the authenticator (TOTP) on or off. Runs in the browser with the user's session. */
export function TwoFactorSetup({ enabled, required }: { enabled: boolean; required: boolean }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [enroll, setEnroll] = useState<Enrollment | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (enabled) {
    return (
      <div className="flex flex-wrap items-center gap-4">
        <span className="flex items-center gap-2 text-sm text-emerald-400">
          <ShieldCheck className="size-5" /> Two-factor sign-in is on
        </span>
        {!required ? (
          <Button
            variant="ghost"
            className="text-destructive hover:text-destructive rounded-full"
            disabled={pending}
            onClick={() => {
              if (!window.confirm("Turn off two-factor sign-in? Your account will be less safe.")) return;
              start(async () => {
                const supabase = createClient();
                const { data } = await supabase.auth.mfa.listFactors();
                for (const f of data?.totp ?? []) await supabase.auth.mfa.unenroll({ factorId: f.id });
                toast.success("Two-factor sign-in turned off");
                router.refresh();
              });
            }}
          >
            Turn off
          </Button>
        ) : (
          <span className="text-muted-foreground text-xs">Required by your organisation.</span>
        )}
      </div>
    );
  }

  if (!enroll) {
    return (
      <div className="space-y-3">
        <p className="text-muted-foreground flex items-center gap-2 text-sm">
          <ShieldOff className="size-5" /> Off. Protect your admin account with an authenticator app (Google Authenticator, 1Password, Authy…).
        </p>
        {error ? <p className="text-destructive text-sm">{error}</p> : null}
        <Button
          className="rounded-full"
          disabled={pending}
          onClick={() =>
            start(async () => {
              setError(null);
              const supabase = createClient();
              // Remove half-finished enrollments first (Supabase allows only one pending).
              const { data: existing } = await supabase.auth.mfa.listFactors();
              for (const f of existing?.all ?? []) if (f.status !== "verified") await supabase.auth.mfa.unenroll({ factorId: f.id });
              const { data, error: e } = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: `admin-${Date.now()}` });
              if (e || !data) {
                setError("Could not start setup. Try again.");
                return;
              }
              setEnroll({ factorId: data.id, qr: data.totp.qr_code, secret: data.totp.secret });
            })
          }
        >
          Set up two-factor
        </Button>
      </div>
    );
  }

  return (
    <form
      className="grid max-w-md gap-4"
      onSubmit={(e) => {
        e.preventDefault();
        const code = String(new FormData(e.currentTarget).get("code") ?? "").replace(/\s/g, "");
        setError(null);
        start(async () => {
          const { error: e2 } = await createClient().auth.mfa.challengeAndVerify({ factorId: enroll.factorId, code });
          if (e2) {
            setError("That code didn't work. Try the newest code from the app.");
            return;
          }
          toast.success("Two-factor sign-in is on");
          setEnroll(null);
          router.refresh();
        });
      }}
    >
      <p className="text-sm">1. Scan this QR code with your authenticator app.</p>
      {/* eslint-disable-next-line @next/next/no-img-element -- data: URI from Supabase */}
      <img src={enroll.qr} alt="Authenticator QR code" className="size-44 rounded-2xl bg-white p-2" />
      <p className="text-muted-foreground text-xs">
        Can&apos;t scan? Enter this key: <span className="text-foreground font-mono break-all">{enroll.secret}</span>
      </p>
      <div className="space-y-2">
        <Label htmlFor="totp">2. Enter the 6-digit code</Label>
        <Input id="totp" name="code" inputMode="numeric" autoComplete="one-time-code" maxLength={7} required className="max-w-40 text-center tracking-[0.3em]" />
      </div>
      {error ? <p className="text-destructive text-sm">{error}</p> : null}
      <div className="flex gap-2">
        <Button type="submit" className="rounded-full" disabled={pending}>
          {pending ? "Checking…" : "Turn on"}
        </Button>
        <Button type="button" variant="ghost" className="rounded-full" onClick={() => setEnroll(null)}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
