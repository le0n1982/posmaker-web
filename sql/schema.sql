-- ============================================================
--  POSMaker SaaS Schema
--  Run this entire file in Supabase → SQL Editor
-- ============================================================

-- Stores (one per business / store owner)
CREATE TABLE IF NOT EXISTS stores (
  id             UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  owner_id       UUID        REFERENCES auth.users NOT NULL,
  name           TEXT        NOT NULL,
  currency       TEXT        DEFAULT '₱',
  tax_rate       NUMERIC     DEFAULT 12,
  address        TEXT        DEFAULT '',
  phone          TEXT        DEFAULT '',
  receipt_footer TEXT        DEFAULT 'Thank you!',
  logo_b64       TEXT        DEFAULT '',
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Store staff: cashiers & managers (NOT Supabase Auth users)
CREATE TABLE IF NOT EXISTS store_users (
  id            UUID    DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id      UUID    REFERENCES stores NOT NULL,
  username      TEXT    NOT NULL,
  password_hash TEXT    NOT NULL,
  full_name     TEXT    DEFAULT '',
  role          TEXT    DEFAULT 'cashier',   -- cashier | manager
  active        BOOLEAN DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (store_id, username)
);

-- Products
CREATE TABLE IF NOT EXISTS products (
  id         UUID    DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id   UUID    REFERENCES stores NOT NULL,
  name       TEXT    NOT NULL,
  category   TEXT    DEFAULT 'General',
  price      NUMERIC NOT NULL,
  stock      INTEGER DEFAULT 0,
  available  BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
-- Add columns to existing products (safe to re-run)
ALTER TABLE products ADD COLUMN IF NOT EXISTS stock      INTEGER DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS available  BOOLEAN DEFAULT TRUE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS sku        TEXT    DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS unit       TEXT    DEFAULT 'pc';
ALTER TABLE products ADD COLUMN IF NOT EXISTS image_b64  TEXT    DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS cost_price NUMERIC DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS inv_links   TEXT    DEFAULT '[]';
ALTER TABLE products ADD COLUMN IF NOT EXISTS barber_name TEXT    DEFAULT '';
ALTER TABLE products ADD COLUMN IF NOT EXISTS embeddings  TEXT    DEFAULT NULL;
-- 0/empty = sold individually only. >1 = cashier can also sell this product
-- by the pack; pack price is always price * pcs_per_pack (no separate price).
ALTER TABLE products ADD COLUMN IF NOT EXISTS pcs_per_pack NUMERIC DEFAULT 0;

-- Barbershop: saved chair layout (positions + assigned barber per chair), stored as JSON text
ALTER TABLE stores ADD COLUMN IF NOT EXISTS chair_layout TEXT DEFAULT '';

-- Inventory Items (raw materials / supplies — separate from sellable products)
CREATE TABLE IF NOT EXISTS inventory_items (
  id                  UUID    DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id            UUID    REFERENCES stores NOT NULL,
  name                TEXT    NOT NULL,
  sku                 TEXT    DEFAULT '',
  category            TEXT    DEFAULT '',
  unit                TEXT    DEFAULT 'pc',
  stock               NUMERIC DEFAULT 0,
  low_stock_threshold NUMERIC DEFAULT 5,
  cost_price          NUMERIC DEFAULT 0,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS default_usage_qty NUMERIC DEFAULT 1;
-- "How many pcs in 1 [unit]?" on the Add/Edit Inventory Item form — optional,
-- informational split-into-pieces preview; NULL means not set.
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS pcs_per_unit NUMERIC;

ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inv_owner        ON inventory_items;
DROP POLICY IF EXISTS inv_anon_read    ON inventory_items;
DROP POLICY IF EXISTS inv_anon_update  ON inventory_items;

CREATE POLICY inv_owner ON inventory_items FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));

-- Cashier (anon) needs to read stock and deduct after sale
CREATE POLICY inv_anon_read   ON inventory_items FOR SELECT TO anon USING (TRUE);
CREATE POLICY inv_anon_update ON inventory_items FOR UPDATE TO anon USING (TRUE) WITH CHECK (TRUE);

-- Orders
CREATE TABLE IF NOT EXISTS orders (
  id              BIGSERIAL PRIMARY KEY,
  store_id        UUID    REFERENCES stores NOT NULL,
  timestamp       TIMESTAMPTZ DEFAULT NOW(),
  cashier_name    TEXT    DEFAULT '',
  subtotal        NUMERIC DEFAULT 0,
  tax             NUMERIC DEFAULT 0,
  total           NUMERIC DEFAULT 0,
  payment_method  TEXT    DEFAULT 'Cash',
  amount_tendered NUMERIC DEFAULT 0,
  change_given    NUMERIC DEFAULT 0,
  discount_pct    NUMERIC DEFAULT 0
);

-- Order line items
CREATE TABLE IF NOT EXISTS order_items (
  id         BIGSERIAL PRIMARY KEY,
  order_id   BIGINT  REFERENCES orders NOT NULL,
  product_id UUID,
  name       TEXT,
  price      NUMERIC,
  qty        INTEGER
);

-- Activity Log (stock edits, price changes, etc. by staff)
CREATE TABLE IF NOT EXISTS activity_logs (
  id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id    UUID        REFERENCES stores NOT NULL,
  actor_name  TEXT        NOT NULL,
  actor_role  TEXT        DEFAULT 'cashier',
  action      TEXT        NOT NULL,   -- ADD_STOCK | EDIT_ITEM | ADD_ITEM
  target_name TEXT        DEFAULT '',
  details     TEXT        DEFAULT '',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS al_owner   ON activity_logs;
DROP POLICY IF EXISTS al_anon_rw ON activity_logs;
CREATE POLICY al_owner ON activity_logs FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));
CREATE POLICY al_anon_rw ON activity_logs FOR ALL TO anon
  USING (TRUE) WITH CHECK (TRUE);

-- Staff Login Logs
CREATE TABLE IF NOT EXISTS staff_logs (
  id        UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id  UUID        REFERENCES stores NOT NULL,
  staff_id  UUID        REFERENCES store_users NOT NULL,
  username  TEXT        NOT NULL,
  login_at  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE staff_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sl_owner      ON staff_logs;
DROP POLICY IF EXISTS sl_anon_insert ON staff_logs;
CREATE POLICY sl_owner ON staff_logs FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));
CREATE POLICY sl_anon_insert ON staff_logs FOR INSERT TO anon WITH CHECK (TRUE);

