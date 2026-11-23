[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/tube-archivist?utm_medium=integration&utm_source=button&utm_campaign=tube-archivist)

# Tube Archivist on Railway

One-click [Tube Archivist](https://github.com/tubearchivist/tubearchivist) for [Railway](https://railway.com): a self-hosted YouTube media server. Subscribe to channels and playlists, download videos with yt-dlp, index their metadata in Elasticsearch, then search and watch them in your browser.

This repo is the source of the Railway template. Every service except Redis builds from it, so when we bump a version here, Railway offers the update to everyone who deployed the template.

## What it deploys

| Service | Built from | What it does | Volume |
|---|---|---|---|
| **Tube Archivist** | [`tubearchivist/`](tubearchivist/) on `bbilly1/tubearchivist:v0.6.0` (pinned by digest) | Web UI and API, Celery download worker and scheduler. Public domain, health check `/api/health/` | `/data` (`/data/youtube` media, `/data/cache` SQLite users and schedules, thumbnails, backups) |
| **Elasticsearch** | [`elasticsearch/`](elasticsearch/) on `elasticsearch:9.5.5` (pinned by digest) | Index of videos, channels, playlists, the download queue and app settings. Private network only, password protected. Health check `/_cluster/health` | `/usr/share/elasticsearch/data` (index and snapshots) |
| **Redis** | Railway's Redis | Task queue and cache, password protected | `/data` |

Versions: Tube Archivist **v0.6.0**, Elasticsearch **9.5.5** (Tube Archivist's recommended version), Redis from Railway's database template.

## Variables

All of them are filled in for you; the template asks for nothing.

| Service | Variable | Default | Notes |
|---|---|---|---|
| Tube Archivist | `TA_USERNAME` | `admin` | First admin's user name, created on first start |
| Tube Archivist | `TA_PASSWORD` | generated | First admin's password. Read it in the service's **Variables** tab |
| Tube Archivist | `TA_HOST` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL(s), space separated. Add your custom domain here |
| Tube Archivist | `ES_URL`, `ELASTIC_PASSWORD`, `REDIS_CON` | references | Wiring to Elasticsearch and Redis over the private network |
| Tube Archivist | `PORT` | `8000` | Port the web server listens on |
| Tube Archivist | `TZ` | `UTC` | Time zone for schedules |
| Elasticsearch | `ELASTIC_PASSWORD` | generated | Password of the `elastic` user. Don't change it after the first deploy |
| Elasticsearch | `PORT` | `9200` | |

Optional, add them yourself if you need them:
- `TA_AUTO_UPDATE_YTDLP=release` (or `nightly`) on Tube Archivist installs the newest yt-dlp on every start. It helps when YouTube changes break downloads before our next update.
- `TA_WEB_WORKERS` and `TA_CELERY_CONCURRENCY` (default `1` each, about 100 MB per worker): raise them on bigger plans.
- `ES_JAVA_OPTS` on Elasticsearch overrides the heap. By default it uses 35% of the service's memory limit, between 160 MB and 512 MB.
- Login options (`TA_LOGIN_AUTH_MODE`, LDAP, forward auth) are in the [upstream docs](https://docs.tubearchivist.com/installation/env-vars/).

## After you deploy

1. Open the Tube Archivist URL and log in as `admin` with the `TA_PASSWORD` from the service's Variables tab. Change the password under **Settings → User** if you like.
2. **YouTube blocks most cloud IPs** ("Sign in to confirm you're not a bot"). Before downloading, export your YouTube cookies (`cookies.txt`) and import them under **Settings → Application → Cookie**. See the [cookie docs](https://docs.tubearchivist.com/settings/application/#cookie).
3. Add channels, playlists or videos under **Downloads** and start the queue.

## Resources

Elasticsearch needs about **1 GB of RAM**: it idles at 450–500 MB even with a small heap, and is killed in a 0.5 GB service. Tube Archivist idles at about 300 MB but needs about **1 GB** while yt-dlp extracts and downloads videos. Redis needs very little. So the stack needs a plan that allows 1 GB per service (Railway's Hobby plan or above). Downloaded videos go on the Tube Archivist volume; grow it in Railway as your archive grows.

## How the services are set up

- `tubearchivist/start.sh` replaces upstream's `run.sh`. It keeps all data on the one Railway volume (`TA_CACHE_DIR=/data/cache`, `TA_MEDIA_DIR=/data/youtube`), waits for Elasticsearch and Redis, runs upstream's setup steps (migrations, superuser, index setup), then starts the web server, the Celery worker and the scheduler. If any of them dies, the container exits non-zero so Railway's restart policy brings it back. It adds `healthcheck.railway.app` to `TA_HOST` so Railway's health check passes Django's host check.
- `elasticsearch/start.sh` runs Elasticsearch as single node with security on, `path.repo` set for Tube Archivist's snapshots, features Tube Archivist doesn't use switched off, and only `/_cluster/health` readable without a password. It gives the root-owned Railway volume to the Elasticsearch user, and turns mmap off on hosts whose `vm.max_map_count` is too low.

## Updates

We follow Tube Archivist's releases. Each update is a commit to `main` here with an entry in [CHANGELOG.md](CHANGELOG.md). Railway then shows "update available" on your project, and you choose when to apply it. Read the changelog first: breaking changes are listed at the top of each entry. Elasticsearch upgrades across a major version are never applied silently.

Before a big update, take a snapshot under **Settings → Actions → Snapshot** (stored on the Elasticsearch volume).

## License

Tube Archivist is licensed under GPL-3.0 and Elasticsearch under Elastic's licences. See the upstream projects for their terms.
