# NEO 8K
## Complete Product Requirements & Technical Architecture Document

**Product:** Neo 8K Universal IPTV Player & Streaming Management Ecosystem  
**Document Type:** Product Vision, Software Requirements Specification (SRS), Technical Architecture & Development Blueprint  
**Status:** Master Project Specification  
**Mobile Application:** Flutter  
**Administration Platform:** React + TypeScript  
**Backend Infrastructure:** Supabase  
**Database:** PostgreSQL  
**Video Delivery:** Direct from authorized IPTV providers  
**Architecture:** Backend-as-a-Service (BaaS), provider-independent, local-first and metadata-centric

---

# 1. Executive Summary

## 1.1 Project Overview

Neo 8K is a universal IPTV player and streaming management ecosystem designed to support multiple IPTV protocols, providers, connection methods and subscription models through one centralized platform.

The ecosystem consists of two main applications:

1. **Neo 8K Mobile Application:** A premium streaming application developed with Flutter for watching live television, movies, series and other supported IPTV content.
2. **Neo 8K Administration Panel:** A comprehensive React-based dashboard through which platform administrators manage users, providers, subscriptions, advertisements, application features, content presentation, analytics, promotions and virtually every configurable aspect of the application.

Both applications will use the same Supabase project.

Supabase will provide the database, authentication, storage, real-time updates, access control and serverless functionality.

There will be no separately deployed Node.js, Python, FastAPI or traditional application backend.

## 1.2 Core Philosophy

Neo 8K will operate according to five fundamental principles:

1. **Universal Compatibility:** Support multiple IPTV providers and protocols through a modular connection system.
2. **Direct Streaming:** Video streams must play directly from the user's authorized IPTV provider.
3. **Centralized Management:** Administrators should control the application through one React dashboard.
4. **Smart Catalog Management:** Reuse global metadata and maintain individual provider availability.
5. **Lightweight Infrastructure:** Store only necessary information and avoid unnecessary database operations, video processing and infrastructure costs.

## 1.3 Product Vision

The long-term vision is to make Neo 8K a complete IPTV ecosystem rather than simply another IPTV player.

Users should be able to:

- Connect their own IPTV providers.
- Add multiple playlists and accounts.
- Watch live channels.
- Browse movies and series.
- Search across connected providers.
- Maintain their own personalized library.
- Save watch history and favorites.
- Synchronize their data across devices.
- Subscribe to Neo 8K plans.
- Access features based on their subscription.
- Receive promotions and notifications.
- Customize their viewing experience.

Administrators should be able to control the entire business and application experience without manually updating the Flutter application for every configuration change.

---

# 2. Product Architecture and Technology Stack

## 2.1 Main Components

The platform will have three primary layers.

### A. Flutter Mobile Application

The Flutter application is responsible for:

- User interface.
- IPTV provider connections.
- Playlist parsing.
- Provider-specific authentication flows.
- Catalog browsing.
- Local caching.
- Video playback.
- Watch history.
- Favorites.
- User preferences.
- Device management.
- Subscription experience.
- Synchronization with Supabase.
- Receiving remote application configurations.

### B. React Administration Panel

The React application is responsible for:

- Platform management.
- User management.
- Subscription management.
- Advertisement management.
- Global feature configuration.
- Catalog administration.
- Provider configuration.
- Analytics.
- Marketing.
- Notifications.
- Device management.
- Administrative permissions.
- Audit logs.
- Remote configuration.

### C. Supabase

Supabase will serve as the shared backend infrastructure.

Services:

| Supabase service | Responsibility |
|---|---|
| PostgreSQL | All structured application data |
| Supabase Auth | User authentication |
| Row Level Security | Database access protection |
| Edge Functions | Secure server-side operations |
| Realtime | Configuration and selected data updates |
| Storage | App artwork, banners and promotional assets |
| Cron | Scheduled synchronization and maintenance |
| Database Functions | Atomic database operations |
| Database Indexes | Query performance |

## 2.2 Technology Stack

| Component | Technology |
|---|---|
| Mobile application | Flutter / Dart |
| Admin panel | React + TypeScript |
| Admin styling | Tailwind CSS |
| Admin components | shadcn/ui |
| State management | Riverpod or Bloc |
| Flutter routing | GoRouter |
| Local database | SQLite / Drift or Isar |
| Local secure storage | Platform secure storage |
| Cloud database | Supabase PostgreSQL |
| Authentication | Supabase Auth |
| Backend functions | Supabase Edge Functions |
| Database access | Supabase client |
| Image caching | Flutter image cache |
| Video playback | Native Android/iOS player integration |
| Android playback engine | Media3 ExoPlayer |
| iOS playback engine | AVPlayer |
| Notifications | Firebase Cloud Messaging / APNs |
| Analytics | Supabase-based event aggregation |
| Version control | GitHub |
| CI/CD | GitHub Actions |

## 2.3 Architecture Diagram

```text
                       NEO 8K ECOSYSTEM
                              |
                 +------------+------------+
                 |                         |
           FLUTTER APP                REACT ADMIN
                 |                         |
                 +------------+------------+
                              |
                         SUPABASE
                              |
        +----------+----------+----------+----------+
        |          |          |          |          |
      AUTH       DATABASE   STORAGE    REALTIME   FUNCTIONS
        |          |          |          |          |
        +----------+----------+----------+----------+
                              |
                   EXTERNAL IPTV PROVIDERS
                              |
          +-------------------+-------------------+
          |                   |                   |
       XTREAM               STALKER               M3U
          |                   |                   |
          +-------------------+-------------------+
                              |
                        DIRECT PLAYBACK
                              |
                       FLUTTER PLAYER
```

## 2.4 Critical Architecture Rule

Supabase will never act as:

- Video streaming server.
- Video proxy.
- Video transcoding server.
- IPTV media hosting platform.
- Continuous streaming relay.

Actual video data must travel directly between the authorized provider and the user's playback application.

Supabase only stores the information needed to manage the application.

---

# 3. Universal IPTV Provider Engine

## 3.1 Overview

The provider engine is one of the most important components of Neo 8K.

Every user may have a completely different IPTV provider, host, username, password, playlist or device authorization method.

The application must not depend on one fixed provider or API.

Instead, Neo 8K will implement independent provider adapters that convert provider-specific data into a common internal format.

## 3.2 Supported Protocols

### Xtream Codes API

Support:

- Host URL.
- Username.
- Password.
- Server information.
- Account information.
- Account expiry where provided.
- Live categories.
- Live channels.
- VOD categories.
- Movies.
- Series.
- Seasons.
- Episodes.
- Playback URL resolution.
- EPG information where available.
- Provider connection testing.
- Playlist synchronization.

### M3U / M3U8

Support:

- Remote M3U URL.
- Remote M3U8 URL.
- Local M3U file.
- Uploaded playlist.
- EXTINF metadata.
- Channel names.
- Channel logos.
- Group titles.
- EPG identifiers.
- Stream types.
- Custom attributes.
- Playlist parsing.
- Duplicate detection.
- Category organization.
- Automatic refresh.

M3U support must distinguish between ordinary channel playlists and provider-specific VOD or catch-up extensions.

### Stalker Portal / MAG

Support authorized portal connections:

