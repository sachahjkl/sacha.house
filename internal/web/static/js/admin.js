function setStatusMessage(element, icon, text) {
  const image = document.createElement("img");
  image.src = "/static/icons/noto/" + icon + ".svg";
  image.alt = "";
  image.setAttribute("aria-hidden", "true");
  image.className = "not-prose mr-[0.3em] inline-block h-[1.1em] w-[1.1em] align-[-0.2em]";
  element.replaceChildren(image, text);
}

function getPasskeyLabel() {
  const input = document.getElementById("passkey-label");
  return input ? input.value.trim() : "";
}

function base64UrlToArrayBuffer(value) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "="));
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function arrayBufferToBase64Url(value) {
  const bytes = new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeCreationOptions(options) {
  return {
    ...options,
    challenge: base64UrlToArrayBuffer(options.challenge),
    user: {
      ...options.user,
      id: base64UrlToArrayBuffer(options.user.id),
    },
    excludeCredentials: (options.excludeCredentials || []).map((credential) => ({
      ...credential,
      id: base64UrlToArrayBuffer(credential.id),
    })),
  };
}

function decodeRequestOptions(options) {
  return {
    ...options,
    challenge: base64UrlToArrayBuffer(options.challenge),
    allowCredentials: (options.allowCredentials || []).map((credential) => ({
      ...credential,
      id: base64UrlToArrayBuffer(credential.id),
    })),
  };
}

async function fetchPublicKeyOptions(url, decode) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(await response.text());
  }
  const payload = await response.json();
  return decode(payload.publicKey);
}

async function requireJSONSuccess(response) {
  if (!response.ok) throw new Error(await response.text());
  if (!response.headers.get("Content-Type")?.includes("application/json")) {
    throw new Error("The admin session expired.");
  }
  const payload = await response.json();
  if (payload.ok !== true) throw new Error("The server rejected the WebAuthn operation.");
}

function credentialToJSON(credential) {
  const response = {
    clientDataJSON: arrayBufferToBase64Url(credential.response.clientDataJSON),
  };

  if ("attestationObject" in credential.response) {
    response.attestationObject = arrayBufferToBase64Url(credential.response.attestationObject);
    if (typeof credential.response.getTransports === "function") {
      response.transports = credential.response.getTransports();
    }
  } else {
    response.authenticatorData = arrayBufferToBase64Url(credential.response.authenticatorData);
    response.signature = arrayBufferToBase64Url(credential.response.signature);
    response.userHandle = credential.response.userHandle
      ? arrayBufferToBase64Url(credential.response.userHandle)
      : null;
  }

  return {
    id: credential.id,
    rawId: arrayBufferToBase64Url(credential.rawId),
    type: credential.type,
    authenticatorAttachment: credential.authenticatorAttachment || null,
    clientExtensionResults: credential.getClientExtensionResults(),
    response,
  };
}

async function registerPasskey(button) {
  if (button?.disabled) return;
  if (button) button.disabled = true;
  const statusEl = document.getElementById("passkey-status");
  statusEl.className = "status mt-4";
  setStatusMessage(statusEl, "hourglass-not-done", "Fetching registration challenge...");
  statusEl.classList.remove("hidden");

  try {
    const label = getPasskeyLabel();
    const url = `/admin/webauthn/register-challenge?label=${encodeURIComponent(label)}`;
    const publicKey = await fetchPublicKeyOptions(url, decodeCreationOptions);

    setStatusMessage(statusEl, "locked-with-key", "Please complete the passkey creation on your device...");
    const credential = await navigator.credentials.create({ publicKey });

    setStatusMessage(statusEl, "hourglass-not-done", "Verifying registration...");

    const verifyRes = await fetch("/admin/webauthn/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(credentialToJSON(credential)),
    });

    await requireJSONSuccess(verifyRes);
    statusEl.className = "status status-ok mt-4";
    setStatusMessage(statusEl, "check-mark-button", "Passkey registered successfully!");
    document.getElementById("refresh-passkeys")?.click();
  } catch (error) {
    statusEl.className = "status status-error mt-4";
    setStatusMessage(statusEl, "cross-mark", "Error: " + error.message);
  } finally {
    if (button) button.disabled = false;
  }
}

