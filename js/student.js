/* =========================================================
   Student Voice Portal — student.js
   Handles complaint submission, success, tracking,
   status display and meeting responses.
   ========================================================= */
(function () {
  "use strict";
  const S = window.SVP;

  /* ---------------- Anonymous complaint ---------------- */
  function initAnonymous() {
    const form = document.getElementById("anonForm");
    const cat = document.getElementById("anonCategory");
    const opt = document.getElementById("anonOption");
    S.fillSelect(cat, Object.keys(S.COMPLAINT_CATEGORIES), "Select a category");

    cat.addEventListener("change", () => {
      if (cat.value) {
        S.fillSelect(opt, S.COMPLAINT_CATEGORIES[cat.value], "Select an option");
        opt.disabled = false;
        S.setValid(cat);
      } else {
        S.fillSelect(opt, [], "Select a category first");
        opt.disabled = true;
      }
      S.clearState(opt);
      showInfo();
    });
    opt.addEventListener("change", () => { if (opt.value) S.setValid(opt); showInfo(); });

    // Shows the fixed description for the chosen option (no free text is collected).
    const info = document.getElementById("optionInfo");
    function showInfo() {
      const text = S.OPTION_INFO[opt.value];
      if (text) {
        info.innerHTML = '<span class="option-info-label">What this complaint means</span><p class="mb-0">' + S.esc(text) + "</p>";
        info.classList.add("show");
      } else {
        info.innerHTML = "";
        info.classList.remove("show");
      }
    }

    form.addEventListener("submit", e => {
      e.preventDefault();
      const ok = [
        S.selectRule(cat, "Please select a category."),
        S.selectRule(opt, "Please select a complaint option.")
      ].every(Boolean);
      if (!ok) { S.focusFirstError(form); return; }

      // Anonymous: no name, registration number, batch, section, account or free text is stored.
      const sub = {
        ref: S.generateRef(), type: "Complaint", mode: "Anonymous",
        category: cat.value, option: opt.value,
        date: S.todayISO(), status: "Received", staff: "Unassigned", response: "", meeting: null
      };
      S.addSubmission(sub);
      window.location.href = "success.html?ref=" + encodeURIComponent(sub.ref);
    });
  }

  /* ---------------- Shared identity fields ---------------- */
  function initIdentityFields() {
    S.fillSelect(document.getElementById("batch"), S.BATCHES, "Select");
    S.fillSelect(document.getElementById("section"), S.SECTIONS, "Select");
    const reg = document.getElementById("regNo");
    reg.addEventListener("input", () => {
      const pos = reg.selectionStart;
      reg.value = reg.value.toUpperCase();
      reg.setSelectionRange(pos, pos);
    });
  }
  document.addEventListener("change", e => {
    if (e.target && e.target.name === "classTiming") {
      document.querySelectorAll('input[name="classTiming"]').forEach(r => { r.classList.remove("is-invalid"); r.classList.add("is-valid"); });
      const er = document.getElementById("classTiming-error");
      if (er) { er.textContent = ""; er.classList.remove("d-block"); }
    }
  });
  function validateIdentity() {
    const reg = document.getElementById("regNo");
    const v = reg.value.trim();
    let regOk = true;
    if (!v) { S.setError(reg, "Registration number is required."); regOk = false; }
    else if (!S.REG_PATTERN.test(v)) { S.setError(reg, "Enter the registration number in the format YYYY-DEPT-NNN, for example 2023-CS-045."); regOk = false; }
    else S.setValid(reg);
    const b = S.selectRule(document.getElementById("batch"), "Please select a batch.");
    const radios = document.querySelectorAll('input[name="classTiming"]');
    const timingErr = document.getElementById("classTiming-error");
    const chosen = document.querySelector('input[name="classTiming"]:checked');
    radios.forEach(r => { r.classList.toggle("is-invalid", !chosen); r.classList.toggle("is-valid", !!chosen); });
    timingErr.textContent = chosen ? "" : "Please select a class timing.";
    timingErr.classList.toggle("d-block", !chosen);
    const s = S.selectRule(document.getElementById("section"), "Please select a section.");
    return regOk && b && s && !!chosen;
  }

  /* ---------------- Identified complaint ---------------- */
  function initIdentified() {
    initIdentityFields();
    const form = document.getElementById("identifiedForm");
    const cat = document.getElementById("category");
    const desc = document.getElementById("description");
    S.fillSelect(cat, Object.keys(S.COMPLAINT_CATEGORIES), "Select a category");
    S.attachCounter(desc, S.LIMITS.description.max);

    form.addEventListener("submit", e => {
      e.preventDefault();
      const ok = [
        validateIdentity(),
        S.selectRule(cat, "Please select a category."),
        S.textLengthRule(desc, "Description", S.LIMITS.description.min, S.LIMITS.description.max, true)
      ].every(Boolean);
      if (!ok) { S.focusFirstError(form); return; }
      const sub = {
        ref: S.generateRef(), type: "Complaint", mode: "Identified",
        regNo: document.getElementById("regNo").value.trim(),
        batch: document.getElementById("batch").value,
        section: document.getElementById("section").value,
        classTiming: document.querySelector('input[name="classTiming"]:checked').value,
        category: cat.value, description: desc.value.trim(),
        date: S.todayISO(), status: "Received", staff: "Unassigned", response: "", meeting: null
      };
      S.addSubmission(sub);
      window.location.href = "success.html?ref=" + encodeURIComponent(sub.ref);
    });
  }

  /* ---------------- Success ---------------- */
  function initSuccess() {
    const sub = S.getByRef(S.param("ref"));
    const box = document.getElementById("successBox");
    if (!sub) {
      box.innerHTML = '<div class="text-center"><h1 class="h3">No recent submission found</h1>' +
        '<p class="text-muted">Submit a complaint to receive a tracking reference.</p>' +
        '<a class="btn btn-primary" href="complaint.html">Submit a complaint</a></div>';
      return;
    }
    document.getElementById("sType").textContent = (sub.mode === "Anonymous" ? "Anonymous " : "") + sub.type;
    document.getElementById("sCategory").textContent = sub.category + (sub.option ? " — " + sub.option : "");
    const sInfo = document.getElementById("sInfo");
    if (sInfo && sub.option && S.OPTION_INFO[sub.option]) { sInfo.textContent = S.OPTION_INFO[sub.option]; sInfo.classList.remove("d-none"); }
    document.getElementById("sDate").textContent = S.formatDate(sub.date);
    document.getElementById("sRef").textContent = sub.ref;
    document.getElementById("trackBtn").href = "track.html?ref=" + encodeURIComponent(sub.ref);

    document.getElementById("copyBtn").addEventListener("click", () => {
      const done = () => S.showToast("Reference copied");
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(sub.ref).then(done, () => fallbackCopy(sub.ref, done));
      } else fallbackCopy(sub.ref, done);
    });
  }
  function fallbackCopy(text, cb) {
    const t = document.createElement("textarea");
    t.value = text; document.body.appendChild(t); t.select();
    try { document.execCommand("copy"); } catch (e) { /* ignore */ }
    document.body.removeChild(t); cb();
  }

  /* ---------------- Track ---------------- */
  function initTrack() {
    const form = document.getElementById("trackForm");
    const input = document.getElementById("trackRef");
    const pre = S.param("ref");
    if (pre) input.value = pre;
    input.addEventListener("input", () => { input.value = input.value.toUpperCase(); });

    document.querySelectorAll("[data-sample]").forEach(btn => {
      btn.addEventListener("click", () => { input.value = btn.dataset.sample; S.clearState(input); input.focus(); });
    });

    if (S.param("go")) setTimeout(() => form.requestSubmit ? form.requestSubmit() : form.dispatchEvent(new Event("submit", { cancelable: true })), 0);
    form.addEventListener("submit", e => {
      e.preventDefault();
      const v = input.value.trim().toUpperCase();
      input.value = v;
      if (!v) { S.setError(input, "Tracking reference is required."); input.focus(); return; }
      if (!S.REF_PATTERN.test(v)) { S.setError(input, "Please enter a valid tracking reference, for example SVP-8F4K29."); input.focus(); return; }
      if (!S.getByRef(v)) { S.setError(input, "No submission was found for " + v + ". Check the reference and try again."); input.focus(); return; }
      S.setValid(input);
      window.location.href = "status.html?ref=" + encodeURIComponent(v);
    });
  }

  /* ---------------- Status ---------------- */
  function initStatus() {
    const sub = S.getByRef(S.param("ref"));
    const box = document.getElementById("statusBox");
    if (!sub) {
      box.innerHTML = '<div class="svp-panel svp-panel-pad text-center"><h1 class="h3">Submission not found</h1>' +
        '<p class="text-muted">Enter a valid tracking reference to see its status.</p><a class="btn btn-primary" href="track.html">Track a submission</a></div>';
      return;
    }
    document.getElementById("stRef").textContent = sub.ref;
    const crumb = document.getElementById("stCrumb"); if (crumb) crumb.textContent = sub.ref;
    document.getElementById("stType").innerHTML = S.typePill(sub);
    document.getElementById("stCategory").textContent = sub.category;
    const issueWrap = document.getElementById("stIssueWrap");
    if (sub.option) {
      document.getElementById("stIssueLabel").textContent = "Complaint option";
      document.getElementById("stIssue").innerHTML = S.esc(sub.option) +
        (S.OPTION_INFO[sub.option] ? '<span class="d-block fw-normal small text-muted mt-1">' + S.esc(S.OPTION_INFO[sub.option]) + "</span>" : "");
      issueWrap.className = "col-12";
    } else {
      document.getElementById("stIssueLabel").textContent = "Your description";
      const dd = document.getElementById("stIssue");
      dd.textContent = sub.description || "—";
      dd.classList.add("fw-normal");
      issueWrap.className = "col-12";
    }
    document.getElementById("stDate").textContent = S.formatDate(sub.date);
    document.getElementById("stStatus").innerHTML = S.statusBadge(sub.status);
    document.getElementById("stTimeline").innerHTML = S.timelineHTML(sub.status);
    const msg = {
      "Received": ["bi-inbox", "Your complaint has reached the department and is waiting to be reviewed."],
      "Under Review": ["bi-search", "Department staff are looking into your complaint now."],
      "Resolved": ["bi-check-circle", "Your complaint has been resolved. Read the department's response below."],
      "Rejected": ["bi-x-circle", "Your complaint has been closed. The reason is in the department's response below."]
    }[sub.status];
    const sm = document.getElementById("stMessage");
    if (msg && sm) { sm.className = "status-msg st-" + sub.status.toLowerCase().replace(" ", "-"); sm.innerHTML = '<i class="bi ' + msg[0] + '" aria-hidden="true"></i><span>' + msg[1] + "</span>"; }

    document.getElementById("stResponse").innerHTML = sub.response
      ? '<blockquote class="mb-0 border-start border-4 ps-3" style="border-color:var(--brand)!important">' + S.esc(sub.response) + "</blockquote>"
      : '<p class="text-muted mb-0">No response has been added yet. Check back after the department reviews your submission.</p>';

    const mBox = document.getElementById("stMeeting");
    if (sub.meeting) {
      const m = sub.meeting;
      mBox.innerHTML =
        '<div class="d-flex justify-content-between align-items-start gap-2 mb-2"><h2 class="h6 mb-0">Meeting proposed</h2>' + S.responseBadge(m.response) + "</div>" +
        '<dl class="detail-list mb-2"><dt>Date and time</dt><dd>' + S.formatDate(m.date) + ", " + S.formatTime(m.time) + "</dd>" +
        "<dt>Location</dt><dd>" + S.esc(m.location) + "</dd></dl>" +
        '<a class="btn btn-primary w-100" href="meeting.html?ref=' + encodeURIComponent(sub.ref) + '">View and respond</a>';
    } else if (sub.mode === "Anonymous") {
      mBox.innerHTML = '<h2 class="h6">Meeting</h2><p class="text-muted mb-0">Meetings are only arranged for identified complaints, so your anonymity is kept. The department will reply through the response on this page.</p>';
    } else {
      mBox.innerHTML = '<h2 class="h6">Meeting</h2><p class="text-muted mb-0">No meeting has been proposed for this submission.</p>';
    }
  }

  /* ---------------- Meeting ---------------- */
  function initMeeting() {
    const ref = S.param("ref");
    const box = document.getElementById("meetingBox");
    let sub = S.getByRef(ref);
    if (!sub || !sub.meeting || sub.mode === "Anonymous") {
      box.innerHTML = '<div class="svp-panel svp-panel-pad text-center"><h1 class="h3">No meeting found</h1>' +
        '<p class="text-muted">There is no meeting proposal for this tracking reference.</p>' +
        '<a class="btn btn-primary" href="track.html">Track a submission</a></div>';
      return;
    }
    const back = document.getElementById("backToStatus");
    back.href = "status.html?ref=" + encodeURIComponent(sub.ref);
    document.getElementById("mRefCrumb").href = back.href;

    const reqForm = document.getElementById("requestForm");
    const actions = document.getElementById("meetingActions");

    function render() {
      sub = S.getByRef(ref);
      const m = sub.meeting;
      document.getElementById("mRef").textContent = sub.ref;
      document.getElementById("mDate").textContent = S.formatDate(m.date);
      document.getElementById("mTime").textContent = S.formatTime(m.time);
      document.getElementById("mLocation").textContent = m.location;
      document.getElementById("mMessage").textContent = m.message || "No additional instructions.";
      document.getElementById("mResponse").innerHTML = S.responseBadge(m.response);
      const reqBox = document.getElementById("mRequested");
      if (m.response === "Requested Different Time" && m.request) {
        reqBox.innerHTML = '<div class="demo-note"><strong>Your requested time:</strong> ' + S.formatDate(m.request.date) + " at " + S.formatTime(m.request.time) +
          (m.request.message ? '<br><span class="small">Message: ' + S.esc(m.request.message) + "</span>" : "") +
          '<br><span class="small">The department will review your request and may propose a new time.</span></div>';
      } else reqBox.innerHTML = "";
      document.getElementById("confirmBtn").disabled = m.response === "Confirmed";
    }
    render();

    document.getElementById("confirmBtn").addEventListener("click", () => {
      const m = Object.assign({}, sub.meeting, { response: "Confirmed", request: null });
      S.updateByRef(sub.ref, { meeting: m });
      reqForm.classList.add("d-none");
      render();
      S.showToast("Meeting confirmed");
    });

    document.getElementById("requestBtn").addEventListener("click", () => {
      reqForm.classList.remove("d-none");
      document.getElementById("prefDate").focus();
    });
    document.getElementById("cancelRequest").addEventListener("click", () => {
      reqForm.classList.add("d-none");
      reqForm.reset();
      reqForm.querySelectorAll(".is-invalid,.is-valid").forEach(el => S.clearState(el));
    });

    const pd = document.getElementById("prefDate");
    pd.min = S.todayISO();
    S.attachCounter(document.getElementById("prefMessage"), S.LIMITS.requestMessage.max);

    reqForm.addEventListener("submit", e => {
      e.preventDefault();
      const pt = document.getElementById("prefTime");
      const pm = document.getElementById("prefMessage");
      let ok = true;
      if (!pd.value) { S.setError(pd, "Preferred date is required."); ok = false; }
      else if (pd.value < S.todayISO()) { S.setError(pd, "Preferred date cannot be in the past."); ok = false; }
      else S.setValid(pd);
      if (!pt.value) { S.setError(pt, "Preferred time is required."); ok = false; } else S.setValid(pt);
      if (!S.textLengthRule(pm, "Message", 0, S.LIMITS.requestMessage.max, false)) ok = false;
      if (!ok) { S.focusFirstError(reqForm); return; }

      const m = Object.assign({}, sub.meeting, {
        response: "Requested Different Time",
        request: { date: pd.value, time: pt.value, message: pm.value.trim() }
      });
      S.updateByRef(sub.ref, { meeting: m });
      reqForm.reset();
      reqForm.querySelectorAll(".is-invalid,.is-valid").forEach(el => S.clearState(el));
      reqForm.classList.add("d-none");
      render();
      S.showToast("Request sent to the department");
      actions.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    const page = document.body.dataset.page;
    const map = {
      anonymous: initAnonymous, identified: initIdentified,
      success: initSuccess, track: initTrack, status: initStatus, meeting: initMeeting
    };
    if (map[page]) map[page]();
  });
})();
