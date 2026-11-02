-- Caren Bragagnollo · funções públicas (agendar, consultar, cancelar, remarcar, mensagem)
create or replace function public._m(t text) returns int language sql immutable set search_path = public as $$
  select split_part(t, ':', 1)::int * 60 + split_part(t, ':', 2)::int
$$;
create or replace function public._now_local() returns timestamp language sql stable set search_path = public as $$
  select (now() at time zone 'America/Sao_Paulo')::timestamp
$$;
create or replace function public._digits(t text) returns text language sql immutable set search_path = public as $$
  select regexp_replace(coalesce(t, ''), '\D', '', 'g')
$$;

create or replace function public._slot_problem(p_date date, p_time time, p_dur int, p_ignore uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  c jsonb; s int; e int; ls int; le int; slot int; adv int;
  tm int := extract(hour from p_time)::int * 60 + extract(minute from p_time)::int;
  nowl timestamp := public._now_local();
begin
  select cfg into c from public.settings where id = 1;
  if c is null then return 'Agenda indisponível no momento.'; end if;
  if p_date < nowl::date then return 'Essa data já passou.'; end if;
  if p_date > nowl::date + 120 then return 'Escolha uma data nos próximos 4 meses.'; end if;
  if not ((c -> 'days') @> to_jsonb(extract(dow from p_date)::int)) then return 'Não há atendimento nesse dia.'; end if;
  s := public._m(c ->> 'start'); e := public._m(c ->> 'end');
  slot := coalesce((c ->> 'slot')::int, 30); adv := coalesce((c ->> 'adv')::int, 0);
  if tm < s or tm + p_dur > e then return 'Horário fora do expediente.'; end if;
  if (tm - s) % slot <> 0 then return 'Horário inválido.'; end if;
  if coalesce(c ->> 'ls', '') <> '' and coalesce(c ->> 'le', '') <> '' then
    ls := public._m(c ->> 'ls'); le := public._m(c ->> 'le');
    if ls < le and tm < le and tm + p_dur > ls then return 'Esse horário cai na pausa do almoço.'; end if;
  end if;
  if (p_date + p_time) < nowl + make_interval(hours => adv) then return 'Esse horário não está mais disponível.'; end if;
  if exists (select 1 from public.blocks b where b.date = p_date and (b.t_from is null
      or (b.t_from < (p_time + make_interval(mins => p_dur)) and b.t_to > p_time))) then
    return 'A Caren não atende nesse horário.'; end if;
  if exists (select 1 from public.appointments a where a.date = p_date and a.status not in ('cancelada', 'falta')
      and (p_ignore is null or a.id <> p_ignore)
      and a.time < (p_time + make_interval(mins => p_dur)) and (a.time + make_interval(mins => a.dur)) > p_time) then
    return 'Esse horário acabou de ser ocupado. Escolha outro.'; end if;
  return null;
end $$;

create or replace function public.busy_slots(p_from date, p_to date)
returns table(date date, "time" text, dur int)
language sql stable security definer set search_path = public as $$
  select a.date, to_char(a.time, 'HH24:MI'), a.dur from public.appointments a
  where a.date between p_from and least(p_to, p_from + 130)
    and a.status not in ('cancelada', 'falta')
$$;

create or replace function public.book_appointment(p_svc text, p_date date, p_time time, p_name text, p_phone text,
  p_email text default '', p_channel text default 'whatsapp', p_gest boolean default false, p_health text default '')
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare sv public.services; prob text; v_code text; v_id uuid; d text := public._digits(p_phone); n int;
begin
  if char_length(trim(coalesce(p_name, ''))) < 3 or char_length(p_name) > 120 then raise exception 'Informe o nome completo.'; end if;
  if char_length(d) < 10 or char_length(d) > 13 then raise exception 'Informe um telefone com DDD.'; end if;
  if char_length(coalesce(p_health, '')) > 1000 or char_length(coalesce(p_email, '')) > 120 then raise exception 'Texto muito longo.'; end if;
  select * into sv from public.services where id = p_svc and active;
  if not found then raise exception 'Esse procedimento não está disponível para agendamento.'; end if;
  perform pg_advisory_xact_lock(hashtext('agenda:' || p_date::text));
  prob := public._slot_problem(p_date, p_time, sv.dur, null);
  if prob is not null then raise exception '%', prob; end if;
  select count(*) into n from public.appointments where right(public._digits(phone), 8) = right(d, 8)
    and status in ('agendada', 'confirmada') and date >= public._now_local()::date;
  if n >= 4 then raise exception 'Você já tem vários horários marcados. Fale com a Caren pelo WhatsApp para marcar mais.'; end if;
  loop
    v_code := 'CC-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.appointments where code = v_code);
  end loop;
  insert into public.appointments(code, name, phone, email, svc_id, dur, price, date, time, status, channel, gest, health, log)
  values (v_code, trim(p_name), trim(p_phone), lower(trim(coalesce(p_email, ''))), sv.id, sv.dur, sv.price, p_date, p_time, 'agendada',
    case when p_channel in ('whatsapp', 'sms', 'email') then p_channel else 'whatsapp' end, coalesce(p_gest, false), trim(coalesce(p_health, '')),
    jsonb_build_array(jsonb_build_object('at', to_char(public._now_local(), 'YYYY-MM-DD"T"HH24:MI'), 'txt', 'Agendado pelo site')))
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code, 'date', p_date, 'time', to_char(p_time, 'HH24:MI'), 'svc', sv.id, 'dur', sv.dur, 'price', sv.price, 'channel', p_channel);
end $$;

