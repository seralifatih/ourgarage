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

  -- Nor evict one of B's members. There is no DELETE policy on memberships
  -- at all (20261117000200): a direct delete matches nothing...
  delete from public.household_members
  where household_id = '22222222-0000-0000-0000-00000000000b';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Alice removed a member of household B';
  end if;

  -- ...and the function that does remove members is the owner's alone.
  begin
    perform public.remove_household_member(
      '22222222-0000-0000-0000-00000000000b',
      'bbbbbbbb-0000-0000-0000-000000000002');
    raise exception 'Alice removed Bob from household B';
  exception
    when insufficient_privilege then null;
  end;

  -- Nor read B's roster.
  select count(*) into visible
  from public.household_roster('22222222-0000-0000-0000-00000000000b');
  if visible <> 0 then
    raise exception 'Alice can read household B''s roster (% rows)', visible;
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

  -- She may leave, though: through leave_household(), the only way out.
  if public.leave_household('11111111-0000-0000-0000-00000000000a') <> 'left' then
    raise exception 'Carol could not leave household A';
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

  -- The owner may not delete their own membership and orphan the household:
  -- no DELETE policy matches, and remove_household_member() refuses self.
  begin
    perform public.remove_household_member(
      '22222222-0000-0000-0000-00000000000b',
      'bbbbbbbb-0000-0000-0000-000000000002');
    raise exception 'The owner removed themselves with remove_household_member';
  exception
    when invalid_parameter_value then null;
  end;

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

-- ---------------------------------------------------------------------------
-- Become Dana: a brand-new user creating her first household
-- ---------------------------------------------------------------------------
--
-- Every household above was seeded as the superuser, which bypasses RLS. This
-- is the path a real client takes, as `authenticated`, and it is the one that
-- broke in production (20261117000100_household_creation.sql): INSERT ...
-- RETURNING requires the new row to pass the SELECT policy before the owner
-- membership trigger has run.

reset role;

insert into auth.users (id, email)
values ('dddddddd-0000-0000-0000-000000000004', 'dana@example.com');

-- The app creates the profile itself, as the user; done the same way here.
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000000004","role":"authenticated"}';
set local role authenticated;

insert into public.profiles (id, display_name)
values ('dddddddd-0000-0000-0000-000000000004', 'Dana');

do $$
declare
  dana constant uuid := 'dddddddd-0000-0000-0000-000000000004';
  hid uuid;
  visible int;
  member_role text;
  stored_name text;
begin
  -- Exactly what builds up to 1.0.8+13 send: POST households?select=id with
  -- {name, owner_id}, i.e. INSERT ... RETURNING id.
  insert into public.households (name, owner_id)
  values ('Dana''s Garage', dana)
  returning id into hid;

  select role into member_role from public.household_members
  where household_id = hid and user_id = dana;
  if member_role is distinct from 'owner' then
    raise exception 'Direct insert: owner membership is %', member_role;
  end if;

  select count(*) into visible from public.households where id = hid;
  if visible <> 1 then
    raise exception 'Direct insert: Dana sees % rows of her own household', visible;
  end if;

  -- The RPC newer builds use.
  hid := public.create_household('  Dana''s Second Garage  ');

  select name into stored_name from public.households where id = hid;
  if stored_name is distinct from 'Dana''s Second Garage' then
    raise exception 'create_household: stored name is %', stored_name;
  end if;

  select role into member_role from public.household_members
  where household_id = hid and user_id = dana;
  if member_role is distinct from 'owner' then
    raise exception 'create_household: owner membership is %', member_role;
  end if;

  begin
    perform public.create_household('   ');
    raise exception 'create_household accepted a blank name';
  exception
    when invalid_parameter_value then null;
  end;

  -- A household cannot be born premium.
  begin
    insert into public.households (name, owner_id, is_premium)
    values ('Free premium', dana, true);
    raise exception 'A client created a household with is_premium = true';
  exception
    when insufficient_privilege then null;
  end;

  -- Nor owned by someone else.
  begin
    insert into public.households (name, owner_id)
    values ('Not mine', 'aaaaaaaa-0000-0000-0000-000000000001');
    raise exception 'Dana created a household owned by Alice';
  exception
    when insufficient_privilege then null;
  end;

  -- Owning households of her own grants nothing in anyone else's.
  select count(*) into visible from public.households
  where owner_id <> dana;
  if visible <> 0 then
    raise exception 'Dana sees % households she does not own', visible;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Leaving and removing: household E (Erin owns; Finn, Gus, Hana are members)
