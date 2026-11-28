# Student Voice Portal — API Decisions

**Status:** Sprint 7 contract proposal for team adoption
**Backend framework:** FastAPI (official project choice)
**API version:** v1
**Base path:** `/api/v1`
**Canonical specification:** `openapi.yaml`
**Generated mirror:** `openapi.json` (do not edit manually)

This document prevents developers and AI assistants from independently interpreting
ambiguous backlog wording. Implementations must follow the canonical OpenAPI file
and these decisions. If a decision is changed, update both documents in the same PR.

## 1. Source-of-truth rules

The backlog CSV is a planning artefact and useful traceability input, but it is not
an infallible technical specification. A typo, missing route name, or contradiction
in the CSV must be raised and resolved rather than copied into code automatically.

Use the following order when sources conflict:

1. Instructor-approved requirements and decisions made by the project team.
2. This agreed API contract (`openapi.yaml`) and this decision record.
3. Verified database schema and documented project behaviour.
4. Backlog CSV wording, where it is complete and consistent.
5. AI-generated output or assumptions (never authoritative by themselves).

A developer must not silently invent or rename endpoints, fields, status values,
validation rules, or authentication behaviour. Report conflicts in the PR.

## 2. Adopted API decisions

These are the decisions recommended by the US-05 author for the whole team to adopt.
They are not represented as instructor-approved until the instructor/project owner
has explicitly accepted them.

| ID | Area | Decision | Rationale / implementation rule |
|---|---|---|---|
| ADR-001 | Framework | FastAPI | This is the officially selected backend framework. Do not generate Express routes. |
| ADR-002 | Staff assignment | `PATCH /admin/complaints/{complaintId}/assignment` | The backlog's `PATCH /staff` does not identify the complaint. The resource-scoped route makes the target explicit. Body: `{"staff_id": 12}`; use `null` to unassign. |
| ADR-003 | Resolution notes | `POST /admin/complaints/{complaintId}/notes` | A note belongs to a complaint. Nesting makes the parent relationship explicit. Body: `{"note_text": "..."}`; 10–500 non-whitespace characters. The author and timestamp come from the authenticated server context. |
| ADR-004 | Meeting date/time | The combined local date/time must be strictly later than the current time. | Today is permitted only when the requested time has not passed. Apply this to administrator proposals and student reschedule requests. This is more precise than checking the date alone and avoids meetings being created for a time earlier today. |
| ADR-005 | Timezone | Use one explicit application/campus timezone for meeting date/time comparisons. | Set it through configuration; never rely on the host machine's implicit timezone. Audit timestamps are UTC. Confirm the campus timezone with the team before deployment. |
| ADR-006 | Student identity | Students have accounts for identified complaint workflows. | Student identity is obtained from the verified student JWT. Public complaint tracking and meeting confirmation/rescheduling continue to use the tracking reference; meeting actions verify that it belongs to the complaint attached to the meeting. |
| ADR-007 | Admin authentication | Admin endpoints require a JWT Bearer token valid for 8 hours. | Missing/invalid/expired token: 401. Authenticated inactive administrator: 403. `admin_id`/author identity is derived from the verified token, not trusted from the request body. |
| ADR-008 | Anonymous complaint privacy | Anonymous submission contains category and predefined option only. | Do not accept or persist student identity or free-text description for anonymous complaints. Tracking responses must never expose student identity. |
| ADR-009 | Error format | All errors use `{error: {code, message, fields}}`. | Field values may be either a string or a list of strings, matching the current US-04 handler. Request/business validation uses 422. Rate limiting uses 429. |
| ADR-010 | Complaint status | Enforce the transition matrix in the same transaction that changes status and writes history. | `Received -> Under Review/Rejected`; `Under Review -> Resolved/Rejected`; `Resolved -> Under Review`; `Rejected -> Under Review`. All other transitions, including unchanged status, return 422. |
| ADR-011 | Tracking-reference format | Preserve `SVP-` plus six uppercase alphanumeric characters for the current contract. | The application generates references with a CSPRNG and retries on uniqueness collision; the database uniqueness constraint is an additional safeguard. This format has only about 31 bits of entropy; consider increasing length before public exposure, but any change must update SQL, validation, UI, and API together. |
| ADR-012 | Queue reference search | Search is case-insensitive. | Normalize input to uppercase before querying the case-sensitive `ascii_bin` tracking-reference column. Use parameterized SQL. |
| ADR-013 | Audit timestamps | API `date-time` values are UTC and end in `Z`. | MySQL `DATETIME` has no timezone metadata; enforce a UTC storage/session convention in the application and database connection. Meeting date/time fields remain campus-local values. |
| ADR-014 | Health endpoint | `GET /health` is process liveness, not database readiness. | It must not query MySQL. App startup must not fail just because the DB is temporarily unavailable; avoid a required DB pool connection at module import time. |
| ADR-015 | Canonical file | `openapi.yaml` is the source of truth; `openapi.json` is generated from it. | Never maintain the two formats independently. The previous JSON/validator draft described different routes and field casing and must be replaced, not kept as a second contract. |
| ADR-016 | Student accounts | Identified complaint workflows use student accounts authenticated by university email and password. | Student login is public and returns an 8-hour student JWT plus `must_change_password`. Password change requires student authentication and a new password of 8–64 characters. The contract does not assign error semantics to an incorrect current password; the team must decide this before implementation. |
| ADR-017 | Student JWT role | Student JWTs carry `role: student` and use the separate `studentBearerAuth` scheme. | Administrator JWTs continue to use `bearerAuth` and carry `role: admin`. Tokens are not interchangeable. Meeting confirmation and rescheduling continue to use `X-Tracking-Reference`. |
| ADR-018 | Identified complaint OTP | A six-digit OTP sent to the authenticated student's university email is required before identified complaint submission. | OTP expires after 5 minutes; another may be requested after a 60-second cooldown. OTP request and complaint submission use the student identity from the verified JWT. |
| ADR-019 | Open complaint limit | A student may have at most two open complaints, where open means `Received` or `Under Review`. | OTP requests and identified complaint submissions return 409 with `OPEN_COMPLAINT_LIMIT` when the student already has two open complaints. |
| ADR-020 | Anonymous complaints paused | Anonymous complaint submission remains documented but is currently paused. | `POST /complaints/anonymous` returns 503 with `ANONYMOUS_PAUSED` while paused. The sprint plan's Jira changes tab names `ANONYMOUS_ENABLED=false` for US-42; that implementation setting is not part of the API contract. |

