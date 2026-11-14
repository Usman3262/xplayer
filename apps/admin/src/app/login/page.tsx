export const metadata = { title: "Sign in" };

/** Placeholder: real admin sign-in (email/password + MFA) arrives in step 2.1. */
export default function LoginPage() {
  return (
    <main className="flex flex-1 items-center justify-center p-8">
      <div className="space-y-2 text-center">
        <h1 className="text-2xl font-semibold">Sign in</h1>
        <p className="text-muted-foreground text-sm">
          Admin sign-in is built in step 2.1.
        </p>
      </div>
    </main>
  );
}