-- Categories (persistent, separate from products/inventory)
CREATE TABLE IF NOT EXISTS categories (
  id       UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id UUID REFERENCES stores NOT NULL,
  name     TEXT NOT NULL,
  type     TEXT DEFAULT 'prod',  -- prod | inv
  UNIQUE (store_id, name, type)
);

-- ── Row Level Security ─────────────────────────────────────────────────────────
ALTER TABLE categories   ENABLE ROW LEVEL SECURITY;
ALTER TABLE stores       ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_users  ENABLE ROW LEVEL SECURITY;
ALTER TABLE products     ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders       ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cat_owner ON categories;
CREATE POLICY cat_owner ON categories FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));

-- Drop existing policies first (safe to re-run)
DROP POLICY IF EXISTS stores_owner      ON stores;
DROP POLICY IF EXISTS stores_anon_read  ON stores;
DROP POLICY IF EXISTS su_owner          ON store_users;
DROP POLICY IF EXISTS su_anon_read      ON store_users;
DROP POLICY IF EXISTS prod_owner        ON products;
DROP POLICY IF EXISTS prod_anon_read    ON products;
DROP POLICY IF EXISTS ord_owner         ON orders;
DROP POLICY IF EXISTS ord_anon_insert   ON orders;
DROP POLICY IF EXISTS ord_anon_select   ON orders;
DROP POLICY IF EXISTS oi_anon_select    ON order_items;
DROP POLICY IF EXISTS oi_owner          ON order_items;
DROP POLICY IF EXISTS oi_anon_insert    ON order_items;

-- Stores: owner full access
CREATE POLICY stores_owner ON stores FOR ALL TO authenticated
  USING     (auth.uid() = owner_id)
  WITH CHECK(auth.uid() = owner_id);

-- Stores: anon can read a store's public info (name, currency, tax, logo)
CREATE POLICY stores_anon_read ON stores FOR SELECT TO anon USING (TRUE);

-- Store users: owner manages their store's staff
CREATE POLICY su_owner ON store_users FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));

-- Store users: anon can read active users (for cashier login check)
CREATE POLICY su_anon_read ON store_users FOR SELECT TO anon
  USING (active = TRUE);

-- Products: owner full access
CREATE POLICY prod_owner ON products FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));

-- Products: anon read available products (cashier needs this)
CREATE POLICY prod_anon_read ON products FOR SELECT TO anon
  USING (available = TRUE);

-- Orders: owner full access
CREATE POLICY ord_owner ON orders FOR ALL TO authenticated
  USING (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));

-- Orders: anon insert (cashier submits orders)
CREATE POLICY ord_anon_insert  ON orders FOR INSERT TO anon WITH CHECK (TRUE);
-- Orders: anon select own store's orders (needed for offline sync check)
CREATE POLICY ord_anon_select  ON orders FOR SELECT TO anon USING (TRUE);
-- Order items: anon select (needed for offline sync)
CREATE POLICY oi_anon_select   ON order_items FOR SELECT TO anon USING (TRUE);

-- Order items: owner full access
CREATE POLICY oi_owner ON order_items FOR ALL TO authenticated
  USING (order_id IN (
    SELECT id FROM orders
    WHERE store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid())
  ));

-- Order items: anon insert
CREATE POLICY oi_anon_insert ON order_items FOR INSERT TO anon WITH CHECK (TRUE);

-- POS Theme columns on stores (for Customize POS feature)
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_font    TEXT    DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_accent  TEXT    DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_bg      TEXT    DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_card    TEXT    DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_text    TEXT    DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_radius  NUMERIC DEFAULT 10;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_bg_img    TEXT    DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS business_type  TEXT    DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_btn_style  TEXT    DEFAULT 'default';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_bg_scale   TEXT    DEFAULT 'cover';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_bg_opacity NUMERIC DEFAULT 18;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_code     TEXT    DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_stores_store_code ON stores(store_code);
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_name_color   TEXT DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_price_color  TEXT DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_totals_color TEXT DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_muted_color  TEXT DEFAULT '';

-- Store return/warranty policy, printed on receipts
ALTER TABLE stores ADD COLUMN IF NOT EXISTS policy_warranty       TEXT    DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS policy_return_days    INTEGER;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS policy_damage_accepted BOOLEAN DEFAULT true;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS policy_damage_note    TEXT    DEFAULT '';

-- Restaurant POS columns on orders
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_type   TEXT    DEFAULT 'Dine In';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS table_no     TEXT    DEFAULT '';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS is_kot       BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount_amt NUMERIC DEFAULT 0;

-- Draft orders (save-for-later cart)
CREATE TABLE IF NOT EXISTS draft_orders (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id     UUID        REFERENCES stores NOT NULL,
  cashier_name TEXT        DEFAULT '',
  order_type   TEXT        DEFAULT 'Dine In',
  table_no     TEXT        DEFAULT '',
  items_json   TEXT        DEFAULT '[]',
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE draft_orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS draft_owner ON draft_orders;
DROP POLICY IF EXISTS draft_anon  ON draft_orders;
CREATE POLICY draft_owner ON draft_orders FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));
CREATE POLICY draft_anon ON draft_orders FOR ALL TO anon
  USING (TRUE) WITH CHECK (TRUE);

-- POS Device Registry (locks each POS terminal to one device)
CREATE TABLE IF NOT EXISTS pos_devices (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id      UUID        REFERENCES stores NOT NULL,
  device_id     TEXT        NOT NULL,
  device_name   TEXT        DEFAULT '',
  platform      TEXT        DEFAULT 'windows',
  registered_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (store_id, device_id)
);
ALTER TABLE pos_devices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pd_owner        ON pos_devices;
DROP POLICY IF EXISTS pd_anon_select  ON pos_devices;
DROP POLICY IF EXISTS pd_anon_insert  ON pos_devices;
DROP POLICY IF EXISTS pd_anon_update  ON pos_devices;
CREATE POLICY pd_owner ON pos_devices FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));
CREATE POLICY pd_anon_select ON pos_devices FOR SELECT TO anon USING (TRUE);
CREATE POLICY pd_anon_insert ON pos_devices FOR INSERT TO anon WITH CHECK (TRUE);
-- Lets a cashier device that re-logs in re-claim its slot (e.g. after a
-- cleared cache changed its local device fingerprint) without the owner
-- needing to click "Reset Device".
CREATE POLICY pd_anon_update ON pos_devices FOR UPDATE TO anon USING (TRUE) WITH CHECK (TRUE);

