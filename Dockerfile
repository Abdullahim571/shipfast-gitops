# syntax=docker/dockerfile:1

# Pin the exact Python patch release and Debian release so builds are reproducible.
# For stricter supply-chain guarantees, also pin the digest:
#   python:3.12.15-slim-bookworm@sha256:<digest>
ARG PYTHON_IMAGE=python:3.12.15-slim-bookworm

# ---------- Stage 1: build dependencies into an isolated virtualenv ----------
FROM ${PYTHON_IMAGE} AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy only the dependency manifest first so this layer is cached
# until requirements.txt changes (code edits won't trigger a reinstall).
COPY requirements.txt .
RUN pip install -r requirements.txt

# ---------- Stage 2: minimal runtime image ----------
FROM ${PYTHON_IMAGE} AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Unprivileged system user with a fixed UID/GID (works with runAsNonRoot in k8s).
RUN groupadd --system --gid 10001 appuser \
 && useradd --system --uid 10001 --gid appuser --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

# Bring over only the installed dependencies, not pip caches or build tooling.
COPY --from=builder /opt/venv /opt/venv

# Application code last: it changes most often, so it invalidates the fewest layers.
# Owned by root and read-only to appuser, so the process can't modify its own code.
COPY app.py .

USER 10001:10001

EXPOSE 5000

# slim images have no curl/wget, so probe /status with the Python stdlib.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/status', timeout=3).status == 200 else 1)"]

ENTRYPOINT ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
