-- Cross-household isolation assertions for the sharing layer.
--
-- Run against a local Supabase instance:
--   supabase db reset
--   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" \
--        -v ON_ERROR_STOP=1 -f supabase/tests/household_isolation_test.sql
--
-- Plain SQL rather than pgTAP so it needs no extension installed. Every check
-- raises on failure, ON_ERROR_STOP turns that into a non-zero exit, and the
-- whole thing runs inside a transaction that is rolled back at the end, so it
-- leaves no rows behind.
--
-- The central subtlety: RLS does not reject a write you are not allowed to
-- make, it makes the row invisible, so the write matches nothing and succeeds
-- having changed nothing. A test that expected an exception on UPDATE or
-- DELETE would pass against a completely open table. These assertions check
-- affected row counts and then re-read the target as its real owner to prove
-- it is untouched.

begin;

-- ---------------------------------------------------------------------------
-- Fixture: two households that share nothing
-- ---------------------------------------------------------------------------

-- Seeded as the superuser, which bypasses RLS. Everything after this runs as
-- the `authenticated` role with a specific user id, which is what the policies
-- actually see in production.

insert into auth.users (id, email)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'alice@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'bob@example.com'),
  ('cccccccc-0000-0000-0000-000000000003', 'carol@example.com');

insert into public.profiles (id, display_name)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Alice'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'Bob'),
  ('cccccccc-0000-0000-0000-000000000003', 'Carol');

-- The insert trigger gives each owner their household_members row.
insert into public.households (id, name, owner_id)
values
  ('11111111-0000-0000-0000-00000000000a', 'Household A',
   'aaaaaaaa-0000-0000-0000-000000000001'),
  ('22222222-0000-0000-0000-00000000000b', 'Household B',
   'bbbbbbbb-0000-0000-0000-000000000002');

-- Carol is a plain member of A, to separate "member" from "owner" rights.
insert into public.household_members (household_id, user_id, role)
values ('11111111-0000-0000-0000-00000000000a',
        'cccccccc-0000-0000-0000-000000000003', 'member');

insert into public.vehicles
  (id, household_id, created_by, nickname, odometer, odometer_unit)
values
  ('a0000000-0000-0000-0000-0000000000a1',
   '11111111-0000-0000-0000-00000000000a',
   'aaaaaaaa-0000-0000-0000-000000000001', 'Alice Civic', 1000, 'mi'),
  ('b0000000-0000-0000-0000-0000000000b1',
   '22222222-0000-0000-0000-00000000000b',
   'bbbbbbbb-0000-0000-0000-000000000002', 'Bob Hilux', 2000, 'km');

insert into public.service_records
  (id, vehicle_id, created_by, performed_at, type, cost)
values
  ('b0000000-0000-0000-0000-0000000000b2',
   'b0000000-0000-0000-0000-0000000000b1',
   'bbbbbbbb-0000-0000-0000-000000000002', now(), 'oilChange', 80.00);

insert into public.reminder_rules
  (id, vehicle_id, created_by, type, interval_months)
values
  ('b0000000-0000-0000-0000-0000000000b3',
   'b0000000-0000-0000-0000-0000000000b1',
   'bbbbbbbb-0000-0000-0000-000000000002', 'oilChange', 6);

insert into public.household_invites
  (id, household_id, code, created_by, expires_at)
values
  ('b0000000-0000-0000-0000-0000000000b4',
   '22222222-0000-0000-0000-00000000000b', 'BOB-INVITE-1',
   'bbbbbbbb-0000-0000-0000-000000000002', now() + interval '7 days');

-- ---------------------------------------------------------------------------
-- Become Alice: owner of household A, no relationship to household B
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
set local role authenticated;

do $$
declare
  visible int;
  affected int;
