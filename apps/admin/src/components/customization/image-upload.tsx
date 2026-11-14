"use client";

import { ImagePlus, Loader2, X } from "lucide-react";
import { useRef, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import { cn } from "@/lib/utils";

const BUCKET = "app-assets";
const TYPES: Record<string, string> = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp" };
const MAX_BYTES = 2 * 1024 * 1024;

/**
 * Upload an image to Storage (bucket `app-assets`) straight from the browser with
 * the admin's session. The bucket enforces type/size and only customization.write
 * admins may write (RLS). Calls onChange with the public URL.
 */
export function ImageUpload({
  value,
  onChange,
  folder,
  aspect = "aspect-video",
  label = "Upload image",
}: {
  value: string | null;
  onChange: (url: string | null) => void;
  folder: string;
  aspect?: string;
  label?: string;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);

  async function upload(file: File) {
    const ext = TYPES[file.type];
    if (!ext) return toast.error("Use a PNG, JPG or WebP image.");
    if (file.size > MAX_BYTES) return toast.error("Image is larger than 2 MB.");
    setBusy(true);
    try {
      const supabase = createClient();
      const path = `${folder}/${crypto.randomUUID()}.${ext}`;
      const { error } = await supabase.storage.from(BUCKET).upload(path, file, {
        contentType: file.type,
        cacheControl: "31536000",
        upsert: false,
      });
      if (error) throw error;
      onChange(supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl);
    } catch {
      toast.error("Upload failed. Check the file and try again.");
    } finally {
      setBusy(false);
      if (input.current) input.current.value = "";
    }
  }

  return (
    <div className={cn("bg-secondary/50 relative overflow-hidden rounded-2xl border border-dashed", aspect)}>
      {value ? (
        <>
          {/* eslint-disable-next-line @next/next/no-img-element -- admin preview of a Storage URL */}
          <img src={value} alt="" className="size-full object-cover" />
          <Button
            type="button"
            size="icon"
            variant="secondary"
            className="absolute top-2 right-2 rounded-full"
            aria-label="Remove image"
            onClick={() => onChange(null)}
          >
            <X />
          </Button>
        </>
      ) : (
        <button
          type="button"
          onClick={() => input.current?.click()}
          disabled={busy}
          className="text-muted-foreground hover:text-foreground flex size-full flex-col items-center justify-center gap-2 text-sm"
        >
          {busy ? <Loader2 className="size-6 animate-spin" /> : <ImagePlus className="size-6" />}
          {busy ? "Uploading…" : label}
          <span className="text-xs">PNG, JPG or WebP · max 2 MB</span>
        </button>
      )}
      <input
        ref={input}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        className="hidden"
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) void upload(f);
        }}
      />
    </div>
  );
}
