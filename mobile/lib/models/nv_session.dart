enum NvStatus { idle, pending, verified, failed }

/// [flowId], backend'in `POST /api/auth/login` yanıtından gelir (mobil
/// üretmez) — sonraki her çağrının (status/qod/upload) anahtarı budur.
class NvSession {
  final NvStatus status;
  final String phoneNumber;
  final String? flowId;
  final String? errorMessage;

  const NvSession({
    this.status = NvStatus.idle,
    this.phoneNumber = '',
    this.flowId,
    this.errorMessage,
  });

  bool get isVerified => status == NvStatus.verified;
}
