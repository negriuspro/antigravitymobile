# ── Stage 1: build Flutter web ───────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:3.32.0 AS builder

WORKDIR /app

COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get --no-example

COPY . .
RUN flutter build web --release \
      --no-tree-shake-icons \
      --dart-define=FLUTTER_WEB_USE_SKIA=true

# ── Stage 2: serve with nginx ─────────────────────────────────────────────────
FROM nginx:1.27-alpine AS runtime

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/build/web /usr/share/nginx/html

RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://127.0.0.1/health >/dev/null || exit 1