async function testPasskey(button) {
  if (button?.disabled) return;
  if (button) button.disabled = true;
  const statusEl = document.getElementById("passkey-status");
  statusEl.className = "status mt-4";
  setStatusMessage(statusEl, "hourglass-not-done", "Fetching authentication challenge...");
  statusEl.classList.remove("hidden");

  try {
    const publicKey = await fetchPublicKeyOptions(
      "/admin/webauthn/login-challenge",
      decodeRequestOptions,
    );

    setStatusMessage(statusEl, "locked-with-key", "Please complete the passkey verification on your device...");
    const assertion = await navigator.credentials.get({ publicKey });

    setStatusMessage(statusEl, "hourglass-not-done", "Verifying authentication...");

    const verifyRes = await fetch("/admin/webauthn/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(credentialToJSON(assertion)),
    });

    await requireJSONSuccess(verifyRes);
    statusEl.className = "status status-ok mt-4";
    setStatusMessage(statusEl, "check-mark-button", "Passkey authentication successful!");
  } catch (error) {
    statusEl.className = "status status-error mt-4";
    setStatusMessage(statusEl, "cross-mark", "Error: " + error.message);
  } finally {
    if (button) button.disabled = false;
  }
}

async function loginWebAuthnPasskey(button) {
  if (button?.disabled) return;
  if (button) button.disabled = true;
  const statusEl = document.getElementById("login-status");
  statusEl.className = "status mt-4";
  setStatusMessage(statusEl, "hourglass-not-done", "Fetching authentication challenge...");
  statusEl.classList.remove("hidden");

  try {
    const publicKey = await fetchPublicKeyOptions(
      "/admin/webauthn/login-challenge",
      decodeRequestOptions,
    );

    setStatusMessage(statusEl, "locked-with-key", "Please complete the passkey verification on your device...");
    const assertion = await navigator.credentials.get({ publicKey });

    setStatusMessage(statusEl, "hourglass-not-done", "Verifying authentication...");

    const verifyRes = await fetch("/admin/webauthn/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(credentialToJSON(assertion)),
    });

    await requireJSONSuccess(verifyRes);
    window.location.assign("/admin");
  } catch (error) {
    statusEl.className = "status status-error mt-4";
    setStatusMessage(statusEl, "cross-mark", "Error: " + error.message);
  } finally {
    if (button) button.disabled = false;
  }
}

function slugifyBlogTitle(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
}

function setBlogEditorStatus(message, type = "info") {
  const statusEl = document.getElementById("blog-editor-status");
  if (!statusEl) return;

  const classes = {
    info: "status mb-4",
    success: "status status-ok mb-4",
    error: "status status-error mb-4",
  };

  statusEl.className = classes[type] || classes.info;
  statusEl.textContent = message;
  statusEl.classList.remove("hidden");
}

function insertTextAtCursor(textarea, text) {
  const start = textarea.selectionStart;
  const end = textarea.selectionEnd;
  const before = textarea.value.slice(0, start);
  const after = textarea.value.slice(end);
  textarea.value = `${before}${text}${after}`;
  const nextPos = start + text.length;
  textarea.selectionStart = nextPos;
  textarea.selectionEnd = nextPos;
  textarea.dispatchEvent(new Event("input", { bubbles: true }));
  textarea.focus();
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = String(reader.result || "");
      const [, base64 = ""] = result.split(",", 2);
      resolve(base64);
    };
    reader.onerror = () => reject(reader.error || new Error("Could not read file"));
    reader.readAsDataURL(file);
  });
}

async function uploadPastedBlogImage(file, slug, currentSlug) {
  const base64 = await fileToBase64(file);
  const response = await fetch("/admin/blogposts/upload-image", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      slug,
      currentSlug,
      filename: file.name || "pasted-image.png",
      mimeType: file.type,
      dataBase64: base64,
    }),
  });

  if (!response.ok) {
    throw new Error(await response.text());
  }

  return response.json();
}

