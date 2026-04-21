// WebAuthn Admin Functions
const ALGORITHM_MAP = {
  ES256: -7,
  RS256: -257,
};
const SUPPORTED_ALGORITHMS = [
  { alg: ALGORITHM_MAP["ES256"], type: "public-key" },
  { alg: ALGORITHM_MAP["RS256"], type: "public-key" },
];

async function registerPasskey() {
  const statusEl = document.getElementById("passkey-status");
  statusEl.className = "mt-4 p-3 bg-blue-100 border-2 border-blue-300 text-blue-800";
  statusEl.textContent = "⏳ Fetching registration challenge...";
  statusEl.classList.remove("hidden");

  try {
    const challengeRes = await fetch("/admin/webauthn/register-challenge");
    const challenge = await challengeRes.json();

    const publicKeyCredentialCreationOptions = {
      challenge: Uint8Array.from(atob(challenge.challenge), (c) => c.charCodeAt(0)),
      rp: {
        name: "sacha.house Admin",
        id: challenge.rp_id,
      },
      user: {
        id: Uint8Array.from(challenge.user_id, (c) => c.charCodeAt(0)),
        name: "admin",
        displayName: "Administrator",
      },
      pubKeyCredParams: SUPPORTED_ALGORITHMS,
      authenticatorSelection: {
        userVerification: "preferred",
        requireResidentKey: true,
        residentKey: "required",
      },
      timeout: 60000,
      attestation: "none",
    };

    statusEl.textContent = "🔐 Please complete the passkey creation on your device...";

    const credential = await navigator.credentials.create({
      publicKey: publicKeyCredentialCreationOptions,
    });

    statusEl.textContent = "⏳ Verifying registration...";

    const credentialData = {
      id: credential.id,
      rawId: btoa(String.fromCharCode(...new Uint8Array(credential.rawId))),
      response: {
        clientDataJSON: btoa(String.fromCharCode(...new Uint8Array(credential.response.clientDataJSON))),
        attestationObject: btoa(String.fromCharCode(...new Uint8Array(credential.response.attestationObject))),
      },
      type: credential.type,
    };

    const verifyRes = await fetch("/admin/webauthn/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(credentialData),
    });

    if (verifyRes.ok) {
      statusEl.className = "mt-4 p-3 bg-green-100 border-2 border-green-300 text-green-800";
      statusEl.textContent = "✅ Passkey registered successfully!";
    } else {
      const error = await verifyRes.text();
      statusEl.className = "status-error mt-4";
      statusEl.textContent = "❌ Registration failed: " + error;
    }
  } catch (error) {
    statusEl.className = "status-error mt-4";
    statusEl.textContent = "❌ Error: " + error.message;
  }
}

async function testPasskey() {
  const statusEl = document.getElementById("passkey-status");
  statusEl.className = "mt-4 p-3 bg-blue-100 border-2 border-blue-300 text-blue-800";
  statusEl.textContent = "⏳ Fetching authentication challenge...";
  statusEl.classList.remove("hidden");

  try {
    const challengeRes = await fetch("/admin/webauthn/login-challenge", {});

    if (!challengeRes.ok) {
      throw new Error(await challengeRes.text());
    }

    const challenge = await challengeRes.json();

    const publicKeyCredentialRequestOptions = {
      challenge: Uint8Array.from(atob(challenge.challenge), (c) => c.charCodeAt(0)),
      timeout: 60000,
      rpId: challenge.rp_id,
    };

    statusEl.textContent = "🔐 Please complete the passkey verification on your device...";

    const assertion = await navigator.credentials.get({
      publicKey: publicKeyCredentialRequestOptions,
    });

    statusEl.textContent = "⏳ Verifying authentication...";

    const assertionData = {
      id: assertion.id,
      rawId: btoa(String.fromCharCode(...new Uint8Array(assertion.rawId))),
      response: {
        clientDataJSON: btoa(String.fromCharCode(...new Uint8Array(assertion.response.clientDataJSON))),
        authenticatorData: btoa(String.fromCharCode(...new Uint8Array(assertion.response.authenticatorData))),
        signature: btoa(String.fromCharCode(...new Uint8Array(assertion.response.signature))),
        userHandle: assertion.response.userHandle
          ? btoa(String.fromCharCode(...new Uint8Array(assertion.response.userHandle)))
          : null,
      },
      type: assertion.type,
    };

    const verifyRes = await fetch("/admin/webauthn/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(assertionData),
    });

    if (verifyRes.ok) {
      statusEl.className = "mt-4 p-3 bg-green-100 border-2 border-green-300 text-green-800";
      statusEl.textContent = "✅ Passkey authentication successful!";
    } else {
      const error = await verifyRes.text();
      statusEl.className = "status-error mt-4";
      statusEl.textContent = "❌ Authentication failed: " + error;
    }
  } catch (error) {
    statusEl.className = "status-error mt-4";
    statusEl.textContent = "❌ Error: " + error.message;
  }
}

