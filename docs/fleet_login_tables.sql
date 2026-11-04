-- =====================================================================
-- Fleet Management: login / access tables (staff, drivers, admins only)
-- PostgreSQL. Everything lives in the "data" schema, nothing in public.
-- Customers (data.customers, data.customer_users) are NOT included.
-- Run once on an empty database. Sample data is at the bottom.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS data;

-- ---------------------------------------------------------------------
-- 1. branches
-- ---------------------------------------------------------------------
CREATE TABLE data.branches (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code           VARCHAR(20)   NOT NULL UNIQUE,
    name           VARCHAR(100)  NOT NULL,
    address        VARCHAR(255),
    city           VARCHAR(100),
    region         VARCHAR(100),
    latitude       DECIMAL(9,6),
    longitude      DECIMAL(9,6),
    contact_number VARCHAR(30),
    is_active      BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- 2. users  (username = email, password = password_hash)
-- ---------------------------------------------------------------------
CREATE TABLE data.users (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id     BIGINT REFERENCES data.branches (id),      -- NULL = head office / global
    type          VARCHAR(20)  NOT NULL
                  CHECK (type IN ('staff', 'driver', 'admin')),
    first_name    VARCHAR(100) NOT NULL,
    last_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(150) NOT NULL,
    phone         VARCHAR(30),
    password_hash VARCHAR(255) NOT NULL,                     -- bcrypt/argon2, never plain text
    status        VARCHAR(20)  NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'inactive', 'suspended')),
    last_login_at TIMESTAMP,
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Case-insensitive unique email. The login query uses LOWER(email) = LOWER($1),
-- so this index makes it fast and also stops "Admin@x.com" / "admin@x.com" duplicates.
CREATE UNIQUE INDEX users_email_lower_uq ON data.users (LOWER(email));
CREATE INDEX users_branch_id_idx ON data.users (branch_id);