- Portal URL.
- MAC/device identity where permitted.
- Portal authentication.
- Token management.
- Device authorization.
- Channel retrieval.
- Category retrieval.
- EPG integration where supported.
- Playback resolution.
- Session renewal.
- Connection diagnostics.

### Additional Providers

Design the system so additional adapters can be added:

- Enigma2.
- Generic IPTV APIs.
- Other documented provider APIs.
- Future supported playlist formats.

## 3.3 Provider Adapter Architecture

```text
NEO IPTV ENGINE
│
├── Provider Interface
│
├── Xtream Adapter
│   ├── Authentication
│   ├── Account Information
│   ├── Live Channels
│   ├── Movies
│   ├── Series
│   └── Playback Resolver
│
├── M3U Adapter
│   ├── Playlist Parser
│   ├── Category Parser
│   ├── EPG Mapping
│   └── Stream Resolver
│
├── Stalker Adapter
│   ├── Portal Authentication
│   ├── Session Management
│   ├── Device Authorization
│   └── Playback Resolver
│
└── Future Adapters
        |
        v
  UNIFIED CONTENT MODEL
```

Each adapter must implement a consistent internal interface.

A new provider should not require rewriting the entire Flutter application.

## 3.4 Provider Management Features

Users must be able to:

- Add multiple IPTV connections.
- Edit connections.
- Delete connections.
- Rename connections.
- Test connections.
- Refresh playlists.
- Set a primary provider.
- Enable or disable providers.
- Switch between providers.
- See connection status.
- See provider account expiry where available.
- View last synchronization time.
- Configure individual provider settings.
- Set content synchronization preferences.
- Retry failed synchronization.
- View provider-specific errors.

Administrators should be able to define supported connection methods and compatibility settings.

## 3.5 Provider Connection States

Every connection should have a standardized status:

- Pending.
- Connecting.
- Connected.
- Synchronizing.
- Active.
- Expired.
- Unauthorized.
- Temporarily unavailable.
- Invalid configuration.
- Disabled.
- Removed.

The application should never assume that an IPTV account is active simply because credentials were previously accepted.

---

# 4. Global Content Catalog System

## 4.1 Overview

Neo 8K must have a shared global catalog.

The objective is to avoid storing duplicate metadata for the same movie, series or channel when multiple users connect different providers.

The global catalog stores canonical content information.

The provider mapping system records where each user can access that content.

## 4.2 Global Catalog

The catalog will include:

### Live Channels

- Channel name.
- Global channel ID.
- Logo.
- Country.
- Language.
- Category.
- Quality information where verified.
- EPG identifier.
- Description.
- Content classification.
- Metadata source.

### Movies

- Movie title.
- Release year.
- Description.
- Poster.
- Backdrop.
- Genre.
- Country.
- Language.
- Cast.
- Director.
- Runtime.
- External metadata identifiers.
- Ratings with source attribution.
- Trailer reference where available.

### Series

- Series title.
- Description.
- Poster.
- Backdrop.
- Release year.
- Genres.
- Cast.
- External metadata identifiers.

### Seasons

- Series reference.
- Season number.
- Season title.
- Poster.
- Description.

### Episodes

- Series reference.
- Season reference.
- Episode number.
- Episode title.
- Description.
- Runtime.
- Thumbnail.
- Release date.

## 4.3 Provider Mapping

A provider item must be associated with a global content record whenever a reliable match exists.

Example:

```text
GLOBAL MOVIE
    Interstellar
    TMDB ID: 157336
           |
           +---- Provider A / Movie 501
           |
           +---- Provider B / Movie 921
           |
           +---- Provider C / Movie 120
```

All provider-specific identifiers remain separate.

## 4.4 Content Matching Engine

Matching should use:

1. External content ID.
2. Normalized title.
3. Release year.
4. Season number.
5. Episode number.
6. Language.
7. Category.
8. Channel identifiers.
9. Additional metadata.

Implement confidence-based matching:

- Exact match.
- High-confidence match.
- Possible match.
- Manual review required.
- Unmatched.

Do not automatically merge unrelated content merely because two titles look similar.

## 4.5 User Availability System

Each user must see only content accessible through their connected providers and allowed by their Neo 8K entitlements.

Example:

```text
GLOBAL CATALOG
       |
       +---- Movie A
       +---- Movie B
       +---- Movie C
       +---- Movie D
       |
       v
USER PROVIDER MAPPING
       |
       +---- Movie A: Available
       +---- Movie B: Available
       +---- Movie C: Unavailable
       +---- Movie D: Available
       |
       v
SUBSCRIPTION FILTER
       |
       v
FINAL USER CATALOG
```

This architecture allows the app to compare the user's provider catalog against the global catalog without exposing content that the user cannot access.

## 4.6 Global Catalog Data Sources

Possible metadata sources:

- Provider-supplied metadata.
- Licensed metadata APIs.
- Public metadata databases where permitted.
- Manually curated administrator content.
- User-reported metadata corrections.

External movie databases may provide metadata and artwork information, but they do not provide streaming rights or playback availability.

---

# 5. Smart Caching and Synchronization

## 5.1 Objective

Neo 8K must load quickly even when a user has a large IPTV playlist.

The application should not download the entire catalog every time a user opens the app.

## 5.2 Three-Level Cache Architecture

### Level 1: Local Device Cache

Store:

- Channel metadata.
- Movie metadata.
- Series metadata.
- Categories.
- Logos.
- Posters.
- EPG information within a defined retention window.
- Favorites.
- Recent searches.
- User preferences.
- Recently watched content.
- Last known catalog version.

Technologies:

- SQLite / Drift.
- Isar.
- Secure platform storage for credentials and sensitive values.

### Level 2: Supabase

Store:

- Global content metadata.
- Provider mappings.
- User-specific availability.
- Watch history.
- Favorites.
- Subscription information.
- Application settings.
- Device information.
- Synchronization status.

### Level 3: Original Provider

Fetch when needed:

- Current playback references.
- Current provider session information.
- Updated channel availability.
- New catalog items.
- Provider account status.
- Current EPG data.

## 5.3 Synchronization Workflow

When a user opens the application:

1. Initialize the application.
2. Load local configuration.
3. Load cached user information.
4. Display cached home screen.
5. Validate account state and entitlements.
6. Check provider connection status when necessary.
7. Refresh changed catalogs.
8. Update local availability.
9. Synchronize pending watch history.
10. Continue operating even if a nonessential synchronization operation fails.

## 5.4 Incremental Synchronization

Never download and rewrite the complete catalog unnecessarily.

Use:

- Content hashes.
- Catalog versions.
- Updated timestamps.
- Last synchronization cursors.
- Bulk upserts.
- Changed-record detection.
- Paginated synchronization.
- Failed-job retry.
- Synchronization checkpoints.

## 5.5 Cache Retention

Configurable policies should define:

- Catalog cache expiration.
- Artwork cache expiration.
- EPG retention.
- Recently watched retention.
- Local database cleanup.
- Storage limits.
- Cache refresh behavior.

The administrator may define default policies, while users may receive limited customization.

## 5.6 Important Performance Rule

Large M3U playlists should preferably be parsed locally.

Do not upload enormous playlists to Supabase simply to process every entry.

If remote synchronization is required, process it in manageable batches through resumable operations.

---

# 6. Flutter Mobile Application

## 6.1 General Requirements

The Flutter application should provide a premium, modern, smooth and responsive interface.

