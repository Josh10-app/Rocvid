-- =====================================================================
-- ROCVID + ROCVID MUSIC STUDIO — skema PostgreSQL 15+ (serasi Supabase)
--
-- Isi:
--   1. Teras Rocvid   : pengguna, saluran, video, like, komen, playlist, laporan
--   2. Music Studio   : pengedar, kunci API, artis, release, lagu, kredit, video muzik
--   3. Peraturan      : saluran artis "(namaartis)-music", validasi syarat release,
--                       kawalan submit, publish dan takedown
--
-- Fail video/audio/gambar disimpan di storan objek (cth. Cloudflare R2);
-- pangkalan data hanya menyimpan kunci objek (*_key), bukan fail.
-- =====================================================================

begin;

create extension if not exists citext;
create extension if not exists unaccent;

-- ---------------------------------------------------------------------
-- ENUM
-- ---------------------------------------------------------------------
create type privacy_level      as enum ('public', 'unlisted', 'private');
create type video_status       as enum ('uploading', 'processing', 'ready', 'failed', 'removed');
create type video_type         as enum ('standard', 'official_music_video', 'lyric_video',
                                        'visualizer', 'live_performance', 'audio_track');
create type channel_type       as enum ('personal', 'artist_music');
create type distributor_status as enum ('pending', 'approved', 'suspended');
create type release_type       as enum ('single', 'ep', 'album', 'compilation');
create type release_status     as enum ('draft', 'submitted', 'in_review', 'approved',
                                        'rejected', 'live', 'taken_down');
create type explicit_flag      as enum ('not_explicit', 'explicit', 'clean');
create type credit_role        as enum ('primary_artist', 'featured_artist', 'composer', 'lyricist',
                                        'producer', 'arranger', 'mixer', 'mastering_engineer',
                                        'remixer', 'publisher');
create type report_reason      as enum ('spam', 'adult', 'violence', 'copyright', 'other');
create type report_status      as enum ('open', 'reviewing', 'actioned', 'dismissed');

-- ---------------------------------------------------------------------
-- UTILITI
-- ---------------------------------------------------------------------
create function set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- "Siti Nurhaliza" -> "siti-nurhaliza"; nama tanpa huruf/nombor -> "artist"
create function slugify(t text) returns text language sql stable as $$
  select coalesce(
    nullif(trim(both '-' from regexp_replace(lower(unaccent(t)), '[^a-z0-9]+', '-', 'g')), ''),
    'artist')
$$;

