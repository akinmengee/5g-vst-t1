"""Flow durumu ve flow kayıt defteri (NV/QoD).

TTL-eviction deseni job_state.py::JobRegistry ile aynıdır (time.monotonic(),
get()'te lazy _evict_expired(), düz dict, kilit yok) — bkz. oradaki docstring.

Kilitsiz olması bilinçli bir tasarım kararıdır: FlowRegistry SADECE async
route handler'larından, event loop üzerinden, asyncio.to_thread SARMALANMADAN
çağrılır — tek thread'li async yürütme bunu kilitsiz güvenli kılar.

NOT: get() bilinmeyen flow_id'de None döner (route 404'e çevirir), otomatik
yaratma YAPILMAZ — flow_id yalnızca backend tarafından /login'de üretilir.
"""

import time
import uuid
from typing import Literal

FlowStatus = Literal["pending", "verified", "rejected", "error"]


class FlowState:
    def __init__(self, flow_id: str, phone_number: str) -> None:
        self.flow_id = flow_id
        self.phone_number = phone_number
        self.status: FlowStatus = "pending"
        self.access_token: str | None = None
        self.token_expires_at: float | None = None  # time.monotonic() bazlı
        self.qod_status: str | None = None
        self.qod_session_id: str | None = None
        self.error_code: str | None = None
        self.error_detail: str | None = None
        self.created_at = time.monotonic()
        self.last_access = self.created_at

    def touch(self) -> None:
        self.last_access = time.monotonic()

    def token_valid(self) -> bool:
        """Access token var ve 300 saniyelik ömrü henüz dolmamış mı?

        Süresi dolmuşsa yeniden almak mümkün değildir (refresh_token yok,
        akış baştan gerekir) — çağıran bunu açık bir başarısızlık olarak işler.
        """
        return (
            self.access_token is not None
            and self.token_expires_at is not None
            and time.monotonic() < self.token_expires_at
        )


class FlowRegistry:
    def __init__(self, ttl_seconds: float) -> None:
        self._ttl = ttl_seconds
        self._flows: dict[str, FlowState] = {}

    def create(self, phone_number: str) -> FlowState:
        self._evict_expired()
        flow = FlowState(str(uuid.uuid4()), phone_number)
        self._flows[flow.flow_id] = flow
        return flow

    def get(self, flow_id: str) -> FlowState | None:
        self._evict_expired()
        flow = self._flows.get(flow_id)
        if flow is not None:
            flow.touch()
        return flow

    def _evict_expired(self) -> None:
        simdi = time.monotonic()
        suresi_dolan = [
            fid for fid, f in self._flows.items() if simdi - f.last_access > self._ttl
        ]
        for fid in suresi_dolan:
            del self._flows[fid]

    def __len__(self) -> int:
        return len(self._flows)