Design direction:

- Dark-first design.
- Optional light theme.
- Premium cinematic experience.
- Smooth transitions.
- Responsive layouts.
- Fast startup.
- Minimal loading screens.
- Skeleton placeholders.
- Lazy-loaded artwork.
- Accessible controls.
- Remote-controlled UI configuration.

The interface should support mobile and television interaction models rather than simply scaling the phone UI onto a television.

## 6.2 Home Screen

The home screen should be configurable entirely through the admin panel.

Possible sections:

1. Continue Watching.
2. Live TV.
3. Featured Channels.
4. Trending Movies.
5. Recently Added Movies.
6. Popular Series.
7. Continue Watching Series.
8. My Favorites.
9. Recently Watched.
10. Recommended For You.
11. New Releases.
12. Featured Categories.
13. Promotional Banners.
14. Subscription Offers.
15. Custom Administrator Sections.

Administrators must be able to:

- Create sections.
- Delete sections.
- Reorder sections.
- Rename sections.
- Change artwork.
- Select section type.
- Set visibility.
- Define subscription restrictions.
- Schedule sections.
- Target user segments.
- Configure content sources.

## 6.3 Live TV Module

### Live TV Features

- All live channels.
- Category navigation.
- Country filters.
- Language filters.
- Search.
- Favorite channels.
- Recently watched.
- Channel history.
- Custom ordering.
- Channel hiding.
- Channel locking.
- EPG.
- Current program.
- Next program.
- Program schedule.
- Channel numbers.
- Channel logos.
- Provider labels.
- Connection status.
- Channel information.
- Multi-audio.
- Supported catch-up.
- Supported timeshift.
- Quick channel switching.

### EPG

Electronic Program Guide should support:

- Current program.
- Upcoming program.
- Program schedule.
- Time navigation.
- Channel-based guide.
- Category filtering.
- Program details.
- EPG refresh.
- Timezone correction.

EPG data may come from provider feeds or other authorized sources.

## 6.4 Movies Module

Features:

- Global movie catalog.
- User-specific availability.
- Featured movies.
- Trending movies.
- Recently added movies.
- Categories.
- Genres.
- Countries.
- Release years.
- Ratings.
- Movie details.
- Cast.
- Director.
- Runtime.
- Posters.
- Backdrops.
- Trailers.
- Watchlist.
- Favorites.
- Resume playback.
- Related movies.
- Similar titles.
- Search.
- Advanced filters.
- Sorting.

## 6.5 Series Module

Features:

- Series catalog.
- Series details.
- Seasons.
- Episodes.
- Episode descriptions.
- Episode thumbnails.
- Season progress.
- Episode progress.
- Continue watching.
- Next episode.
- Autoplay.
- Skip intro where configured.
- Recently released episodes.
- Favorite series.
- Watchlist.
- Completed episodes.
- Related series.

## 6.6 Universal Search

Search must work across:

- Live channels.
- Movies.
- Series.
- Seasons.
- Episodes.
- Categories.
- Actors and directors when metadata exists.

Search features:

- Instant suggestions.
- Search history.
- Popular searches.
- Typo tolerance.
- Partial matching.
- Filters.
- Language filters.
- Provider filters.
- Available-only results.
- Voice search where supported.

Initially use PostgreSQL search capabilities and appropriate indexes. Consider a dedicated search engine only if actual scale requires it.

## 6.7 Media Player

The media player is a critical part of Neo 8K.

### Live Player

- Direct stream playback.
- Fullscreen.
- Channel switching.
- Aspect ratio.
- Audio track selection.
- Subtitle selection.
- Volume.
- Brightness gestures where appropriate.
- Screen orientation.
- Picture-in-picture.
- Supported external casting.
- Buffer management.
- Network diagnostics.
- Automatic reconnection.
- Stream retry.
- Error reporting.
- Channel information overlay.

### VOD Player

- Play and pause.
- Seek.
- Playback speed.
- Resume playback.
- Audio tracks.
- Subtitles.
- External subtitles.
- Skip intro where configured.
- Skip credits where configured.
- Next episode.
- Previous episode.
- Fullscreen.
- Picture-in-picture.
- Progress synchronization.
- Resume from another device.

### Supported Media Formats

Implement compatibility for common formats where supported by the device and provider:

- HLS.
- MPEG-TS.
- MPEG-DASH.
- MP4.
- MKV where the native playback engine supports the contained codecs.
- AAC.
- MP3.
- AC3 where device licensing and decoder support allow it.
- Common subtitle formats.

The application must use actual codec and device capability detection. It should not claim universal format compatibility.

## 6.8 User Profiles

Allow multiple profiles under one Neo account where subscription permissions allow.

Each profile may have:

- Display name.
- Avatar.
- Language.
- Theme.
- Favorites.
- Watch history.
- Watchlist.
- Content preferences.
- Parental restrictions.
- Profile PIN.
- Personalized recommendations.

## 6.9 Guest Mode

Users should be able to use basic functionality without immediately creating a Neo account.

Guest features:

- Add provider.
- Browse content.
- Watch content.
- Local favorites.
- Local watch history.
- Local settings.

The app should encourage account creation to synchronize information.

When a guest registers, migrate their supported local data into their account.

## 6.10 Account Synchronization

Authenticated users can synchronize:

- Providers.
- Favorites.
- Watch history.
- Watchlists.
- Profiles.
- Preferences.
- Viewing progress.
- Last-used provider.
- Player settings.

Conflict resolution must be defined for situations where multiple devices modify the same information.

## 6.11 Advanced User Features

- Custom playlists.
- Multiple providers.
- Provider switching.
- Custom categories.
- Hide unwanted categories.
- Hide channels.
- Lock channels.
- Recently played.
- Favorite collections.
- Continue Watching.
- Search history.
- Network information.
- Player diagnostics.
- User feedback.
- Broken channel reporting.
- App update notifications.
- Account deletion.
- Data export.
- Privacy settings.

---

# 7. React Administration Panel

## 7.1 Overview

The React Admin Panel is the central command center of Neo 8K.

Administrators should be able to manage the platform without needing to edit Flutter code for normal operational changes.

The panel should use a modular architecture with proper permissions.

## 7.2 Admin Dashboard

Display:

- Total registrations.
- Active users.
- Daily active users.
- Monthly active users.
- Guest users.
- Paid subscribers.
- Free subscribers.
- Expired subscriptions.
- New registrations.
- Active devices.
- Recent sessions.
- Provider connections.
- Provider failures.
- Total watch time.
- Popular channels.
- Popular movies.
- Popular series.
- Advertisement performance.
- Subscription revenue.
- Campaign performance.
- Recent administrative activity.

Use date filters and graphical reports.

## 7.3 User Management

Administrators should be able to:

- View users.
- Search users.
- Filter users.
- View profiles.
- View registration date.
- View last active time.
- View subscription.
- View connected devices.
- View provider connection counts.
- View account status.
- View permitted activity statistics.
- Change user roles.
- Suspend accounts.
- Reactivate accounts.
- Ban accounts.
- Delete accounts.
- Reset supported account settings.
- Assign subscription plans.
- Grant trial access.
- Extend expiry.
- Revoke access.
- Send notifications.
- Add administrative notes.

Sensitive credentials must not be displayed in plaintext.

## 7.4 Provider Management

