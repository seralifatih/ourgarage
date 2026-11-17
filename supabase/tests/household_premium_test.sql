-- Assertions for apply_household_premium() (migration 20261117000300).
--
-- Run against a Supabase database, like the other files here, e.g.:
--   supabase db query --linked -f supabase/tests/household_premium_test.sql
--
-- Plain SQL, every check raises on failure, all inside a transaction that is
-- rolled back, so it leaves no rows behind.
--
-- Fixture: household P (…00f1) with members Alma (owner) and Ben, plus Cleo,
-- who is not a member. Each case resets P's premium columns, calls the
-- function with a list of entitlements (as the Edge Functions would, after
-- asking RevenueCat), and checks the outcome.

begin;

insert into auth.users (id, email)
values
  ('a1a1a1a1-0000-0000-0000-0000000000a1', 'alma@example.com'),
  ('b2b2b2b2-0000-0000-0000-0000000000b2', 'ben@example.com'),
  ('c3c3c3c3-0000-0000-0000-0000000000c3', 'cleo@example.com');

insert into public.profiles (id, display_name)
values
  ('a1a1a1a1-0000-0000-0000-0000000000a1', 'Alma'),
  ('b2b2b2b2-0000-0000-0000-0000000000b2', 'Ben'),
  ('c3c3c3c3-0000-0000-0000-0000000000c3', 'Cleo');

insert into public.households (id, name, owner_id)
values ('f1f1f1f1-0000-0000-0000-0000000000f1', 'Household P',
        'a1a1a1a1-0000-0000-0000-0000000000a1');

insert into public.household_members (household_id, user_id, role)
values ('f1f1f1f1-0000-0000-0000-0000000000f1',
        'b2b2b2b2-0000-0000-0000-0000000000b2', 'member');

-- Helpers for the cases below; dropped with the rollback.
create function pg_temp.set_premium(premium boolean, source uuid, expires timestamptz)
returns void language sql as $$
  update public.households
  set is_premium = premium, premium_source_user_id = source, premium_expires_at = expires
  where id = 'f1f1f1f1-0000-0000-0000-0000000000f1';
$$;

create function pg_temp.ent(uid uuid, active boolean, expires timestamptz)
returns jsonb language sql as $$
  select jsonb_build_object('user_id', uid, 'active', active, 'expires_at', expires);
$$;

do $$
declare
  p constant uuid := 'f1f1f1f1-0000-0000-0000-0000000000f1';
  alma constant uuid := 'a1a1a1a1-0000-0000-0000-0000000000a1';
  ben constant uuid := 'b2b2b2b2-0000-0000-0000-0000000000b2';
  cleo constant uuid := 'c3c3c3c3-0000-0000-0000-0000000000c3';
  in_a_month constant timestamptz := now() + interval '1 month';
  in_a_year constant timestamptz := now() + interval '1 year';
  h public.households%rowtype;
  result jsonb;