## 3. API operation map (21 operations)

| User story | Method | Path |
|---|---|---|
| US-04 | GET | `/health` |
| US-07 | POST | `/auth/login` |
| US-39 | POST | `/auth/student/login` |
| US-40 | POST | `/auth/student/change-password` |
| US-40 | GET | `/student/me` |
| US-41 | POST | `/student/complaints/otp` |
| US-09 | GET | `/lookups` |
| US-12 (paused by US-42) | POST | `/complaints/anonymous` |
| US-44 (replaces US-13) | POST | `/complaints/identified` |
| US-15 | GET | `/track/{ref}` |
| US-17 | GET | `/admin/complaints` |
| US-19 | GET | `/admin/complaints/{complaintId}` |
| US-20 | PATCH | `/admin/complaints/{complaintId}/status` |
| US-21 | PATCH | `/admin/complaints/{complaintId}/assignment` |
| US-21 | GET | `/admin/staff` |
| US-22 | POST | `/admin/complaints/{complaintId}/notes` |
| US-24 | POST | `/admin/complaints/{complaintId}/meetings` |
| US-25 | POST | `/meetings/{meetingId}/confirm` |
| US-25 | POST | `/meetings/{meetingId}/reschedule` |
| US-26 | GET | `/admin/meetings` |
| US-27 | GET | `/admin/analytics` |

The CSV's `PATCH /staff` and `POST /notes` wording is treated as abbreviated
behaviour, not a literal route contract, because neither path identifies the target
complaint. The route names above are deliberate design refinements. If the instructor
requires literal paths, raise that before merging US-05 and change the contract once;
do not let individual implementers choose different variants.