begin
  -- Baseline: the policies are permissive enough to be worth testing. If this
  -- fails, every "cannot see it" assertion below would pass vacuously.
  select count(*) into visible from public.vehicles
  where id = 'a0000000-0000-0000-0000-0000000000a1';
  if visible <> 1 then
    raise exception 'Alice cannot see her own vehicle (saw % rows)', visible;
  end if;

  -- SELECT: household B's vehicle does not exist as far as Alice is concerned.
  select count(*) into visible from public.vehicles
  where id = 'b0000000-0000-0000-0000-0000000000b1';
  if visible <> 0 then
    raise exception 'Alice can SELECT household B''s vehicle (saw % rows)', visible;
  end if;

  -- A blanket read must not leak it either.
  select count(*) into visible from public.vehicles;
  if visible <> 1 then
    raise exception 'Unqualified SELECT leaked rows (saw %, expected 1)', visible;
  end if;

  -- UPDATE: matches nothing rather than erroring.
  update public.vehicles
  set nickname = 'Stolen', odometer = 999999
  where id = 'b0000000-0000-0000-0000-0000000000b1';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Alice UPDATEd household B''s vehicle (% rows)', affected;
  end if;

  -- DELETE: likewise.
  delete from public.vehicles
  where id = 'b0000000-0000-0000-0000-0000000000b1';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Alice DELETEd household B''s vehicle (% rows)', affected;
  end if;

  -- INSERT: Alice cannot plant a vehicle in household B.
  begin
    insert into public.vehicles
      (id, household_id, created_by, nickname, odometer, odometer_unit)
    values
      ('a0000000-0000-0000-0000-0000000000a9',
       '22222222-0000-0000-0000-00000000000b',
       'aaaaaaaa-0000-0000-0000-000000000001', 'Trojan', 0, 'mi');
    raise exception 'Alice INSERTed a vehicle into household B';
  exception
    when insufficient_privilege then null;  -- expected: WITH CHECK rejected it
  end;
end;
$$;

-- Blast radius of an unqualified write: it must reach Alice's own row and stop.
--
-- Behind a savepoint because these statements really do delete Alice's vehicle,
-- and the assertions further down still need household A's fixture intact.
savepoint before_blast_radius;

do $$
declare
  affected int;
begin
  update public.vehicles set nickname = 'Everything';
  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'Unqualified UPDATE touched % rows, expected 1', affected;
  end if;

  delete from public.vehicles;
  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'Unqualified DELETE touched % rows, expected 1', affected;
  end if;
end;
$$;

rollback to savepoint before_blast_radius;

-- Child tables reached through vehicle_id.
do $$
declare
  visible int;
  affected int;
begin
  select count(*) into visible from public.service_records
  where id = 'b0000000-0000-0000-0000-0000000000b2';
  if visible <> 0 then
    raise exception 'Alice can SELECT household B''s service record';
  end if;

  update public.service_records set cost = 0.01
  where id = 'b0000000-0000-0000-0000-0000000000b2';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Alice UPDATEd household B''s service record';
  end if;

  delete from public.service_records
  where id = 'b0000000-0000-0000-0000-0000000000b2';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Alice DELETEd household B''s service record';
  end if;

  -- Attaching a record to someone else's vehicle is the interesting attack
  -- here, since service_records has no household_id of its own to check.
  begin
    insert into public.service_records
      (id, vehicle_id, created_by, performed_at, type)
    values
      ('a0000000-0000-0000-0000-0000000000a8',
       'b0000000-0000-0000-0000-0000000000b1',
       'aaaaaaaa-0000-0000-0000-000000000001', now(), 'brakes');
    raise exception 'Alice attached a service record to household B''s vehicle';
  exception
    when insufficient_privilege then null;
  end;

  select count(*) into visible from public.reminder_rules
  where id = 'b0000000-0000-0000-0000-0000000000b3';
  if visible <> 0 then
    raise exception 'Alice can SELECT household B''s reminder rule';
  end if;

  delete from public.reminder_rules
  where id = 'b0000000-0000-0000-0000-0000000000b3';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Alice DELETEd household B''s reminder rule';
  end if;

  begin
    insert into public.reminder_rules
      (id, vehicle_id, created_by, type, interval_months)
    values
      ('a0000000-0000-0000-0000-0000000000a7',
       'b0000000-0000-0000-0000-0000000000b1',
       'aaaaaaaa-0000-0000-0000-000000000001', 'tireRotation', 6);
    raise exception 'Alice attached a reminder rule to household B''s vehicle';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Households, membership and invites.
