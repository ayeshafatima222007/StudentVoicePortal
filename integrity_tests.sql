-- =====================================================================
-- Student Voice Portal - integrity tests (v2)
-- Run after schema.sql and sample_data.sql. Works on MySQL 8 and MariaDB (XAMPP).
-- Each test runs inside a transaction that is rolled back, so the sample
-- data is unchanged afterwards. Output: one row per test with PASS/FAIL.
--   expect = 'FAIL' -> the database must REJECT the statement
--   expect = 'OK'   -> the database must ACCEPT the statement(s)
-- Tests C01-C07 additionally check the RESULT of the triggers/procedures.
-- =====================================================================
USE student_voice_portal;

DROP TEMPORARY TABLE IF EXISTS test_result;
CREATE TEMPORARY TABLE test_result (
  test_id   VARCHAR(5),
  rule      VARCHAR(120),
  expected  VARCHAR(4),
  actual    VARCHAR(4),
  outcome   VARCHAR(4),
  db_message VARCHAR(255)
);

DROP PROCEDURE IF EXISTS svp_test;
DROP PROCEDURE IF EXISTS svp_check;
DELIMITER $$
CREATE PROCEDURE svp_test(IN p_id VARCHAR(5), IN p_rule VARCHAR(120), IN p_expect VARCHAR(4),
                          IN p_sql1 TEXT, IN p_sql2 TEXT)
BEGIN
  DECLARE v_failed BOOLEAN DEFAULT FALSE;
  DECLARE v_msg VARCHAR(255) DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    SET v_failed = TRUE;
  END;

  START TRANSACTION;
  SET @svp_sql = p_sql1;
  PREPARE svp_stmt FROM @svp_sql;
  EXECUTE svp_stmt;
  DEALLOCATE PREPARE svp_stmt;
  IF NOT v_failed AND p_sql2 IS NOT NULL THEN
    SET @svp_sql = p_sql2;
    PREPARE svp_stmt FROM @svp_sql;
    EXECUTE svp_stmt;
    DEALLOCATE PREPARE svp_stmt;
  END IF;
  ROLLBACK;

  INSERT INTO test_result VALUES (
    p_id, p_rule, p_expect,
    IF(v_failed, 'FAIL', 'OK'),
    IF((p_expect = 'FAIL') = v_failed, 'PASS', 'FAIL'),
    LEFT(v_msg, 255));
END$$

-- Runs a setup statement, then a "SET @svp_ok = (<condition>)" statement.
-- PASS only if both run without error and the condition is true (1).
CREATE PROCEDURE svp_check(IN p_id VARCHAR(5), IN p_rule VARCHAR(120),
                           IN p_setup TEXT, IN p_check TEXT)
BEGIN
  DECLARE v_failed BOOLEAN DEFAULT FALSE;
  DECLARE v_msg VARCHAR(255) DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    SET v_failed = TRUE;
  END;

  SET @svp_ok = 0;
  START TRANSACTION;
  SET @svp_sql = p_setup;
  PREPARE svp_stmt FROM @svp_sql;
  EXECUTE svp_stmt;
  DEALLOCATE PREPARE svp_stmt;
  IF NOT v_failed THEN
    SET @svp_sql = p_check;
    PREPARE svp_stmt FROM @svp_sql;
    EXECUTE svp_stmt;
    DEALLOCATE PREPARE svp_stmt;
  END IF;
  ROLLBACK;

  INSERT INTO test_result VALUES (
    p_id, p_rule, 'OK',
    IF(v_failed, 'FAIL', 'OK'),
    IF(NOT v_failed AND @svp_ok = 1, 'PASS', 'FAIL'),
    LEFT(v_msg, 255));
END$$
DELIMITER ;

