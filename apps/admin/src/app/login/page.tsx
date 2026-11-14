import { Suspense } from "react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

import { LoginForm } from "./login-form";

export const metadata = { title: "Sign in" };

export default function LoginPage() {
  return (
    <main className="flex flex-1 items-center justify-center p-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-xl">Admin sign in</CardTitle>
          <CardDescription>Use your admin account.</CardDescription>
        </CardHeader>
        <CardContent>
          {/* useSearchParams (the ?next= target) needs a Suspense boundary. */}
          <Suspense fallback={<div className="h-48" />}>
            <LoginForm />
          </Suspense>
        </CardContent>
      </Card>
    </main>
  );
}
