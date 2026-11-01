-- ═══════════════════════════════════════════════════════════════════
-- مشوار: التخزين (أوراق السائقين خاصة، الصور الشخصية عامة) والمدن
-- ═══════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('driver-docs', 'driver-docs', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- أوراق السائق: كل واحد بيرفع ويقرا جوا مجلدو بس ({uid}/...)، والإدارة بتقرا الكل
create policy driver_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'driver-docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy driver_docs_update on storage.objects for update to authenticated
  using (bucket_id = 'driver-docs' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'driver-docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy driver_docs_read on storage.objects for select to authenticated
  using (bucket_id = 'driver-docs' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff()));

create policy avatars_read on storage.objects for select using (bucket_id = 'avatars');
create policy avatars_write on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

insert into public.cities (id, name_ar, lat, lon, spots) values
  ('damascus', 'دمشق', 33.5138, 36.2765, array['كراجات البرامكة', 'المزة', 'باب توما']),
  ('aleppo', 'حلب', 36.2021, 37.1343, array['كراج الراموسة', 'الجميلية']),
  ('latakia', 'اللاذقية', 35.5196, 35.7832, array['الكورنيش', 'الدوار الأزرق', 'الزراعة']),
  ('homs', 'حمص', 34.7324, 36.7137, array['كراج حمص الجديد', 'الإنشاءات']),
  ('tartus', 'طرطوس', 34.8890, 35.8866, array['الكورنيش البحري', 'كراج الانطلاق']),
  ('hama', 'حماة', 35.1318, 36.7578, array['ساحة العاصي', 'كراج البولمان']),
  ('jableh', 'جبلة', 35.3610, 35.9256, array['المدخل الشمالي', 'الكراج']),
  ('daraa', 'درعا', 32.6189, 36.1021, array['الكراج الجنوبي']),
  ('banias', 'بانياس', 35.1828, 35.9486, array['الكورنيش', 'مدخل المدينة']),
  ('idlib', 'إدلب', 35.9306, 36.6339, array['الكراج', 'ساحة الساعة']),
  ('raqqa', 'الرقة', 35.9500, 39.0100, array['الكراج', 'دوار النعيم']),
  ('deir_ez_zor', 'دير الزور', 35.3360, 40.1400, array['الكراج', 'الجسر المعلّق']),
  ('hasakah', 'الحسكة', 36.5000, 40.7500, array['الكراج', 'المركز']),
  ('qamishli', 'القامشلي', 37.0500, 41.2200, array['الكراج', 'المركز']),
  ('sweida', 'السويداء', 32.7090, 36.5660, array['الكراج', 'دوار المشنقة']),
  ('palmyra', 'تدمر', 34.5600, 38.2800, array['المدخل الغربي']),
  ('salamiyah', 'السلمية', 35.0110, 37.0530, array['الكراج', 'المركز']),
  ('safita', 'صافيتا', 34.8200, 36.1170, array['الكراج', 'المركز']),
  ('qardaha', 'القرداحة', 35.4560, 36.0560, array['المركز']),
  ('manbij', 'منبج', 36.5280, 37.9550, array['الكراج', 'المركز']),
  ('quneitra', 'القنيطرة', 33.1260, 35.8240, array['مدينة البعث', 'الكراج']),
  ('nabk', 'النبك', 34.0237, 36.7280, array['استراحة الأوتوستراد'])
on conflict (id) do nothing;
