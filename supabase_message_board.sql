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

-- ============================================================
-- 🎨 自定义开屏图标（v2.9.0）
-- 使用前请先把上海大学图标保存为项目根目录 icon-shu.png 并推送部署
-- ============================================================

-- user_settings 增加 icon_url 列：dataURL（App 内上传）或图片 URL；空值 = 默认 CUHK 校徽
alter table public.user_settings add column if not exists icon_url text;

-- 给 35 账号（3057278447@qq.com）绑定上海大学图标（已存在行则更新，不存在则插入）
insert into public.user_settings (user_id, icon_url, updated_at)
select u.id, 'https://deliciouskfc.github.io/calendar-reminder/icon-shu.png', now()
from auth.users u
where lower(u.email) = '3057278447@qq.com'
on conflict (user_id) do update set icon_url = excluded.icon_url, updated_at = now();

-- ============================================================
-- 📎 课件文件云存储（v2.10.0）
-- 电脑 / 手机 / iPad 三端通用：文件存 Supabase Storage，按账户隔离
-- 替代旧的 GitHub 仓库 Contents API（旧方案 1MB 上限、需 Token、易失败）
-- ============================================================

-- 1. 课件元数据表（文件本体在 Storage，这里只存清单）
create table if not exists public.courseware_files (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  course_key text not null default '',   -- 归一化课程 section，如 CSC1001L02
  name text not null,
  type text not null default '',
  size bigint not null default 0,
  created_at timestamptz not null default now()
);
alter table public.courseware_files enable row level security;

drop policy if exists "courseware_select_own" on public.courseware_files;
create policy "courseware_select_own" on public.courseware_files
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "courseware_insert_own" on public.courseware_files;
create policy "courseware_insert_own" on public.courseware_files
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "courseware_delete_own" on public.courseware_files;
create policy "courseware_delete_own" on public.courseware_files
  for delete to authenticated using (auth.uid() = user_id);

-- 2. 私有存储桶（对象路径 {user_id}/{file_id}）
insert into storage.buckets (id, name, public)
values ('courseware', 'courseware', false)
on conflict (id) do nothing;

-- 3. 存储桶 RLS：用户只能读写自己 user_id 前缀下的对象
drop policy if exists "courseware_storage_read" on storage.objects;
create policy "courseware_storage_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'courseware' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "courseware_storage_insert" on storage.objects;
create policy "courseware_storage_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'courseware' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "courseware_storage_delete" on storage.objects;
create policy "courseware_storage_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'courseware' and (storage.foldername(name))[1] = auth.uid()::text);
