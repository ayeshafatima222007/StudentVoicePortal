/* =========================================================
   Student Voice Portal — main.js
   Shared data store (localStorage), constants, helpers,
   navigation and validation utilities.
   PROTOTYPE ONLY: no real backend, authentication or security.
   ========================================================= */
(function () {
  "use strict";

  const STORE_KEY = "svp_submissions_v3";
  const SESSION_KEY = "svp_admin_session";
  const REMEMBER_KEY = "svp_admin_remember";

  /* ---------- Constants taken from the approved requirements ---------- */
  const COMPLAINT_CATEGORIES = {
    "Faculty / Teaching": ["Teaching quality concern", "Instructor availability", "Teaching methodology"],
    "Course": ["Course content issue", "Course material issue"],
    "Facilities": ["Classroom issue", "Laboratory issue", "Equipment issue"],
    "Timetable": ["Scheduling conflict", "Timing issue"],
    "Examination": ["Examination scheduling", "Examination arrangement"],
    "Student Experience": ["General student experience", "Idea to improve student life"],
    "Other": ["Suggestion for improvement", "Something not listed here"]
  };
  const STATUSES = ["Received", "Under Review", "Resolved", "Rejected"];
  const CLASS_TIMINGS = ["Morning", "Evening"];

  /* Fixed, predefined descriptions for each anonymous complaint option.
     They explain the complaint without letting the student type free text. */
  const OPTION_INFO = {
    "Teaching quality concern": "Lectures are hard to follow, poorly prepared or do not cover the topic properly.",
    "Instructor availability": "The instructor is hard to reach, misses classes or has no usable office hours.",
    "Teaching methodology": "The way the course is taught does not suit the subject, for example no examples or practice.",
    "Course content issue": "Topics taught do not match the course outline or are outdated.",
    "Course material issue": "Slides, notes or books are missing, shared late or of poor quality.",
    "Classroom issue": "Broken furniture, lighting, fans, air conditioning or cleanliness problems in a classroom.",
    "Laboratory issue": "Lab computers, equipment or software are not working or not enough for students.",
    "Equipment issue": "Projectors, speakers or other teaching equipment are not working.",
    "Scheduling conflict": "Two classes, labs or exams are scheduled at the same time.",
    "Timing issue": "Class timings are inconvenient, for example too early, too late or with no break in between.",
    "Examination scheduling": "Exam dates clash or are announced too late to prepare.",
    "Examination arrangement": "Problems with seating, invigilation, question papers or the exam hall.",
    "General student experience": "Something about day-to-day student life in the department is not working well.",
    "Idea to improve student life": "A suggestion that would make student life in the department better.",
    "Suggestion for improvement": "An idea to improve the department that does not fit another category.",
    "Something not listed here": "A concern that does not fit any of the categories above."
  };
  const STAFF = ["Ahmed Khan", "Sara Ali", "Hassan Raza", "Ayesha Malik"];
  const MEETING_RESPONSES = ["Confirmed", "Requested Different Time", "No Response"];

  /* ---------- Prototype assumptions (not fixed by the SRS) ---------- */
  const BATCHES = ["2022", "2023", "2024", "2025", "2026"];
  const SECTIONS = ["A", "B", "C", "D"];
  const REF_PATTERN = /^SVP-[A-Z0-9]{6}$/;
  const REG_PATTERN = /^\d{4}-[A-Z]{2,4}-\d{3}$/; // e.g. 2023-CS-045
  const LIMITS = {
    description: { min: 20, max: 1000 },
    note: { min: 10, max: 500 },
    location: { min: 3, max: 100 },
    meetingMessage: { max: 300 },
    requestMessage: { max: 300 }
  };
  const DEMO_ADMIN = { email: "admin@studentvoice.com", password: "Admin123" };

  /* ---------- Dummy data (fictional) ---------- */
  const SEED = [
    { ref: "SVP-8F4K29", type: "Complaint", mode: "Identified", category: "Facilities",
      regNo: "2023-CS-019", batch: "2023", section: "A", classTiming: "Morning",
      description: "Several chairs in Room 7 are broken and the ceiling fan makes a loud noise during lectures, making it hard to concentrate.",
      date: "2026-09-29", status: "Under Review", staff: "Ahmed Khan",
      response: "Your complaint has been reviewed and forwarded to the concerned staff member.",
      meeting: { date: "2026-10-06", time: "11:30", location: "Department Office",
        message: "Please visit the department office to discuss your submission.", response: "No Response", request: null } },
    { ref: "SVP-4A72KD", type: "Complaint", mode: "Identified", category: "Course",
      regNo: "2023-CS-045", batch: "2023", section: "B", classTiming: "Morning",
      description: "Lecture slides for this course are shared only after the class, so we cannot prepare or follow along during lectures.",
      date: "2026-09-28", status: "Received", staff: "Unassigned", response: "", meeting: null },
    { ref: "SVP-91LK20", type: "Complaint", mode: "Identified", category: "Examination",
      regNo: "2022-CS-112", batch: "2022", section: "A", classTiming: "Morning",
      description: "Two of my mid-term papers were scheduled in the same time slot on the same day, so I could not attend both.",
      date: "2026-09-27", status: "Resolved", staff: "Sara Ali",
      response: "Your concern has been reviewed and appropriate action has been taken.", meeting: null },
    { ref: "SVP-7QX3M1", type: "Complaint", mode: "Anonymous", category: "Timetable", option: "Scheduling conflict",
      date: "2026-09-26", status: "Received", staff: "Unassigned", response: "", meeting: null },
    { ref: "SVP-2HD8P5", type: "Complaint", mode: "Identified", category: "Course",
      regNo: "2024-SE-018", batch: "2024", section: "C", classTiming: "Morning",
      description: "The weekly assignments for this course take far longer than the credit hours suggest and overlap with quizzes.",
      date: "2026-09-25", status: "Under Review", staff: "Hassan Raza",
      response: "The course coordinator has been asked to review the assignment schedule.",
      meeting: { date: "2026-10-02", time: "10:00", location: "Room 204, Academic Block", message: "Please bring your course outline.", response: "Confirmed", request: null } },
    { ref: "SVP-K5T9W2", type: "Complaint", mode: "Identified", category: "Facilities",
      regNo: "2023-SE-077", batch: "2023", section: "A", classTiming: "Evening",
      description: "The library study area needs more charging points; most desks have no working socket nearby.",
      date: "2026-09-24", status: "Resolved", staff: "Ayesha Malik",
      response: "Additional charging points have been requested for the library study area.", meeting: null },
    { ref: "SVP-B3N6R8", type: "Complaint", mode: "Identified", category: "Faculty / Teaching",
      regNo: "2024-SE-052", batch: "2024", section: "C", classTiming: "Evening",
      description: "Our instructor's office hours are only in the morning, so evening students have no time to ask questions outside class.",
      date: "2026-09-22", status: "Under Review", staff: "Sara Ali",
      response: "We would like to discuss this concern with you in person.",
      meeting: { date: "2026-10-05", time: "14:00", location: "Department Office",
        message: "Please bring your timetable so we can find a suitable slot.", response: "Requested Different Time",
        request: { date: "2026-10-07", time: "12:00", message: "I have a lab session at the proposed time." } } },
    { ref: "SVP-P8V1C4", type: "Complaint", mode: "Anonymous", category: "Examination", option: "Examination arrangement",
      date: "2026-09-20", status: "Rejected", staff: "Ahmed Khan",
      response: "This matter is handled by the Examinations Office. Please contact them directly.", meeting: null },
    { ref: "SVP-Z6M2E7", type: "Complaint", mode: "Identified", category: "Student Experience",
      regNo: "2025-CS-009", batch: "2025", section: "D", classTiming: "Evening",
      description: "Department events are announced only a day before, so evening students cannot plan around their classes and miss them.",
      date: "2026-09-18", status: "Received", staff: "Unassigned", response: "", meeting: null },
    { ref: "SVP-H4J7L9", type: "Complaint", mode: "Identified", category: "Facilities",
      regNo: "2022-IT-031", batch: "2022", section: "B", classTiming: "Morning",
      description: "The projector in Lecture Hall 3 has been flickering for two weeks, making slides hard to read.",
      date: "2026-09-15", status: "Resolved", staff: "Hassan Raza",
      response: "The projector has been replaced by the maintenance team.", meeting: null },
    { ref: "SVP-C9F2A6", type: "Complaint", mode: "Anonymous", category: "Student Experience", option: "General student experience",
      date: "2026-09-12", status: "Resolved", staff: "Ayesha Malik",
      response: "Your concern has been noted and shared with the student affairs coordinator.", meeting: null },
    { ref: "SVP-R1S8T3", type: "Complaint", mode: "Identified", category: "Timetable",
      regNo: "2024-CS-120", batch: "2024", section: "A", classTiming: "Morning",
      description: "Assignment and quiz deadlines from different courses keep falling on the same day because there is no shared schedule.",
      date: "2026-09-10", status: "Under Review", staff: "Ahmed Khan", response: "", meeting: null },
    { ref: "SVP-D7G4Y5", type: "Complaint", mode: "Anonymous", category: "Course", option: "Course material issue",
      date: "2026-09-05", status: "Resolved", staff: "Sara Ali",
      response: "Updated course material has been uploaded by the instructor.", meeting: null },
    { ref: "SVP-N2W6Q8", type: "Complaint", mode: "Identified", category: "Other",
      regNo: "2023-IT-064", batch: "2023", section: "C", classTiming: "Evening",
      description: "The department notice board is not updated regularly and some notices are months old.",
      date: "2026-08-28", status: "Under Review", staff: "Hassan Raza", response: "", meeting: null },
    { ref: "SVP-E5U3I1", type: "Complaint", mode: "Identified", category: "Faculty / Teaching",
      regNo: "2022-SE-015", batch: "2022", section: "D", classTiming: "Evening",
      description: "The instructor for our evening section frequently starts class 20 to 30 minutes late without notice.",
      date: "2026-08-20", status: "Resolved", staff: "Ayesha Malik",
      response: "The matter has been raised with the instructor and class timings are now being followed.", meeting: null },
    { ref: "SVP-V8B1X4", type: "Complaint", mode: "Anonymous", category: "Facilities", option: "Laboratory issue",
      date: "2026-08-14", status: "Resolved", staff: "Hassan Raza",
      response: "Faulty lab computers have been repaired.", meeting: null },
    { ref: "SVP-L3K9T0", type: "Complaint", mode: "Identified", category: "Other",
      regNo: "2024-IT-088", batch: "2024", section: "B", classTiming: "Evening",
      description: "The department office closes before evening classes end, so evening students cannot get documents signed during exams.",
      date: "2026-07-30", status: "Resolved", staff: "Sara Ali",
      response: "Office hours will be extended by one hour during examinations.", meeting: null },
    { ref: "SVP-G6H2J8", type: "Complaint", mode: "Identified", category: "Timetable",
      regNo: "2025-SE-041", batch: "2025", section: "A", classTiming: "Morning",
      description: "Two lab sessions are scheduled back to back in buildings far apart, leaving no time to move between them.",
      date: "2026-07-22", status: "Resolved", staff: "Ahmed Khan",
      response: "The timetable has been revised to add a gap between the two sessions.", meeting: null }
  ];

  /* ---------- Storage (with in-memory fallback) ---------- */
  let memory = null;
  function clone(x) { return JSON.parse(JSON.stringify(x)); }
  function storageGet(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }
  function storageSet(key, val) { try { localStorage.setItem(key, val); return true; } catch (e) { return false; } }
  function storageRemove(key) { try { localStorage.removeItem(key); } catch (e) { /* ignore */ } }

  function loadAll() {
    const raw = storageGet(STORE_KEY);
    if (raw) { try { return JSON.parse(raw); } catch (e) { /* fall through */ } }
    if (memory) return memory;
    const data = clone(SEED);
    saveAll(data);
    return data;
  }
  function saveAll(data) {
    memory = data;
    storageSet(STORE_KEY, JSON.stringify(data));
  }
  function getByRef(ref) {
    if (!ref) return null;
    return loadAll().find(s => s.ref === String(ref).toUpperCase()) || null;
  }
  function updateByRef(ref, changes) {
    const data = loadAll();
    const i = data.findIndex(s => s.ref === ref);
    if (i === -1) return null;
    data[i] = Object.assign({}, data[i], changes);
    saveAll(data);
    return data[i];
  }
  function addSubmission(sub) {
    const data = loadAll();
    data.unshift(sub);
    saveAll(data);
    return sub;
  }
  function resetData() {
    storageRemove(STORE_KEY);
    memory = null;
    return loadAll();
  }

  /* Prototype reference generator — NOT secure; for demonstration only. */
  function generateRef() {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    const existing = new Set(loadAll().map(s => s.ref));
    let ref;
    do {
      ref = "SVP-";
      for (let i = 0; i < 6; i++) ref += chars[Math.floor(Math.random() * chars.length)];
    } while (existing.has(ref));
    return ref;
  }

  /* ---------- Formatting helpers ---------- */
  const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  function todayISO() {
    const d = new Date();
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }
  function formatDate(iso, short) {
    if (!iso) return "—";
    const [y, m, d] = iso.split("-").map(Number);
    return short ? d + " " + MONTHS[m - 1].slice(0, 3) : d + " " + MONTHS[m - 1] + " " + y;
  }
  function formatTime(t) {
    if (!t) return "—";
    let [h, m] = t.split(":").map(Number);
    const ap = h >= 12 ? "PM" : "AM";
    h = h % 12 || 12;
    return h + ":" + String(m).padStart(2, "0") + " " + ap;
  }
  function esc(str) {
    return String(str == null ? "" : str).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }
  function param(name) { return new URLSearchParams(window.location.search).get(name); }

  function statusBadge(status) {
    const cls = { "Received": "status-received", "Under Review": "status-review", "Resolved": "status-resolved", "Rejected": "status-rejected" }[status] || "status-received";
    return '<span class="status-badge ' + cls + '">' + esc(status) + "</span>";
  }
  function responseBadge(resp) {
    const cls = { "Confirmed": "resp-confirmed", "Requested Different Time": "resp-requested", "No Response": "resp-none" }[resp] || "resp-none";
    return '<span class="status-badge ' + cls + '">' + esc(resp) + "</span>";
  }
  function typeLabel(sub) {
    return sub.mode === "Anonymous" ? "Anonymous complaint" : "Identified complaint";
  }
  function typePill(sub) { return '<span class="type-text">' + esc(typeLabel(sub)) + "</span>"; }

  /* ---------- Validation helpers (Bootstrap styling) ---------- */
  function setError(el, msg) {
    el.classList.add("is-invalid");
    el.classList.remove("is-valid");
    el.setAttribute("aria-invalid", "true");
    const fb = document.getElementById(el.id + "-error");
    if (fb) fb.textContent = msg;
  }
  function setValid(el) {
    el.classList.remove("is-invalid");
    el.classList.add("is-valid");
    el.removeAttribute("aria-invalid");
  }
  function clearState(el) {
    el.classList.remove("is-invalid", "is-valid");
    el.removeAttribute("aria-invalid");
  }
  function focusFirstError(form) {
    const first = form.querySelector(".is-invalid");
    if (first) first.focus();
  }
  function textLengthRule(el, label, min, max, required) {
    const raw = el.value;
    const v = raw.trim();
    if (!v) {
      if (required) { setError(el, raw.length ? label + " cannot contain only spaces." : label + " is required."); return false; }
      clearState(el); return true;
    }
    if (min && v.length < min) { setError(el, label + " must contain at least " + min + " characters."); return false; }
    if (max && v.length > max) { setError(el, label + " cannot exceed " + max + " characters."); return false; }
    setValid(el); return true;
  }
  function selectRule(el, msg) {
    if (!el.value) { setError(el, msg); return false; }
    setValid(el); return true;
  }
  function attachCounter(textarea, max) {
    const counter = document.getElementById(textarea.id + "-count");
    if (!counter) return;
    const update = () => {
      const n = textarea.value.trim().length;
      counter.textContent = n + " / " + max + " characters";
      counter.classList.toggle("over", n > max);
    };
    textarea.addEventListener("input", update);
    update();
  }
  function fillSelect(sel, items, placeholder) {
    sel.innerHTML = (placeholder ? '<option value="">' + esc(placeholder) + "</option>" : "") +
      items.map(i => '<option value="' + esc(i) + '">' + esc(i) + "</option>").join("");
  }

  /* ---------- Alerts ---------- */
  function showAlert(container, type, html, autoHide) {
    if (!container) return;
    const icon = { success: "bi-check-circle-fill", danger: "bi-exclamation-triangle-fill", warning: "bi-exclamation-circle-fill", info: "bi-info-circle-fill" }[type] || "bi-info-circle-fill";
    container.innerHTML = '<div class="alert alert-' + type + ' alert-dismissible d-flex gap-2 align-items-start" role="alert">' +
      '<i class="bi ' + icon + ' mt-1" aria-hidden="true"></i><div>' + html + '</div>' +
      '<button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button></div>';
    if (autoHide) setTimeout(() => { if (container) container.innerHTML = ""; }, 5000);
  }

  /* ---------- Admin session (SIMULATED) ---------- */
  function isAdmin() { return storageGet(SESSION_KEY) === "1" || sessionMemory; }
  let sessionMemory = false;
  function loginAdmin(remember, email) {
    sessionMemory = true;
    storageSet(SESSION_KEY, "1");
    if (remember) storageSet(REMEMBER_KEY, email); else storageRemove(REMEMBER_KEY);
  }
  function logoutAdmin() { sessionMemory = false; storageRemove(SESSION_KEY); }
  function rememberedEmail() { return storageGet(REMEMBER_KEY) || ""; }

  /* ---------- Progress tracker (status page) ---------- */
  function timelineHTML(status) {
    const finalStage = status === "Rejected" ? "Rejected" : status === "Resolved" ? "Resolved" : "Resolved or rejected";
    const stages = ["Received", "Under Review", finalStage];
    const idx = status === "Received" ? 0 : status === "Under Review" ? 1 : 2;
    const icon = { "Received": "bi-inbox", "Under Review": "bi-hourglass-split", "Resolved": "bi-check-lg", "Rejected": "bi-x-lg", "Resolved or rejected": "bi-flag" };
    return '<ol class="progress-seg" aria-label="Submission progress">' + stages.map((st, i) => {
      let cls, note, ic = icon[st];
      if (i < idx) { cls = "done"; note = "Completed"; ic = "bi-check-lg"; }
      else if (i === idx) {
        cls = "current" + (st === "Resolved" ? " is-resolved" : "") + (st === "Rejected" ? " is-rejected" : "");
        note = (st === "Resolved" || st === "Rejected") ? "Final stage" : "Current stage";
      } else { cls = "pending"; note = "Pending"; }
      return '<li class="' + cls + '" style="--i:' + i + '"' + (i === idx ? ' aria-current="step"' : "") + ">" +
        '<span class="seg-track"><span class="seg-fill"></span></span>' +
        '<span class="seg-head"><span class="seg-dot"><i class="bi ' + ic + '" aria-hidden="true"></i></span><span class="seg-label">' + esc(st) + "</span></span>" +
        '<span class="seg-note">' + note + "</span></li>";
    }).join("") + "</ol>";
  }

  /* ---------- Motion helpers ---------- */
  function reducedMotion() {
    try { return window.matchMedia("(prefers-reduced-motion: reduce)").matches; } catch (e) { return false; }
  }
  // Counts a number up from 0. Keeps any suffix such as "%".
  function countUp(el, target, opts) {
    if (!el) return;
    const o = opts || {};
    const decimals = o.decimals || 0, suffix = o.suffix || "", duration = o.duration || 900;
    const fmt = v => (decimals ? v.toFixed(decimals).replace(/\.0+$/, "") : Math.round(v)) + suffix;
    if (reducedMotion() || !target) { el.textContent = fmt(target || 0); return; }
    const start = performance.now();
    function step(now) {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      el.textContent = fmt(target * eased);
      if (t < 1) requestAnimationFrame(step); else el.textContent = fmt(target);
    }
    el.textContent = fmt(0);
    requestAnimationFrame(step);
  }
  // Counts up every element with data-count inside root.
  function animateCounts(root) {
    (root || document).querySelectorAll("[data-count]").forEach(el => {
      const raw = el.getAttribute("data-count");
      const suffix = raw.endsWith("%") ? "%" : "";
      const n = parseFloat(raw);
      countUp(el, isNaN(n) ? 0 : n, { suffix: suffix, decimals: String(n).includes(".") ? 1 : 0 });
    });
  }
  // Staggered entrance for panels and cards on every page.
  function revealPage() {
    if (reducedMotion()) return;
    const els = document.querySelectorAll("main .page-head, main h1, main .svp-panel, main .stat-card, main .side-note, main .demo-note, main .ticket, main .feature-card");
    let i = 0;
    els.forEach(el => {
      if (el.closest(".reveal")) return;
      el.classList.add("reveal");
      el.style.setProperty("--d", Math.min(i++, 12) * 55 + "ms");
    });
  }

  /* ---------- Toasts ---------- */
  function showToast(message, type) {
    let stack = document.getElementById("toastStack");
    if (!stack) {
      stack = document.createElement("div");
      stack.id = "toastStack";
      stack.className = "toast-stack";
      stack.setAttribute("aria-live", "polite");
      stack.setAttribute("role", "status");
      document.body.appendChild(stack);
    }
    const t = document.createElement("div");
    t.className = "svp-toast" + (type && type !== "success" ? " " + type : "");
    t.innerHTML = "<span>" + message + '</span><button type="button" aria-label="Dismiss">&times;</button>';
    t.querySelector("button").addEventListener("click", () => t.remove());
    stack.appendChild(t);
    setTimeout(() => t.remove(), 4500);
  }
  // A toast can be queued before navigating to another page.
  function queueToast(message, type) { try { sessionStorage.setItem("svp_toast", JSON.stringify([message, type || "success"])); } catch (e) { /* ignore */ } }
  function flushToast() {
    try {
      const raw = sessionStorage.getItem("svp_toast");
      if (raw) { sessionStorage.removeItem("svp_toast"); const [m, t] = JSON.parse(raw); showToast(m, t); }
    } catch (e) { /* ignore */ }
  }

  /* ---------- Top bar ---------- */
  function renderTopbar() {
    const slot = document.getElementById("site-nav");
    if (!slot) return;
    const root = document.body.dataset.root || "";
    const active = document.body.dataset.nav || "";
    const admin = document.body.dataset.area === "admin";
    const links = admin ? [
      ["dashboard", "dashboard.html", "Dashboard"],
      ["submissions", "submissions.html", "Submission queue"],
      ["meetings", "meetings.html", "Meetings"],
      ["analytics", "analytics.html", "Analytics"]
    ] : [
      ["home", root + "index.html", "Home"],
      ["complaint", root + "student/complaint.html", "Submit complaint"],
      ["track", root + "student/track.html", "Track submission"]
    ];
    const home = admin ? "dashboard.html" : root + "index.html";
    const right = admin
      ? '<div class="d-flex align-items-center gap-2 mt-2 mt-lg-0"><span class="admin-pill">Admin</span><button type="button" class="btn btn-sm btn-quiet" id="logoutBtn">Log out</button></div>'
      : '<a class="btn btn-sm btn-accent mt-2 mt-lg-0 px-3" href="' + root + 'admin/login.html">Admin login</a>';
    slot.innerHTML =
      '<header class="topbar sticky-top"><nav class="navbar navbar-expand-lg navbar-light" aria-label="Main navigation"><div class="container-xl">' +
      '<a class="svp-brand me-3" href="' + home + '"><span class="svp-mark" aria-hidden="true"><i class="bi bi-chat-square-text-fill"></i></span>Student Voice Portal</a>' +
      '<button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#mainNav" aria-controls="mainNav" aria-expanded="false" aria-label="Toggle navigation"><span class="navbar-toggler-icon"></span></button>' +
      '<div class="collapse navbar-collapse" id="mainNav"><ul class="navbar-nav me-auto gap-lg-1">' +
      links.map(l => '<li class="nav-item"><a class="nav-link' + (active === l[0] ? " active" : "") + '"' + (active === l[0] ? ' aria-current="page"' : "") +
        ' href="' + l[1] + '">' + l[2] + "</a></li>").join("") +
      "</ul>" + right + "</div></div></nav></header>";

    const lo = document.getElementById("logoutBtn");
    if (lo) lo.addEventListener("click", () => {
      logoutAdmin();
      queueToast("Logged out");
      window.location.href = "login.html";
    });
  }

  function renderFooter() {
    const slot = document.getElementById("site-footer");
    if (!slot) return;
    const root = document.body.dataset.root || "";
    slot.innerHTML = '<footer class="svp-footer"><div class="container-xl d-flex flex-column flex-md-row justify-content-between gap-2">' +
      "<span>Student Voice Portal prototype. Uses sample data; nothing is sent to a server.</span>" +
      '<span class="d-flex gap-3"><a href="' + root + 'documentation.html">Project documentation</a><button type="button" id="resetDemo">Reset demo data</button></span></div></footer>';
    document.getElementById("resetDemo").addEventListener("click", () => {
      if (confirm("Reset all prototype data to the original sample submissions?")) {
        resetData();
        queueToast("Demo data reset");
        window.location.reload();
      }
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    renderTopbar();
    renderFooter();
    flushToast();
    revealPage();
  });

  window.SVP = {
    COMPLAINT_CATEGORIES, CLASS_TIMINGS, OPTION_INFO, STATUSES, STAFF, MEETING_RESPONSES,
    SEED: clone(SEED), BATCHES, SECTIONS, REF_PATTERN, REG_PATTERN, LIMITS, DEMO_ADMIN,
    loadAll, saveAll, getByRef, updateByRef, addSubmission, resetData, generateRef,
    todayISO, formatDate, formatTime, esc, param, statusBadge, responseBadge, typePill, typeLabel, showToast, queueToast,
    setError, setValid, clearState, focusFirstError, textLengthRule, selectRule, attachCounter, fillSelect,
    showAlert, isAdmin, loginAdmin, logoutAdmin, rememberedEmail, countUp, reducedMotion, revealPage, timelineHTML, animateCounts
  };
})();
