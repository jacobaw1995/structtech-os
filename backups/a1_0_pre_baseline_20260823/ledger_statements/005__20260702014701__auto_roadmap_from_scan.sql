-- ============================================================
-- AUTO-ROADMAP BRAINS
-- Every audit_leads insert auto-creates a client_roadmaps row.
-- The playbook maps each question area (q1-q10) to a pre-built
-- level: title, why, and milestones (StructTech builds vs client homework).
-- The 3 lowest-scoring areas become Levels 1-3 (worst first).
-- ============================================================

create or replace function public.roadmap_playbook(q text)
returns jsonb language sql immutable as $$
select case q
  when 'q1' then '{
    "title": "Instant Lead Response System",
    "why": "Speed wins jobs. The contractor who answers first gets the walkthrough — this system makes sure that is always you, even when you are on a roof.",
    "milestones": [
      {"label":"StructTech builds instant text-back + lead capture system for every call and form fill","owner":"jacob"},
      {"label":"Connect your business phone number and website forms","owner":"client"},
      {"label":"Every new lead answered in under 5 minutes for 2 straight weeks","owner":"client"}
    ]}'::jsonb
  when 'q2' then '{
    "title": "Estimate Follow-Up Engine",
    "why": "Most estimates die from silence, not price. Automatic follow-ups at day 2, 5, and 10 revive jobs you already quoted.",
    "milestones": [
      {"label":"StructTech builds automated estimate follow-up sequence (text + email)","owner":"jacob"},
      {"label":"Review and approve the follow-up message templates","owner":"client"},
      {"label":"Win one job from a revived estimate","owner":"client"}
    ]}'::jsonb
  when 'q3' then '{
    "title": "Field-to-Office Communication Flow",
    "why": "Work happens in the field but the office finds out whenever someone remembers to mention it. This closes that gap the same day.",
    "milestones": [
      {"label":"StructTech builds crew check-in system — photos, hours, materials in 5 minutes","owner":"jacob"},
      {"label":"Train crew lead on the daily check-in","owner":"client"},
      {"label":"Two full weeks of consistent daily logs from every active job","owner":"client"}
    ]}'::jsonb
  when 'q4' then '{
    "title": "Real-Time Job Cost Tracking",
    "why": "If you cannot see what a job actually costs while it is running, you find out you lost money after it is too late to fix.",
    "milestones": [
      {"label":"StructTech builds per-job cost tracker — labor, materials, margin at a glance","owner":"jacob"},
      {"label":"Log labor and material costs on your current jobs for 2 weeks","owner":"client"},
      {"label":"Five jobs fully costed — know your real margin on each","owner":"client"}
    ]}'::jsonb
  when 'q5' then '{
    "title": "One Hub, Fewer Apps",
    "why": "Every app your data hops between is a place it gets lost. We consolidate into one hub your whole crew actually uses.",
    "milestones": [
      {"label":"StructTech builds unified ops hub and migrates your existing data","owner":"jacob"},
      {"label":"Pick the 2 redundant tools to cancel and confirm nothing breaks","owner":"client"},
      {"label":"Whole crew working out of one system for 2 weeks","owner":"client"}
    ]}'::jsonb
  when 'q6' then '{
    "title": "Key-Person Backup System",
    "why": "If one person getting sick stops your operation, you do not have a system — you have a liability. We document and cross-train it out.",
    "milestones": [
      {"label":"StructTech documents your critical workflows into simple SOPs","owner":"jacob"},
      {"label":"Pick a backup person for each critical role","owner":"client"},
      {"label":"Backup person runs the workflow solo for one full week","owner":"client"}
    ]}'::jsonb
  when 'q7' then '{
    "title": "Same-Day Invoicing System",
    "why": "Every day an invoice sits unsent is a day you are funding your client''s business instead of yours. Invoice the day the job closes.",
    "milestones": [
      {"label":"StructTech builds automated invoice generation tied to job completion","owner":"jacob"},
      {"label":"Connect your accounting software (QuickBooks or similar)","owner":"client"},
      {"label":"Send your first same-day invoice on a real job","owner":"client"}
    ]}'::jsonb
  when 'q8' then '{
    "title": "Visual Crew Scheduling Board",
    "why": "Scheduling from memory and texts means double-booked crews and dead days. One board, whole week visible, no surprises.",
    "milestones": [
      {"label":"StructTech builds visual scheduling board for jobs and crew assignments","owner":"jacob"},
      {"label":"Load your current jobs and crew into the board","owner":"client"},
      {"label":"Two weeks with zero scheduling conflicts or dead days","owner":"client"}
    ]}'::jsonb
  when 'q9' then '{
    "title": "Automated Client Updates",
    "why": "Clients who know what is happening do not call, do not stress, and do not dispute scope. En-route texts and progress updates run themselves.",
    "milestones": [
      {"label":"StructTech builds automated client updates — en-route, daily progress, completion","owner":"jacob"},
      {"label":"Approve the client message templates","owner":"client"},
      {"label":"Run one full job with automated updates start to finish","owner":"client"}
    ]}'::jsonb
  when 'q10' then '{
    "title": "Owner Independence Dashboard",
    "why": "The business should run when you take a day off. This gets you out of every single decision without losing visibility.",
    "milestones": [
      {"label":"StructTech builds owner dashboard — jobs, cash, crew at a glance","owner":"jacob"},
      {"label":"Delegate scheduling and invoicing to your second-in-command","owner":"client"},
      {"label":"Take a full day off — business runs without a single call to you","owner":"client"}
    ]}'::jsonb
  else null
end $$;

create or replace function public.auto_create_roadmap()
returns trigger language plpgsql security definer as $$
declare
  worst record;
  lvls jsonb := '[]'::jsonb;
  pb jsonb;
  ms jsonb;
  li int := 0;
  mi int;
  built_ms jsonb;
begin
  -- pick the 3 lowest-scoring questions (worst first, q-order tiebreak)
  for worst in
    select key as q, (value)::int as score
    from jsonb_each_text(coalesce(new.answers, '{}'::jsonb))
    where key ~ '^q([1-9]|10)$'
    order by (value)::int asc, substring(key from 2)::int asc
    limit 3
  loop
    pb := public.roadmap_playbook(worst.q);
    if pb is null then continue; end if;

    built_ms := '[]'::jsonb;
    mi := 0;
    for ms in select * from jsonb_array_elements(pb->'milestones')
    loop
      built_ms := built_ms || jsonb_build_array(jsonb_build_object(
        'id', 'l' || li || 'm' || mi,
        'label', ms->>'label',
        'owner', ms->>'owner',
        'done', false,
        'done_at', null
      ));
      mi := mi + 1;
    end loop;

    lvls := lvls || jsonb_build_array(jsonb_build_object(
      'title', pb->>'title',
      'why', pb->>'why',
      'area', worst.q,
      'milestones', built_ms
    ));
    li := li + 1;
  end loop;

  if jsonb_array_length(lvls) > 0 then
    insert into public.client_roadmaps
      (client_name, company, trade, crew_size, score, risk_level, revenue_leak_monthly, levels)
    values
      (coalesce(new.name,'—'), coalesce(new.company,'—'), new.trade, new.crew_size,
       new.score, new.risk_level, new.monthly_leak, lvls);
  end if;

  return new;
end $$;

drop trigger if exists trg_auto_roadmap on public.audit_leads;
create trigger trg_auto_roadmap
  after insert on public.audit_leads
  for each row execute function public.auto_create_roadmap();