Admin features:

- Enable/disable supported adapters.
- Configure provider limits.
- Configure synchronization policies.
- View provider errors.
- View provider connection statistics.
- Configure supported formats.
- Configure default timeout settings.
- Configure retry policies.
- Configure adapter versions.
- Manage provider compatibility.
- View failed synchronization jobs.

This module manages Neo 8K's adapter capabilities. It should not become a repository of users' unencrypted IPTV passwords.

## 7.5 Global Catalog Administration

Manage:

- Global channels.
- Movies.
- Series.
- Seasons.
- Episodes.
- Genres.
- Countries.
- Languages.
- Artwork.
- Metadata.
- Content identifiers.
- Duplicate records.
- Provider mappings.
- Unmatched records.
- Incorrect mappings.
- Metadata corrections.

Provide a manual content-matching interface.

## 7.6 Home Screen Builder

Create a visual home screen management tool.

Administrators should be able to:

- Add a section.
- Remove a section.
- Reorder sections.
- Change titles.
- Choose content types.
- Choose content categories.
- Select artwork.
- Set visibility.
- Set subscription targeting.
- Set country targeting.
- Set user targeting.
- Schedule publication.
- Preview the layout.
- Publish changes.

The Flutter app should render the configured sections dynamically.

## 7.7 Application Settings

A central configuration module should control:

- Application name.
- Branding.
- Logos.
- Splash artwork.
- Theme defaults.
- Primary colors.
- Supported languages.
- Default language.
- Default player.
- Player preferences.
- Search behavior.
- Home screen configuration.
- Catalog settings.
- Provider settings.
- Cache policies.
- Notification preferences.
- Maintenance mode.
- Minimum app version.
- Recommended app version.
- Feature availability.

## 7.8 Feature Flag Management

Feature flags must support:

- Global control.
- Android-specific control.
- iOS-specific control.
- TV-specific control.
- Subscription-based control.
- Country-based control.
- App-version control.
- User-specific overrides.
- Scheduled activation.
- Scheduled deactivation.

Example:

```json
{
  "features": {
    "live_tv": true,
    "movies": true,
    "series": true,
    "epg": true,
    "catchup": true,
    "watch_history": true,
    "favorites": true,
    "multi_provider": true,
    "profiles": true,
    "picture_in_picture": true,
    "chromecast": true,
    "offline_catalog": true
  }
}
```

The configuration must be validated against known feature definitions.

Unknown or invalid configuration should never crash the application.

## 7.9 Remote Configuration Limitations

Remote configuration can control existing functionality, but cannot create arbitrary new native functionality.

For example:

- Turning on an existing player option: Remote.
- Changing home screen sections: Remote.
- Changing advertisement placement: Remote.
- Enabling a compiled feature: Remote.
- Adding a completely new native player engine: Requires an app release.
- Adding a new permission or native SDK: Usually requires an app release.
- Changing app store binaries: Requires a new release.

---

# 8. Subscription and Entitlement System

## 8.1 Subscription Types

Support:

- Free.
- Monthly.
- Quarterly.
- Yearly.
- Lifetime.
- Trial.
- Promotional.
- Custom.
- Manually assigned.

## 8.2 Subscription Configuration

Every plan should have configurable:

- Name.
- Description.
- Price.
- Currency.
- Duration.
- Trial duration.
- Device limit.
- Provider limit.
- Profile limit.
- Feature access.
- Advertisement rules.
- Storage/cache limits where applicable.
- Support level.
- Renewal policy.
- Grace period.
- Visibility.
- Availability.

## 8.3 Example Subscription Plans

| Feature | Free | Basic | Premium | VIP |
|---|---:|---:|---:|---:|
| Live TV | Yes | Yes | Yes | Yes |
| Movies | Yes | Yes | Yes | Yes |
| Series | Yes | Yes | Yes | Yes |
| Provider connections | 1 | 2 | 5 | 10 |
| Devices | 1 | 2 | 3 | 5 |
| Watch history sync | Optional | Yes | Yes | Yes |
| Profiles | 1 | 1 | 3 | 5 |
| Advanced player features | Limited | Yes | Yes | Yes |
| Ads | Yes | Yes | Optional | No |
| Priority support | No | No | Optional | Yes |

All values must be administrator-configurable.

## 8.4 Entitlement Engine

Do not check subscription access using only a plan name.

Create a centralized entitlement system.

Example:

```text
USER
 |
 +-- Subscription
       |
       +-- Active Plan
       |
       +-- Device Limit
       |
       +-- Provider Limit
       |
       +-- Feature Entitlements
       |
       +-- Expiry
       |
       v
    ACCESS DECISION
```

The same entitlement rules must apply to the Flutter app and trusted administrative operations.

## 8.5 Payment Management

Support integration with suitable payment providers where available.

Possible payment channels:

- Apple In-App Purchases.
- Google Play Billing.
- Supported local payment providers.
- Other authorized payment gateways.
- Manually verified payments.

Payment confirmation must be verified through a trusted server-side process or authorized administrator action.

Never allow the mobile client to grant itself a paid subscription by writing directly to the subscription table.

---

# 9. Advertisement and Marketing System

## 9.1 Advertisement Types

Support:

- Splash advertisements.
- Home banners.
- Native advertisements.
- Sponsored sections.
- Interstitial advertisements.
- Promotional cards.
- Subscription advertisements.
- External advertising networks.
- Video advertisements where compatible and permitted.

## 9.2 Advertisement Management

Administrators should configure:

- Advertisement name.
- Placement.
- Campaign.
- Start date.
- End date.
- Target country.
- Target plan.
- Target users.
- Priority.
- Frequency limit.
- Display duration.
- Click destination.
- Image/video asset.
- Active status.

## 9.3 Advertisement Analytics

Track:

- Impressions.
- Clicks.
- Click-through rate.
- Campaign performance.
- Placement performance.
- User segment performance.

Use aggregated analytics where possible to minimize database writes.

## 9.4 Promotion System

Include:

- Coupon codes.
- Referral codes.
- Promotional campaigns.
- Welcome offers.
- Discount campaigns.
- Free trials.
- Renewal offers.
- Upgrade offers.
- Seasonal campaigns.
- Promotional notifications.

Advertising must respect consent, platform policies and subscription promises.

---

# 10. Watch History and User Analytics

## 10.1 Watch History

Save:

- User ID.
- Profile ID.
- Content ID.
- Provider connection.
- Content type.
- Last playback position.
- Total duration where known.
- Last watched time.
- Completion state.
- Device ID.

## 10.2 Watch History Behavior

Users can:

- Continue watching.
- Remove history entries.
- Clear all history.
- Disable cloud synchronization.
- Resume across devices.
- View recently watched content.

## 10.3 User Statistics

Display:

- Total watch time.
- Daily viewing.
- Weekly viewing.
- Monthly viewing.
- Most watched channels.
- Most watched movies.
- Most watched series.
- Favorite categories.
- Recent activity.
- Viewing trends.

## 10.4 Administrative Analytics

Administrators can view appropriately permissioned and privacy-compliant aggregate information.

Reports:

- Active users.
- New registrations.
- Retention.
- Subscription conversion.
- Churn.
- Watch time.
- Content popularity.
- Device distribution.
- Provider connection failures.
- Playback errors.
- Advertising engagement.
- Revenue reports.

