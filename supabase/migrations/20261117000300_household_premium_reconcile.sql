-- Household premium from all members' RevenueCat entitlements (1.0.9).
--
-- RevenueCat's REST API is the source of truth; the Edge Functions
-- (claim-premium, and the webhook, which now treats every event as "re-check
-- these users") fetch each member's entitlement and hand the lot to this
-- function, which is the only thing that grants premium. Leaving, removal and
-- account deletion keep their existing source-scoped clears.
--
-- The best active entitlement among *current* members wins: lifetime beats any
-- expiry, then the latest expiry; ties keep the current source. Deciding over
-- every member, under a row lock, is what makes this safe where the old
-- webhook path was not:
--   * one member's EXPIRATION/REFUND can't wipe premium another provides;
--   * a renewal can't overwrite someone's lifetime with a shorter expiry;
--   * if the member who took over as source lapses, whoever else is still
--     entitled takes it back in the same call;
--   * concurrent claim/webhook calls serialise on the lock, and the result
--     depends only on the input and current membership, so repeats and
--     out-of-order webhooks are harmless.

create function public.apply_household_premium(hid uuid, entitlements jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cur public.households%rowtype;
  new_source uuid;
  new_expires timestamptz;
  new_premium boolean;
  changed boolean := false;
begin
  select * into cur from public.households where id = hid for update;
  if not found then
    return null;
  end if;

  with reported as (
    select (e->>'user_id')::uuid as user_id,
           coalesce((e->>'active')::boolean, false) as active,
           (e->>'expires_at')::timestamptz as expires_at
    from jsonb_array_elements(coalesce(entitlements, '[]'::jsonb)) as e
  ),
  candidates as (
    -- Reported, active, unexpired, and still a member at write time.
    select r.user_id, r.expires_at
    from reported r
    join public.household_members m
      on m.household_id = hid and m.user_id = r.user_id
    where r.active and (r.expires_at is null or r.expires_at > now())
    union all
    -- The current source wasn't in the caller's snapshot (e.g. joined after
    -- the caller listed members): unknown is not "lapsed", so it stays in the
    -- running.
    select cur.premium_source_user_id, cur.premium_expires_at
    where cur.is_premium
      and cur.premium_source_user_id is not null
      and (cur.premium_expires_at is null or cur.premium_expires_at > now())
      and not exists (select 1 from reported r
                      where r.user_id = cur.premium_source_user_id)
      and exists (select 1 from public.household_members m
                  where m.household_id = hid
                    and m.user_id = cur.premium_source_user_id)
  )
  select c.user_id, c.expires_at into new_source, new_expires
  from candidates c
  order by c.expires_at desc nulls first,                              -- lifetime, then latest
           (c.user_id = cur.premium_source_user_id) desc nulls last,   -- ties: no churn
           c.user_id
  limit 1;

  new_premium := new_source is not null;

  if new_premium is distinct from cur.is_premium
     or new_source is distinct from cur.premium_source_user_id
     or new_expires is distinct from cur.premium_expires_at then
    update public.households
    set is_premium = new_premium,
        premium_source_user_id = new_source,
        premium_expires_at = new_expires
    where id = hid;
    changed := true;
  end if;

  return jsonb_build_object(
    'household_id', hid,
    'is_premium', new_premium,
    'changed', changed
  );
end;
$$;

revoke execute on function public.apply_household_premium(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.apply_household_premium(uuid, jsonb) to service_role;