do $$
declare
  visible int;
  affected int;
begin
  select count(*) into visible from public.households
  where id = '22222222-0000-0000-0000-00000000000b';
  if visible <> 0 then
    raise exception 'Alice can SELECT household B';
  end if;

  update public.households set name = 'Renamed by Alice'
  where id = '22222222-0000-0000-0000-00000000000b';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Alice renamed household B';
  end if;

  -- The roster of a household Alice does not belong to.
  select count(*) into visible from public.household_members
  where household_id = '22222222-0000-0000-0000-00000000000b';
  if visible <> 0 then
    raise exception 'Alice can SELECT household B''s membership';
  end if;

  -- No INSERT policy exists on household_members: joining goes through
  -- accept_household_invite(). Alice cannot simply write herself in.
  begin
    insert into public.household_members (household_id, user_id, role)
    values ('22222222-0000-0000-0000-00000000000b',
            'aaaaaaaa-0000-0000-0000-000000000001', 'member');
    raise exception 'Alice joined household B by direct INSERT';
  exception
    when insufficient_privilege then null;
  end;

  -- Nor evict one of B's members.
  delete from public.household_members
  where household_id = '22222222-0000-0000-0000-00000000000b';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Alice removed a member of household B';
  end if;

  -- Invites belong to their household's owner alone.
  select count(*) into visible from public.household_invites
  where household_id = '22222222-0000-0000-0000-00000000000b';
  if visible <> 0 then
    raise exception 'Alice can SELECT household B''s invites';
  end if;

  -- Owning A does not let her mint invites into B.
  begin
    insert into public.household_invites
      (id, household_id, code, created_by, expires_at)
    values
      ('a0000000-0000-0000-0000-0000000000a6',
       '22222222-0000-0000-0000-00000000000b', 'ALICE-FORGED',
       'aaaaaaaa-0000-0000-0000-000000000001', now() + interval '1 day');
    raise exception 'Alice created an invite into household B';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Entitlement: not even the owner of their own household may grant premium.
do $$
declare
  premium boolean;
begin
  begin
    update public.households
    set is_premium = true
    where id = '11111111-0000-0000-0000-00000000000a';
    -- Column grants make this the expected path; the guard trigger is the
    -- backstop if a later migration re-grants UPDATE on the whole table.
    raise exception 'Alice granted her own household premium';
  exception
    when insufficient_privilege then null;
  end;

  select is_premium into premium from public.households
  where id = '11111111-0000-0000-0000-00000000000a';
  if premium then
    raise exception 'Household A ended up premium';
  end if;

  -- Renaming, which the owner may do, must still work: the column grant has to
  -- be narrow, not a blanket denial of UPDATE.
  update public.households set name = 'Household A renamed'
  where id = '11111111-0000-0000-0000-00000000000a';
end;
$$;

-- ---------------------------------------------------------------------------
-- Become Carol: a member of A, not its owner
-- ---------------------------------------------------------------------------

reset role;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000000003","role":"authenticated"}';
set local role authenticated;

do $$
declare
  visible int;
  affected int;