-- ---------------------------------------------------------------------
-- 3. roles
-- ---------------------------------------------------------------------
CREATE TABLE data.roles (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL UNIQUE,
    description VARCHAR(255),
    is_system   BOOLEAN      NOT NULL DEFAULT FALSE,         -- TRUE = built-in, cannot be deleted
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- 4. permissions  (code = module.action, checked in code)
-- ---------------------------------------------------------------------
CREATE TABLE data.permissions (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    module      VARCHAR(50)  NOT NULL,
    action      VARCHAR(30)  NOT NULL,
    code        VARCHAR(100) NOT NULL UNIQUE,
    description VARCHAR(255),
    UNIQUE (module, action)
);

-- ---------------------------------------------------------------------
-- 5. role_permissions
-- ---------------------------------------------------------------------
CREATE TABLE data.role_permissions (
    role_id       BIGINT NOT NULL REFERENCES data.roles (id)       ON DELETE CASCADE,
    permission_id BIGINT NOT NULL REFERENCES data.permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);
CREATE INDEX role_permissions_permission_idx ON data.role_permissions (permission_id);

-- ---------------------------------------------------------------------
-- 6. user_roles  (branch_id limits the role to one branch; NULL = all)
-- ---------------------------------------------------------------------
CREATE TABLE data.user_roles (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT    NOT NULL REFERENCES data.users (id)    ON DELETE CASCADE,
    role_id     BIGINT    NOT NULL REFERENCES data.roles (id),
    branch_id   BIGINT    REFERENCES data.branches (id),
    assigned_at TIMESTAMP NOT NULL DEFAULT NOW()
);
-- Same role cannot be given twice for the same branch (COALESCE because NULLs are
-- treated as distinct by a plain UNIQUE constraint).
CREATE UNIQUE INDEX user_roles_uq ON data.user_roles (user_id, role_id, COALESCE(branch_id, 0));
CREATE INDEX user_roles_user_idx ON data.user_roles (user_id);

-- ---------------------------------------------------------------------
-- 7. user_permissions  (per-user grant or deny; deny wins over role)
-- ---------------------------------------------------------------------
CREATE TABLE data.user_permissions (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT  NOT NULL REFERENCES data.users (id)       ON DELETE CASCADE,
    permission_id BIGINT  NOT NULL REFERENCES data.permissions (id) ON DELETE CASCADE,
    is_granted    BOOLEAN NOT NULL,                          -- TRUE = extra grant, FALSE = explicit deny
    UNIQUE (user_id, permission_id)
);

-- ---------------------------------------------------------------------
-- 8. drivers  (extra details for users who drive)
-- ---------------------------------------------------------------------
CREATE TABLE data.drivers (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        BIGINT      NOT NULL UNIQUE REFERENCES data.users (id) ON DELETE CASCADE,
    license_number VARCHAR(50) NOT NULL UNIQUE,
    license_class  VARCHAR(20),
    license_expiry DATE        NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'available'
                   CHECK (status IN ('available', 'on_trip', 'off_duty'))
);

-- ---------------------------------------------------------------------
-- 9. audit_logs  (login, create, update, delete ...)
-- Note: customer_user_id is left out because customer tables are not created
-- here. Add it later with ALTER TABLE when data.customer_users exists.
-- ---------------------------------------------------------------------
CREATE TABLE data.audit_logs (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT REFERENCES data.users (id) ON DELETE SET NULL,  -- NULL = system action
    action     VARCHAR(30) NOT NULL,                                  -- create, update, delete, login ...
    table_name VARCHAR(50) NOT NULL,                                  -- without schema, e.g. users
    record_id  BIGINT,
    changes    JSONB,                                                 -- before/after values
    created_at TIMESTAMP   NOT NULL DEFAULT NOW()
);
CREATE INDEX audit_logs_user_created_idx  ON data.audit_logs (user_id, created_at DESC);
CREATE INDEX audit_logs_table_record_idx  ON data.audit_logs (table_name, record_id);

-- ---------------------------------------------------------------------
-- updated_at trigger for branches and users
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION data.set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER branches_set_updated_at BEFORE UPDATE ON data.branches
    FOR EACH ROW EXECUTE FUNCTION data.set_updated_at();
CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON data.users
    FOR EACH ROW EXECUTE FUNCTION data.set_updated_at();


-- =====================================================================
-- SAMPLE DATA (small on purpose)
-- Inserts use names/codes/emails to find ids, so no ids are hard-coded.
-- =====================================================================

-- pgcrypto is used ONLY to create bcrypt hashes for the sample passwords below.
-- In the real app, hash passwords in code (bcrypt/argon2) and do not use this.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Branches ------------------------------------------------------------
INSERT INTO data.branches (code, name, city, region, latitude, longitude, contact_number) VALUES
    ('QC-01',  'Quezon City Main Depot', 'Quezon City', 'NCR', 14.676000, 121.043700, '+63 2 8000 0001'),
    ('MNL-01', 'Manila Depot',           'Manila',      'NCR', 14.599500, 120.984200, '+63 2 8000 0002');

-- Roles ---------------------------------------------------------------
INSERT INTO data.roles (name, description, is_system) VALUES
    ('Super Admin',    'Full access to every branch and setting.',                                     TRUE),
    ('Branch Manager', 'Manages vehicles, trips, staff and reports for own branch.',                   TRUE),
    ('Dispatcher',     'Creates orders and trips, assigns drivers and vehicles.',                      TRUE),
    ('Mechanic',       'Handles maintenance records and vehicle status.',                              TRUE),
    ('Driver',         'Sees own trips, updates trip status, logs fuel, uploads proof of delivery.',   TRUE);

-- Permissions (a starter subset; add the rest of the matrix as modules are built)
INSERT INTO data.permissions (module, action, code, description) VALUES
    ('users',           'view',          'users.view',             'View user list'),
    ('users',           'create',        'users.create',           'Create user accounts'),
    ('users',           'update',        'users.update',           'Edit user accounts'),
    ('users',           'delete',        'users.delete',           'Deactivate/delete users'),
    ('roles',           'manage',        'roles.manage',           'Create roles and assign permissions'),
    ('vehicles',        'view',          'vehicles.view',          'View vehicles'),
    ('vehicles',        'create',        'vehicles.create',        'Add vehicles'),
    ('vehicles',        'update',        'vehicles.update',        'Edit vehicle details'),
    ('trips',           'view',          'trips.view',             'View trips'),
    ('trips',           'create',        'trips.create',           'Create/dispatch trips'),
    ('trips',           'assign',        'trips.assign',           'Assign vehicle and driver'),
    ('trips',           'update_status', 'trips.update_status',    'Start/complete trips'),
    ('delivery_proofs', 'create',        'delivery_proofs.create', 'Upload proof of delivery'),
    ('fuel_logs',       'create',        'fuel_logs.create',       'Log fuel');

-- Role -> permissions -------------------------------------------------
-- Super Admin gets every permission.
INSERT INTO data.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM data.roles r
CROSS JOIN data.permissions p
WHERE r.name = 'Super Admin';

-- Other roles get the codes listed for them.
INSERT INTO data.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM data.roles r
JOIN data.permissions p
  ON p.code = ANY (
       CASE r.name
         WHEN 'Branch Manager' THEN ARRAY['users.view','users.create','users.update',
                                          'vehicles.view','vehicles.create','vehicles.update',
                                          'trips.view','trips.create','trips.assign','trips.update_status']
         WHEN 'Dispatcher'     THEN ARRAY['vehicles.view','trips.view','trips.create',
                                          'trips.assign','trips.update_status']
         WHEN 'Mechanic'       THEN ARRAY['vehicles.view','vehicles.update']
         WHEN 'Driver'         THEN ARRAY['vehicles.view','trips.view','trips.update_status',
                                          'delivery_proofs.create','fuel_logs.create']
         ELSE ARRAY[]::text[]
       END)
WHERE r.name <> 'Super Admin';

-- Users (sample password for all four: Password123!  -> change after first login)
INSERT INTO data.users (branch_id, type, first_name, last_name, email, phone, password_hash) VALUES
    (NULL,
     'admin', 'Ana',  'Reyes',  'admin@fleet.test',      '+63 917 000 0001',
     crypt('Password123!', gen_salt('bf', 10))),
    ((SELECT id FROM data.branches WHERE code = 'QC-01'),
     'staff', 'Marco', 'Santos', 'manager@fleet.test',    '+63 917 000 0002',
     crypt('Password123!', gen_salt('bf', 10))),
    ((SELECT id FROM data.branches WHERE code = 'QC-01'),
     'staff', 'Liza',  'Cruz',   'dispatcher@fleet.test', '+63 917 000 0003',
     crypt('Password123!', gen_salt('bf', 10))),
    ((SELECT id FROM data.branches WHERE code = 'QC-01'),
     'driver','Jun',   'Dela Cruz','driver@fleet.test',   '+63 917 000 0004',
     crypt('Password123!', gen_salt('bf', 10)));

-- User -> roles (admin has no branch limit = all branches) -------------
INSERT INTO data.user_roles (user_id, role_id, branch_id)
SELECT u.id, r.id, b.id
FROM (VALUES
        ('admin@fleet.test',      'Super Admin',    NULL),
        ('manager@fleet.test',    'Branch Manager', 'QC-01'),
        ('dispatcher@fleet.test', 'Dispatcher',     'QC-01'),
        ('driver@fleet.test',     'Driver',         'QC-01')
     ) AS v(email, role_name, branch_code)
JOIN data.users u ON u.email = v.email
JOIN data.roles r ON r.name  = v.role_name
LEFT JOIN data.branches b ON b.code = v.branch_code;

-- Driver details ------------------------------------------------------
INSERT INTO data.drivers (user_id, license_number, license_class, license_expiry)
SELECT id, 'N01-23-456789', 'B', DATE '2028-06-30'
FROM data.users WHERE email = 'driver@fleet.test';

-- Per-user overrides (two examples) -----------------------------------
--   dispatcher: extra grant  -> may also view the user list
--   manager:    explicit deny -> cannot create users even though the role allows it
INSERT INTO data.user_permissions (user_id, permission_id, is_granted)
SELECT u.id, p.id, v.is_granted
FROM (VALUES
        ('dispatcher@fleet.test', 'users.view',   TRUE),
        ('manager@fleet.test',    'users.create', FALSE)
     ) AS v(email, code, is_granted)
JOIN data.users u       ON u.email = v.email
JOIN data.permissions p ON p.code  = v.code;

-- One sample audit row ------------------------------------------------
INSERT INTO data.audit_logs (user_id, action, table_name, record_id)
SELECT id, 'login', 'users', id FROM data.users WHERE email = 'admin@fleet.test';

-- =====================================================================
-- Quick checks
--   SELECT email, type, status FROM data.users;
--   -- effective permissions of the manager (should NOT include users.create):
--   -- run query 3 from the login guide with that user's id.
-- =====================================================================
