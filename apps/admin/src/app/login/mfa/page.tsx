import { Suspense } from "react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

import { MfaForm } from "./mfa-form";

export const metadata = { title: "Two-factor code" };

export default function MfaPage() {
  return (
    <main className="flex flex-1 items-center justify-center p-6">
      <Card className="w-full max-w-sm rounded-3xl">
        <CardHeader>
          <CardTitle className="text-xl">Two-factor sign-in</CardTitle>
          <CardDescription>Enter the code from your authenticator app.</CardDescription>
        </CardHeader>
        <CardContent>
          <Suspense fallback={<div className="h-40" />}>
            <MfaForm />
          </Suspense>
        </CardContent>
      </Card>
    </main>
  );
}
