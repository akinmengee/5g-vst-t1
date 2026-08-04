"""DockerAiRunner'ın HATA dalları.

Mutlu yol burada test edilmez: gerçek imajı çalıştırmak dakikalar sürer ve GPU
ister — o, `docker run` ile elle/entegrasyon olarak doğrulanır. Buradaki
testler, gerçek imaj patladığında backend'in sessizce "başarılı" saymadığını
garanti eder (timeout / sıfır-dışı çıkış / results.json üretilmemesi).
"""

import asyncio

import pytest

from app.services.orchestration.ai_runner import AiRunnerError, DockerAiRunner


class _SahteProc:
    """asyncio.create_subprocess_exec'in döndürdüğü process'in sahtesi."""

    def __init__(self, returncode: int = 0, takilsin: bool = False):
        self.returncode = returncode
        self._takilsin = takilsin
        self.kill_edildi = False

    async def communicate(self):
        if self._takilsin:
            await asyncio.sleep(3600)
        return b"", b"sahte stderr"

    def kill(self):
        self.kill_edildi = True

    async def wait(self):
        return self.returncode


def _docker_runner(monkeypatch, proc: _SahteProc) -> DockerAiRunner:
    monkeypatch.setattr("shutil.which", lambda cmd: "C:/sahte/docker.exe")

    async def sahte_exec(*cmd, **kwargs):
        return proc

    monkeypatch.setattr(asyncio, "create_subprocess_exec", sahte_exec)
    runner = DockerAiRunner(image="teknofest-2026/vst-t1:latest", timeout_seconds=600)
    runner._timeout = 0.05  # test hızı için kısaltılır
    return runner


def test_docker_runner_zaman_asiminda_kill_edilir_ve_hata_firlatir(monkeypatch, tmp_path):
    """10 dk sınırı aşılırsa process öldürülür ve AiRunnerError fırlatılır."""
    proc = _SahteProc(takilsin=True)
    runner = _docker_runner(monkeypatch, proc)
    with pytest.raises(AiRunnerError, match="zaman aşımı"):
        asyncio.run(runner.run("j", tmp_path / "input" / "video.mp4", tmp_path / "output"))
    assert proc.kill_edildi


def test_docker_runner_sifir_disi_cikista_hata_firlatir(monkeypatch, tmp_path):
    """Container hata koduyla biterse stderr özetiyle AiRunnerError fırlatılır."""
    runner = _docker_runner(monkeypatch, _SahteProc(returncode=1))
    with pytest.raises(AiRunnerError, match="çıkış kodu 1"):
        asyncio.run(runner.run("j", tmp_path / "input" / "video.mp4", tmp_path / "output"))


def test_docker_runner_results_json_uretilmezse_hata_firlatir(monkeypatch, tmp_path):
    """Exit 0 ama results.json yoksa sessiz başarı YOKTUR, hata fırlatılır."""
    runner = _docker_runner(monkeypatch, _SahteProc(returncode=0))
    with pytest.raises(AiRunnerError, match="results.json üretmedi"):
        asyncio.run(runner.run("j", tmp_path / "input" / "video.mp4", tmp_path / "output"))
