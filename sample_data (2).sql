-- =====================================================================
-- Student Voice Portal - sample data (fictional), matches the prototype
-- Run after schema.sql.
-- =====================================================================
USE student_voice_portal;
START TRANSACTION;

-- Demo admin. Password 'Admin123' stored as a bcrypt hash.
INSERT INTO admin_user (admin_id, full_name, email, password_hash) VALUES (1, 'Department Coordinator', 'admin@studentvoice.com', '$2b$10$4ufFdnz9eQQgkcZKfRqxf.aIRi.cKkAFJBM.NZNAgRPj0gZFOljWa');

INSERT INTO staff_member (staff_id, full_name) VALUES
  (1, 'Ahmed Khan'),
  (2, 'Sara Ali'),
  (3, 'Hassan Raza'),
  (4, 'Ayesha Malik');

INSERT INTO complaint_category (category_id, name, display_order) VALUES
  (1, 'Faculty / Teaching', 1),
  (2, 'Course', 2),
  (3, 'Facilities', 3),
  (4, 'Timetable', 4),
  (5, 'Examination', 5),
  (6, 'Student Experience', 6),
  (7, 'Other', 7);

INSERT INTO complaint_option (option_id, category_id, label, description, display_order) VALUES
  (1, 1, 'Teaching quality concern', 'Lectures are hard to follow, poorly prepared or do not cover the topic properly.', 1),
  (2, 1, 'Instructor availability', 'The instructor is hard to reach, misses classes or has no usable office hours.', 2),
  (3, 1, 'Teaching methodology', 'The way the course is taught does not suit the subject, for example no examples or practice.', 3),
  (4, 2, 'Course content issue', 'Topics taught do not match the course outline or are outdated.', 1),
  (5, 2, 'Course material issue', 'Slides, notes or books are missing, shared late or of poor quality.', 2),
  (6, 3, 'Classroom issue', 'Broken furniture, lighting, fans, air conditioning or cleanliness problems in a classroom.', 1),
  (7, 3, 'Laboratory issue', 'Lab computers, equipment or software are not working or not enough for students.', 2),
  (8, 3, 'Equipment issue', 'Projectors, speakers or other teaching equipment are not working.', 3),
  (9, 4, 'Scheduling conflict', 'Two classes, labs or exams are scheduled at the same time.', 1),
  (10, 4, 'Timing issue', 'Class timings are inconvenient, for example too early, too late or with no break in between.', 2),
  (11, 5, 'Examination scheduling', 'Exam dates clash or are announced too late to prepare.', 1),
  (12, 5, 'Examination arrangement', 'Problems with seating, invigilation, question papers or the exam hall.', 2),
  (13, 6, 'General student experience', 'Something about day-to-day student life in the department is not working well.', 1),
  (14, 6, 'Idea to improve student life', 'A suggestion that would make student life in the department better.', 2),
  (15, 7, 'Suggestion for improvement', 'An idea to improve the department that does not fit another category.', 1),
  (16, 7, 'Something not listed here', 'A concern that does not fit any of the categories above.', 2);

INSERT INTO academic_batch (batch_id, batch_year) VALUES
  (1, 2022),
  (2, 2023),
  (3, 2024),
  (4, 2025),
  (5, 2026);

INSERT INTO section (section_id, section_code) VALUES
  (1, 'A'),
  (2, 'B'),
  (3, 'C'),
  (4, 'D');

INSERT INTO student (student_id, registration_no, batch_id, section_id, class_timing) VALUES
  (1, '2023-CS-019', 2, 1, 'Morning'),
  (2, '2023-CS-045', 2, 2, 'Morning'),
  (3, '2022-CS-112', 1, 1, 'Morning'),
  (4, '2024-SE-018', 3, 3, 'Morning'),
  (5, '2023-SE-077', 2, 1, 'Evening'),
  (6, '2024-SE-052', 3, 3, 'Evening'),
  (7, '2025-CS-009', 4, 4, 'Evening'),
  (8, '2022-IT-031', 1, 2, 'Morning'),
  (9, '2024-CS-120', 3, 1, 'Morning'),
  (10, '2023-IT-064', 2, 3, 'Evening'),
  (11, '2022-SE-015', 1, 4, 'Evening'),
  (12, '2024-IT-088', 3, 2, 'Evening'),
  (13, '2025-SE-041', 4, 1, 'Morning');

