"use client";

import { Send } from "lucide-react";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import { publishConfig } from "@/app/(dashboard)/customization/actions";
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

export function PublishButton({ dirty }: { dirty: boolean }) {
  const [open, setOpen] = useState(false);
  const [pending, start] = useTransition();
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button className="rounded-full" disabled={!dirty} />}>
        <Send /> Publish
      </DialogTrigger>
      <DialogContent className="rounded-3xl sm:max-w-md">
        <form
          className="space-y-5"
          onSubmit={(e) => {
            e.preventDefault();
            const notes = String(new FormData(e.currentTarget).get("notes") ?? "");
            start(async () => {
              const res = await publishConfig(notes);
              if (res.ok) {
                toast.success(`Published version ${res.data?.version}. Apps pick it up on their next check.`);
                setOpen(false);
              } else toast.error(res.error);
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>Publish to the apps</DialogTitle>
            <DialogDescription>
              Phones and TVs load the new settings the next time they check (on start and every few minutes).
            </DialogDescription>
          </DialogHeader>
          <Input name="notes" maxLength={200} placeholder="What changed? (optional)" autoFocus />
          <DialogFooter>
            <Button type="submit" className="rounded-full" disabled={pending}>
              {pending ? "Publishing…" : "Publish now"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