## 10.5 Analytics Efficiency

Do not write a database record every second.

Instead:

- Start playback session.
- Periodically update progress.
- Batch events.
- Save playback completion.
- Aggregate daily statistics.
- Apply retention policies.
- Exclude sensitive stream credentials from logs.

Users must have transparent privacy settings for activity tracking.

---

# 11. Notifications and Communication

## 11.1 Push Notifications

Use Firebase Cloud Messaging and Apple Push Notification service where appropriate.

Notification categories:

- Account notifications.
- Subscription notifications.
- Payment notifications.
- Provider connection alerts.
- Application updates.
- New features.
- Promotional campaigns.
- Maintenance announcements.
- Security notifications.

## 11.2 Admin Notification Center

Administrators can:

- Create notifications.
- Schedule notifications.
- Target all users.
- Target specific plans.
- Target selected users.
- Target supported platforms.
- Send announcements.
- Review delivery statistics.
- Manage templates.

## 11.3 In-App Notifications

Provide:

- Notification inbox.
- Read/unread status.
- Deep links.
- Expiry.
- Notification categories.
- User notification preferences.

---

# 12. Device and Session Management

## 12.1 Device Registration

Each authenticated device should have:

- Device identifier.
- Device type.
- Operating system.
- Application version.
- Registration date.
- Last active time.
- Session status.
- Device name.

Do not treat a client-generated device identifier as strong proof of device identity.

## 12.2 Device Management Features

Users can:

- View registered devices.
- Rename devices.
- Remove devices.
- Revoke sessions.
- View last activity.

Administrators can:

- View device counts.
- Set device limits.
- Revoke suspicious sessions.
- Suspend access.
- View supported platform information.

## 12.3 Concurrent Sessions

Subscription rules may define:

- Maximum registered devices.
- Maximum simultaneous sessions.
- Maximum active profiles.

A database-backed session and heartbeat system can provide application-level session management.

It cannot guarantee exact knowledge of provider-side concurrent streams unless the provider exposes that information.

---

# 13. Advanced Features

These features can be developed after the core platform is stable.

## 13.1 Smart Content Discovery

- Personalized recommendations.
- Similar movies.
- Related series.
- Popular channels.
- Recently added content.
- Trending categories.
- Recommendations by language.
- Recommendations by viewing history.

## 13.2 Automatic Provider Failover

If a user has multiple authorized providers for the same content:

- Detect playback errors.
- Identify alternative authorized mappings.
- Offer another source.
- Optionally retry an eligible alternative.
- Record provider health information.

Do not automatically switch to unrelated content or bypass provider authorization.

## 13.3 Provider Health Monitor

Measure:

- Authentication success.
- Playlist refresh success.
- Catalog response time.
- Playback initialization failures.
- Connection errors.
- Last successful synchronization.

Provider health must be treated as an observed client-side or server-side result, not as guaranteed availability.

## 13.4 Content Quality Information

Where trustworthy provider metadata is available, display:

- Resolution.
- Audio language.
- Subtitle availability.
- Codec.
- Stream type.

Do not label a stream 4K or 8K simply because its provider name contains those terms.

## 13.5 User Feedback System

Users can report:

- Broken channel.
- Incorrect movie information.
- Incorrect episode.
- Missing poster.
- Incorrect EPG.
- Provider connection issue.
- Application bug.
- Playback problem.

Administrators can manage reports and mark them resolved.

## 13.6 Family and Parental Controls

- PIN protection.
- Profile restrictions.
- Kids mode.
- Category restrictions.
- Content-rating restrictions where metadata is available.
- Viewing-time limits.
- Profile-specific favorites.
- Profile-specific history.

---

# 14. Supabase Database Architecture

## 14.1 Database Design Principles

The database must be:

- Relational.
- Normalized.
- Indexed.
- Secure.
- Efficient.
- Scalable.
- Multi-user.
- Provider-independent.

Do not store every piece of information in one JSON column.

Use JSONB only for genuinely variable provider metadata and configuration where a fixed relational schema is not appropriate.

## 14.2 Database Modules

### A. Identity and Accounts

| Table | Purpose |
|---|---|
| profiles | User profiles |
| user_roles | Administrative and user roles |
| user_devices | Registered devices |
| user_sessions | Application sessions |
| user_preferences | User preferences |
| user_profiles | Multiple household profiles |
| privacy_preferences | Privacy and analytics settings |

### B. Provider Management

| Table | Purpose |
|---|---|
| provider_types | Supported provider formats |
| user_connections | User provider connections |
| connection_secrets | Protected credential references |
| connection_status | Current connection status |
| provider_sync_jobs | Synchronization jobs |
| provider_sync_logs | Synchronization results |
| provider_categories | Provider categories |
| provider_items | Provider-specific content records |
| connection_items | Availability per connection |

### C. Global Content

| Table | Purpose |
|---|---|
| global_channels | Canonical channels |
| global_movies | Canonical movies |
| global_series | Canonical series |
| global_seasons | Series seasons |
| global_episodes | Series episodes |
| global_categories | Shared categories |
| global_genres | Shared genres |
| global_countries | Countries |
| global_languages | Languages |
| content_metadata | Extended metadata |
| content_artwork | Posters and images |
| content_external_ids | External identifiers |
| content_mappings | Canonical matching |

### D. EPG

| Table | Purpose |
|---|---|
| epg_sources | EPG sources |
| epg_channel_mappings | Channel-to-EPG mapping |
| epg_programs | Program information |
| epg_sync_status | EPG synchronization status |

### E. User Activity

| Table | Purpose |
|---|---|
| watch_history | Viewing progress |
| favorites | User favorites |
| watchlists | Saved content collections |
| playback_sessions | Playback session summaries |
| user_activity | Important activity events |
| search_history | Recent searches |
| user_content_preferences | User-specific content preferences |

### F. Subscriptions

| Table | Purpose |
|---|---|
| subscription_plans | Available plans |
| plan_entitlements | Plan features and limits |
| subscriptions | User subscriptions |
| payment_records | Verified payment records |
| invoices | Invoice records |
| coupons | Discount codes |
| coupon_redemptions | Coupon usage |
| subscription_events | Subscription history |

### G. Advertising and Marketing

| Table | Purpose |
|---|---|
| ad_campaigns | Campaigns |
| advertisements | Advertisement assets and configuration |
| ad_placements | Placement definitions |
| ad_impressions | Impression records |
| ad_clicks | Click records |
| referral_codes | Referral codes |
| referral_rewards | Referral rewards |
| marketing_segments | Targeting groups |

### H. Application Configuration

| Table | Purpose |
|---|---|
| app_settings | Global application settings |
| feature_flags | Feature switches |
| feature_overrides | Targeted overrides |
| home_sections | Dynamic home screen |
| home_section_items | Section content |
| app_versions | Supported versions |
| remote_announcements | Announcements |
| app_languages | Available languages |
| maintenance_windows | Maintenance scheduling |

### I. Support and Administration

| Table | Purpose |
|---|---|
| support_tickets | Support requests |
| support_messages | Ticket messages |
| content_reports | Content issue reports |
| admin_roles | Admin roles |
| admin_permissions | Admin permissions |
| admin_role_permissions | Role permission mapping |
| audit_logs | Administrative activity |
| system_alerts | Operational alerts |

