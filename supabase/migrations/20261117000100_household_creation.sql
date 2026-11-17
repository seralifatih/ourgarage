-- Household creation as a normal authenticated user.
--
-- The bug (2026-11-17, build 1.0.8+13 on a real iPad): the app creates its
-- household with
--
--   POST /rest/v1/households?select=id   {name, owner_id}
--
-- which PostgREST runs as INSERT ... RETURNING id. When a statement returns
-- rows, Postgres also requires each new row to pass the table's SELECT
-- policies, and it checks that right after the row is inserted. The only
-- SELECT policy was "caller is a member" — and the caller's owner membership
-- is written by the AFTER INSERT trigger add_owner_membership(), which has not
-- run yet at that point. So every client-side household creation failed with
-- 42501 "new row violates row-level security policy for table households",
-- even though the INSERT policy itself (owner_id = caller) was satisfied.
--
-- Nothing caught it because every test created households as a role that
-- bypasses RLS (superuser in household_isolation_test.sql, service role in
-- e2e_delete_account.py). See e2e_household_creation.py and the new block in
-- household_isolation_test.sql.
--
-- This migration:
--   1. Lets the owner of a household see it (fixes the shipped build as is).
--   2. Narrows what a client may write on INSERT to name and owner_id, and
--      guards the premium columns on INSERT the way they were already guarded
--      on UPDATE. Before this, nothing stopped a client sending
--      {"is_premium": true} when creating a household.
--   3. Adds create_household(), the path newer builds use: one call that
--      creates the household (and, via the trigger, the owner's membership)
--      for the caller, with owner_id taken from the JWT, not the request.

-- ---------------------------------------------------------------------------
-- 1. Owners can see their own household
-- ---------------------------------------------------------------------------

-- Permissive policies are OR'd, so this sits alongside households_select_member.
-- It never widens visibility in practice: an owner is always also a member
-- (the trigger adds the row), except in the moment between the INSERT and the
-- trigger — which is exactly the moment RETURNING needs to see the row.
create policy households_select_owner on public.households
  for select to authenticated
  using (owner_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 2. Premium columns cannot be set on INSERT either
-- ---------------------------------------------------------------------------

-- Same mechanism as the UPDATE grants in the sharing-layer migration: column
-- privileges are what actually enforce it. The shipped app sends exactly
-- {name, owner_id}, so this does not break it.
revoke insert on public.households from anon, authenticated;
grant insert (name, owner_id) on public.households to authenticated;

-- The same name rule create_household() applies, for clients that insert
-- directly (build 13) or rename. NOT VALID: enforced on every new or updated
-- row from now on, without failing the migration over any existing row.
alter table public.households
  add constraint households_name_length
  check (length(btrim(name)) between 1 and 100) not valid;

-- Defence in depth, mirroring guard_household_premium_columns() for UPDATE: if
-- a future migration re-grants INSERT on the whole table, a client still
-- cannot create a household that is already premium.
create function public.guard_household_premium_columns_on_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    if new.is_premium
      or new.premium_source_user_id is not null
      or new.premium_expires_at is not null
    then
      raise exception
        'Premium columns are written only by the RevenueCat webhook'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

create trigger households_guard_premium_columns_on_insert
  before insert on public.households
  for each row
  execute function public.guard_household_premium_columns_on_insert();

-- ---------------------------------------------------------------------------
-- 3. create_household()
-- ---------------------------------------------------------------------------

-- Creates a household owned by the caller and returns its id. The owner's
-- household_members row comes from the existing AFTER INSERT trigger, inside
-- this same statement, so the two are atomic.
--
-- SECURITY DEFINER so it does not depend on the RLS/RETURNING interplay above
-- at all; in exchange, everything a client could lie about is decided here:
-- the owner is always auth.uid(), and only the name comes from the request.
-- search_path is pinned and every identifier qualified, for the reasons given
-- on is_household_member().
--
-- It does not refuse a second household. The client only calls it when
-- getHouseholdId() found none, and a uniqueness rule belongs in its own
-- migration with a decision about what multi-household means, not as a side
-- effect here.
create function public.create_household(household_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  trimmed text := btrim(coalesce(household_name, ''));
  new_id uuid;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if trimmed = '' then
    raise exception 'Household name is required' using errcode = '22023';
  end if;

  if length(trimmed) > 100 then
    raise exception 'Household name is too long' using errcode = '22023';
  end if;

  -- households.owner_id references profiles; a clearer error than the FK one.
  if not exists (select 1 from public.profiles where id = caller) then
    raise exception 'Profile missing' using errcode = 'P0002';
  end if;

  insert into public.households (name, owner_id)
  values (trimmed, caller)
  returning id into new_id;

  return new_id;
end;
$$;

revoke execute on function public.create_household(text) from public, anon;
grant execute on function public.create_household(text) to authenticated;
