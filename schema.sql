-- =====================================================================
-- Student Voice Portal - Database Schema (v2, FastAPI-ready)
-- Target DBMS : MySQL 8.0.16+ or MariaDB 10.4+ (XAMPP).
-- Tables      : 12   Views : 5   Triggers : 3   Procedures : 3
-- Rule        : records are never hard-deleted. Lookup rows and staff are
--               retired with is_active = FALSE, so all foreign keys RESTRICT.
--
-- SAFE TO RE-RUN: this file no longer drops the database. Existing tables
-- and data are kept (CREATE ... IF NOT EXISTS). Triggers, procedures and
-- views are re-created. To wipe everything, run the line below manually:
--   DROP DATABASE IF EXISTS student_voice_portal;
--
-- What the database now does by itself (no longer FastAPI's job):
--   * tracking_ref is auto-generated (SVP-XXXXXX, unique) if not supplied
--   * first status_history row ('Received') is written on complaint insert
--   * every status change on complaint writes a status_history row
--   * sp_change_status / sp_request_reschedule / sp_confirm_meeting wrap the
--     multi-step workflows in one call
-- =====================================================================

CREATE DATABASE IF NOT EXISTS student_voice_portal
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE student_voice_portal;

-- ---------------------------------------------------------------------
-- 1. Access control
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_user (
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
CREATE TABLE IF NOT EXISTS staff_member (
  staff_id        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  full_name       VARCHAR(100)  NOT NULL,
  email           VARCHAR(150)  NULL,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_staff_member       PRIMARY KEY (staff_id),
  CONSTRAINT uq_staff_member_name  UNIQUE (full_name),
  CONSTRAINT uq_staff_member_email UNIQUE (email),
  CONSTRAINT chk_staff_name        CHECK (CHAR_LENGTH(TRIM(full_name)) >= 2)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS complaint_category (
  category_id     SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name            VARCHAR(50)   NOT NULL,
  display_order   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_complaint_category   PRIMARY KEY (category_id),
  CONSTRAINT uq_complaint_category   UNIQUE (name)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS complaint_option (
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

CREATE TABLE IF NOT EXISTS academic_batch (
  batch_id        SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  batch_year      SMALLINT UNSIGNED NOT NULL,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_academic_batch  PRIMARY KEY (batch_id),
  CONSTRAINT uq_batch_year      UNIQUE (batch_year),
  CONSTRAINT chk_batch_year     CHECK (batch_year BETWEEN 2000 AND 2100)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS section (
  section_id      SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  section_code    VARCHAR(5)    NOT NULL,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_section      PRIMARY KEY (section_id),
  CONSTRAINT uq_section_code UNIQUE (section_code)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 3. Student (identified complaints only - no login, no password)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student (
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
-- tracking_ref has the placeholder default 'SVP-000000'. The BEFORE INSERT
-- trigger below replaces it with a unique random reference, so the
-- application can simply omit tracking_ref when inserting.
CREATE TABLE IF NOT EXISTS complaint (
  complaint_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  tracking_ref      CHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'SVP-000000',
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
    REFERENCES staff_member (staff_id),
  -- Indexes for the admin queue filters (category, status, type, date range)
  INDEX ix_complaint_status_date   (status, submitted_at),
  INDEX ix_complaint_category_date (category_id, submitted_at),
  INDEX ix_complaint_mode_date     (mode, submitted_at),
  INDEX ix_complaint_submitted     (submitted_at)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 5. Resolution & notification history
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS resolution_note (
  note_id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  complaint_id    INT UNSIGNED  NOT NULL,
  admin_id        INT UNSIGNED  NOT NULL,
  note_text       VARCHAR(500)  NOT NULL,
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_resolution_note   PRIMARY KEY (note_id),
  CONSTRAINT chk_note_len         CHECK (CHAR_LENGTH(TRIM(note_text)) BETWEEN 10 AND 500),
  CONSTRAINT fk_note_complaint    FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id),
  CONSTRAINT fk_note_admin        FOREIGN KEY (admin_id)     REFERENCES admin_user (admin_id),
  INDEX ix_note_complaint (complaint_id, created_at)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS status_history (
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
  CONSTRAINT fk_history_admin     FOREIGN KEY (changed_by_admin_id) REFERENCES admin_user (admin_id),
  INDEX ix_history_complaint (complaint_id, changed_at)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 6. Meeting scheduling (identified complaints only)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS meeting (
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
  CONSTRAINT fk_meeting_admin        FOREIGN KEY (proposed_by_admin_id) REFERENCES admin_user (admin_id),
  INDEX ix_meeting_complaint (complaint_id, proposed_at),
  INDEX ix_meeting_response  (student_response)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS reschedule_request (
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
-- 7. Analytics views (read-only; use them for the dashboard endpoints)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_status_summary AS
SELECT status, COUNT(*) AS total,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM complaint), 1) AS percent
FROM complaint GROUP BY status;

CREATE OR REPLACE VIEW v_resolution_rate AS
SELECT COUNT(*) AS total_complaints,
       SUM(status = 'Resolved') AS resolved,
       ROUND(100 * SUM(status = 'Resolved') / NULLIF(COUNT(*), 0), 1) AS resolution_rate_percent
FROM complaint;

CREATE OR REPLACE VIEW v_category_summary AS
SELECT c.category_id, c.name AS category,
       COUNT(p.complaint_id) AS total,
       COALESCE(SUM(p.status IN ('Received', 'Under Review')), 0) AS open_count,
       COALESCE(SUM(p.status = 'Resolved'), 0) AS resolved,
       ROUND(100 * SUM(p.status = 'Resolved') / NULLIF(COUNT(p.complaint_id), 0), 0) AS resolution_rate_percent
FROM complaint_category c
LEFT JOIN complaint p ON p.category_id = c.category_id
GROUP BY c.category_id, c.name;

CREATE OR REPLACE VIEW v_monthly_volume AS
SELECT DATE_FORMAT(submitted_at, '%Y-%m') AS month,
       COUNT(*) AS total,
       SUM(mode = 'Anonymous')  AS anonymous,
       SUM(mode = 'Identified') AS identified
FROM complaint
GROUP BY DATE_FORMAT(submitted_at, '%Y-%m');

CREATE OR REPLACE VIEW v_class_timing_summary AS
SELECT s.class_timing, COUNT(*) AS identified_complaints
FROM complaint p JOIN student s ON s.student_id = p.student_id
GROUP BY s.class_timing;

-- ---------------------------------------------------------------------
-- 8. Triggers
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_complaint_bi;
DROP TRIGGER IF EXISTS trg_complaint_ai;
DROP TRIGGER IF EXISTS trg_complaint_au;

DELIMITER $$

-- 8.1 Auto-generate a unique tracking reference (SVP- + 6 uppercase letters/digits)
CREATE TRIGGER trg_complaint_bi BEFORE INSERT ON complaint
FOR EACH ROW
BEGIN
  DECLARE v_ref   CHAR(10) CHARACTER SET ascii COLLATE ascii_bin;
  DECLARE v_chars CHAR(36) CHARACTER SET ascii DEFAULT 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  DECLARE v_i     INT;

  IF NEW.tracking_ref = 'SVP-000000' THEN
    SET v_ref = 'SVP-000000';
    WHILE v_ref = 'SVP-000000'
          OR EXISTS (SELECT 1 FROM complaint WHERE tracking_ref = v_ref) DO
      SET v_ref = 'SVP-';
      SET v_i = 0;
      WHILE v_i < 6 DO
        SET v_ref = CONCAT(v_ref, SUBSTRING(v_chars, FLOOR(1 + RAND() * 36), 1));
        SET v_i = v_i + 1;
      END WHILE;
    END WHILE;
    SET NEW.tracking_ref = v_ref;
  END IF;
END$$

-- 8.2 First history row ('Received') is written when a complaint is submitted
CREATE TRIGGER trg_complaint_ai AFTER INSERT ON complaint
FOR EACH ROW
BEGIN
  INSERT INTO status_history (complaint_id, old_status, new_status, changed_by_admin_id, changed_at)
  VALUES (NEW.complaint_id, NULL, NEW.status, NULL, NEW.submitted_at);
END$$

-- 8.3 Every status change is recorded. The application sets
--     SET @current_admin_id = <admin_id>;  before updating the status
--     (sp_change_status does this for you). NULL = recorded by the system.
CREATE TRIGGER trg_complaint_au AFTER UPDATE ON complaint
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO status_history (complaint_id, old_status, new_status, changed_by_admin_id)
    VALUES (NEW.complaint_id, OLD.status, NEW.status, @current_admin_id);
  END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- 9. Stored procedures (call them inside the application's transaction)
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_change_status;
DROP PROCEDURE IF EXISTS sp_request_reschedule;
DROP PROCEDURE IF EXISTS sp_confirm_meeting;

DELIMITER $$

-- 9.1 Change status (+ optional staff assignment and resolution note) in one call.
--     p_staff_id NULL = keep current assignment; p_note NULL = no note.
--     The status_history row is written by trigger trg_complaint_au.
CREATE PROCEDURE sp_change_status(
  IN p_complaint_id INT UNSIGNED,
  IN p_new_status   VARCHAR(15),
  IN p_admin_id     INT UNSIGNED,
  IN p_staff_id     INT UNSIGNED,
  IN p_note         VARCHAR(500))
BEGIN
  DECLARE v_old VARCHAR(15) DEFAULT NULL;

  SELECT status INTO v_old FROM complaint WHERE complaint_id = p_complaint_id FOR UPDATE;
  IF v_old IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Complaint not found';
  END IF;
  IF v_old = p_new_status THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status is unchanged';
  END IF;

  SET @current_admin_id = p_admin_id;
  UPDATE complaint
     SET status = p_new_status,
         assigned_staff_id = COALESCE(p_staff_id, assigned_staff_id)
   WHERE complaint_id = p_complaint_id;
  SET @current_admin_id = NULL;

  IF p_note IS NOT NULL THEN
    INSERT INTO resolution_note (complaint_id, admin_id, note_text)
    VALUES (p_complaint_id, p_admin_id, p_note);
  END IF;
END$$

-- 9.2 Student asks for a different time: sets the response first, then
--     inserts the request (the order the composite FK requires).
CREATE PROCEDURE sp_request_reschedule(
  IN p_meeting_id INT UNSIGNED,
  IN p_date       DATE,
  IN p_time       TIME,
  IN p_message    VARCHAR(300))
BEGIN
  UPDATE meeting
     SET student_response = 'Requested Different Time', responded_at = NOW()
   WHERE meeting_id = p_meeting_id AND student_response = 'No Response';
  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Meeting not found or already answered';
  END IF;

  INSERT INTO reschedule_request (meeting_id, preferred_date, preferred_time, message)
  VALUES (p_meeting_id, p_date, p_time, p_message);
END$$

-- 9.3 Student confirms the meeting: removes any attached reschedule request
--     first (a confirmed meeting cannot keep one), then confirms.
CREATE PROCEDURE sp_confirm_meeting(IN p_meeting_id INT UNSIGNED)
BEGIN
  DELETE FROM reschedule_request WHERE meeting_id = p_meeting_id;

  UPDATE meeting
     SET student_response = 'Confirmed', responded_at = NOW()
   WHERE meeting_id = p_meeting_id AND student_response <> 'Confirmed';
  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Meeting not found or already confirmed';
  END IF;
END$$

DELIMITER ;