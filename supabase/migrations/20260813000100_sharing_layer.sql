-- Sharing layer: households, membership, invites, and the synced data tables.
--
-- Free users never reach any of this. A local-only install keeps everything in
-- its Drift database and talks to no server; these tables exist solely so a
-- household can share one garage. That is why every data table here has a
-- NOT NULL household_id: a row with no household has no reason to be in the
-- cloud at all.
--
-- Entitlement note: households.is_premium and the premium_* columns are the
-- authoritative record of "this household has paid". They are written only by
-- the service role, from the RevenueCat webhook. The client caches the value
-- locally for UI responsiveness (see HouseholdEntitlements in the Drift
-- schema), but that cache is never the security boundary — these tables and
-- the policies below are.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

comment on table public.profiles is
  'One row per authenticated user. Readable and writable only by that user.';

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references public.profiles (id) on delete restrict,

  -- Written only by the service role, from the RevenueCat webhook.
  -- See the column grants and the guard trigger further down: no client role
  -- can change these, however the request is shaped.
  is_premium boolean not null default false,
  premium_source_user_id uuid references public.profiles (id) on delete set null,
  premium_expires_at timestamptz,

  created_at timestamptz not null default now()
);

comment on column public.households.is_premium is
  'Service-role only. One member pays, the whole household is premium.';
comment on column public.households.premium_source_user_id is
  'Service-role only. Which member''s purchase granted the entitlement.';
comment on column public.households.premium_expires_at is
  'Service-role only. Null for a lifetime purchase; set for a subscription.';

create table public.household_members (
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

comment on table public.household_members is
  'Membership. Never inserted directly by a client — see accept_household_invite().';

create table public.household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  code text not null unique,
  created_by uuid not null references public.profiles (id) on delete cascade,
  expires_at timestamptz not null,
  accepted_by uuid references public.profiles (id) on delete set null,
  accepted_at timestamptz
);

-- The three synced data tables mirror the local Drift schema, plus the columns
-- sharing needs: household_id (which household owns the row) and created_by
-- (which member wrote it, for attribution in a shared history).
--
-- Two deliberate divergences from Drift, both because Postgres can do better:
--   * ids are uuid rather than text. The client already generates v4 uuids as
--     strings, so they cast cleanly, and the native type indexes better.
--   * cost is numeric rather than a float. Drift stores a Dart double, which
--     is fine for display but wrong for money once totals are summed
--     server-side; numeric(12, 2) avoids accumulating binary rounding error.

