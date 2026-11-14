/**
 * Turn a Supabase/Postgres error into a message safe to show admins.
 * DB rule messages (P0001) and check-constraint/validation errors are written for
 * people; anything else stays generic (no internals leaked).
 */
export function dbMessage(error: { code?: string; message?: string } | null | undefined): string {
  if (!error) return "Something went wrong. Please try again.";
  if (error.code === "42501") return "You don't have permission for this.";
  if (error.code === "P0001" && error.message) return error.message;
  if (error.code === "23514") return "One of the values isn't allowed. Check the form.";
  if (error.code === "23505") return "That already exists.";
  if (error.code === "23503") return "This is still used somewhere else.";
  // validate_app_setting() raises plain exceptions with readable text.
  if (error.code === "P0001" || (error.message && /^setting /.test(error.message))) return error.message ?? "Invalid value.";
  return "Something went wrong. Please try again.";
}