function initBlogEditor() {
  const form = document.querySelector("form[data-blog-editor]");
  if (!form || form.dataset.blogEditorReady === "1") return;
  form.dataset.blogEditorReady = "1";

  const titleInput = document.getElementById("blog-title");
  const slugInput = document.getElementById("blog-slug");
  const markdownInput = document.getElementById("blog-markdown");
  const publishedAtInput = document.getElementById("blog-published-at");
  const publishedAtPickerButton = document.getElementById("blog-published-at-picker");
  if (!titleInput || !slugInput || !markdownInput) return;

  const currentSlug = form.dataset.currentSlug || "";
  let slugWasManual = slugInput.value.trim() !== "";
  let pendingUploads = 0;
  // A new post that failed to save comes back with its images, already stored under this slug.
  let slugLocked = currentSlug === "" && slugInput.value !== "" && markdownInput.value.includes(`/media/blog/${slugInput.value}/`);
  const submitButtons = Array.from(form.querySelectorAll('button[type="submit"]'));
  const updateUploadState = () => {
    slugInput.readOnly = slugLocked || pendingUploads > 0;
    for (const button of submitButtons) button.disabled = pendingUploads > 0;
  };

  form.addEventListener("submit", (event) => {
    if (pendingUploads === 0) return;
    event.preventDefault();
    setBlogEditorStatus("Wait for the image upload to finish before saving.", "error");
  });

  titleInput.addEventListener("input", () => {
    if (!slugWasManual && !slugLocked && pendingUploads === 0) {
      slugInput.value = slugifyBlogTitle(titleInput.value);
    }
  });

  slugInput.addEventListener("input", () => {
    slugWasManual = true;
  });

  if (publishedAtInput && publishedAtPickerButton) {
    publishedAtPickerButton.addEventListener("click", () => {
      if (typeof publishedAtInput.showPicker === "function") {
        publishedAtInput.showPicker();
      } else {
        publishedAtInput.focus();
        publishedAtInput.click();
      }
    });
  }

  updateUploadState();

  markdownInput.addEventListener("paste", async (event) => {
    const items = Array.from(event.clipboardData?.items || []);
    const imageItem = items.find((item) => item.type.startsWith("image/"));
    if (!imageItem) return;

    const slug = slugifyBlogTitle(slugInput.value.trim());
    if (!slug) {
      event.preventDefault();
      setBlogEditorStatus("Set the slug before pasting an image.", "error");
      return;
    }

    const file = imageItem.getAsFile();
    if (!file) return;

    event.preventDefault();
    pendingUploads += 1;
    updateUploadState();
    try {
      setBlogEditorStatus("Uploading pasted image...", "info");
      const upload = await uploadPastedBlogImage(file, slug, currentSlug);
      insertTextAtCursor(markdownInput, `${upload.markdown}\n`);
      slugLocked = true;
      setBlogEditorStatus("Image uploaded and inserted into markdown.", "success");
    } catch (error) {
      setBlogEditorStatus(`Upload failed: ${error.message}`, "error");
    } finally {
      pendingUploads -= 1;
      updateUploadState();
    }
  });
}

// Checks the session before a form that holds typed text is sent: a redirect to the login page would lose it.
function initSessionGuards() {
  for (const form of document.querySelectorAll("form[data-session-guard]")) {
    if (form.dataset.sessionGuardReady === "1") continue;
    form.dataset.sessionGuardReady = "1";

    const showError = (message) => {
      const statusEl = document.getElementById(form.dataset.sessionGuard);
      if (!statusEl) return;
      statusEl.className = "status status-error mb-4";
      statusEl.textContent = message;
    };

    form.addEventListener("submit", async (event) => {
      if (event.defaultPrevented) return;
      if (form.dataset.sessionChecked === "1") {
        delete form.dataset.sessionChecked;
        return;
      }
      event.preventDefault();
      const submitter = event.submitter || undefined;
      try {
        const response = await fetch("/admin/session", { cache: "no-store" });
        if (response.status === 401) {
          showError("Your session expired, and nothing was sent. Log in again in another tab, then save here.");
          return;
        }
      } catch (error) {
        showError("The server cannot be reached, and nothing was sent. Save again when it is back.");
        return;
      }
      form.dataset.sessionChecked = "1";
      form.requestSubmit(submitter);
    });
  }
}

function initBlogpostsFilter() {
  const input = document.getElementById("blogposts-filter");
  const list = document.getElementById("blogposts-list");
  if (!input || !list || input.dataset.blogpostsFilterReady === "1") return;

  input.dataset.blogpostsFilterReady = "1";
  const items = Array.from(list.querySelectorAll("[data-blogpost-item]"));
  const emptyState = document.getElementById("blogposts-filter-empty");

  const applyFilter = () => {
    const needle = input.value.trim().toLowerCase();
    let visibleCount = 0;

    items.forEach((item) => {
      const matches = needle === "" || item.textContent.toLowerCase().includes(needle);
      item.classList.toggle("hidden", !matches);
      if (matches) visibleCount += 1;
    });

    if (emptyState) {
      emptyState.classList.toggle("hidden", visibleCount !== 0);
    }
  };

  input.addEventListener("input", applyFilter);
  applyFilter();
}

function initAdminPageEnhancements() {
  initBlogEditor();
  initSessionGuards();
  initBlogpostsFilter();
  if (!document.documentElement.dataset.adminEnhancementsReady) {
    document.documentElement.dataset.adminEnhancementsReady = "1";
    document.addEventListener("datastar-fetch", (event) => {
      if (event.detail?.type !== "datastar-patch-elements") return;
      queueMicrotask(() => {
        initBlogEditor();
        initSessionGuards();
        initBlogpostsFilter();
      });
    });
  }
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initAdminPageEnhancements);
} else {
  initAdminPageEnhancements();
}