-- ---------------------------------------------------------------------
-- 1. PENGGUNA
-- ---------------------------------------------------------------------
create table users (
  id            uuid primary key default gen_random_uuid(),
  email         citext not null unique,
  password_hash text,                          -- kosongkan jika guna Supabase Auth / OAuth
  display_name  text not null check (char_length(display_name) between 1 and 60),
  avatar_key    text,
  is_admin      boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger users_updated before update on users for each row execute function set_updated_at();

-- ---------------------------------------------------------------------
-- 2. PENGEDAR MUZIK + API
-- ---------------------------------------------------------------------
create table distributors (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  legal_name          text not null,
  registration_no     text,
  country             text not null check (country ~ '^[A-Z]{2}$'),
  contact_email       citext not null,
  website             text,
  status              distributor_status not null default 'pending',
  agreement_accepted_at timestamptz,           -- perjanjian pengedar ditandatangani
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create trigger distributors_updated before update on distributors for each row execute function set_updated_at();

create table distributor_members (
  distributor_id uuid not null references distributors(id) on delete cascade,
  user_id        uuid not null references users(id) on delete cascade,
  role           text not null default 'editor' check (role in ('owner', 'admin', 'editor', 'viewer')),
  primary key (distributor_id, user_id)
);

-- Kunci API: simpan hash sahaja. Kunci penuh dipaparkan sekali semasa dicipta.
create table api_keys (
  id             uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references distributors(id) on delete cascade,
  name           text not null,
  key_prefix     text not null unique,         -- cth. rvm_live_ab12cd34 (untuk carian)
  key_hash       text not null,                -- SHA-256 bagi kunci penuh
  scopes         text[] not null default array['releases:read', 'releases:write', 'uploads:write'],
  created_by     uuid references users(id) on delete set null,
  last_used_at   timestamptz,
  expires_at     timestamptz,
  revoked_at     timestamptz,
  created_at     timestamptz not null default now()
);
create index api_keys_distributor_idx on api_keys (distributor_id);

create table idempotency_keys (
  distributor_id uuid not null references distributors(id) on delete cascade,
  key            text not null,
  request_hash   text not null,
  response_code  integer,
  response_body  jsonb,
  created_at     timestamptz not null default now(),
  primary key (distributor_id, key)
);

create table webhook_endpoints (
  id             uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references distributors(id) on delete cascade,
  url            text not null check (url ~ '^https://'),
  secret         text not null,                -- untuk tandatangan HMAC
  events         text[] not null default array['release.status_changed'],
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. ARTIS
-- ---------------------------------------------------------------------
create table artists (
  id                        uuid primary key default gen_random_uuid(),
  name                      text not null check (char_length(name) between 1 and 80),
  slug                      text not null unique,
  country                   text check (country is null or country ~ '^[A-Z]{2}$'),
  bio                       text,
  image_key                 text,
  isni                      text check (isni is null or isni ~ '^[0-9]{15}[0-9X]$'),
  managed_by_distributor_id uuid references distributors(id) on delete set null,
  claimed_by_user_id        uuid references users(id) on delete set null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);
create trigger artists_updated before update on artists for each row execute function set_updated_at();

-- ---------------------------------------------------------------------
-- 4. SALURAN
--    personal     : saluran biasa milik pengguna
--    artist_music : saluran rasmi artis, WAJIB bernama "(namaartis)-music"
-- ---------------------------------------------------------------------
create table channels (
  id               uuid primary key default gen_random_uuid(),
  type             channel_type not null default 'personal',
  owner_user_id    uuid references users(id) on delete cascade,
  artist_id        uuid unique references artists(id) on delete cascade,
  handle           citext not null unique check (handle ~ '^[a-z0-9][a-z0-9._-]{2,59}$'),
  name             text not null check (char_length(name) between 1 and 100),
  description      text,
  avatar_key       text,
  banner_key       text,
  subscriber_count bigint not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint channel_owner_by_type check (
    (type = 'personal'     and owner_user_id is not null and artist_id is null) or
    (type = 'artist_music' and artist_id is not null)
  ),
  -- Akhiran "-music" dikhaskan untuk saluran artis supaya tiada penyamaran
  constraint channel_music_suffix check (
    (type = 'artist_music' and name ~ '-music$' and handle ~ '-music$') or
    (type = 'personal'     and name !~* '-music$' and handle !~ '-music$')
  )
);
create trigger channels_updated before update on channels for each row execute function set_updated_at();

-- Artis baru -> slug unik + saluran "(namaartis)-music" dicipta automatik
create function trg_artist_slug() returns trigger language plpgsql as $$
declare
  base text := regexp_replace(left(slugify(new.name), 40), '-+$', '');
  cand text := base;
  i    int  := 1;
begin
  while exists (select 1 from artists a where a.slug = cand) loop
    i := i + 1;
    cand := base || '-' || i;
  end loop;
  new.slug := cand;
  return new;
end $$;
create trigger artists_slug before insert on artists for each row execute function trg_artist_slug();

create function trg_artist_channel() returns trigger language plpgsql as $$
begin
  insert into channels (type, artist_id, handle, name)
  values ('artist_music', new.id, new.slug || '-music', new.name || '-music');
  return new;
end $$;
create trigger artists_channel after insert on artists for each row execute function trg_artist_channel();

-- Tukar nama artis -> nama saluran mengikut
create function trg_artist_rename() returns trigger language plpgsql as $$
begin
  update channels set name = new.name || '-music' where artist_id = new.id;
  return new;
end $$;
create trigger artists_rename after update of name on artists
  for each row when (old.name is distinct from new.name) execute function trg_artist_rename();

-- Nama/handle/jenis saluran artis tidak boleh diubah secara manual
create function trg_channel_lock() returns trigger language plpgsql as $$
begin
  if new.type is distinct from old.type then
    raise exception 'Jenis saluran tidak boleh ditukar' using errcode = 'check_violation';
  end if;
  if old.type = 'artist_music' and pg_trigger_depth() < 2
     and (new.name is distinct from old.name or new.handle is distinct from old.handle) then
    raise exception 'Nama saluran artis ditetapkan oleh nama artis ((namaartis)-music)'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger channels_lock before update on channels for each row execute function trg_channel_lock();

create table subscriptions (
  user_id    uuid not null references users(id) on delete cascade,
  channel_id uuid not null references channels(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, channel_id)
);
create index subscriptions_channel_idx on subscriptions (channel_id);

create function trg_subscriber_count() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update channels set subscriber_count = subscriber_count + 1 where id = new.channel_id;
  else
    update channels set subscriber_count = greatest(subscriber_count - 1, 0) where id = old.channel_id;
  end if;
  return null;
end $$;
create trigger subscriptions_count after insert or delete on subscriptions
  for each row execute function trg_subscriber_count();

-- ---------------------------------------------------------------------
-- 5. VIDEO
-- ---------------------------------------------------------------------
create table videos (
  id             uuid primary key default gen_random_uuid(),
  channel_id     uuid not null references channels(id) on delete cascade,
  uploaded_by    uuid references users(id) on delete set null,
  distributor_id uuid references distributors(id) on delete set null,   -- jika dihantar melalui API/Studio
  type           video_type not null default 'standard',
  title          text not null check (char_length(title) between 1 and 200),
  description    text not null default '',
  category       text,
  tags           text[] not null default '{}',
  privacy        privacy_level not null default 'public',
  status         video_status not null default 'uploading',
  source_key     text,                         -- fail asal di storan objek
  hls_key        text,                         -- manifest HLS selepas transcoding
  thumbnail_key  text,
  duration_ms    integer check (duration_ms is null or duration_ms > 0),
  width          integer,
  height         integer,
  isrc           text check (isrc is null or isrc ~ '^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$'),
  view_count     bigint not null default 0,
  like_count     bigint not null default 0,
  dislike_count  bigint not null default 0,
  comment_count  bigint not null default 0,
  search         tsvector generated always as
                   (to_tsvector('simple', title || ' ' || description)) stored,
  published_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create trigger videos_updated before update on videos for each row execute function set_updated_at();

create index videos_channel_idx  on videos (channel_id, published_at desc);
create index videos_feed_idx     on videos (published_at desc) where privacy = 'public' and status = 'ready';
create index videos_trending_idx on videos (view_count desc)   where privacy = 'public' and status = 'ready';
create index videos_search_idx   on videos using gin (search);
create index videos_tags_idx     on videos using gin (tags);

create table video_likes (
  video_id   uuid not null references videos(id) on delete cascade,
  user_id    uuid not null references users(id) on delete cascade,
  value      smallint not null check (value in (1, -1)),
  created_at timestamptz not null default now(),
  primary key (video_id, user_id)
);

create function trg_like_counts() returns trigger language plpgsql as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    update videos
       set like_count    = like_count    - (old.value =  1)::int,
           dislike_count = dislike_count - (old.value = -1)::int
     where id = old.video_id;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    update videos
       set like_count    = like_count    + (new.value =  1)::int,
           dislike_count = dislike_count + (new.value = -1)::int
     where id = new.video_id;
  end if;
  return null;
end $$;
create trigger video_likes_count after insert or update of value or delete on video_likes
  for each row execute function trg_like_counts();

create table comments (
  id         uuid primary key default gen_random_uuid(),
  video_id   uuid not null references videos(id) on delete cascade,
  user_id    uuid not null references users(id) on delete cascade,
  parent_id  uuid references comments(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index comments_video_idx on comments (video_id, created_at desc);

create function trg_comment_count() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update videos set comment_count = comment_count + 1 where id = new.video_id;
  else
    update videos set comment_count = greatest(comment_count - 1, 0) where id = old.video_id;
  end if;
  return null;
end $$;
create trigger comments_count after insert or delete on comments
  for each row execute function trg_comment_count();

create table playlists (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references users(id) on delete cascade,
  kind       text not null default 'custom' check (kind in ('custom', 'watch_later')),
  title      text not null check (char_length(title) between 1 and 100),
  privacy    privacy_level not null default 'private',
  created_at timestamptz not null default now()
);
create unique index playlists_one_watch_later on playlists (owner_id) where kind = 'watch_later';

create table playlist_items (
  playlist_id uuid not null references playlists(id) on delete cascade,
  video_id    uuid not null references videos(id) on delete cascade,
  position    integer not null default 0,
  added_at    timestamptz not null default now(),
  primary key (playlist_id, video_id)
);

create table watch_history (
  user_id          uuid not null references users(id) on delete cascade,
  video_id         uuid not null references videos(id) on delete cascade,
  last_position_ms integer not null default 0,
  watched_at       timestamptz not null default now(),
  primary key (user_id, video_id)
);
create index watch_history_recent_idx on watch_history (user_id, watched_at desc);

-- Log tontonan mentah untuk analitik (boleh dipartisi mengikut bulan kemudian)
create table video_view_events (
  id         bigint generated always as identity primary key,
  video_id   uuid not null references videos(id) on delete cascade,
  user_id    uuid references users(id) on delete set null,
  watched_ms integer not null default 0,
  created_at timestamptz not null default now()
);
create index video_view_events_idx on video_view_events (video_id, created_at);

create table reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid references users(id) on delete set null,
  video_id    uuid references videos(id) on delete cascade,
  comment_id  uuid references comments(id) on delete cascade,
  reason      report_reason not null,
  details     text,
  status      report_status not null default 'open',
  resolved_by uuid references users(id) on delete set null,
  resolved_at timestamptz,
  created_at  timestamptz not null default now(),
  check ((video_id is not null)::int + (comment_id is not null)::int = 1)
);
create index reports_open_idx on reports (created_at) where status = 'open';

-- ---------------------------------------------------------------------
-- 6. RELEASE MUZIK
-- ---------------------------------------------------------------------
create table releases (
  id                    uuid primary key default gen_random_uuid(),
  distributor_id        uuid not null references distributors(id),
  external_ref          text,                  -- ID dalaman pengedar
  upc                   text unique check (upc is null or upc ~ '^[0-9]{12,13}$'),
  title                 text not null check (char_length(title) between 1 and 200),
  version_title         text,                  -- cth. "Acoustic", "Remastered 2026"
  type                  release_type not null default 'single',
  label_name            text,
  genre                 text,
  subgenre              text,
  language              text check (language is null or language ~ '^[a-z]{2,3}$'),   -- ISO 639
  original_release_date date,                  -- tarikh keluaran asal di mana-mana platform
  release_date          date,                  -- tarikh keluaran di Rocvid
  p_line                text,                  -- hak rakaman, cth. "2026 Nama Label"
  c_line                text,                  -- hak cipta,   cth. "2026 Nama Pemilik"
  cover_key             text,
  cover_width           integer,
  cover_height          integer,
  territories           text[] not null default array['WW'] check (cardinality(territories) >= 1),
  explicit              explicit_flag not null default 'not_explicit',
  status                release_status not null default 'draft',
  rejection_reason      text,
  submitted_at          timestamptz,
  approved_at           timestamptz,
  live_at               timestamptz,
  taken_down_at         timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (distributor_id, external_ref),
  check (release_date is null or original_release_date is null or release_date >= original_release_date)
);
create trigger releases_updated before update on releases for each row execute function set_updated_at();
create index releases_distributor_idx on releases (distributor_id, status);

-- Hanya pengedar yang diluluskan boleh mencipta release
create function trg_release_distributor_guard() returns trigger language plpgsql as $$
begin
  if not exists (select 1 from distributors d where d.id = new.distributor_id and d.status = 'approved') then
    raise exception 'Pengedar belum diluluskan atau digantung' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;
create trigger releases_distributor_guard before insert on releases
  for each row execute function trg_release_distributor_guard();

create table release_artists (
  release_id uuid not null references releases(id) on delete cascade,
  artist_id  uuid not null references artists(id),
  role       credit_role not null check (role in ('primary_artist', 'featured_artist')),
  position   smallint not null default 1,
  primary key (release_id, artist_id, role)
);
create index release_artists_artist_idx on release_artists (artist_id);

create table tracks (
  id              uuid primary key default gen_random_uuid(),
  release_id      uuid not null references releases(id) on delete cascade,
  disc_number     smallint not null default 1 check (disc_number >= 1),
  track_number    smallint not null check (track_number >= 1),
  title           text not null check (char_length(title) between 1 and 200),
  version_title   text,
  isrc            text unique check (isrc is null or isrc ~ '^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$'),
  duration_ms     integer check (duration_ms is null or duration_ms > 0),
  audio_key       text,
  audio_format    text check (audio_format is null or audio_format in ('wav', 'flac')),
  sample_rate_hz  integer,
  bit_depth       smallint,
  language        text check (language is null or language ~ '^[a-z]{2,3}$'),
  explicit        explicit_flag not null default 'not_explicit',
  lyrics          text,
  lyrics_language text check (lyrics_language is null or lyrics_language ~ '^[a-z]{2,3}$'),
  preview_start_ms integer check (preview_start_ms is null or preview_start_ms >= 0),
  genre           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (release_id, disc_number, track_number)
);
create trigger tracks_updated before update on tracks for each row execute function set_updated_at();

-- Kredit: artis utama/jemputan, pencipta lagu, penerbit, penerbit rakaman, dsb.
create table track_credits (
  id        uuid primary key default gen_random_uuid(),
  track_id  uuid not null references tracks(id) on delete cascade,
  artist_id uuid references artists(id),
  name      text not null,                      -- nama penuh seperti pada kredit
  role      credit_role not null,
  ipi       text check (ipi is null or ipi ~ '^[0-9]{9,11}$'),
  position  smallint not null default 1,
  check (role not in ('primary_artist', 'featured_artist') or artist_id is not null)
);
create unique index track_credits_unique on track_credits (track_id, lower(name), role);

-- Audio + video muzik untuk lagu yang sama (digabungkan dalam Studio)
create table track_videos (
  track_id uuid not null references tracks(id) on delete cascade,
  video_id uuid not null references videos(id) on delete cascade,
  relation video_type not null check (relation in
    ('audio_track', 'official_music_video', 'lyric_video', 'visualizer', 'live_performance')),
  primary key (track_id, video_id)
);
create index track_videos_video_idx on track_videos (video_id);

-- Video mesti dalam saluran (namaartis)-music bagi artis utama release,
-- dan jenis video mesti sepadan dengan hubungan yang dipilih.
create function trg_track_video_guard() returns trigger language plpgsql as $$
begin
  if not exists (
    select 1
      from tracks tr
      join release_artists ra on ra.release_id = tr.release_id and ra.role = 'primary_artist'
      join channels c         on c.artist_id = ra.artist_id
      join videos v           on v.channel_id = c.id
     where tr.id = new.track_id and v.id = new.video_id and v.type = new.relation
  ) then
    raise exception 'Video mesti berada dalam saluran (namaartis)-music bagi artis utama dan jenisnya mesti sepadan'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger track_videos_guard before insert or update on track_videos
  for each row execute function trg_track_video_guard();

-- Sejarah status release (juga sumber untuk webhook pengedar)
create table release_events (
  id         bigint generated always as identity primary key,
  release_id uuid not null references releases(id) on delete cascade,
  type       text not null,
  from_status release_status,
  to_status   release_status,
  payload    jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index release_events_idx on release_events (release_id, created_at);

create function trg_release_events() returns trigger language plpgsql as $$
begin
  insert into release_events (release_id, type, from_status, to_status, payload)
  values (new.id, 'release.status_changed', old.status, new.status,
          jsonb_build_object('rejection_reason', new.rejection_reason));
  return null;
end $$;
create trigger releases_events after update of status on releases
  for each row when (old.status is distinct from new.status) execute function trg_release_events();

-- ---------------------------------------------------------------------
-- 7. SYARAT RELEASE: validasi sebelum submit
--    Mengembalikan senarai ralat (kosong = sedia dihantar).
-- ---------------------------------------------------------------------
create function release_validation(p_release uuid)
returns table (err_code text, err_track_id uuid, err_message text)
language plpgsql stable as $$
declare
  r        releases%rowtype;
  n_tracks integer;
  t        record;
begin
  select * into r from releases where id = p_release;
  if not found then
    return query select 'RELEASE_NOT_FOUND'::text, null::uuid, 'Release tidak dijumpai'::text;
    return;
  end if;

  -- Maklumat release
  return query select 'UPC_REQUIRED'::text, null::uuid, 'UPC/EAN (12-13 digit) diperlukan'::text
    where r.upc is null;
  return query select 'LABEL_REQUIRED'::text, null::uuid, 'Nama label diperlukan'::text
    where coalesce(btrim(r.label_name), '') = '';
  return query select 'GENRE_REQUIRED'::text, null::uuid, 'Genre diperlukan'::text
    where coalesce(btrim(r.genre), '') = '';
  return query select 'LANGUAGE_REQUIRED'::text, null::uuid, 'Bahasa (kod ISO 639) diperlukan'::text
    where r.language is null;
  return query select 'RELEASE_DATE_REQUIRED'::text, null::uuid,
                      'Tarikh keluaran asal dan tarikh keluaran di Rocvid diperlukan'::text
    where r.original_release_date is null or r.release_date is null;
  return query select 'P_LINE_INVALID'::text, null::uuid,
                      'P-line mesti berformat "TAHUN Pemilik", cth. 2026 Nama Label'::text
    where r.p_line is null or r.p_line !~ '^(19|20)[0-9]{2} .+';
  return query select 'C_LINE_INVALID'::text, null::uuid,
                      'C-line mesti berformat "TAHUN Pemilik", cth. 2026 Nama Pemilik'::text
    where r.c_line is null or r.c_line !~ '^(19|20)[0-9]{2} .+';

  -- Gambar muka depan: segi empat sama, sekurang-kurangnya 3000 x 3000 px
  return query select 'COVER_REQUIRED'::text, null::uuid, 'Gambar muka depan diperlukan'::text
    where r.cover_key is null;
  return query select 'COVER_NOT_SQUARE'::text, null::uuid, 'Gambar muka depan mesti segi empat sama'::text
    where r.cover_key is not null and r.cover_width is distinct from r.cover_height;
  return query select 'COVER_TOO_SMALL'::text, null::uuid,
                      'Gambar muka depan mesti sekurang-kurangnya 3000 x 3000 piksel'::text
    where r.cover_key is not null and coalesce(r.cover_width, 0) < 3000;

  -- Artis utama
  return query select 'PRIMARY_ARTIST_REQUIRED'::text, null::uuid, 'Sekurang-kurangnya satu artis utama diperlukan'::text
    where not exists (select 1 from release_artists ra
                       where ra.release_id = p_release and ra.role = 'primary_artist');

  -- Bilangan lagu mengikut jenis release
  select count(*) into n_tracks from tracks tr where tr.release_id = p_release;
  if n_tracks = 0 then
    return query select 'NO_TRACKS'::text, null::uuid, 'Release mesti ada sekurang-kurangnya satu lagu'::text;
  elsif (r.type = 'single' and n_tracks > 3)
     or (r.type = 'ep'     and n_tracks not between 4 and 6)
     or (r.type = 'album'  and n_tracks < 7) then
    return query select 'TRACK_COUNT_MISMATCH'::text, null::uuid,
                        format('Jenis %s tidak sesuai dengan %s lagu (single 1-3, EP 4-6, album 7+)', r.type, n_tracks);
  end if;

  -- Nombor lagu berturutan bagi setiap cakera
  return query
    select 'TRACK_NUMBERING_GAP'::text, null::uuid,
           format('Cakera %s: nombor lagu mesti berturutan bermula dari 1', d.disc_number)
      from (select tr.disc_number, count(*) as c, max(tr.track_number) as mx, min(tr.track_number) as mn
              from tracks tr where tr.release_id = p_release group by tr.disc_number) d
     where d.mx <> d.c or d.mn <> 1;

  -- Setiap lagu
  for t in select * from tracks tr where tr.release_id = p_release order by tr.disc_number, tr.track_number loop
    if t.isrc is null then
      return query select 'TRACK_ISRC_REQUIRED'::text, t.id, format('Lagu %s: ISRC diperlukan', t.track_number);
    end if;
    if t.audio_key is null then
      return query select 'TRACK_AUDIO_REQUIRED'::text, t.id, format('Lagu %s: fail audio (WAV/FLAC) diperlukan', t.track_number);
    elsif coalesce(t.sample_rate_hz, 0) < 44100 or coalesce(t.bit_depth, 0) < 16 then
      return query select 'TRACK_AUDIO_QUALITY'::text, t.id,
                          format('Lagu %s: audio mesti sekurang-kurangnya 16-bit / 44.1 kHz', t.track_number);
    end if;
    if t.duration_ms is null then
      return query select 'TRACK_DURATION_REQUIRED'::text, t.id, format('Lagu %s: tempoh diperlukan', t.track_number);
    end if;
    if not exists (select 1 from track_credits c where c.track_id = t.id and c.role = 'primary_artist') then
      return query select 'TRACK_PRIMARY_ARTIST_REQUIRED'::text, t.id,
                          format('Lagu %s: artis utama diperlukan', t.track_number);
    end if;
    if not exists (select 1 from track_credits c where c.track_id = t.id and c.role in ('composer', 'lyricist')) then
      return query select 'TRACK_SONGWRITER_REQUIRED'::text, t.id,
                          format('Lagu %s: pencipta lagu (composer/lyricist) diperlukan', t.track_number);
    end if;
  end loop;

  -- Video yang dipautkan mesti siap diproses
  return query
    select 'VIDEO_NOT_READY'::text, tv.track_id, format('Video "%s" belum siap diproses', v.title)
      from track_videos tv
      join tracks tr on tr.id = tv.track_id
      join videos v  on v.id = tv.video_id
     where tr.release_id = p_release and tv.relation <> 'audio_track' and v.status <> 'ready';
end $$;

-- Status "submitted" hanya dibenarkan jika semua syarat dipenuhi
create function trg_release_submit_guard() returns trigger language plpgsql as $$
begin
  if exists (select 1 from release_validation(new.id)) then
    raise exception 'Release belum memenuhi syarat. Semak: select * from release_validation(''%'')', new.id
      using errcode = 'check_violation';
  end if;
  return null;
end $$;
create constraint trigger releases_submit_guard after update of status on releases
  deferrable initially immediate
  for each row when (new.status = 'submitted' and old.status is distinct from new.status)
  execute function trg_release_submit_guard();

create function submit_release(p_release uuid) returns void language plpgsql as $$
begin
  update releases set status = 'submitted', submitted_at = now(), rejection_reason = null
   where id = p_release and status in ('draft', 'rejected');
  if not found then
    raise exception 'Release tidak wujud atau tidak boleh dihantar dalam statusnya sekarang';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 8. KELULUSAN, PUBLISH, TAKEDOWN (dipanggil oleh pasukan semakan Rocvid)
-- ---------------------------------------------------------------------
create function review_release(p_release uuid, p_approve boolean, p_reason text default null)
returns void language plpgsql as $$
begin
  if not p_approve and coalesce(btrim(p_reason), '') = '' then
    raise exception 'Sebab penolakan diperlukan';
  end if;
  update releases
     set status = case when p_approve then 'approved'::release_status else 'rejected'::release_status end,
         approved_at = case when p_approve then now() end,
         rejection_reason = case when p_approve then null else p_reason end
   where id = p_release and status in ('submitted', 'in_review');
  if not found then
    raise exception 'Release mesti berstatus submitted atau in_review';
  end if;
end $$;

-- Cipta item audio dalam saluran (namaartis)-music bagi setiap lagu, kemudian set status live
create function publish_release(p_release uuid) returns integer language plpgsql as $$
declare
  r         releases%rowtype;
  v_channel uuid;
  v_video   uuid;
  n         integer := 0;
  t         record;
begin
  select * into r from releases where id = p_release for update;
  if not found or r.status <> 'approved' then
    raise exception 'Release mesti berstatus approved sebelum diterbitkan';
  end if;

  select c.id into v_channel
    from release_artists ra
    join channels c on c.artist_id = ra.artist_id
   where ra.release_id = p_release and ra.role = 'primary_artist'
   order by ra.position
   limit 1;
  if v_channel is null then
    raise exception 'Artis utama tiada saluran';
  end if;

  for t in select * from tracks tr where tr.release_id = p_release order by tr.disc_number, tr.track_number loop
    insert into videos (channel_id, distributor_id, type, title, description, category, privacy,
                        status, source_key, thumbnail_key, duration_ms, isrc, published_at)
    values (v_channel, r.distributor_id, 'audio_track',
            t.title || coalesce(' (' || t.version_title || ')', ''),
            format(E'Daripada keluaran "%s"\n℗ %s\n© %s', r.title, r.p_line, r.c_line),
            'Muzik', 'public', 'processing', t.audio_key, r.cover_key, t.duration_ms, t.isrc,
            r.release_date::timestamptz)
    returning id into v_video;

    insert into track_videos (track_id, video_id, relation) values (t.id, v_video, 'audio_track');
    n := n + 1;
  end loop;

  update releases set status = 'live', live_at = now() where id = p_release;
  return n;
end $$;

-- Tarik balik release: semua item audio/video yang dipautkan dibuang daripada tontonan
create function takedown_release(p_release uuid, p_reason text default null) returns void language plpgsql as $$
begin
  update releases set status = 'taken_down', taken_down_at = now(), rejection_reason = p_reason
   where id = p_release and status in ('approved', 'live');
  if not found then
    raise exception 'Hanya release approved atau live boleh ditarik balik';
  end if;
  update videos set status = 'removed'
   where id in (select tv.video_id from track_videos tv
                  join tracks tr on tr.id = tv.track_id
                 where tr.release_id = p_release);
end $$;

-- ---------------------------------------------------------------------
-- 9. VIEW
-- ---------------------------------------------------------------------
-- Video awam yang sudah siap dan sudah tiba tarikh terbitnya
create view public_videos as
select v.*, c.name as channel_name, c.handle as channel_handle, c.type as channel_type
  from videos v
  join channels c on c.id = v.channel_id
 where v.privacy = 'public' and v.status = 'ready'
   and (v.published_at is null or v.published_at <= now());

-- Paparan Studio: satu baris setiap lagu bersama semua audio/video yang dipautkan
create view studio_catalog as
select r.distributor_id, r.id as release_id, r.title as release_title, r.type as release_type,
       r.status as release_status, r.release_date,
       t.id as track_id, t.disc_number, t.track_number, t.title as track_title, t.isrc,
       coalesce((select jsonb_agg(jsonb_build_object(
                   'video_id', v.id, 'relation', tv.relation, 'status', v.status, 'title', v.title)
                   order by tv.relation)
                   from track_videos tv join videos v on v.id = tv.video_id
                  where tv.track_id = t.id), '[]'::jsonb) as media
  from releases r
  join tracks t on t.release_id = r.id;

-- ---------------------------------------------------------------------
-- 10. KESELAMATAN
--     RLS dihidupkan pada semua jadual tanpa polisi: capaian terus melalui
--     PostgREST/anon key ditolak. Backend API menyambung sebagai pemilik
--     jadual (atau service role) dan menguatkuasakan kebenaran sendiri.
--     Tambah polisi per-jadual jika mahu klien membaca terus dari Supabase.
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', r.tablename);
  end loop;
end $$;

commit;