INSERT INTO complaint (complaint_id, tracking_ref, mode, category_id, option_id, student_id, description, status, assigned_staff_id, submitted_at) VALUES
  (1, 'SVP-G6H2J8', 'Identified', 4, NULL, 13, 'Two lab sessions are scheduled back to back in buildings far apart, leaving no time to move between them.', 'Resolved', 1, '2026-07-22 10:00:00'),
  (2, 'SVP-L3K9T0', 'Identified', 7, NULL, 12, 'The department office closes before evening classes end, so evening students cannot get documents signed during exams.', 'Resolved', 2, '2026-07-30 10:01:00'),
  (3, 'SVP-V8B1X4', 'Anonymous', 3, 7, NULL, NULL, 'Resolved', 3, '2026-08-14 10:02:00'),
  (4, 'SVP-E5U3I1', 'Identified', 1, NULL, 11, 'The instructor for our evening section frequently starts class 20 to 30 minutes late without notice.', 'Resolved', 4, '2026-08-20 10:03:00'),
  (5, 'SVP-N2W6Q8', 'Identified', 7, NULL, 10, 'The department notice board is not updated regularly and some notices are months old.', 'Under Review', 3, '2026-08-28 10:04:00'),
  (6, 'SVP-D7G4Y5', 'Anonymous', 2, 5, NULL, NULL, 'Resolved', 2, '2026-09-05 10:05:00'),
  (7, 'SVP-R1S8T3', 'Identified', 4, NULL, 9, 'Assignment and quiz deadlines from different courses keep falling on the same day because there is no shared schedule.', 'Under Review', 1, '2026-09-10 10:06:00'),
  (8, 'SVP-C9F2A6', 'Anonymous', 6, 13, NULL, NULL, 'Resolved', 4, '2026-09-12 10:07:00'),
  (9, 'SVP-H4J7L9', 'Identified', 3, NULL, 8, 'The projector in Lecture Hall 3 has been flickering for two weeks, making slides hard to read.', 'Resolved', 3, '2026-09-15 10:08:00'),
  (10, 'SVP-Z6M2E7', 'Identified', 6, NULL, 7, 'Department events are announced only a day before, so evening students cannot plan around their classes and miss them.', 'Received', NULL, '2026-09-18 10:09:00'),
  (11, 'SVP-P8V1C4', 'Anonymous', 5, 12, NULL, NULL, 'Rejected', 1, '2026-09-20 10:10:00'),
  (12, 'SVP-B3N6R8', 'Identified', 1, NULL, 6, 'Our instructor''s office hours are only in the morning, so evening students have no time to ask questions outside class.', 'Under Review', 2, '2026-09-22 10:11:00'),
  (13, 'SVP-K5T9W2', 'Identified', 3, NULL, 5, 'The library study area needs more charging points; most desks have no working socket nearby.', 'Resolved', 4, '2026-09-24 10:12:00'),
  (14, 'SVP-2HD8P5', 'Identified', 2, NULL, 4, 'The weekly assignments for this course take far longer than the credit hours suggest and overlap with quizzes.', 'Under Review', 3, '2026-09-25 10:13:00'),
  (15, 'SVP-7QX3M1', 'Anonymous', 4, 9, NULL, NULL, 'Received', NULL, '2026-09-26 10:14:00'),
  (16, 'SVP-91LK20', 'Identified', 5, NULL, 3, 'Two of my mid-term papers were scheduled in the same time slot on the same day, so I could not attend both.', 'Resolved', 2, '2026-09-27 10:15:00'),
  (17, 'SVP-4A72KD', 'Identified', 2, NULL, 2, 'Lecture slides for this course are shared only after the class, so we cannot prepare or follow along during lectures.', 'Received', NULL, '2026-09-28 10:16:00'),
  (18, 'SVP-8F4K29', 'Identified', 3, NULL, 1, 'Several chairs in Room 7 are broken and the ceiling fan makes a loud noise during lectures, making it hard to concentrate.', 'Under Review', 1, '2026-09-29 10:17:00');

