create policy "insert roadmap" on public.client_roadmaps
  for insert to anon with check (true);