create or replace function public._owner_ok(p_phone text, p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select char_length(public._digits(p_phone)) >= 8 and exists (select 1 from public.appointments a
    where a.code = upper(trim(coalesce(p_code, ''))) and right(public._digits(a.phone), 8) = right(public._digits(p_phone), 8))
$$;

create or replace function public.my_appointments(p_phone text, p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._owner_ok(p_phone, p_code) then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'svc', a.svc_id, 'dur', a.dur, 'price', a.price,
      'date', a.date, 'time', to_char(a.time, 'HH24:MI'), 'status', a.status) order by a.date, a.time)
    from public.appointments a where right(public._digits(a.phone), 8) = right(public._digits(p_phone), 8)
      and a.date >= public._now_local()::date - 365), '[]'::jsonb);
end $$;

create or replace function public.client_cancel(p_phone text, p_code text, p_id uuid)
returns boolean language plpgsql volatile security definer set search_path = public as $$
declare a public.appointments;
begin
  if not public._owner_ok(p_phone, p_code) then raise exception 'Confira o telefone e o código.'; end if;
  select * into a from public.appointments where id = p_id and right(public._digits(phone), 8) = right(public._digits(p_phone), 8);
  if not found then raise exception 'Agendamento não encontrado.'; end if;
  if a.status not in ('agendada', 'confirmada') or a.date < public._now_local()::date then raise exception 'Esse horário não pode mais ser cancelado pelo site. Fale com a Caren.'; end if;
  update public.appointments set status = 'cancelada', cancel_reason = 'Cancelado pela cliente no site',
    log = log || jsonb_build_array(jsonb_build_object('at', to_char(public._now_local(), 'YYYY-MM-DD"T"HH24:MI'), 'txt', 'Cancelado pela cliente no site'))
  where id = p_id;
  insert into public.messages(kind, name, contact, text) values ('contato', a.name, a.phone,
    'Cancelou pelo site o horário de ' || to_char(a.date, 'DD/MM') || ' às ' || to_char(a.time, 'HH24:MI') || '.');
  return true;
end $$;

create or replace function public.client_reschedule(p_phone text, p_code text, p_id uuid, p_date date, p_time time)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare a public.appointments; prob text; old text;
begin
  if not public._owner_ok(p_phone, p_code) then raise exception 'Confira o telefone e o código.'; end if;
  select * into a from public.appointments where id = p_id and right(public._digits(phone), 8) = right(public._digits(p_phone), 8);
  if not found then raise exception 'Agendamento não encontrado.'; end if;
  if a.status not in ('agendada', 'confirmada') then raise exception 'Esse horário não pode ser remarcado pelo site. Fale com a Caren.'; end if;
  perform pg_advisory_xact_lock(hashtext('agenda:' || p_date::text));
  prob := public._slot_problem(p_date, p_time, a.dur, a.id);
  if prob is not null then raise exception '%', prob; end if;
  old := to_char(a.date, 'DD/MM') || ' ' || to_char(a.time, 'HH24:MI');
  update public.appointments set date = p_date, time = p_time, status = 'agendada', rem_sent = false,
    log = log || jsonb_build_array(jsonb_build_object('at', to_char(public._now_local(), 'YYYY-MM-DD"T"HH24:MI'), 'txt', 'Remarcado pela cliente no site (era ' || old || ')'))
  where id = p_id;
  return jsonb_build_object('id', a.id, 'code', a.code, 'date', p_date, 'time', to_char(p_time, 'HH24:MI'), 'svc', a.svc_id, 'dur', a.dur, 'price', a.price);
end $$;

create or replace function public.send_message(p_kind text, p_name text, p_contact text, p_text text)
returns boolean language plpgsql volatile security definer set search_path = public as $$
begin
  if p_kind not in ('contato', 'espera') then raise exception 'Tipo inválido.'; end if;
  if char_length(trim(coalesce(p_contact, ''))) < 3 or char_length(p_contact) > 120 then raise exception 'Informe um telefone ou e-mail.'; end if;
  if char_length(trim(coalesce(p_text, ''))) < 1 or char_length(p_text) > 2000 or char_length(coalesce(p_name, '')) > 120 then raise exception 'Mensagem inválida.'; end if;
  if (select count(*) from public.messages where contact = trim(p_contact) and at > now() - interval '1 day') >= 5
     or (select count(*) from public.messages where at > now() - interval '10 minutes') >= 30 then
    raise exception 'Muitas mensagens em pouco tempo. Tente mais tarde ou chame no WhatsApp.'; end if;
  insert into public.messages(kind, name, contact, text) values (p_kind, trim(coalesce(p_name, '')), trim(p_contact), trim(p_text));
  return true;
end $$;

revoke execute on function public._slot_problem(date, time, int, uuid), public._owner_ok(text, text) from public, anon, authenticated;
grant execute on function public.busy_slots(date, date), public.book_appointment(text, date, time, text, text, text, text, boolean, text),
  public.my_appointments(text, text), public.client_cancel(text, text, uuid), public.client_reschedule(text, text, uuid, date, time),
  public.send_message(text, text, text, text) to anon, authenticated;
