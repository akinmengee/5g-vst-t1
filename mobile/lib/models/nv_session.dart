/// mobile-integration.md 2.3'teki durum makinesi + yerel `idle`/`authorizing`.
///
/// Sunucu durumları: pending | verified | rejected | error.
/// `authorizing`: login cevabı geldi, authorize_url WebView'de açık ve status
/// polling sürüyor (sunucu tarafında "pending"e karşılık gelir).
enum NvStatus { idle, authorizing, verified, rejected, failed }

class NvSession {
  final NvStatus status;
  final String phoneNumber;

  /// mobile-integration.md 3: "flow_id tek ipliktir" — status, qod ve upload
  /// çağrılarının hepsi bu id ile yapılır.
  final String? flowId;

  /// WebView'de olduğu gibi açılacak Turkcell OAuth adresi. Login başarısız
  /// olduysa null kalır.
  final String? authorizeUrl;

  final String? errorCode;
  final String? errorMessage;

  const NvSession({
    this.status = NvStatus.idle,
    this.phoneNumber = '',
    this.flowId,
    this.authorizeUrl,
    this.errorCode,
    this.errorMessage,
  });

  NvSession copyWith({
    NvStatus? status,
    String? phoneNumber,
    String? flowId,
    String? authorizeUrl,
    String? errorCode,
    String? errorMessage,
  }) {
    return NvSession(
      status: status ?? this.status,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      flowId: flowId ?? this.flowId,
      authorizeUrl: authorizeUrl ?? this.authorizeUrl,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  bool get isVerified => status == NvStatus.verified;

  /// mobile-integration.md 2.3: "sahada en olası hata" — cihaz WiFi'deyken NV
  /// kesin başarısız olur; UI'da özel mesajı vardır.
  bool get isWifiError =>
      errorCode == 'NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK';
}
