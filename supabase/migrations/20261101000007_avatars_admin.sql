-- ═══════════════════════════════════════════════════════════════════
-- مشوار: الصورة الشخصية (حذف القديمة + حماية المسار) وأرقام لوحة الإدارة
-- ═══════════════════════════════════════════════════════════════════

create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- الصورة لازم تكون من مجلد صاحب الحساب
create or replace function public.check_avatar_path() returns trigger
language plpgsql as $$
begin
  if new.avatar_path is distinct from old.avatar_path and new.avatar_path is not null
     and (new.avatar_path not like new.id::text || '/%' or new.avatar_path like '%..%') then
    raise exception 'INVALID_INPUT' using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger profiles_avatar_path before update of avatar_path on public.profiles
for each row execute function public.check_avatar_path();

-- نظرة عامة للإدارة
create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then perform public._fail('FORBIDDEN'); end if;
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'drivers', (select count(*) from public.profiles where driver_status = 'approved'),
    'pending_applications', (select count(*) from public.driver_applications where status in ('submitted', 'reviewing', 'interview')),
    'trips_upcoming', (select count(*) from public.trips where status = 'scheduled' and departure_at > now()),
    'trips_today', (select count(*) from public.trips where (departure_at at time zone 'Asia/Damascus')::date = (now() at time zone 'Asia/Damascus')::date),
    'bookings_week', (select count(*) from public.bookings where created_at > now() - interval '7 days'),
    'confirmed_week', (select count(*) from public.bookings where status in ('confirmed', 'completed') and created_at > now() - interval '7 days'),
    'open_reports', (select count(*) from public.reports where status = 'open'),
    'suspended', (select count(*) from public.profiles where driver_status = 'suspended'),
    'top_routes', coalesce((select jsonb_agg(x) from (
        select public._city_name(from_city) || ' ← ' || public._city_name(to_city) as route, count(*) as trips
        from public.trips where created_at > now() - interval '30 days' group by from_city, to_city order by count(*) desc limit 5) x), '[]'::jsonb)
  );
end $$;
revoke execute on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;
revoke execute on function public.check_avatar_path() from public, anon, authenticated;