-- ---------------- Anonymity and complaint structure ----------------
CALL svp_test('T01', 'Anonymous complaint cannot store a student', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id, option_id, student_id) VALUES ('SVP-TST001','Anonymous',3,6,1)", NULL);
CALL svp_test('T02', 'Anonymous complaint cannot store free text', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id, option_id, description) VALUES ('SVP-TST002','Anonymous',3,6,'Typed text that could identify the student')", NULL);
CALL svp_test('T03', 'Anonymous complaint must have a predefined option', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id) VALUES ('SVP-TST003','Anonymous',3)", NULL);
CALL svp_test('T04', 'Option must belong to the chosen category', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id, option_id) VALUES ('SVP-TST004','Anonymous',2,6)", NULL);
CALL svp_test('T05', 'Identified complaint must reference a student', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id, description) VALUES ('SVP-TST005','Identified',3,'The projector in Room 9 has not worked for a week.')", NULL);
CALL svp_test('T06', 'Identified complaint cannot use a predefined option', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id, option_id, student_id, description) VALUES ('SVP-TST006','Identified',3,6,1,'The projector in Room 9 has not worked for a week.')", NULL);
CALL svp_test('T07', 'Description needs at least 20 characters', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id, student_id, description) VALUES ('SVP-TST007','Identified',3,1,'Too short text here')", NULL);
CALL svp_test('T08', 'Description cannot be only spaces', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id, student_id, description) VALUES ('SVP-TST008','Identified',3,1,'                          ')", NULL);
CALL svp_test('T09', 'Tracking reference is unique', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id, option_id) VALUES ('SVP-8F4K29','Anonymous',3,6)", NULL);
CALL svp_test('T10', 'Tracking reference format SVP-XXXXXX (uppercase)', 'FAIL',
  "INSERT INTO complaint (tracking_ref, mode, category_id, option_id) VALUES ('svp-abc123','Anonymous',3,6)", NULL);
CALL svp_test('T11', 'Status limited to the four allowed values', 'FAIL',
  "UPDATE complaint SET status = 'Closed' WHERE tracking_ref = 'SVP-8F4K29'", NULL);
CALL svp_test('T12', 'Staff assignment must reference an existing staff member', 'FAIL',
  "UPDATE complaint SET assigned_staff_id = 99 WHERE tracking_ref = 'SVP-8F4K29'", NULL);
CALL svp_test('T13', 'Category in use cannot be deleted', 'FAIL',
  "DELETE FROM complaint_category WHERE name = 'Facilities'", NULL);
CALL svp_test('T29', 'An option in use cannot be moved to another category', 'FAIL',
  "UPDATE complaint_option SET category_id = 2 WHERE option_id = 7", NULL);

-- ---------------- Student details ----------------
CALL svp_test('T14', 'Registration number format YYYY-DEPT-NNN', 'FAIL',
  "INSERT INTO student (registration_no, batch_id, section_id, class_timing) VALUES ('23-cs-45',2,1,'Morning')", NULL);
CALL svp_test('T15', 'Registration number is unique', 'FAIL',
  "INSERT INTO student (registration_no, batch_id, section_id, class_timing) VALUES ('2023-CS-019',2,1,'Morning')", NULL);
CALL svp_test('T16', 'Class timing is Morning or Evening', 'FAIL',
  "INSERT INTO student (registration_no, batch_id, section_id, class_timing) VALUES ('2026-CS-001',5,1,'Night')", NULL);
CALL svp_test('T17', 'Batch must exist in academic_batch', 'FAIL',
  "INSERT INTO student (registration_no, batch_id, section_id, class_timing) VALUES ('2026-CS-001',99,1,'Morning')", NULL);

-- ---------------- Resolution and history ----------------
CALL svp_test('T18', 'Resolution note needs at least 10 characters', 'FAIL',
  "INSERT INTO resolution_note (complaint_id, admin_id, note_text) VALUES (1,1,'Done.')", NULL);
CALL svp_test('T19', 'Status history must record an actual change', 'FAIL',
  "INSERT INTO status_history (complaint_id, old_status, new_status, changed_by_admin_id) VALUES (1,'Resolved','Resolved',1)", NULL);
CALL svp_test('T20', 'Admin email is unique', 'FAIL',
  "INSERT INTO admin_user (full_name, email, password_hash) VALUES ('Second Admin','admin@studentvoice.com','x')", NULL);

-- ---------------- Meetings (identified complaints only) ----------------
CALL svp_test('T21', 'No meeting for an anonymous complaint', 'FAIL',
  "INSERT INTO meeting (complaint_id, proposed_by_admin_id, meeting_date, meeting_time, location) SELECT complaint_id,1,'2026-11-02','10:00:00','Department Office' FROM complaint WHERE tracking_ref = 'SVP-7QX3M1'", NULL);
CALL svp_test('T22', 'Meeting cannot be marked as for an anonymous complaint', 'FAIL',
  "INSERT INTO meeting (complaint_id, complaint_mode, proposed_by_admin_id, meeting_date, meeting_time, location) SELECT complaint_id,'Anonymous',1,'2026-11-02','10:00:00','Department Office' FROM complaint WHERE tracking_ref = 'SVP-7QX3M1'", NULL);
