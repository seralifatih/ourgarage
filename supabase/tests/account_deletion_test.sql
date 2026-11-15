-- Assertions for delete_account_data() (account deletion migration).
--
-- Run against a local Supabase instance, like household_isolation_test.sql:
--   supabase db reset
--   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" \
--        -v ON_ERROR_STOP=1 -f supabase/tests/account_deletion_test.sql
--
-- Plain SQL, every check raises on failure, all inside a transaction that is
-- rolled back, so it leaves no rows behind.
--
-- Fixture:
--   Household S (…0051): Sam is the only member, with a car, history and a
--                        reminder.
--   Household O (…0052): Olive owns it; Mia joined first, Max second. Olive
--                        and Mia both logged services on the shared car.
-- Cases: sole member (S deleted), owner with members (O handed to Mia, and
-- O's premium cleared because Olive paid for it), plain member (Max leaves,
-- data stays), repeat call (no-op), and the permission boundary (client roles
-- cannot call it).

begin;

insert into auth.users (id, email)
values
  ('a0000000-0000-0000-0000-000000000001', 'sam@example.com'),
  ('a0000000-0000-0000-0000-000000000002', 'olive@example.com'),
  ('a0000000-0000-0000-0000-000000000003', 'mia@example.com'),
  ('a0000000-0000-0000-0000-000000000004', 'max@example.com');

insert into public.profiles (id, display_name)
values
  ('a0000000-0000-0000-0000-000000000001', 'Sam'),
  ('a0000000-0000-0000-0000-000000000002', 'Olive'),
  ('a0000000-0000-0000-0000-000000000003', 'Mia'),
  ('a0000000-0000-0000-0000-000000000004', 'Max');

-- The insert trigger adds each owner's membership row.
insert into public.households (id, name, owner_id)
values
  ('00000000-0000-0000-0000-000000000051', 'S',
   'a0000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000052', 'O',
   'a0000000-0000-0000-0000-000000000002');

-- Olive's purchase made O premium (written as the superuser, which the
-- premium guard trigger allows, standing in for the RevenueCat webhook).
update public.households
set is_premium = true,
    premium_source_user_id = 'a0000000-0000-0000-0000-000000000002',
    premium_expires_at = now() + interval '300 days'
where id = '00000000-0000-0000-0000-000000000052';

-- Mia joined before Max: she is the heir.
insert into public.household_members (household_id, user_id, role, joined_at)
values
  ('00000000-0000-0000-0000-000000000052',
   'a0000000-0000-0000-0000-000000000003', 'member', now() - interval '2 days'),
  ('00000000-0000-0000-0000-000000000052',
   'a0000000-0000-0000-0000-000000000004', 'member', now() - interval '1 day');

insert into public.vehicles
  (id, household_id, created_by, nickname, odometer, odometer_unit)
values
  ('b0000000-0000-0000-0000-000000000051',
   '00000000-0000-0000-0000-000000000051',
   'a0000000-0000-0000-0000-000000000001', 'Sam car', 1000, 'mi'),
  ('b0000000-0000-0000-0000-000000000052',
   '00000000-0000-0000-0000-000000000052',
   'a0000000-0000-0000-0000-000000000002', 'Shared car', 2000, 'mi');

insert into public.service_records (id, vehicle_id, created_by, performed_at, type)
values
  ('c0000000-0000-0000-0000-000000000051',
   'b0000000-0000-0000-0000-000000000051',
   'a0000000-0000-0000-0000-000000000001', now(), 'oilChange'),
  ('c0000000-0000-0000-0000-000000000052',
   'b0000000-0000-0000-0000-000000000052',
   'a0000000-0000-0000-0000-000000000002', now(), 'oilChange'),
  ('c0000000-0000-0000-0000-000000000053',
   'b0000000-0000-0000-0000-000000000052',
   'a0000000-0000-0000-0000-000000000003', now(), 'tireRotation');

insert into public.reminder_rules (id, vehicle_id, created_by, type, interval_months)
values
  ('d0000000-0000-0000-0000-000000000051',
   'b0000000-0000-0000-0000-000000000051',
   'a0000000-0000-0000-0000-000000000001', 'oilChange', 6);

insert into public.household_invites (household_id, code, created_by, expires_at)
values
  ('00000000-0000-0000-0000-000000000051', 'SAMCODE1',
   'a0000000-0000-0000-0000-000000000001', now() + interval '7 days'),
  ('00000000-0000-0000-0000-000000000052', 'OLIVECODE1',
   'a0000000-0000-0000-0000-000000000002', now() + interval '7 days');

-- ---------------------------------------------------------------------------
-- Client roles cannot run it, not even on themselves.
-- ---------------------------------------------------------------------------
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}';
set local role authenticated;

do $$
begin
  perform public.delete_account_data('a0000000-0000-0000-0000-000000000001');
  raise exception 'authenticated was able to call delete_account_data';
exception
  when insufficient_privilege then null;
