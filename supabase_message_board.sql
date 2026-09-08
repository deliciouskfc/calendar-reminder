-- ============================================================
-- 💬 留言板 & 👑 管理员功能（v2.4.0）
-- 使用方法：打开 Supabase Dashboard → SQL Editor → 粘贴全部内容 → Run
-- 管理员账户：2214077724@qq.com / 3057278447@qq.com
-- 超级管理员（唯一可删除留言）：2214077724@qq.com
-- ============================================================

-- 1) 管理员判断函数（security definer，可读取 auth.users 中的邮箱）
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((
    select lower(u.email) in ('2214077724@qq.com', '3057278447@qq.com')
    from auth.users u
    where u.id = auth.uid()
  ), false);
$$;

-- 1b) 超级管理员判断（仅 2214077724@qq.com，唯一拥有删除留言权限）
create or replace function public.is_super_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((
    select lower(u.email) = '2214077724@qq.com'
    from auth.users u
    where u.id = auth.uid()
  ), false);
$$;

-- 2) 留言表
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_email text not null default '',
  recipient_id uuid not null references auth.users(id) on delete cascade,
  recipient_email text not null default '',
  content text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.messages enable row level security;

-- 只能看到自己发出 / 收到的留言（管理员可看全部，便于管理）
drop policy if exists "messages_select_participant" on public.messages;
create policy "messages_select_participant" on public.messages
  for select to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id or public.is_admin());

-- 只能以自己名义发留言
drop policy if exists "messages_insert_sender" on public.messages;
create policy "messages_insert_sender" on public.messages
  for insert to authenticated
  with check (auth.uid() = sender_id);

-- 收件人可标记已读
drop policy if exists "messages_update_recipient" on public.messages;
create policy "messages_update_recipient" on public.messages
  for update to authenticated
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);

-- 删除留言权限仅限超级管理员 2214077724@qq.com（v2.8.1 收紧）
drop policy if exists "messages_delete_admin" on public.messages;
create policy "messages_delete_admin" on public.messages
  for delete to authenticated
  using (public.is_super_admin());

-- 3) 管理员可只读查看所有账户的课表与校历
drop policy if exists "timetables_admin_read" on public.timetables;
create policy "timetables_admin_read" on public.timetables
  for select to authenticated
  using (public.is_admin());

drop policy if exists "user_settings_admin_read" on public.user_settings;
create policy "user_settings_admin_read" on public.user_settings
  for select to authenticated
  using (public.is_admin());

-- 4) 列出所有注册用户（仅管理员可调用）
create or replace function public.list_all_users()
returns table (id uuid, email text, created_at timestamptz)
language sql volatile security definer set search_path = public
as $$
  select u.id, u.email, u.created_at
  from auth.users u
  where public.is_admin()
  order by u.created_at asc;
$$;
grant execute on function public.list_all_users() to authenticated;

-- 5) 列出管理员（普通用户用来给管理员发新留言）
create or replace function public.list_admins()
returns table (id uuid, email text)
language sql stable security definer set search_path = public
as $$
  select u.id, lower(u.email)
  from auth.users u
  where lower(u.email) in ('2214077724@qq.com', '3057278447@qq.com');
$$;
grant execute on function public.list_admins() to authenticated;
