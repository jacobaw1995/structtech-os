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
    PostgrestVersion: "14.4"
  }
  public: {
    Tables: {
      audit_leads: {
        Row: {
          answers: Json | null
          company: string | null
          contacted: boolean | null
          created_at: string | null
          crew_size: number | null
          email: string
          id: string
          monthly_leak: number | null
          name: string | null
          notes: string | null
          risk_level: string | null
          score: number | null
          source: string | null
          top_leaks: string[] | null
          trade: string | null
        }
        Insert: {
          answers?: Json | null
          company?: string | null
          contacted?: boolean | null
          created_at?: string | null
          crew_size?: number | null
          email: string
          id?: string
          monthly_leak?: number | null
          name?: string | null
          notes?: string | null
          risk_level?: string | null
          score?: number | null
          source?: string | null
          top_leaks?: string[] | null
          trade?: string | null
        }
        Update: {
          answers?: Json | null
          company?: string | null
          contacted?: boolean | null
          created_at?: string | null
          crew_size?: number | null
          email?: string
          id?: string
          monthly_leak?: number | null
          name?: string | null
          notes?: string | null
          risk_level?: string | null
          score?: number | null
          source?: string | null
          top_leaks?: string[] | null
          trade?: string | null
        }
        Relationships: []
      }
      audits: {
        Row: {
          answers: Json | null
          area_scores: Json | null
          created_at: string | null
          id: string
          prospect_id: string | null
          ranked_bottlenecks: Json | null
          recommended_tier: string | null
          total_pain_score: number | null
        }
        Insert: {
          answers?: Json | null
          area_scores?: Json | null
          created_at?: string | null
          id?: string
          prospect_id?: string | null
          ranked_bottlenecks?: Json | null
          recommended_tier?: string | null
          total_pain_score?: number | null
        }
        Update: {
          answers?: Json | null
          area_scores?: Json | null
          created_at?: string | null
          id?: string
          prospect_id?: string | null
          ranked_bottlenecks?: Json | null
          recommended_tier?: string | null
          total_pain_score?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "audits_prospect_id_fkey"
            columns: ["prospect_id"]
            isOneToOne: false
            referencedRelation: "prospects"
            referencedColumns: ["id"]
          },
        ]
      }
      client_roadmaps: {
        Row: {
          client_name: string
          company: string
          created_at: string
          crew_size: number | null
          history: Json
          id: string
          lead_id: string | null
          levels: Json
          org_id: string | null
          revenue_leak_monthly: number | null
          risk_level: string | null
          score: number | null
          status: string
          token: string
          trade: string | null
          updated_at: string
        }
        Insert: {
          client_name: string
          company: string
          created_at?: string
          crew_size?: number | null
          history?: Json
          id?: string
          lead_id?: string | null
          levels?: Json
          org_id?: string | null
          revenue_leak_monthly?: number | null
          risk_level?: string | null
          score?: number | null
          status?: string
          token?: string
          trade?: string | null
          updated_at?: string
        }
        Update: {
          client_name?: string
          company?: string
          created_at?: string
          crew_size?: number | null
          history?: Json
          id?: string
          lead_id?: string | null
          levels?: Json
          org_id?: string | null
          revenue_leak_monthly?: number | null
          risk_level?: string | null
          score?: number | null
          status?: string
          token?: string
          trade?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_roadmaps_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "audit_leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_roadmaps_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      deal_activity: {
        Row: {
          action: string
          created_at: string
          deal_id: string
          from_value: string | null
          id: string
          to_value: string | null
        }
        Insert: {
          action: string
          created_at?: string
          deal_id: string
          from_value?: string | null
          id?: string
          to_value?: string | null
        }
        Update: {
          action?: string
          created_at?: string
          deal_id?: string
          from_value?: string | null
          id?: string
          to_value?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "deal_activity_deal_id_fkey"
            columns: ["deal_id"]
            isOneToOne: false
            referencedRelation: "deals"
            referencedColumns: ["id"]
          },
        ]
      }
      deal_notes: {
        Row: {
          content: string
          created_at: string
          deal_id: string
          id: string
        }
        Insert: {
          content: string
          created_at?: string
          deal_id: string
          id?: string
        }
        Update: {
          content?: string
          created_at?: string
          deal_id?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "deal_notes_deal_id_fkey"
            columns: ["deal_id"]
            isOneToOne: false
            referencedRelation: "deals"
            referencedColumns: ["id"]
          },
        ]
      }
      deals: {
        Row: {
          closed_at: string | null
          company: string | null
          contact_name: string
          created_at: string
          crew_size: number | null
          email: string | null
          id: string
          lead_id: string | null
          lost_reason: string | null
          phone: string | null
          proposal_notes: string | null
          proposal_tier: string | null
          source: string | null
          stage: string
          trade: string | null
          updated_at: string
          value: number | null
        }
        Insert: {
          closed_at?: string | null
          company?: string | null
          contact_name: string
          created_at?: string
          crew_size?: number | null
          email?: string | null
          id?: string
          lead_id?: string | null
          lost_reason?: string | null
          phone?: string | null
          proposal_notes?: string | null
          proposal_tier?: string | null
          source?: string | null
          stage?: string
          trade?: string | null
          updated_at?: string
          value?: number | null
        }
        Update: {
          closed_at?: string | null
          company?: string | null
          contact_name?: string
          created_at?: string
          crew_size?: number | null
          email?: string | null
          id?: string
          lead_id?: string | null
          lost_reason?: string | null
          phone?: string | null
          proposal_notes?: string | null
          proposal_tier?: string | null
          source?: string | null
          stage?: string
          trade?: string | null
          updated_at?: string
          value?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "deals_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "audit_leads"
            referencedColumns: ["id"]
          },
        ]
      }
      engagement_checkins: {
        Row: {
          created_at: string
          engagement_id: string
          id: string
          level_id: string | null
          notes: string | null
          org_id: string | null
          scheduled_at: string
          status: string
          title: string
        }
        Insert: {
          created_at?: string
          engagement_id: string
          id?: string
          level_id?: string | null
          notes?: string | null
          org_id?: string | null
          scheduled_at: string
          status?: string
          title: string
        }
        Update: {
          created_at?: string
          engagement_id?: string
          id?: string
          level_id?: string | null
          notes?: string | null
          org_id?: string | null
          scheduled_at?: string
          status?: string
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "engagement_checkins_engagement_id_fkey"
            columns: ["engagement_id"]
            isOneToOne: false
            referencedRelation: "engagements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagement_checkins_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "engagement_levels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagement_checkins_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      engagement_levels: {
        Row: {
          actual_end: string | null
          actual_start: string | null
          area: string | null
          created_at: string
          depends_on_level_id: string | null
          engagement_id: string
          id: string
          level_no: number
          org_id: string | null
          planned_end: string | null
          planned_start: string | null
          sort_order: number
          status: string
          title: string
          why: string | null
        }
        Insert: {
          actual_end?: string | null
          actual_start?: string | null
          area?: string | null
          created_at?: string
          depends_on_level_id?: string | null
          engagement_id: string
          id?: string
          level_no: number
          org_id?: string | null
          planned_end?: string | null
          planned_start?: string | null
          sort_order?: number
          status?: string
          title: string
          why?: string | null
        }
        Update: {
          actual_end?: string | null
          actual_start?: string | null
          area?: string | null
          created_at?: string
          depends_on_level_id?: string | null
          engagement_id?: string
          id?: string
          level_no?: number
          org_id?: string | null
          planned_end?: string | null
          planned_start?: string | null
          sort_order?: number
          status?: string
          title?: string
          why?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "engagement_levels_depends_on_level_id_fkey"
            columns: ["depends_on_level_id"]
            isOneToOne: false
            referencedRelation: "engagement_levels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagement_levels_engagement_id_fkey"
            columns: ["engagement_id"]
            isOneToOne: false
            referencedRelation: "engagements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagement_levels_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      engagement_milestones: {
        Row: {
          body: string
          completed_at: string | null
          created_at: string
          id: string
          is_win_condition: boolean
          level_id: string
          org_id: string | null
          owner: string
          sort_order: number
          status: string
        }
        Insert: {
          body: string
          completed_at?: string | null
          created_at?: string
          id?: string
          is_win_condition?: boolean
          level_id: string
          org_id?: string | null
          owner: string
          sort_order?: number
          status?: string
        }
        Update: {
          body?: string
          completed_at?: string | null
          created_at?: string
          id?: string
          is_win_condition?: boolean
          level_id?: string
          org_id?: string | null
          owner?: string
          sort_order?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "engagement_milestones_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "engagement_levels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagement_milestones_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      engagements: {
        Row: {
          created_at: string
          deal_id: string
          id: string
          org_id: string | null
          roadmap_id: string | null
          start_date: string | null
          status: string
          target_end_date: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          deal_id: string
          id?: string
          org_id?: string | null
          roadmap_id?: string | null
          start_date?: string | null
          status?: string
          target_end_date?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          deal_id?: string
          id?: string
          org_id?: string | null
          roadmap_id?: string | null
          start_date?: string | null
          status?: string
          target_end_date?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "engagements_deal_id_fkey"
            columns: ["deal_id"]
            isOneToOne: true
            referencedRelation: "deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagements_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagements_roadmap_id_fkey"
            columns: ["roadmap_id"]
            isOneToOne: false
            referencedRelation: "client_roadmaps"
            referencedColumns: ["id"]
          },
        ]
      }
      follow_ups: {
        Row: {
          body: string
          created_at: string
          deal_id: string
          id: string
          send_at: string
          sent_at: string | null
          status: string
          subject: string
          to_email: string
        }
        Insert: {
          body: string
          created_at?: string
          deal_id: string
          id?: string
          send_at: string
          sent_at?: string | null
          status?: string
          subject: string
          to_email: string
        }
        Update: {
          body?: string
          created_at?: string
          deal_id?: string
          id?: string
          send_at?: string
          sent_at?: string | null
          status?: string
          subject?: string
          to_email?: string
        }
        Relationships: [
          {
            foreignKeyName: "follow_ups_deal_id_fkey"
            columns: ["deal_id"]
            isOneToOne: false
            referencedRelation: "deals"
            referencedColumns: ["id"]
          },
        ]
      }
      lead_activity: {
        Row: {
          action: Database["public"]["Enums"]["lead_activity_action"]
          actor_id: string
          created_at: string
          from_value: string | null
          id: string
          lead_id: string
          to_value: string | null
        }
        Insert: {
          action: Database["public"]["Enums"]["lead_activity_action"]
          actor_id: string
          created_at?: string
          from_value?: string | null
          id?: string
          lead_id: string
          to_value?: string | null
        }
        Update: {
          action?: Database["public"]["Enums"]["lead_activity_action"]
          actor_id?: string
          created_at?: string
          from_value?: string | null
          id?: string
          lead_id?: string
          to_value?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_activity_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_activity_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
        ]
      }
      lead_appointments: {
        Row: {
          cancelled_at: string | null
          completed_at: string | null
          created_at: string
          duration_minutes: number
          id: string
          lead_id: string
          notes: string | null
          scheduled_at: string
          status: string
          title: string | null
        }
        Insert: {
          cancelled_at?: string | null
          completed_at?: string | null
          created_at?: string
          duration_minutes?: number
          id?: string
          lead_id: string
          notes?: string | null
          scheduled_at: string
          status?: string
          title?: string | null
        }
        Update: {
          cancelled_at?: string | null
          completed_at?: string | null
          created_at?: string
          duration_minutes?: number
          id?: string
          lead_id?: string
          notes?: string | null
          scheduled_at?: string
          status?: string
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_appointments_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
        ]
      }
      lead_notes: {
        Row: {
          author_id: string
          content: string
          created_at: string
          id: string
          lead_id: string
        }
        Insert: {
          author_id: string
          content: string
          created_at?: string
          id?: string
          lead_id: string
        }
        Update: {
          author_id?: string
          content?: string
          created_at?: string
          id?: string
          lead_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_notes_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_notes_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
        ]
      }
      leads: {
        Row: {
          cell_phone: string | null
          city: string | null
          claim_locked: boolean
          closed_at: string | null
          company_name: string | null
          created_at: string
          email: string | null
          first_name: string | null
          id: string
          intake_checklist: Json
          last_contacted_at: string | null
          last_name: string | null
          lost_reason: string | null
          name: string
          owner_id: string | null
          phone: string | null
          proposal_sent_at: string | null
          quote_presented_at: string | null
          referral_name: string | null
          scope_ordered_at: string | null
          secondary_phone: string | null
          service_city: string | null
          service_state: string | null
          service_street_address: string | null
          service_zip: string | null
          site_visit_complete_at: string | null
          source: Database["public"]["Enums"]["lead_source"]
          stage: Database["public"]["Enums"]["lead_stage"]
          state: string | null
          status: Database["public"]["Enums"]["lead_status"]
          street_address: string | null
          updated_at: string
          value: number | null
          zip: string | null
        }
        Insert: {
          cell_phone?: string | null
          city?: string | null
          claim_locked?: boolean
          closed_at?: string | null
          company_name?: string | null
          created_at?: string
          email?: string | null
          first_name?: string | null
          id?: string
          intake_checklist?: Json
          last_contacted_at?: string | null
          last_name?: string | null
          lost_reason?: string | null
          name: string
          owner_id?: string | null
          phone?: string | null
          proposal_sent_at?: string | null
          quote_presented_at?: string | null
          referral_name?: string | null
          scope_ordered_at?: string | null
          secondary_phone?: string | null
          service_city?: string | null
          service_state?: string | null
          service_street_address?: string | null
          service_zip?: string | null
          site_visit_complete_at?: string | null
          source?: Database["public"]["Enums"]["lead_source"]
          stage?: Database["public"]["Enums"]["lead_stage"]
          state?: string | null
          status?: Database["public"]["Enums"]["lead_status"]
          street_address?: string | null
          updated_at?: string
          value?: number | null
          zip?: string | null
        }
        Update: {
          cell_phone?: string | null
          city?: string | null
          claim_locked?: boolean
          closed_at?: string | null
          company_name?: string | null
          created_at?: string
          email?: string | null
          first_name?: string | null
          id?: string
          intake_checklist?: Json
          last_contacted_at?: string | null
          last_name?: string | null
          lost_reason?: string | null
          name?: string
          owner_id?: string | null
          phone?: string | null
          proposal_sent_at?: string | null
          quote_presented_at?: string | null
          referral_name?: string | null
          scope_ordered_at?: string | null
          secondary_phone?: string | null
          service_city?: string | null
          service_state?: string | null
          service_street_address?: string | null
          service_zip?: string | null
          site_visit_complete_at?: string | null
          source?: Database["public"]["Enums"]["lead_source"]
          stage?: Database["public"]["Enums"]["lead_stage"]
          state?: string | null
          status?: Database["public"]["Enums"]["lead_status"]
          street_address?: string | null
          updated_at?: string
          value?: number | null
          zip?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "leads_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      org_invites: {
        Row: {
          accepted_at: string | null
          created_at: string
          email: string
          id: string
          org_id: string
          role: string
          token: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          email: string
          id?: string
          org_id: string
          role?: string
          token?: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          email?: string
          id?: string
          org_id?: string
          role?: string
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "org_invites_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      org_invoices: {
        Row: {
          amount: number
          created_at: string
          due_date: string | null
          id: string
          kind: string
          label: string
          org_id: string
          paid_at: string | null
          status: string
        }
        Insert: {
          amount: number
          created_at?: string
          due_date?: string | null
          id?: string
          kind?: string
          label: string
          org_id: string
          paid_at?: string | null
          status?: string
        }
        Update: {
          amount?: number
          created_at?: string
          due_date?: string | null
          id?: string
          kind?: string
          label?: string
          org_id?: string
          paid_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "org_invoices_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      org_members: {
        Row: {
          created_at: string
          full_name: string | null
          org_id: string
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          full_name?: string | null
          org_id: string
          role?: string
          user_id: string
        }
        Update: {
          created_at?: string
          full_name?: string | null
          org_id?: string
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "org_members_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      org_systems: {
        Row: {
          created_at: string
          description: string | null
          id: string
          name: string
          org_id: string
          sort: number | null
          status: string
          url: string | null
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          name: string
          org_id: string
          sort?: number | null
          status?: string
          url?: string | null
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          name?: string
          org_id?: string
          sort?: number | null
          status?: string
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_systems_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          deal_id: string | null
          id: string
          name: string
          tenant_type: string
          trade: string | null
        }
        Insert: {
          created_at?: string
          deal_id?: string | null
          id?: string
          name: string
          tenant_type?: string
          trade?: string | null
        }
        Update: {
          created_at?: string
          deal_id?: string | null
          id?: string
          name?: string
          tenant_type?: string
          trade?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organizations_deal_id_fkey"
            columns: ["deal_id"]
            isOneToOne: false
            referencedRelation: "deals"
            referencedColumns: ["id"]
          },
        ]
      }
      pipeline_invites: {
        Row: {
          accepted_at: string | null
          created_at: string
          created_by: string | null
          email: string
          id: string
          role: Database["public"]["Enums"]["pipeline_user_role"]
          token: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          created_by?: string | null
          email: string
          id?: string
          role?: Database["public"]["Enums"]["pipeline_user_role"]
          token?: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          created_by?: string | null
          email?: string
          id?: string
          role?: Database["public"]["Enums"]["pipeline_user_role"]
          token?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          email: string
          full_name: string
          id: string
          role: Database["public"]["Enums"]["pipeline_user_role"]
        }
        Insert: {
          created_at?: string
          email: string
          full_name: string
          id: string
          role?: Database["public"]["Enums"]["pipeline_user_role"]
        }
        Update: {
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          role?: Database["public"]["Enums"]["pipeline_user_role"]
        }
        Relationships: []
      }
      proposals: {
        Row: {
          audit_id: string | null
          created_at: string | null
          custom_notes: string | null
          id: string
          price: string | null
          prospect_id: string | null
          status: string | null
          tier: string | null
        }
        Insert: {
          audit_id?: string | null
          created_at?: string | null
          custom_notes?: string | null
          id?: string
          price?: string | null
          prospect_id?: string | null
          status?: string | null
          tier?: string | null
        }
        Update: {
          audit_id?: string | null
          created_at?: string | null
          custom_notes?: string | null
          id?: string
          price?: string | null
          prospect_id?: string | null
          status?: string | null
          tier?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "proposals_audit_id_fkey"
            columns: ["audit_id"]
            isOneToOne: false
            referencedRelation: "audits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "proposals_prospect_id_fkey"
            columns: ["prospect_id"]
            isOneToOne: false
            referencedRelation: "prospects"
            referencedColumns: ["id"]
          },
        ]
      }
      prospects: {
        Row: {
          business_type: string | null
          city: string | null
          company_name: string
          created_at: string | null
          email: string | null
          employee_count: number | null
          icp_score: number | null
          icp_verdict: string | null
          id: string
          leak_signals: string[] | null
          notes: string | null
          owner_name: string | null
          owner_operated: boolean | null
          phone: string | null
          serves_contractors: boolean | null
          stage: string | null
          state: string | null
          trade_type: string | null
          updated_at: string | null
          website: string | null
        }
        Insert: {
          business_type?: string | null
          city?: string | null
          company_name: string
          created_at?: string | null
          email?: string | null
          employee_count?: number | null
          icp_score?: number | null
          icp_verdict?: string | null
          id?: string
          leak_signals?: string[] | null
          notes?: string | null
          owner_name?: string | null
          owner_operated?: boolean | null
          phone?: string | null
          serves_contractors?: boolean | null
          stage?: string | null
          state?: string | null
          trade_type?: string | null
          updated_at?: string | null
          website?: string | null
        }
        Update: {
          business_type?: string | null
          city?: string | null
          company_name?: string
          created_at?: string | null
          email?: string | null
          employee_count?: number | null
          icp_score?: number | null
          icp_verdict?: string | null
          id?: string
          leak_signals?: string[] | null
          notes?: string | null
          owner_name?: string | null
          owner_operated?: boolean | null
          phone?: string | null
          serves_contractors?: boolean | null
          stage?: string | null
          state?: string | null
          trade_type?: string | null
          updated_at?: string | null
          website?: string | null
        }
        Relationships: []
      }
      staff_invites: {
        Row: {
          accepted_at: string | null
          created_at: string
          created_by: string | null
          email: string
          id: string
          role: string
          token: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          created_by?: string | null
          email: string
          id?: string
          role?: string
          token?: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          created_by?: string | null
          email?: string
          id?: string
          role?: string
          token?: string
        }
        Relationships: []
      }
      staff_users: {
        Row: {
          created_at: string
          email: string | null
          full_name: string | null
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          role?: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          role?: string
          user_id?: string
        }
        Relationships: []
      }
      structtech_state: {
        Row: {
          current_week: number | null
          id: string
          income_entries: Json | null
          os_data: Json | null
          task_state: Json | null
          updated_at: string | null
        }
        Insert: {
          current_week?: number | null
          id?: string
          income_entries?: Json | null
          os_data?: Json | null
          task_state?: Json | null
          updated_at?: string | null
        }
        Update: {
          current_week?: number | null
          id?: string
          income_entries?: Json | null
          os_data?: Json | null
          task_state?: Json | null
          updated_at?: string | null
        }
        Relationships: []
      }
      tenant_modules: {
        Row: {
          config: Json
          created_at: string
          enabled: boolean
          id: string
          module_key: string
          org_id: string
          updated_at: string
        }
        Insert: {
          config?: Json
          created_at?: string
          enabled?: boolean
          id?: string
          module_key: string
          org_id: string
          updated_at?: string
        }
        Update: {
          config?: Json
          created_at?: string
          enabled?: boolean
          id?: string
          module_key?: string
          org_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_modules_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      ticket_messages: {
        Row: {
          author_name: string
          content: string
          created_at: string
          id: string
          is_structtech: boolean
          ticket_id: string
        }
        Insert: {
          author_name: string
          content: string
          created_at?: string
          id?: string
          is_structtech?: boolean
          ticket_id: string
        }
        Update: {
          author_name?: string
          content?: string
          created_at?: string
          id?: string
          is_structtech?: boolean
          ticket_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ticket_messages_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "tickets"
            referencedColumns: ["id"]
          },
        ]
      }
      tickets: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          org_id: string
          priority: string
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          org_id: string
          priority?: string
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          org_id?: string
          priority?: string
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tickets_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_invite: {
        Args: { p_full_name?: string; p_token: string }
        Returns: string
      }
      accept_pipeline_invite: {
        Args: { p_full_name?: string; p_token: string }
        Returns: undefined
      }
      accept_staff_invite: {
        Args: { p_full_name?: string; p_token: string }
        Returns: undefined
      }
      add_org_member: {
        Args: {
          p_full_name?: string
          p_org_id: string
          p_role: string
          p_user_id: string
        }
        Returns: undefined
      }
      build_roadmap_levels: {
        Args: { p_answers: Json; p_crew: number }
        Returns: Json
      }
      create_engagement_from_roadmap: {
        Args: { p_deal_id: string }
        Returns: string
      }
      create_organization: {
        Args: { p_name: string; p_tenant_type: string; p_trade?: string }
        Returns: string
      }
      fetch_membership_context: {
        Args: never
        Returns: Database["public"]["CompositeTypes"]["membership_context"][]
        SetofOptions: {
          from: "*"
          to: "membership_context"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_organization: {
        Args: { p_org_id: string }
        Returns: {
          created_at: string
          deal_id: string | null
          id: string
          name: string
          tenant_type: string
          trade: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "organizations"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      generate_roadmap_for_lead: {
        Args: { p_lead_id: string }
        Returns: string
      }
      is_pipeline_manager: { Args: never; Returns: boolean }
      is_pipeline_user: { Args: never; Returns: boolean }
      is_platform_admin: { Args: never; Returns: boolean }
      is_staff: { Args: never; Returns: boolean }
      my_active_lead_count: { Args: never; Returns: number }
      my_avg_cycle_days: { Args: never; Returns: number }
      my_closes_this_month: { Args: never; Returns: number }
      my_open_pipeline_value: { Args: never; Returns: number }
      my_org_ids: { Args: never; Returns: string[] }
      my_win_rate: { Args: never; Returns: number }
      roadmap_playbook: { Args: { q: string }; Returns: Json }
      set_tenant_module: {
        Args: {
          p_config?: Json
          p_enabled?: boolean
          p_module_key: string
          p_org_id: string
        }
        Returns: string
      }
    }
    Enums: {
      lead_activity_action:
        | "created"
        | "stage_changed"
        | "status_changed"
        | "reassigned"
        | "value_set"
        | "edited"
      lead_source: "webhook" | "manual" | "referral"
      lead_stage:
        | "lead_captured"
        | "qualified"
        | "proposal_sent"
        | "negotiating"
        | "closed"
      lead_status: "active" | "closed_won" | "closed_lost"
      pipeline_user_role: "salesman" | "manager"
    }
    CompositeTypes: {
      membership_context: {
        org_id: string | null
        org_name: string | null
        tenant_type: string | null
        role: string | null
        entitled_modules: string[] | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      lead_activity_action: [
        "created",
        "stage_changed",
        "status_changed",
        "reassigned",
        "value_set",
        "edited",
      ],
      lead_source: ["webhook", "manual", "referral"],
      lead_stage: [
        "lead_captured",
        "qualified",
        "proposal_sent",
        "negotiating",
        "closed",
      ],
      lead_status: ["active", "closed_won", "closed_lost"],
      pipeline_user_role: ["salesman", "manager"],
    },
  },
} as const

