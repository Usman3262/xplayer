/** Shape of `admin_dashboard_stats()` (see migration 012). */
export type DashboardStats = {
  users: { total: number; guests: number; new_7d: number; active_7d: number; suspended: number; admins: number };
  signups_weekly: { week: string; count: number }[];
  config: { version: number; published_at: string; notes: string | null } | null;
  customization: { sections: number; banners: number; flags_on: number; flags_total: number; panel_types: number; maintenance_now: boolean };
  catalog: { movies: number; series: number; episodes: number; channels: number; misses_7d: number };
  sports: { live: number; today: number; upcoming: number };
  recent_activity: { id: number; action: string; entity: string; entity_id: string | null; created_at: string; actor_email: string | null }[] | null;
};
