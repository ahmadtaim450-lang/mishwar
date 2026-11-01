-- ═══════════════════════════════════════════════════════════════════
-- مشوار: تفضيلات السفر، ملف السائق العام مع التقييمات، وطلب حذف الحساب
-- ═══════════════════════════════════════════════════════════════════

alter table public.profiles add column if not exists travel_prefs jsonb not null default '{}'::jsonb
  check (jsonb_typeof(travel_prefs) = 'object' and pg_column_size(travel_prefs) < 2000);
alter table public.profiles add column if not exists deletion_requested_at timestamptz;
grant update (travel_prefs) on public.profiles to authenticated;

-- ملف السائق كما بيشوفو الراكب: بلا رقم موبايل، مع آخر التقييمات
create or replace function public.driver_public(p_driver uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'full_name', p.full_name, 'avatar_path', p.avatar_path,
    'rating_avg', p.rating_avg, 'rating_count', p.rating_count, 'trips_count', p.trips_count,
    'verified', p.driver_status = 'approved', 'member_since', p.created_at, 'travel_prefs', p.travel_prefs,
    'histogram', (select jsonb_object_agg(s, coalesce(c, 0)) from generate_series(1, 5) s
                  left join (select stars, count(*) c from public.reviews where target_id = p.id group by stars) r on r.stars = s),
    'reviews', coalesce((select jsonb_agg(x order by x.created_at desc) from (
        select r.stars, r.tags, r.comment, r.created_at, split_part(a.full_name, ' ', 1) as author
        from public.reviews r join public.profiles a on a.id = r.author_id
        where r.target_id = p.id order by r.created_at desc limit 20) x), '[]'::jsonb)
  )
  from public.profiles p where p.id = p_driver and auth.uid() is not null;
$$;

-- طلب حذف الحساب: بيتسجّل وبتشوفو الإدارة (الحذف الفعلي بعد إلغاء الحجوزات بأمان)
create or replace function public.request_account_deletion() returns void
language plpgsql security definer set search_path = public as $$
declare u uuid := public._uid();
begin
  update public.profiles set deletion_requested_at = now() where id = u;
  -- الحجوزات الجاية بتتلغى فوراً
  update public.trips t set seats_available = least(t.seats_total, t.seats_available + b.seats)
  from public.bookings b where b.trip_id = t.id and b.rider_id = u and b.status = 'confirmed' and t.status = 'scheduled';
  update public.bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = 'حذف الحساب'
  where rider_id = u and status in ('pending', 'confirmed');
  perform public._notify(p.id, 'admin.deletion', 'طلب حذف حساب', (select full_name from public.profiles where id = u), jsonb_build_object('user_id', u))
  from public.profiles p where p.role = 'admin';
  perform public._audit('account.delete_request', 'profile', u::text);
end $$;

revoke execute on function public.driver_public(uuid), public.request_account_deletion() from public, anon;
grant execute on function public.driver_public(uuid), public.request_account_deletion() to authenticated;

-- my_profile صار فيه تفضيلات السفر
create or replace function public.my_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'full_name', p.full_name, 'gender', p.gender, 'avatar_path', p.avatar_path, 'role', p.role,
    'driver_status', p.driver_status, 'rating_avg', p.rating_avg, 'rating_count', p.rating_count,
    'trips_count', p.trips_count, 'music_pref', p.music_pref, 'travel_prefs', p.travel_prefs,
    'phone', pp.phone, 'created_at', p.created_at,
    'vehicle', (select to_jsonb(v) from public.vehicles v where v.owner_id = p.id and v.verified order by v.created_at desc limit 1)
  )
  from public.profiles p left join public.profile_private pp on pp.id = p.id
  where p.id = auth.uid();
$$;
