# Standalone single-container image for the backend only — intended for
# PaaS platforms (Render, Railway, Fly.io, etc.) that build a project from a
# root-level Dockerfile without docker-compose. For local multi-container
# development, use `docker-compose up` instead, which builds from
# docker/Dockerfile.backend + docker/Dockerfile.frontend.
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . ./
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
