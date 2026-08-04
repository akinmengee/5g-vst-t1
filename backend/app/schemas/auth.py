"""NV (Number Verification) mobil sözleşme şemaları.

Alan adları mobil ekiple paylaşılan sözleşmeye birebir uyar:
istek `{phoneNumber}` (camelCase — Turkcell API'siyle aynı), yanıtlar
`{flow_id, authorize_url}` ve `{status, devicePhoneNumberVerified, error_code,
message}`. Karışık casing kasıtlıdır, "düzeltilmemelidir".
"""

import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

# number-verification.yaml'daki E.164 deseniyle aynı.
_E164 = re.compile(r"^\+[1-9][0-9]{4,14}$")


class LoginRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    phone_number: str = Field(alias="phoneNumber")

    @field_validator("phone_number")
    @classmethod
    def _e164_dogrula(cls, v: str) -> str:
        if not _E164.fullmatch(v):
            raise ValueError("phoneNumber E.164 formatında olmalı (örn: +905551234567)")
        return v


class LoginResponse(BaseModel):
    flow_id: str
    authorize_url: str


class AuthStatusResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    status: Literal["pending", "verified", "rejected", "error"]
    device_phone_number_verified: bool | None = Field(
        default=None, alias="devicePhoneNumberVerified"
    )
    # Yalnızca status == "error" iken dolar. Mobil bunlarla kullanıcıya anlamlı
    # mesaj gösterebilir — özellikle error_code ==
    # "NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK" iken
    # "WiFi'yi kapatıp mobil veriyi açın" uyarısı.
    error_code: str | None = None
    message: str | None = None
