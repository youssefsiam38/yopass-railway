# Security

## What Yopass guarantees

- **End-to-end encryption.** The browser encrypts with OpenPGP.js before upload. The key is in the link's
  `#fragment`, which is never sent to the server. Yopass rejects anything that is not an OpenPGP message.
- **One-time and expiring.** One-time secrets are deleted atomically on the first read; every secret has a store TTL of
  1 hour, 1 day or 1 week.

## What the template adds

- Valkey is **private** (no public domain, no TCP proxy) and **password-protected** with a generated password.
- **Abuse bounds** for a public instance: Valkey `maxmemory` (`VALKEY_MAXMEMORY`, default 256 MB) with
  `volatile-ttl` eviction, `MAX_LENGTH=10000` per text secret, 512 KB per file, one week maximum lifetime.
- `CORS_ALLOW_ORIGIN` is the app's own `https://` origin instead of upstream's `*`, so other websites cannot use your
  instance as a backend from their visitors' browsers.
- Images pinned by digest.

## Creation is public — by design

Anyone who can reach the URL can create a secret. Recipients must also be able to open links without signing in, and
the web app (a single-page app with hash routes) serves creating and reading from the same page, so a password in
front of the whole site would also lock out every recipient. Yopass's own creation login (`REQUIRE_AUTH` with OIDC,
or `API_TOKEN`) is a paid Yopass business-licence feature, so the template does not enable it.

**Decision:** the template ships Yopass as upstream intends (open creation), bounded by the limits above, and does
**not** add a front door. If you need to restrict who can create secrets:

| Option | How |
|---|---|
| Retrieval-only public instance | Set `READ_ONLY=true` on this deployment (no `/create/*` endpoints). Create secrets from a second, private Yopass instance (e.g. one reachable only through a VPN or an identity-aware proxy) with `PUBLIC_URL` set to this instance's URL, sharing the same Valkey. |
| Access proxy | Put an identity-aware proxy (e.g. Cloudflare Access) on a custom domain in front of `yopass` and exempt only the read paths a recipient needs, if your proxy can express that. |
| Text only | `DISABLE_UPLOAD=true` removes file sharing. |
| Fixed policy | `FORCE_ONETIME_SECRETS=true`, `FORCE_EXPIRATION=1h`. |
| Licensed Yopass | With a Yopass business licence, `LICENSE_KEY` + `OIDC_*` + `REQUIRE_AUTH=true` (or `API_TOKEN`) gate creation natively. |

## Operational notes

- Back up nothing: by design, secrets are short-lived and unrecoverable without the link.
- Valkey stores only ciphertext. Losing the volume loses unread secrets, never plaintext.
- Reporting: Yopass issues go to the upstream project (`SECURITY.md` there); template issues to this repository.
