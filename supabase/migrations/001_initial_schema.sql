-- ============================================================
-- CareStrings 初期スキーマ
-- File: supabase/migrations/001_initial_schema.sql
-- 設計書: docs/db_design.md (v2) 参照
-- 実行方法: Supabase Dashboard > SQL Editor に貼り付けて Run
-- ============================================================

-- ------------------------------------------------------------
-- 0. 共通: updated_at 自動更新トリガー関数
--    どの経路(Next.js / Go / 手動SQL)からUPDATEされても
--    updated_at が必ず現在時刻になる。アプリ側での書き忘れを構造的に防ぐ。
-- ------------------------------------------------------------
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- ------------------------------------------------------------
-- 1. units — 棟
--    文字直書きにせずテーブル化: 棟の追加・改名に強く、表記ゆれ('1棟'/'１棟')を防ぐ
-- ------------------------------------------------------------
create table units (
  id          smallint primary key,
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_units_updated before update on units
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 2. profiles — 職員 (auth.users と1対1)
--    認証情報(パスワード等)はSupabaseのauth.usersが管理。ここはアプリ用の属性のみ。
--    退職は削除でなく is_active=false: 投稿履歴の整合性を守る(「言った言わない」を防ぐアプリで履歴が消えるのは自己矛盾)
-- ------------------------------------------------------------
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  name          text not null,
  avatar_url    text,
  role          text not null check (role in ('caregiver','nurse','admin')),
  unit_id       smallint references units(id),
  display_mode  text not null default 'ja' check (display_mode in ('ja','furigana','en','th')),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger trg_profiles_updated before update on profiles
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 3. residents — 利用者(※全員架空データ。実在の個人情報は入れない)
-- ------------------------------------------------------------
create table residents (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  room_number text,
  unit_id     smallint references units(id),
  care_level  smallint check (care_level between 1 and 5),
  avatar_url  text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_residents_updated before update on residents
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 4. resident_notes — 恒常的な注意・連絡事項(ストック情報)
--    タイムライン(フロー)と分離: 「流れてはいけない情報」の置き場。
--    カテゴリはpostsと同じ値リスト(CHECKで統一。ズレると絞り込みが壊れる)
-- ------------------------------------------------------------
create table resident_notes (
  id           uuid primary key default gen_random_uuid(),
  resident_id  uuid not null references residents(id) on delete cascade,
  category     text not null check (category in ('meal','oral_care','excretion','sleep','health','family','other')),
  content      text not null,
  updated_by   uuid references profiles(id),  -- 最終更新者(責任の可視化)
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger trg_resident_notes_updated before update on resident_notes
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 5. posts — 申し送り投稿
--    resident_id NULL = 利用者に紐づかない施設連絡 / unit_id NULL = 全体宛
--    投稿後の編集は不可(RLSでUPDATEポリシーを作らない)。訂正は新規投稿かコメントで。
--    body_lang: 外国人職員が母語で投稿→日本語に翻訳、の双方向に対応
-- ------------------------------------------------------------
create table posts (
  id              uuid primary key default gen_random_uuid(),
  author_id       uuid not null references profiles(id),
  resident_id     uuid references residents(id),
  unit_id         smallint references units(id),
  category        text not null check (category in ('meal','oral_care','excretion','sleep','health','family','other')),
  body            text not null,
  body_lang       text not null default 'ja',
  is_important    boolean not null default false,  -- 重要=全員の確認必須。ホームのバナーに滞留
  family_approved boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create trigger trg_posts_updated before update on posts
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 6. post_images — 添付画像(クライアント側で圧縮してからアップロード)
-- ------------------------------------------------------------
create table post_images (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references posts(id) on delete cascade,
  storage_path text not null,
  thumb_path   text,
  sort_order   smallint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger trg_post_images_updated before update on post_images
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 7. post_translations — 翻訳キャッシュ
--    投稿時に1回だけ翻訳APIを実行して保存(表示時にAPIを叩かない=コスト固定+表示高速)。
--    ふりがなはkuroshiroでクライアント側生成のためテーブル無し。
-- ------------------------------------------------------------
create table post_translations (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references posts(id) on delete cascade,
  lang        text not null,
  body        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (post_id, lang)  -- 同一投稿×言語は1件
);
create trigger trg_post_translations_updated before update on post_translations
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 8. post_comments — コメント(質疑・補足)
--    フラット構造(ネストなし): 施設規模では十分。回答への気づきは通知で担保。
--    編集不可はpostsと同方針。
-- ------------------------------------------------------------
create table post_comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references posts(id) on delete cascade,
  author_id   uuid not null references profiles(id),
  body        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_post_comments_updated before update on post_comments
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 9. post_receipts — 既読・確認(投稿×職員で1行)
--    read_at=詳細を開いた時刻(自動) / confirmed_at=確認ボタン押下時刻(NULL=未確認)
--    行なし=未読 / read_atのみ=既読どまり / confirmed_atあり=確認済み
--    「読んだのに確認していない人」を可視化するのがこのアプリの核。
-- ------------------------------------------------------------
create table post_receipts (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references posts(id) on delete cascade,
  staff_id     uuid not null references profiles(id),
  read_at      timestamptz not null default now(),
  confirmed_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (post_id, staff_id)
);
create trigger trg_post_receipts_updated before update on post_receipts
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 10. notifications — 通知
--    生成ルール(アプリ側で実装): コメント投稿時、
--    通知先 = 投稿者 + その投稿の既存コメント者(重複除去) − 本人
--    → 質問者が回答に必ず気づける(質疑ループを閉じる)
-- ------------------------------------------------------------
create table notifications (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references profiles(id) on delete cascade,
  type         text not null check (type in ('comment_on_my_post','comment_on_joined_post')),
  post_id      uuid not null references posts(id) on delete cascade,
  comment_id   uuid references post_comments(id) on delete cascade,
  read_at      timestamptz,  -- NULL=未読(ベルのバッジ件数の対象)
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger trg_notifications_updated before update on notifications
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 11. vitals — バイタル記録
--    全項目NULL可 = 測った項目だけ記録できる(現場では毎回全項目は測らない)
-- ------------------------------------------------------------
create table vitals (
  id           uuid primary key default gen_random_uuid(),
  resident_id  uuid not null references residents(id) on delete cascade,
  recorded_by  uuid not null references profiles(id),
  measured_at  timestamptz not null,
  temperature  numeric(3,1),
  pulse        smallint,
  bp_systolic  smallint,
  bp_diastolic smallint,
  spo2         smallint,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger trg_vitals_updated before update on vitals
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 12. vital_thresholds — バイタル基準値(施設設定)
--    医学的判断をコードに埋め込まない: デフォルトは一般的な参考値、
--    現場(管理者)が変更できる設計でドメイン知識の限界を補う。
-- ------------------------------------------------------------
create table vital_thresholds (
  item        text primary key check (item in ('temperature','pulse','bp_systolic','bp_diastolic','spo2')),
  min_value   numeric,
  max_value   numeric,
  updated_by  uuid references profiles(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_vital_thresholds_updated before update on vital_thresholds
  for each row execute function set_updated_at();

-- ============================================================
-- インデックス(検索の索引。データが増えても表示速度を維持する)
-- ============================================================
create index idx_posts_created        on posts (created_at desc);                -- タイムライン新着順
create index idx_posts_unit_created   on posts (unit_id, created_at desc);       -- 棟タブ
create index idx_posts_resident       on posts (resident_id, created_at desc);   -- 利用者別タイムライン
create index idx_posts_important      on posts (created_at desc) where is_important; -- 重要バナー(部分インデックス)
create index idx_resident_notes_res   on resident_notes (resident_id);
create index idx_comments_post        on post_comments (post_id, created_at);
create index idx_receipts_staff       on post_receipts (staff_id, confirmed_at); -- 自分の未確認リスト
create index idx_receipts_post        on post_receipts (post_id);                -- 確認状況一覧
create index idx_notif_recipient      on notifications (recipient_id, read_at);  -- ベルのバッジ・通知一覧
create index idx_vitals_resident      on vitals (resident_id, measured_at desc); -- 推移グラフ

-- ============================================================
-- RLS (Row Level Security)
-- 方針: UIの出し分けだけでなくDB自体が門番になる2層防御。
--   - 参照系: ログイン職員なら可(施設内共有が前提のアプリのため)
--   - 登録系: residents/units/vital_thresholds は admin のみ
--   - posts/comments: 作成可・更新ポリシー無し = 編集不可
-- ============================================================

-- ヘルパー: 現在ログイン中のユーザーがadminか
create or replace function is_admin()
returns boolean as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and role = 'admin' and is_active
  );
$$ language sql security definer stable;

-- 全テーブルでRLSを有効化
alter table units             enable row level security;
alter table profiles          enable row level security;
alter table residents         enable row level security;
alter table resident_notes    enable row level security;
alter table posts             enable row level security;
alter table post_images       enable row level security;
alter table post_translations enable row level security;
alter table post_comments     enable row level security;
alter table post_receipts     enable row level security;
alter table notifications     enable row level security;
alter table vitals            enable row level security;
alter table vital_thresholds  enable row level security;

-- units: 参照=全職員 / 変更=admin
create policy units_select on units for select to authenticated using (true);
create policy units_admin  on units for all    to authenticated using (is_admin()) with check (is_admin());

-- profiles: 参照=全職員 / 追加=admin / 更新=本人(表示設定等) or admin
create policy profiles_select on profiles for select to authenticated using (true);
create policy profiles_insert on profiles for insert to authenticated with check (is_admin());
create policy profiles_update on profiles for update to authenticated
  using (id = auth.uid() or is_admin()) with check (id = auth.uid() or is_admin());

-- residents: 参照=全職員 / 変更=admin
create policy residents_select on residents for select to authenticated using (true);
create policy residents_admin  on residents for insert to authenticated with check (is_admin());
create policy residents_update on residents for update to authenticated using (is_admin()) with check (is_admin());

-- resident_notes: 参照・作成・更新=全職員(updated_byで責任を記録)
create policy rnotes_select on resident_notes for select to authenticated using (true);
create policy rnotes_insert on resident_notes for insert to authenticated with check (true);
create policy rnotes_update on resident_notes for update to authenticated using (true) with check (true);

-- posts: 参照=全職員 / 作成=本人名義のみ / 更新ポリシー無し=編集不可
create policy posts_select on posts for select to authenticated using (true);
create policy posts_insert on posts for insert to authenticated with check (author_id = auth.uid());

-- post_images: 参照=全職員 / 作成=ログイン職員
create policy pimg_select on post_images for select to authenticated using (true);
create policy pimg_insert on post_images for insert to authenticated with check (true);

-- post_translations: 参照=全職員 / 作成=サーバー処理(当面はログイン職員に許可)
create policy ptr_select on post_translations for select to authenticated using (true);
create policy ptr_insert on post_translations for insert to authenticated with check (true);

-- post_comments: 参照=全職員 / 作成=本人名義のみ / 編集不可
create policy pcom_select on post_comments for select to authenticated using (true);
create policy pcom_insert on post_comments for insert to authenticated with check (author_id = auth.uid());

-- post_receipts: 参照=全職員(確認状況の可視化のため) / 作成・更新=本人の行のみ
create policy prcpt_select on post_receipts for select to authenticated using (true);
create policy prcpt_insert on post_receipts for insert to authenticated with check (staff_id = auth.uid());
create policy prcpt_update on post_receipts for update to authenticated
  using (staff_id = auth.uid()) with check (staff_id = auth.uid());

-- notifications: 本人の行のみ参照・既読化。作成は当面ログイン職員(コメント処理から)
create policy notif_select on notifications for select to authenticated using (recipient_id = auth.uid());
create policy notif_insert on notifications for insert to authenticated with check (true);
create policy notif_update on notifications for update to authenticated
  using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());

-- vitals: 参照=全職員 / 作成=本人名義 / 更新=記録者本人
create policy vit_select on vitals for select to authenticated using (true);
create policy vit_insert on vitals for insert to authenticated with check (recorded_by = auth.uid());
create policy vit_update on vitals for update to authenticated
  using (recorded_by = auth.uid()) with check (recorded_by = auth.uid());

-- vital_thresholds: 参照=全職員 / 変更=admin
create policy vth_select on vital_thresholds for select to authenticated using (true);
create policy vth_update on vital_thresholds for update to authenticated using (is_admin()) with check (is_admin());
create policy vth_insert on vital_thresholds for insert to authenticated with check (is_admin());

-- ============================================================
-- 初期データ(シード)
-- ============================================================
insert into units (id, name) values (1, '1棟'), (2, '2棟');

-- バイタル基準値のデフォルト(一般的な参考値。管理画面で施設ごとに変更する前提)
insert into vital_thresholds (item, min_value, max_value) values
  ('temperature',  35.0,  37.5),
  ('pulse',        50,    100),
  ('bp_systolic',  90,    160),
  ('bp_diastolic', 50,    100),
  ('spo2',         90,    null);