INSERT INTO status_history (complaint_id, old_status, new_status, changed_by_admin_id, changed_at) VALUES
  (1, NULL, 'Received', NULL, '2026-07-22 10:00:00'),
  (1, 'Received', 'Under Review', 1, DATE_ADD('2026-07-22 10:00:00', INTERVAL 1 DAY)),
  (1, 'Under Review', 'Resolved', 1, DATE_ADD('2026-07-22 10:00:00', INTERVAL 2 DAY)),
  (2, NULL, 'Received', NULL, '2026-07-30 10:01:00'),
  (2, 'Received', 'Under Review', 1, DATE_ADD('2026-07-30 10:01:00', INTERVAL 1 DAY)),
  (2, 'Under Review', 'Resolved', 1, DATE_ADD('2026-07-30 10:01:00', INTERVAL 2 DAY)),
  (3, NULL, 'Received', NULL, '2026-08-14 10:02:00'),
  (3, 'Received', 'Under Review', 1, DATE_ADD('2026-08-14 10:02:00', INTERVAL 1 DAY)),
  (3, 'Under Review', 'Resolved', 1, DATE_ADD('2026-08-14 10:02:00', INTERVAL 2 DAY)),
  (4, NULL, 'Received', NULL, '2026-08-20 10:03:00'),
  (4, 'Received', 'Under Review', 1, DATE_ADD('2026-08-20 10:03:00', INTERVAL 1 DAY)),
  (4, 'Under Review', 'Resolved', 1, DATE_ADD('2026-08-20 10:03:00', INTERVAL 2 DAY)),
  (5, NULL, 'Received', NULL, '2026-08-28 10:04:00'),
  (5, 'Received', 'Under Review', 1, DATE_ADD('2026-08-28 10:04:00', INTERVAL 1 DAY)),
  (6, NULL, 'Received', NULL, '2026-09-05 10:05:00'),
  (6, 'Received', 'Under Review', 1, DATE_ADD('2026-09-05 10:05:00', INTERVAL 1 DAY)),
  (6, 'Under Review', 'Resolved', 1, DATE_ADD('2026-09-05 10:05:00', INTERVAL 2 DAY)),
  (7, NULL, 'Received', NULL, '2026-09-10 10:06:00'),
  (7, 'Received', 'Under Review', 1, DATE_ADD('2026-09-10 10:06:00', INTERVAL 1 DAY)),
  (8, NULL, 'Received', NULL, '2026-09-12 10:07:00'),
  (8, 'Received', 'Under Review', 1, DATE_ADD('2026-09-12 10:07:00', INTERVAL 1 DAY)),
  (8, 'Under Review', 'Resolved', 1, DATE_ADD('2026-09-12 10:07:00', INTERVAL 2 DAY)),
  (9, NULL, 'Received', NULL, '2026-09-15 10:08:00'),
  (9, 'Received', 'Under Review', 1, DATE_ADD('2026-09-15 10:08:00', INTERVAL 1 DAY)),
  (9, 'Under Review', 'Resolved', 1, DATE_ADD('2026-09-15 10:08:00', INTERVAL 2 DAY)),
  (10, NULL, 'Received', NULL, '2026-09-18 10:09:00'),
  (11, NULL, 'Received', NULL, '2026-09-20 10:10:00'),
  (11, 'Received', 'Under Review', 1, DATE_ADD('2026-09-20 10:10:00', INTERVAL 1 DAY)),
  (11, 'Under Review', 'Rejected', 1, DATE_ADD('2026-09-20 10:10:00', INTERVAL 2 DAY)),
  (12, NULL, 'Received', NULL, '2026-09-22 10:11:00'),
  (12, 'Received', 'Under Review', 1, DATE_ADD('2026-09-22 10:11:00', INTERVAL 1 DAY)),
  (13, NULL, 'Received', NULL, '2026-09-24 10:12:00'),
  (13, 'Received', 'Under Review', 1, DATE_ADD('2026-09-24 10:12:00', INTERVAL 1 DAY)),
  (13, 'Under Review', 'Resolved', 1, DATE_ADD('2026-09-24 10:12:00', INTERVAL 2 DAY)),
  (14, NULL, 'Received', NULL, '2026-09-25 10:13:00'),
  (14, 'Received', 'Under Review', 1, DATE_ADD('2026-09-25 10:13:00', INTERVAL 1 DAY)),
  (15, NULL, 'Received', NULL, '2026-09-26 10:14:00'),
  (16, NULL, 'Received', NULL, '2026-09-27 10:15:00'),
  (16, 'Received', 'Under Review', 1, DATE_ADD('2026-09-27 10:15:00', INTERVAL 1 DAY)),
  (16, 'Under Review', 'Resolved', 1, DATE_ADD('2026-09-27 10:15:00', INTERVAL 2 DAY)),
  (17, NULL, 'Received', NULL, '2026-09-28 10:16:00'),
  (18, NULL, 'Received', NULL, '2026-09-29 10:17:00'),
  (18, 'Received', 'Under Review', 1, DATE_ADD('2026-09-29 10:17:00', INTERVAL 1 DAY));