-- ---------------------------------------------------------------------------
--
-- Covers leave_household(), remove_household_member() and
-- household_roster() from 20261117000200, including the rules they share with
-- delete_account_data(): ownership passes to the earliest member, the last
-- member out deletes the household and its data, and premium paid for by
-- whoever leaves or is removed is cleared.

reset role;

insert into auth.users (id, email)
values
  ('eeeeeeee-0000-0000-0000-000000000005', 'erin@example.com'),
  ('ffffffff-0000-0000-0000-000000000006', 'finn@example.com'),
  ('99999999-0000-0000-0000-000000000007', 'gus@example.com'),
  ('88888888-0000-0000-0000-000000000008', 'hana@example.com');

insert into public.profiles (id, display_name)
values
  ('eeeeeeee-0000-0000-0000-000000000005', 'Erin'),
  ('ffffffff-0000-0000-0000-000000000006', 'Finn'),
  ('99999999-0000-0000-0000-000000000007', 'Gus'),
  ('88888888-0000-0000-0000-000000000008', null);

insert into public.households (id, name, owner_id)
values ('33333333-0000-0000-0000-00000000000e', 'Household E',
        'eeeeeeee-0000-0000-0000-000000000005');

-- Explicit join times: Gus joined before Hana, so he is the heir once Finn
-- has gone.
insert into public.household_members (household_id, user_id, role, joined_at)
values
  ('33333333-0000-0000-0000-00000000000e',
   'ffffffff-0000-0000-0000-000000000006', 'member', now() + interval '1 min'),
  ('33333333-0000-0000-0000-00000000000e',
   '99999999-0000-0000-0000-000000000007', 'member', now() + interval '2 min'),
  ('33333333-0000-0000-0000-00000000000e',
   '88888888-0000-0000-0000-000000000008', 'member', now() + interval '3 min');

insert into public.vehicles
  (id, household_id, created_by, nickname, odometer, odometer_unit)
values ('e0000000-0000-0000-0000-0000000000e1',
        '33333333-0000-0000-0000-00000000000e',
        'eeeeeeee-0000-0000-0000-000000000005', 'Erin Golf', 100, 'km');

insert into public.service_records (id, vehicle_id, created_by, performed_at, type)
values ('e0000000-0000-0000-0000-0000000000e2',
        'e0000000-0000-0000-0000-0000000000e1',
        'eeeeeeee-0000-0000-0000-000000000005', now(), 'oilChange');

-- Hana's purchase made the household premium.
update public.households
set is_premium = true,
    premium_source_user_id = '88888888-0000-0000-0000-000000000008'
where id = '33333333-0000-0000-0000-00000000000e';

-- Finn: a plain member.
set local request.jwt.claims = '{"sub":"ffffffff-0000-0000-0000-000000000006","role":"authenticated"}';
set local role authenticated;

do $$
declare
  e constant uuid := '33333333-0000-0000-0000-00000000000e';
  visible int;
  affected int;
  owner_name text;