## 14.3 Important Relationships

```text
AUTH USERS
   |
   +---- PROFILES
   |
   +---- USER DEVICES
   |
   +---- USER CONNECTIONS
   |          |
   |          +---- CONNECTION ITEMS
   |          |          |
   |          |          +---- PROVIDER ITEMS
   |          |                     |
   |          |                     +---- GLOBAL CONTENT
   |          |
   |          +---- PROVIDER SYNC JOBS
   |
   +---- SUBSCRIPTIONS
   |          |
   |          +---- PLAN ENTITLEMENTS
   |
   +---- WATCH HISTORY
   |
   +---- FAVORITES
   |
   +---- USER PROFILES
```

## 14.4 Essential Database Rules

1. Every user-owned record must have an appropriate ownership relationship.
2. Every provider connection must belong to a user.
3. Every provider item must belong to a provider connection or a properly scoped provider record.
4. Global catalog records must not contain user-specific credentials.
5. Playback references must not be treated as permanent global metadata.
6. Subscription entitlements must be validated independently of UI visibility.
7. Administrative permissions must be enforced in the database and trusted functions.
8. Database operations must be indexed and paginated.
9. Large data imports must be resumable.
10. Historical records must have appropriate retention policies.

## 14.5 Database Indexes

Prioritize indexes on:

- `user_id`.
- `connection_id`.
- `provider_item_id`.
- `global_content_id`.
- `content_type`.
- `created_at`.
- `updated_at`.
- `subscription_status`.
- `expiry_at`.
- `external_content_id`.
- `epg_channel_id`.
- Frequently queried search fields.

Use composite indexes based on actual query patterns.

Do not add indexes indiscriminately because they increase write costs.

---

# 15. Supabase Security Architecture

Security must be designed before application development, not added after release.

## 15.1 Authentication

Support:

- Email and password.
- Email verification.
- Password reset.
- Google sign-in where required.
- Apple sign-in where required.
- Guest access.
- Account deletion.

## 15.2 Row Level Security

Enable RLS on all user-owned tables.

Example policies:

- Users can read their own profile.
- Users can update allowed profile fields.
- Users can access their own connections.
- Users can access their own watch history.
- Users can access their own favorites.
- Users cannot read another user's private provider records.
- Users cannot grant themselves subscriptions.
- Users cannot modify administrative roles.
- Users cannot modify global configuration.

Global catalog information can be readable according to the chosen publication and access policy.

## 15.3 Administrative Security

Implement role-based access control.

Suggested roles:

| Role | Permissions |
|---|---|
| Super Admin | Full platform control |
| Admin | General management |
| Content Manager | Catalog and home screen |
| Subscription Manager | Plans and subscriptions |
| Marketing Manager | Ads and promotions |
| Support Agent | User support |
| Analyst | Read-only analytics |

Use permission-specific authorization, not simply an `is_admin` flag.

## 15.4 Sensitive Provider Credentials

Xtream usernames/passwords, Stalker session tokens, and other provider secrets must be protected.

Requirements:

- Never expose the Supabase service-role key.
- Never store credentials in public catalog tables.
- Do not expose secret values through normal admin queries.
- Encrypt secrets using an appropriate server-side cryptographic design.
- Keep encryption keys outside ordinary client-readable database records.
- Restrict decryption to trusted operations.
- Avoid writing credentials to logs.
- Delete secrets when a connection is removed, subject to retention requirements.

Where credentials must be submitted to an external provider, use a trusted Edge Function when client-side exposure would create an unacceptable security risk.

## 15.5 Additional Protection

- Rate limiting.
- Login abuse protection.
- Session revocation.
- Admin audit logs.
- Device management.
- Sensitive-operation validation.
- Secure transport.
- Database backup strategy.
- Dependency updates.
- Security testing.

---

# 16. Supabase Cost and Performance Strategy

## 16.1 Primary Objective

Neo 8K must not unnecessarily increase Supabase usage.

The platform stores information rather than media streams.

## 16.2 Operations That Must Not Happen

- No video upload to Supabase.
- No video proxying.
- No continuous stream relay.
- No unnecessary full catalog downloads.
- No individual database write for every second of playback.
- No repeated insertion of duplicate metadata.
- No excessive Realtime subscriptions.
- No unbounded synchronization jobs.
- No unnecessary image duplication.

## 16.3 Optimization Strategy

- Local-first catalog access.
- Bulk database operations.
- Pagination.
- Incremental updates.
- Database indexes.
- Batch history synchronization.
- Artwork caching.
- Efficient query selection.
- Reusable global metadata.
- Controlled Realtime subscriptions.
- Retention and cleanup jobs.
- Scheduled catalog synchronization.
- Usage monitoring.

## 16.4 Scalability

Start with a single Supabase project.

Scale through:

- Query optimization.
- Database indexes.
- Connection management.
- Efficient synchronization.
- Caching.
- Database capacity upgrades.
- Workload separation when justified.

Do not introduce Redis, Kafka or separate microservices without measured evidence that they are necessary.

---

# 17. Edge Functions and Background Operations

No separate always-running application backend is planned.

However, certain operations must execute in a trusted environment.

Supabase Edge Functions may handle:

1. Protected provider authentication.
2. Provider credential operations.
3. Payment verification.
4. Subscription entitlement updates.
5. Administrative operations.
6. Notification dispatch.
7. Scheduled catalog synchronization.
8. Secure provider synchronization.
9. Administrative reporting.
10. Sensitive configuration changes.

Database functions can handle atomic database operations.

Cron can schedule maintenance and supported synchronization jobs.

## 17.1 Background Processing Limitations

Edge Functions are not unlimited background workers.

They have execution and resource limits.

Therefore:

- Large imports must be split into batches.
- Every synchronization job must be resumable.
- Each batch must have a checkpoint.
- Failed jobs must be retryable.
- Jobs must be idempotent.
- Large operations must not depend on one long-running function invocation.

If a future requirement exceeds Supabase's managed execution capabilities, evaluate managed external processing rather than silently introducing a traditional application server.

---

# 18. Application Configuration and Remote Control

## 18.1 Configuration Structure

Every remote setting should have:

- Setting identifier.
- Data type.
- Default value.
- Current value.
- Description.
- Scope.
- Validation rules.
- Updated by.
- Updated at.
- Configuration version.

## 18.2 Configuration Categories

### Application

- App name.
- Logo.
- Splash screen.
- Theme.
- Languages.
- Default navigation.

### Content

- Live TV.
- Movies.
- Series.
- Categories.
- EPG.
- Featured sections.
- Home screen layout.

### Player

- Default playback settings.
- Player controls.
- Supported player modes.
- Retry configuration.
- Buffer preferences.

### Monetization

- Ads.
- Subscriptions.
- Promotions.
- Free trials.
- Referral settings.

### Account

- Guest access.
- Account registration.
- Device limits.
- Profile limits.
- History synchronization.

### Security

- Maintenance mode.
- Minimum app version.
- Session policy.
- Feature restrictions.

## 18.3 Remote Configuration Delivery

The Flutter app should:

1. Load the last valid configuration.
2. Fetch the latest configuration.
3. Validate the configuration.
4. Apply supported changes.
5. Subscribe to selected Realtime updates.
6. Save the last valid configuration locally.

