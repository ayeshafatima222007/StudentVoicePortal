-- =====================================================================
-- Student Voice Portal - Database Schema
-- Target DBMS : MySQL 8.0.16+ or MariaDB 10.4+ (XAMPP). Tested on MySQL 8.0.46 and MariaDB.
-- Tables      : 12   Views : 5
-- Rule        : records are never hard-deleted. Lookup rows and staff are
--               retired with is_active = FALSE, so all foreign keys RESTRICT.
-- =====================================================================

DROP DATABASE IF EXISTS student_voice_portal;
CREATE DATABASE student_voice_portal
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE student_voice_portal;

-- ---------------------------------------------------------------------
-- 1. Access control
-- ---------------------------------------------------------------------
CREATE TABLE admin_user (
  admin_id        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  full_name       VARCHAR(100)  NOT NULL,
  email           VARCHAR(150)  NOT NULL,
  password_hash   VARCHAR(255)  NOT NULL,                 -- bcrypt/argon2 hash, never plain text
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  last_login_at   DATETIME      NULL,
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_admin_user        PRIMARY KEY (admin_id),
  CONSTRAINT uq_admin_user_email  UNIQUE (email),
  CONSTRAINT chk_admin_email      CHECK (email REGEXP '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$'),
  CONSTRAINT chk_admin_name       CHECK (CHAR_LENGTH(TRIM(full_name)) >= 2)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 2. Reference (lookup) data
-- ---------------------------------------------------------------------
CREATE TABLE staff_member (
  staff_id        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  full_name       VARCHAR(100)  NOT NULL,
  email           VARCHAR(150)  NULL,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_staff_member       PRIMARY KEY (staff_id),
  CONSTRAINT uq_staff_member_name  UNIQUE (full_name),
  CONSTRAINT uq_staff_member_email UNIQUE (email),
  CONSTRAINT chk_staff_name        CHECK (CHAR_LENGTH(TRIM(full_name)) >= 2)
) ENGINE = InnoDB;

CREATE TABLE complaint_category (
  category_id     SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name            VARCHAR(50)   NOT NULL,
  display_order   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_complaint_category   PRIMARY KEY (category_id),
  CONSTRAINT uq_complaint_category   UNIQUE (name)
) ENGINE = InnoDB;

CREATE TABLE complaint_option (
  option_id       SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  category_id     SMALLINT UNSIGNED NOT NULL,
  label           VARCHAR(80)   NOT NULL,
  description     VARCHAR(200)  NOT NULL,                -- fixed text shown to the student
  display_order   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_complaint_option         PRIMARY KEY (option_id),
  CONSTRAINT uq_option_label_in_category UNIQUE (category_id, label),
  CONSTRAINT uq_option_category_pair     UNIQUE (option_id, category_id),  -- target of composite FK
  CONSTRAINT fk_option_category FOREIGN KEY (category_id)
    REFERENCES complaint_category (category_id)
) ENGINE = InnoDB;

CREATE TABLE academic_batch (
  batch_id        SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  batch_year      SMALLINT UNSIGNED NOT NULL,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_academic_batch  PRIMARY KEY (batch_id),
  CONSTRAINT uq_batch_year      UNIQUE (batch_year),
  CONSTRAINT chk_batch_year     CHECK (batch_year BETWEEN 2000 AND 2100)
) ENGINE = InnoDB;

CREATE TABLE section (
  section_id      SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  section_code    VARCHAR(5)    NOT NULL,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_section      PRIMARY KEY (section_id),
  CONSTRAINT uq_section_code UNIQUE (section_code)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 3. Student (identified complaints only - no login, no password)
-- ---------------------------------------------------------------------
CREATE TABLE student (
  student_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  registration_no VARCHAR(13) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  batch_id        SMALLINT UNSIGNED NOT NULL,
  section_id      SMALLINT UNSIGNED NOT NULL,
  class_timing    VARCHAR(10)   NOT NULL,
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_student           PRIMARY KEY (student_id),
  CONSTRAINT uq_student_reg_no    UNIQUE (registration_no),
  CONSTRAINT chk_student_reg_no   CHECK (registration_no REGEXP '^[0-9]{4}-[A-Z]{2,4}-[0-9]{3}$'),
  CONSTRAINT chk_student_timing   CHECK (class_timing IN ('Morning', 'Evening')),
  CONSTRAINT fk_student_batch     FOREIGN KEY (batch_id)   REFERENCES academic_batch (batch_id),
  CONSTRAINT fk_student_section   FOREIGN KEY (section_id) REFERENCES section (section_id)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 4. Complaint (central table)
-- ---------------------------------------------------------------------
CREATE TABLE complaint (
  complaint_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  tracking_ref      CHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  mode              VARCHAR(10)   NOT NULL,
  category_id       SMALLINT UNSIGNED NOT NULL,
  option_id         SMALLINT UNSIGNED NULL,               -- anonymous only
  student_id        INT UNSIGNED  NULL,                   -- identified only
  description       VARCHAR(1000) NULL,                   -- identified only
  status            VARCHAR(15)   NOT NULL DEFAULT 'Received',
  assigned_staff_id INT UNSIGNED  NULL,                   -- NULL = Unassigned
  submitted_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_complaint            PRIMARY KEY (complaint_id),
  CONSTRAINT uq_complaint_tracking   UNIQUE (tracking_ref),
  CONSTRAINT uq_complaint_id_mode    UNIQUE (complaint_id, mode),   -- target of meeting composite FK
  CONSTRAINT chk_complaint_ref       CHECK (tracking_ref REGEXP '^SVP-[A-Z0-9]{6}$'),
  CONSTRAINT chk_complaint_mode      CHECK (mode IN ('Anonymous', 'Identified')),
  CONSTRAINT chk_complaint_status    CHECK (status IN ('Received', 'Under Review', 'Resolved', 'Rejected')),
  CONSTRAINT chk_complaint_desc_len  CHECK (description IS NULL OR CHAR_LENGTH(TRIM(description)) BETWEEN 20 AND 1000),
  -- Anonymity rule: an anonymous complaint carries a predefined option and NO identity or free text;
  -- an identified complaint carries a student and a description and no predefined option.
  CONSTRAINT chk_complaint_mode_fields CHECK (
       (mode = 'Anonymous'  AND option_id IS NOT NULL AND student_id IS NULL     AND description IS NULL)
    OR (mode = 'Identified' AND option_id IS NULL     AND student_id IS NOT NULL AND description IS NOT NULL)
  ),
  CONSTRAINT fk_complaint_category FOREIGN KEY (category_id)
    REFERENCES complaint_category (category_id),
  -- Composite FK: the chosen option must belong to the chosen category.
  CONSTRAINT fk_complaint_option   FOREIGN KEY (option_id, category_id)
    REFERENCES complaint_option (option_id, category_id),
  CONSTRAINT fk_complaint_student  FOREIGN KEY (student_id)
    REFERENCES student (student_id),
  CONSTRAINT fk_complaint_staff    FOREIGN KEY (assigned_staff_id)
    REFERENCES staff_member (staff_id)
) ENGINE = InnoDB;

-- Indexes for the admin queue filters (category, status, type, date range)
CREATE INDEX ix_complaint_status_date   ON complaint (status, submitted_at);
CREATE INDEX ix_complaint_category_date ON complaint (category_id, submitted_at);
CREATE INDEX ix_complaint_mode_date     ON complaint (mode, submitted_at);
CREATE INDEX ix_complaint_submitted     ON complaint (submitted_at);

-- ---------------------------------------------------------------------
-- 5. Resolution & notification history
-- ---------------------------------------------------------------------
CREATE TABLE resolution_note (
  note_id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  complaint_id    INT UNSIGNED  NOT NULL,
  admin_id        INT UNSIGNED  NOT NULL,
  note_text       VARCHAR(500)  NOT NULL,
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_resolution_note   PRIMARY KEY (note_id),
  CONSTRAINT chk_note_len         CHECK (CHAR_LENGTH(TRIM(note_text)) BETWEEN 10 AND 500),
  CONSTRAINT fk_note_complaint    FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id),
  CONSTRAINT fk_note_admin        FOREIGN KEY (admin_id)     REFERENCES admin_user (admin_id)
) ENGINE = InnoDB;
CREATE INDEX ix_note_complaint ON resolution_note (complaint_id, created_at);

CREATE TABLE status_history (
  history_id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  complaint_id        INT UNSIGNED NOT NULL,
  old_status          VARCHAR(15)  NULL,                  -- NULL for the first entry (submission)
  new_status          VARCHAR(15)  NOT NULL,
  changed_by_admin_id INT UNSIGNED NULL,                  -- NULL = recorded by the system at submission
  changed_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_status_history   PRIMARY KEY (history_id),
  CONSTRAINT chk_history_old     CHECK (old_status IS NULL OR old_status IN ('Received', 'Under Review', 'Resolved', 'Rejected')),
  CONSTRAINT chk_history_new     CHECK (new_status IN ('Received', 'Under Review', 'Resolved', 'Rejected')),
  CONSTRAINT chk_history_change  CHECK (old_status IS NULL OR old_status <> new_status),
  CONSTRAINT fk_history_complaint FOREIGN KEY (complaint_id)        REFERENCES complaint (complaint_id),
  CONSTRAINT fk_history_admin     FOREIGN KEY (changed_by_admin_id) REFERENCES admin_user (admin_id)
) ENGINE = InnoDB;
CREATE INDEX ix_history_complaint ON status_history (complaint_id, changed_at);

-- ---------------------------------------------------------------------
-- 6. Meeting scheduling (identified complaints only)
-- ---------------------------------------------------------------------
CREATE TABLE meeting (
  meeting_id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  complaint_id         INT UNSIGNED NOT NULL,
  complaint_mode       VARCHAR(10)  NOT NULL DEFAULT 'Identified',
  proposed_by_admin_id INT UNSIGNED NOT NULL,
  meeting_date         DATE         NOT NULL,
  meeting_time         TIME         NOT NULL,
  location             VARCHAR(100) NOT NULL,
  message              VARCHAR(300) NULL,
  student_response     VARCHAR(30)  NOT NULL DEFAULT 'No Response',
  responded_at         DATETIME     NULL,
  proposed_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_meeting              PRIMARY KEY (meeting_id),
  CONSTRAINT uq_meeting_id_response  UNIQUE (meeting_id, student_response),  -- target of request composite FK
  -- Meetings are for identified complaints only (enforced by the composite FK below).
  CONSTRAINT chk_meeting_identified  CHECK (complaint_mode = 'Identified'),
  CONSTRAINT chk_meeting_location    CHECK (CHAR_LENGTH(TRIM(location)) BETWEEN 3 AND 100),
  CONSTRAINT chk_meeting_response    CHECK (student_response IN ('No Response', 'Confirmed', 'Requested Different Time')),
  CONSTRAINT chk_meeting_responded   CHECK ((student_response = 'No Response') = (responded_at IS NULL)),
  CONSTRAINT fk_meeting_complaint    FOREIGN KEY (complaint_id, complaint_mode)
    REFERENCES complaint (complaint_id, mode),
  CONSTRAINT fk_meeting_admin        FOREIGN KEY (proposed_by_admin_id) REFERENCES admin_user (admin_id)
) ENGINE = InnoDB;
CREATE INDEX ix_meeting_complaint ON meeting (complaint_id, proposed_at);
CREATE INDEX ix_meeting_response  ON meeting (student_response);

CREATE TABLE reschedule_request (
  request_id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  meeting_id       INT UNSIGNED NOT NULL,
  meeting_response VARCHAR(30)  NOT NULL DEFAULT 'Requested Different Time',
  preferred_date   DATE         NOT NULL,
  preferred_time   TIME         NOT NULL,
  message          VARCHAR(300) NULL,
  requested_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_reschedule_request  PRIMARY KEY (request_id),
  CONSTRAINT uq_request_per_meeting UNIQUE (meeting_id),                     -- at most one request per proposal
  -- A request can only exist while the meeting's response is 'Requested Different Time'.
  CONSTRAINT chk_request_response   CHECK (meeting_response = 'Requested Different Time'),
  CONSTRAINT fk_request_meeting     FOREIGN KEY (meeting_id, meeting_response)
    REFERENCES meeting (meeting_id, student_response)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 7. Analytics views (Analytics & Reporting Dashboard)
-- ---------------------------------------------------------------------
CREATE VIEW v_status_summary AS
SELECT status, COUNT(*) AS total,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM complaint), 1) AS percent
FROM complaint GROUP BY status;

CREATE VIEW v_resolution_rate AS
SELECT COUNT(*) AS total_complaints,
       SUM(status = 'Resolved') AS resolved,
       ROUND(100 * SUM(status = 'Resolved') / NULLIF(COUNT(*), 0), 1) AS resolution_rate_percent
FROM complaint;

CREATE VIEW v_category_summary AS
SELECT c.category_id, c.name AS category,
       COUNT(p.complaint_id) AS total,
       COALESCE(SUM(p.status IN ('Received', 'Under Review')), 0) AS open_count,
       COALESCE(SUM(p.status = 'Resolved'), 0) AS resolved,
       ROUND(100 * SUM(p.status = 'Resolved') / NULLIF(COUNT(p.complaint_id), 0), 0) AS resolution_rate_percent
FROM complaint_category c
LEFT JOIN complaint p ON p.category_id = c.category_id
GROUP BY c.category_id, c.name;

CREATE VIEW v_monthly_volume AS
SELECT DATE_FORMAT(submitted_at, '%Y-%m') AS month,
       COUNT(*) AS total,
       SUM(mode = 'Anonymous')  AS anonymous,
       SUM(mode = 'Identified') AS identified
FROM complaint
GROUP BY DATE_FORMAT(submitted_at, '%Y-%m');

CREATE VIEW v_class_timing_summary AS
SELECT s.class_timing, COUNT(*) AS identified_complaints
FROM complaint p JOIN student s ON s.student_id = p.student_id
GROUP BY s.class_timing;
