# FTR Referans Kodu (dokunulmamış, orijinal hali)

Bu klasördeki `predict.py`, `utils.py`, `main.py`, takımın FTR (Final Tasarım Raporu)
aşamasında teslim ettiği, çalışan ve doğrulukları ölçülmüş AI pipeline'ının **birebir
kopyasıdır**. Buraya sadece referans/kaynak olarak konuldu — uygulamaya doğrudan
bağlı değil (import yolları `src.utils` gibi orijinal proje yapısına göredir, bu
klasörden çalıştırılamaz).

`current_model_service.py`'nin Gün 4-7'de gerçek incremental implementasyonunu
yazarken buradaki mantık (model yükleme, kare-başına tespit, oylama, zamansal
doğrulama fonksiyonları) taşınıp uyarlanacak. Bkz. plan dosyasındaki
"Kod İncelemesi Bulguları" ve "Mimari Kararlar" madde 9.

**Bu dosyaları düzenlemeyin** — orijinal referans olarak kalmalı. Değişiklikler
`current_model_service.py` içinde yapılmalı.