If Supabase is temporarily unavailable, the application should continue with the last valid configuration, subject to security-sensitive entitlement checks.

---

# 19. Privacy, User Consent and Data Ownership

Neo 8K must provide transparent privacy controls.

Users should understand:

- Which provider information is stored.
- Whether history synchronization is enabled.
- Which viewing statistics are collected.
- How long information is retained.
- Whether promotional targeting is used.
- How to delete their account.
- How to disconnect providers.

Provide:

- Privacy policy.
- Terms of service.
- Data deletion.
- Data export where appropriate.
- History clearing.
- Analytics preferences.
- Advertising preferences.
- Provider disconnection.

The platform should collect only data needed for functionality, security, analytics and user-requested features.

User-specific viewing information must not be publicly accessible or casually exposed to support staff.

---

# 20. Supported Platforms

## Initial Target Platforms

### Android Mobile

- Android phones.
- Android tablets.
- Touch interface.
- Portrait and landscape.

### Android TV

- Android TV.
- Google TV.
- Remote navigation.
- D-pad support.
- Large-screen interface.
- TV player controls.

### iOS

- iPhone.
- iPad.
- Native playback support.
- iOS-compatible connection handling.

### Future Platforms

- Apple TV.
- Amazon Fire TV.
- Other Flutter-compatible platforms where native playback and distribution requirements can be met.

Each platform must have its own compatibility testing.

---

# 21. User Experience and Navigation

## 21.1 Mobile Navigation

Recommended bottom navigation:

1. Home.
2. Live TV.
3. Movies.
4. Series.
5. Profile.

Search should be accessible globally.

## 21.2 TV Navigation

Use a TV-friendly navigation structure:

- Home.
- Live TV.
- Movies.
- Series.
- Search.
- Providers.
- Settings.

Support focus states, directional navigation, remote controls and predictable back navigation.

## 21.3 Loading and Error States

Every module must handle:

- Loading.
- Empty results.
- Offline state.
- Expired provider.
- Invalid credentials.
- Synchronization failure.
- Playback failure.
- Subscription restriction.
- Maintenance mode.

Never show a blank screen when a provider fails.

Display useful, non-sensitive error messages and retry options.

---

# 22. Testing and Quality Assurance

## 22.1 Flutter Tests

- Unit tests.
- Provider adapter tests.
- Playlist parser tests.
- Catalog matching tests.
- Playback tests.
- Local database tests.
- Synchronization tests.
- Offline tests.
- UI tests.
- Device-specific tests.

## 22.2 React Admin Tests

- Authentication.
- Role permissions.
- User management.
- Subscription management.
- Feature flag management.
- Configuration publishing.
- Advertisement management.
- Catalog editing.
- Audit logging.

## 22.3 Supabase Tests

- RLS policies.
- Ownership isolation.
- Privilege escalation prevention.
- Database constraints.
- Index performance.
- Edge Function authorization.
- Secret handling.
- Backup and recovery.

## 22.4 IPTV Compatibility Tests

Create a provider compatibility matrix.

Test:

- Xtream authentication.
- M3U parsing.
- Stalker portal authorization.
- Multiple connections.
- Expired credentials.
- Invalid playlists.
- Large playlists.
- EPG.
- Playback URL resolution.
- Different codecs.
- Different network conditions.

Test only with authorized provider accounts and content.

## 22.5 Performance Testing

Measure:

- Application startup.
- Home screen rendering.
- Catalog loading.
- Search response.
- Channel switching.
- Playback initialization.
- Memory consumption.
- Local cache size.
- Supabase database usage.
- Synchronization time.

Performance goals should be measured on representative low-end and high-end devices rather than treated as guaranteed numbers.

---

# 23. Failure Handling and Reliability

The application should remain usable even when some services fail.

Examples:

| Failure | Expected behavior |
|---|---|
| Supabase unavailable | Use cached non-sensitive information |
| One provider unavailable | Other providers remain usable |
| Invalid provider credentials | Show reconnect option |
| Catalog sync fails | Keep previous catalog |
| Artwork unavailable | Show placeholder |
| History sync fails | Queue locally |
| EPG unavailable | Continue channel playback |
| Subscription verification fails | Apply secure fallback policy |
| Invalid remote configuration | Keep last valid configuration |
| Playback URL expires | Resolve a fresh authorized URL |

Never delete an existing working catalog just because a synchronization operation failed.

---

# 24. Development Structure

## 24.1 GitHub Repository Structure

Recommended monorepo:

```text
neo8k/
│
├── apps/
│   │
│   ├── mobile/
│   │   ├── lib/
│   │   │   ├── core/
│   │   │   ├── config/
│   │   │   ├── routing/
│   │   │   ├── theme/
│   │   │   ├── providers/
│   │   │   ├── database/
│   │   │   ├── services/
│   │   │   ├── features/
│   │   │   │   ├── auth/
│   │   │   │   ├── home/
│   │   │   │   ├── live_tv/
│   │   │   │   ├── movies/
│   │   │   │   ├── series/
│   │   │   │   ├── search/
│   │   │   │   ├── player/
│   │   │   │   ├── favorites/
│   │   │   │   ├── history/
│   │   │   │   ├── profiles/
│   │   │   │   ├── subscriptions/
│   │   │   │   └── settings/
│   │   │   └── main.dart
│   │   │
│   │   └── test/
│   │
│   └── admin/
│       ├── src/
│       │   ├── components/
│       │   ├── layouts/
│       │   ├── pages/
│       │   ├── modules/
│       │   │   ├── dashboard/
│       │   │   ├── users/
│       │   │   ├── providers/
│       │   │   ├── catalog/
│       │   │   ├── subscriptions/
│       │   │   ├── advertisements/
│       │   │   ├── analytics/
│       │   │   ├── settings/
│       │   │   ├── notifications/
│       │   │   ├── devices/
│       │   │   └── support/
│       │   ├── services/
│       │   ├── hooks/
│       │   ├── permissions/
│       │   └── App.tsx
│       │
│       └── tests/
│
├── supabase/
│   ├── migrations/
│   ├── functions/
│   ├── seed.sql
│   ├── config.toml
│   └── tests/
│
├── docs/
│   ├── product/
│   ├── architecture/
│   ├── database/
│   ├── security/
│   ├── provider-adapters/
│   ├── api-contracts/
│   ├── admin/
│   ├── mobile/
│   ├── testing/
│   └── deployment/
│
├── scripts/
│
└── README.md
```

## 24.2 Development Standards

- Feature-based architecture.
- Reusable components.
- Typed database models.
- Centralized configuration.
- Consistent error handling.
- Secure credential management.
- Clear repository boundaries.
- Database migrations for every schema change.
- Documented Edge Functions.
- Unit tests.
- Integration tests.
- Git-based release management.

## 24.3 Shared Database Contract

React and Flutter must use the same database definitions.

Use Supabase-generated TypeScript and Dart models where practical.

Do not independently invent different interpretations of the same database field.

---

# 25. Complete Development Roadmap

## Phase 1 — Product Foundation

- Finalize product requirements.
- Establish Supabase project.
- Configure environments.
- Design database schema.
- Define user roles.
- Implement authentication.
- Configure RLS.
- Build base React admin.
- Build base Flutter application.

**Deliverable:** Secure working foundation.

## Phase 2 — Provider Engine

