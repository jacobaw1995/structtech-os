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
          org_id: string | null
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
          org_id?: string | null
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
          org_id?: string | null
          risk_level?: string | null
          score?: number | null
          source?: string | null
          top_leaks?: string[] | null
          trade?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_leads_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
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
      check_ins: {
        Row: {
          blockers: string | null
          check_in_date: string
          created_at: string
          crew_name: string
          hours: number
          id: string
          materials_used: string | null
          org_id: string
          photos: string[]
          schedule_block_id: string | null
          updated_at: string
          work_order_id: string
        }
        Insert: {
          blockers?: string | null
          check_in_date?: string
          created_at?: string
          crew_name: string
          hours?: number
          id?: string
          materials_used?: string | null
          org_id: string
          photos?: string[]
          schedule_block_id?: string | null
          updated_at?: string
          work_order_id: string
        }
        Update: {
          blockers?: string | null
          check_in_date?: string
          created_at?: string
          crew_name?: string
          hours?: number
          id?: string
          materials_used?: string | null
          org_id?: string
          photos?: string[]
          schedule_block_id?: string | null
          updated_at?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "check_ins_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_ins_schedule_block_id_fkey"
            columns: ["schedule_block_id"]
            isOneToOne: false
            referencedRelation: "schedule_blocks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_ins_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
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
          actor_id: string | null
          created_at: string
          deal_id: string
          from_value: string | null
          id: string
          org_id: string | null
          to_value: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          deal_id: string
          from_value?: string | null
          id?: string
          org_id?: string | null
          to_value?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          deal_id?: string
          from_value?: string | null
          id?: string
          org_id?: string | null
          to_value?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "deal_activity_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_activity_deal_id_fkey"
            columns: ["deal_id"]
            isOneToOne: false
            referencedRelation: "deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_activity_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      deal_notes: {
        Row: {
          content: string
          created_at: string
          created_by: string | null
          deal_id: string
          id: string
          org_id: string | null
        }
        Insert: {
          content: string
          created_at?: string
          created_by?: string | null
          deal_id: string
          id?: string
          org_id?: string | null
        }
        Update: {
          content?: string
          created_at?: string
          created_by?: string | null
          deal_id?: string
          id?: string
          org_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "deal_notes_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_notes_deal_id_fkey"
            columns: ["deal_id"]
            isOneToOne: false
            referencedRelation: "deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_notes_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      deals: {
        Row: {
          archived_at: string | null
          billing_address: string | null
          closed_at: string | null
          company: string | null
          contact_name: string
          created_at: string
          crew_size: number | null
          email: string | null
          existing_roof_type: string[] | null
          first_name: string | null
          id: string
          intake_checklist: Json
          last_name: string | null
          lead_id: string | null
          lead_type: string | null
          lost_reason: string | null
          org_id: string | null
          owner_id: string | null
          phone: string | null
          project_address: string | null
          proposal_notes: string | null
          proposal_tier: string | null
          quote_presented_at: string | null
          referral_name: string | null
          remodel_or_new_construction: string | null
          roof_scope_ordered_at: string | null
          roof_type_requested: string[] | null
          secondary_phone: string | null
          service_address_city: string | null
          service_address_state: string | null
          service_address_street: string | null
          service_address_zip: string | null
          site_survey_complete_at: string | null
          source: string | null
          stage: string
          tags: string[] | null
          trade: string | null
          updated_at: string
          value: number | null
        }
        Insert: {
          archived_at?: string | null
          billing_address?: string | null
          closed_at?: string | null
          company?: string | null
          contact_name: string
          created_at?: string
          crew_size?: number | null
          email?: string | null
          existing_roof_type?: string[] | null
          first_name?: string | null
          id?: string
          intake_checklist?: Json
          last_name?: string | null
          lead_id?: string | null
          lead_type?: string | null
          lost_reason?: string | null
          org_id?: string | null
          owner_id?: string | null
          phone?: string | null
          project_address?: string | null
          proposal_notes?: string | null
          proposal_tier?: string | null
          quote_presented_at?: string | null
          referral_name?: string | null
          remodel_or_new_construction?: string | null
          roof_scope_ordered_at?: string | null
          roof_type_requested?: string[] | null
          secondary_phone?: string | null
          service_address_city?: string | null
          service_address_state?: string | null
          service_address_street?: string | null
          service_address_zip?: string | null
          site_survey_complete_at?: string | null
          source?: string | null
          stage?: string
          tags?: string[] | null
          trade?: string | null
          updated_at?: string
          value?: number | null
        }
        Update: {
          archived_at?: string | null
          billing_address?: string | null
          closed_at?: string | null
          company?: string | null
          contact_name?: string
          created_at?: string
          crew_size?: number | null
          email?: string | null
          existing_roof_type?: string[] | null
          first_name?: string | null
          id?: string
          intake_checklist?: Json
          last_name?: string | null
          lead_id?: string | null
          lead_type?: string | null
          lost_reason?: string | null
          org_id?: string | null
          owner_id?: string | null
          phone?: string | null
          project_address?: string | null
          proposal_notes?: string | null
          proposal_tier?: string | null
          quote_presented_at?: string | null
          referral_name?: string | null
          remodel_or_new_construction?: string | null
          roof_scope_ordered_at?: string | null
          roof_type_requested?: string[] | null
          secondary_phone?: string | null
          service_address_city?: string | null
          service_address_state?: string | null
          service_address_street?: string | null
          service_address_zip?: string | null
          site_survey_complete_at?: string | null
          source?: string | null
          stage?: string
          tags?: string[] | null
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
          {
            foreignKeyName: "deals_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deals_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
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
      estimate_line_items: {
        Row: {
          created_at: string
          description: string
          estimate_id: string
          id: string
          line_total: number | null
          org_id: string
          product_id: string | null
          quantity: number
          scope_key: string | null
          sort_order: number
          unit: string | null
          unit_price: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          description: string
          estimate_id: string
          id?: string
          line_total?: number | null
          org_id: string
          product_id?: string | null
          quantity?: number
          scope_key?: string | null
          sort_order?: number
          unit?: string | null
          unit_price?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string
          estimate_id?: string
          id?: string
          line_total?: number | null
          org_id?: string
          product_id?: string | null
          quantity?: number
          scope_key?: string | null
          sort_order?: number
          unit?: string | null
          unit_price?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "estimate_line_items_estimate_id_fkey"
            columns: ["estimate_id"]
            isOneToOne: false
            referencedRelation: "estimates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "estimate_line_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      estimate_number_counters: {
        Row: {
          next_number: number
          org_id: string
        }
        Insert: {
          next_number?: number
          org_id: string
        }
        Update: {
          next_number?: number
          org_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "estimate_number_counters_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      estimates: {
        Row: {
          build_mode: string
          company: string | null
          contact_name: string | null
          created_at: string
          deal_id: string
          email: string | null
          estimate_date: string | null
          estimate_number: string | null
          id: string
          notes_terms: string | null
          org_id: string
          phone: string | null
          pitch: string | null
          presented_at: string | null
          presented_total: number | null
          signed_at: string | null
          site_address: string | null
          squares: number | null
          status: string
          subtotal: number
          tax_amount: number | null
          tax_rate: number | null
          updated_at: string
          valid_until: string | null
        }
        Insert: {
          build_mode?: string
          company?: string | null
          contact_name?: string | null
          created_at?: string
          deal_id: string
          email?: string | null
          estimate_date?: string | null
          estimate_number?: string | null
          id?: string
          notes_terms?: string | null
          org_id: string
          phone?: string | null
          pitch?: string | null
          presented_at?: string | null
          presented_total?: number | null
          signed_at?: string | null
          site_address?: string | null
          squares?: number | null
          status?: string
          subtotal?: number
          tax_amount?: number | null
          tax_rate?: number | null
          updated_at?: string
          valid_until?: string | null
        }
        Update: {
          build_mode?: string
          company?: string | null
          contact_name?: string | null
          created_at?: string
          deal_id?: string
          email?: string | null
          estimate_date?: string | null
          estimate_number?: string | null
          id?: string
          notes_terms?: string | null
          org_id?: string
          phone?: string | null
          pitch?: string | null
          presented_at?: string | null
          presented_total?: number | null
          signed_at?: string | null
          site_address?: string | null
          squares?: number | null
          status?: string
          subtotal?: number
          tax_amount?: number | null
          tax_rate?: number | null
          updated_at?: string
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "estimates_deal_id_fkey"
            columns: ["deal_id"]
            isOneToOne: false
            referencedRelation: "deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "estimates_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
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
          org_id: string | null
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
          org_id?: string | null
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
          org_id?: string | null
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
          {
            foreignKeyName: "follow_ups_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
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
      material_items: {
        Row: {
          created_at: string
          id: string
          name: string
          org_id: string
          quantity: number
          ready_by: string | null
          sort_order: number
          updated_at: string
          work_order_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          org_id: string
          quantity?: number
          ready_by?: string | null
          sort_order?: number
          updated_at?: string
          work_order_id: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          org_id?: string
          quantity?: number
          ready_by?: string | null
          sort_order?: number
          updated_at?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "material_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "material_items_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      migration_bmr_activity_raw: {
        Row: {
          loaded_at: string
          old_id: string
          payload: Json
        }
        Insert: {
          loaded_at?: string
          old_id: string
          payload: Json
        }
        Update: {
          loaded_at?: string
          old_id?: string
          payload?: Json
        }
        Relationships: []
      }
      migration_bmr_id_map: {
        Row: {
          created_at: string
          entity: string
          new_id: string | null
          old_id: string
        }
        Insert: {
          created_at?: string
          entity: string
          new_id?: string | null
          old_id: string
        }
        Update: {
          created_at?: string
          entity?: string
          new_id?: string | null
          old_id?: string
        }
        Relationships: []
      }
      migration_bmr_leads_raw: {
        Row: {
          loaded_at: string
          old_id: string
          payload: Json
        }
        Insert: {
          loaded_at?: string
          old_id: string
          payload: Json
        }
        Update: {
          loaded_at?: string
          old_id?: string
          payload?: Json
        }
        Relationships: []
      }
      migration_bmr_notes_raw: {
        Row: {
          loaded_at: string
          old_id: string
          payload: Json
        }
        Insert: {
          loaded_at?: string
          old_id: string
          payload: Json
        }
        Update: {
          loaded_at?: string
          old_id?: string
          payload?: Json
        }
        Relationships: []
      }
      migration_bmr_users_raw: {
        Row: {
          loaded_at: string
          old_id: string
          payload: Json
        }
        Insert: {
          loaded_at?: string
          old_id: string
          payload: Json
        }
        Update: {
          loaded_at?: string
          old_id?: string
          payload?: Json
        }
        Relationships: []
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
      production_packets: {
        Row: {
          callouts: Json
          created_at: string
          id: string
          notes: string | null
          org_id: string
          updated_at: string
          work_order_id: string
        }
        Insert: {
          callouts?: Json
          created_at?: string
          id?: string
          notes?: string | null
          org_id: string
          updated_at?: string
          work_order_id: string
        }
        Update: {
          callouts?: Json
          created_at?: string
          id?: string
          notes?: string | null
          org_id?: string
          updated_at?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "production_packets_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "production_packets_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: true
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
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
      roadmap_items: {
        Row: {
          created_at: string
          feature: string
          id: string
          notes: string | null
          org_id: string
          phase: string
          section: string
          sort_order: number
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          feature: string
          id?: string
          notes?: string | null
          org_id: string
          phase: string
          section: string
          sort_order?: number
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          feature?: string
          id?: string
          notes?: string | null
          org_id?: string
          phase?: string
          section?: string
          sort_order?: number
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "roadmap_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "roadmap_items_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      schedule_blocks: {
        Row: {
          blocked: boolean
          blocked_reason: string | null
          created_at: string
          crew_name: string
          end_date: string
          id: string
          org_id: string
          start_date: string
          updated_at: string
          work_order_id: string
        }
        Insert: {
          blocked?: boolean
          blocked_reason?: string | null
          created_at?: string
          crew_name: string
          end_date: string
          id?: string
          org_id: string
          start_date: string
          updated_at?: string
          work_order_id: string
        }
        Update: {
          blocked?: boolean
          blocked_reason?: string | null
          created_at?: string
          crew_name?: string
          end_date?: string
          id?: string
          org_id?: string
          start_date?: string
          updated_at?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "schedule_blocks_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "schedule_blocks_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      signatures: {
        Row: {
          created_at: string
          estimate_id: string
          id: string
          org_id: string
          pdf_url: string | null
          sign_token: string | null
          signature_data: string
          signed_at: string
          signer_name: string
          signer_role: string
        }
        Insert: {
          created_at?: string
          estimate_id: string
          id?: string
          org_id: string
          pdf_url?: string | null
          sign_token?: string | null
          signature_data: string
          signed_at?: string
          signer_name: string
          signer_role: string
        }
        Update: {
          created_at?: string
          estimate_id?: string
          id?: string
          org_id?: string
          pdf_url?: string | null
          sign_token?: string | null
          signature_data?: string
          signed_at?: string
          signer_name?: string
          signer_role?: string
        }
        Relationships: [
          {
            foreignKeyName: "signatures_estimate_id_fkey"
            columns: ["estimate_id"]
            isOneToOne: false
            referencedRelation: "estimates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "signatures_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
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
      tracker_items: {
        Row: {
          archived_at: string | null
          assignee_id: string | null
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          org_id: string
          position: number
          priority: string
          project_id: string
          reported_by_org_id: string | null
          reported_by_profile_id: string | null
          resolved_at: string | null
          source: string
          status: string
          title: string
          type: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          assignee_id?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          org_id: string
          position?: number
          priority?: string
          project_id: string
          reported_by_org_id?: string | null
          reported_by_profile_id?: string | null
          resolved_at?: string | null
          source?: string
          status?: string
          title: string
          type?: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          assignee_id?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          org_id?: string
          position?: number
          priority?: string
          project_id?: string
          reported_by_org_id?: string | null
          reported_by_profile_id?: string | null
          resolved_at?: string | null
          source?: string
          status?: string
          title?: string
          type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tracker_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracker_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracker_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracker_items_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "tracker_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracker_items_reported_by_org_id_fkey"
            columns: ["reported_by_org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracker_items_reported_by_profile_id_fkey"
            columns: ["reported_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      tracker_projects: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          linked_org_id: string | null
          name: string
          org_id: string
          status: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          linked_org_id?: string | null
          name: string
          org_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          linked_org_id?: string | null
          name?: string
          org_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tracker_projects_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracker_projects_linked_org_id_fkey"
            columns: ["linked_org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracker_projects_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_activity: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          from_value: string | null
          id: string
          org_id: string
          to_value: string | null
          work_order_id: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          from_value?: string | null
          id?: string
          org_id: string
          to_value?: string | null
          work_order_id: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          from_value?: string | null
          id?: string
          org_id?: string
          to_value?: string | null
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_activity_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      work_orders: {
        Row: {
          created_at: string
          estimate_id: string
          id: string
          org_id: string
          sign_off_at: string | null
          sign_off_notes: string | null
          updated_at: string
          voided_at: string | null
        }
        Insert: {
          created_at?: string
          estimate_id: string
          id?: string
          org_id: string
          sign_off_at?: string | null
          sign_off_notes?: string | null
          updated_at?: string
          voided_at?: string | null
        }
        Update: {
          created_at?: string
          estimate_id?: string
          id?: string
          org_id?: string
          sign_off_at?: string | null
          sign_off_notes?: string | null
          updated_at?: string
          voided_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "work_orders_estimate_id_fkey"
            columns: ["estimate_id"]
            isOneToOne: true
            referencedRelation: "estimates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_org_id_fkey"
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
      add_check_in_photo: {
        Args: { p_check_in_id: string; p_photo_data_url: string }
        Returns: undefined
      }
      add_deal_note: {
        Args: { p_content: string; p_deal_id: string }
        Returns: string
      }
      add_estimate_line_item: {
        Args: {
          p_description: string
          p_estimate_id: string
          p_product_id?: string
          p_quantity?: number
          p_sort_order?: number
          p_unit?: string
          p_unit_price?: number
        }
        Returns: string
      }
      add_material_item: {
        Args: {
          p_name: string
          p_quantity?: number
          p_ready_by?: string
          p_sort_order?: number
          p_work_order_id: string
        }
        Returns: string
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
      add_production_packet_callout: {
        Args: {
          p_detail?: string
          p_label: string
          p_production_packet_id: string
        }
        Returns: string
      }
      add_schedule_block: {
        Args: {
          p_crew_name: string
          p_end_date: string
          p_start_date: string
          p_work_order_id: string
        }
        Returns: string
      }
      archive_deal: { Args: { p_deal_id: string }; Returns: undefined }
      archive_tracker_item: { Args: { p_item_id: string }; Returns: undefined }
      archive_tracker_project: {
        Args: { p_project_id: string }
        Returns: undefined
      }
      assign_deal_owner: {
        Args: { p_deal_id: string; p_owner_id?: string }
        Returns: undefined
      }
      build_roadmap_levels: {
        Args: { p_answers: Json; p_crew: number }
        Returns: Json
      }
      complete_site_survey: {
        Args: { p_completed_at?: string; p_deal_id: string }
        Returns: undefined
      }
      create_check_in: {
        Args: {
          p_blockers?: string
          p_check_in_date?: string
          p_crew_name: string
          p_hours?: number
          p_materials_used?: string
          p_schedule_block_id?: string
          p_work_order_id: string
        }
        Returns: string
      }
      create_deal: {
        Args: {
          p_billing_address?: string
          p_company?: string
          p_contact_name?: string
          p_crew_size?: number
          p_email?: string
          p_existing_roof_type?: string[]
          p_first_name?: string
          p_last_name?: string
          p_lead_type?: string
          p_org_id: string
          p_owner_id?: string
          p_phone?: string
          p_project_address?: string
          p_referral_name?: string
          p_remodel_or_new_construction?: string
          p_roof_type_requested?: string[]
          p_secondary_phone?: string
          p_service_address_city?: string
          p_service_address_state?: string
          p_service_address_street?: string
          p_service_address_zip?: string
          p_source?: string
          p_tags?: string[]
          p_trade?: string
          p_value?: number
        }
        Returns: string
      }
      create_engagement_from_roadmap: {
        Args: { p_deal_id: string }
        Returns: string
      }
      create_estimate_from_deal: {
        Args: { p_deal_id: string }
        Returns: string
      }
      create_organization: {
        Args: { p_name: string; p_tenant_type: string; p_trade?: string }
        Returns: string
      }
      create_roadmap_item: {
        Args: {
          p_feature: string
          p_notes?: string
          p_org_id: string
          p_phase: string
          p_section: string
          p_sort_order?: number
          p_status?: string
        }
        Returns: string
      }
      create_tracker_item: {
        Args: {
          p_assignee_id?: string
          p_description?: string
          p_org_id: string
          p_priority?: string
          p_project_id: string
          p_status?: string
          p_title: string
          p_type?: string
        }
        Returns: string
      }
      create_tracker_project: {
        Args: {
          p_description?: string
          p_linked_org_id?: string
          p_name: string
          p_org_id: string
        }
        Returns: string
      }
      create_work_order_from_estimate: {
        Args: { p_estimate_id: string }
        Returns: string
      }
      crm_follow_up_cadence_days: {
        Args: { p_org_id: string }
        Returns: number[]
      }
      crm_stage_config: { Args: { p_org_id: string }; Returns: Json }
      crm_stage_entry: {
        Args: { p_org_id: string; p_stage_key: string }
        Returns: Json
      }
      delete_check_in: { Args: { p_check_in_id: string }; Returns: undefined }
      delete_estimate: { Args: { p_estimate_id: string }; Returns: undefined }
      delete_estimate_line_item: {
        Args: { p_line_item_id: string }
        Returns: undefined
      }
      delete_material_item: {
        Args: { p_material_item_id: string }
        Returns: undefined
      }
      delete_production_packet: {
        Args: { p_production_packet_id: string }
        Returns: undefined
      }
      delete_production_packet_callout: {
        Args: { p_callout_id: string; p_production_packet_id: string }
        Returns: undefined
      }
      delete_roadmap_item: { Args: { p_id: string }; Returns: undefined }
      delete_schedule_block: {
        Args: { p_schedule_block_id: string }
        Returns: undefined
      }
      delete_tracker_item: { Args: { p_item_id: string }; Returns: undefined }
      delete_tracker_project: {
        Args: { p_project_id: string }
        Returns: undefined
      }
      delete_work_order: {
        Args: { p_work_order_id: string }
        Returns: undefined
      }
      fetch_check_in: {
        Args: { p_check_in_id: string }
        Returns: {
          blockers: string | null
          check_in_date: string
          created_at: string
          crew_name: string
          hours: number
          id: string
          materials_used: string | null
          org_id: string
          photos: string[]
          schedule_block_id: string | null
          updated_at: string
          work_order_id: string
        }[]
        SetofOptions: {
          from: "*"
          to: "check_ins"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_deal: {
        Args: { p_deal_id: string }
        Returns: {
          archived_at: string | null
          billing_address: string | null
          closed_at: string | null
          company: string | null
          contact_name: string
          created_at: string
          crew_size: number | null
          email: string | null
          existing_roof_type: string[] | null
          first_name: string | null
          id: string
          intake_checklist: Json
          last_name: string | null
          lead_id: string | null
          lead_type: string | null
          lost_reason: string | null
          org_id: string | null
          owner_id: string | null
          phone: string | null
          project_address: string | null
          proposal_notes: string | null
          proposal_tier: string | null
          quote_presented_at: string | null
          referral_name: string | null
          remodel_or_new_construction: string | null
          roof_scope_ordered_at: string | null
          roof_type_requested: string[] | null
          secondary_phone: string | null
          service_address_city: string | null
          service_address_state: string | null
          service_address_street: string | null
          service_address_zip: string | null
          site_survey_complete_at: string | null
          source: string | null
          stage: string
          tags: string[] | null
          trade: string | null
          updated_at: string
          value: number | null
        }[]
        SetofOptions: {
          from: "*"
          to: "deals"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_estimate: {
        Args: { p_estimate_id: string }
        Returns: {
          build_mode: string
          company: string | null
          contact_name: string | null
          created_at: string
          deal_id: string
          email: string | null
          estimate_date: string | null
          estimate_number: string | null
          id: string
          notes_terms: string | null
          org_id: string
          phone: string | null
          pitch: string | null
          presented_at: string | null
          presented_total: number | null
          signed_at: string | null
          site_address: string | null
          squares: number | null
          status: string
          subtotal: number
          tax_amount: number | null
          tax_rate: number | null
          updated_at: string
          valid_until: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "estimates"
          isOneToOne: false
          isSetofReturn: true
        }
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
      fetch_production_packet: {
        Args: { p_production_packet_id: string }
        Returns: {
          callouts: Json
          created_at: string
          id: string
          notes: string | null
          org_id: string
          updated_at: string
          work_order_id: string
        }[]
        SetofOptions: {
          from: "*"
          to: "production_packets"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_tracker_item: {
        Args: { p_item_id: string }
        Returns: {
          archived_at: string | null
          assignee_id: string | null
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          org_id: string
          position: number
          priority: string
          project_id: string
          reported_by_org_id: string | null
          reported_by_profile_id: string | null
          resolved_at: string | null
          source: string
          status: string
          title: string
          type: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "tracker_items"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_tracker_project: {
        Args: { p_project_id: string }
        Returns: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          linked_org_id: string | null
          name: string
          org_id: string
          status: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "tracker_projects"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_work_order: {
        Args: { p_work_order_id: string }
        Returns: {
          created_at: string
          estimate_id: string
          id: string
          org_id: string
          sign_off_at: string | null
          sign_off_notes: string | null
          updated_at: string
          voided_at: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "work_orders"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      generate_roadmap_for_lead: {
        Args: { p_lead_id: string }
        Returns: string
      }
      get_or_create_production_packet: {
        Args: { p_work_order_id: string }
        Returns: string
      }
      is_org_manager: { Args: { p_org_id: string }; Returns: boolean }
      is_pipeline_manager: { Args: never; Returns: boolean }
      is_pipeline_user: { Args: never; Returns: boolean }
      is_platform_admin: { Args: never; Returns: boolean }
      is_staff: { Args: never; Returns: boolean }
      list_org_members: {
        Args: { p_org_id: string }
        Returns: {
          full_name: string
          user_id: string
        }[]
      }
      my_active_lead_count: { Args: never; Returns: number }
      my_avg_cycle_days: { Args: never; Returns: number }
      my_closes_this_month: { Args: never; Returns: number }
      my_open_pipeline_value: { Args: never; Returns: number }
      my_org_ids: { Args: never; Returns: string[] }
      my_win_rate: { Args: never; Returns: number }
      order_scope: {
        Args: { p_deal_id: string; p_ordered_at?: string }
        Returns: undefined
      }
      present_estimate: { Args: { p_estimate_id: string }; Returns: undefined }
      present_quote: {
        Args: { p_deal_id: string; p_presented_at?: string }
        Returns: undefined
      }
      record_work_order_sign_off: {
        Args: { p_notes?: string; p_work_order_id: string }
        Returns: undefined
      }
      remove_check_in_photo: {
        Args: { p_check_in_id: string; p_photo_data_url: string }
        Returns: undefined
      }
      reorder_estimate_line_items: {
        Args: { p_estimate_id: string; p_line_item_ids: string[] }
        Returns: undefined
      }
      restore_deal: { Args: { p_deal_id: string }; Returns: undefined }
      restore_tracker_item: { Args: { p_item_id: string }; Returns: undefined }
      restore_tracker_project: {
        Args: { p_project_id: string }
        Returns: undefined
      }
      restore_work_order: {
        Args: { p_work_order_id: string }
        Returns: undefined
      }
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
      sign_estimate: {
        Args: {
          p_estimate_id: string
          p_signature_data: string
          p_signer_name: string
          p_signer_role: string
        }
        Returns: string
      }
      tracker_status_config: { Args: { p_org_id: string }; Returns: Json }
      tracker_type_config: { Args: { p_org_id: string }; Returns: Json }
      update_check_in: {
        Args: {
          p_blockers?: string
          p_check_in_date?: string
          p_check_in_id: string
          p_crew_name?: string
          p_hours?: number
          p_materials_used?: string
        }
        Returns: undefined
      }
      update_deal_fields: {
        Args: { p_deal_id: string; p_patch: Json }
        Returns: undefined
      }
      update_deal_stage: {
        Args: { p_deal_id: string; p_new_stage: string }
        Returns: undefined
      }
      update_estimate_build_mode: {
        Args: { p_build_mode: string; p_estimate_id: string }
        Returns: undefined
      }
      update_estimate_contact: {
        Args: {
          p_company?: string
          p_contact_name?: string
          p_email?: string
          p_estimate_id: string
          p_phone?: string
        }
        Returns: undefined
      }
      update_estimate_details: {
        Args: {
          p_clear_tax_rate?: boolean
          p_clear_valid_until?: boolean
          p_estimate_date?: string
          p_estimate_id: string
          p_notes_terms?: string
          p_pitch?: string
          p_site_address?: string
          p_squares?: number
          p_tax_rate?: number
          p_valid_until?: string
        }
        Returns: undefined
      }
      update_estimate_line_item: {
        Args: {
          p_description?: string
          p_line_item_id: string
          p_quantity?: number
          p_sort_order?: number
          p_unit?: string
          p_unit_price?: number
        }
        Returns: undefined
      }
      update_intake_checklist_field: {
        Args: { p_deal_id: string; p_field_path: string[]; p_value: Json }
        Returns: undefined
      }
      update_material_item: {
        Args: {
          p_material_item_id: string
          p_name?: string
          p_quantity?: number
          p_ready_by?: string
          p_sort_order?: number
        }
        Returns: undefined
      }
      update_production_packet_callout: {
        Args: {
          p_callout_id: string
          p_detail?: string
          p_label?: string
          p_production_packet_id: string
        }
        Returns: undefined
      }
      update_production_packet_notes: {
        Args: { p_notes: string; p_production_packet_id: string }
        Returns: undefined
      }
      update_roadmap_fields: {
        Args: { p_id: string; p_patch: Json }
        Returns: undefined
      }
      update_schedule_block: {
        Args: {
          p_crew_name?: string
          p_end_date?: string
          p_schedule_block_id: string
          p_start_date?: string
        }
        Returns: undefined
      }
      update_tracker_item: {
        Args: {
          p_assignee_id?: string
          p_clear_assignee?: boolean
          p_description?: string
          p_item_id: string
          p_position?: number
          p_priority?: string
          p_status?: string
          p_title?: string
          p_type?: string
        }
        Returns: undefined
      }
      update_tracker_project: {
        Args: {
          p_description?: string
          p_linked_org_id?: string
          p_name?: string
          p_project_id: string
          p_status?: string
        }
        Returns: undefined
      }
      upsert_estimate_scope_line_items: {
        Args: { p_estimate_id: string; p_items: Json }
        Returns: undefined
      }
      void_estimate: { Args: { p_estimate_id: string }; Returns: undefined }
      void_work_order: { Args: { p_work_order_id: string }; Returns: undefined }
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