CALL svp_test('T23', 'Identified complaint cannot become anonymous once it has a meeting', 'FAIL',
  "UPDATE complaint SET mode = 'Anonymous' WHERE tracking_ref = 'SVP-8F4K29'", NULL);
CALL svp_test('T24', 'Meeting location needs at least 3 characters', 'FAIL',
  "INSERT INTO meeting (complaint_id, proposed_by_admin_id, meeting_date, meeting_time, location) SELECT complaint_id,1,'2026-11-02','10:00:00','AB' FROM complaint WHERE tracking_ref = 'SVP-4A72KD'", NULL);
CALL svp_test('T25', 'Response other than No Response needs a response time', 'FAIL',
  "UPDATE meeting SET student_response = 'Confirmed', responded_at = NULL WHERE meeting_id = 3", NULL);
CALL svp_test('T26', 'Reschedule request only when the response is Requested Different Time', 'FAIL',
  "INSERT INTO reschedule_request (meeting_id, preferred_date, preferred_time) SELECT meeting_id,'2026-11-05','12:00:00' FROM meeting WHERE student_response = 'No Response' LIMIT 1", NULL);
CALL svp_test('T27', 'Only one reschedule request per meeting', 'FAIL',
  "INSERT INTO reschedule_request (meeting_id, preferred_date, preferred_time) SELECT meeting_id,'2026-11-06','09:00:00' FROM reschedule_request LIMIT 1", NULL);
CALL svp_test('T28', 'Cannot confirm a meeting while a reschedule request is still attached', 'FAIL',
  "UPDATE meeting SET student_response = 'Confirmed', responded_at = NOW() WHERE meeting_id = (SELECT MIN(meeting_id) FROM reschedule_request)", NULL);

-- ---------------- Stored procedures must reject bad calls ----------------
CALL svp_test('T30', 'sp_change_status rejects an unchanged status', 'FAIL',
  "CALL sp_change_status(18,'Under Review',1,NULL,NULL)", NULL);
CALL svp_test('T31', 'sp_change_status rejects an invalid status', 'FAIL',
  "CALL sp_change_status(18,'Closed',1,NULL,NULL)", NULL);
CALL svp_test('T32', 'sp_change_status rejects an unknown complaint', 'FAIL',
  "CALL sp_change_status(9999,'Resolved',1,NULL,NULL)", NULL);
CALL svp_test('T33', 'sp_request_reschedule rejects a meeting that is already answered', 'FAIL',
  "CALL sp_request_reschedule(2,'2026-11-05','12:00:00','Clash')", NULL);
CALL svp_test('T34', 'sp_confirm_meeting rejects an already confirmed meeting', 'FAIL',
  "CALL sp_confirm_meeting(2)", NULL);

-- ---------------- Valid operations must be accepted ----------------
CALL svp_test('P01', 'Valid anonymous complaint is accepted', 'OK',
  "INSERT INTO complaint (tracking_ref, mode, category_id, option_id) VALUES ('SVP-TSTP01','Anonymous',3,6)", NULL);
CALL svp_test('P02', 'Valid identified complaint is accepted', 'OK',
  "INSERT INTO complaint (tracking_ref, mode, category_id, student_id, description) VALUES ('SVP-TSTP02','Identified',3,1,'The projector in Room 9 has not worked for a week.')", NULL);
CALL svp_test('P03', 'Valid meeting on an identified complaint is accepted', 'OK',
  "INSERT INTO meeting (complaint_id, proposed_by_admin_id, meeting_date, meeting_time, location) SELECT complaint_id,1,'2026-11-02','10:00:00','Department Office' FROM complaint WHERE tracking_ref = 'SVP-4A72KD'", NULL);
CALL svp_test('P04', 'Plain status update is accepted (history written by trigger)', 'OK',
  "UPDATE complaint SET status = 'Resolved' WHERE complaint_id = 18", NULL);
CALL svp_test('P05', 'Student requests a different time (response first, then request)', 'OK',
  "UPDATE meeting SET student_response = 'Requested Different Time', responded_at = NOW() WHERE student_response = 'No Response' LIMIT 1",
  "INSERT INTO reschedule_request (meeting_id, preferred_date, preferred_time, message) SELECT meeting_id,'2026-11-05','12:00:00','I have a lab at that time.' FROM meeting m WHERE student_response = 'Requested Different Time' AND NOT EXISTS (SELECT 1 FROM reschedule_request r WHERE r.meeting_id = m.meeting_id) LIMIT 1");