create table public.vehicles (
  id uuid primary key,
  household_id uuid not null references public.households (id) on delete cascade,
  created_by uuid references public.profiles (id) on delete set null,

  nickname text not null,
  make text,
  model text,
  year integer,
  plate text,
  odometer integer not null default 0,
  odometer_unit text not null check (odometer_unit in ('km', 'mi')),
  odometer_updated_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.service_records (
  id uuid primary key,
  vehicle_id uuid not null references public.vehicles (id) on delete restrict,
  created_by uuid references public.profiles (id) on delete set null,

  performed_at timestamptz not null,
  odometer integer,
  type text not null,
  custom_type_label text,
  notes text,
  cost numeric(12, 2),
  currency text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.reminder_rules (
  id uuid primary key,
  vehicle_id uuid not null references public.vehicles (id) on delete restrict,
  created_by uuid references public.profiles (id) on delete set null,

  type text not null,
  custom_type_label text,
  interval_months integer,
  interval_distance integer,
  last_done_at timestamptz,
  last_done_odometer integer,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  -- The local repository already rejects a rule with neither interval, since
  -- nothing would ever make it come due. Enforced here too: a buggy or hostile
  -- client must not be able to write rows the engine can't interpret.
  constraint reminder_rules_need_an_interval
    check (interval_months is not null or interval_distance is not null)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- Membership lookups. The helper function filters on (household_id, user_id),
-- which the primary key already serves; this covers the reverse direction —
-- "which households does this user belong to" — used when listing garages.
create index household_members_user_id_idx
  on public.household_members (user_id);

-- Every vehicles policy resolves household_id, and every list query filters by
-- it. Without this, each policy check degrades into a sequential scan.
create index vehicles_household_id_idx
  on public.vehicles (household_id);

-- The service_records and reminder_rules policies reach the household through
-- an EXISTS join on vehicle_id. These are what keep that join an index lookup
-- rather than a scan of the whole child table, per row, per query.
create index service_records_vehicle_id_idx
  on public.service_records (vehicle_id);

create index reminder_rules_vehicle_id_idx
  on public.reminder_rules (vehicle_id);

-- Mirrors the local Drift indexes, for the same access patterns: history is
-- always read newest-first per vehicle, and the scheduler wants active rules.
create index service_records_vehicle_performed_at_idx
  on public.service_records (vehicle_id, performed_at desc);

create index reminder_rules_vehicle_active_idx
  on public.reminder_rules (vehicle_id, is_active);

-- Invite redemption looks up by code; the unique constraint already indexes it.
create index household_invites_household_id_idx
  on public.household_invites (household_id);

-- ---------------------------------------------------------------------------
-- Membership helper
-- ---------------------------------------------------------------------------

-- Whether the caller belongs to the given household.
--
-- SECURITY DEFINER for two reasons. The obvious one is that it is the single
-- place membership is decided, so the policies below stay readable. The
-- load-bearing one is recursion: the household_members SELECT policy needs to
-- ask "is this user a member of this household", which is itself a read of
-- household_members. Under RLS that recurses forever. A definer function runs
-- as its owner, for whom RLS is not enforced, which breaks the cycle.
--
-- That also means household_members must never have FORCE ROW LEVEL SECURITY
-- enabled — forcing RLS applies it to the table owner too, and the recursion
-- would come straight back.
--
-- `set search_path = ''` is not optional. A SECURITY DEFINER function inherits
-- the caller's search_path unless it pins its own, so a user could create their
-- own `household_members` table in a schema earlier in the path and have this
-- function consult that instead — returning true for every household in the
-- system. Every identifier below is schema-qualified for the same reason.
create function public.is_household_member(hid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.household_members
    where household_id = hid
      and user_id = (select auth.uid())
  );
$$;

revoke execute on function public.is_household_member(uuid) from public, anon;
grant execute on function public.is_household_member(uuid) to authenticated;

-- Whether the caller owns the given household.
create function public.is_household_owner(hid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.household_members
    where household_id = hid
      and user_id = (select auth.uid())
      and role = 'owner'
  );
$$;

revoke execute on function public.is_household_owner(uuid) from public, anon;
grant execute on function public.is_household_owner(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Household creation and invite acceptance
-- ---------------------------------------------------------------------------

-- Creating a household must also make the creator its owner-member, and there
-- is deliberately no client INSERT policy on household_members. A trigger keeps
-- the two writes inseparable: there is no ordering in which a household exists
-- without an owner row, and no way for a client to skip the second write.
create function public.add_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.household_members (household_id, user_id, role)
  values (new.id, new.owner_id, 'owner');
  return new;
end;
$$;

create trigger households_add_owner_membership
  after insert on public.households
  for each row
  execute function public.add_owner_membership();

-- Redeems an invite code, joining the caller to the household.
--
-- This is the only path that writes household_members from a client, which is
-- why it is SECURITY DEFINER and why no INSERT policy exists on that table.
-- Everything a client could otherwise lie about is checked here: that the code
-- exists, has not expired, and has not already been used.
--
-- The invite row itself is never readable by the invitee (see the invites
-- policies — owner-only). They hand over a code and get back a household id or
-- an error; they never get to enumerate invites.
create function public.accept_household_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  invite public.household_invites;
  caller uuid := (select auth.uid());
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  -- Locked so two simultaneous redemptions of a single-use code cannot both
  -- see it as unaccepted.
  select * into invite
  from public.household_invites
  where code = invite_code
  for update;

  if not found then
    raise exception 'Invite not found' using errcode = 'P0002';
  end if;

  if invite.accepted_at is not null then
    raise exception 'Invite already used' using errcode = '23505';
  end if;

  if invite.expires_at <= now() then
    raise exception 'Invite expired' using errcode = '22023';
  end if;

  insert into public.household_members (household_id, user_id, role)
  values (invite.household_id, caller, 'member')
  on conflict (household_id, user_id) do nothing;

  update public.household_invites
  set accepted_by = caller,
      accepted_at = now()
  where id = invite.id;

  return invite.household_id;
end;
$$;

revoke execute on function public.accept_household_invite(text) from public, anon;
grant execute on function public.accept_household_invite(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Premium columns: service role only
-- ---------------------------------------------------------------------------

-- RLS cannot express "this role may update these columns but not those" — a
-- policy grants or denies a whole row, and WITH CHECK cannot see the old row to
-- compare against. Column-level privileges are the mechanism that actually
-- enforces it, so the household UPDATE policy below is paired with these
-- grants: the owner may write `name`, and nothing else.
--
-- Supabase grants broad table privileges to anon/authenticated by default, so
-- the revoke has to come first.
revoke update on public.households from anon, authenticated;
grant update (name) on public.households to authenticated;

-- Defence in depth. The grants above are the real enforcement; this trigger
-- catches the case where a future migration re-grants UPDATE on the whole
-- table and silently reopens the hole. Entitlement is the one thing in this
-- schema that is worth paying for a second check on.
create function public.guard_household_premium_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    if new.is_premium is distinct from old.is_premium
      or new.premium_source_user_id is distinct from old.premium_source_user_id
      or new.premium_expires_at is distinct from old.premium_expires_at
    then
      raise exception
        'Premium columns are written only by the RevenueCat webhook'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

create trigger households_guard_premium_columns
  before update on public.households
  for each row
  execute function public.guard_household_premium_columns();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles           enable row level security;
alter table public.households         enable row level security;
alter table public.household_members  enable row level security;
alter table public.household_invites  enable row level security;
alter table public.vehicles           enable row level security;
alter table public.service_records    enable row level security;
alter table public.reminder_rules     enable row level security;

-- profiles: your own row, nothing else. No DELETE policy — profiles go when the
-- auth user does, via the cascade.
create policy profiles_select_own on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy profiles_update_own on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- households: visible to members; created by the caller as owner; renamed by
-- the owner. The premium columns are unreachable regardless of this policy —
-- see the column grants above.
create policy households_select_member on public.households
  for select to authenticated
  using (public.is_household_member(id));

create policy households_insert_self_owned on public.households
  for insert to authenticated
  with check ((select auth.uid()) = owner_id);

create policy households_update_owner on public.households
  for update to authenticated
  using (public.is_household_owner(id))
  with check (public.is_household_owner(id));

-- household_members: members see the roster of households they belong to.
--
-- No INSERT policy, deliberately: joining happens through
-- accept_household_invite(), and the owner's own row through the creation
-- trigger. Both are SECURITY DEFINER and bypass this table's RLS.
create policy household_members_select_same_household on public.household_members
  for select to authenticated
  using (public.is_household_member(household_id));

-- Leaving a household: anyone may remove themselves.
create policy household_members_delete_self on public.household_members
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Removing someone else: the owner may, but not themselves. An owner deleting
-- their own row would strand the household with no owner and no way to appoint
-- one; transferring ownership needs its own flow, not a side effect of leaving.
create policy household_members_delete_by_owner on public.household_members
  for delete to authenticated
  using (
    public.is_household_owner(household_id)
    and user_id <> (select auth.uid())
  );

-- household_invites: the owner's alone, to read and to create. An invitee never
-- selects these; they call accept_household_invite() with the code.
create policy household_invites_select_owner on public.household_invites
  for select to authenticated
  using (public.is_household_owner(household_id));

create policy household_invites_insert_owner on public.household_invites
  for insert to authenticated
  with check (
    public.is_household_owner(household_id)
    and created_by = (select auth.uid())
  );

create policy household_invites_delete_owner on public.household_invites
  for delete to authenticated
  using (public.is_household_owner(household_id));

-- vehicles: full CRUD for members of the owning household.
--
-- The USING clause governs which existing rows are visible to read, update and
-- delete; the WITH CHECK clause governs what a row is allowed to look like
-- afterwards. Both are needed on UPDATE — without WITH CHECK a member could
-- move a vehicle into a household they do not belong to, or out of one they do.
create policy vehicles_select_member on public.vehicles
  for select to authenticated
  using (public.is_household_member(household_id));

create policy vehicles_insert_member on public.vehicles
  for insert to authenticated
  with check (public.is_household_member(household_id));

create policy vehicles_update_member on public.vehicles
  for update to authenticated
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

create policy vehicles_delete_member on public.vehicles
  for delete to authenticated
  using (public.is_household_member(household_id));

-- service_records and reminder_rules carry no household_id of their own; they
-- inherit it from their vehicle. Each policy is an EXISTS join back to
-- vehicles, which is why service_records(vehicle_id) and
-- reminder_rules(vehicle_id) are indexed above — the planner runs this per row.

create policy service_records_select_member on public.service_records
  for select to authenticated
  using (
    exists (
      select 1
      from public.vehicles v
      where v.id = service_records.vehicle_id
        and public.is_household_member(v.household_id)
    )
  );

create policy service_records_insert_member on public.service_records
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.vehicles v
      where v.id = service_records.vehicle_id
        and public.is_household_member(v.household_id)
    )
  );

create policy service_records_update_member on public.service_records
  for update to authenticated
  using (
    exists (
      select 1
      from public.vehicles v
      where v.id = service_records.vehicle_id
        and public.is_household_member(v.household_id)
    )
  )
  with check (
    exists (
      select 1
      from public.vehicles v
      where v.id = service_records.vehicle_id
        and public.is_household_member(v.household_id)
    )
  );

create policy service_records_delete_member on public.service_records
  for delete to authenticated
  using (
    exists (
      select 1
      from public.vehicles v
      where v.id = service_records.vehicle_id
        and public.is_household_member(v.household_id)
    )
  );

create policy reminder_rules_select_member on public.reminder_rules
  for select to authenticated
  using (
    exists (
      select 1
      from public.vehicles v
      where v.id = reminder_rules.vehicle_id
        and public.is_household_member(v.household_id)
    )
  );

create policy reminder_rules_insert_member on public.reminder_rules
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.vehicles v
      where v.id = reminder_rules.vehicle_id
        and public.is_household_member(v.household_id)
    )
  );

create policy reminder_rules_update_member on public.reminder_rules
  for update to authenticated
  using (
    exists (
      select 1
      from public.vehicles v
      where v.id = reminder_rules.vehicle_id
        and public.is_household_member(v.household_id)
    )
  )
  with check (
    exists (
      select 1
      from public.vehicles v
      where v.id = reminder_rules.vehicle_id
        and public.is_household_member(v.household_id)
    )
  );

create policy reminder_rules_delete_member on public.reminder_rules
  for delete to authenticated
  using (
    exists (
      select 1
      from public.vehicles v
      where v.id = reminder_rules.vehicle_id
        and public.is_household_member(v.household_id)
    )
  );
