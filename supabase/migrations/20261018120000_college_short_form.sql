-- Campus short form on colleges, same idea as universities.code.
-- Unique within a university (case-insensitive) so pickers can show
-- `MAMC · Maulana Azad Medical College`.

alter table public.colleges
  add column if not exists short_form text;

-- Rows that predate the column get a throwaway value so NOT NULL can land.
-- scripts/seed_universities_colleges.py replaces the whole catalog after this.
update public.colleges
set short_form = 'row-' || substr(replace(id::text, '-', ''), 1, 12)
where short_form is null or btrim(short_form) = '';

alter table public.colleges
  alter column short_form set not null;

create unique index if not exists colleges_university_short_form_lower_idx
  on public.colleges (university_id, lower(short_form));

comment on column public.colleges.short_form is
  'Campus short form (MAMC). Unique within a university, case-insensitive.';
