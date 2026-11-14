import {
  Activity,
  BarChart3,
  Bell,
  Clapperboard,
  CreditCard,
  Flag,
  Gauge,
  Image as ImageIcon,
  KeyRound,
  LayoutDashboard,
  LayoutTemplate,
  LifeBuoy,
  ListOrdered,
  Megaphone,
  Monitor,
  Palette,
  ScrollText,
  Settings,
  ShieldCheck,
  Smartphone,
  Trophy,
  Tv,
  Users,
  type LucideIcon,
} from "lucide-react";

/**
 * Every admin module, grouped. One place to add a module:
 * add it here with its permission; `ready: false` shows it greyed with "Soon".
 * Items the admin lacks permission for are hidden (the server checks again).
 */
export type NavItem = {
  title: string;
  href: string;
  icon: LucideIcon;
  permission: string;
  ready: boolean;
};

export type NavGroup = { label: string; items: NavItem[] };

export const NAV: NavGroup[] = [
  {
    label: "Overview",
    items: [
      { title: "Dashboard", href: "/", icon: LayoutDashboard, permission: "dashboard.read", ready: true },
      { title: "Analytics", href: "/analytics", icon: BarChart3, permission: "analytics.read", ready: false },
    ],
  },
  {
    label: "App customization",
    items: [
      { title: "Branding & theme", href: "/customization/theme", icon: Palette, permission: "customization.read", ready: false },
      { title: "Home builder", href: "/customization/home", icon: LayoutTemplate, permission: "customization.read", ready: false },
      { title: "Banners", href: "/customization/banners", icon: ImageIcon, permission: "customization.read", ready: false },
      { title: "Top 10", href: "/customization/top10", icon: ListOrdered, permission: "customization.read", ready: false },
      { title: "Feature flags", href: "/customization/flags", icon: Flag, permission: "customization.read", ready: true },
      { title: "Login & panels", href: "/customization/access", icon: KeyRound, permission: "customization.read", ready: false },
      { title: "Versions & maintenance", href: "/customization/versions", icon: Smartphone, permission: "customization.read", ready: false },
    ],
  },
  {
    label: "Content",
    items: [
      { title: "Catalog", href: "/catalog", icon: Clapperboard, permission: "catalog.read", ready: false },
      { title: "Live channels", href: "/channels", icon: Tv, permission: "catalog.read", ready: false },
      { title: "Sports", href: "/sports", icon: Trophy, permission: "sports.read", ready: false },
      { title: "Providers", href: "/providers", icon: Activity, permission: "providers.read", ready: false },
    ],
  },
  {
    label: "People",
    items: [
      { title: "Users", href: "/users", icon: Users, permission: "users.read", ready: false },
      { title: "Devices", href: "/devices", icon: Monitor, permission: "devices.read", ready: false },
      { title: "Support", href: "/support", icon: LifeBuoy, permission: "support.read", ready: false },
    ],
  },
  {
    label: "Business",
    items: [
      { title: "Subscriptions", href: "/subscriptions", icon: CreditCard, permission: "subscriptions.read", ready: false },
      { title: "Ads & promotions", href: "/ads", icon: Megaphone, permission: "ads.read", ready: false },
      { title: "Notifications", href: "/notifications", icon: Bell, permission: "notifications.read", ready: false },
    ],
  },
  {
    label: "System",
    items: [
      { title: "Admins & roles", href: "/admins", icon: ShieldCheck, permission: "admins.read", ready: true },
      { title: "Audit log", href: "/audit", icon: ScrollText, permission: "audit.read", ready: true },
      { title: "Settings", href: "/settings", icon: Settings, permission: "settings.read", ready: false },
      { title: "Health", href: "/health", icon: Gauge, permission: "settings.read", ready: false },
    ],
  },
];

/** Groups/items visible for a set of permissions. */
export function navFor(permissions: ReadonlySet<string>): NavGroup[] {
  return NAV.map((g) => ({ ...g, items: g.items.filter((i) => permissions.has(i.permission)) })).filter(
    (g) => g.items.length > 0,
  );
}

/** Title for a path (breadcrumb / page header). */
export function navTitle(pathname: string): string {
  for (const g of NAV) {
    for (const i of g.items) {
      if (i.href === pathname) return i.title;
    }
  }
  return "";
}