begin
  -- Members get the shared garage — that is the entire point of the feature.
  select count(*) into visible from public.vehicles
  where household_id = '11111111-0000-0000-0000-00000000000a';
  if visible <> 1 then
    raise exception 'Carol cannot see household A''s vehicles (saw %)', visible;
  end if;

  -- But not household B's, membership in A notwithstanding.
  select count(*) into visible from public.vehicles
  where id = 'b0000000-0000-0000-0000-0000000000b1';
  if visible <> 0 then
    raise exception 'Carol can SELECT household B''s vehicle';
  end if;

  -- A member is not an owner: no renaming, no invites.
  update public.households set name = 'Carol was here'
  where id = '11111111-0000-0000-0000-00000000000a';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Carol renamed household A without owning it';
  end if;

  begin
    insert into public.household_invites
      (id, household_id, code, created_by, expires_at)
    values
      ('c0000000-0000-0000-0000-0000000000c1',
       '11111111-0000-0000-0000-00000000000a', 'CAROL-INVITE',
       'cccccccc-0000-0000-0000-000000000003', now() + interval '1 day');
    raise exception 'Carol created an invite for a household she does not own';
  exception
    when insufficient_privilege then null;
  end;

  -- She may leave, though.
  delete from public.household_members
  where household_id = '11111111-0000-0000-0000-00000000000a'
    and user_id = 'cccccccc-0000-0000-0000-000000000003';
  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'Carol could not leave household A (% rows)', affected;
  end if;

  -- And having left, the shared garage is gone.
  select count(*) into visible from public.vehicles;
  if visible <> 0 then
    raise exception 'Carol still sees % vehicles after leaving', visible;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Become Bob: owner of B, verifying A never actually touched anything
-- ---------------------------------------------------------------------------

reset role;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}';
set local role authenticated;

do $$
declare
  v record;
  r record;
  rules int;
begin
  select * into v from public.vehicles
  where id = 'b0000000-0000-0000-0000-0000000000b1';
  if not found then
    raise exception 'Household B''s vehicle is gone';
  end if;
  if v.nickname <> 'Bob Hilux' or v.odometer <> 2000 then
    raise exception 'Household B''s vehicle was modified: % / %',
      v.nickname, v.odometer;
  end if;

  select * into r from public.service_records
  where id = 'b0000000-0000-0000-0000-0000000000b2';
  if not found then
    raise exception 'Household B''s service record is gone';
  end if;
  if r.cost <> 80.00 then
    raise exception 'Household B''s service record cost was modified: %', r.cost;
  end if;

  select count(*) into rules from public.reminder_rules
  where id = 'b0000000-0000-0000-0000-0000000000b3';
  if rules <> 1 then
    raise exception 'Household B''s reminder rule is gone';
  end if;

  -- No stowaway rows from Alice's insert attempts.
  if exists (select 1 from public.household_members
             where household_id = '22222222-0000-0000-0000-00000000000b'
               and user_id = 'aaaaaaaa-0000-0000-0000-000000000001') then
    raise exception 'Alice is a member of household B';
  end if;

  -- The owner may not delete their own membership and orphan the household.
  delete from public.household_members
  where household_id = '22222222-0000-0000-0000-00000000000b'
    and user_id = 'bbbbbbbb-0000-0000-0000-000000000002';
  if not exists (select 1 from public.household_members
                 where household_id = '22222222-0000-0000-0000-00000000000b'
                   and user_id = 'bbbbbbbb-0000-0000-0000-000000000002') then
    raise exception 'The owner deleted their own membership row';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Invite acceptance is the only way in
-- ---------------------------------------------------------------------------

reset role;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
set local role authenticated;

do $$
declare
  joined uuid;
  visible int;
begin
  -- Alice could not read this invite, but she was given the code out of band.
  joined := public.accept_household_invite('BOB-INVITE-1');
  if joined <> '22222222-0000-0000-0000-00000000000b' then
    raise exception 'Accepting the invite returned %', joined;
  end if;

  -- Now, and only now, household B's garage is visible to her.
  select count(*) into visible from public.vehicles
  where id = 'b0000000-0000-0000-0000-0000000000b1';
  if visible <> 1 then
    raise exception 'Alice joined household B but sees % of its vehicles', visible;
  end if;

  -- Single use.
  begin
    perform public.accept_household_invite('BOB-INVITE-1');
    raise exception 'An invite was accepted twice';
  exception
    when unique_violation then null;
  end;

  -- And a code that does not exist is not a way in either.
  begin
    perform public.accept_household_invite('NOT-A-REAL-CODE');
    raise exception 'A nonexistent invite code was accepted';
  exception
    when no_data_found then null;
  end;
end;
$$;

rollback;