## 4. Security requirements and limits

### Requirements already stated by the backlog

- Login: no more than 5 attempts per 15-minute window (US-31); return 429 when
  the configured limit is exceeded.
- Student login: after five failed attempts, further attempts are locked for
  15 minutes and return 429.
- OTP requests: return 429 when another request is made during the 60-second
  cooldown.
- Student JWTs are separate from administrator JWTs; use their role claims to
  reject cross-role access.
- Use parameterized SQL for all user-controlled values.
- Add the project's required security headers (US-31; the CSV uses the term
  `helmet`, which is Express-specific; for FastAPI, implement equivalent headers
  with appropriate middleware rather than adding Express/Helmet).
- Keep secrets out of the repository.

### Additional hardening recommended before public deployment

- Rate-limit `GET /track/{ref}` and both student meeting-response endpoints.
  The API contract includes 429 responses, but the exact limits are deployment
  settings that the team must choose and test. Do not invent different limits in
  individual route implementations.
- Redact tracking references from application logs, reverse-proxy/access logs,
  analytics, and exception messages. The tracking reference appears in a URL path
  for tracking and in a header for meeting actions; logging middleware must account
  for both.
- The current six-character suffix has about 31 bits of entropy. CSPRNG generation
  and rate limiting are minimum compensating controls, not a substitute for a
  longer capability secret if the portal is exposed publicly.
- Return generic not-found/authentication responses that do not reveal whether a
  tracking reference, student, or private complaint exists beyond the required
  response contract.

## 5. Implementation risks to track in backend PRs

These are implementation requirements, not items that OpenAPI documentation can
fix by itself:

1. **Status transitions:** the previously reviewed `sp_change_status` procedure
   did not enforce the complete US-20 transition matrix. Enforce it in the service
   layer or update the procedure. The status update and history insert must be
   atomic; concurrent updates must not bypass the transition check.
2. **Application startup / health:** the previously reviewed US-03 `main.py`
   created the MySQL connection pool at import time. Refactor so DB connection
   failure does not prevent the liveness endpoint from starting.
3. **Reference generation:** the current `schema.sql` trigger still uses MySQL
   `RAND()`. Replace that legacy generation path with application-side CSPRNG
   generation, retain the unique constraint, and retry on collision before
   claiming implementation conformance.
4. **Datetime consistency:** MySQL `DATETIME` does not contain timezone information.
   Set a single UTC convention for audit columns and an explicit campus timezone
   for meeting-time validation.
5. **Queue search collation:** normalize reference-search input to uppercase before
   querying the case-sensitive `ascii_bin` column, or deliberately change the
   column/query semantics in a coordinated migration.
6. **FastAPI security headers:** implement the required headers with FastAPI/ASGI
   middleware. Do not copy Express-specific `helmet` setup into a FastAPI app.
7. **Student schema migration:** the checked-in base `schema.sql` has no student
   login email/password fields or OTP table. US-37 must supply these before the
   student contract can be implemented against the database.

## 6. Release / review checklist

- [ ] Project team accepts ADR-002 to ADR-005 (the four choices that resolve the
      main route and date-rule ambiguities) or records an instructor-directed change.
- [ ] Project team reviews ADR-016 to ADR-020 and decides incorrect-current-password
      behavior before implementing the student password-change endpoint.
- [ ] `openapi.yaml` is the only manually edited contract; JSON is regenerated.
- [ ] All 21 operations, operation IDs, request/response schemas and error formats
      pass the validator and render in Swagger UI.
- [ ] Every `/admin/*` operation requires an administrator JWT; student operations
      require a student JWT where specified and never accept an administrator JWT.
- [ ] US-20 transitions are enforced in code/database transactions and tested.
- [ ] Tracking-reference generation, rate limiting and log redaction are implemented
      or clearly tracked as pre-public-deployment work.
- [ ] Timezone configuration and UTC audit timestamp behaviour are tested.
- [ ] No developer has implemented a route or payload based only on AI output or an
      isolated reading of the CSV.