begin
  -- The roster names his co-members, and keeps a member with no display
  -- name rather than dropping them.
  select count(*) into visible from public.household_roster(e);
  if visible <> 4 then
    raise exception 'Finn sees % roster rows, expected 4', visible;
  end if;
  select display_name into owner_name from public.household_roster(e)
  where role = 'owner';
  if owner_name is distinct from 'Erin' then
    raise exception 'Roster owner name is %', owner_name;
  end if;
  select count(*) into visible from public.household_roster(e)
  where user_id = '88888888-0000-0000-0000-000000000008' and display_name is null;
  if visible <> 1 then
    raise exception 'A member without a display name fell off the roster';
  end if;

  -- Not the owner: cannot remove anyone.
  begin
    perform public.remove_household_member(e, '99999999-0000-0000-0000-000000000007');
    raise exception 'A plain member removed someone';
  exception
    when insufficient_privilege then null;
  end;

  -- The internal premium helper is not callable by clients.
  begin
    perform public.clear_household_premium_from(e, '88888888-0000-0000-0000-000000000008');
    raise exception 'A client called clear_household_premium_from';
  exception
    when insufficient_privilege then null;
  end;

  -- A direct delete of someone's membership matches nothing.
  delete from public.household_members
  where household_id = e and user_id = '99999999-0000-0000-0000-000000000007';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'Finn deleted Gus''s membership directly';
  end if;

  if public.leave_household(e) <> 'left' then
    raise exception 'Finn did not simply leave';
  end if;

  -- Gone means gone.
  select count(*) into visible from public.vehicles;
  if visible <> 0 then
    raise exception 'Finn still sees % vehicles after leaving', visible;
  end if;
  begin
    perform public.leave_household(e);
    raise exception 'Finn left a household he is not in';
  exception
    when no_data_found then null;
  end;
end;
$$;

-- Erin: the owner.
reset role;
set local request.jwt.claims = '{"sub":"eeeeeeee-0000-0000-0000-000000000005","role":"authenticated"}';
set local role authenticated;

do $$
declare
  e constant uuid := '33333333-0000-0000-0000-00000000000e';
  premium boolean;
begin
  begin
    perform public.remove_household_member(e, 'ffffffff-0000-0000-0000-000000000006');
    raise exception 'Removed someone who already left';
  exception
    when no_data_found then null;
  end;

  -- Removing Hana, who paid, takes premium with her.
  perform public.remove_household_member(e, '88888888-0000-0000-0000-000000000008');
  select is_premium into premium from public.households where id = e;
  if premium then
    raise exception 'Household E kept premium after its payer was removed';
  end if;
end;
$$;

-- Now Erin is the payer; then she leaves.
reset role;
update public.households
set is_premium = true,
    premium_source_user_id = 'eeeeeeee-0000-0000-0000-000000000005'
where id = '33333333-0000-0000-0000-00000000000e';
set local request.jwt.claims = '{"sub":"eeeeeeee-0000-0000-0000-000000000005","role":"authenticated"}';
set local role authenticated;

do $$
begin
  if public.leave_household('33333333-0000-0000-0000-00000000000e') <> 'transferred' then
    raise exception 'Erin''s leave did not transfer ownership';
  end if;
end;
$$;

reset role;

do $$
declare
  e constant uuid := '33333333-0000-0000-0000-00000000000e';
  h record;
  gus_role text;
begin
  select owner_id, is_premium, premium_source_user_id into h
  from public.households where id = e;
  if h.owner_id <> '99999999-0000-0000-0000-000000000007' then
    raise exception 'Ownership went to %, expected Gus', h.owner_id;
  end if;
  if h.is_premium or h.premium_source_user_id is not null then
    raise exception 'Household E kept the premium Erin paid for';
  end if;
  select role into gus_role from public.household_members
  where household_id = e and user_id = '99999999-0000-0000-0000-000000000007';
  if gus_role is distinct from 'owner' then
    raise exception 'Gus''s membership role is %', gus_role;
  end if;
end;
$$;

-- Gus: the last one out.
set local request.jwt.claims = '{"sub":"99999999-0000-0000-0000-000000000007","role":"authenticated"}';
set local role authenticated;

do $$
begin
  if public.leave_household('33333333-0000-0000-0000-00000000000e') <> 'deleted' then
    raise exception 'The last member''s leave did not delete the household';
  end if;
end;
$$;

reset role;

do $$
begin
  if exists (select 1 from public.households
             where id = '33333333-0000-0000-0000-00000000000e')
    or exists (select 1 from public.vehicles
               where id = 'e0000000-0000-0000-0000-0000000000e1')
    or exists (select 1 from public.service_records
               where id = 'e0000000-0000-0000-0000-0000000000e2')
  then
    raise exception 'Household E or its data survived its last member leaving';
  end if;
end;
$$;

rollback;
