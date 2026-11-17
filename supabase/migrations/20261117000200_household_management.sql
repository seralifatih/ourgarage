-- Household management from the app (1.0.9): the member roster with display
-- names, removing a member, and leaving a household.
--
-- Up to 1.0.8 no client ever called the household_members DELETE policies —
-- there was no UI for it — so they are replaced here by two SECURITY DEFINER
-- functions that do the bookkeeping a bare DELETE cannot:
--
--   * An owner deleting their own membership row (allowed by
--     household_members_delete_self) stranded the household with an owner_id
--     but no owner member: nobody could invite, rename or remove anyone.
--   * Removing or losing the member whose purchase made the household premium
--     left is_premium set with nobody's renewals or expiries able to reach it
--     — premium forever, the same problem delete_account_data() solves for
--     deleted accounts.
--
-- The rules mirror delete_account_data() (20261115000100) deliberately, so
-- leaving and deleting your account do the same thing to the household:
-- sole member -> household deleted; owner with others -> ownership passes to
-- whoever joined first; member -> membership removed; premium the leaver paid
-- for is cleared.

-- ---------------------------------------------------------------------------
-- Roster with display names
-- ---------------------------------------------------------------------------

-- profiles is readable only by its owner, so the roster could show roles and
-- join dates but not who anyone is. This exposes exactly one extra column,
-- display_name, and only for people who share a household with the caller.
-- The email address is never exposed (it lives in auth.users, not here).
create function public.household_roster(hid uuid)
returns table (
  user_id uuid,
  role text,
  joined_at timestamptz,
  display_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  -- Left join: a member must never drop out of the roster (the app decides
  -- "am I the only member?" from it) just because a name is missing.
  select hm.user_id, hm.role, hm.joined_at, p.display_name
  from public.household_members hm
  left join public.profiles p on p.id = hm.user_id
  where hm.household_id = hid
    and public.is_household_member(hid)
  order by hm.joined_at, hm.user_id;
$$;

revoke execute on function public.household_roster(uuid) from public, anon;
grant execute on function public.household_roster(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- No direct deletes of memberships from clients
-- ---------------------------------------------------------------------------

drop policy household_members_delete_self on public.household_members;
drop policy household_members_delete_by_owner on public.household_members;

-- Clears premium on [hid] if [uid] is the member who paid for it. Internal:
-- not executable by any client role.
create function public.clear_household_premium_from(hid uuid, uid uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.households
  set is_premium = false,
      premium_source_user_id = null,
      premium_expires_at = null
  where id = hid
    and premium_source_user_id = uid;
$$;

revoke execute on function public.clear_household_premium_from(uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- remove_household_member()
-- ---------------------------------------------------------------------------

-- The owner removes someone else. Their access ends; the vehicles and history
-- stay with the household (see the privacy policy). Removing yourself is
-- leave_household(), which also handles ownership.
create function public.remove_household_member(hid uuid, member uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  -- Same lock order as delete_account_data(): household first.
  perform 1 from public.households where id = hid for update;

  if not public.is_household_owner(hid) then
    raise exception 'Only the owner can remove members' using errcode = '42501';
  end if;

  if member = caller then
    raise exception 'Use leave_household to remove yourself' using errcode = '22023';
  end if;

  delete from public.household_members
  where household_id = hid and user_id = member;

  if not found then
    raise exception 'Not a member of this household' using errcode = 'P0002';
  end if;

  perform public.clear_household_premium_from(hid, member);
end;
$$;

revoke execute on function public.remove_household_member(uuid, uuid) from public, anon;
grant execute on function public.remove_household_member(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- leave_household()
-- ---------------------------------------------------------------------------

-- Returns 'deleted' (caller was the only member; the household and its data
-- are gone), 'transferred' (caller owned it; the earliest other member now
-- does) or 'left'. Locking follows delete_account_data(), for the same reasons
-- given there.
create function public.leave_household(hid uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  my_role text;
  heir uuid;
begin
  if caller is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  perform 1 from public.households where id = hid for update;

  select role into my_role
  from public.household_members
  where household_id = hid and user_id = caller
  for update;

  if not found then
    raise exception 'Not a member of this household' using errcode = 'P0002';
  end if;

  select hm.user_id into heir
  from public.household_members hm
  where hm.household_id = hid
    and hm.user_id <> caller
  order by hm.joined_at, hm.user_id
  limit 1
  for update;

  if heir is null then
    -- Children first: both reference vehicles with ON DELETE RESTRICT.
    delete from public.reminder_rules
    where vehicle_id in (select id from public.vehicles where household_id = hid);
    delete from public.service_records
    where vehicle_id in (select id from public.vehicles where household_id = hid);
    delete from public.vehicles where household_id = hid;
    -- Cascades to household_members and household_invites.
    delete from public.households where id = hid;
    return 'deleted';
  end if;

  if my_role = 'owner' then
    update public.household_members
    set role = 'owner'
    where household_id = hid and user_id = heir;

    update public.households
    set owner_id = heir
    where id = hid;
  end if;

  delete from public.household_members
  where household_id = hid and user_id = caller;

  perform public.clear_household_premium_from(hid, caller);

  return case when my_role = 'owner' then 'transferred' else 'left' end;
end;
$$;

revoke execute on function public.leave_household(uuid) from public, anon;
grant execute on function public.leave_household(uuid) to authenticated;
