-- 픽잇 커뮤니티 스키마 (초안 2026-10-27)
-- Supabase 대시보드 > SQL Editor에 붙여넣고 Run. 로그인은 Authentication > Providers에서 Email, Google 켜기.

-- 1. 프로필: 본인만 읽고 쓴다. 남에게 보이는 목표는 public_profiles 뷰로만 나간다.
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  gender text check (gender in ('여성','남성','선택 안 함')),
  weight_kg numeric(5,1),          -- 비워 둘 수 있음(건너뛰기)
  body_fat_pct numeric(4,1),
  muscle_kg numeric(5,1),
  goal text not null check (goal in ('대회준비','벌크업','다이어트','체중유지')),
  body_consent_at timestamptz,     -- 몸 수치 수집 동의 시각(따로 받음)
  created_at timestamptz default now()
);
alter table profiles enable row level security;
create policy "본인만 읽기" on profiles for select using (auth.uid() = id);
create policy "본인만 만들기" on profiles for insert with check (auth.uid() = id);
create policy "본인만 고치기" on profiles for update using (auth.uid() = id);

-- 2. 글
create table posts (
  id bigint generated always as identity primary key,
  author_id uuid not null references auth.users on delete cascade default auth.uid(),
  board text not null check (board in ('자유','오늘 식단','제품 후기','질문')),
  goal text not null,              -- 쓸 때의 목표 태그를 복사해 둔다
  title text,
  body text not null check (char_length(body) between 1 and 3000),
  like_count int not null default 0,
  report_count int not null default 0,
  hidden boolean not null default false,
  created_at timestamptz default now()
);

-- 3. 댓글 (익명 번호는 글마다 처음 단 순서로 매긴다)
create table comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references posts on delete cascade,
  author_id uuid not null references auth.users on delete cascade default auth.uid(),
  anon_no int not null,            -- 0 = 글쓴이, 1·2·3… = 익명1·익명2…
  body text not null check (char_length(body) between 1 and 1000),
  report_count int not null default 0,
  hidden boolean not null default false,
  created_at timestamptz default now()
);

-- 4. 공감·신고 (한 사람이 한 번씩만)
create table likes (
  post_id bigint references posts on delete cascade,
  user_id uuid references auth.users on delete cascade default auth.uid(),
  primary key (post_id, user_id)
);
create table reports (
  id bigint generated always as identity primary key,
  post_id bigint references posts on delete cascade,
  comment_id bigint references comments on delete cascade,
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  reason text,
  created_at timestamptz default now(),
  unique (post_id, user_id), unique (comment_id, user_id)
);

-- author_id가 화면으로 나가지 않게: 목록·글 보기는 이 뷰만 쓴다.
create view posts_public with (security_invoker = false) as
  select id, board, goal, title, body, like_count, created_at,
         (author_id = auth.uid()) as is_mine
  from posts where hidden = false;
create view comments_public with (security_invoker = false) as
  select c.id, c.post_id, c.anon_no, c.body, c.created_at, (c.author_id = auth.uid()) as is_mine
  from comments c where c.hidden = false;

alter table posts enable row level security;
alter table comments enable row level security;
alter table likes enable row level security;
alter table reports enable row level security;
-- 원본 테이블은 직접 읽지 못하게 select 정책 없음(본인 글만 예외). 쓰기는 본인 것만.
create policy "본인 글 읽기" on posts for select using (auth.uid() = author_id);
create policy "글쓰기" on posts for insert with check (auth.uid() = author_id);
create policy "본인 글 삭제" on posts for delete using (auth.uid() = author_id);
create policy "본인 댓글 읽기" on comments for select using (auth.uid() = author_id);
create policy "본인 댓글 삭제" on comments for delete using (auth.uid() = author_id);
create policy "공감" on likes for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "신고" on reports for insert with check (auth.uid() = user_id);
grant select on posts_public, comments_public to authenticated;
revoke select on posts_public, comments_public from anon;

-- 댓글 달기: 익명 번호를 서버에서 매긴다
create function add_comment(p_post bigint, p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select case when author_id = auth.uid() then 0 end into n from posts where id = p_post;
  if n is null then
    select anon_no into n from comments where post_id = p_post and author_id = auth.uid() limit 1;
  end if;
  if n is null then
    select coalesce(max(anon_no),0)+1 into n from comments where post_id = p_post and anon_no > 0;
  end if;
  insert into comments(post_id, author_id, anon_no, body) values (p_post, auth.uid(), n, p_body);
end $$;

-- 공감 수, 신고 5회 자동 숨김
create function on_like() returns trigger language plpgsql security definer as $$
begin
  update posts set like_count = like_count + (case when tg_op='INSERT' then 1 else -1 end)
  where id = coalesce(new.post_id, old.post_id);
  return null;
end $$;
create trigger likes_count after insert or delete on likes for each row execute function on_like();

create function on_report() returns trigger language plpgsql security definer as $$
begin
  if new.post_id is not null then
    update posts set report_count = report_count + 1, hidden = (report_count + 1 >= 5) where id = new.post_id;
  else
    update comments set report_count = report_count + 1, hidden = (report_count + 1 >= 5) where id = new.comment_id;
  end if;
  return null;
end $$;
create trigger reports_count after insert on reports for each row execute function on_report();

-- HOT: select * from posts_public where like_count >= 10 order by created_at desc;

-- 탈퇴: 계정과 글·댓글·프로필이 함께 지워진다(on delete cascade)
create function delete_me() returns void language plpgsql security definer set search_path = public as $$
begin
  delete from auth.users where id = auth.uid();
end $$;

-- API 권한 (프로젝트 만들 때 "Grant API access to new tables automatically"를 꺼 둬도 동작하게)
grant usage on schema public to anon, authenticated;
grant select, insert, update on profiles to authenticated;
grant select, insert, delete on posts to authenticated;
grant select, delete on comments to authenticated;
grant select, insert, delete on likes to authenticated;
grant insert on reports to authenticated;
grant usage on all sequences in schema public to authenticated;
grant select on posts_public, comments_public to authenticated;
grant execute on function add_comment(bigint, text), delete_me() to authenticated;
