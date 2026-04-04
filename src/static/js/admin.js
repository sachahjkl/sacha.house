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
