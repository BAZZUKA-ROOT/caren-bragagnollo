-- Caren Bragagnollo · tabelas e regras de acesso (RLS)
create table public.settings (
  id int primary key default 1 check (id = 1),
  cfg jsonb not null,
  clinic jsonb not null default '{}'::jsonb,
  tpl jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table public.services (
  id text primary key,
  name text not null check (char_length(name) between 2 and 120),
  cat text not null default 'Outros',
  dur int not null check (dur between 5 and 600),
  price numeric(10,2) not null default 0 check (price >= 0),
  descr text not null default '',
  prep text not null default '',
  active boolean not null default true,
  sort int not null default 0
);
create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  t_from time,
  t_to time,
  reason text not null default '',
  check ((t_from is null and t_to is null) or (t_from < t_to))
);
create index on public.blocks(date);
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null check (char_length(name) between 2 and 120),
  phone text not null check (char_length(phone) between 8 and 30),
  email text not null default '',
  svc_id text references public.services(id) on delete set null,
  dur int not null check (dur between 5 and 600),
  price numeric(10,2) not null default 0,
  date date not null,
  time time not null,
  status text not null default 'agendada' check (status in ('agendada','confirmada','aguardando','atendimento','concluida','falta','cancelada')),
  channel text not null default 'whatsapp',
  gest boolean not null default false,
  health text not null default '',
  notes text not null default '',
  rem_sent boolean not null default false,
  arrived text,
  pay jsonb not null default '{"st":"pendente","method":""}'::jsonb,
  cancel_reason text not null default '',
  log jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
create index on public.appointments(date);
create index on public.appointments(phone);
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('contato','espera')),
  name text not null default '',
  contact text not null check (char_length(contact) between 3 and 120),
  text text not null check (char_length(text) between 1 and 2000),
  at timestamptz not null default now(),
  read boolean not null default false
);
create table public.client_notes (key text primary key, note text not null default '');
create table public.admins (user_id uuid primary key references auth.users(id) on delete cascade);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.admins where user_id = auth.uid())
$$;

alter table public.settings enable row level security;
alter table public.services enable row level security;
alter table public.blocks enable row level security;
alter table public.appointments enable row level security;
alter table public.messages enable row level security;
alter table public.client_notes enable row level security;
alter table public.admins enable row level security;

create policy "settings leitura publica" on public.settings for select to anon, authenticated using (true);
create policy "settings admin escreve" on public.settings for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "services leitura" on public.services for select to anon, authenticated using (active or public.is_admin());
create policy "services admin insere" on public.services for insert to authenticated with check (public.is_admin());
create policy "services admin altera" on public.services for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "services admin exclui" on public.services for delete to authenticated using (public.is_admin());
create policy "blocks leitura publica" on public.blocks for select to anon, authenticated using (true);
create policy "blocks admin insere" on public.blocks for insert to authenticated with check (public.is_admin());
create policy "blocks admin altera" on public.blocks for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "blocks admin exclui" on public.blocks for delete to authenticated using (public.is_admin());
create policy "appts admin le" on public.appointments for select to authenticated using (public.is_admin());
create policy "appts admin insere" on public.appointments for insert to authenticated with check (public.is_admin());
create policy "appts admin altera" on public.appointments for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "appts admin exclui" on public.appointments for delete to authenticated using (public.is_admin());
create policy "msgs admin le" on public.messages for select to authenticated using (public.is_admin());
create policy "msgs admin altera" on public.messages for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "msgs admin exclui" on public.messages for delete to authenticated using (public.is_admin());
create policy "notes admin le" on public.client_notes for select to authenticated using (public.is_admin());
create policy "notes admin insere" on public.client_notes for insert to authenticated with check (public.is_admin());
create policy "notes admin altera" on public.client_notes for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "notes admin exclui" on public.client_notes for delete to authenticated using (public.is_admin());
create policy "admins ve a si" on public.admins for select to authenticated using (user_id = auth.uid());

alter publication supabase_realtime add table public.appointments, public.messages;
