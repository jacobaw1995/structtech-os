-- The Project Repairs bot is retired. Its data was exported first. This is the whole
-- system: because it never wrote outside its own schema, one drop removes all of it
-- and nothing in public or the BMR tenant account is affected.
drop schema if exists bmr_tickets cascade;
