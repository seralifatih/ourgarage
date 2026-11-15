-- Account deletion (App Store guideline 5.1.1(v)).
--
-- Called only by the `delete-account` Edge Function, with the service role,
-- after it has verified the caller's JWT. Removes everything server-side that
-- belongs to one user, in one transaction, *before* the function deletes the
-- auth user — which it has to, because two foreign keys would otherwise make
-- that deletion fail or leave a mess:
--
--   * households.owner_id is ON DELETE RESTRICT, so an owner's auth user (and
--     its cascading profile) cannot be deleted while they own a household.
--   * service_records/reminder_rules -> vehicles is ON DELETE RESTRICT, so a
--     household cannot be deleted by cascade while its cars have history.
--
-- Per household the user belongs to:
--
--   * Sole member: the household is deleted outright, with its vehicles,
--     service records, reminder rules and invites. Nobody else relies on it.
--   * Owner with other members: ownership passes to the member who joined
--     first (ties broken by user id, so the choice is deterministic), and the
--     user's membership is removed. The household, its data and its premium
--     status carry on for everyone else. Chosen over blocking deletion until a
--     manual hand-over (an obstacle Apple discourages) or deleting the
--     household for all (destroys records other people rely on).
--   * Plain member: the membership row is removed. Shared data stays, as the
--     privacy policy promises.
--
-- Rows the user created in households that live on keep existing; their
-- created_by is nulled by the profile cascade.
--
-- Premium: if the user is the one whose purchase made a surviving household
-- premium (premium_source_user_id), that household's premium is cleared. The
-- purchase belongs to the buyer's Apple ID and goes with them (they can
-- restore it); and once they are gone the RevenueCat webhook can no longer
-- match their renewal or expiry events to the household, so leaving the flag
-- set would make a lapsed subscription premium forever. Remaining members can
-- buy their own. A household whose premium came from someone else is
-- untouched.
--
-- Concurrency: each household row is locked FOR UPDATE before anything is
-- decided about it. That also blocks a concurrent accept_household_invite (its
-- membership insert needs a KEY SHARE lock on the household for the foreign
-- key), so a sole-member household can't gain a member mid-deletion. The
-- heir's membership row is locked too, so they can't leave between being
-- chosen and being promoted. Households are processed in id order, so two
-- deletions touching the same households lock them in the same order.
--
-- Idempotent: a second call for an already-cleaned user changes nothing, so a
-- deletion interrupted between this function and the auth-user deletion can
-- simply be retried.

create function public.delete_account_data(target uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m record;
  heir uuid;
  current_role_name text;
  deleted_households int := 0;
  transferred jsonb := '[]'::jsonb;
  left_households int := 0;
begin
  if target is null then
    raise exception 'target is required' using errcode = '22004';
  end if;

  for m in
    select household_id
    from public.household_members
    where user_id = target
    order by household_id
  loop
    perform 1 from public.households where id = m.household_id for update;

    -- Re-read under the lock: the membership may have changed since the
    -- loop's snapshot.
    select role into current_role_name
    from public.household_members
    where household_id = m.household_id and user_id = target
    for update;
    if not found then
      continue;
    end if;

    if current_role_name = 'owner' then
      select hm.user_id into heir
      from public.household_members hm
      where hm.household_id = m.household_id
        and hm.user_id <> target
      order by hm.joined_at, hm.user_id
      limit 1
      for update;

      if heir is null then
        -- Children first: both reference vehicles with ON DELETE RESTRICT.
        delete from public.reminder_rules
        where vehicle_id in (
          select id from public.vehicles where household_id = m.household_id
        );
        delete from public.service_records
        where vehicle_id in (
          select id from public.vehicles where household_id = m.household_id
        );
        delete from public.vehicles where household_id = m.household_id;
        -- Cascades to household_members and household_invites.
        delete from public.households where id = m.household_id;
        deleted_households := deleted_households + 1;
      else
        update public.household_members
        set role = 'owner'
        where household_id = m.household_id and user_id = heir;

        update public.households
        set owner_id = heir
        where id = m.household_id;

        delete from public.household_members
        where household_id = m.household_id and user_id = target;

        transferred := transferred || jsonb_build_object(
          'household_id', m.household_id,
          'new_owner_id', heir
        );
      end if;
    else
      delete from public.household_members
      where household_id = m.household_id and user_id = target;
      left_households := left_households + 1;
    end if;

    -- See "Premium" above. A no-op when the household was deleted, or when
    -- someone else paid.
    update public.households
    set is_premium = false,
        premium_source_user_id = null,
        premium_expires_at = null
    where id = m.household_id
      and premium_source_user_id = target;
  end loop;

  -- Premium the user paid for in a household they had already left. The loop
  -- only sees current memberships, and the profile delete below would null
  -- premium_source_user_id while leaving the flag set — premium forever.
  update public.households
  set is_premium = false,
      premium_source_user_id = null,
      premium_expires_at = null
  where premium_source_user_id = target;

  -- A household whose owner_id points at the user but with no owner
  -- membership row should not exist (the creation trigger makes both), but if
  -- one does it would block the auth-user deletion via ON DELETE RESTRICT.
  -- Fail loudly rather than delete someone else's data on a guess.
  if exists (select 1 from public.households where owner_id = target) then
    raise exception 'Inconsistent ownership for user %', target
      using errcode = '23503';
  end if;

  -- Explicit rather than left to the auth-user cascade, so every constraint is
  -- checked inside this transaction. Nulls created_by on surviving rows,
  -- premium_source_user_id, and removes the user's invites.
  delete from public.profiles where id = target;

  return jsonb_build_object(
    'deleted_households', deleted_households,
    'transferred', transferred,
    'left_households', left_households
  );
end;
$$;

-- Service role only. Not callable by any client role, even for itself: the
-- Edge Function is the one place that also revokes the Apple token and deletes
-- the auth user, so a client must not be able to run half of the deletion.
revoke execute on function public.delete_account_data(uuid)
  from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;
