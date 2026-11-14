"use client";

import { RotateCcw } from "lucide-react";
import { useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";

import { rollbackTo } from "./actions";

export function RollbackButton({ version }: { version: number }) {
  const [pending, start] = useTransition();
  return (
    <Button
      variant="outline"
      className="rounded-full"
      disabled={pending}
      onClick={() => {
        if (!window.confirm(`Send version ${version} to the apps again? Your current drafts stay as they are (the publish bar will show the difference).`)) return;
        start(async () => {
          const res = await rollbackTo(version);
          if (res.ok) toast.success(`Rolled back: apps now get version ${version}'s settings (as v${res.data?.version}).`);
          else toast.error(res.error);
        });
      }}
    >
      <RotateCcw /> Roll back to this
    </Button>
  );
}
