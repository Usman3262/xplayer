export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      admin_permissions: {
        Row: {
          description: string
          key: string
          module: string
        }
        Insert: {
          description: string
          key: string
          module: string
        }
        Update: {
          description?: string
          key?: string
          module?: string
        }
        Relationships: []
      }
      admin_role_permissions: {
        Row: {
          permission_key: string
          role_id: string
        }
        Insert: {
          permission_key: string
          role_id: string
        }
        Update: {
          permission_key?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_role_permissions_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: false
            referencedRelation: "admin_permissions"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "admin_role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "admin_roles"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_roles: {
        Row: {
          created_at: string
          description: string | null
          id: string
          is_system: boolean
          key: string
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          is_system?: boolean
          key: string
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          is_system?: boolean
          key?: string
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      admin_user_roles: {
        Row: {
          created_at: string
          created_by: string | null
          is_active: boolean
          role_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          is_active?: boolean
          role_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          is_active?: boolean
          role_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_user_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "admin_roles"
            referencedColumns: ["id"]
          },
        ]
      }
      app_settings: {
        Row: {
          category: string
          default_value: Json
          description: string
          is_public: boolean
          key: string
          updated_at: string
          updated_by: string | null
          validation: Json
          value: Json
          value_type: string
        }
        Insert: {
          category: string
          default_value: Json
          description: string
          is_public?: boolean
          key: string
          updated_at?: string
          updated_by?: string | null
          validation?: Json
          value: Json
          value_type: string
        }
        Update: {
          category?: string
          default_value?: Json
          description?: string
          is_public?: boolean
          key?: string
          updated_at?: string
          updated_by?: string | null
          validation?: Json
          value?: Json
          value_type?: string
        }
        Relationships: []
      }
      app_themes: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          name: string
          tokens: Json
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          tokens: Json
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          tokens?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      app_versions: {
        Row: {
          latest_version: string | null
          min_version: string
          platform: string
          recommended_version: string | null
          release_notes: string | null
          update_url: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          latest_version?: string | null
          min_version?: string
          platform: string
          recommended_version?: string | null
          release_notes?: string | null
          update_url?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          latest_version?: string | null
          min_version?: string
          platform?: string
          recommended_version?: string | null
          release_notes?: string | null
          update_url?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      audit_logs: {
        Row: {
          action: string
          actor_id: string | null
          after: Json | null
          before: Json | null
          created_at: string
          entity: string
          entity_id: string | null
          id: number
          meta: Json | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          entity: string
          entity_id?: string | null
          id?: never
          meta?: Json | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          entity?: string
          entity_id?: string | null
          id?: never
          meta?: Json | null
        }
        Relationships: []
      }
      banners: {
        Row: {
          action_type: string
          action_value: string | null
          countries: string[] | null
          created_at: string
          cta_label: string | null
          ends_at: string | null
          id: string
          image_url: string
          image_url_tv: string | null
          is_enabled: boolean
          item_kind: string | null
          panel_item_id: string | null
          panel_key: string | null
          platforms: string[] | null
          requires_login: boolean
          sort_order: number
          starts_at: string | null
          subtitle: string | null
          title: string
          tmdb_id: number | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          action_type?: string
          action_value?: string | null
          countries?: string[] | null
          created_at?: string
          cta_label?: string | null
          ends_at?: string | null
          id?: string
          image_url: string
          image_url_tv?: string | null
          is_enabled?: boolean
          item_kind?: string | null
          panel_item_id?: string | null
          panel_key?: string | null
          platforms?: string[] | null
          requires_login?: boolean
          sort_order?: number
          starts_at?: string | null
          subtitle?: string | null
          title: string
          tmdb_id?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          action_type?: string
          action_value?: string | null
          countries?: string[] | null
          created_at?: string
          cta_label?: string | null
          ends_at?: string | null
          id?: string
          image_url?: string
          image_url_tv?: string | null
          is_enabled?: boolean
          item_kind?: string | null
          panel_item_id?: string | null
          panel_key?: string | null
          platforms?: string[] | null
          requires_login?: boolean
          sort_order?: number
          starts_at?: string | null
          subtitle?: string | null
          title?: string
          tmdb_id?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      config_versions: {
        Row: {
          notes: string | null
          published_at: string
          published_by: string | null
          snapshot: Json
          version: number
        }
        Insert: {
          notes?: string | null
          published_at?: string
          published_by?: string | null
          snapshot: Json
          version?: never
        }
        Update: {
          notes?: string | null
          published_at?: string
          published_by?: string | null
          snapshot?: Json
          version?: never
        }
        Relationships: []
      }
      countries: {
        Row: {
          code: string
          name: string
        }
        Insert: {
          code: string
          name: string
        }
        Update: {
          code?: string
          name?: string
        }
        Relationships: []
      }
      feature_flags: {
        Row: {
          description: string
          enabled: boolean
          ends_at: string | null
          is_public: boolean
          key: string
          max_app_version: string | null
          min_app_version: string | null
          name: string
          platforms: string[] | null
          starts_at: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          description: string
          enabled?: boolean
          ends_at?: string | null
          is_public?: boolean
          key: string
          max_app_version?: string | null
          min_app_version?: string | null
          name: string
          platforms?: string[] | null
          starts_at?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          description?: string
          enabled?: boolean
          ends_at?: string | null
          is_public?: boolean
          key?: string
          max_app_version?: string | null
          min_app_version?: string | null
          name?: string
          platforms?: string[] | null
          starts_at?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      feature_overrides: {
        Row: {
          created_at: string
          created_by: string | null
          enabled: boolean
          ends_at: string | null
          flag_key: string
          id: string
          starts_at: string | null
          target_type: string
          target_value: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          enabled: boolean
          ends_at?: string | null
          flag_key: string
          id?: string
          starts_at?: string | null
          target_type: string
          target_value: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          enabled?: boolean
          ends_at?: string | null
          flag_key?: string
          id?: string
          starts_at?: string | null
          target_type?: string
          target_value?: string
        }
        Relationships: [
          {
            foreignKeyName: "feature_overrides_flag_key_fkey"
            columns: ["flag_key"]
            isOneToOne: false
            referencedRelation: "feature_flags"
            referencedColumns: ["key"]
          },
        ]
      }
      genres: {
        Row: {
          id: number
          name: string
          slug: string
          tmdb_id: number | null
        }
        Insert: {
          id?: never
          name: string
          slug: string
          tmdb_id?: number | null
        }
        Update: {
          id?: never
          name?: string
          slug?: string
          tmdb_id?: number | null
        }
        Relationships: []
      }
      global_channels: {
        Row: {
          aliases: string[]
          category: string | null
          country: string | null
          created_at: string
          epg_channel_id: string | null
          id: string
          is_published: boolean
          language: string | null
          locked_fields: string[]
          logo_url: string | null
          name: string
          name_norm: string | null
          quality: string | null
          updated_at: string
        }
        Insert: {
          aliases?: string[]
          category?: string | null
          country?: string | null
          created_at?: string
          epg_channel_id?: string | null
          id?: string
          is_published?: boolean
          language?: string | null
          locked_fields?: string[]
          logo_url?: string | null
          name: string
          name_norm?: string | null
          quality?: string | null
          updated_at?: string
        }
        Update: {
          aliases?: string[]
          category?: string | null
          country?: string | null
          created_at?: string
          epg_channel_id?: string | null
          id?: string
          is_published?: boolean
          language?: string | null
          locked_fields?: string[]
          logo_url?: string | null
          name?: string
          name_norm?: string | null
          quality?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      global_episodes: {
        Row: {
          air_date: string | null
          episode_number: number
          id: string
          locked_fields: string[]
          name: string | null
          overview: string | null
          runtime_min: number | null
          season_id: string | null
          season_number: number
          series_id: string
          still_path: string | null
          updated_at: string
        }
        Insert: {
          air_date?: string | null
          episode_number: number
          id?: string
          locked_fields?: string[]
          name?: string | null
          overview?: string | null
          runtime_min?: number | null
          season_id?: string | null
          season_number: number
          series_id: string
          still_path?: string | null
          updated_at?: string
        }
        Update: {
          air_date?: string | null
          episode_number?: number
          id?: string
          locked_fields?: string[]
          name?: string | null
          overview?: string | null
          runtime_min?: number | null
          season_id?: string | null
          season_number?: number
          series_id?: string
          still_path?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "global_episodes_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "global_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "global_episodes_series_id_fkey"
            columns: ["series_id"]
            isOneToOne: false
            referencedRelation: "global_series"
            referencedColumns: ["id"]
          },
        ]
      }
      global_movies: {
        Row: {
          adult: boolean
          backdrop_path: string | null
          certification: string | null
          countries: string[] | null
          created_at: string
          credits: Json
          fetched_at: string | null
          id: string
          imdb_id: string | null
          is_published: boolean
          locked_fields: string[]
          logo_path: string | null
          metadata_source: string
          original_language: string | null
          original_title: string | null
          overview: string | null
          popularity: number | null
          poster_path: string | null
          rating: number | null
          release_date: string | null
          runtime_min: number | null
          tagline: string | null
          title: string
          title_norm: string | null
          tmdb_id: number | null
          trailer_youtube: string | null
          updated_at: string
          vote_count: number | null
          year: number | null
        }
        Insert: {
          adult?: boolean
          backdrop_path?: string | null
          certification?: string | null
          countries?: string[] | null
          created_at?: string
          credits?: Json
          fetched_at?: string | null
          id?: string
          imdb_id?: string | null
          is_published?: boolean
          locked_fields?: string[]
          logo_path?: string | null
          metadata_source?: string
          original_language?: string | null
          original_title?: string | null
          overview?: string | null
          popularity?: number | null
          poster_path?: string | null
          rating?: number | null
          release_date?: string | null
          runtime_min?: number | null
          tagline?: string | null
          title: string
          title_norm?: string | null
          tmdb_id?: number | null
          trailer_youtube?: string | null
          updated_at?: string
          vote_count?: number | null
          year?: number | null
        }
        Update: {
          adult?: boolean
          backdrop_path?: string | null
          certification?: string | null
          countries?: string[] | null
          created_at?: string
          credits?: Json
          fetched_at?: string | null
          id?: string
          imdb_id?: string | null
          is_published?: boolean
          locked_fields?: string[]
          logo_path?: string | null
          metadata_source?: string
          original_language?: string | null
          original_title?: string | null
          overview?: string | null
          popularity?: number | null
          poster_path?: string | null
          rating?: number | null
          release_date?: string | null
          runtime_min?: number | null
          tagline?: string | null
          title?: string
          title_norm?: string | null
          tmdb_id?: number | null
          trailer_youtube?: string | null
          updated_at?: string
          vote_count?: number | null
          year?: number | null
        }
        Relationships: []
      }
      global_seasons: {
        Row: {
          air_date: string | null
          episode_count: number | null
          id: string
          locked_fields: string[]
          name: string | null
          overview: string | null
          poster_path: string | null
          season_number: number
          series_id: string
          updated_at: string
        }
        Insert: {
          air_date?: string | null
          episode_count?: number | null
          id?: string
          locked_fields?: string[]
          name?: string | null
          overview?: string | null
          poster_path?: string | null
          season_number: number
          series_id: string
          updated_at?: string
        }
        Update: {
          air_date?: string | null
          episode_count?: number | null
          id?: string
          locked_fields?: string[]
          name?: string | null
          overview?: string | null
          poster_path?: string | null
          season_number?: number
          series_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "global_seasons_series_id_fkey"
            columns: ["series_id"]
            isOneToOne: false
            referencedRelation: "global_series"
            referencedColumns: ["id"]
          },
        ]
      }
      global_series: {
        Row: {
          adult: boolean
          backdrop_path: string | null
          certification: string | null
          countries: string[] | null
          created_at: string
          credits: Json
          episode_count: number | null
          fetched_at: string | null
          first_air_date: string | null
          id: string
          imdb_id: string | null
          is_published: boolean
          last_air_date: string | null
          locked_fields: string[]
          logo_path: string | null
          metadata_source: string
          original_language: string | null
          original_title: string | null
          overview: string | null
          popularity: number | null
          poster_path: string | null
          rating: number | null
          season_count: number | null
          status: string | null
          title: string
          title_norm: string | null
          tmdb_id: number | null
          trailer_youtube: string | null
          updated_at: string
          vote_count: number | null
          year: number | null
        }
        Insert: {
          adult?: boolean
          backdrop_path?: string | null
          certification?: string | null
          countries?: string[] | null
          created_at?: string
          credits?: Json
          episode_count?: number | null
          fetched_at?: string | null
          first_air_date?: string | null
          id?: string
          imdb_id?: string | null
          is_published?: boolean
          last_air_date?: string | null
          locked_fields?: string[]
          logo_path?: string | null
          metadata_source?: string
          original_language?: string | null
          original_title?: string | null
          overview?: string | null
          popularity?: number | null
          poster_path?: string | null
          rating?: number | null
          season_count?: number | null
          status?: string | null
          title: string
          title_norm?: string | null
          tmdb_id?: number | null
          trailer_youtube?: string | null
          updated_at?: string
          vote_count?: number | null
          year?: number | null
        }
        Update: {
          adult?: boolean
          backdrop_path?: string | null
          certification?: string | null
          countries?: string[] | null
          created_at?: string
          credits?: Json
          episode_count?: number | null
          fetched_at?: string | null
          first_air_date?: string | null
          id?: string
          imdb_id?: string | null
          is_published?: boolean
          last_air_date?: string | null
          locked_fields?: string[]
          logo_path?: string | null
          metadata_source?: string
          original_language?: string | null
          original_title?: string | null
          overview?: string | null
          popularity?: number | null
          poster_path?: string | null
          rating?: number | null
          season_count?: number | null
          status?: string | null
          title?: string
          title_norm?: string | null
          tmdb_id?: number | null
          trailer_youtube?: string | null
          updated_at?: string
          vote_count?: number | null
          year?: number | null
        }
        Relationships: []
      }
      home_section_items: {
        Row: {
          created_at: string
          deep_link: string | null
          id: string
          image_url: string | null
          item_kind: string
          match_title: string | null
          panel_item_id: string | null
          panel_key: string | null
          section_id: string
          sort_order: number
          title: string | null
          tmdb_id: number | null
        }
        Insert: {
          created_at?: string
          deep_link?: string | null
          id?: string
          image_url?: string | null
          item_kind: string
          match_title?: string | null
          panel_item_id?: string | null
          panel_key?: string | null
          section_id: string
          sort_order?: number
          title?: string | null
          tmdb_id?: number | null
        }
        Update: {
          created_at?: string
          deep_link?: string | null
          id?: string
          image_url?: string | null
          item_kind?: string
          match_title?: string | null
          panel_item_id?: string | null
          panel_key?: string | null
          section_id?: string
          sort_order?: number
          title?: string | null
          tmdb_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "home_section_items_section_id_fkey"
            columns: ["section_id"]
            isOneToOne: false
            referencedRelation: "home_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      home_sections: {
        Row: {
          content_kind: string | null
          countries: string[] | null
          created_at: string
          ends_at: string | null
          id: string
          is_enabled: boolean
          item_limit: number
          layout: string
          params: Json
          platforms: string[] | null
          requires_login: boolean
          section_type: string
          sort_order: number
          source: string
          starts_at: string | null
          subtitle: string | null
          title: string
          top10_list_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          content_kind?: string | null
          countries?: string[] | null
          created_at?: string
          ends_at?: string | null
          id?: string
          is_enabled?: boolean
          item_limit?: number
          layout?: string
          params?: Json
          platforms?: string[] | null
          requires_login?: boolean
          section_type: string
          sort_order?: number
          source?: string
          starts_at?: string | null
          subtitle?: string | null
          title: string
          top10_list_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          content_kind?: string | null
          countries?: string[] | null
          created_at?: string
          ends_at?: string | null
          id?: string
          is_enabled?: boolean
          item_limit?: number
          layout?: string
          params?: Json
          platforms?: string[] | null
          requires_login?: boolean
          section_type?: string
          sort_order?: number
          source?: string
          starts_at?: string | null
          subtitle?: string | null
          title?: string
          top10_list_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "home_sections_top10_fk"
            columns: ["top10_list_id"]
            isOneToOne: false
            referencedRelation: "top10_lists"
            referencedColumns: ["id"]
          },
        ]
      }
      languages: {
        Row: {
          code: string
          name: string
        }
        Insert: {
          code: string
          name: string
        }
        Update: {
          code?: string
          name?: string
        }
        Relationships: []
      }
      maintenance_windows: {
        Row: {
          created_at: string
          created_by: string | null
          ends_at: string
          id: string
          is_active: boolean
          message: string
          platforms: string[] | null
          starts_at: string
          title: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          ends_at: string
          id?: string
          is_active?: boolean
          message: string
          platforms?: string[] | null
          starts_at: string
          title: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          ends_at?: string
          id?: string
          is_active?: boolean
          message?: string
          platforms?: string[] | null
          starts_at?: string
          title?: string
        }
        Relationships: []
      }
      metadata_misses: {
        Row: {
          checked_at: string
          kind: string
          title_norm: string
          year: number
        }
        Insert: {
          checked_at?: string
          kind: string
          title_norm: string
          year?: number
        }
        Update: {
          checked_at?: string
          kind?: string
          title_norm?: string
          year?: number
        }
        Relationships: []
      }
      metadata_sync_state: {
        Row: {
          job: string
          last_error: string | null
          last_result: Json | null
          last_run_at: string | null
        }
        Insert: {
          job: string
          last_error?: string | null
          last_result?: Json | null
          last_run_at?: string | null
        }
        Update: {
          job?: string
          last_error?: string | null
          last_result?: Json | null
          last_run_at?: string | null
        }
        Relationships: []
      }
      movie_genres: {
        Row: {
          genre_id: number
          movie_id: string
        }
        Insert: {
          genre_id: number
          movie_id: string
        }
        Update: {
          genre_id?: number
          movie_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "movie_genres_genre_id_fkey"
            columns: ["genre_id"]
            isOneToOne: false
            referencedRelation: "genres"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "movie_genres_movie_id_fkey"
            columns: ["movie_id"]
            isOneToOne: false
            referencedRelation: "global_movies"
            referencedColumns: ["id"]
          },
        ]
      }
      onboarding_panel_types: {
        Row: {
          description: string | null
          fields: Json
          help_text: string | null
          icon: string | null
          is_enabled: boolean
          key: string
          label: string
          platforms: string[] | null
          sort_order: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          description?: string | null
          fields?: Json
          help_text?: string | null
          icon?: string | null
          is_enabled?: boolean
          key: string
          label: string
          platforms?: string[] | null
          sort_order?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          description?: string | null
          fields?: Json
          help_text?: string | null
          icon?: string | null
          is_enabled?: boolean
          key?: string
          label?: string
          platforms?: string[] | null
          sort_order?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          country: string | null
          created_at: string
          display_name: string | null
          id: string
          is_guest: boolean
          last_seen_at: string | null
          locale: string | null
          status: string
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          country?: string | null
          created_at?: string
          display_name?: string | null
          id: string
          is_guest?: boolean
          last_seen_at?: string | null
          locale?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          country?: string | null
          created_at?: string
          display_name?: string | null
          id?: string
          is_guest?: boolean
          last_seen_at?: string | null
          locale?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      series_genres: {
        Row: {
          genre_id: number
          series_id: string
        }
        Insert: {
          genre_id: number
          series_id: string
        }
        Update: {
          genre_id?: number
          series_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "series_genres_genre_id_fkey"
            columns: ["genre_id"]
            isOneToOne: false
            referencedRelation: "genres"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "series_genres_series_id_fkey"
            columns: ["series_id"]
            isOneToOne: false
            referencedRelation: "global_series"
            referencedColumns: ["id"]
          },
        ]
      }
      sports_competitions: {
        Row: {
          country: string | null
          created_at: string
          external_id: string | null
          external_source: string | null
          id: string
          is_enabled: boolean
          is_featured: boolean
          logo_url: string | null
          name: string
          season: string | null
          short_name: string | null
          sort_order: number
          sport: string
          updated_at: string
        }
        Insert: {
          country?: string | null
          created_at?: string
          external_id?: string | null
          external_source?: string | null
          id?: string
          is_enabled?: boolean
          is_featured?: boolean
          logo_url?: string | null
          name: string
          season?: string | null
          short_name?: string | null
          sort_order?: number
          sport?: string
          updated_at?: string
        }
        Update: {
          country?: string | null
          created_at?: string
          external_id?: string | null
          external_source?: string | null
          id?: string
          is_enabled?: boolean
          is_featured?: boolean
          logo_url?: string | null
          name?: string
          season?: string | null
          short_name?: string | null
          sort_order?: number
          sport?: string
          updated_at?: string
        }
        Relationships: []
      }
      sports_events: {
        Row: {
          assist: string | null
          created_at: string
          detail: string | null
          extra_minute: number | null
          id: string
          match_id: string
          minute: number
          player: string | null
          team_id: string | null
          type: string
        }
        Insert: {
          assist?: string | null
          created_at?: string
          detail?: string | null
          extra_minute?: number | null
          id?: string
          match_id: string
          minute: number
          player?: string | null
          team_id?: string | null
          type: string
        }
        Update: {
          assist?: string | null
          created_at?: string
          detail?: string | null
          extra_minute?: number | null
          id?: string
          match_id?: string
          minute?: number
          player?: string | null
          team_id?: string | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "sports_events_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "sports_matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sports_events_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "sports_teams"
            referencedColumns: ["id"]
          },
        ]
      }
      sports_lineups: {
        Row: {
          coach: string | null
          formation: string | null
          match_id: string
          players: Json
          team_id: string
          updated_at: string
        }
        Insert: {
          coach?: string | null
          formation?: string | null
          match_id: string
          players?: Json
          team_id: string
          updated_at?: string
        }
        Update: {
          coach?: string | null
          formation?: string | null
          match_id?: string
          players?: Json
          team_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sports_lineups_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "sports_matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sports_lineups_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "sports_teams"
            referencedColumns: ["id"]
          },
        ]
      }
      sports_match_channels: {
        Row: {
          channel_id: string | null
          channel_match: string | null
          country: string | null
          id: string
          match_id: string
          note: string | null
        }
        Insert: {
          channel_id?: string | null
          channel_match?: string | null
          country?: string | null
          id?: string
          match_id: string
          note?: string | null
        }
        Update: {
          channel_id?: string | null
          channel_match?: string | null
          country?: string | null
          id?: string
          match_id?: string
          note?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sports_match_channels_channel_id_fkey"
            columns: ["channel_id"]
            isOneToOne: false
            referencedRelation: "global_channels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sports_match_channels_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "sports_matches"
            referencedColumns: ["id"]
          },
        ]
      }
      sports_matches: {
        Row: {
          away_score: number | null
          away_team_id: string
          competition_id: string | null
          created_at: string
          external_id: string | null
          external_source: string | null
          home_score: number | null
          home_team_id: string
          id: string
          is_featured: boolean
          is_hidden: boolean
          kickoff_at: string
          minute: number | null
          round: string | null
          sport: string
          status: string
          updated_at: string
          venue: string | null
        }
        Insert: {
          away_score?: number | null
          away_team_id: string
          competition_id?: string | null
          created_at?: string
          external_id?: string | null
          external_source?: string | null
          home_score?: number | null
          home_team_id: string
          id?: string
          is_featured?: boolean
          is_hidden?: boolean
          kickoff_at: string
          minute?: number | null
          round?: string | null
          sport?: string
          status?: string
          updated_at?: string
          venue?: string | null
        }
        Update: {
          away_score?: number | null
          away_team_id?: string
          competition_id?: string | null
          created_at?: string
          external_id?: string | null
          external_source?: string | null
          home_score?: number | null
          home_team_id?: string
          id?: string
          is_featured?: boolean
          is_hidden?: boolean
          kickoff_at?: string
          minute?: number | null
          round?: string | null
          sport?: string
          status?: string
          updated_at?: string
          venue?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sports_matches_away_team_id_fkey"
            columns: ["away_team_id"]
            isOneToOne: false
            referencedRelation: "sports_teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sports_matches_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: false
            referencedRelation: "sports_competitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sports_matches_home_team_id_fkey"
            columns: ["home_team_id"]
            isOneToOne: false
            referencedRelation: "sports_teams"
            referencedColumns: ["id"]
          },
        ]
      }
      sports_standings: {
        Row: {
          competition_id: string
          drawn: number
          form: string | null
          goals_against: number
          goals_for: number
          group_name: string
          lost: number
          played: number
          points: number
          rank: number
          team_id: string
          updated_at: string
          won: number
        }
        Insert: {
          competition_id: string
          drawn?: number
          form?: string | null
          goals_against?: number
          goals_for?: number
          group_name?: string
          lost?: number
          played?: number
          points?: number
          rank: number
          team_id: string
          updated_at?: string
          won?: number
        }
        Update: {
          competition_id?: string
          drawn?: number
          form?: string | null
          goals_against?: number
          goals_for?: number
          group_name?: string
          lost?: number
          played?: number
          points?: number
          rank?: number
          team_id?: string
          updated_at?: string
          won?: number
        }
        Relationships: [
          {
            foreignKeyName: "sports_standings_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: false
            referencedRelation: "sports_competitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sports_standings_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "sports_teams"
            referencedColumns: ["id"]
          },
        ]
      }
      sports_sync_state: {
        Row: {
          cursor: Json
          last_error: string | null
          last_synced_at: string | null
          resource: string
          source: string
        }
        Insert: {
          cursor?: Json
          last_error?: string | null
          last_synced_at?: string | null
          resource: string
          source: string
        }
        Update: {
          cursor?: Json
          last_error?: string | null
          last_synced_at?: string | null
          resource?: string
          source?: string
        }
        Relationships: []
      }
      sports_teams: {
        Row: {
          country: string | null
          created_at: string
          external_id: string | null
          external_source: string | null
          id: string
          logo_url: string | null
          name: string
          short_name: string | null
          sport: string
          updated_at: string
        }
        Insert: {
          country?: string | null
          created_at?: string
          external_id?: string | null
          external_source?: string | null
          id?: string
          logo_url?: string | null
          name: string
          short_name?: string | null
          sport?: string
          updated_at?: string
        }
        Update: {
          country?: string | null
          created_at?: string
          external_id?: string | null
          external_source?: string | null
          id?: string
          logo_url?: string | null
          name?: string
          short_name?: string | null
          sport?: string
          updated_at?: string
        }
        Relationships: []
      }
      top10_items: {
        Row: {
          image_url: string | null
          item_kind: string
          list_id: string
          match_title: string | null
          panel_item_id: string | null
          panel_key: string | null
          rank: number
          title: string | null
          tmdb_id: number | null
        }
        Insert: {
          image_url?: string | null
          item_kind: string
          list_id: string
          match_title?: string | null
          panel_item_id?: string | null
          panel_key?: string | null
          rank: number
          title?: string | null
          tmdb_id?: number | null
        }
        Update: {
          image_url?: string | null
          item_kind?: string
          list_id?: string
          match_title?: string | null
          panel_item_id?: string | null
          panel_key?: string | null
          rank?: number
          title?: string | null
          tmdb_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "top10_items_list_id_fkey"
            columns: ["list_id"]
            isOneToOne: false
            referencedRelation: "top10_lists"
            referencedColumns: ["id"]
          },
        ]
      }
      top10_lists: {
        Row: {
          content_kind: string
          country: string | null
          created_at: string
          id: string
          is_enabled: boolean
          params: Json
          source: string
          title: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          content_kind: string
          country?: string | null
          created_at?: string
          id?: string
          is_enabled?: boolean
          params?: Json
          source?: string
          title: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          content_kind?: string
          country?: string | null
          created_at?: string
          id?: string
          is_enabled?: boolean
          params?: Json
          source?: string
          title?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      _other_active_super_admins: { Args: { p_user: string }; Returns: number }
      admin_audit_entities: { Args: never; Returns: string[] }
      admin_audit_logs: {
        Args: {
          p_action?: string
          p_entity?: string
          p_limit?: number
          p_offset?: number
          p_q?: string
          p_since?: string
        }
        Returns: {
          action: string
          actor_email: string
          actor_id: string
          after: Json
          before: Json
          created_at: string
          entity: string
          entity_id: string
          id: number
          meta: Json
        }[]
      }
      admin_config_status: { Args: never; Returns: Json }
      admin_dashboard_stats: { Args: never; Returns: Json }
      admin_find_user: { Args: { p_email: string }; Returns: string }
      admin_list_admins: {
        Args: never
        Returns: {
          added_at: string
          email: string
          is_active: boolean
          last_sign_in_at: string
          role_key: string
          role_name: string
          user_id: string
        }[]
      }
      admin_remove: { Args: { p_user: string }; Returns: undefined }
      admin_security_state: { Args: never; Returns: Json }
      admin_session: { Args: never; Returns: Json }
      admin_set_active: {
        Args: { p_active: boolean; p_user: string }
        Returns: undefined
      }
      admin_set_role: {
        Args: { p_role_key: string; p_user: string }
        Returns: undefined
      }
      bootstrap_super_admin: { Args: { p_email: string }; Returns: string }
      build_app_config_snapshot: { Args: never; Returns: Json }
      build_home_snapshot: { Args: never; Returns: Json }
      config_item_visible: {
        Args: {
          p_country: string
          p_now: string
          p_platform: string
          p_signed_in: boolean
          x: Json
        }
        Returns: boolean
      }
      get_app_config: {
        Args: {
          p_app_version?: string
          p_country?: string
          p_known_version?: number
          p_platform: string
        }
        Returns: Json
      }
      get_match: { Args: { p_id: string }; Returns: Json }
      get_matches: {
        Args: {
          p_competition?: string
          p_featured_only?: boolean
          p_limit?: number
          p_window?: string
        }
        Returns: Json
      }
      has_permission: { Args: { perm: string }; Returns: boolean }
      is_admin: { Args: never; Returns: boolean }
      log_audit: {
        Args: {
          p_action: string
          p_after?: Json
          p_before?: Json
          p_entity: string
          p_entity_id?: string
          p_meta?: Json
        }
        Returns: number
      }
      my_permissions: { Args: never; Returns: string[] }
      publish_app_config: { Args: { p_notes?: string }; Returns: number }
      search_catalog: {
        Args: { kinds?: string[]; max_results?: number; q: string }
        Returns: {
          id: string
          image: string
          kind: string
          score: number
          title: string
          year: number
        }[]
      }
      version_cmp: { Args: { a: string; b: string }; Returns: number }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
