"""In-memory ask job runner for long NotebookLM requests."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, datetime
from threading import Lock
from uuid import uuid4

from ..adapters.base import NotebookLMAdapter
from ..models import AskJobResponse, AskRequest, AskResponse
from .ask import ask_notebook


@dataclass
class AskJob:
    job_id: str
    status: str
    request: AskRequest
    result: AskResponse | None = None
    error: str | None = None
    created_at: str = ""
    updated_at: str = ""


class AskJobStore:
    def __init__(self, max_workers: int = 2):
        self._executor = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="ask-job")
        self._jobs: dict[str, AskJob] = {}
        self._lock = Lock()

    def submit(self, adapter: NotebookLMAdapter, request: AskRequest) -> AskJobResponse:
        now = _now()
        job = AskJob(
            job_id=uuid4().hex,
            status="queued",
            request=request,
            created_at=now,
            updated_at=now,
        )
        with self._lock:
            self._jobs[job.job_id] = job

        self._executor.submit(self._run, adapter, job.job_id)
        return self.get(job.job_id)

    def get(self, job_id: str) -> AskJobResponse:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                raise KeyError(job_id)
            return AskJobResponse(
                job_id=job.job_id,
                status=job.status,
                result=job.result,
                error=job.error,
            )

    def _run(self, adapter: NotebookLMAdapter, job_id: str) -> None:
        request = self._set_running(job_id)
        if request is None:
            return
        try:
            result = ask_notebook(adapter, request)
        except Exception as e:  # noqa: BLE001 - captured into job state for polling clients.
            with self._lock:
                job = self._jobs[job_id]
                job.status = "failed"
                job.error = str(e)
                job.updated_at = _now()
            return

        with self._lock:
            job = self._jobs[job_id]
            job.status = "succeeded"
            job.result = result
            job.updated_at = _now()

    def _set_running(self, job_id: str) -> AskRequest | None:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                return None
            job.status = "running"
            job.updated_at = _now()
            return job.request


def _now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