async function loginWebAuthnPasskey() {
  const statusEl = document.getElementById("login-status");
  statusEl.className = "mt-4 p-3 bg-blue-100 border-2 border-blue-300 text-blue-800";
  statusEl.textContent = "⏳ Fetching authentication challenge...";
  statusEl.classList.remove("hidden");

  try {
    const challengeRes = await fetch("/admin/webauthn/login-challenge", {});
    if (!challengeRes.ok) {
      statusEl.className = "status-error mt-4";
      statusEl.textContent = "❌ No passkeys registered yet";
      return;
    }

    const challenge = await challengeRes.json();

    const publicKeyCredentialRequestOptions = {
      challenge: Uint8Array.from(atob(challenge.challenge), (c) => c.charCodeAt(0)),
      timeout: 60000,
      rpId: challenge.rp_id,
    };

    statusEl.textContent = "🔐 Please complete the passkey verification on your device...";

    const assertion = await navigator.credentials.get({
      publicKey: publicKeyCredentialRequestOptions,
    });

    statusEl.textContent = "⏳ Verifying authentication...";

    const assertionData = {
      id: assertion.id,
      rawId: btoa(String.fromCharCode(...new Uint8Array(assertion.rawId))),
      response: {
        clientDataJSON: btoa(String.fromCharCode(...new Uint8Array(assertion.response.clientDataJSON))),
        authenticatorData: btoa(String.fromCharCode(...new Uint8Array(assertion.response.authenticatorData))),
        signature: btoa(String.fromCharCode(...new Uint8Array(assertion.response.signature))),
        userHandle: assertion.response.userHandle
          ? btoa(String.fromCharCode(...new Uint8Array(assertion.response.userHandle)))
          : null,
      },
      type: assertion.type,
    };

    const verifyRes = await fetch("/admin/webauthn/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(assertionData),
    });

    if (verifyRes.ok) {
      window.location.href = "/admin";
    } else {
      const error = await verifyRes.text();
      statusEl.className = "status-error mt-4";
      statusEl.textContent = "❌ Authentication failed: " + error;
    }
  } catch (error) {
    statusEl.className = "status-error mt-4";
    statusEl.textContent = "❌ Error: " + error.message;
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
    try {
      setBlogEditorStatus("Uploading pasted image...", "info");
      const upload = await uploadPastedBlogImage(file, slug);
      insertTextAtCursor(markdownInput, `${upload.markdown}\n`);
      setBlogEditorStatus("Image uploaded and inserted into markdown.", "success");
    } catch (error) {
      setBlogEditorStatus(`Upload failed: ${error.message}`, "error");
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
  if (document.body && !document.body.dataset.adminEnhancementsReady) {
    document.body.dataset.adminEnhancementsReady = "1";
    document.body.addEventListener("htmx:afterSwap", () => {
      initBlogEditor();
      initBlogpostsFilter();
    });
  }
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initAdminPageEnhancements);
} else {
  initAdminPageEnhancements();
}
