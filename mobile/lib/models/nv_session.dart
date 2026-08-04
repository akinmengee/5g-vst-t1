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

  NvSession copyWith({
    NvStatus? status,
    String? phoneNumber,
    String? flowId,
    String? errorMessage,
  }) {
    return NvSession(
      status: status ?? this.status,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      flowId: flowId ?? this.flowId,
      errorMessage: errorMessage,
    );
  }

  bool get isVerified => status == NvStatus.verified;
}