- Design provider interface.
- Implement Xtream adapter.
- Implement M3U adapter.
- Implement Stalker adapter.
- Implement connection management.
- Implement connection testing.
- Implement catalog parsing.
- Implement playback resolution.

**Deliverable:** Users can connect supported IPTV providers and play authorized content.

## Phase 3 — Catalog Architecture

- Global channel catalog.
- Global movie catalog.
- Global series catalog.
- Provider mapping.
- Content matching.
- Category mapping.
- EPG.
- User availability.
- Synchronization system.

**Deliverable:** Unified catalog with user-specific content.

## Phase 4 — Core Flutter Experience

- Home screen.
- Live TV.
- Movies.
- Series.
- Universal search.
- Media player.
- Favorites.
- Watch history.
- Local caching.

**Deliverable:** Complete basic streaming application.

## Phase 5 — Admin Control Center

- User management.
- Provider management.
- Catalog management.
- Home screen builder.
- Application settings.
- Feature flags.
- Remote configuration.
- Device management.

**Deliverable:** Administrators can manage the main application experience.

## Phase 6 — Business System

- Subscription plans.
- Entitlements.
- Payments.
- Advertisements.
- Promotions.
- Coupons.
- Referrals.
- Notification center.

**Deliverable:** Monetization-ready platform.

## Phase 7 — Analytics and Advanced Features

- Watch statistics.
- User activity.
- Provider health.
- Recommendations.
- Advanced search.
- Multi-profile.
- Smart failover.
- Support center.

**Deliverable:** Advanced Neo 8K ecosystem.

## Phase 8 — Production Readiness

- Security audit.
- Database optimization.
- Provider compatibility testing.
- Device testing.
- Performance testing.
- Privacy compliance.
- Backup verification.
- App store preparation.
- Production deployment.

**Deliverable:** Production-ready Neo 8K.

---

# 26. Project Acceptance Criteria

Neo 8K should not be considered complete simply because its screens look finished.

The following criteria must be satisfied.

### Provider Integration

- Supported providers can be connected.
- Invalid connections show useful errors.
- Multiple connections work independently.
- Provider data is normalized.
- Provider credentials are protected.
- Authorized streams play directly.

### Catalog

- Global catalog works.
- Provider mappings work.
- Duplicate metadata is controlled.
- User-specific availability works.
- Unavailable content is not shown as playable.
- Synchronization can resume after failure.

### Flutter

- Live TV works.
- Movies work.
- Series work.
- Search works.
- Player controls work.
- Favorites work.
- History works.
- Local cache works.
- Offline fallback works.

### Admin

- User management works.
- Subscription management works.
- Feature switches work.
- Home screen configuration works.
- Advertisement management works.
- Catalog management works.
- Audit logging works.
- Admin permissions are enforced.

### Supabase

- RLS is tested.
- No cross-user data access is possible.
- Privileged keys are protected.
- Large catalogs are handled efficiently.
- Database queries are indexed.
- Backups and recovery are verified.

### Production

- Supported devices are tested.
- Application updates work.
- Crash reporting works.
- Provider failures are handled.
- Privacy requirements are implemented.
- App store requirements are satisfied.

---

# 27. Important Product and Business Considerations

## 27.1 IPTV Content Rights

Neo 8K is a player and management platform.

Any IPTV services, channels, movies and series that the platform itself supplies must be appropriately licensed or authorized.

Supporting a protocol does not mean that every provider or content source is legally authorized.

## 27.2 External Metadata Rights

Metadata, artwork, logos and trailers must be used according to the relevant source's licensing and API terms.

## 27.3 App Store Policies

Subscriptions, external payments, advertising and content access must comply with applicable Google Play and Apple App Store policies.

## 27.4 Provider Compatibility

Not every IPTV provider implements Xtream, Stalker or M3U in exactly the same way.

Maintain a provider compatibility matrix.

Support should be based on tested implementations, not protocol names alone.

## 27.5 Native Player Limitations

Different operating systems and devices support different codecs, audio formats and DRM systems.

Implement capability detection and meaningful fallbacks.

## 27.6 Privacy

Watching history and viewing statistics are personal user data.

Make data collection transparent and provide appropriate user controls.

---

# 28. Future Expansion

Once the main application is stable, consider:

- Dedicated Android TV application experience.
- Apple TV.
- Additional provider adapters.
- Advanced global content matching.
- Better personalized recommendations.
- Household profiles.
- Advanced EPG.
- Multi-language interface.
- More advertising integrations.
- Advanced analytics.
- Provider reliability comparison.
- Premium account features.
- Additional authorized content partnerships.
- White-label application configuration.

These should be added without compromising the original architecture.

---

# 29. Final Architecture Decisions

The following decisions define the intended project.

| Decision | Final direction |
|---|---|
| Product | Universal IPTV player and ecosystem |
| Mobile | Flutter |
| Administration | React + TypeScript |
| Backend infrastructure | Supabase |
| Separate Node backend | Not planned |
| Separate Python backend | Not planned |
| Database | Supabase PostgreSQL |
| Authentication | Supabase Auth |
| Server-side operations | Supabase Edge Functions |
| Video hosting | Not provided by Neo 8K |
| Video delivery | Direct from IPTV providers |
| Video processing | Not provided by Neo 8K |
| Catalog storage | Supabase |
| Global metadata | Shared catalog |
| Provider availability | User/connection-specific mappings |
| Watch history | Supabase + local cache |
| Favorites | Supabase + local cache |
| Performance | Local-first and incremental synchronization |
| Admin control | Centralized React dashboard |
| Monetization | Configurable subscriptions and ads |
| Security | RLS + RBAC + protected operations |
| Scaling | Optimize Supabase before adding infrastructure |

---

# 30. Final Product Vision

Neo 8K should become a universal, provider-independent IPTV player that combines the flexibility of multiple IPTV formats with the convenience of a modern streaming platform.

The user should not care which protocol their provider uses.

They should simply:

1. Open Neo 8K.
2. Add their authorized IPTV connection.
3. Allow the application to identify the provider.
4. Synchronize their catalog.
5. Browse live channels, movies and series.
6. Watch directly from their provider.
7. Save their history and preferences.
8. Continue watching on another device.
9. Upgrade their Neo subscription when they need additional features.

The administrator should be able to:

1. Manage all users.
2. Manage subscription plans.
3. Configure provider compatibility.
4. Control features.
5. Manage advertisements.
6. Publish promotions.
7. Customize the home screen.
8. Control content presentation.
9. Monitor platform usage.
10. Manage application configuration.
11. Send notifications.
12. Manage devices and access.
13. Analyze business performance.

All through one centralized React Admin Panel connected to the same Supabase project as the Flutter application.

## The fundamental rule of Neo 8K

**Supabase manages information. Flutter manages the user experience. IPTV providers deliver the video. React manages the entire platform.**

The architecture should remain lightweight, secure, modular, efficient and extensible.

The objective is not to build another IPTV player with a collection of screens.

The objective is to build a complete, remotely manageable, universal IPTV ecosystem that can evolve without requiring a fundamental architectural redesign.

---

**END OF MASTER PROJECT SPECIFICATION**

**Project Name:** Neo 8K  
**Architecture:** Supabase-Centric Universal IPTV Ecosystem  
**Primary Applications:** Flutter + React  
**Document Status:** Master Product Blueprint