end;
$$;

reset role;

do $$
declare
  result jsonb;
begin
  -- -------------------------------------------------------------------------
  -- Sole member: the whole household goes, children first.
  -- -------------------------------------------------------------------------
  result := public.delete_account_data('a0000000-0000-0000-0000-000000000001');
  if (result ->> 'deleted_households')::int <> 1 then
    raise exception 'Sam: expected 1 deleted household, got %', result;
  end if;
  if exists (select 1 from public.households
             where id = '00000000-0000-0000-0000-000000000051')
     or exists (select 1 from public.vehicles
                where id = 'b0000000-0000-0000-0000-000000000051')
     or exists (select 1 from public.service_records
                where id = 'c0000000-0000-0000-0000-000000000051')
     or exists (select 1 from public.reminder_rules
                where id = 'd0000000-0000-0000-0000-000000000051')
     or exists (select 1 from public.household_invites where code = 'SAMCODE1')
     or exists (select 1 from public.profiles
                where id = 'a0000000-0000-0000-0000-000000000001')
  then
    raise exception 'Sam: household data or profile survived deletion';
  end if;

  -- The auth user can now be deleted without a restrict violation.
  delete from auth.users where id = 'a0000000-0000-0000-0000-000000000001';

  -- -------------------------------------------------------------------------
  -- Owner with members: Mia (first to join) becomes owner, nothing is lost.
  -- -------------------------------------------------------------------------
  result := public.delete_account_data('a0000000-0000-0000-0000-000000000002');
  if result -> 'transferred' -> 0 ->> 'new_owner_id'
       <> 'a0000000-0000-0000-0000-000000000003' then
    raise exception 'Olive: expected hand-over to Mia, got %', result;
  end if;
  if (select owner_id from public.households
      where id = '00000000-0000-0000-0000-000000000052')
     <> 'a0000000-0000-0000-0000-000000000003' then
    raise exception 'Olive: households.owner_id not moved to Mia';
  end if;
  if (select role from public.household_members
      where household_id = '00000000-0000-0000-0000-000000000052'
        and user_id = 'a0000000-0000-0000-0000-000000000003') <> 'owner' then
    raise exception 'Olive: Mia''s membership not promoted to owner';
  end if;
  if exists (select 1 from public.household_members
             where user_id = 'a0000000-0000-0000-0000-000000000002') then
    raise exception 'Olive: membership survived';
  end if;
  if (select count(*) from public.household_members
      where household_id = '00000000-0000-0000-0000-000000000052') <> 2 then
    raise exception 'Olive: expected Mia and Max to remain';
  end if;
  -- Shared history stays, detached from Olive.
  if (select created_by from public.service_records
      where id = 'c0000000-0000-0000-0000-000000000052') is not null then
    raise exception 'Olive: created_by not nulled on her surviving record';
  end if;
  if not exists (select 1 from public.vehicles
                 where id = 'b0000000-0000-0000-0000-000000000052')
     or (select count(*) from public.service_records
         where vehicle_id = 'b0000000-0000-0000-0000-000000000052') <> 2 then
    raise exception 'Olive: shared vehicle or history was lost';
  end if;
  -- She paid for O's premium, so it leaves with her.
  if (select is_premium or premium_source_user_id is not null
             or premium_expires_at is not null
      from public.households
      where id = '00000000-0000-0000-0000-000000000052') then
    raise exception 'Olive: household premium survived its payer''s deletion';
  end if;
  -- Her invite goes with her profile.
  if exists (select 1 from public.household_invites where code = 'OLIVECODE1') then
    raise exception 'Olive: her invite survived';
  end if;
  delete from auth.users where id = 'a0000000-0000-0000-0000-000000000002';

  -- -------------------------------------------------------------------------
  -- Plain member: leaves; household and Mia's ownership untouched.
  -- -------------------------------------------------------------------------
  result := public.delete_account_data('a0000000-0000-0000-0000-000000000004');
  if (result ->> 'left_households')::int <> 1 then
    raise exception 'Max: expected to leave 1 household, got %', result;
  end if;
  if exists (select 1 from public.household_members
             where user_id = 'a0000000-0000-0000-0000-000000000004') then
    raise exception 'Max: membership survived';
  end if;
  if (select owner_id from public.households
      where id = '00000000-0000-0000-0000-000000000052')
     <> 'a0000000-0000-0000-0000-000000000003' then
    raise exception 'Max: ownership changed when a plain member left';
  end if;

  -- -------------------------------------------------------------------------
  -- Repeat call for an already-cleaned user is a no-op.
  -- -------------------------------------------------------------------------
  result := public.delete_account_data('a0000000-0000-0000-0000-000000000004');
  if (result ->> 'deleted_households')::int <> 0
     or (result ->> 'left_households')::int <> 0
     or jsonb_array_length(result -> 'transferred') <> 0 then
    raise exception 'Repeat call was not a no-op: %', result;
  end if;
end;
$$;

rollback;