INSERT INTO resolution_note (complaint_id, admin_id, note_text, created_at) VALUES
  (1, 1, 'The timetable has been revised to add a gap between the two sessions.', DATE_ADD('2026-07-22 10:00:00', INTERVAL 1 DAY)),
  (2, 1, 'Office hours will be extended by one hour during examinations.', DATE_ADD('2026-07-30 10:01:00', INTERVAL 1 DAY)),
  (3, 1, 'Faulty lab computers have been repaired.', DATE_ADD('2026-08-14 10:02:00', INTERVAL 1 DAY)),
  (4, 1, 'The matter has been raised with the instructor and class timings are now being followed.', DATE_ADD('2026-08-20 10:03:00', INTERVAL 1 DAY)),
  (6, 1, 'Updated course material has been uploaded by the instructor.', DATE_ADD('2026-09-05 10:05:00', INTERVAL 1 DAY)),
  (8, 1, 'Your concern has been noted and shared with the student affairs coordinator.', DATE_ADD('2026-09-12 10:07:00', INTERVAL 1 DAY)),
  (9, 1, 'The projector has been replaced by the maintenance team.', DATE_ADD('2026-09-15 10:08:00', INTERVAL 1 DAY)),
  (11, 1, 'This matter is handled by the Examinations Office. Please contact them directly.', DATE_ADD('2026-09-20 10:10:00', INTERVAL 1 DAY)),
  (12, 1, 'We would like to discuss this concern with you in person.', DATE_ADD('2026-09-22 10:11:00', INTERVAL 1 DAY)),
  (13, 1, 'Additional charging points have been requested for the library study area.', DATE_ADD('2026-09-24 10:12:00', INTERVAL 1 DAY)),
  (14, 1, 'The course coordinator has been asked to review the assignment schedule.', DATE_ADD('2026-09-25 10:13:00', INTERVAL 1 DAY)),
  (16, 1, 'Your concern has been reviewed and appropriate action has been taken.', DATE_ADD('2026-09-27 10:15:00', INTERVAL 1 DAY)),
  (18, 1, 'Your complaint has been reviewed and forwarded to the concerned staff member.', DATE_ADD('2026-09-29 10:17:00', INTERVAL 1 DAY));

INSERT INTO meeting (meeting_id, complaint_id, proposed_by_admin_id, meeting_date, meeting_time, location, message, student_response, responded_at, proposed_at) VALUES
  (1, 12, 1, '2026-10-05', '14:00', 'Department Office', 'Please bring your timetable so we can find a suitable slot.', 'Requested Different Time', DATE_ADD('2026-09-22 10:11:00', INTERVAL 3 DAY), DATE_ADD('2026-09-22 10:11:00', INTERVAL 2 DAY)),
  (2, 14, 1, '2026-10-02', '10:00', 'Room 204, Academic Block', 'Please bring your course outline.', 'Confirmed', DATE_ADD('2026-09-25 10:13:00', INTERVAL 3 DAY), DATE_ADD('2026-09-25 10:13:00', INTERVAL 2 DAY)),
  (3, 18, 1, '2026-10-06', '11:30', 'Department Office', 'Please visit the department office to discuss your submission.', 'No Response', NULL, DATE_ADD('2026-09-29 10:17:00', INTERVAL 2 DAY));

INSERT INTO reschedule_request (meeting_id, preferred_date, preferred_time, message, requested_at) VALUES
  (1, '2026-10-07', '12:00', 'I have a lab session at the proposed time.', DATE_ADD('2026-09-22 10:11:00', INTERVAL 3 DAY));

COMMIT;
