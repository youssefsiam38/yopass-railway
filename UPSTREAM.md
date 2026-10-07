# Upstream

| Component | Source | Licence | Pinned |
|---|---|---|---|
| Yopass | https://github.com/jhaals/yopass (official image `jhaals/yopass`) | Apache-2.0 | `jhaals/yopass:14.10.0@sha256:6c33d9c813f77bae70787e1bce76710840ff654f454998b01f8dacc0a7988fd3` (amd64, arm64) |
| Valkey | https://github.com/valkey-io/valkey (official image `valkey/valkey`) | BSD-3-Clause | `valkey/valkey:9.1.2-alpine@sha256:48332870af354a799964c0012ae1194a0bf2bf894eb508f945810596dc2d8d11` (multi-arch) |

Yopass 14.10.0 corresponds to upstream commit `34d8bbcc4aac14dbf326d46dc69d26895b7f5282`.

## Refreshing a digest

```bash
docker buildx imagetools inspect jhaals/yopass:<tag> --format '{{json .Manifest}}' | jq -r .digest
docker buildx imagetools inspect valkey/valkey:<tag>-alpine --format '{{json .Manifest}}' | jq -r .digest
```

Update `compose.yaml`, `tests/lib.sh` (`YOPASS_IMAGE`), this file and the generator spec, then run the tests
(see `MAINTENANCE.md`).
