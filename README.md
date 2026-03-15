# Ragfolio2

One project: frontend (React + Vite + Tailwind), backend (FastAPI), and RAG (uv library).

## Layout

- **frontend/** — React app; dev server on port 5000; all API calls go to `/api/*` (proxied to backend).
- **backend/** — FastAPI app on port 8000; `GET /health`, `POST /ask`.
- **rag/** — uv package (chromadb, fastembed, requests); for use by backend.

## Run

1. **Backend** (terminal 1):
   ```bash
   cd backend && uv run python main.py
   ```
   Listens on http://localhost:8000.

2. **Frontend** (terminal 2):
   ```bash
   cd frontend && npm install && npm run dev
   ```
   App at http://localhost:5000. Requests to `/api/health` and `/api/ask` are proxied to the backend.
   

Optionally install RAG for development: `cd rag && uv sync`.