-- Hardware/browser fingerprint — survives a cleared localStorage/cache,
-- since it's recomputed from the device's environment each time rather
-- than read from storage. Used as a fallback to recognize a returning
-- device without asking for the Store Code again.
ALTER TABLE pos_devices ADD COLUMN IF NOT EXISTS fingerprint TEXT;
CREATE INDEX IF NOT EXISTS idx_pos_devices_fingerprint ON pos_devices(fingerprint);

-- Extra terminals for a store, each with its OWN unique code and its OWN
-- single-device lock — so a second (or third) cashier register shares the
-- same store's menu/staff/sales, but its code can be revoked/rotated
-- independently of the others if it's lost or a device needs replacing.
-- The store's own store_code remains "Terminal #1" implicitly (no row
-- here), so existing single-terminal stores need no migration.
CREATE TABLE IF NOT EXISTS pos_terminals (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id      UUID        REFERENCES stores NOT NULL,
  terminal_code TEXT        NOT NULL UNIQUE,
  name          TEXT        NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE pos_terminals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pt_owner       ON pos_terminals;
DROP POLICY IF EXISTS pt_anon_select ON pos_terminals;
CREATE POLICY pt_owner ON pos_terminals FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));
CREATE POLICY pt_anon_select ON pos_terminals FOR SELECT TO anon USING (TRUE);

-- A device now registers against a specific terminal (NULL terminal_id
-- means it's on the store's own code, i.e. "Terminal #1") so each extra
-- terminal's device lock is independent of the others. Removal still goes
-- through reset_pos_device() (SECURITY DEFINER) or the owner's own
-- authenticated session — anon never gets DELETE on pos_devices directly.
ALTER TABLE pos_devices ADD COLUMN IF NOT EXISTS terminal_id UUID REFERENCES pos_terminals;

