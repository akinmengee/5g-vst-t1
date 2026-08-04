"""NV (Number Verification) endpoint'leri — 3-legged OIDC akışının backend ucu.

Akış (Bölüm H tasarımı):
  mobil → POST /api/auth/login → {flow_id, authorize_url}
  mobil, authorize_url'i WebView'de açar (hücresel veri üzerinden)
  Turkcell → GET /api/auth/callback?code=...&state={flow_id}  (WebView yönlendirmesi)
  backend: code → token → NV verify → flow durumu güncellenir
  mobil → GET /api/auth/status/{flow_id} (~1sn polling) → verified/rejected/error
"""

import logging
import time

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse

from app.schemas.auth import AuthStatusResponse, LoginRequest, LoginResponse
from app.services.network.interface import OpenGatewayError
from app.services.network.runtime import get_gateway_client
from app.services.orchestration.runtime import get_flow_registry

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/auth/login")
async def login(body: LoginRequest) -> LoginResponse:
    flow = get_flow_registry().create(body.phone_number)
    url = get_gateway_client().build_authorize_url(flow.flow_id, flow.phone_number)
    return LoginResponse(flow_id=flow.flow_id, authorize_url=url)


@router.get("/api/auth/callback", response_class=HTMLResponse)
async def callback(
    state: str, code: str | None = None, error: str | None = None
) -> HTMLResponse:
    """Turkcell'in yönlendirdiği adres — mobil bunu doğrudan çağırmaz.

    `code` bilerek opsiyonel: Turkcell OAuth hatasında `?error=...&state=...`
    ile (code olmadan) dönebilir; zorunlu olsaydı FastAPI 422 döner ve flow
    sonsuza dek "pending" kalırdı.
    """
    flow = get_flow_registry().get(state)
    if flow is None:
        return HTMLResponse("<html><body>Bilinmeyen oturum.</body></html>", status_code=400)

    if code is None:
        logger.warning("NV callback code olmadan geldi (flow=%s, error=%s)", state, error)
        flow.status = "error"
        flow.error_code = error or "code_eksik"
        flow.error_detail = error or "Turkcell yetkilendirme kodu dönmedi."
        return HTMLResponse(
            "<html><body>Doğrulama başarısız. Bu pencereyi kapatabilirsiniz.</body></html>"
        )

    gateway = get_gateway_client()
    try:
        token = await gateway.exchange_code_for_token(code)
        flow.access_token = token.access_token
        flow.token_expires_at = time.monotonic() + token.expires_in
        verified = await gateway.verify_number(token.access_token, flow.phone_number)
        flow.status = "verified" if verified else "rejected"
    except OpenGatewayError as exc:
        logger.warning("NV başarısız (flow=%s): %s", state, exc)
        flow.status = "error"
        flow.error_code = exc.error_code
        flow.error_detail = str(exc)
    except Exception:
        logger.exception("NV callback beklenmeyen hata (flow=%s)", state)
        flow.status = "error"
        flow.error_detail = "Beklenmeyen sunucu hatası."
    return HTMLResponse(
        "<html><body>Doğrulama tamamlandı, bu pencereyi kapatabilirsiniz.</body></html>"
    )


@router.get("/api/auth/status/{flow_id}")
async def status(flow_id: str) -> AuthStatusResponse:
    flow = get_flow_registry().get(flow_id)
    if flow is None:
        raise HTTPException(status_code=404, detail="flow_id bulunamadı")
    verified = flow.status == "verified" if flow.status in ("verified", "rejected") else None
    return AuthStatusResponse(
        status=flow.status,
        device_phone_number_verified=verified,
        error_code=flow.error_code,
        message=flow.error_detail,
    )
