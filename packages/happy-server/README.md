# Happy Server

Minimal backend for open-source end-to-end encrypted Claude Code clients.

## What is Happy?

Happy Server is the synchronization backbone for secure Claude Code clients. It enables multiple devices to share encrypted conversations while maintaining complete privacy - the server never sees your messages, only encrypted blobs it cannot read.

## Features

- 🔐 **Zero Knowledge** - The server stores encrypted data but has no ability to decrypt it
- 🎯 **Minimal Surface** - Only essential features for secure sync, nothing more  
- 🕵️ **Privacy First** - No analytics, no tracking, no data mining
- 📖 **Open Source** - Transparent implementation you can audit and self-host
- 🔑 **Cryptographic Auth** - No passwords stored, only public key signatures
- ⚡ **Real-time Sync** - WebSocket-based synchronization across all your devices
- 📱 **Multi-device** - Seamless session management across phones, tablets, and computers
- 🔔 **Push Notifications** - Notify when Claude Code finishes tasks or needs permissions (encrypted, we can't see the content)
- 🌐 **Distributed Ready** - Built to scale horizontally when needed

## How It Works

Your Claude Code clients generate encryption keys locally and use Happy Server as a secure relay. Messages are end-to-end encrypted before leaving your device. The server's job is simple: store encrypted blobs and sync them between your devices in real-time.

## Hosting

**You don't need to self-host!** Our free cloud Happy Server at `happy-api.slopus.com` is just as secure as running your own. Since all data is end-to-end encrypted before it reaches our servers, we literally cannot read your messages even if we wanted to. The encryption happens on your device, and only you have the keys.

That said, Happy Server is open source and self-hostable if you prefer running your own infrastructure. The security model is identical whether you use our servers or your own.

## Self-Hosting with Docker

The standalone Docker image runs everything in a single container with no external dependencies (no Postgres, no Redis, no S3).

```bash
docker build -t happy-server -f Dockerfile .
```

Run from the monorepo root:

```bash
docker run -p 3005:3005 \
  -e HANDY_MASTER_SECRET=<your-secret> \
  -v happy-data:/data \
  happy-server
```

This uses:
- **PGlite** - embedded PostgreSQL (data stored in `/data/pglite`)
- **Local filesystem** - for file uploads (stored in `/data/files`)
- **In-memory event bus** - no Redis needed

Data persists in the `happy-data` Docker volume across container restarts.

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HANDY_MASTER_SECRET` | Yes | - | Master secret for auth/encryption |
| `PUBLIC_URL` | No | `http://localhost:3005` | Public base URL for file URLs sent to clients |
| `PORT` | No | `3005` | Server port |
| `DATA_DIR` | No | `/data` | Base data directory |
| `PGLITE_DIR` | No | `/data/pglite` | PGlite database directory |

### HTTPS for Mobile Apps (Android / iOS)

Android blocks cleartext HTTP by default, so the Play Store / App Store builds of the Happy mobile app **cannot connect to a plain HTTP server**. You need an HTTPS reverse proxy in front of your Happy Server.

A setup script is included that generates a self-signed certificate and runs [Caddy](https://caddyserver.com/) as a reverse proxy in Docker:

```bash
# From the monorepo root:
cd packages/happy-server
./scripts/setup-https-proxy.sh
```

The script auto-detects your LAN IP and:
1. Generates a self-signed certificate valid for 10 years
2. Writes a Caddyfile for the reverse proxy
3. Creates a Docker network connecting Caddy to the Happy Server container
4. Starts the Caddy container on port 443

See `./scripts/setup-https-proxy.sh --help` for all options (custom IP, port, cert directory, etc.).

#### Install the CA certificate on your phone

The self-signed certificate must be trusted by your phone. The script outputs a `happy-server-ca.crt` file — transfer it to your phone and install it:

**Android:** Settings > Security > Encryption & credentials > Install a certificate > CA certificate

**iOS:** Open the `.crt` file > Install Profile, then Settings > General > About > Certificate Trust Settings > enable the certificate

A quick way to transfer the cert is to serve it temporarily:

```bash
python3 -m http.server 8080 -d ./certs
# Open http://<your-ip>:8080/happy-server-ca.crt on your phone
```

#### Configure the CLI for HTTPS

Add to your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
export HAPPY_SERVER_URL=https://<your-ip>
export NODE_EXTRA_CA_CERTS=/path/to/certs/server.crt
```

#### Configure the mobile app

On the Happy app's server configuration screen, enter `https://<your-ip>` and save. The app validates the connection before applying.

> **Note:** On Android, the server configuration screen is accessible from the welcome screen (before login) via the server icon in the top-right header. If you're already logged in, you must log out first to access it.

### Optional: External Services

To use external Postgres or Redis instead of the embedded defaults, set:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection URL (bypasses PGlite) |
| `REDIS_URL` | Redis connection URL |
| `S3_HOST` | S3/MinIO host (bypasses local file storage) |

## License

MIT - Use it, modify it, deploy it anywhere.