-- Removes a registered device from a store so it (or a different device)
-- needs the Store Code again to reconnect. SECURITY DEFINER bypasses RLS
-- since the dashboard calls this as the authenticated owner via RPC rather
-- than a direct table delete. p_device_id is optional for backward
-- compatibility — omitting it resets every device on the store at once
-- (the original single-device behavior); passing it removes just that one
-- device, since a store can now have several devices registered at once
-- (e.g. a second cashier register sharing the same menu/staff).
CREATE OR REPLACE FUNCTION reset_pos_device(p_store_id UUID, p_device_id TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_device_id IS NULL THEN
    DELETE FROM pos_devices WHERE store_id = p_store_id;
  ELSE
    DELETE FROM pos_devices WHERE store_id = p_store_id AND device_id = p_device_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION reset_pos_device(uuid, text) TO anon, authenticated;

-- Staff online tracking columns
ALTER TABLE store_users ADD COLUMN IF NOT EXISTS last_seen     TIMESTAMPTZ;
ALTER TABLE store_users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

-- Payroll: an open-ended list of mandatory deductions (SSS, PhilHealth,
-- insurance, whatever the owner adds by name) deducted from net pay each
-- payroll run, plus how often this staff member is actually paid.
-- mandatory_contributions shape: [{"name":"SSS","amount":500}, ...]
ALTER TABLE store_users DROP COLUMN IF EXISTS sss_contribution;
ALTER TABLE store_users DROP COLUMN IF EXISTS philhealth_contribution;
ALTER TABLE store_users DROP COLUMN IF EXISTS pagibig_contribution;
ALTER TABLE store_users ADD COLUMN IF NOT EXISTS mandatory_contributions JSONB DEFAULT '[]';
ALTER TABLE store_users ADD COLUMN IF NOT EXISTS salary_frequency       TEXT DEFAULT 'monthly'; -- weekly | semimonthly | monthly

-- Face ID for Time In/Out face scan (manager.html) — a face-api.js 128-value
-- descriptor (numbers only, not a photo), registered once via face-scan.html
-- from the Add/Edit Staff modal's "Scan QR to Register Face".
ALTER TABLE store_users ADD COLUMN IF NOT EXISTS face_descriptor JSONB;

-- Owner toggle (Settings → POS Permissions): shows/hides a "View Sales"
-- button in the cashier POS. Scoped to that cashier's own sales only when
-- enabled — never store-wide totals.
ALTER TABLE stores ADD COLUMN IF NOT EXISTS show_sales_to_cashier BOOLEAN DEFAULT false;

-- Ping: update last_seen so dashboard can show Online indicator
CREATE OR REPLACE FUNCTION ping_staff_online(p_staff_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE store_users SET last_seen = NOW() WHERE id = p_staff_id;
END;
$$;

-- Login: insert into staff_logs AND stamp last_login_at on store_users
CREATE OR REPLACE FUNCTION log_staff_login(p_store_id UUID, p_staff_id UUID, p_username TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO staff_logs (store_id, staff_id, username) VALUES (p_store_id, p_staff_id, p_username);
  UPDATE store_users SET last_login_at = NOW() WHERE id = p_staff_id;
END;
$$;

-- Logout: clear last_seen so staff shows as offline immediately
CREATE OR REPLACE FUNCTION log_staff_logout(p_staff_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE store_users SET last_seen = NULL WHERE id = p_staff_id;
END;
$$;

-- ============================================================
--  Agent Referral Program
--  Run this block in Supabase → SQL Editor (once)
-- ============================================================

-- People who apply to become POSMaker referral agents
CREATE TABLE IF NOT EXISTS agents (
  id             UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  name           TEXT        DEFAULT '',
  email          TEXT        DEFAULT '',
  contact_number TEXT        DEFAULT '',
  address        TEXT        DEFAULT '',
  description    TEXT        DEFAULT '',
  referral_code  TEXT        UNIQUE,
  status         TEXT        DEFAULT 'pending',  -- pending | approved | rejected
  default_free_months INTEGER DEFAULT 1,         -- free period (1-12) granted by default to this agent's referrals
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE agents ADD COLUMN IF NOT EXISTS default_free_months INTEGER DEFAULT 1;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS email TEXT DEFAULT '';
ALTER TABLE agents ALTER COLUMN name DROP NOT NULL;
ALTER TABLE agents ALTER COLUMN name SET DEFAULT '';
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS agents_all ON agents;
CREATE POLICY agents_all ON agents FOR ALL TO anon USING (true) WITH CHECK (true);

-- Accounts requested through an agent's referral link (pending admin review)
CREATE TABLE IF NOT EXISTS agent_referrals (
  id             UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  agent_id       UUID        REFERENCES agents NOT NULL,
  store_name     TEXT        NOT NULL,
  business_type  TEXT        DEFAULT 'retail',
  owner_email    TEXT        NOT NULL,
  contact_number TEXT        DEFAULT '',
  notes          TEXT        DEFAULT '',
  status         TEXT        DEFAULT 'pending',  -- pending | granted | denied
  free_period    TEXT        DEFAULT '',         -- '1month' | '1year'
  store_id       UUID        REFERENCES stores ON DELETE SET NULL,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE agent_referrals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS agent_referrals_all ON agent_referrals;
CREATE POLICY agent_referrals_all ON agent_referrals FOR ALL TO anon USING (true) WITH CHECK (true);

-- Public: submit an agent application (from agent-apply.html) — email-only lead capture;
-- the owner follows up by email to learn more before approving.
DROP FUNCTION IF EXISTS submit_agent_application(text, text, text, text);
CREATE OR REPLACE FUNCTION submit_agent_application(p_email text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO agents (name, email, status)
  VALUES (p_email, p_email, 'pending')
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

-- Public: look up an approved agent by referral code (used by agent-signup.html)
CREATE OR REPLACE FUNCTION get_agent_by_code(p_code text)
RETURNS TABLE(id uuid, name text, status text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY SELECT a.id, a.name, a.status FROM agents a
    WHERE a.referral_code = p_code AND a.status = 'approved';
END; $$;

-- Public: submit a referral signup request (from agent-signup.html) — does NOT create the account
CREATE OR REPLACE FUNCTION submit_agent_referral(p_ref_code text, p_store_name text,
  p_business_type text, p_owner_email text, p_contact text, p_notes text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_agent_id uuid; v_id uuid;
BEGIN
  SELECT id INTO v_agent_id FROM agents WHERE referral_code = p_ref_code AND status = 'approved';
  IF v_agent_id IS NULL THEN RAISE EXCEPTION 'Invalid or inactive referral link.'; END IF;
  INSERT INTO agent_referrals (agent_id, store_name, business_type, owner_email, contact_number, notes, status)
  VALUES (v_agent_id, p_store_name, p_business_type, p_owner_email, p_contact, p_notes, 'pending')
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

-- Admin: list agent applications
DROP FUNCTION IF EXISTS dev_get_agents(text);
CREATE OR REPLACE FUNCTION dev_get_agents(p_token text)
RETURNS TABLE(id uuid, name text, email text, contact_number text, address text, description text,
              referral_code text, status text, default_free_months integer, commission_rate numeric, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  RETURN QUERY SELECT a.id, a.name, a.email, a.contact_number, a.address, a.description,
    a.referral_code, a.status, a.default_free_months, a.commission_rate, a.created_at FROM agents a ORDER BY a.created_at DESC;
END; $$;

-- Admin: approve an agent application — generates their referral code on first approval,
-- sets the default free period (1-12 months) granted to accounts they refer, and the
-- commission rate (%) the agent earns each month on their referred stores' subscriptions.
DROP FUNCTION IF EXISTS dev_approve_agent(text, uuid, integer);
CREATE OR REPLACE FUNCTION dev_approve_agent(p_token text, p_agent_id uuid, p_months integer DEFAULT 1, p_commission_rate numeric DEFAULT 10)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_code text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT referral_code INTO v_code FROM agents WHERE id = p_agent_id;
  IF v_code IS NULL THEN
    v_code := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
    UPDATE agents SET referral_code = v_code WHERE id = p_agent_id;
  END IF;
  UPDATE agents SET status = 'approved', default_free_months = p_months, commission_rate = p_commission_rate WHERE id = p_agent_id;
  RETURN v_code;
END; $$;

-- Admin: reject / revoke an agent application
CREATE OR REPLACE FUNCTION dev_reject_agent(p_token text, p_agent_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  UPDATE agents SET status = 'rejected' WHERE id = p_agent_id;
  RETURN FOUND;
END; $$;

-- Admin: list referral signup requests
DROP FUNCTION IF EXISTS dev_get_agent_referrals(text);
CREATE OR REPLACE FUNCTION dev_get_agent_referrals(p_token text)
RETURNS TABLE(id uuid, agent_id uuid, agent_name text, agent_default_months integer, store_name text, business_type text,
              owner_email text, contact_number text, notes text, status text,
              free_period text, store_id uuid, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  RETURN QUERY
    SELECT r.id, r.agent_id, a.name, a.default_free_months, r.store_name, r.business_type, r.owner_email,
           r.contact_number, r.notes, r.status, r.free_period, r.store_id, r.created_at
    FROM agent_referrals r JOIN agents a ON a.id = r.agent_id
    ORDER BY r.created_at DESC;
END; $$;

-- Admin: deny a referral signup request
CREATE OR REPLACE FUNCTION dev_deny_referral(p_token text, p_referral_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  UPDATE agent_referrals SET status = 'denied' WHERE id = p_referral_id;
  RETURN FOUND;
END; $$;

-- Admin: grant free access for a referral — call AFTER creating the store via dev_create_partner.
-- Records a free subscription (amount = 0) and links the referral to the new store.
-- Free period is a number of months (1-12), chosen by the admin per referral.
DROP FUNCTION IF EXISTS dev_grant_referral(text, uuid, uuid, text);
CREATE OR REPLACE FUNCTION dev_grant_referral(p_token text, p_referral_id uuid,
  p_store_id uuid, p_months integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_email text; v_expires timestamptz;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT owner_email INTO v_email FROM agent_referrals WHERE id = p_referral_id;
  v_expires := now() + (p_months || ' months')::interval;
  INSERT INTO subscriptions (store_id, subscriber_email, plan_name, amount, status, expires_at)
  VALUES (p_store_id, v_email, 'Agent Referral - Free', 0, 'active', v_expires);
  UPDATE agent_referrals SET status = 'granted', free_period = p_months::text, store_id = p_store_id
    WHERE id = p_referral_id;
  RETURN true;
END; $$;

-- ============================================================
--  Affiliate self-signup (agent-apply.html + affiliate-dashboard.html)
-- ============================================================

ALTER TABLE agents ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS agreed_terms BOOLEAN DEFAULT false;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS commission_rate NUMERIC DEFAULT 10;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS link_clicks INTEGER DEFAULT 0;

-- Public: called by index.html the first time a visitor lands via ?ref=CODE in a given
-- browser session. Lets affiliates see whether their link is getting any traffic at all.
CREATE OR REPLACE FUNCTION track_referral_click(p_ref_code text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE agents SET link_clicks = link_clicks + 1
    WHERE referral_code = p_ref_code AND status = 'approved';
END; $$;

-- Public (authenticated affiliate): submit/update their affiliate application after creating
-- their Supabase Auth account in agent-apply.html. Idempotent on auth_user_id so returning
-- from an email-confirmation link doesn't create a duplicate row.
CREATE OR REPLACE FUNCTION submit_affiliate_application(p_auth_user_id uuid, p_name text, p_email text, p_address text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM agents WHERE auth_user_id = p_auth_user_id;
  IF v_id IS NULL THEN
    INSERT INTO agents (auth_user_id, name, email, address, status, agreed_terms)
    VALUES (p_auth_user_id, p_name, p_email, p_address, 'pending', true)
    RETURNING id INTO v_id;
  ELSE
    UPDATE agents SET name = p_name, email = p_email, address = p_address, agreed_terms = true
      WHERE id = v_id;
  END IF;
  RETURN v_id;
END; $$;

-- Public (authenticated affiliate): fetch their own application/status for affiliate-dashboard.html
DROP FUNCTION IF EXISTS get_my_affiliate(uuid);
CREATE OR REPLACE FUNCTION get_my_affiliate(p_auth_user_id uuid)
RETURNS TABLE(id uuid, name text, email text, status text, referral_code text,
              default_free_months integer, commission_rate numeric, link_clicks integer, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY SELECT a.id, a.name, a.email, a.status, a.referral_code, a.default_free_months, a.commission_rate, a.link_clicks, a.created_at
    FROM agents a WHERE a.auth_user_id = p_auth_user_id;
END; $$;

-- Public (authenticated affiliate): list their own referrals for affiliate-dashboard.html, including
-- the referred store's current active subscription amount and the resulting monthly commission
-- (subscription amount x the affiliate's commission_rate).
DROP FUNCTION IF EXISTS get_my_referrals(uuid);
CREATE OR REPLACE FUNCTION get_my_referrals(p_auth_user_id uuid)
RETURNS TABLE(id uuid, store_name text, business_type text, status text, free_period text,
              created_at timestamptz, subscription_amount numeric, monthly_commission numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_agent_id uuid; v_rate numeric;
BEGIN
  SELECT a.id, a.commission_rate INTO v_agent_id, v_rate FROM agents a WHERE a.auth_user_id = p_auth_user_id;
  IF v_agent_id IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT r.id, r.store_name, r.business_type, r.status, r.free_period, r.created_at,
           s.amount,
           ROUND(COALESCE(s.amount, 0) * COALESCE(v_rate, 10) / 100, 2)
    FROM agent_referrals r
    LEFT JOIN LATERAL (
      SELECT sub.amount FROM subscriptions sub
      WHERE sub.store_id = r.store_id AND sub.status = 'active' AND (sub.expires_at IS NULL OR sub.expires_at >= now())
      ORDER BY sub.expires_at DESC LIMIT 1
    ) s ON true
    WHERE r.agent_id = v_agent_id ORDER BY r.created_at DESC;
END; $$;

-- Public: called automatically by signup.html right after a new store is created via a
-- referral link (?ref=CODE). Records the referral against the affiliate and immediately
-- grants the affiliate's default free-trial period (as a 0-amount active subscription) —
-- no admin review needed. Silently does nothing if the code is missing/invalid/unapproved,
-- so signup always proceeds normally either way.
CREATE OR REPLACE FUNCTION track_referral(p_ref_code text, p_store_id uuid, p_store_name text,
  p_business_type text, p_owner_email text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_agent_id uuid; v_months integer;
BEGIN
  SELECT id, default_free_months INTO v_agent_id, v_months FROM agents
    WHERE referral_code = p_ref_code AND status = 'approved';
  IF v_agent_id IS NULL THEN RETURN; END IF;

  INSERT INTO agent_referrals (agent_id, store_name, business_type, owner_email, status, free_period, store_id)
  VALUES (v_agent_id, p_store_name, p_business_type, p_owner_email, 'granted', v_months::text, p_store_id);

  INSERT INTO subscriptions (store_id, subscriber_email, plan_name, amount, status, expires_at)
  VALUES (p_store_id, p_owner_email, 'Referral - Free Trial', 0, 'active', now() + (v_months || ' months')::interval);
END; $$;

-- RLS: store owners need to read their own subscriptions row so dashboard.html can
-- determine IS_PRO (subscriptions has RLS enabled with no policies by default, which
-- blocks all client-side reads).
GRANT SELECT ON subscriptions TO authenticated;
CREATE POLICY "Users can view their own subscriptions" ON subscriptions
FOR SELECT
USING (
  subscriber_email = auth.jwt() ->> 'email'
  OR store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid())
);

-- Cashier pages run as `anon` (custom store_users login, not Supabase Auth),
-- so the RLS policy above (auth.jwt()/auth.uid()) doesn't help there.
-- This SECURITY DEFINER RPC lets the cashier check the store's Pro status
-- without exposing raw subscription rows to anon.
CREATE OR REPLACE FUNCTION get_store_pro_status(p_store_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_free_until timestamptz; v_active boolean;
BEGIN
  SELECT free_until INTO v_free_until FROM stores WHERE id = p_store_id;
  IF v_free_until IS NOT NULL AND v_free_until > now() THEN RETURN true; END IF;
  SELECT true INTO v_active FROM subscriptions
    WHERE store_id = p_store_id AND status = 'active' AND (expires_at IS NULL OR expires_at >= now())
    LIMIT 1;
  RETURN COALESCE(v_active, false);
END; $$;

GRANT EXECUTE ON FUNCTION get_store_pro_status(uuid) TO anon, authenticated;

-- ============================================================
--  Daily Checklist / SOP Notes / Photo Proof (ops_data)
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================

-- Stores per-store checklist items, today's completion log, SOP notes, and
-- checklist photo-proof images/capture tokens (see js/store-plan.js).
ALTER TABLE stores ADD COLUMN IF NOT EXISTS ops_data JSONB DEFAULT '{}'::jsonb;

-- manager.html and checklist-capture.html run as `anon` (custom store_users login,
-- not Supabase Auth), so the owner-only stores_owner policy doesn't cover their
-- writes. Rather than grant anon broad UPDATE on `stores` (which would let anyone
-- with a store id rewrite owner_id, telegram tokens, etc.), expose a narrow
-- SECURITY DEFINER RPC that can only touch the ops_data column.
CREATE OR REPLACE FUNCTION save_ops_data(p_store_id uuid, p_ops_data jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE stores SET ops_data = p_ops_data WHERE id = p_store_id;
END; $$;

GRANT EXECUTE ON FUNCTION save_ops_data(uuid, jsonb) TO anon, authenticated;

-- ============================================================
--  Store Hours (opening/closing time + closed days)
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================

-- "HH:MM" 24-hour strings; closed_days is a comma-separated list of
-- weekday numbers (0=Sun .. 6=Sat), empty = open every day.
ALTER TABLE stores ADD COLUMN IF NOT EXISTS open_time   TEXT DEFAULT '08:00';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS close_time  TEXT DEFAULT '20:00';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS closed_days TEXT DEFAULT '';

-- ============================================================
--  Floating Calculator widget on/off switch
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS show_calculator BOOLEAN DEFAULT TRUE;

-- ============================================================
--  Cash Remittances — description column + MobileNet embeddings
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE cash_remittances ADD COLUMN IF NOT EXISTS description TEXT DEFAULT NULL;
ALTER TABLE products         ADD COLUMN IF NOT EXISTS embeddings  TEXT DEFAULT NULL;

-- ============================================================
--  Customize POS — Font Size Scale (80-130%, applied as CSS zoom)
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS pos_font_scale INTEGER DEFAULT 100;

-- ============================================================
--  Fix: deleting a store from Dev Support failed with
--  "violates foreign key constraint agent_referrals_store_id_fkey"
--  because agent_referrals.store_id had no ON DELETE behavior.
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE agent_referrals DROP CONSTRAINT IF EXISTS agent_referrals_store_id_fkey;
ALTER TABLE agent_referrals ADD CONSTRAINT agent_referrals_store_id_fkey
  FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE SET NULL;

-- ============================================================
--  "Free for Everyone" toggle (Dev Support -> Subscriptions)
--  Lets the admin flip every store (existing + new signups) between Pro
--  unlocked indefinitely and the normal 14-day trial / paid plan, without
--  hand-running SQL. Both the dashboard's IS_PRO check and the cashier's
--  get_store_pro_status() RPC already read stores.free_until, so flipping
--  this just extends/clears that one column for every store at once.
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.app_settings (
  key   TEXT PRIMARY KEY,
  value TEXT
);
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_settings_all ON app_settings;
CREATE POLICY app_settings_all ON app_settings FOR ALL TO anon USING (true) WITH CHECK (true);

-- Public read — signup.html checks this (no admin token) to decide whether a
-- new store's trial should be the normal 14 days or unlocked indefinitely.
CREATE OR REPLACE FUNCTION get_free_for_all()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT value::boolean FROM app_settings WHERE key = 'free_for_all'), false);
$$;
GRANT EXECUTE ON FUNCTION get_free_for_all() TO anon, authenticated;

CREATE OR REPLACE FUNCTION dev_set_free_for_all(p_token text, p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  INSERT INTO app_settings (key, value) VALUES ('free_for_all', p_enabled::text)
    ON CONFLICT (key) DO UPDATE SET value = p_enabled::text;
  IF p_enabled THEN
    UPDATE stores SET free_until = now() + interval '100 years' WHERE true;
  ELSE
    UPDATE stores SET free_until = NULL WHERE true;
  END IF;
END; $$;

-- ============================================================
--  Plan Limits (Dev Support -> Plan Limits)
--  Admin-configurable Inventory/Product/Staff/POS-terminal limits for each
--  of the 4 plan tiers (free, standard, pro, premium). Reads are public;
--  writes are gated to a logged-in dev admin. Every store defaults to the
--  'free' tier — dashboards/cashiers now read plan_limits by this column
--  instead of a hardcoded 3/3/1/1, so whatever is set in Dev Support ->
--  Plan Limits is the real, live limit (still bypassed entirely when a
--  store is Pro via subscription or the "Free for Everyone" toggle).
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS plan_tier TEXT DEFAULT 'free';
CREATE TABLE IF NOT EXISTS public.plan_limits (
  tier            TEXT PRIMARY KEY,
  inventory_limit INTEGER NOT NULL DEFAULT 0,
  product_limit   INTEGER NOT NULL DEFAULT 0,
  staff_limit     INTEGER NOT NULL DEFAULT 0,
  pos_limit       INTEGER NOT NULL DEFAULT 0,
  price_usd       NUMERIC(10,2) NOT NULL DEFAULT 0
);
ALTER TABLE plan_limits ADD COLUMN IF NOT EXISTS price_usd NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE plan_limits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS plan_limits_read ON plan_limits;
CREATE POLICY plan_limits_read ON plan_limits FOR SELECT TO anon USING (true);

INSERT INTO plan_limits (tier, inventory_limit, product_limit, staff_limit, pos_limit) VALUES
  ('free',     3,  3,  1, 1),
  ('standard', 10, 10, 3, 1),
  ('pro',      50, 50, 10, 3),
  ('premium',  999999, 999999, 999999, 999999)
ON CONFLICT (tier) DO NOTHING;

-- Signature changed (added p_price) — drop the old 6-arg version first so
-- CREATE OR REPLACE doesn't leave a stale orphaned overload behind.
DROP FUNCTION IF EXISTS dev_set_plan_limit(text, text, int, int, int, int);
CREATE OR REPLACE FUNCTION dev_set_plan_limit(p_token text, p_tier text,
  p_inventory int, p_product int, p_staff int, p_pos int, p_price numeric DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  INSERT INTO plan_limits (tier, inventory_limit, product_limit, staff_limit, pos_limit, price_usd)
    VALUES (p_tier, p_inventory, p_product, p_staff, p_pos, p_price)
    ON CONFLICT (tier) DO UPDATE SET inventory_limit = p_inventory,
      product_limit = p_product, staff_limit = p_staff, pos_limit = p_pos, price_usd = p_price;
END; $$;

-- ============================================================
--  5-day "Are you satisfied?" check-in survey (owner dashboard) +
--  public Contact Support form (contact.html)
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
-- Marks a store as already prompted so the survey only ever shows once.
ALTER TABLE stores ADD COLUMN IF NOT EXISTS survey_prompted_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.satisfaction_surveys (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id    UUID REFERENCES stores ON DELETE SET NULL,
  store_name  TEXT DEFAULT '',
  owner_email TEXT DEFAULT '',
  rating      INTEGER,
  comment     TEXT DEFAULT '',
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE satisfaction_surveys ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS satisfaction_surveys_insert ON satisfaction_surveys;
CREATE POLICY satisfaction_surveys_insert ON satisfaction_surveys FOR INSERT TO anon WITH CHECK (true);

CREATE OR REPLACE FUNCTION dev_get_satisfaction_surveys(p_token text)
RETURNS SETOF satisfaction_surveys LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  RETURN QUERY SELECT * FROM satisfaction_surveys ORDER BY created_at DESC;
END; $$;

CREATE TABLE IF NOT EXISTS public.contact_messages (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  email      TEXT NOT NULL,
  store_name TEXT DEFAULT '',
  subject    TEXT NOT NULL,
  message    TEXT NOT NULL,
  status     TEXT DEFAULT 'open',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE contact_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS contact_messages_insert ON contact_messages;
CREATE POLICY contact_messages_insert ON contact_messages FOR INSERT TO anon WITH CHECK (true);

CREATE OR REPLACE FUNCTION dev_get_contact_messages(p_token text)
RETURNS SETOF contact_messages LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  RETURN QUERY SELECT * FROM contact_messages ORDER BY created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION dev_set_contact_status(p_token text, p_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  UPDATE contact_messages SET status = p_status WHERE id = p_id;
END; $$;

-- ============================================================
-- Website Visitor Tracking (index.html landing page)
-- ============================================================

CREATE TABLE IF NOT EXISTS site_visits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  country TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_site_visits_created ON site_visits(created_at DESC);
ALTER TABLE site_visits ENABLE ROW LEVEL SECURITY;

-- Public: called by index.html once per browser session, fire-and-forget. Country is
-- resolved client-side via a free IP geolocation lookup (best-effort — null if it fails).
-- SECURITY DEFINER bypasses RLS for the insert, same as track_referral_click above —
-- no anon table grant/policy needed since nothing ever queries this table directly.
CREATE OR REPLACE FUNCTION track_site_visit(p_country text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO site_visits (country) VALUES (p_country);
END; $$;

-- Admin: country breakdown of website visits + total, for dev-support.html's Visitors tab.
CREATE OR REPLACE FUNCTION dev_get_site_visits(p_token text)
RETURNS TABLE(country text, visits bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_admins WHERE session_token = p_token
    AND session_expires_at > now()) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  RETURN QUERY SELECT COALESCE(sv.country, 'Unknown') AS country, COUNT(*) AS visits
    FROM site_visits sv GROUP BY COALESCE(sv.country, 'Unknown') ORDER BY visits DESC;
END; $$;

-- Customer name/contact on orders — used by the Laundry cashier's claim-slip
-- receipt (customer copy + owner copy) so the owner can match a slip back
-- to who dropped it off.
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_name  TEXT DEFAULT '';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_phone TEXT DEFAULT '';

-- One store per owner, enforced at the DB level (the "MC" x4 duplicate-store
-- incident showed the client-side "already has a store" check alone isn't
-- enough — a race between two near-simultaneous signup attempts can slip
-- past it). Run the dedupe DELETE first if any duplicates already exist,
-- or this ALTER will fail.
ALTER TABLE stores ADD CONSTRAINT stores_owner_id_unique UNIQUE (owner_id);

-- ============================================================
--  Inactivity auto-delete policy
--  "Inactive" = no LOGIN in activity_logs AND no orders for that store.
--  Flow: warn the owner by email once a store has been inactive for
--  (3 months - 1 week); if still inactive 1 week after that warning
--  (~3 months total), delete the store. Re-activity before the deadline
--  clears the warning and resets the clock.
--  Requires: the send-inactivity-warning-email Edge Function deployed
--  (supabase/functions/send-inactivity-warning-email/index.ts) with
--  RESEND_API_KEY set, the pg_cron / pg_net extensions enabled below, and
--  a one-time app_settings row holding the project's anon key — run
--  separately in SQL Editor (not committed here):
--    INSERT INTO app_settings (key, value) VALUES ('supabase_anon_key', '<Settings -> API -> anon public key>')
--    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

ALTER TABLE stores ADD COLUMN IF NOT EXISTS inactivity_warned_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION process_inactive_stores()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r RECORD;
  _anon_key TEXT;
  _fn_url   TEXT := 'https://djvwlwnnlldoppomhbap.supabase.co/functions/v1/send-inactivity-warning-email';
  _cutoff   INTERVAL := INTERVAL '3 months' - INTERVAL '1 week';
BEGIN
  SELECT value INTO _anon_key FROM app_settings WHERE key = 'supabase_anon_key';
  IF _anon_key IS NULL THEN
    RAISE NOTICE 'process_inactive_stores: app_settings.supabase_anon_key not set — skipping email step, deletions still run.';
  END IF;

  -- Step 0: re-activity since being warned clears the warning (restart the clock)
  UPDATE stores s SET inactivity_warned_at = NULL
  WHERE s.inactivity_warned_at IS NOT NULL
    AND (
      EXISTS (SELECT 1 FROM activity_logs al WHERE al.store_id = s.id AND al.action = 'LOGIN' AND al.created_at > s.inactivity_warned_at)
      OR EXISTS (SELECT 1 FROM orders o WHERE o.store_id = s.id AND o.timestamp > s.inactivity_warned_at)
    );

  -- Step 1: warn stores inactive for (3 months - 1 week) that haven't been warned yet
  IF _anon_key IS NOT NULL THEN
    FOR r IN
      SELECT s.id, s.name, u.email
      FROM stores s
      JOIN auth.users u ON u.id = s.owner_id
      WHERE s.inactivity_warned_at IS NULL
        AND s.created_at < now() - _cutoff
        AND NOT EXISTS (SELECT 1 FROM activity_logs al WHERE al.store_id = s.id AND al.action = 'LOGIN' AND al.created_at > now() - _cutoff)
        AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.store_id = s.id AND o.timestamp > now() - _cutoff)
    LOOP
      PERFORM net.http_post(
        url     := _fn_url,
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || _anon_key),
        body    := jsonb_build_object('to', r.email, 'name', r.name)
      );
      UPDATE stores SET inactivity_warned_at = now() WHERE id = r.id;
    END LOOP;
  END IF;

  -- Step 2: delete stores warned 1+ week ago that are still inactive (~3 months total)
  DELETE FROM stores s
  WHERE s.inactivity_warned_at IS NOT NULL
    AND s.inactivity_warned_at < now() - INTERVAL '1 week'
    AND NOT EXISTS (SELECT 1 FROM activity_logs al WHERE al.store_id = s.id AND al.action = 'LOGIN' AND al.created_at > s.inactivity_warned_at)
    AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.store_id = s.id AND o.timestamp > s.inactivity_warned_at);
END;
$$;

-- Re-runnable: drop any existing schedule with this name before re-creating it
DO $$
BEGIN
  PERFORM cron.unschedule('process-inactive-stores-daily');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
SELECT cron.schedule('process-inactive-stores-daily', '0 3 * * *', 'SELECT process_inactive_stores();');

-- ============================================================
--  GCash QR code for the customer-facing display (customer-display.html)
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS gcash_qr_b64 TEXT;

-- ============================================================
--  Dual Screen toggle (My POS Terminals) — same device, second
--  window/monitor shows the customer-facing display, synced
--  instantly via BroadcastChannel instead of pairing a 2nd device.
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS dual_screen_enabled BOOLEAN DEFAULT FALSE;

-- ============================================================
--  Payment Methods — owner-configured e-payment QR codes (GCash, BDO,
--  BPI, Maya, etc.), shown as options in the cashier's E-Pay widget.
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
CREATE TABLE IF NOT EXISTS payment_methods (
  id         UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id   UUID        REFERENCES stores NOT NULL,
  label      TEXT        NOT NULL,
  qr_b64     TEXT        DEFAULT '',
  qr_payload TEXT,
  sort_order INTEGER     DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pm_owner     ON payment_methods;
DROP POLICY IF EXISTS pm_anon_read ON payment_methods;
CREATE POLICY pm_owner ON payment_methods FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));
CREATE POLICY pm_anon_read ON payment_methods FOR SELECT TO anon USING (TRUE);

-- ============================================================
--  Stock History — per-item log of sale deductions and manual
--  stock add/adjust events, shown via "History" on the Inventory page.
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
CREATE TABLE IF NOT EXISTS stock_history (
  id                UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id          UUID        REFERENCES stores NOT NULL,
  inventory_item_id UUID        NOT NULL,
  change_type       TEXT        NOT NULL,   -- SALE | MANUAL_ADD | MANUAL_ADJUST
  qty_change        NUMERIC     NOT NULL,   -- negative = deducted, positive = added
  note              TEXT        DEFAULT '', -- product name(s) for SALE rows
  created_at        TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_stock_history_item ON stock_history(inventory_item_id, created_at DESC);
ALTER TABLE stock_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sh_owner   ON stock_history;
DROP POLICY IF EXISTS sh_anon_rw ON stock_history;
CREATE POLICY sh_owner ON stock_history FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));
CREATE POLICY sh_anon_rw ON stock_history FOR ALL TO anon
  USING (TRUE) WITH CHECK (TRUE);

-- ============================================================
--  Staff Deductions — owner charges a staff member for a proven
--  loss (e.g. missing cash/stock). Sits alongside cash_advances:
--  both get subtracted from that staff's next payroll run, and
--  both show up in the Payroll History breakdown by date.
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
CREATE TABLE IF NOT EXISTS staff_deductions (
  id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id    UUID        REFERENCES stores NOT NULL,
  staff_id    UUID        NOT NULL,
  staff_name  TEXT        NOT NULL,
  amount      NUMERIC     NOT NULL,
  reason      TEXT        DEFAULT '',
  status      TEXT        DEFAULT 'pending', -- pending | settled
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  settled_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_staff_deductions_store ON staff_deductions(store_id, staff_id);
ALTER TABLE staff_deductions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sd_owner   ON staff_deductions;
DROP POLICY IF EXISTS sd_anon_rw ON staff_deductions;
CREATE POLICY sd_owner ON staff_deductions FOR ALL TO authenticated
  USING     (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
  WITH CHECK(store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));
CREATE POLICY sd_anon_rw ON staff_deductions FOR ALL TO anon
  USING (TRUE) WITH CHECK (TRUE);

-- ============================================================
--  Drawer Float on Logout — owner-toggled option letting a cashier keep
--  part of the counted cash as a change fund for the next shift instead of
--  remitting all of it (e.g. ₱11,500 counted, ₱10,000 remitted, ₱1,500 kept
--  in the drawer). Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores           ADD COLUMN IF NOT EXISTS enable_drawer_float BOOLEAN DEFAULT false;
ALTER TABLE cash_remittances ADD COLUMN IF NOT EXISTS remit_amount        NUMERIC DEFAULT NULL;
ALTER TABLE cash_remittances ADD COLUMN IF NOT EXISTS drawer_float        NUMERIC DEFAULT NULL;

-- ============================================================
--  Cashier-Recorded Expenses + "My Activity" — owner-toggled option letting
--  a cashier log an expense straight from the POS (e.g. bought office
--  supplies out of the drawer), tagged with who recorded it so it shows up
--  in both the owner's Activity Log and that cashier's own activity view.
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores   ADD COLUMN IF NOT EXISTS allow_cashier_expenses BOOLEAN DEFAULT false;
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS added_by               TEXT DEFAULT NULL;

-- ============================================================
--  BIR Registration Info — stored for the owner's own records and for
--  eventual BIR-compliant Official Receipt numbering (registered name,
--  TIN, and a photo of the Certificate of Registration / BIR Form 2303).
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS bir_registered_name TEXT DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS bir_tin              TEXT DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS bir_cor_b64          TEXT DEFAULT NULL;

-- ============================================================
--  Allow Overselling — owner-toggled option letting a sale go through even
--  when the requested quantity exceeds recorded stock (stock goes negative
--  and self-corrects once new stock is added). Default off — preserves the
--  existing "block the sale" behavior unless a store opts in.
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS allow_oversell BOOLEAN DEFAULT false;

-- ============================================================
--  Owner-toggled: whether a cashier's Void/Refund request requires a
--  manager-scanned photo proof before it can be submitted. Default true —
--  preserves the existing "photo required" behavior unless a store opts out.
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS require_void_refund_proof BOOLEAN DEFAULT true;

-- ============================================================
--  Fund Transfer to Manager — cashier hands over cash to the manager
--  mid-shift, with a reason. Reuses the existing `expenses` table (same
--  shape as a cashier-added expense, tagged category='Fund Transfer') so it
--  automatically deducts from the Cash Drawer figure in both "My Activity
--  Today" and the Cash Remittance modal. Owner-toggled, default off —
--  same pattern as "Let cashiers add expenses".
--  Run this block in Supabase -> SQL Editor (once)
-- ============================================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS allow_fund_transfer BOOLEAN DEFAULT false;

-- ============================================================
--  My Wallet (Owner's Dashboard) — no new table needed. It's a view over
--  the store's existing "Deposit to Owner" feature (manager.html's
--  mgrDepositModal -> saveMgrDeposit): cash_remittances rows with
--  status='mgr_remit' (amount as negative cash_on_hand, owner_confirmed
--  flag) plus the linked activity_logs 'MGR_REMIT' entry (details.cr_id)
--  that carries the receipt photo/note, since the remittance row itself
--  doesn't store the photo. Confirming uses the existing
--  confirmMgrDeposit() function already on the dashboard.
-- ============================================================
