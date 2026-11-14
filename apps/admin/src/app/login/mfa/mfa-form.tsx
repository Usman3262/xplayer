"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

import { signOut } from "../actions";

function safeNext(next: string | null): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return "/";
  return next;
}

/** Second step of sign-in: 6-digit code from the authenticator app. */
export function MfaForm() {
  const router = useRouter();
  const next = safeNext(useSearchParams().get("next"));
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <form
      className="space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        const code = String(new FormData(e.currentTarget).get("code") ?? "").replace(/\s/g, "");
        setError(null);
        start(async () => {
          const supabase = createClient();
          const { data: factors, error: listError } = await supabase.auth.mfa.listFactors();
          const factor = factors?.totp.find((f) => f.status === "verified");
          if (listError || !factor) {
            setError("No authenticator found for this account. Sign in again.");
            return;
          }
          const { error: verifyError } = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code });
          if (verifyError) {
            setError("That code didn't work. Check the time on your phone and try the newest code.");
            return;
          }
          router.replace(next);
          router.refresh();
        });
      }}
    >
      <div className="space-y-2">
        <Label htmlFor="code">6-digit code</Label>
        <Input
          id="code"
          name="code"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9 ]{6,7}"
          maxLength={7}
          required
          autoFocus
          className="text-center text-lg tracking-[0.4em]"
        />
      </div>
      {error ? (
        <p role="alert" className="text-destructive text-sm">
          {error}
        </p>
      ) : null}
      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? "Checking…" : "Verify"}
      </Button>
      <button type="button" onClick={() => void signOut()} className="text-muted-foreground hover:text-foreground w-full text-sm">
        Use a different account
      </button>
    </form>
  );
}
