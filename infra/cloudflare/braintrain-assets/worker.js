// Cloudflare Worker "braintrain-assets": serves objects from the private R2
// bucket `braintrain` (binding ASSETS).
//
// - Keys under PUBLIC_PREFIX (Brain Train game content: manifest, registries,
//   levels, symbol art) are public and read-only. No token needed.
// - Every other key needs `Authorization: Bearer <payload>.<signature>`:
//   payload = base64url(JSON {aud: "bt-assets", exp: <unix seconds>}),
//   signature = base64url(HMAC-SHA256(payload, ASSET_TOKEN_SECRET)).
//   Tokens may live at most TOKEN_MAX_TTL_SECONDS.
//
// Source of truth for the deployed Worker. Deploy by pasting into the
// dashboard editor (Workers > braintrain-assets > Edit code) or with wrangler.

const TOKEN_MAX_TTL_SECONDS = 10 * 60; // 10 minutes
const PUBLIC_PREFIX = "brain-train/";
const MUTABLE_PUBLIC_KEYS = new Set([PUBLIC_PREFIX + "manifest.json"]);

function base64UrlEncode(bytes) {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64UrlDecode(value) {
  value = value
    .replace(/-/g, "+")
    .replace(/_/g, "/");

  while (value.length % 4) {
    value += "=";
  }

  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);

  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }

  return bytes;
}

async function createHmac(secret, data) {
  const encoder = new TextEncoder();

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    {
      name: "HMAC",
      hash: "SHA-256",
    },
    false,
    ["sign"]
  );

  return crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(data)
  );
}

async function verifyAssetToken(token, secret) {
  try {
    const parts = token.split(".");

    if (parts.length !== 2) {
      return false;
    }

    const [payloadPart, signaturePart] = parts;

    const payloadBytes = base64UrlDecode(payloadPart);
    const payloadText = new TextDecoder().decode(payloadBytes);
    const payload = JSON.parse(payloadText);

    if (!payload) {
      return false;
    }

    if (payload.aud !== "bt-assets") {
      return false;
    }

    if (!payload.exp || typeof payload.exp !== "number") {
      return false;
    }

    const now = Math.floor(Date.now() / 1000);

    // Expired
    if (payload.exp <= now) {
      return false;
    }

    // Do not accept tokens that live longer than our maximum TTL
    if (payload.exp > now + TOKEN_MAX_TTL_SECONDS) {
      return false;
    }

    const expectedSignature = new Uint8Array(
      await createHmac(secret, payloadPart)
    );

    const providedSignature = base64UrlDecode(signaturePart);

    if (providedSignature.length !== expectedSignature.length) {
      return false;
    }

    return crypto.subtle.timingSafeEqual(
      providedSignature,
      expectedSignature
    );
  } catch (error) {
    console.error("Asset token validation failed", error);
    return false;
  }
}

// Public only for plain keys: no empty, "." or ".." segments.
function isPublicKey(key) {
  return key.startsWith(PUBLIC_PREFIX) &&
    key.split("/").every((segment) => segment !== "" && segment !== "." && segment !== "..");
}

export default {
  async fetch(request, env) {
    // Only GET / HEAD
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: {
          Allow: "GET, HEAD",
        },
      });
    }

    const url = new URL(request.url);

    // URL path "/brain-train/manifest.json" -> key "brain-train/manifest.json"
    let key;
    try {
      key = decodeURIComponent(url.pathname.slice(1));
    } catch {
      return new Response("Bad Request", { status: 400 });
    }

    if (!key) {
      return new Response("Asset path required", {
        status: 400,
      });
    }

    const isPublic = isPublicKey(key);

    if (!isPublic) {
      // Secret must exist
      if (!env.ASSET_TOKEN_SECRET) {
        console.error("ASSET_TOKEN_SECRET is missing");

        return new Response("Server Configuration Error", {
          status: 500,
        });
      }

      // Read Authorization header
      const authorization = request.headers.get("Authorization") || "";

      if (!authorization.startsWith("Bearer ")) {
        return new Response("Unauthorized", {
          status: 401,
        });
      }

      const token = authorization.substring("Bearer ".length).trim();

      if (!token) {
        return new Response("Unauthorized", {
          status: 401,
        });
      }

      // Validate token
      const valid = await verifyAssetToken(
        token,
        env.ASSET_TOKEN_SECRET
      );

      if (!valid) {
        return new Response("Unauthorized", {
          status: 401,
        });
      }
    }

    // Fetch from R2
    const object = await env.ASSETS.get(key);

    if (object === null) {
      return new Response("Asset Not Found", {
        status: 404,
      });
    }

    const headers = new Headers();

    object.writeHttpMetadata(headers);

    headers.set("ETag", object.httpEtag);

    // The manifest is the only mutable public object: revalidate quickly.
    // Everything else uses versioned keys and never changes.
    headers.set(
      "Cache-Control",
      MUTABLE_PUBLIC_KEYS.has(key)
        ? "public, max-age=60, must-revalidate"
        : "public, max-age=31536000, immutable"
    );

    if (isPublic) {
      headers.set("Access-Control-Allow-Origin", "*");
    }

    return new Response(request.method === "HEAD" ? null : object.body, {
      status: 200,
      headers,
    });
  },
};
