-- Replace the MBBS subject catalog with the university-exam subjects.
-- 1st: Anatomy, Physiology, Biochemistry
-- 2nd: Pathology, Pharmacology, Microbiology
-- 3rd: FMT, PSM, Ophthalmology, ENT
-- 4th: Medicine, Surgery, OBGYN, Pediatrics
--
-- Longer names already in the database are renamed onto these labels.
-- Allied subjects (Orthopedics, Dermatology, Psychiatry, Anesthesia,
-- Radiology) are dropped only when they have no papers, tests, or lessons.

-- ---------------------------------------------------------------------------
-- Rename existing rows onto the catalog labels
-- ---------------------------------------------------------------------------

update public.subjects s
set name = m.new_name
from (
  values
    ('Forensic Medicine', 'FMT'),
    ('Forensic Medicine & Toxicology', 'FMT'),
    ('Forensic Medicine and Toxicology', 'FMT'),
    ('Community Medicine', 'PSM'),
    ('Preventive and Social Medicine', 'PSM'),
    ('Preventive & Social Medicine', 'PSM'),
    ('SPM', 'PSM'),
    ('Obstetrics & Gynaecology', 'OBGYN'),
    ('Obstetrics and Gynaecology', 'OBGYN'),
    ('Obstetrics & Gynecology', 'OBGYN'),
    ('Obstetrics and Gynecology', 'OBGYN'),
    ('OBG', 'OBGYN'),
    ('Paediatrics', 'Pediatrics')
) as m(old_name, new_name)
where lower(s.name) = lower(m.old_name)
  and not exists (
    select 1
    from public.subjects kept
    where lower(kept.name) = lower(m.new_name)
      and kept.id <> s.id
  );

-- If both the long name and the short name already exist, move children
-- onto the short-name row, then drop the empty alias.
do $$
declare
  r record;
  v_keep uuid;
begin
  for r in
    select *
    from (
      values
        ('Forensic Medicine', 'FMT'),
        ('Forensic Medicine & Toxicology', 'FMT'),
        ('Forensic Medicine and Toxicology', 'FMT'),
        ('Community Medicine', 'PSM'),
        ('Preventive and Social Medicine', 'PSM'),
        ('Preventive & Social Medicine', 'PSM'),
        ('SPM', 'PSM'),
        ('Obstetrics & Gynaecology', 'OBGYN'),
        ('Obstetrics and Gynaecology', 'OBGYN'),
        ('Obstetrics & Gynecology', 'OBGYN'),
        ('Obstetrics and Gynecology', 'OBGYN'),
        ('OBG', 'OBGYN'),
        ('Paediatrics', 'Pediatrics')
    ) as m(old_name, new_name)
  loop
    select id into v_keep
    from public.subjects
    where lower(name) = lower(r.new_name)
    limit 1;

    if v_keep is null then
      continue;
    end if;

    update public.topics t
    set subject_id = v_keep
    where t.subject_id in (
      select id from public.subjects where lower(name) = lower(r.old_name)
    )
    and not exists (
      select 1 from public.topics existing
      where existing.subject_id = v_keep
        and lower(existing.name) = lower(t.name)
    );

    update public.exam_papers ep
    set subject_id = v_keep
    where ep.subject_id in (
      select id from public.subjects where lower(name) = lower(r.old_name)
    );

    update public.tests te
    set subject_id = v_keep
    where te.subject_id in (
      select id from public.subjects where lower(name) = lower(r.old_name)
    );
  end loop;
end;
$$;

delete from public.subjects s
where lower(s.name) in (
  'forensic medicine',
  'forensic medicine & toxicology',
  'forensic medicine and toxicology',
  'community medicine',
  'preventive and social medicine',
  'preventive & social medicine',
  'spm',
  'obstetrics & gynaecology',
  'obstetrics and gynaecology',
  'obstetrics & gynecology',
  'obstetrics and gynecology',
  'obg',
  'paediatrics'
)
and exists (
  select 1 from public.subjects kept
  where lower(kept.name) in ('fmt', 'psm', 'obgyn', 'pediatrics')
    and kept.id <> s.id
    and (
      (lower(s.name) like '%forensic%' and lower(kept.name) = 'fmt')
      or (lower(s.name) in ('community medicine', 'preventive and social medicine', 'preventive & social medicine', 'spm') and lower(kept.name) = 'psm')
      or ((lower(s.name) like 'obstetric%' or lower(s.name) = 'obg') and lower(kept.name) = 'obgyn')
      or (lower(s.name) = 'paediatrics' and lower(kept.name) = 'pediatrics')
    )
)
and not exists (
  select 1 from public.topics t where t.subject_id = s.id
)
and not exists (
  select 1 from public.exam_papers ep where ep.subject_id = s.id
)
and not exists (
  select 1 from public.tests te where te.subject_id = s.id
);

-- ---------------------------------------------------------------------------
-- Year map
-- ---------------------------------------------------------------------------

delete from public.subject_phase_defaults
where lower(subject_name) not in (
  'anatomy', 'physiology', 'biochemistry',
  'pathology', 'pharmacology', 'microbiology',
  'fmt', 'psm', 'ophthalmology', 'ent',
  'medicine', 'surgery', 'obgyn', 'pediatrics'
);

insert into public.subject_phase_defaults (subject_name, phase_code, display_order) values
  ('Anatomy', 'year1', 1),
  ('Physiology', 'year1', 2),
  ('Biochemistry', 'year1', 3),
  ('Pathology', 'year2', 4),
  ('Pharmacology', 'year2', 5),
  ('Microbiology', 'year2', 6),
  ('FMT', 'year3', 7),
  ('PSM', 'year3', 8),
  ('Ophthalmology', 'year3', 9),
  ('ENT', 'year3', 10),
  ('Medicine', 'year4', 11),
  ('Surgery', 'year4', 12),
  ('OBGYN', 'year4', 13),
  ('Pediatrics', 'year4', 14)
on conflict (subject_name) do update
  set phase_code = excluded.phase_code,
      display_order = excluded.display_order;

update public.subjects s
set mbbs_phase_id = p.id,
    display_order = d.display_order
from public.subject_phase_defaults d
join public.mbbs_phases p on p.code = d.phase_code
where lower(s.name) = lower(d.subject_name);

insert into public.subjects (name, display_order, mbbs_phase_id)
select d.subject_name, d.display_order, p.id
from public.subject_phase_defaults d
join public.mbbs_phases p on p.code = d.phase_code
where not exists (
  select 1 from public.subjects s where lower(s.name) = lower(d.subject_name)
);

-- ---------------------------------------------------------------------------
-- Drop allied subjects that the seed created and nothing references
-- ---------------------------------------------------------------------------

delete from public.subjects s
where lower(s.name) in (
  'orthopedics',
  'orthopaedics',
  'dermatology',
  'psychiatry',
  'anesthesia',
  'anaesthesia',
  'radiology'
)
and not exists (
  select 1
  from public.topics t
  join public.questions q on q.topic_id = t.id
  where t.subject_id = s.id
)
and not exists (
  select 1
  from public.topics t
  join public.lessons l on l.topic_id = t.id
  where t.subject_id = s.id
)
and not exists (
  select 1 from public.exam_papers ep where ep.subject_id = s.id
)
and not exists (
  select 1 from public.tests te where te.subject_id = s.id
);

-- Anything left outside the catalog (for example an allied subject that still
-- has questions) is untagged so it no longer appears under an MBBS year.
update public.subjects s
set mbbs_phase_id = null
where not exists (
  select 1
  from public.subject_phase_defaults d
  where lower(d.subject_name) = lower(s.name)
);
