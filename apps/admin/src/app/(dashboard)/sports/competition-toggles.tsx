"use client";

import { useTransition } from "react";
import { toast } from "sonner";

import { Switch } from "@/components/ui/switch";

import { setCompetitionFlag } from "./actions";

export function CompetitionToggle({ id, field, value, label, disabled }: { id: string; field: "is_enabled" | "is_featured"; value: boolean; label: string; disabled: boolean }) {
  const [pending, start] = useTransition();
  return (
    <Switch
      checked={value}
      disabled={disabled || pending}
      aria-label={label}
      onCheckedChange={(v) =>
        start(async () => {
          const res = await setCompetitionFlag(id, field, v);
          if (res.ok) toast.success("Saved");
          else toast.error(res.error);
        })
      }
    />
  );
}
