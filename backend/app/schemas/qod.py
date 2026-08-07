"""QoD (Quality on Demand) mobil sözleşme şemaları.

QoD başarısızlığı puan kaybettirmez (Final Senaryosu madde 3) — bu yüzden yanıt
hiçbir durumda HTTP hatası değildir (bilinmeyen flow_id hariç): mobil sadece
`success` alanına bakıp akışa devam eder.
"""

from pydantic import BaseModel, ConfigDict, Field


class QodStartRequest(BaseModel):
    flow_id: str


class QodStartResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    success: bool
    # Turkcell 409 Conflict döndüyse: aynı cihaz için zaten aktif oturum var —
    # hata değil, başarı sayılır.
    already_active: bool = False
    session_id: str | None = Field(default=None, alias="sessionId")
    qos_status: str | None = Field(default=None, alias="qosStatus")
    # Turkcell'in GERÇEKTEN verdiği oturum süresi (saniye). Talep ettiğimizden
    # kısa olabilir. Kritik: oturum bittiği anda cihazın veri bağlantısı
    # kopuyor (7 Ağustos ölçümü), yani bu "ne kadar süremiz var" demek.
    duration: int | None = None


class QodStopResponse(BaseModel):
    """QoD oturumunu erken sonlandırma denemesinin sonucu.

    `stopped: false` bir HATA DEĞİLDİR: Turkcell'in paylaştığı spec'te silme
    operasyonu yok, dolayısıyla desteklenmiyor olabilir. Bu durumda oturum
    kendi süresi dolunca sonlanır.
    """

    stopped: bool
