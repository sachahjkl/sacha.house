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
  statusEl.className = "mt-4 p-3 bg-blue-100 border-2 border-blue-300 text-blue-800";
  statusEl.textContent = "⏳ Fetching registration challenge...";
  statusEl.classList.remove("hidden");

  try {
    const label = getPasskeyLabel();
    const url = `/admin/webauthn/register-challenge?label=${encodeURIComponent(label)}`;
    const publicKey = await fetchPublicKeyOptions(url, decodeCreationOptions);

    statusEl.textContent = "🔐 Please complete the passkey creation on your device...";
    const credential = await navigator.credentials.create({ publicKey });

    statusEl.textContent = "⏳ Verifying registration...";

    const verifyRes = await fetch("/admin/webauthn/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(credentialToJSON(credential)),
    });

    await requireJSONSuccess(verifyRes);
    statusEl.className = "mt-4 p-3 bg-green-100 border-2 border-green-300 text-green-800";
    statusEl.textContent = "✅ Passkey registered successfully!";
    document.getElementById("refresh-passkeys")?.click();
  } catch (error) {
    statusEl.className = "status-error mt-4";
    statusEl.textContent = "❌ Error: " + error.message;
  } finally {
    if (button) button.disabled = false;
  }
}

async function testPasskey(button) {
  if (button?.disabled) return;
  if (button) button.disabled = true;
  const statusEl = document.getElementById("passkey-status");
  statusEl.className = "mt-4 p-3 bg-blue-100 border-2 border-blue-300 text-blue-800";
  statusEl.textContent = "⏳ Fetching authentication challenge...";
  statusEl.classList.remove("hidden");

  try {
    const publicKey = await fetchPublicKeyOptions(
      "/admin/webauthn/login-challenge",
      decodeRequestOptions,
    );

    statusEl.textContent = "🔐 Please complete the passkey verification on your device...";
    const assertion = await navigator.credentials.get({ publicKey });

    statusEl.textContent = "⏳ Verifying authentication...";

    const verifyRes = await fetch("/admin/webauthn/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(credentialToJSON(assertion)),
    });

    await requireJSONSuccess(verifyRes);
    statusEl.className = "mt-4 p-3 bg-green-100 border-2 border-green-300 text-green-800";
    statusEl.textContent = "✅ Passkey authentication successful!";
  } catch (error) {
    statusEl.className = "status-error mt-4";
    statusEl.textContent = "❌ Error: " + error.message;
  } finally {
    if (button) button.disabled = false;
  }
}

async function loginWebAuthnPasskey(button) {
  if (button?.disabled) return;
  if (button) button.disabled = true;
  const statusEl = document.getElementById("login-status");
  statusEl.className = "mt-4 p-3 bg-blue-100 border-2 border-blue-300 text-blue-800";
  statusEl.textContent = "⏳ Fetching authentication challenge...";
  statusEl.classList.remove("hidden");

  try {
    const publicKey = await fetchPublicKeyOptions(
      "/admin/webauthn/login-challenge",
      decodeRequestOptions,
    );

    statusEl.textContent = "🔐 Please complete the passkey verification on your device...";
    const assertion = await navigator.credentials.get({ publicKey });

    statusEl.textContent = "⏳ Verifying authentication...";

    const verifyRes = await fetch("/admin/webauthn/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(credentialToJSON(assertion)),
    });

    await requireJSONSuccess(verifyRes);
    window.location.assign("/admin");
  } catch (error) {
    statusEl.className = "status-error mt-4";
    statusEl.textContent = "❌ Error: " + error.message;
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
    info: "mb-4 border-2 border-blue-300 bg-blue-100 p-3 text-blue-800",
    success: "mb-4 border-2 border-green-300 bg-green-100 p-3 text-green-800",
    error: "mb-4 border-2 border-red-300 bg-red-100 p-3 text-red-800",
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

async function uploadPastedBlogImage(file, slug) {
  const base64 = await fileToBase64(file);
  const response = await fetch("/admin/blogposts/upload-image", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      slug,
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

  let slugWasManual = slugInput.value.trim() !== "";
  let pendingUploads = 0;
  let slugLocked = false;
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
    if (!slugWasManual) {
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
      const upload = await uploadPastedBlogImage(file, slug);
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
  initBlogpostsFilter();
  if (!document.documentElement.dataset.adminEnhancementsReady) {
    document.documentElement.dataset.adminEnhancementsReady = "1";
    document.addEventListener("datastar-fetch", (event) => {
      if (event.detail?.type !== "datastar-patch-elements") return;
      queueMicrotask(() => {
        initBlogEditor();
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
