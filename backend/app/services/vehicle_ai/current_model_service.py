"""VehicleAnalysisService'in gerçek implementasyonu.

DURUM (Gün 0-1): Bu bir iskelet/placeholder'dır — henüz hiçbir model yüklemiyor,
her çağrıda boş (ama şema açısından geçerli) bir sonuç döner. Sadece uçtan uca
boru hattının (WebSocket -> bu servis -> WebSocket) doğru şemayla çalıştığını
doğrulamak için yeterlidir (bkz. plan Gün 2-3 "Yürüyen İskelet").

Gün 4-7'de burada yapılacaklar (bkz. plan "Kod İncelemesi Bulguları" ve
"Mimari Kararlar" madde 9):
  - `_ftr_reference/predict.py`'deki model yükleme + kare-başına tespit mantığının
    (araç takibi, plaka/renk/kasa oylaması) buraya taşınması — try/except ile
    güvenli model yükleme (bkz. Kod İncelemesi madde 2).
  - `ardisik_seg`/`esneme_seg`/`bakinma_seg`/çakışma önleme/cooldown mantığının
    incremental (kare geldikçe olay yayınlayan) hale getirilmesi.
  - `session_id` başına sürekli durum (hafıza, oylama) tutulması ve uzun süre
    güncellenmeyen oturumların TTL ile düşürülmesi (bellek sızıntısını önlemek için).
"""

from app.schemas.mobile_contract import MobileRoiPayload
from app.services.vehicle_ai.interface import VehicleAnalysisResult


class CurrentModelService:
    def __init__(self) -> None:
        # Gün 4-7: burada model yükleme (try/except ile güvenli) yapılacak.
        pass

    def process_roi(self, payload: MobileRoiPayload, image_bytes: bytes) -> VehicleAnalysisResult:
        # Gün 4-7: gerçek çıkarım burada yapılacak. Şimdilik boş sonuç.
        return VehicleAnalysisResult()
