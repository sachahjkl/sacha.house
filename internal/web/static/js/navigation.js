const { actions } = await import(`/static/js/datastar.js${new URL(import.meta.url).search}`);

const MARKER = "datastar-navigation";
const REQUEST_CLASS = "datastar-request";
const cleanups = new Map();
const nativeSubmits = new WeakSet();
let request;
let requestId = 0;
let requestSource;

history.scrollRestoration = "manual";
history.replaceState(state(location.href), "", location.href);

function state(url, current = history.state) {
  return { ...current, datastarNavigation: true, url, x: scrollX, y: scrollY };
}

function saveScroll() {
  history.replaceState(state(location.href), "", location.href);
}

function excluded(element) {
  return element.closest("[data-no-boost]") || (element.target && element.target !== "_self");
}

function error(reason, detail) {
  return Object.assign(new Error(reason), { detail });
}

function emit(type, detail, cancelable = false) {
  return document.dispatchEvent(new CustomEvent(`datastar:navigation-${type}`, { detail, cancelable }));
}

function focusAndScroll(url, position) {
  const main = document.querySelector("#main");
  if (main) {
    if (!main.matches("a, button, input, select, textarea, [tabindex]")) main.tabIndex = -1;
    main.focus({ preventScroll: true });
  }

  if (position) {
    scrollTo(position.x || 0, position.y || 0);
    return;
  }

  const hash = new URL(url).hash;
  if (hash) {
    let id = hash.slice(1);
    try { id = decodeURIComponent(id); } catch {}
    const target = document.getElementById(id) || document.querySelector(`[name="${CSS.escape(id)}"]`);
    if (target) {
      target.scrollIntoView();
      return;
    }
  }
  scrollTo(0, 0);
}

function focusValidationError() {
  const target = document.querySelector("#main [aria-invalid='true'], #main :invalid, #main [role='alert']");
  if (!target) return;
  if (!target.matches("a, button, input, select, textarea, [tabindex]")) target.tabIndex = -1;
  target.focus({ preventScroll: true });
  target.scrollIntoView({ block: "center" });
}

function syncHiddenInputs() {
  for (const input of document.querySelectorAll('input[type="hidden"]')) {
    input.value = input.getAttribute("value") || "";
  }
}

function fullNavigation(job) {
  if (job.popstate) {
    location.replace(job.url);
    return;
  }
  if (job.form && job.method !== "GET") {
    location.reload();
    return;
  }
  if (!job.form) {
    location.assign(job.url);
    return;
  }

  if (job.form.isConnected) {
    nativeSubmits.add(job.form);
    job.form.requestSubmit(job.submitter || undefined);
    return;
  }
  location.assign(job.url);
}

