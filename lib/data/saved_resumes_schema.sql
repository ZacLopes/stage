-- Create Table: saved_resumes (Metadata)
create table public.saved_resumes (
  id uuid not null default gen_random_uuid (),
  user_id uuid not null default auth.uid (),
  title text not null,
  file_path text not null, -- Path in Storage (e.g. {user_id}/{timestamp}.pdf)
  created_at timestamp with time zone not null default now(),
  constraint saved_resumes_pkey primary key (id),
  constraint saved_resumes_user_id_fkey foreign key (user_id) references user_profiles (id) on delete cascade
);

-- RLS Policies for the metadata table
alter table public.saved_resumes enable row level security;

create policy "Users can view their own resumes" on public.saved_resumes for select to authenticated using ( (select auth.uid()) = user_id );
create policy "Users can insert their own resumes" on public.saved_resumes for insert to authenticated with check ( (select auth.uid()) = user_id );
create policy "Users can delete their own resumes" on public.saved_resumes for delete to authenticated using ( (select auth.uid()) = user_id );

-----------------------------------------------------------
-- STORAGE CONFIGURATION
-- Run these to create the bucket and set permissions
-----------------------------------------------------------

-- 1. Create the bucket
insert into storage.buckets (id, name, public)
values ('resumes', 'resumes', false)
on conflict (id) do nothing;

-- 2. Storage Policies (Allow users to manage their own folder: resumes/{user_id}/*)

create policy "Users can upload their own resumes"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'resumes' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can view their own resumes from storage"
on storage.objects for select
to authenticated
using (
  bucket_id = 'resumes' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can delete their own resumes from storage"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'resumes' AND
  (storage.foldername(name))[1] = auth.uid()::text
);