CALL svp_test('P06', 'Student confirms after withdrawing the request', 'OK',
  "DELETE FROM reschedule_request WHERE meeting_id = 1",
  "UPDATE meeting SET student_response = 'Confirmed', responded_at = NOW() WHERE meeting_id = 1");
CALL svp_test('P07', 'Staff member is assigned', 'OK',
  "UPDATE complaint SET assigned_staff_id = 2 WHERE tracking_ref = 'SVP-4A72KD'", NULL);
CALL svp_test('P08', 'Two complaints without tracking_ref both get unique references', 'OK',
  "INSERT INTO complaint (mode, category_id, option_id) VALUES ('Anonymous',3,6),('Anonymous',3,7)", NULL);

-- ---------------- Triggers and procedures: check the RESULT ----------------
CALL svp_check('C01', 'Every complaint has its initial history row (trigger)',
  "SET @svp_dummy = 1",
  "SET @svp_ok = (SELECT COUNT(*) = 0 FROM complaint c WHERE NOT EXISTS (SELECT 1 FROM status_history h WHERE h.complaint_id = c.complaint_id AND h.old_status IS NULL AND h.new_status = 'Received'))");
CALL svp_check('C02', 'New complaint without tracking_ref gets a valid generated one',
  "INSERT INTO complaint (mode, category_id, option_id) VALUES ('Anonymous',3,6)",
  "SET @svp_ok = (SELECT COUNT(*) = 1 FROM complaint WHERE complaint_id = LAST_INSERT_ID() AND tracking_ref REGEXP '^SVP-[A-Z0-9]{6}$' AND tracking_ref <> 'SVP-000000')");
CALL svp_check('C03', 'New complaint automatically gets a Received history row',
  "INSERT INTO complaint (mode, category_id, option_id) VALUES ('Anonymous',3,6)",
  "SET @svp_ok = (SELECT COUNT(*) = 1 FROM status_history WHERE complaint_id = LAST_INSERT_ID() AND old_status IS NULL AND new_status = 'Received')");
CALL svp_check('C04', 'Status update automatically writes a history row (trigger)',
  "UPDATE complaint SET status = 'Resolved' WHERE complaint_id = 18",
  "SET @svp_ok = (SELECT COUNT(*) = 1 FROM status_history WHERE complaint_id = 18 AND old_status = 'Under Review' AND new_status = 'Resolved')");
CALL svp_check('C05', 'sp_change_status writes history (with admin), staff and note',
  "CALL sp_change_status(18,'Resolved',1,2,'Issue fixed and verified by staff.')",
  "SET @svp_ok = (SELECT (SELECT COUNT(*) FROM status_history WHERE complaint_id = 18 AND new_status = 'Resolved' AND changed_by_admin_id = 1) = 1 AND (SELECT assigned_staff_id FROM complaint WHERE complaint_id = 18) = 2 AND (SELECT COUNT(*) FROM resolution_note WHERE complaint_id = 18 AND note_text = 'Issue fixed and verified by staff.') = 1)");
CALL svp_check('C06', 'sp_request_reschedule sets the response and stores the request',
  "CALL sp_request_reschedule(3,'2026-11-05','12:00:00','Lab clash.')",
  "SET @svp_ok = (SELECT (SELECT student_response FROM meeting WHERE meeting_id = 3) = 'Requested Different Time' AND (SELECT COUNT(*) FROM reschedule_request WHERE meeting_id = 3) = 1)");
CALL svp_check('C07', 'sp_confirm_meeting removes the request and confirms',
  "CALL sp_confirm_meeting(1)",
  "SET @svp_ok = (SELECT (SELECT student_response FROM meeting WHERE meeting_id = 1) = 'Confirmed' AND (SELECT COUNT(*) FROM reschedule_request WHERE meeting_id = 1) = 0)");

DROP PROCEDURE svp_test;
DROP PROCEDURE svp_check;

-- Summary first, then one row per test (shown last so phpMyAdmin displays it).
SELECT COUNT(*) AS tests, SUM(outcome = 'PASS') AS passed, SUM(outcome = 'FAIL') AS failed FROM test_result;
SELECT test_id, rule, expected, actual, outcome, db_message FROM test_result;