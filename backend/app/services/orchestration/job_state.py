"""Job durumu ve job kayıt defteri (video → AI imajı → results.json).

TTL politikası FlowRegistry'den farklıdır: PROCESSING durumundaki bir job
HİÇBİR ZAMAN TTL ile düşürülmez (aktif docker run'ın kaydını kaybetmemek
için) — yalnızca DONE/FAILED olmuş ve `result_ttl_seconds` süresinden eski
job'lar düşürülür. Kilitsizlik gerekçesi flow_state.py ile aynıdır: bu
registry'ye yalnızca event loop üzerinden erişilir (job_executor'ın arka plan
task'ları dahil — onlar da aynı loop'ta koşan asyncio task'larıdır,
thread değildir).
"""

import time
from pathlib import Path
from typing import Literal

JobStatus = Literal["PROCESSING", "DONE", "FAILED"]


class JobState:
    def __init__(self, job_id: str) -> None:
        self.job_id = job_id
        self.status: JobStatus = "PROCESSING"
        self.started_at = time.monotonic()
        self.finished_at: float | None = None
        self.results_path: Path | None = None
        self.error: str | None = None


class JobRegistry:
    def __init__(self, result_ttl_seconds: float) -> None:
        self._ttl = result_ttl_seconds
        self._jobs: dict[str, JobState] = {}

    def create(self, job_id: str) -> JobState:
        self._evict_expired()
        job = JobState(job_id)
        self._jobs[job_id] = job
        return job

    def get(self, job_id: str) -> JobState | None:
        self._evict_expired()
        return self._jobs.get(job_id)

    def mark_done(self, job_id: str, results_path: Path) -> None:
        job = self._jobs.get(job_id)
        if job is None:
            return
        job.status = "DONE"
        job.results_path = results_path
        job.finished_at = time.monotonic()

    def mark_failed(self, job_id: str, error: str) -> None:
        job = self._jobs.get(job_id)
        if job is None:
            return
        job.status = "FAILED"
        job.error = error
        job.finished_at = time.monotonic()

    def _evict_expired(self) -> None:
        simdi = time.monotonic()
        suresi_dolan = [
            jid
            for jid, j in self._jobs.items()
            if j.status != "PROCESSING"
            and j.finished_at is not None
            and simdi - j.finished_at > self._ttl
        ]
        for jid in suresi_dolan:
            del self._jobs[jid]

    def __len__(self) -> int:
        return len(self._jobs)
