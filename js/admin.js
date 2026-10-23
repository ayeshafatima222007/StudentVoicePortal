/* =========================================================
   Student Voice Portal — admin.js
   Simulated admin login, dashboard, queue, details,
   meetings and analytics. PROTOTYPE ONLY.
   ========================================================= */
(function () {
  "use strict";
  const S = window.SVP;
  const page = document.body.dataset.page;

  // Simulated access control: every admin page except login requires the demo session flag.
  if (page !== "login" && !S.isAdmin()) {
    window.location.replace("login.html?required=1");
    return;
  }

  function counts(data) {
    const c = { total: data.length, "Received": 0, "Under Review": 0, "Resolved": 0, "Rejected": 0 };
    data.forEach(s => { c[s.status] = (c[s.status] || 0) + 1; });
    return c;
  }
  function pct(n, d) { return d ? Math.round((n / d) * 1000) / 10 : 0; }
  function barRows(entries, max, fillClass) {
    return entries.map(([label, value, cls], i) =>
      '<div class="bar-row" style="--i:' + i + '"><span>' + S.esc(label) + '</span>' +
      '<div class="bar-track" role="img" aria-label="' + S.esc(label) + ": " + value + '"><div class="bar-fill ' + (cls || fillClass || "") + '" style="width:' + (max ? (value / max) * 100 : 0) + '%"></div></div>' +
      '<span class="bar-value" data-count="' + value + '">' + value + "</span></div>").join("");
  }
  const STATUS_FILL = { "Received": "f-received", "Under Review": "f-review", "Resolved": "f-resolved", "Rejected": "f-rejected" };

  /* ---------------- Login ---------------- */
  function initLogin() {
    if (S.isAdmin()) { window.location.replace("dashboard.html"); return; }
    const form = document.getElementById("loginForm");
    const email = document.getElementById("email");
    const pw = document.getElementById("password");
    const remember = document.getElementById("remember");
    const alertBox = document.getElementById("loginAlert");
    const saved = S.rememberedEmail();
    if (saved) { email.value = saved; remember.checked = true; }
    if (S.param("required")) S.showAlert(alertBox, "warning", "Log in to access the admin area.");

    document.getElementById("togglePw").addEventListener("click", function () {
      const show = pw.type === "password";
      pw.type = show ? "text" : "password";
      this.setAttribute("aria-label", show ? "Hide password" : "Show password");
      this.textContent = show ? "Hide" : "Show";
    });
    document.getElementById("fillDemo").addEventListener("click", () => {
      email.value = S.DEMO_ADMIN.email; pw.value = S.DEMO_ADMIN.password;
      S.clearState(email); S.clearState(pw);
    });

    form.addEventListener("submit", e => {
      e.preventDefault();
      alertBox.innerHTML = "";
      let ok = true;
      const ev = email.value.trim();
      if (!ev) { S.setError(email, "Username or email is required."); ok = false; }
      else if (ev.includes("@") && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(ev)) { S.setError(email, "Enter a valid email address."); ok = false; }
      else S.setValid(email);
      if (!pw.value) { S.setError(pw, "Password is required."); ok = false; } else S.setValid(pw);
      if (!ok) { S.focusFirstError(form); return; }

      if (ev.toLowerCase() === S.DEMO_ADMIN.email && pw.value === S.DEMO_ADMIN.password) {
        S.loginAdmin(remember.checked, ev);
        S.queueToast("Logged in");
        window.location.href = "dashboard.html";
      } else {
        S.clearState(email); S.setError(pw, "");
        S.showAlert(alertBox, "danger", "<strong>Invalid login.</strong> The email or password is incorrect.");
        pw.value = ""; pw.focus();
      }
    });
  }

  /* ---------------- Dashboard ---------------- */
  function initDashboard() {
    const data = S.loadAll();
    const c = counts(data);
    const cards = [
      ["Total submissions", c.total, "", ""],
      ["Received", c["Received"], "c-received", "Received"],
      ["Under review", c["Under Review"], "c-review", "Under Review"],
      ["Resolved", c["Resolved"], "c-resolved", "Resolved"],
      ["Rejected", c["Rejected"], "c-rejected", "Rejected"]
    ];
    document.getElementById("statCards").innerHTML = cards.map(([label, val, cls, filter]) =>
      '<div class="col-6 col-md-4 col-xl"><a class="stat-card ' + cls + '" href="submissions.html' + (filter ? "?status=" + encodeURIComponent(filter) : "") + '">' +
      '<div class="stat-value" data-count="' + val + '">' + val + '</div><div class="stat-label">' + label + "</div></a></div>").join("");

    const recent = data.slice().sort((a, b) => b.date.localeCompare(a.date)).slice(0, 6);
    document.getElementById("recentBody").innerHTML = recent.map(s =>
      '<tr><td class="ref-cell">' + s.ref + "</td><td>" + S.typePill(s) + "</td><td>" + S.esc(s.category) + '</td><td class="nowrap">' + S.formatDate(s.date, true) +
      "</td><td>" + S.statusBadge(s.status) + '</td><td class="text-end"><a class="btn btn-sm btn-quiet" href="submission-details.html?ref=' + s.ref + '" aria-label="View ' + s.ref + '">View</a></td></tr>').join("");

    const notReviewed = c["Received"];
    const noStaff = data.filter(s => s.staff === "Unassigned" && (s.status === "Received" || s.status === "Under Review")).length;
    const newTime = data.filter(s => s.meeting && s.meeting.response === "Requested Different Time").length;
    document.getElementById("attention").innerHTML =
      '<a href="submissions.html?status=Received"><span>New submissions not yet reviewed</span><span class="count-chip blue">' + notReviewed + "</span></a>" +
      '<a href="submissions.html?staff=Unassigned"><span>Open submissions without staff</span><span class="count-chip">' + noStaff + "</span></a>" +
      '<a href="meetings.html?response=' + encodeURIComponent("Requested Different Time") + '"><span>Meetings with a new time requested</span><span class="count-chip amber">' + newTime + "</span></a>";

    document.getElementById("statusBars").innerHTML = barRows(S.STATUSES.map(st => [st, c[st], STATUS_FILL[st]]), c.total);
    document.getElementById("resolutionRate").setAttribute("data-count", pct(c["Resolved"], c.total) + "%");
    S.animateCounts();
  }

  /* ---------------- Submission queue ---------------- */
  function initSubmissions() {
    const catSel = document.getElementById("fCategory");
    S.fillSelect(catSel, Object.keys(S.COMPLAINT_CATEGORIES), "All categories");
    S.fillSelect(document.getElementById("fStatus"), S.STATUSES, "All statuses");
    const fSearch = document.getElementById("fSearch"), fStatus = document.getElementById("fStatus");
    const fType = document.getElementById("fType"), fFrom = document.getElementById("fFrom"), fTo = document.getElementById("fTo");
    const pre = S.param("status"); if (pre) fStatus.value = pre;
    let onlyUnassigned = S.param("staff") === "Unassigned";
    const note = document.getElementById("staffNote");
    if (onlyUnassigned && note) note.classList.remove("d-none");

    function apply() {
      const q = fSearch.value.trim().toLowerCase();
      const rows = S.loadAll().filter(s => {
        if (q && !(s.ref.toLowerCase().includes(q) || s.category.toLowerCase().includes(q) || s.staff.toLowerCase().includes(q))) return false;
        if (catSel.value && s.category !== catSel.value) return false;
        if (fStatus.value && s.status !== fStatus.value) return false;
        if (fType.value && s.mode !== fType.value) return false;
        if (fFrom.value && s.date < fFrom.value) return false;
        if (fTo.value && s.date > fTo.value) return false;
        if (onlyUnassigned && !(s.staff === "Unassigned" && (s.status === "Received" || s.status === "Under Review"))) return false;
        return true;
      }).sort((a, b) => b.date.localeCompare(a.date));

      document.getElementById("resultCount").textContent = "Showing " + rows.length + " of " + S.loadAll().length + " submissions";
      const body = document.getElementById("queueBody");
      if (!rows.length) {
        body.innerHTML = '<tr><td colspan="7" class="text-center py-5"><p class="fw-semibold mb-1">No submissions match these filters.</p><button class="btn btn-sm btn-outline-primary" type="button" id="emptyReset">Clear filters</button></td></tr>';
        document.getElementById("emptyReset").addEventListener("click", reset);
        return;
      }
      body.innerHTML = rows.map(s =>
        '<tr><td class="ref-cell">' + s.ref + "</td><td>" + S.typePill(s) + "</td><td>" + S.esc(s.category) + "</td><td class=\"nowrap\">" + S.formatDate(s.date, true) + "</td><td>" +
        S.statusBadge(s.status) + "</td><td>" + (s.staff === "Unassigned" ? '<span class="text-muted fst-italic">Unassigned</span>' : S.esc(s.staff)) +
        '</td><td><a class="btn btn-sm btn-quiet" href="submission-details.html?ref=' + s.ref + '" aria-label="View ' + s.ref + '">View</a></td></tr>').join("");
    }
    function reset() {
      fSearch.value = ""; catSel.value = ""; fStatus.value = ""; fType.value = ""; fFrom.value = ""; fTo.value = "";
      onlyUnassigned = false; if (note) note.classList.add("d-none");
      apply();
    }
    [fSearch].forEach(el => el.addEventListener("input", apply));
    [catSel, fStatus, fType, fFrom, fTo].forEach(el => el.addEventListener("change", apply));
    document.getElementById("resetFilters").addEventListener("click", reset);
    apply();
  }

  /* ---------------- Submission details ---------------- */
  function initDetails() {
    const ref = S.param("ref");
    if (!S.getByRef(ref)) {
      document.getElementById("detailsBox").innerHTML = '<div class="svp-panel svp-panel-pad text-center"><h1 class="h4">Submission not found</h1><a class="btn btn-primary" href="submissions.html">Back to submission queue</a></div>';
      return;
    }
    const modal = id => bootstrap.Modal.getOrCreateInstance(document.getElementById(id));

    function render() {
      const s = S.getByRef(ref);
      document.getElementById("dRef").textContent = s.ref;
      document.getElementById("dRefCrumb").textContent = s.ref;
      document.getElementById("dType").innerHTML = S.typePill(s);
      document.getElementById("dCategory").textContent = s.category;
      document.getElementById("dDate").textContent = S.formatDate(s.date);
      document.getElementById("dStatus").innerHTML = S.statusBadge(s.status);
      document.getElementById("dStaff").innerHTML = s.staff === "Unassigned" ? '<span class="text-muted fst-italic">Unassigned</span>' : S.esc(s.staff);

      const idBox = document.getElementById("dIdentity");
      if (s.mode === "Anonymous") {
        idBox.innerHTML = '<div class="privacy-note"><strong><i class="bi bi-incognito me-2" aria-hidden="true"></i>Anonymous submission</strong><br>' +
          '<span class="small">No student identity was collected. Name, registration number, batch, section and class timing are not available.</span></div>';
      } else {
        idBox.innerHTML = '<dl class="row detail-list mb-0">' +
          '<div class="col-6 col-md-3"><dt>Registration number</dt><dd>' + S.esc(s.regNo) + "</dd></div>" +
          '<div class="col-6 col-md-3"><dt>Batch</dt><dd>' + S.esc(s.batch) + "</dd></div>" +
          '<div class="col-6 col-md-3"><dt>Section</dt><dd>' + S.esc(s.section) + "</dd></div>" +
          '<div class="col-6 col-md-3"><dt>Class timing</dt><dd>' + S.esc(s.classTiming || "—") + "</dd></div></dl>";
      }
      document.getElementById("dContent").innerHTML = s.mode === "Anonymous"
        ? '<p class="mb-1"><span class="text-muted">Selected option:</span></p><p class="fs-5 fw-semibold mb-1">' + S.esc(s.option) + "</p>" +
          (S.OPTION_INFO[s.option] ? '<p class="text-muted mb-0">' + S.esc(S.OPTION_INFO[s.option]) + "</p>" : "")
        : '<p class="mb-0" style="white-space:pre-wrap">' + S.esc(s.description) + "</p>";

      document.getElementById("dResponse").innerHTML = s.response
        ? '<blockquote class="mb-0 border-start border-4 ps-3" style="border-color:var(--brand)!important">' + S.esc(s.response) + "</blockquote>"
        : '<p class="text-muted mb-0">No resolution note yet. Use “Add Resolution Note” to respond to the student.</p>';

      const mBox = document.getElementById("dMeeting");
      if (s.meeting) {
        const m = s.meeting;
        let req = "";
        if (m.response === "Requested Different Time" && m.request) {
          req = '<div class="demo-note mt-3"><strong>Student requested:</strong> ' + S.formatDate(m.request.date) + " at " + S.formatTime(m.request.time) +
            (m.request.message ? '<br><span class="small">“' + S.esc(m.request.message) + "”</span>" : "") +
            '<br><button type="button" class="btn btn-sm btn-accent mt-2" id="useRequested">Propose the requested time</button></div>';
        }
        mBox.innerHTML = '<div class="d-flex flex-wrap justify-content-between gap-2 mb-2"><span class="fw-semibold">Proposed meeting</span>' + S.responseBadge(m.response) + "</div>" +
          '<dl class="row detail-list mb-0"><div class="col-sm-4"><dt>Date</dt><dd>' + S.formatDate(m.date) + '</dd></div><div class="col-sm-4"><dt>Time</dt><dd>' + S.formatTime(m.time) +
          '</dd></div><div class="col-sm-4"><dt>Location</dt><dd>' + S.esc(m.location) + "</dd></div></dl>" +
          (m.message ? '<p class="small text-muted mb-0">Message: ' + S.esc(m.message) + "</p>" : "") + req;
        const useBtn = document.getElementById("useRequested");
        if (useBtn) useBtn.addEventListener("click", () => {
          openMeeting({ date: m.request.date, time: m.request.time, location: m.location, message: m.message });
        });
      } else if (s.mode === "Anonymous") {
        mBox.innerHTML = '<p class="text-muted mb-0">Meetings are not available for anonymous complaints, because the student has not shared who they are. Use the resolution note to respond.</p>';
      } else {
        mBox.innerHTML = '<p class="text-muted mb-0">No meeting proposed.</p>';
      }
      // Meetings are for identified complaints only.
      const mtBtn = document.getElementById("openMeeting");
      const anon = s.mode === "Anonymous";
      mtBtn.disabled = anon;
      mtBtn.title = anon ? "Meetings are only available for identified complaints" : "";
      document.getElementById("meetingHint").classList.toggle("d-none", !anon);
    }
    render();

    /* Change status */
    const statusSel = document.getElementById("newStatus");
    S.fillSelect(statusSel, S.STATUSES);
    document.getElementById("statusModal").addEventListener("show.bs.modal", () => { statusSel.value = S.getByRef(ref).status; });
    document.getElementById("statusForm").addEventListener("submit", e => {
      e.preventDefault();
      if (!S.selectRule(statusSel, "Please select a status.")) return;
      S.updateByRef(ref, { status: statusSel.value });
      modal("statusModal").hide(); S.clearState(statusSel); render();
      S.showToast("Status changed to <strong>" + S.esc(statusSel.value) + "</strong>.");
    });

    /* Assign staff */
    const staffSel = document.getElementById("staffSelect");
    S.fillSelect(staffSel, ["Unassigned"].concat(S.STAFF));
    document.getElementById("staffModal").addEventListener("show.bs.modal", () => { staffSel.value = S.getByRef(ref).staff; });
    document.getElementById("staffForm").addEventListener("submit", e => {
      e.preventDefault();
      S.updateByRef(ref, { staff: staffSel.value });
      modal("staffModal").hide(); render();
      S.showToast(staffSel.value === "Unassigned" ? "Staff assignment removed." : "Submission assigned to <strong>" + S.esc(staffSel.value) + "</strong>.");
    });

    /* Resolution note */
    const note = document.getElementById("noteText");
    S.attachCounter(note, S.LIMITS.note.max);
    document.getElementById("noteModal").addEventListener("show.bs.modal", () => {
      note.value = S.getByRef(ref).response || ""; S.clearState(note); note.dispatchEvent(new Event("input"));
    });
    document.getElementById("noteForm").addEventListener("submit", e => {
      e.preventDefault();
      if (!S.textLengthRule(note, "Resolution note", S.LIMITS.note.min, S.LIMITS.note.max, true)) { note.focus(); return; }
      S.updateByRef(ref, { response: note.value.trim() });
      modal("noteModal").hide(); render();
      S.showToast("Resolution note added successfully.");
    });

    /* Meeting */
    const md = document.getElementById("mtDate"), mt = document.getElementById("mtTime"), ml = document.getElementById("mtLocation"), mm = document.getElementById("mtMessage");
    md.min = S.todayISO();
    S.attachCounter(mm, S.LIMITS.meetingMessage.max);
    function openMeeting(prefill) {
      if (S.getByRef(ref).mode === "Anonymous") return;
      const cur = prefill || S.getByRef(ref).meeting || {};
      md.value = cur.date || ""; mt.value = cur.time || ""; ml.value = cur.location || "Department Office"; mm.value = cur.message || "";
      [md, mt, ml, mm].forEach(el => S.clearState(el)); mm.dispatchEvent(new Event("input"));
      modal("meetingModal").show();
    }
    document.getElementById("openMeeting").addEventListener("click", () => openMeeting());
    document.getElementById("meetingForm").addEventListener("submit", e => {
      e.preventDefault();
      let ok = true;
      if (!md.value) { S.setError(md, "Meeting date is required."); ok = false; }
      else if (md.value < S.todayISO()) { S.setError(md, "Meeting date cannot be in the past."); ok = false; }
      else S.setValid(md);
      if (!mt.value) { S.setError(mt, "Meeting time is required."); ok = false; } else S.setValid(mt);
      if (!ml.value.trim()) { S.setError(ml, "Location is required."); ok = false; }
      else if (!S.textLengthRule(ml, "Location", S.LIMITS.location.min, S.LIMITS.location.max, true)) ok = false;
      if (!S.textLengthRule(mm, "Message", 0, S.LIMITS.meetingMessage.max, false)) ok = false;
      if (!ok) { S.focusFirstError(document.getElementById("meetingForm")); return; }
      S.updateByRef(ref, { meeting: { date: md.value, time: mt.value, location: ml.value.trim(), message: mm.value.trim(), response: "No Response", request: null } });
      modal("meetingModal").hide(); render();
      S.showToast("Meeting proposed successfully.");
    });
  }

  /* ---------------- Meetings ---------------- */
  function initMeetings() {
    let current = S.param("response") || "";
    const tabs = document.getElementById("respTabs");
    function render() {
      const all = S.loadAll().filter(s => s.meeting);
      const c = { "Confirmed": 0, "Requested Different Time": 0, "No Response": 0 };
      all.forEach(s => { c[s.meeting.response]++; });
      document.getElementById("mCounts").innerHTML = [
        ["Confirmed", c["Confirmed"], "c-resolved"],
        ["Requested different time", c["Requested Different Time"], "c-review"],
        ["No response", c["No Response"], "c-muted"]
      ].map(([l, v, cls]) => '<div class="col-12 col-sm-4"><div class="stat-card ' + cls + '"><div class="stat-value" data-count="' + v + '">' + v + '</div><div class="stat-label">' + l + "</div></div></div>").join("");

      const opts = [["", "All", all.length], ["Confirmed", "Confirmed", c["Confirmed"]], ["Requested Different Time", "Requested different time", c["Requested Different Time"]], ["No Response", "No response", c["No Response"]]];
      tabs.innerHTML = opts.map(([v, l, n]) => '<button type="button" data-v="' + v + '" aria-pressed="' + (current === v) + '">' + l + ' <span class="count-chip">' + n + "</span></button>").join("");
      tabs.querySelectorAll("button").forEach(b => b.addEventListener("click", () => { current = b.dataset.v; render(); }));

      const rows = all.filter(s => !current || s.meeting.response === current).sort((a, b) => a.meeting.date.localeCompare(b.meeting.date));
      document.getElementById("meetingsBody").innerHTML = rows.length ? rows.map(s => {
        const m = s.meeting;
        const req = m.response === "Requested Different Time" && m.request
          ? S.formatDate(m.request.date, true) + ' <br><span class="small text-muted">' + S.formatTime(m.request.time) + "</span>" : "—";
        return '<tr><td class="ref-cell">' + s.ref + "</td><td>" + S.esc(s.category) + '</td><td class="nowrap">' + S.formatDate(m.date, true) +
          '<br><span class="small text-muted">' + S.formatTime(m.time) + "</span></td><td>" + S.esc(m.location) +
          "</td><td>" + S.responseBadge(m.response) + '</td><td class="nowrap">' + req +
          '</td><td class="text-end"><a class="btn btn-sm btn-quiet" href="submission-details.html?ref=' + s.ref + '" aria-label="View ' + s.ref + '">View</a></td></tr>';
      }).join("") : '<tr><td colspan="7" class="text-center py-5 text-muted">No meetings match this filter. Schedule one from a submission’s details page.</td></tr>';
    }
    render();
    S.animateCounts(document.getElementById("mCounts"));
  }

  /* ---------------- Analytics ---------------- */
  function initAnalytics() {
    const data = S.loadAll();
    const c = counts(data);
    const rate = pct(c["Resolved"], c.total);
    const complaints = data;
    const identified = data.filter(s => s.mode === "Identified");

    document.getElementById("aTotal").setAttribute("data-count", c.total);
    document.getElementById("aAnon").setAttribute("data-count", data.filter(s => s.mode === "Anonymous").length);
    document.getElementById("aIdentified").setAttribute("data-count", identified.length);
    document.getElementById("aOpen").setAttribute("data-count", c["Received"] + c["Under Review"]);

    const ring = document.getElementById("rateRing");
    // Ring sweeps from 0 to the resolution rate.
    const paintRing = r => { ring.style.background = "conic-gradient(#2F6FDB " + r * 3.6 + "deg, #E3EAF5 0deg)"; };
    if (S.reducedMotion()) paintRing(rate);
    else {
      const t0 = performance.now();
      const tick = now => { const t = Math.min(1, (now - t0) / 1200); paintRing(rate * (1 - Math.pow(1 - t, 3))); if (t < 1) requestAnimationFrame(tick); };
      paintRing(0); requestAnimationFrame(tick);
    }
    document.getElementById("rateValue").setAttribute("data-count", rate + "%");
    document.getElementById("rateFormula").textContent = c["Resolved"] + " resolved ÷ " + c.total + " total × 100 = " + rate + "%";

    function catRows(list, cats) {
      return cats.map(cat => {
        const items = list.filter(s => s.category === cat);
        const open = items.filter(s => s.status === "Received" || s.status === "Under Review").length;
        const res = items.filter(s => s.status === "Resolved").length;
        return "<tr><td>" + S.esc(cat) + '</td><td class="text-end">' + items.length + '</td><td class="text-end">' + open + '</td><td class="text-end">' + res +
          '</td><td class="text-end">' + (items.length ? Math.round((res / items.length) * 100) + "%" : "—") + "</td></tr>";
      }).join("");
    }
    document.getElementById("complaintCatBody").innerHTML = catRows(complaints, Object.keys(S.COMPLAINT_CATEGORIES));
    // Identified complaints by class timing (anonymous complaints have no class timing)
    document.getElementById("timingBars").innerHTML = barRows(S.CLASS_TIMINGS.map(t => [t, identified.filter(s => s.classTiming === t).length]), Math.max(1, identified.length));
    const closedAll = c["Resolved"] + c["Rejected"];
    document.getElementById("closedNote").textContent = closedAll + " of " + c.total + " submissions are closed (resolved or rejected).";
    document.getElementById("statusBarsA").innerHTML = barRows(S.STATUSES.map(st => [st + " (" + pct(c[st], c.total) + "%)", c[st], STATUS_FILL[st]]), c.total);

    // Monthly volume
    const byMonth = {};
    data.forEach(s => { const k = s.date.slice(0, 7); byMonth[k] = (byMonth[k] || 0) + 1; });
    const months = Object.keys(byMonth).sort().slice(-6);
    const max = Math.max(1, ...months.map(k => byMonth[k]));
    const names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    document.getElementById("volChart").innerHTML = months.map(k =>
      '<div class="vol-col" style="--i:' + months.indexOf(k) + '"><span class="fw-bold mb-1" data-count="' + byMonth[k] + '">' + byMonth[k] + '</span><div class="vol-bar" style="height:' + (byMonth[k] / max) * 100 + '%" role="img" aria-label="' +
      names[+k.slice(5) - 1] + " " + k.slice(0, 4) + ": " + byMonth[k] + ' submissions"></div><span class="mt-1 text-muted">' + names[+k.slice(5) - 1] + "</span></div>").join("");

    // Staff workload
    const staff = ["Unassigned"].concat(S.STAFF).map(n => [n, data.filter(s => s.staff === n).length]);
    document.getElementById("staffBars").innerHTML = barRows(staff, Math.max(1, ...staff.map(x => x[1])));
    S.animateCounts();
  }

  document.addEventListener("DOMContentLoaded", () => {
    const map = { login: initLogin, dashboard: initDashboard, submissions: initSubmissions, details: initDetails, meetings: initMeetings, analytics: initAnalytics };
    if (map[page]) map[page]();
  });
})();
