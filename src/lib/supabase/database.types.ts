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
    PostgrestVersion: "14.5"
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
          client_token: string | null
          created_at: string
          created_by: string | null
          crew_id: string | null
          crew_name: string
          hours: number | null
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
          client_token?: string | null
          created_at?: string
          created_by?: string | null
          crew_id?: string | null
          crew_name: string
          hours?: number | null
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
          client_token?: string | null
          created_at?: string
          created_by?: string | null
          crew_id?: string | null
          crew_name?: string
          hours?: number | null
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
            foreignKeyName: "check_ins_crew_fk"
            columns: ["crew_id", "org_id"]
            isOneToOne: false
            referencedRelation: "crews"
            referencedColumns: ["id", "org_id"]
          },
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
            referencedRelation: "crew_assignment_states"
            referencedColumns: ["schedule_block_id"]
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
      crew_memberships: {
        Row: {
          created_at: string
          created_by: string | null
          crew_id: string
          is_lead: boolean
          org_id: string
          person_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          crew_id: string
          is_lead?: boolean
          org_id: string
          person_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          crew_id?: string
          is_lead?: boolean
          org_id?: string
          person_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "crew_memberships_crew"
            columns: ["crew_id", "org_id"]
            isOneToOne: false
            referencedRelation: "crews"
            referencedColumns: ["id", "org_id"]
          },
          {
            foreignKeyName: "crew_memberships_person"
            columns: ["person_id", "org_id"]
            isOneToOne: false
            referencedRelation: "crew_people"
            referencedColumns: ["id", "org_id"]
          },
        ]
      }
      crew_people: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          full_name: string
          has_vehicle: boolean | null
          id: string
          org_id: string
          phone: string | null
          preferred_language: string | null
          skills: string[] | null
          updated_at: string
          user_id: string | null
          vehicle_note: string | null
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          full_name: string
          has_vehicle?: boolean | null
          id?: string
          org_id: string
          phone?: string | null
          preferred_language?: string | null
          skills?: string[] | null
          updated_at?: string
          user_id?: string | null
          vehicle_note?: string | null
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          full_name?: string
          has_vehicle?: boolean | null
          id?: string
          org_id?: string
          phone?: string | null
          preferred_language?: string | null
          skills?: string[] | null
          updated_at?: string
          user_id?: string | null
          vehicle_note?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "crew_people_member_login"
            columns: ["org_id", "user_id"]
            isOneToOne: false
            referencedRelation: "org_members"
            referencedColumns: ["org_id", "user_id"]
          },
          {
            foreignKeyName: "crew_people_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      crew_person_unavailability: {
        Row: {
          created_at: string
          created_by: string | null
          ends_on: string
          id: string
          org_id: string
          person_id: string
          reason: string | null
          starts_on: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          ends_on: string
          id?: string
          org_id: string
          person_id: string
          reason?: string | null
          starts_on: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          ends_on?: string
          id?: string
          org_id?: string
          person_id?: string
          reason?: string | null
          starts_on?: string
        }
        Relationships: [
          {
            foreignKeyName: "crew_person_unavailability_person"
            columns: ["person_id", "org_id"]
            isOneToOne: false
            referencedRelation: "crew_people"
            referencedColumns: ["id", "org_id"]
          },
        ]
      }
      crews: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          id: string
          name: string
          org_id: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          org_id: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          org_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "crews_org_id_fkey"
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
          quantity: number
          scope_key?: string | null
          sort_order?: number
          unit?: string | null
          unit_price: number
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
          {
            foreignKeyName: "estimate_line_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
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
      estimate_sign_links: {
        Row: {
          created_at: string
          created_by: string | null
          document_hash: string
          estimate_id: string
          expires_at: string
          id: string
          org_id: string
          revoked_at: string | null
          revoked_by: string | null
          signature_id: string | null
          token_hash: string
          used_at: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          document_hash: string
          estimate_id: string
          expires_at: string
          id?: string
          org_id: string
          revoked_at?: string | null
          revoked_by?: string | null
          signature_id?: string | null
          token_hash: string
          used_at?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          document_hash?: string
          estimate_id?: string
          expires_at?: string
          id?: string
          org_id?: string
          revoked_at?: string | null
          revoked_by?: string | null
          signature_id?: string | null
          token_hash?: string
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "estimate_sign_links_estimate_id_fkey"
            columns: ["estimate_id"]
            isOneToOne: false
            referencedRelation: "estimates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "estimate_sign_links_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "estimate_sign_links_signature_id_fkey"
            columns: ["signature_id"]
            isOneToOne: false
            referencedRelation: "signatures"
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
      field_events: {
        Row: {
          actor_id: string
          client_sent_at: string | null
          duration_ms: number | null
          event: string
          id: string
          occurred_at: string
          org_id: string
          outcome: string | null
          subject_ref: string | null
          work_order_id: string | null
        }
        Insert: {
          actor_id: string
          client_sent_at?: string | null
          duration_ms?: number | null
          event: string
          id?: string
          occurred_at?: string
          org_id: string
          outcome?: string | null
          subject_ref?: string | null
          work_order_id?: string | null
        }
        Update: {
          actor_id?: string
          client_sent_at?: string | null
          duration_ms?: number | null
          event?: string
          id?: string
          occurred_at?: string
          org_id?: string
          outcome?: string | null
          subject_ref?: string | null
          work_order_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "field_events_org_id_fkey"
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
      jobs: {
        Row: {
          created_at: string
          deal_id: string
          estimate_id: string
          id: string
          org_id: string
          service_address_city: string | null
          service_address_state: string | null
          service_address_street: string | null
          service_address_zip: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          deal_id: string
          estimate_id: string
          id?: string
          org_id: string
          service_address_city?: string | null
          service_address_state?: string | null
          service_address_street?: string | null
          service_address_zip?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          deal_id?: string
          estimate_id?: string
          id?: string
          org_id?: string
          service_address_city?: string | null
          service_address_state?: string | null
          service_address_street?: string | null
          service_address_zip?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "jobs_deal_id_fkey"
            columns: ["deal_id"]
            isOneToOne: false
            referencedRelation: "deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_estimate_id_fkey"
            columns: ["estimate_id"]
            isOneToOne: true
            referencedRelation: "estimates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_org_id_fkey"
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
          estimate_line_item_id: string | null
          id: string
          name: string
          org_id: string
          product_id: string | null
          quantity: number
          ready_by: string | null
          ready_by_source: string
          sort_order: number
          take_off_description: string | null
          take_off_quantity: number | null
          take_off_unit: string | null
          unit: string | null
          updated_at: string
          work_order_id: string
        }
        Insert: {
          created_at?: string
          estimate_line_item_id?: string | null
          id?: string
          name: string
          org_id: string
          product_id?: string | null
          quantity: number
          ready_by?: string | null
          ready_by_source?: string
          sort_order?: number
          take_off_description?: string | null
          take_off_quantity?: number | null
          take_off_unit?: string | null
          unit?: string | null
          updated_at?: string
          work_order_id: string
        }
        Update: {
          created_at?: string
          estimate_line_item_id?: string | null
          id?: string
          name?: string
          org_id?: string
          product_id?: string | null
          quantity?: number
          ready_by?: string | null
          ready_by_source?: string
          sort_order?: number
          take_off_description?: string | null
          take_off_quantity?: number | null
          take_off_unit?: string | null
          unit?: string | null
          updated_at?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "material_items_estimate_line_item_id_fkey"
            columns: ["estimate_line_item_id"]
            isOneToOne: false
            referencedRelation: "estimate_line_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "material_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "material_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
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
          permissions: Json
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          full_name?: string | null
          org_id: string
          permissions?: Json
          role?: string
          user_id: string
        }
        Update: {
          created_at?: string
          full_name?: string | null
          org_id?: string
          permissions?: Json
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
          policy: Json
          tenant_type: string
          trade: string | null
        }
        Insert: {
          created_at?: string
          deal_id?: string | null
          id?: string
          name: string
          policy?: Json
          tenant_type?: string
          trade?: string | null
        }
        Update: {
          created_at?: string
          deal_id?: string | null
          id?: string
          name?: string
          policy?: Json
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
      products: {
        Row: {
          active: boolean
          category: string | null
          cost: number | null
          created_at: string
          created_by: string | null
          id: string
          markup: number | null
          name: string
          org_id: string
          price_method: string | null
          price_review_reason: string | null
          price_value: number | null
          sell: number | null
          unit: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          category?: string | null
          cost?: number | null
          created_at?: string
          created_by?: string | null
          id?: string
          markup?: number | null
          name: string
          org_id: string
          price_method?: string | null
          price_review_reason?: string | null
          price_value?: number | null
          sell?: number | null
          unit?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          category?: string | null
          cost?: number | null
          created_at?: string
          created_by?: string | null
          id?: string
          markup?: number | null
          name?: string
          org_id?: string
          price_method?: string | null
          price_review_reason?: string | null
          price_value?: number | null
          sell?: number | null
          unit?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "products_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
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
      purchase_order_line_promises: {
        Row: {
          id: string
          org_id: string
          promised_date: string | null
          purchase_order_line_id: string
          recorded_at: string
          recorded_by: string | null
        }
        Insert: {
          id?: string
          org_id: string
          promised_date?: string | null
          purchase_order_line_id: string
          recorded_at?: string
          recorded_by?: string | null
        }
        Update: {
          id?: string
          org_id?: string
          promised_date?: string | null
          purchase_order_line_id?: string
          recorded_at?: string
          recorded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_line_promises_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_line_promises_purchase_order_line_id_fkey"
            columns: ["purchase_order_line_id"]
            isOneToOne: false
            referencedRelation: "purchase_order_lines"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_order_lines: {
        Row: {
          actual_date: string | null
          created_at: string
          id: string
          material_item_id: string
          org_id: string
          promised_date: string | null
          purchase_order_id: string
          quantity_ordered: number
          updated_at: string
        }
        Insert: {
          actual_date?: string | null
          created_at?: string
          id?: string
          material_item_id: string
          org_id: string
          promised_date?: string | null
          purchase_order_id: string
          quantity_ordered: number
          updated_at?: string
        }
        Update: {
          actual_date?: string | null
          created_at?: string
          id?: string
          material_item_id?: string
          org_id?: string
          promised_date?: string | null
          purchase_order_id?: string
          quantity_ordered?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_lines_material_item_id_fkey"
            columns: ["material_item_id"]
            isOneToOne: false
            referencedRelation: "material_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_orders: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          job_id: string | null
          notes: string | null
          org_id: string
          reference: string | null
          status: string
          supplier_name: string
          supplier_org_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          job_id?: string | null
          notes?: string | null
          org_id: string
          reference?: string | null
          status?: string
          supplier_name: string
          supplier_org_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          job_id?: string | null
          notes?: string | null
          org_id?: string
          reference?: string | null
          status?: string
          supplier_name?: string
          supplier_org_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "purchase_orders_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_supplier_org_id_fkey"
            columns: ["supplier_org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      qc_items: {
        Row: {
          actor_id: string
          cleared_at: string | null
          cleared_by: string | null
          count_value: number | null
          first_actor_id: string
          first_occurred_at: string
          id: string
          kind: string
          occurred_at: string
          org_id: string
          photo_ref: string | null
          requirement_key: string
          work_order_id: string
        }
        Insert: {
          actor_id: string
          cleared_at?: string | null
          cleared_by?: string | null
          count_value?: number | null
          first_actor_id: string
          first_occurred_at: string
          id?: string
          kind: string
          occurred_at?: string
          org_id: string
          photo_ref?: string | null
          requirement_key: string
          work_order_id: string
        }
        Update: {
          actor_id?: string
          cleared_at?: string | null
          cleared_by?: string | null
          count_value?: number | null
          first_actor_id?: string
          first_occurred_at?: string
          id?: string
          kind?: string
          occurred_at?: string
          org_id?: string
          photo_ref?: string | null
          requirement_key?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "qc_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "qc_items_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      roadmap_items: {
        Row: {
          created_at: string
          feature: string
          id: string
          notes: string | null
          org_id: string
          phase: string
          project_id: string
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
          project_id: string
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
          project_id?: string
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
            foreignKeyName: "roadmap_items_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "roadmap_projects"
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
      roadmap_projects: {
        Row: {
          created_at: string
          id: string
          key: string
          name: string
          org_id: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          key: string
          name: string
          org_id: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          key?: string
          name?: string
          org_id?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "roadmap_projects_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      schedule_blocks: {
        Row: {
          created_at: string
          crew_id: string | null
          crew_name: string
          end_date: string
          id: string
          org_id: string
          ready_by_conflict: boolean
          ready_by_conflict_reason: string | null
          start_date: string
          updated_at: string
          work_order_id: string
        }
        Insert: {
          created_at?: string
          crew_id?: string | null
          crew_name: string
          end_date: string
          id?: string
          org_id: string
          ready_by_conflict?: boolean
          ready_by_conflict_reason?: string | null
          start_date: string
          updated_at?: string
          work_order_id: string
        }
        Update: {
          created_at?: string
          crew_id?: string | null
          crew_name?: string
          end_date?: string
          id?: string
          org_id?: string
          ready_by_conflict?: boolean
          ready_by_conflict_reason?: string | null
          start_date?: string
          updated_at?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "schedule_blocks_crew_fk"
            columns: ["crew_id", "org_id"]
            isOneToOne: false
            referencedRelation: "crews"
            referencedColumns: ["id", "org_id"]
          },
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
          sign_link_id: string | null
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
          sign_link_id?: string | null
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
          sign_link_id?: string | null
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
          {
            foreignKeyName: "signatures_sign_link_id_fkey"
            columns: ["sign_link_id"]
            isOneToOne: false
            referencedRelation: "estimate_sign_links"
            referencedColumns: ["id"]
          },
        ]
      }
      signed_copy_records: {
        Row: {
          attempts: number
          estimate_id: string
          last_attempt_at: string | null
          last_attempt_via: string | null
          org_id: string
          owed_at: string
          provider_message_id: string | null
          sent_at: string | null
          signature_id: string
          state: string
        }
        Insert: {
          attempts?: number
          estimate_id: string
          last_attempt_at?: string | null
          last_attempt_via?: string | null
          org_id: string
          owed_at?: string
          provider_message_id?: string | null
          sent_at?: string | null
          signature_id: string
          state: string
        }
        Update: {
          attempts?: number
          estimate_id?: string
          last_attempt_at?: string | null
          last_attempt_via?: string | null
          org_id?: string
          owed_at?: string
          provider_message_id?: string | null
          sent_at?: string | null
          signature_id?: string
          state?: string
        }
        Relationships: [
          {
            foreignKeyName: "signed_copy_records_estimate_id_fkey"
            columns: ["estimate_id"]
            isOneToOne: false
            referencedRelation: "estimates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "signed_copy_records_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "signed_copy_records_signature_id_fkey"
            columns: ["signature_id"]
            isOneToOne: true
            referencedRelation: "signatures"
            referencedColumns: ["id"]
          },
        ]
      }
      special_trips: {
        Row: {
          client_token: string | null
          created_at: string
          id: string
          note: string | null
          occurred_on: string
          org_id: string
          reason_code: string
          recorded_at: string
          recorded_by: string
          work_order_id: string
        }
        Insert: {
          client_token?: string | null
          created_at?: string
          id?: string
          note?: string | null
          occurred_on: string
          org_id: string
          reason_code: string
          recorded_at?: string
          recorded_by: string
          work_order_id: string
        }
        Update: {
          client_token?: string | null
          created_at?: string
          id?: string
          note?: string | null
          occurred_on?: string
          org_id?: string
          reason_code?: string
          recorded_at?: string
          recorded_by?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "special_trips_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "special_trips_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "special_trips_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
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
      take_off_decisions: {
        Row: {
          decided_at: string
          decided_by: string | null
          disposition: string
          estimate_line_item_id: string
          item_removed_at: string | null
          item_removed_by: string | null
          org_id: string
          source: string
          work_order_id: string | null
        }
        Insert: {
          decided_at?: string
          decided_by?: string | null
          disposition: string
          estimate_line_item_id: string
          item_removed_at?: string | null
          item_removed_by?: string | null
          org_id: string
          source: string
          work_order_id?: string | null
        }
        Update: {
          decided_at?: string
          decided_by?: string | null
          disposition?: string
          estimate_line_item_id?: string
          item_removed_at?: string | null
          item_removed_by?: string | null
          org_id?: string
          source?: string
          work_order_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "take_off_decisions_estimate_line_item_id_fkey"
            columns: ["estimate_line_item_id"]
            isOneToOne: true
            referencedRelation: "estimate_line_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "take_off_decisions_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "take_off_decisions_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
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
      tg_agenda_card: {
        Row: {
          chat_id: number | null
          created_at: string
          created_by: number | null
          delivered_to: Json
          id: number
          payload: Json
        }
        Insert: {
          chat_id?: number | null
          created_at?: string
          created_by?: number | null
          delivered_to?: Json
          id?: number
          payload: Json
        }
        Update: {
          chat_id?: number | null
          created_at?: string
          created_by?: number | null
          delivered_to?: Json
          id?: number
          payload?: Json
        }
        Relationships: []
      }
      tg_agenda_contact: {
        Row: {
          active: boolean
          added_by: number | null
          created_at: string
          id: number
          label: string
          tg_user_id: number | null
          username: string | null
        }
        Insert: {
          active?: boolean
          added_by?: number | null
          created_at?: string
          id?: number
          label: string
          tg_user_id?: number | null
          username?: string | null
        }
        Update: {
          active?: boolean
          added_by?: number | null
          created_at?: string
          id?: number
          label?: string
          tg_user_id?: number | null
          username?: string | null
        }
        Relationships: []
      }
      tg_agenda_group: {
        Row: {
          active: boolean
          added_by: number | null
          chat_id: number
          created_at: string
          title: string | null
        }
        Insert: {
          active?: boolean
          added_by?: number | null
          chat_id: number
          created_at?: string
          title?: string | null
        }
        Update: {
          active?: boolean
          added_by?: number | null
          chat_id?: number
          created_at?: string
          title?: string | null
        }
        Relationships: []
      }
      tg_agenda_sender: {
        Row: {
          added_by: number | null
          created_at: string
          label: string | null
          owner: boolean
          tg_user_id: number
        }
        Insert: {
          added_by?: number | null
          created_at?: string
          label?: string | null
          owner?: boolean
          tg_user_id: number
        }
        Update: {
          added_by?: number | null
          created_at?: string
          label?: string | null
          owner?: boolean
          tg_user_id?: number
        }
        Relationships: []
      }
      tg_agenda_session: {
        Row: {
          chat_id: number
          draft: Json
          step: string
          tg_user_id: number
          updated_at: string
        }
        Insert: {
          chat_id: number
          draft?: Json
          step?: string
          tg_user_id: number
          updated_at?: string
        }
        Update: {
          chat_id?: number
          draft?: Json
          step?: string
          tg_user_id?: number
          updated_at?: string
        }
        Relationships: []
      }
      tg_agenda_update: {
        Row: {
          seen_at: string
          update_id: number
        }
        Insert: {
          seen_at?: string
          update_id: number
        }
        Update: {
          seen_at?: string
          update_id?: number
        }
        Relationships: []
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
      wh_categories: {
        Row: {
          active: boolean | null
          badge: string | null
          card_type: string | null
          catalog_section: string | null
          created_at: string | null
          display_order: number | null
          id: string
          image_url: string | null
          microcopy: string | null
          name: string
          org_id: string
          required: boolean | null
          skip_label: string | null
          slug: string
          stage_id: string | null
          status: string
          system_id: string
        }
        Insert: {
          active?: boolean | null
          badge?: string | null
          card_type?: string | null
          catalog_section?: string | null
          created_at?: string | null
          display_order?: number | null
          id?: string
          image_url?: string | null
          microcopy?: string | null
          name: string
          org_id: string
          required?: boolean | null
          skip_label?: string | null
          slug: string
          stage_id?: string | null
          status?: string
          system_id: string
        }
        Update: {
          active?: boolean | null
          badge?: string | null
          card_type?: string | null
          catalog_section?: string | null
          created_at?: string | null
          display_order?: number | null
          id?: string
          image_url?: string | null
          microcopy?: string | null
          name?: string
          org_id?: string
          required?: boolean | null
          skip_label?: string | null
          slug?: string
          stage_id?: string | null
          status?: string
          system_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_categories_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_categories_stage_id_fkey"
            columns: ["stage_id"]
            isOneToOne: false
            referencedRelation: "wh_stages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_categories_system_id_fkey"
            columns: ["system_id"]
            isOneToOne: false
            referencedRelation: "wh_systems"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_category_products: {
        Row: {
          category_id: string
          product_id: string
        }
        Insert: {
          category_id: string
          product_id: string
        }
        Update: {
          category_id?: string
          product_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_category_products_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "wh_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_category_products_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "wh_products"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_colors: {
        Row: {
          available_finishes: string[] | null
          color_family: string | null
          created_at: string | null
          display_order: number | null
          finishes_chosen_at: string | null
          hex_code: string | null
          id: string
          name: string
          org_id: string
          status: string
          swatch_image_url: string | null
        }
        Insert: {
          available_finishes?: string[] | null
          color_family?: string | null
          created_at?: string | null
          display_order?: number | null
          finishes_chosen_at?: string | null
          hex_code?: string | null
          id?: string
          name: string
          org_id: string
          status?: string
          swatch_image_url?: string | null
        }
        Update: {
          available_finishes?: string[] | null
          color_family?: string | null
          created_at?: string | null
          display_order?: number | null
          finishes_chosen_at?: string | null
          hex_code?: string | null
          id?: string
          name?: string
          org_id?: string
          status?: string
          swatch_image_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_colors_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_cost_history: {
        Row: {
          changed_by: string | null
          cost: number
          created_at: string
          effective_from: string
          effective_to: string | null
          id: string
          note: string | null
          org_id: string
          variation_id: string
        }
        Insert: {
          changed_by?: string | null
          cost: number
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          note?: string | null
          org_id?: string
          variation_id: string
        }
        Update: {
          changed_by?: string | null
          cost?: number
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          note?: string | null
          org_id?: string
          variation_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_cost_history_variation_id_fkey"
            columns: ["variation_id"]
            isOneToOne: false
            referencedRelation: "wh_product_variations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_drivers: {
        Row: {
          active: boolean | null
          created_at: string | null
          email: string
          id: string
          name: string
          org_id: string
          phone: string | null
        }
        Insert: {
          active?: boolean | null
          created_at?: string | null
          email: string
          id?: string
          name: string
          org_id?: string
          phone?: string | null
        }
        Update: {
          active?: boolean | null
          created_at?: string | null
          email?: string
          id?: string
          name?: string
          org_id?: string
          phone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_drivers_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_order_access_tokens: {
        Row: {
          created_at: string
          expires_at: string
          order_id: string
          org_id: string
          revoked_at: string | null
          token: string
        }
        Insert: {
          created_at?: string
          expires_at?: string
          order_id: string
          org_id?: string
          revoked_at?: string | null
          token: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          order_id?: string
          org_id?: string
          revoked_at?: string | null
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_order_access_tokens_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: true
            referencedRelation: "wh_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_order_attachments: {
        Row: {
          attached_at: string
          id: string
          order_id: string
          org_id: string
          user_id: string
        }
        Insert: {
          attached_at?: string
          id?: string
          order_id: string
          org_id: string
          user_id?: string
        }
        Update: {
          attached_at?: string
          id?: string
          order_id?: string
          org_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_order_attachments_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "wh_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_order_line_items: {
        Row: {
          amount: number | null
          attributes: Json | null
          auto_generated: boolean | null
          category: string | null
          color_id: string | null
          description: string | null
          display_order: number | null
          finish: string | null
          id: string
          is_priceable: boolean | null
          length_in: number | null
          order_id: string
          org_id: string
          pricing_rule: string | null
          product_id: string | null
          quantity: number | null
          quantity_unit: string | null
          specs: string | null
          waste_units: number | null
        }
        Insert: {
          amount?: number | null
          attributes?: Json | null
          auto_generated?: boolean | null
          category?: string | null
          color_id?: string | null
          description?: string | null
          display_order?: number | null
          finish?: string | null
          id?: string
          is_priceable?: boolean | null
          length_in?: number | null
          order_id: string
          org_id?: string
          pricing_rule?: string | null
          product_id?: string | null
          quantity?: number | null
          quantity_unit?: string | null
          specs?: string | null
          waste_units?: number | null
        }
        Update: {
          amount?: number | null
          attributes?: Json | null
          auto_generated?: boolean | null
          category?: string | null
          color_id?: string | null
          description?: string | null
          display_order?: number | null
          finish?: string | null
          id?: string
          is_priceable?: boolean | null
          length_in?: number | null
          order_id?: string
          org_id?: string
          pricing_rule?: string | null
          product_id?: string | null
          quantity?: number | null
          quantity_unit?: string | null
          specs?: string | null
          waste_units?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_order_line_items_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "wh_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_order_line_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_orders: {
        Row: {
          amount_paid_cents: number | null
          created_at: string | null
          customer_email: string | null
          customer_id: string | null
          customer_name: string | null
          customer_phone: string | null
          delivery_address: Json | null
          driver_email: string | null
          dropped_off_at: string | null
          freight_amount: number | null
          fulfillment: string | null
          id: string
          job_name: string | null
          lead_time_text: string | null
          order_date: string | null
          order_notes: string | null
          order_number: string
          order_total: number | null
          org_id: string
          paid_at: string | null
          payment_status: string
          pdf_generated_at: string | null
          pdf_url: string | null
          pickup_location: string | null
          printed_at: string | null
          printed_by_email: string | null
          return_policy_acknowledged_at: string | null
          return_policy_text: string | null
          status: string | null
          stripe_checkout_session_id: string | null
          stripe_payment_intent_id: string | null
          subtotal: number | null
          system: string | null
          tax_amount: number | null
          tax_exempt: boolean
          tax_exemption_id: string | null
          tax_rate_percent: number | null
          webhook_claimed_at: string | null
          webhook_error: string | null
          webhook_fired: boolean | null
          webhook_payload: Json | null
        }
        Insert: {
          amount_paid_cents?: number | null
          created_at?: string | null
          customer_email?: string | null
          customer_id?: string | null
          customer_name?: string | null
          customer_phone?: string | null
          delivery_address?: Json | null
          driver_email?: string | null
          dropped_off_at?: string | null
          freight_amount?: number | null
          fulfillment?: string | null
          id?: string
          job_name?: string | null
          lead_time_text?: string | null
          order_date?: string | null
          order_notes?: string | null
          order_number: string
          order_total?: number | null
          org_id?: string
          paid_at?: string | null
          payment_status?: string
          pdf_generated_at?: string | null
          pdf_url?: string | null
          pickup_location?: string | null
          printed_at?: string | null
          printed_by_email?: string | null
          return_policy_acknowledged_at?: string | null
          return_policy_text?: string | null
          status?: string | null
          stripe_checkout_session_id?: string | null
          stripe_payment_intent_id?: string | null
          subtotal?: number | null
          system?: string | null
          tax_amount?: number | null
          tax_exempt?: boolean
          tax_exemption_id?: string | null
          tax_rate_percent?: number | null
          webhook_claimed_at?: string | null
          webhook_error?: string | null
          webhook_fired?: boolean | null
          webhook_payload?: Json | null
        }
        Update: {
          amount_paid_cents?: number | null
          created_at?: string | null
          customer_email?: string | null
          customer_id?: string | null
          customer_name?: string | null
          customer_phone?: string | null
          delivery_address?: Json | null
          driver_email?: string | null
          dropped_off_at?: string | null
          freight_amount?: number | null
          fulfillment?: string | null
          id?: string
          job_name?: string | null
          lead_time_text?: string | null
          order_date?: string | null
          order_notes?: string | null
          order_number?: string
          order_total?: number | null
          org_id?: string
          paid_at?: string | null
          payment_status?: string
          pdf_generated_at?: string | null
          pdf_url?: string | null
          pickup_location?: string | null
          printed_at?: string | null
          printed_by_email?: string | null
          return_policy_acknowledged_at?: string | null
          return_policy_text?: string | null
          status?: string | null
          stripe_checkout_session_id?: string | null
          stripe_payment_intent_id?: string | null
          subtotal?: number | null
          system?: string | null
          tax_amount?: number | null
          tax_exempt?: boolean
          tax_exemption_id?: string | null
          tax_rate_percent?: number | null
          webhook_claimed_at?: string | null
          webhook_error?: string | null
          webhook_fired?: boolean | null
          webhook_payload?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_orders_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_orders_tax_exemption_id_fkey"
            columns: ["tax_exemption_id"]
            isOneToOne: false
            referencedRelation: "wh_tax_exemptions"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_price_history: {
        Row: {
          changed_by: string | null
          created_at: string
          effective_from: string
          effective_to: string | null
          id: string
          note: string | null
          org_id: string
          price: number
          price_unit: string | null
          variation_id: string
        }
        Insert: {
          changed_by?: string | null
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          note?: string | null
          org_id?: string
          price: number
          price_unit?: string | null
          variation_id: string
        }
        Update: {
          changed_by?: string | null
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          note?: string | null
          org_id?: string
          price?: number
          price_unit?: string | null
          variation_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_price_history_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_price_history_variation_id_fkey"
            columns: ["variation_id"]
            isOneToOne: false
            referencedRelation: "wh_product_variations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_product_colors: {
        Row: {
          color_id: string
          price_modifier: number | null
          product_id: string
        }
        Insert: {
          color_id: string
          price_modifier?: number | null
          product_id: string
        }
        Update: {
          color_id?: string
          price_modifier?: number | null
          product_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_product_colors_color_id_fkey"
            columns: ["color_id"]
            isOneToOne: false
            referencedRelation: "wh_colors"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_product_colors_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "wh_products"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_product_families: {
        Row: {
          catalog_section: string | null
          compatible_systems: string[]
          created_at: string
          display_order: number
          id: string
          image_url: string | null
          member_conflicts: Json | null
          name: string
          org_id: string
          product_type: string | null
          slug: string | null
          status: string
          type_id: string | null
        }
        Insert: {
          catalog_section?: string | null
          compatible_systems?: string[]
          created_at?: string
          display_order?: number
          id?: string
          image_url?: string | null
          member_conflicts?: Json | null
          name: string
          org_id?: string
          product_type?: string | null
          slug?: string | null
          status?: string
          type_id?: string | null
        }
        Update: {
          catalog_section?: string | null
          compatible_systems?: string[]
          created_at?: string
          display_order?: number
          id?: string
          image_url?: string | null
          member_conflicts?: Json | null
          name?: string
          org_id?: string
          product_type?: string | null
          slug?: string | null
          status?: string
          type_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_product_families_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_product_families_type_id_fkey"
            columns: ["type_id"]
            isOneToOne: false
            referencedRelation: "wh_product_types"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_product_families_backup_20260828: {
        Row: {
          catalog_section: string | null
          compatible_systems: string[] | null
          created_at: string | null
          display_order: number | null
          id: string | null
          image_url: string | null
          member_conflicts: Json | null
          name: string | null
          org_id: string | null
          product_type: string | null
          slug: string | null
          status: string | null
          type_id: string | null
        }
        Insert: {
          catalog_section?: string | null
          compatible_systems?: string[] | null
          created_at?: string | null
          display_order?: number | null
          id?: string | null
          image_url?: string | null
          member_conflicts?: Json | null
          name?: string | null
          org_id?: string | null
          product_type?: string | null
          slug?: string | null
          status?: string | null
          type_id?: string | null
        }
        Update: {
          catalog_section?: string | null
          compatible_systems?: string[] | null
          created_at?: string | null
          display_order?: number | null
          id?: string | null
          image_url?: string | null
          member_conflicts?: Json | null
          name?: string | null
          org_id?: string | null
          product_type?: string | null
          slug?: string | null
          status?: string | null
          type_id?: string | null
        }
        Relationships: []
      }
      wh_product_roles: {
        Row: {
          created_at: string
          id: string
          key: string
          name: string
          note: string | null
          org_id: string
          product_id: string | null
          system_slug: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          key: string
          name: string
          note?: string | null
          org_id?: string
          product_id?: string | null
          system_slug?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          key?: string
          name?: string
          note?: string | null
          org_id?: string
          product_id?: string | null
          system_slug?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_product_roles_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_product_roles_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "wh_products"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_product_types: {
        Row: {
          attributes: Json
          coverage_mult: number | null
          created_at: string
          display_order: number
          id: string
          input_mode: string | null
          key: string
          name: string
          org_id: string
          pack_qty: number | null
          sold_in_packs: boolean
          takes_color: boolean
          takes_finish: boolean
          takes_gauge: boolean
          unit_factor: number | null
          waste_factor: number | null
        }
        Insert: {
          attributes?: Json
          coverage_mult?: number | null
          created_at?: string
          display_order?: number
          id?: string
          input_mode?: string | null
          key: string
          name: string
          org_id?: string
          pack_qty?: number | null
          sold_in_packs?: boolean
          takes_color?: boolean
          takes_finish?: boolean
          takes_gauge?: boolean
          unit_factor?: number | null
          waste_factor?: number | null
        }
        Update: {
          attributes?: Json
          coverage_mult?: number | null
          created_at?: string
          display_order?: number
          id?: string
          input_mode?: string | null
          key?: string
          name?: string
          org_id?: string
          pack_qty?: number | null
          sold_in_packs?: boolean
          takes_color?: boolean
          takes_finish?: boolean
          takes_gauge?: boolean
          unit_factor?: number | null
          waste_factor?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_product_types_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_product_variations: {
        Row: {
          coverage_width_in: number | null
          created_at: string
          display_order: number
          family_id: string
          finish: string | null
          gauge: string | null
          id: string
          image_url: string | null
          name: string
          org_id: string
          price: number | null
          price_unit: string | null
          sku: string | null
          source_product_id: string | null
          status: string
          type_id: string | null
        }
        Insert: {
          coverage_width_in?: number | null
          created_at?: string
          display_order?: number
          family_id: string
          finish?: string | null
          gauge?: string | null
          id?: string
          image_url?: string | null
          name: string
          org_id?: string
          price?: number | null
          price_unit?: string | null
          sku?: string | null
          source_product_id?: string | null
          status?: string
          type_id?: string | null
        }
        Update: {
          coverage_width_in?: number | null
          created_at?: string
          display_order?: number
          family_id?: string
          finish?: string | null
          gauge?: string | null
          id?: string
          image_url?: string | null
          name?: string
          org_id?: string
          price?: number | null
          price_unit?: string | null
          sku?: string | null
          source_product_id?: string | null
          status?: string
          type_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_product_variations_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "wh_product_families"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_product_variations_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_product_variations_source_product_id_fkey"
            columns: ["source_product_id"]
            isOneToOne: false
            referencedRelation: "wh_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_product_variations_type_id_fkey"
            columns: ["type_id"]
            isOneToOne: false
            referencedRelation: "wh_product_types"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_product_variations_backup_20260828: {
        Row: {
          coverage_width_in: number | null
          created_at: string | null
          display_order: number | null
          family_id: string | null
          finish: string | null
          gauge: string | null
          id: string | null
          image_url: string | null
          name: string | null
          org_id: string | null
          price: number | null
          price_unit: string | null
          sku: string | null
          source_product_id: string | null
          status: string | null
          type_id: string | null
        }
        Insert: {
          coverage_width_in?: number | null
          created_at?: string | null
          display_order?: number | null
          family_id?: string | null
          finish?: string | null
          gauge?: string | null
          id?: string | null
          image_url?: string | null
          name?: string | null
          org_id?: string | null
          price?: number | null
          price_unit?: string | null
          sku?: string | null
          source_product_id?: string | null
          status?: string | null
          type_id?: string | null
        }
        Update: {
          coverage_width_in?: number | null
          created_at?: string | null
          display_order?: number | null
          family_id?: string | null
          finish?: string | null
          gauge?: string | null
          id?: string | null
          image_url?: string | null
          name?: string | null
          org_id?: string | null
          price?: number | null
          price_unit?: string | null
          sku?: string | null
          source_product_id?: string | null
          status?: string | null
          type_id?: string | null
        }
        Relationships: []
      }
      wh_products: {
        Row: {
          active: boolean | null
          base_price: number | null
          catalog_section: string | null
          compatible_systems: string[] | null
          coverage_width_in: number | null
          created_at: string | null
          description: string | null
          display_order: number | null
          finish: string | null
          gauge: string | null
          id: string
          image_url: string | null
          name: string
          org_id: string
          product_type: string | null
          sku: string | null
          unit_size: string | null
          unit_type: string | null
        }
        Insert: {
          active?: boolean | null
          base_price?: number | null
          catalog_section?: string | null
          compatible_systems?: string[] | null
          coverage_width_in?: number | null
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          finish?: string | null
          gauge?: string | null
          id?: string
          image_url?: string | null
          name: string
          org_id: string
          product_type?: string | null
          sku?: string | null
          unit_size?: string | null
          unit_type?: string | null
        }
        Update: {
          active?: boolean | null
          base_price?: number | null
          catalog_section?: string | null
          compatible_systems?: string[] | null
          coverage_width_in?: number | null
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          finish?: string | null
          gauge?: string | null
          id?: string
          image_url?: string | null
          name?: string
          org_id?: string
          product_type?: string | null
          sku?: string | null
          unit_size?: string | null
          unit_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_products_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_products_backup_20260828: {
        Row: {
          active: boolean | null
          base_price: number | null
          catalog_section: string | null
          compatible_systems: string[] | null
          coverage_width_in: number | null
          created_at: string | null
          description: string | null
          display_order: number | null
          finish: string | null
          gauge: string | null
          id: string | null
          image_url: string | null
          name: string | null
          org_id: string | null
          product_type: string | null
          sku: string | null
          unit_size: string | null
          unit_type: string | null
        }
        Insert: {
          active?: boolean | null
          base_price?: number | null
          catalog_section?: string | null
          compatible_systems?: string[] | null
          coverage_width_in?: number | null
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          finish?: string | null
          gauge?: string | null
          id?: string | null
          image_url?: string | null
          name?: string | null
          org_id?: string | null
          product_type?: string | null
          sku?: string | null
          unit_size?: string | null
          unit_type?: string | null
        }
        Update: {
          active?: boolean | null
          base_price?: number | null
          catalog_section?: string | null
          compatible_systems?: string[] | null
          coverage_width_in?: number | null
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          finish?: string | null
          gauge?: string | null
          id?: string | null
          image_url?: string | null
          name?: string | null
          org_id?: string | null
          product_type?: string | null
          sku?: string | null
          unit_size?: string | null
          unit_type?: string | null
        }
        Relationships: []
      }
      wh_saved_cart_lines: {
        Row: {
          attributes: Json
          cart_id: string
          category_id: string | null
          color_id: string | null
          created_at: string
          description: string | null
          display_order: number
          id: string
          is_priceable: boolean
          length_in: number | null
          line_key: string
          org_id: string
          pricing_rule: string | null
          product_id: string | null
          quantity: number | null
          quantity_unit: string | null
          specs: string | null
          waste_units: number
        }
        Insert: {
          attributes?: Json
          cart_id: string
          category_id?: string | null
          color_id?: string | null
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          is_priceable?: boolean
          length_in?: number | null
          line_key?: string
          org_id?: string
          pricing_rule?: string | null
          product_id?: string | null
          quantity?: number | null
          quantity_unit?: string | null
          specs?: string | null
          waste_units?: number
        }
        Update: {
          attributes?: Json
          cart_id?: string
          category_id?: string | null
          color_id?: string | null
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          is_priceable?: boolean
          length_in?: number | null
          line_key?: string
          org_id?: string
          pricing_rule?: string | null
          product_id?: string | null
          quantity?: number | null
          quantity_unit?: string | null
          specs?: string | null
          waste_units?: number
        }
        Relationships: [
          {
            foreignKeyName: "wh_saved_cart_lines_cart_id_fkey"
            columns: ["cart_id"]
            isOneToOne: false
            referencedRelation: "wh_saved_carts"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_saved_carts: {
        Row: {
          created_at: string
          finish: string | null
          id: string
          mode: string | null
          name: string
          org_id: string
          roof_color_id: string | null
          system_slug: string | null
          trim_color_id: string | null
          trim_match: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          finish?: string | null
          id?: string
          mode?: string | null
          name: string
          org_id?: string
          roof_color_id?: string | null
          system_slug?: string | null
          trim_color_id?: string | null
          trim_match?: boolean
          updated_at?: string
          user_id?: string
        }
        Update: {
          created_at?: string
          finish?: string | null
          id?: string
          mode?: string | null
          name?: string
          org_id?: string
          roof_color_id?: string | null
          system_slug?: string | null
          trim_color_id?: string | null
          trim_match?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      wh_settings: {
        Row: {
          key: string
          org_id: string
          updated_at: string | null
          value: string | null
        }
        Insert: {
          key: string
          org_id?: string
          updated_at?: string | null
          value?: string | null
        }
        Update: {
          key?: string
          org_id?: string
          updated_at?: string | null
          value?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_settings_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_spec_files: {
        Row: {
          created_at: string | null
          description: string | null
          filename: string | null
          id: string
          order_id: string
          org_id: string
          storage_url: string | null
        }
        Insert: {
          created_at?: string | null
          description?: string | null
          filename?: string | null
          id?: string
          order_id: string
          org_id?: string
          storage_url?: string | null
        }
        Update: {
          created_at?: string | null
          description?: string | null
          filename?: string | null
          id?: string
          order_id?: string
          org_id?: string
          storage_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_spec_files_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "wh_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_spec_files_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_stages: {
        Row: {
          active: boolean
          display_order: number
          id: string
          name: string
          org_id: string
          status: string
          system_id: string
        }
        Insert: {
          active?: boolean
          display_order: number
          id?: string
          name: string
          org_id: string
          status?: string
          system_id: string
        }
        Update: {
          active?: boolean
          display_order?: number
          id?: string
          name?: string
          org_id?: string
          status?: string
          system_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_stages_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_stages_system_id_fkey"
            columns: ["system_id"]
            isOneToOne: false
            referencedRelation: "wh_systems"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_systems: {
        Row: {
          active: boolean | null
          created_at: string | null
          description: string | null
          display_order: number | null
          hero_image_url: string | null
          id: string
          name: string
          org_id: string
          slug: string
          tagline: string | null
        }
        Insert: {
          active?: boolean | null
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          hero_image_url?: string | null
          id?: string
          name: string
          org_id: string
          slug: string
          tagline?: string | null
        }
        Update: {
          active?: boolean | null
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          hero_image_url?: string | null
          id?: string
          name?: string
          org_id?: string
          slug?: string
          tagline?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_systems_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_tax_exemptions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          certificate_ref: string | null
          certificate_type: string | null
          created_at: string
          document_path: string | null
          expires_on: string | null
          id: string
          notes: string | null
          org_id: string
          status: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          certificate_ref?: string | null
          certificate_type?: string | null
          created_at?: string
          document_path?: string | null
          expires_on?: string | null
          id?: string
          notes?: string | null
          org_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          certificate_ref?: string | null
          certificate_type?: string | null
          created_at?: string
          document_path?: string | null
          expires_on?: string | null
          id?: string
          notes?: string | null
          org_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      wh_team_members: {
        Row: {
          created_at: string
          driver_active: boolean
          email: string
          id: string
          is_driver: boolean
          name: string
          org_id: string
          phone: string | null
          role: string
          status: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          driver_active?: boolean
          email: string
          id?: string
          is_driver?: boolean
          name: string
          org_id?: string
          phone?: string | null
          role?: string
          status?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          driver_active?: boolean
          email?: string
          id?: string
          is_driver?: boolean
          name?: string
          org_id?: string
          phone?: string | null
          role?: string
          status?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_team_members_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_variation_colors: {
        Row: {
          color_id: string
          created_at: string
          id: string
          org_id: string
          price_modifier: number | null
          variation_id: string
        }
        Insert: {
          color_id: string
          created_at?: string
          id?: string
          org_id?: string
          price_modifier?: number | null
          variation_id: string
        }
        Update: {
          color_id?: string
          created_at?: string
          id?: string
          org_id?: string
          price_modifier?: number | null
          variation_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_variation_colors_color_id_fkey"
            columns: ["color_id"]
            isOneToOne: false
            referencedRelation: "wh_colors"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_variation_colors_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wh_variation_colors_variation_id_fkey"
            columns: ["variation_id"]
            isOneToOne: false
            referencedRelation: "wh_product_variations"
            referencedColumns: ["id"]
          },
        ]
      }
      wh_variation_pricing: {
        Row: {
          needs_price_review: boolean
          org_id: string
          pricing_method: string | null
          pricing_value: number | null
          review_reason: string | null
          supplier_cost: number | null
          updated_at: string
          updated_by: string | null
          variation_id: string
        }
        Insert: {
          needs_price_review?: boolean
          org_id?: string
          pricing_method?: string | null
          pricing_value?: number | null
          review_reason?: string | null
          supplier_cost?: number | null
          updated_at?: string
          updated_by?: string | null
          variation_id: string
        }
        Update: {
          needs_price_review?: boolean
          org_id?: string
          pricing_method?: string | null
          pricing_value?: number | null
          review_reason?: string | null
          supplier_cost?: number | null
          updated_at?: string
          updated_by?: string | null
          variation_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wh_variation_pricing_variation_id_fkey"
            columns: ["variation_id"]
            isOneToOne: true
            referencedRelation: "wh_product_variations"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_acknowledgments: {
        Row: {
          acknowledged_at: string
          acknowledged_by: string
          id: string
          org_id: string
          work_order_id: string
          work_order_version: string
        }
        Insert: {
          acknowledged_at?: string
          acknowledged_by: string
          id?: string
          org_id: string
          work_order_id: string
          work_order_version: string
        }
        Update: {
          acknowledged_at?: string
          acknowledged_by?: string
          id?: string
          org_id?: string
          work_order_id?: string
          work_order_version?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_acknowledgments_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_acknowledgments_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
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
      work_order_agreements: {
        Row: {
          colors_finishes: Json
          created_at: string
          id: string
          org_id: string
          sent_at: string | null
          sign_token_hash: string | null
          signature_data: string | null
          signed_at: string | null
          signer_name: string | null
          signer_role: string | null
          snapshot: Json
          status: string
          updated_at: string
          void_cascade_prior_status: string | null
          void_cascade_source_id: string | null
          void_reason: string | null
          voided_at: string | null
          work_order_id: string
        }
        Insert: {
          colors_finishes?: Json
          created_at?: string
          id?: string
          org_id: string
          sent_at?: string | null
          sign_token_hash?: string | null
          signature_data?: string | null
          signed_at?: string | null
          signer_name?: string | null
          signer_role?: string | null
          snapshot: Json
          status?: string
          updated_at?: string
          void_cascade_prior_status?: string | null
          void_cascade_source_id?: string | null
          void_reason?: string | null
          voided_at?: string | null
          work_order_id: string
        }
        Update: {
          colors_finishes?: Json
          created_at?: string
          id?: string
          org_id?: string
          sent_at?: string | null
          sign_token_hash?: string | null
          signature_data?: string | null
          signed_at?: string | null
          signer_name?: string | null
          signer_role?: string | null
          snapshot?: Json
          status?: string
          updated_at?: string
          void_cascade_prior_status?: string | null
          void_cascade_source_id?: string | null
          void_reason?: string | null
          voided_at?: string | null
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_agreements_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_agreements_void_cascade_source_id_fkey"
            columns: ["void_cascade_source_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_agreements_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_crew_assignments: {
        Row: {
          created_at: string
          created_by: string | null
          crew_id: string
          id: string
          org_id: string
          task: string | null
          work_order_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          crew_id: string
          id?: string
          org_id: string
          task?: string | null
          work_order_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          crew_id?: string
          id?: string
          org_id?: string
          task?: string | null
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_crew_assignments_crew"
            columns: ["crew_id", "org_id"]
            isOneToOne: false
            referencedRelation: "crews"
            referencedColumns: ["id", "org_id"]
          },
          {
            foreignKeyName: "work_order_crew_assignments_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      work_order_objectives: {
        Row: {
          body: string
          id: string
          objective_date: string
          org_id: string
          published_at: string
          published_by: string | null
          updated_at: string
          work_order_id: string
        }
        Insert: {
          body: string
          id?: string
          objective_date?: string
          org_id: string
          published_at?: string
          published_by?: string | null
          updated_at?: string
          work_order_id: string
        }
        Update: {
          body?: string
          id?: string
          objective_date?: string
          org_id?: string
          published_at?: string
          published_by?: string | null
          updated_at?: string
          work_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_order_objectives_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_order_objectives_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      work_orders: {
        Row: {
          assignee_ref: string | null
          assignee_type: string | null
          created_at: string
          estimate_id: string
          id: string
          job_id: string
          kind: string
          org_id: string
          predecessor_id: string | null
          sign_off_at: string | null
          sign_off_notes: string | null
          trade: string | null
          updated_at: string
          void_cascade_source_id: string | null
          voided_at: string | null
        }
        Insert: {
          assignee_ref?: string | null
          assignee_type?: string | null
          created_at?: string
          estimate_id: string
          id?: string
          job_id: string
          kind?: string
          org_id: string
          predecessor_id?: string | null
          sign_off_at?: string | null
          sign_off_notes?: string | null
          trade?: string | null
          updated_at?: string
          void_cascade_source_id?: string | null
          voided_at?: string | null
        }
        Update: {
          assignee_ref?: string | null
          assignee_type?: string | null
          created_at?: string
          estimate_id?: string
          id?: string
          job_id?: string
          kind?: string
          org_id?: string
          predecessor_id?: string | null
          sign_off_at?: string | null
          sign_off_notes?: string | null
          trade?: string | null
          updated_at?: string
          void_cascade_source_id?: string | null
          voided_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "work_orders_estimate_id_fkey"
            columns: ["estimate_id"]
            isOneToOne: false
            referencedRelation: "estimates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_predecessor_id_fkey"
            columns: ["predecessor_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_void_cascade_source_id_fkey"
            columns: ["void_cascade_source_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      crew_assignment_states: {
        Row: {
          assignment_id: string | null
          availability_state: string | null
          crew_id: string | null
          crew_name: string | null
          end_date: string | null
          job_id: string | null
          members: number | null
          org_id: string | null
          schedule_block_id: string | null
          start_date: string | null
          task: string | null
          trade: string | null
          unavailable_members: number | null
          vehicle_state: string | null
          work_order_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "work_order_crew_assignments_crew"
            columns: ["crew_id", "org_id"]
            isOneToOne: false
            referencedRelation: "crews"
            referencedColumns: ["id", "org_id"]
          },
          {
            foreignKeyName: "work_order_crew_assignments_work_order_id_fkey"
            columns: ["work_order_id"]
            isOneToOne: false
            referencedRelation: "work_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_orders_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      take_off_lines: {
        Row: {
          description: string | null
          disposition: string | null
          disposition_source: string | null
          estimate_id: string | null
          estimate_line_item_id: string | null
          estimate_status: string | null
          item_state: string | null
          job_id: string | null
          material_item_id: string | null
          material_work_order_id: string | null
          org_id: string | null
          quantity: number | null
          scope_key: string | null
          sort_order: number | null
          trade_state: string | null
          trade_work_order_id: string | null
          unit: string | null
        }
        Relationships: []
      }
      wh_current_prices: {
        Row: {
          effective_from: string | null
          effective_to: string | null
          price: number | null
          price_unit: string | null
          variation_id: string | null
        }
        Insert: {
          effective_from?: string | null
          effective_to?: string | null
          price?: number | null
          price_unit?: string | null
          variation_id?: string | null
        }
        Update: {
          effective_from?: string | null
          effective_to?: string | null
          price?: number | null
          price_unit?: string | null
          variation_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wh_price_history_variation_id_fkey"
            columns: ["variation_id"]
            isOneToOne: false
            referencedRelation: "wh_product_variations"
            referencedColumns: ["id"]
          },
        ]
      }
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
      acknowledge_work_order: {
        Args: { p_work_order_id: string }
        Returns: Json
      }
      add_check_in_photo: {
        Args: { p_check_in_id: string; p_photo_data_url: string }
        Returns: undefined
      }
      add_crew_member: {
        Args: { p_crew_id: string; p_is_lead?: boolean; p_person_id: string }
        Returns: undefined
      }
      add_crew_person_unavailability: {
        Args: {
          p_ends_on: string
          p_person_id: string
          p_reason?: string
          p_starts_on: string
        }
        Returns: string
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
      add_purchase_order_line: {
        Args: {
          p_material_item_id: string
          p_po_id: string
          p_promised_date?: string
          p_quantity_ordered?: number
        }
        Returns: string
      }
      add_schedule_block: {
        Args: {
          p_crew_id?: string
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
      assert_work_order_level: {
        Args: { p_expected_kind: string; p_work_order_id: string }
        Returns: string
      }
      assign_crew_to_work_order: {
        Args: { p_crew_id: string; p_task?: string; p_work_order_id: string }
        Returns: Json
      }
      assign_deal_owner: {
        Args: { p_deal_id: string; p_owner_id?: string }
        Returns: undefined
      }
      build_roadmap_levels: {
        Args: { p_answers: Json; p_crew: number }
        Returns: Json
      }
      can_reach_work_order_files: {
        Args: { p_org_id: string }
        Returns: boolean
      }
      can_view_financials: { Args: { p_org_id: string }; Returns: boolean }
      can_view_master_work_order: {
        Args: { p_org_id: string }
        Returns: boolean
      }
      clear_check_in_hours: {
        Args: { p_check_in_id: string }
        Returns: undefined
      }
      clear_qc_item: {
        Args: { p_requirement_key: string; p_work_order_id: string }
        Returns: number
      }
      clear_work_order_objective: {
        Args: { p_objective_date?: string; p_work_order_id: string }
        Returns: undefined
      }
      complete_site_survey: {
        Args: { p_completed_at?: string; p_deal_id: string }
        Returns: undefined
      }
      create_check_in: {
        Args: {
          p_blockers?: string
          p_check_in_date?: string
          p_client_token?: string
          p_crew_id?: string
          p_crew_name: string
          p_hours?: number
          p_materials_used?: string
          p_schedule_block_id?: string
          p_work_order_id: string
        }
        Returns: string
      }
      create_crew: {
        Args: { p_name: string; p_org_id: string }
        Returns: string
      }
      create_crew_person: {
        Args: {
          p_full_name: string
          p_has_vehicle?: boolean
          p_org_id: string
          p_phone?: string
          p_preferred_language?: string
          p_skills?: string[]
          p_user_id?: string
          p_vehicle_note?: string
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
      create_estimate_sign_link: {
        Args: { p_estimate_id: string; p_valid_days: number }
        Returns: Json
      }
      create_job_from_estimate: {
        Args: { p_estimate_id: string }
        Returns: Json
      }
      create_organization: {
        Args: { p_name: string; p_tenant_type: string; p_trade?: string }
        Returns: string
      }
      create_product: {
        Args: {
          p_category?: string
          p_cost?: number
          p_markup?: number
          p_name: string
          p_org_id: string
          p_price_method?: string
          p_price_value?: number
          p_sell?: number
          p_unit?: string
        }
        Returns: string
      }
      create_purchase_order: {
        Args: {
          p_job_id?: string
          p_org_id: string
          p_supplier_name: string
          p_supplier_org_id?: string
        }
        Returns: string
      }
      create_roadmap_item: {
        Args: {
          p_feature: string
          p_notes?: string
          p_org_id: string
          p_phase: string
          p_project_id: string
          p_section: string
          p_sort_order?: number
          p_status?: string
        }
        Returns: string
      }
      create_roadmap_project: {
        Args: {
          p_key: string
          p_name: string
          p_org_id: string
          p_sort_order?: number
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
      create_trade_work_order: {
        Args: {
          p_assignee_ref?: string
          p_assignee_type?: string
          p_master_work_order_id: string
          p_predecessor_id?: string
          p_trade: string
        }
        Returns: string
      }
      create_wh_order: {
        Args: {
          p_line_items?: Json
          p_order: Json
          p_org_id?: string
          p_spec_files?: Json
        }
        Returns: Json
      }
      create_work_order_agreement: {
        Args: { p_work_order_id: string }
        Returns: string
      }
      crew_assert_can_manage: { Args: { p_org_id: string }; Returns: undefined }
      crew_check_login: {
        Args: { p_org_id: string; p_person_id: string; p_user_id: string }
        Returns: undefined
      }
      crm_follow_up_cadence_days: {
        Args: { p_org_id: string }
        Returns: number[]
      }
      crm_follow_up_cadence_days_internal: {
        Args: { p_org_id: string }
        Returns: number[]
      }
      crm_stage_config: { Args: { p_org_id: string }; Returns: Json }
      crm_stage_config_internal: { Args: { p_org_id: string }; Returns: Json }
      crm_stage_entry: {
        Args: { p_org_id: string; p_stage_key: string }
        Returns: Json
      }
      crm_stage_entry_internal: {
        Args: { p_org_id: string; p_stage_key: string }
        Returns: Json
      }
      default_permissions_for_role: { Args: { p_role: string }; Returns: Json }
      delete_check_in: { Args: { p_check_in_id: string }; Returns: undefined }
      delete_crew: { Args: { p_crew_id: string }; Returns: undefined }
      delete_crew_person: { Args: { p_person_id: string }; Returns: undefined }
      delete_crew_person_unavailability: {
        Args: { p_unavailability_id: string }
        Returns: undefined
      }
      delete_estimate: { Args: { p_estimate_id: string }; Returns: undefined }
      delete_estimate_line_item: {
        Args: { p_line_item_id: string }
        Returns: undefined
      }
      delete_material_item: {
        Args: { p_material_item_id: string }
        Returns: undefined
      }
      delete_product: { Args: { p_product_id: string }; Returns: undefined }
      delete_production_packet: {
        Args: { p_production_packet_id: string }
        Returns: undefined
      }
      delete_production_packet_callout: {
        Args: { p_callout_id: string; p_production_packet_id: string }
        Returns: undefined
      }
      delete_purchase_order: { Args: { p_po_id: string }; Returns: undefined }
      delete_purchase_order_line: {
        Args: { p_line_id: string }
        Returns: undefined
      }
      delete_roadmap_item: { Args: { p_id: string }; Returns: undefined }
      delete_roadmap_project: {
        Args: { p_project_id: string }
        Returns: undefined
      }
      delete_schedule_block: {
        Args: { p_schedule_block_id: string }
        Returns: undefined
      }
      delete_special_trip: {
        Args: { p_special_trip_id: string }
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
      derive_catalog_price: {
        Args: { p_cost: number; p_markup: number; p_sell: number }
        Returns: {
          out_markup: number
          out_sell: number
        }[]
      }
      estimate_signing_document: {
        Args: { p_estimate_id: string }
        Returns: Json
      }
      fetch_check_in: {
        Args: { p_check_in_id: string }
        Returns: {
          blockers: string | null
          check_in_date: string
          client_token: string | null
          created_at: string
          created_by: string | null
          crew_id: string | null
          crew_name: string
          hours: number | null
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
      fetch_crew_roster: { Args: { p_org_id: string }; Returns: Json }
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
      fetch_field_jobs: {
        Args: { p_org_id: string; p_today?: string }
        Returns: Json
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
          policy: Json
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
      fetch_product: {
        Args: { p_product_id: string }
        Returns: {
          active: boolean
          category: string | null
          cost: number | null
          created_at: string
          created_by: string | null
          id: string
          markup: number | null
          name: string
          org_id: string
          price_method: string | null
          price_review_reason: string | null
          price_value: number | null
          sell: number | null
          unit: string | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "products"
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
      fetch_purchase_order: {
        Args: { p_po_id: string }
        Returns: {
          created_at: string
          created_by: string | null
          id: string
          job_id: string | null
          notes: string | null
          org_id: string
          reference: string | null
          status: string
          supplier_name: string
          supplier_org_id: string | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "purchase_orders"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_roadmap_by_token: {
        Args: { p_token: string }
        Returns: {
          client_name: string
          company: string
          created_at: string
          crew_size: number
          id: string
          levels: Json
          revenue_leak_monthly: number
          risk_level: string
          score: number
          status: string
          trade: string
          updated_at: string
        }[]
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
          assignee_ref: string | null
          assignee_type: string | null
          created_at: string
          estimate_id: string
          id: string
          job_id: string
          kind: string
          org_id: string
          predecessor_id: string | null
          sign_off_at: string | null
          sign_off_notes: string | null
          trade: string | null
          updated_at: string
          void_cascade_source_id: string | null
          voided_at: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "work_orders"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_work_order_agreement: {
        Args: { p_work_order_id: string }
        Returns: {
          colors_finishes: Json
          created_at: string
          id: string
          org_id: string
          sent_at: string | null
          sign_token_hash: string | null
          signature_data: string | null
          signed_at: string | null
          signer_name: string | null
          signer_role: string | null
          snapshot: Json
          status: string
          updated_at: string
          void_cascade_prior_status: string | null
          void_cascade_source_id: string | null
          void_reason: string | null
          voided_at: string | null
          work_order_id: string
        }[]
        SetofOptions: {
          from: "*"
          to: "work_order_agreements"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_work_order_brief: {
        Args: { p_work_order_id: string }
        Returns: Json
      }
      fetch_work_order_tree: {
        Args: { p_work_order_id: string }
        Returns: Json
      }
      generate_roadmap_for_lead: {
        Args: { p_lead_id: string }
        Returns: string
      }
      get_or_create_production_packet: {
        Args: { p_work_order_id: string }
        Returns: string
      }
      has_capability: {
        Args: { p_capability: string; p_org_id: string }
        Returns: boolean
      }
      is_manager_role: { Args: { p_role: string }; Returns: boolean }
      is_org_manager: { Args: { p_org_id: string }; Returns: boolean }
      is_pipeline_manager: { Args: never; Returns: boolean }
      is_pipeline_user: { Args: never; Returns: boolean }
      is_platform_admin: { Args: never; Returns: boolean }
      is_qc_attester: { Args: { p_org_id: string }; Returns: boolean }
      is_staff: { Args: never; Returns: boolean }
      is_wh_owner: { Args: never; Returns: boolean }
      job_master_sign_off: {
        Args: { p_work_order_id: string }
        Returns: {
          master_id: string
          sign_off_at: string
        }[]
      }
      list_org_members: {
        Args: { p_org_id: string }
        Returns: {
          full_name: string
          user_id: string
        }[]
      }
      list_products: {
        Args: { p_include_inactive?: boolean; p_org_id: string }
        Returns: {
          active: boolean
          category: string | null
          cost: number | null
          created_at: string
          created_by: string | null
          id: string
          markup: number | null
          name: string
          org_id: string
          price_method: string | null
          price_review_reason: string | null
          price_value: number | null
          sell: number | null
          unit: string | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "products"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_purchase_orders: {
        Args: { p_job_id?: string; p_org_id: string }
        Returns: {
          created_at: string
          created_by: string | null
          id: string
          job_id: string | null
          notes: string | null
          org_id: string
          reference: string | null
          status: string
          supplier_name: string
          supplier_org_id: string | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "purchase_orders"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      materialize_take_off: { Args: { p_job_id: string }; Returns: Json }
      member_display_name: {
        Args: { p_org_id: string; p_user_id: string }
        Returns: string
      }
      my_active_lead_count: { Args: never; Returns: number }
      my_avg_cycle_days: { Args: never; Returns: number }
      my_closes_this_month: { Args: never; Returns: number }
      my_open_pipeline_value: { Args: never; Returns: number }
      my_org_ids: { Args: never; Returns: string[] }
      my_pipeline_role: {
        Args: never
        Returns: Database["public"]["Enums"]["pipeline_user_role"]
      }
      my_wh_org_ids: { Args: never; Returns: string[] }
      my_wh_role: { Args: never; Returns: string }
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
      price_from_method: {
        Args: { p_cost: number; p_method: string; p_value: number }
        Returns: number
      }
      qc_photo_on_work_order: {
        Args: { p_photo_ref: string; p_work_order_id: string }
        Returns: boolean
      }
      recompute_material_item_ready_by: {
        Args: { p_material_item_id: string }
        Returns: undefined
      }
      record_field_event: {
        Args: {
          p_client_sent_at?: string
          p_duration_ms?: number
          p_event: string
          p_org_id: string
          p_outcome?: string
          p_subject_ref?: string
          p_work_order_id?: string
        }
        Returns: number
      }
      record_qc_item: {
        Args: {
          p_count_value?: number
          p_kind: string
          p_photo_ref?: string
          p_requirement_key: string
          p_work_order_id: string
        }
        Returns: string
      }
      record_signed_copy_outcome: {
        Args: {
          p_provider_message_id?: string
          p_signature_id: string
          p_state: string
        }
        Returns: Json
      }
      record_signed_copy_outcome_by_link: {
        Args: {
          p_provider_message_id?: string
          p_state: string
          p_token: string
        }
        Returns: Json
      }
      record_special_trip: {
        Args: {
          p_client_token?: string
          p_note?: string
          p_occurred_on?: string
          p_reason_code: string
          p_work_order_id: string
        }
        Returns: string
      }
      record_work_order_sign_off: {
        Args: { p_notes?: string; p_work_order_id: string }
        Returns: undefined
      }
      remove_check_in_photo: {
        Args: { p_check_in_id: string; p_photo_data_url: string }
        Returns: undefined
      }
      remove_crew_member: {
        Args: { p_crew_id: string; p_person_id: string }
        Returns: undefined
      }
      rename_crew: {
        Args: { p_crew_id: string; p_name: string }
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
      revoke_estimate_sign_link: {
        Args: { p_link_id: string }
        Returns: undefined
      }
      roadmap_playbook: { Args: { q: string }; Returns: Json }
      role_capability_matrix: {
        Args: never
        Returns: {
          allowed: boolean
          capability: string
          manager_tier: boolean
          role: string
        }[]
      }
      set_crew_archived: {
        Args: { p_archived: boolean; p_crew_id: string }
        Returns: undefined
      }
      set_crew_person_archived: {
        Args: { p_archived: boolean; p_person_id: string }
        Returns: undefined
      }
      set_member_capability: {
        Args: {
          p_capability: string
          p_org_id: string
          p_user_id: string
          p_value: boolean
        }
        Returns: undefined
      }
      set_take_off_decision: {
        Args: {
          p_disposition: string
          p_estimate_line_item_id: string
          p_work_order_id?: string
        }
        Returns: Json
      }
      set_tenant_module: {
        Args: {
          p_config?: Json
          p_enabled?: boolean
          p_module_key: string
          p_org_id: string
        }
        Returns: string
      }
      set_work_order_objective: {
        Args: {
          p_body: string
          p_objective_date?: string
          p_work_order_id: string
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
      sign_estimate_by_link: {
        Args: {
          p_document_version: string
          p_signature_data: string
          p_signer_name: string
          p_signer_role: string
          p_token: string
        }
        Returns: Json
      }
      signed_copy_by_link: { Args: { p_token: string }; Returns: Json }
      signed_copy_link_resolve: { Args: { p_token: string }; Returns: Json }
      signing_link_resolve: { Args: { p_token: string }; Returns: Json }
      signing_link_view: { Args: { p_token: string }; Returns: Json }
      tenant_enforces_stage_gating: {
        Args: { p_org_id: string }
        Returns: boolean
      }
      tenant_scopes_field_jobs_to_crew: {
        Args: { p_org_id: string }
        Returns: boolean
      }
      tracker_status_config: { Args: { p_org_id: string }; Returns: Json }
      tracker_type_config: { Args: { p_org_id: string }; Returns: Json }
      unassign_crew_from_work_order: {
        Args: { p_assignment_id: string }
        Returns: undefined
      }
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
      update_crew_person: {
        Args: { p_patch: Json; p_person_id: string }
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
      update_product: {
        Args: { p_patch: Json; p_product_id: string }
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
      update_purchase_order: {
        Args: {
          p_job_id?: string
          p_po_id: string
          p_status?: string
          p_supplier_name?: string
          p_supplier_org_id?: string
        }
        Returns: undefined
      }
      update_purchase_order_line: {
        Args: {
          p_line_id: string
          p_promised_date?: string
          p_quantity_ordered?: number
        }
        Returns: undefined
      }
      update_roadmap_fields: {
        Args: { p_id: string; p_patch: Json }
        Returns: undefined
      }
      update_roadmap_project: {
        Args: { p_name?: string; p_project_id: string; p_sort_order?: number }
        Returns: undefined
      }
      update_schedule_block: {
        Args: {
          p_crew_id?: string
          p_crew_name?: string
          p_end_date?: string
          p_schedule_block_id: string
          p_start_date?: string
          p_unlink_crew?: boolean
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
      wh_ack_price_review: {
        Args: { p_variation_id: string }
        Returns: undefined
      }
      wh_attach_order_by_token: { Args: { p_token: string }; Returns: Json }
      wh_auth_login_for_email: {
        Args: { p_email: string }
        Returns: {
          created_at: string
          last_sign_in_at: string
          user_id: string
        }[]
      }
      wh_catalog_clear_preview: { Args: never; Returns: Json }
      wh_catalog_delete_scope: {
        Args: { p_family_ids: string[]; p_product_ids: string[] }
        Returns: Json
      }
      wh_claim_order_delivery: { Args: { p_order_id: string }; Returns: Json }
      wh_claim_order_send: { Args: { p_order_id: string }; Returns: Json }
      wh_clear_catalog: { Args: { p_confirm: string }; Returns: Json }
      wh_clear_colors: { Args: { p_confirm: string }; Returns: Json }
      wh_colors_clear_preview: { Args: never; Returns: Json }
      wh_colors_delete_scope: { Args: { p_color_ids: string[] }; Returns: Json }
      wh_customer_order_json: { Args: { p_order_id: string }; Returns: Json }
      wh_delete_system: {
        Args: { p_confirm: string; p_system_id: string }
        Returns: Json
      }
      wh_get_family_pricing: {
        Args: { p_family_id: string }
        Returns: {
          cost_effective_from: string
          needs_price_review: boolean
          pricing_method: string
          pricing_value: number
          review_reason: string
          supplier_cost: number
          variation_id: string
        }[]
      }
      wh_my_attached_orders: { Args: never; Returns: Json }
      wh_new_order_access_token: { Args: never; Returns: string }
      wh_order_by_token: { Args: { p_token: string }; Returns: Json }
      wh_order_id_for_token: { Args: { p_token: string }; Returns: string }
      wh_release_order_delivery: { Args: { p_order_id: string }; Returns: Json }
      wh_release_order_send: {
        Args: { p_order_id: string; p_reason: string }
        Returns: Json
      }
      wh_save_catalog_family: {
        Args: { p_family: Json; p_variations: Json }
        Returns: Json
      }
      wh_set_coverage_width: {
        Args: { p_variation_id: string; p_width: number }
        Returns: undefined
      }
      wh_set_unit_size: {
        Args: { p_unit_size: string; p_variation_id: string }
        Returns: undefined
      }
      wh_set_variation_pricing: {
        Args: {
          p_cost: number
          p_method: string
          p_note?: string
          p_value: number
          p_variation_id: string
        }
        Returns: Json
      }
      wh_setting_is_protected: { Args: { p_key: string }; Returns: boolean }
      wh_system_delete_preview: { Args: { p_system_id: string }; Returns: Json }
      work_order_is_my_trade: {
        Args: { p_work_order_id: string }
        Returns: boolean
      }
      work_order_version: { Args: { p_work_order_id: string }; Returns: string }
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