async function navigate(job) {
  if (!emit("before", job, true)) return;

  if (!job.popstate) saveScroll();
  const source = job.form || job.link || document.documentElement;
  requestSource?.classList.remove(REQUEST_CLASS);
  request?.abort();
  request = new AbortController();
  requestSource = source;
  const controller = request;
  const id = ++requestId;
  let status = 0;
  let patched = false;
  const onFetch = (event) => {
    if (event.detail.el !== source) return;
    if (event.detail.type === "error") status = Number(event.detail.argsRaw.status);
    if (event.detail.type === "datastar-patch-elements") patched = true;
  };

  document.addEventListener("datastar-fetch", onFetch);
  document.documentElement.classList.add(REQUEST_CLASS);
  document.documentElement.setAttribute("aria-busy", "true");
  source.classList.add(REQUEST_CLASS);

  try {
    const options = {
      contentType: job.form ? "form" : "json",
      payload: job.form ? undefined : {},
      requestCancellation: controller,
      retry: "never",
      retryMaxCount: 0,
    };
    const context = { el: source, evt: job.event, error, cleanups };
    const enctype = job.submitter?.formEnctype;
    const oldEnctype = job.form?.getAttribute("enctype");
    if (job.form && enctype) job.form.enctype = enctype;
    const pending = actions[job.method.toLowerCase()](context, job.url, options);
    if (job.form && enctype) {
      if (oldEnctype === null) job.form.removeAttribute("enctype");
      else job.form.setAttribute("enctype", oldEnctype);
    }
    await pending;

    if (controller.signal.aborted || id !== requestId) return;
    syncHiddenInputs();
    const marker = document.getElementById(MARKER);
    const markerStatus = Number(marker?.dataset.status || 200);
    status ||= Number.isFinite(markerStatus) ? markerStatus : 500;
    if (!patched) throw error(`Navigation failed with status ${status}`);

    const url = new URL(marker?.dataset.url || job.url, location.href).href;
    const serverHistory = marker?.dataset.history?.toLowerCase();
    const mode = serverHistory === "replace" ? "replace" :
      serverHistory === "push" || serverHistory === "true" ? "push" :
      serverHistory === "none" || serverHistory === "false" ? "none" :
      job.form && url !== job.url ? "replace" : job.history;
    const nextState = {
      datastarNavigation: true,
      url,
      x: job.position?.x || 0,
      y: job.position?.y || 0,
    };
    if (mode === "push") history.pushState(nextState, "", url);
    if (mode === "replace") history.replaceState(nextState, "", url);
    if (status < 400) focusAndScroll(url, job.position);
    else if (status < 500) focusValidationError();
    emit("after", { ...job, url, status });
  } catch (cause) {
    if (controller.signal.aborted || id !== requestId) return;
    emit("error", { ...job, cause });
    fullNavigation(job);
  } finally {
    document.removeEventListener("datastar-fetch", onFetch);
    if (id === requestId) {
      document.documentElement.classList.remove(REQUEST_CLASS);
      document.documentElement.removeAttribute("aria-busy");
      source.classList.remove(REQUEST_CLASS);
      requestSource = undefined;
    }
  }
}

document.addEventListener("click", (event) => {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  const link = event.target.closest?.("a[href]");
  if (!link || excluded(link) || link.hasAttribute("download")) return;
  if (link.getAttribute("href").startsWith("#")) return;
  const url = new URL(link.href, location.href);
  if (url.origin !== location.origin) return;
  if (url.hash && url.pathname === location.pathname && url.search === location.search) return;
  event.preventDefault();
  navigate({ event, link, method: "GET", url: url.href, history: "push" });
});

document.addEventListener("submit", (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement)) return;
  if (nativeSubmits.delete(form) || event.defaultPrevented) return;
  const submitter = event.submitter;
  if (excluded(form) || submitter?.closest("[data-no-boost]") ||
      (submitter?.formTarget && submitter.formTarget !== "_self")) return;
  const method = (submitter?.formMethod || form.method || "GET").toUpperCase();
  if (method !== "GET" && method !== "POST") return;
  if (!form.noValidate && !submitter?.formNoValidate && !form.reportValidity()) return;
  const url = new URL(submitter?.formAction || form.action || location.href, location.href);
  if (url.origin !== location.origin) return;
  if (method === "GET") url.search = "";
  event.preventDefault();
  navigate({ event, form, submitter, method, url: url.href, history: "none" });
});

addEventListener("popstate", (event) => {
  const url = event.state?.url || location.href;
  navigate({ method: "GET", url, history: "replace", position: event.state, popstate: true });
});

function initMobileNavigation() {
  const summary = document.getElementById("nav-summary");
  const details = summary?.closest("details");
  if (!summary || !details || details.dataset.navigationReady === "1") return;
  details.dataset.navigationReady = "1";
  const update = () => { summary.textContent = details.open ? "Close navigation" : "Open navigation"; };
  details.addEventListener("toggle", update);
  update();
}

document.addEventListener("datastar:navigation-after", initMobileNavigation);
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", initMobileNavigation);
else initMobileNavigation();

let scrollFrame;
addEventListener("scroll", () => {
  cancelAnimationFrame(scrollFrame);
  scrollFrame = requestAnimationFrame(saveScroll);
}, { passive: true });
