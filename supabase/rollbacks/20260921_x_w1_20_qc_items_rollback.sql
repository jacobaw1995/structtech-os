-- ROLLBACK for 20260922004806_x_w1_20_qc_items (applied 2026-09-21 20:48 EDT by Track S).
-- Removes the QC checklist entirely, including every recorded and cleared row — not recoverable afterwards.
drop function if exists public.clear_qc_item(uuid, text);
drop function if exists public.record_qc_item(uuid, text, text, text, integer);
drop table if exists public.qc_items;