begin
  -- 1. One member's expiry can't wipe premium another provides.
  perform pg_temp.set_premium(true, alma, null);
  perform public.apply_household_premium(p, jsonb_build_array(
    pg_temp.ent(ben, false, null), pg_temp.ent(alma, true, null)));
  select * into h from public.households where id = p;
  if not h.is_premium or h.premium_source_user_id <> alma or h.premium_expires_at is not null then
    raise exception '1: Ben''s lapse disturbed Alma''s lifetime premium';
  end if;

  -- 2. A source missing from the report is unknown, not lapsed.
  perform public.apply_household_premium(p, jsonb_build_array(pg_temp.ent(ben, false, null)));
  select * into h from public.households where id = p;
  if not h.is_premium or h.premium_source_user_id <> alma then
    raise exception '2: an unreported source was treated as lapsed';
  end if;

  -- 3. A shorter entitlement never overwrites a lifetime.
  perform public.apply_household_premium(p, jsonb_build_array(
    pg_temp.ent(alma, true, null), pg_temp.ent(ben, true, in_a_month)));
  select * into h from public.households where id = p;
  if h.premium_source_user_id <> alma or h.premium_expires_at is not null then
    raise exception '3: Ben''s month replaced Alma''s lifetime';
  end if;

  -- 4. Handoff: the longer one wins, and when it lapses the other takes back.
  perform pg_temp.set_premium(true, alma, in_a_month);
  perform public.apply_household_premium(p, jsonb_build_array(
    pg_temp.ent(alma, true, in_a_month), pg_temp.ent(ben, true, in_a_year)));
  select * into h from public.households where id = p;
  if h.premium_source_user_id <> ben or h.premium_expires_at <> in_a_year then
    raise exception '4a: the longer entitlement did not take over';
  end if;
  perform public.apply_household_premium(p, jsonb_build_array(
    pg_temp.ent(alma, true, in_a_month), pg_temp.ent(ben, false, null)));
  select * into h from public.households where id = p;
  if not h.is_premium or h.premium_source_user_id <> alma or h.premium_expires_at <> in_a_month then
    raise exception '4b: Alma did not take premium back when Ben lapsed';
  end if;

  -- 5. Nobody entitled: cleared.
  perform public.apply_household_premium(p, jsonb_build_array(
    pg_temp.ent(alma, false, null), pg_temp.ent(ben, false, null)));
  select * into h from public.households where id = p;
  if h.is_premium or h.premium_source_user_id is not null or h.premium_expires_at is not null then
    raise exception '5: premium survived with nobody entitled';
  end if;

  -- 6. "Active" with an expiry in the past is not entitled.
  perform public.apply_household_premium(p, jsonb_build_array(
    pg_temp.ent(alma, true, now() - interval '1 day')));
  select * into h from public.households where id = p;
  if h.is_premium then
    raise exception '6: an expired entitlement granted premium';
  end if;

  -- 7. A non-member's entitlement counts for nothing.
  perform public.apply_household_premium(p, jsonb_build_array(pg_temp.ent(cleo, true, null)));
  select * into h from public.households where id = p;
  if h.is_premium then
    raise exception '7: a non-member''s purchase made the household premium';
  end if;

  -- 8. Idempotent.
  result := public.apply_household_premium(p, jsonb_build_array(pg_temp.ent(alma, true, null)));
  if (result->>'changed')::boolean is not true or (result->>'is_premium')::boolean is not true then
    raise exception '8a: first grant reported %', result;
  end if;
  result := public.apply_household_premium(p, jsonb_build_array(pg_temp.ent(alma, true, null)));
  if (result->>'changed')::boolean then
    raise exception '8b: a repeat call reported a change';
  end if;

  -- 9. Equal expiries: the current source stays.
  perform pg_temp.set_premium(true, ben, in_a_year);
  perform public.apply_household_premium(p, jsonb_build_array(
    pg_temp.ent(alma, true, in_a_year), pg_temp.ent(ben, true, in_a_year)));
  select * into h from public.households where id = p;
  if h.premium_source_user_id <> ben then
    raise exception '9: an equal entitlement churned the source';
  end if;

  -- 11. Unknown household.
  if public.apply_household_premium(gen_random_uuid(), '[]'::jsonb) is not null then
    raise exception '11: an unknown household did not return null';
  end if;
end;
$$;

-- 10. Not callable by clients.
set local request.jwt.claims = '{"sub":"a1a1a1a1-0000-0000-0000-0000000000a1","role":"authenticated"}';
set local role authenticated;

do $$
begin
  perform public.apply_household_premium(
    'f1f1f1f1-0000-0000-0000-0000000000f1',
    jsonb_build_array(jsonb_build_object(
      'user_id', 'a1a1a1a1-0000-0000-0000-0000000000a1',
      'active', true, 'expires_at', null)));
  raise exception '10: a client called apply_household_premium';
exception
  when insufficient_privilege then null;
end;
$$;

rollback;
