-- ============================================================
-- TIMETABLE APP — Supabase Schema
-- รัน SQL นี้ใน Supabase SQL Editor ทีละ section
-- ============================================================

-- ============================================================
-- SECTION 1: Extensions
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- SECTION 2: Custom Types (Enums)
-- ============================================================
DO $$ BEGIN
  CREATE TYPE user_role       AS ENUM ('user', 'admin');
  CREATE TYPE user_status     AS ENUM ('active', 'banned');
  CREATE TYPE sub_tier        AS ENUM ('free', 'vip_monthly', 'vip_yearly', 'enterprise');
  CREATE TYPE ticket_category AS ENUM ('bug', 'feature', 'question', 'other');
  CREATE TYPE hw_type         AS ENUM ('hw', 'exam', 'project', 'other');
  CREATE TYPE hw_priority     AS ENUM ('low', 'normal', 'high');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- SECTION 3: PROFILES table (extends auth.users)
-- ============================================================
CREATE TABLE IF NOT EXISTS profiles (
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username            TEXT UNIQUE NOT NULL,
  name                TEXT NOT NULL DEFAULT '',
  school              TEXT NOT NULL DEFAULT '',
  grade               TEXT NOT NULL DEFAULT '',
  addr                TEXT DEFAULT '',
  sub_district        TEXT DEFAULT '',
  district            TEXT DEFAULT '',
  province            TEXT DEFAULT '',
  avatar_url          TEXT DEFAULT NULL,
  role                user_role NOT NULL DEFAULT 'user',
  status              user_status NOT NULL DEFAULT 'active',
  ban_reason          TEXT DEFAULT NULL,
  -- Subscription
  subscription_tier   sub_tier NOT NULL DEFAULT 'free',
  subscription_expires_at TIMESTAMPTZ DEFAULT NULL,
  quota_override      INT NOT NULL DEFAULT 3,
  -- Stripe
  stripe_customer_id  TEXT DEFAULT NULL,
  -- Metadata
  last_seen_at        TIMESTAMPTZ DEFAULT NOW(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 4: TIMETABLES table
-- ============================================================
CREATE TABLE IF NOT EXISTS timetables (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name        TEXT NOT NULL DEFAULT 'ตารางเรียน',
  advisor_name TEXT DEFAULT '',
  advisor_phone TEXT DEFAULT '',
  theme_id    TEXT DEFAULT 'cat-purple',
  is_public   BOOLEAN NOT NULL DEFAULT FALSE,
  share_token TEXT UNIQUE DEFAULT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 5: PERIOD_SETTINGS table
-- ============================================================
CREATE TABLE IF NOT EXISTS period_settings (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  periods     JSONB NOT NULL DEFAULT '[]',  -- [{id,label,s,e,b}]
  days        JSONB NOT NULL DEFAULT '[]',  -- ["วันจันทร์",...]
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id)
);

-- ============================================================
-- SECTION 6: SUBJECTS table
-- ============================================================
CREATE TABLE IF NOT EXISTS subjects (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  code        TEXT NOT NULL DEFAULT '',
  name        TEXT NOT NULL DEFAULT '',
  room        TEXT DEFAULT '',
  teacher     TEXT DEFAULT '',
  icon        TEXT DEFAULT '📚',
  color_key   TEXT DEFAULT 'lav',
  sort_order  INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 7: TIMETABLE_SLOTS table
-- ============================================================
CREATE TABLE IF NOT EXISTS timetable_slots (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  timetable_id  UUID NOT NULL REFERENCES timetables(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  day_index     INT NOT NULL,     -- 0=Mon, 1=Tue, ...
  period_id     TEXT NOT NULL,    -- matches period settings id
  subject_id    UUID REFERENCES subjects(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(timetable_id, day_index, period_id)
);

-- ============================================================
-- SECTION 8: CALENDAR_NOTES table
-- ============================================================
CREATE TABLE IF NOT EXISTS calendar_notes (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title       TEXT NOT NULL DEFAULT '',
  body        TEXT DEFAULT '',
  note_date   DATE DEFAULT NULL,
  color_key   TEXT DEFAULT 'yellow',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 9: HOMEWORK table
-- ============================================================
CREATE TABLE IF NOT EXISTS homework (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title       TEXT NOT NULL DEFAULT '',
  subject_name TEXT DEFAULT '',
  type        hw_type NOT NULL DEFAULT 'hw',
  priority    hw_priority NOT NULL DEFAULT 'normal',
  due_date    DATE DEFAULT NULL,
  detail      TEXT DEFAULT '',
  is_done     BOOLEAN NOT NULL DEFAULT FALSE,
  done_at     TIMESTAMPTZ DEFAULT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 10: SUPPORT_TICKETS table
-- ============================================================
CREATE TABLE IF NOT EXISTS support_tickets (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  subject     TEXT NOT NULL DEFAULT '',
  category    ticket_category NOT NULL DEFAULT 'other',
  is_resolved BOOLEAN NOT NULL DEFAULT FALSE,
  resolved_at TIMESTAMPTZ DEFAULT NULL,
  resolved_by UUID REFERENCES profiles(id) DEFAULT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 11: TICKET_MESSAGES table
-- ============================================================
CREATE TABLE IF NOT EXISTS ticket_messages (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ticket_id   UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  sender_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  message     TEXT NOT NULL DEFAULT '',
  is_read     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 12: ANNOUNCEMENTS table
-- ============================================================
CREATE TABLE IF NOT EXISTS announcements (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_by  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  message     TEXT NOT NULL DEFAULT '',
  color       TEXT DEFAULT 'gradient',
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  expires_at  TIMESTAMPTZ DEFAULT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 13: ACTIVITY_LOG table
-- ============================================================
CREATE TABLE IF NOT EXISTS activity_log (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID REFERENCES profiles(id) ON DELETE SET NULL,
  action      TEXT NOT NULL DEFAULT '',
  metadata    JSONB DEFAULT '{}',
  ip_address  INET DEFAULT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 14: SUBSCRIPTION_EVENTS table (for billing audit)
-- ============================================================
CREATE TABLE IF NOT EXISTS subscription_events (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_type      TEXT NOT NULL,  -- 'upgraded','downgraded','cancelled','renewed'
  tier_from       sub_tier DEFAULT NULL,
  tier_to         sub_tier DEFAULT NULL,
  stripe_event_id TEXT DEFAULT NULL,
  amount_thb      INT DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SECTION 15: Indexes (Performance)
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_timetables_user     ON timetables(user_id);
CREATE INDEX IF NOT EXISTS idx_slots_timetable     ON timetable_slots(timetable_id);
CREATE INDEX IF NOT EXISTS idx_slots_user          ON timetable_slots(user_id);
CREATE INDEX IF NOT EXISTS idx_subjects_user       ON subjects(user_id);
CREATE INDEX IF NOT EXISTS idx_period_settings_user ON period_settings(user_id);
CREATE INDEX IF NOT EXISTS idx_notes_user_date     ON calendar_notes(user_id, note_date);
CREATE INDEX IF NOT EXISTS idx_homework_user_due   ON homework(user_id, due_date);
CREATE INDEX IF NOT EXISTS idx_tickets_user        ON support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_ticket     ON ticket_messages(ticket_id);
CREATE INDEX IF NOT EXISTS idx_activity_user       ON activity_log(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_created    ON activity_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_announcements_active ON announcements(is_active) WHERE is_active = TRUE;

-- ============================================================
-- SECTION 16: Updated_at auto-trigger
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DO $$ DECLARE t TEXT;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'profiles','timetables','period_settings','subjects',
    'calendar_notes','homework','support_tickets'
  ]) LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_updated_at ON %I', t);
    EXECUTE format('CREATE TRIGGER trg_updated_at BEFORE UPDATE ON %I
      FOR EACH ROW EXECUTE FUNCTION update_updated_at()', t);
  END LOOP;
END $$;

-- ============================================================
-- SECTION 17: Auto-create profile on signup
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  uname TEXT;
  admin_count INT;
BEGIN
  -- Generate unique username from email
  uname := LOWER(SPLIT_PART(NEW.email, '@', 1));
  -- Append random suffix if username taken
  WHILE EXISTS (SELECT 1 FROM profiles WHERE username = uname) LOOP
    uname := uname || floor(random()*900+100)::text;
  END LOOP;
  -- Count existing admins (first user = admin)
  SELECT COUNT(*) INTO admin_count FROM profiles WHERE role = 'admin';
  INSERT INTO profiles (id, username, name, role)
  VALUES (
    NEW.id,
    uname,
    COALESCE(NEW.raw_user_meta_data->>'name', uname),
    CASE WHEN admin_count = 0 THEN 'admin' ELSE 'user' END
  );
  -- Default period settings
  INSERT INTO period_settings (user_id, periods, days) VALUES (
    NEW.id,
    '[{"id":"p1","label":"คาบที่ 1","s":"08:00","e":"09:00","b":false},
      {"id":"p2","label":"คาบที่ 2","s":"09:00","e":"10:00","b":false},
      {"id":"p3","label":"คาบที่ 3","s":"10:00","e":"11:00","b":false},
      {"id":"p4","label":"คาบที่ 4","s":"11:00","e":"12:00","b":false},
      {"id":"br","label":"พักกลางวัน","s":"12:00","e":"13:00","b":true},
      {"id":"p5","label":"คาบที่ 5","s":"13:00","e":"14:00","b":false},
      {"id":"p6","label":"คาบที่ 6","s":"14:00","e":"15:00","b":false},
      {"id":"p7","label":"คาบที่ 7","s":"15:00","e":"16:00","b":false},
      {"id":"p8","label":"คาบที่ 8","s":"16:00","e":"17:00","b":false}]',
    '["วันจันทร์","วันอังคาร","วันพุธ","วันพฤหัสบดี","วันศุกร์"]'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- SECTION 18: Row Level Security (RLS)
-- ============================================================
ALTER TABLE profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE timetables         ENABLE ROW LEVEL SECURITY;
ALTER TABLE period_settings    ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjects           ENABLE ROW LEVEL SECURITY;
ALTER TABLE timetable_slots    ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_notes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE homework           ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets    ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_messages    ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements      ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_log       ENABLE ROW LEVEL SECURITY;

-- Helper: is current user admin?
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin' AND status = 'active'
  );
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- Helper: is current user banned?
CREATE OR REPLACE FUNCTION is_banned()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND status = 'banned'
  );
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- Helper: get user quota
CREATE OR REPLACE FUNCTION get_user_quota(uid UUID)
RETURNS INT AS $$
  SELECT COALESCE(quota_override, 3) FROM profiles WHERE id = uid;
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- PROFILES policies
CREATE POLICY "Users see own profile"       ON profiles FOR SELECT  USING (auth.uid() = id OR is_admin());
CREATE POLICY "Users update own profile"    ON profiles FOR UPDATE  USING (auth.uid() = id AND NOT is_banned()) WITH CHECK (role = (SELECT role FROM profiles WHERE id = auth.uid()));
CREATE POLICY "Admin manages all profiles"  ON profiles FOR ALL     USING (is_admin());

-- TIMETABLES policies
CREATE POLICY "Users manage own timetables" ON timetables FOR ALL   USING (auth.uid() = user_id AND NOT is_banned());
CREATE POLICY "Public timetables readable"  ON timetables FOR SELECT USING (is_public = TRUE);
CREATE POLICY "Admin sees all timetables"   ON timetables FOR SELECT USING (is_admin());
-- Quota enforcement via check constraint
CREATE POLICY "Enforce timetable quota"     ON timetables FOR INSERT
  WITH CHECK (
    (SELECT COUNT(*) FROM timetables WHERE user_id = auth.uid())
    < get_user_quota(auth.uid())
  );

-- PERIOD_SETTINGS policies
CREATE POLICY "Users manage own settings"   ON period_settings FOR ALL USING (auth.uid() = user_id AND NOT is_banned());

-- SUBJECTS policies
CREATE POLICY "Users manage own subjects"   ON subjects FOR ALL     USING (auth.uid() = user_id AND NOT is_banned());
CREATE POLICY "Limit 50 subjects"           ON subjects FOR INSERT
  WITH CHECK ((SELECT COUNT(*) FROM subjects WHERE user_id = auth.uid()) < 50);

-- SLOTS policies
CREATE POLICY "Users manage own slots"      ON timetable_slots FOR ALL
  USING (auth.uid() = user_id AND NOT is_banned());

-- CALENDAR_NOTES policies
CREATE POLICY "Users manage own notes"      ON calendar_notes FOR ALL
  USING (auth.uid() = user_id AND NOT is_banned());
CREATE POLICY "Limit 200 notes"             ON calendar_notes FOR INSERT
  WITH CHECK ((SELECT COUNT(*) FROM calendar_notes WHERE user_id = auth.uid()) < 200);

-- HOMEWORK policies
CREATE POLICY "Users manage own homework"   ON homework FOR ALL
  USING (auth.uid() = user_id AND NOT is_banned());
CREATE POLICY "Limit 200 homework items"    ON homework FOR INSERT
  WITH CHECK ((SELECT COUNT(*) FROM homework WHERE user_id = auth.uid()) < 200);

-- SUPPORT_TICKETS policies
CREATE POLICY "Users see own tickets"       ON support_tickets FOR SELECT USING (auth.uid() = user_id OR is_admin());
CREATE POLICY "Users create tickets"        ON support_tickets FOR INSERT WITH CHECK (auth.uid() = user_id AND NOT is_banned());
CREATE POLICY "Admin resolves tickets"      ON support_tickets FOR UPDATE USING (is_admin());

-- TICKET_MESSAGES policies
CREATE POLICY "Ticket participants see messages" ON ticket_messages FOR SELECT
  USING (
    auth.uid() = sender_id OR is_admin() OR
    EXISTS (SELECT 1 FROM support_tickets WHERE id = ticket_id AND user_id = auth.uid())
  );
CREATE POLICY "Ticket participants send messages" ON ticket_messages FOR INSERT
  WITH CHECK (
    auth.uid() = sender_id AND NOT is_banned() AND (
      is_admin() OR
      EXISTS (SELECT 1 FROM support_tickets WHERE id = ticket_id AND user_id = auth.uid())
    )
  );
-- Rate limit: max 30 messages per ticket
CREATE POLICY "Limit messages per ticket"   ON ticket_messages FOR INSERT
  WITH CHECK (
    (SELECT COUNT(*) FROM ticket_messages WHERE ticket_id = ticket_messages.ticket_id) < 30
  );

-- ANNOUNCEMENTS policies
CREATE POLICY "Everyone reads active announcements" ON announcements FOR SELECT USING (is_active = TRUE);
CREATE POLICY "Admin manages announcements"         ON announcements FOR ALL   USING (is_admin());

-- ACTIVITY_LOG policies
CREATE POLICY "Admin sees all activity"     ON activity_log FOR SELECT USING (is_admin());
CREATE POLICY "System inserts activity"     ON activity_log FOR INSERT WITH CHECK (TRUE);

-- ============================================================
-- SECTION 19: Subscription quota function
-- ============================================================
CREATE OR REPLACE FUNCTION get_max_timetables(uid UUID)
RETURNS INT AS $$
DECLARE
  tier sub_tier;
  override INT;
  expires TIMESTAMPTZ;
BEGIN
  SELECT subscription_tier, quota_override, subscription_expires_at
  INTO tier, override, expires FROM profiles WHERE id = uid;
  -- If admin override is set and > 3
  IF override > 3 THEN RETURN override; END IF;
  -- Check subscription active
  IF tier IN ('vip_monthly','vip_yearly','enterprise') AND
     (expires IS NULL OR expires > NOW()) THEN
    RETURN CASE tier
      WHEN 'enterprise' THEN 999
      ELSE 10
    END;
  END IF;
  RETURN 3; -- free tier
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================
-- SECTION 20: Realtime subscriptions (enable for live inbox)
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE ticket_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE support_tickets;
ALTER PUBLICATION supabase_realtime ADD TABLE announcements;

-- ============================================================
-- DONE! ตรวจสอบด้วย:
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public' ORDER BY table_name;
-- ============================================================
