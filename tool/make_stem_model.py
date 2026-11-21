#!/usr/bin/env python3
"""Erzeugt die Modell-Datei für „Spuren trennen“ (htdemucs_core.onnx).

Grundlage ist Hybrid Transformer Demucs (htdemucs) von Meta, MIT-Lizenz.
Das Modell trennt ein Lied in Schlagzeug, Bass, Rest (Gitarre, Keys …) und
Gesang. Umgewandelt wird nur der Kern ohne die Spektral-Umrechnung
(STFT/iSTFT): Die rechnet Volti selbst (`lib/core/audio/stems.dart`), weil
sie sich im ONNX-Format nicht gut abbilden lässt.

Ein- und Ausgaben (ein Stück von 7,8 s bei 44,1 kHz, stereo):
  mix  [1, 2, 343980]          Tonspur (normiert wie das ganze Lied)
  mag  [1, 4, 2048, 336]       Spektrum (Real- und Imaginärteil je Kanal)
  spec [1, 4, 4, 2048, 336]    Spektrum je Spur (Real/Imaginär je Kanal)
  wave [1, 4, 2, 343980]       Tonspur je Spur (Zeit-Zweig)
Spuren in der Reihenfolge drums, bass, other, vocals.

Läuft im Bau-Server (`.github/workflows/stem_model.yml`):
  python tool/make_stem_model.py <ausgabe-ordner>
Braucht torch (CPU), demucs, onnx, onnxruntime.
"""

import hashlib
import sys
import urllib.request
from pathlib import Path

import numpy as np
import torch

# Schneller Rechenweg der Aufmerksamkeits-Schicht lässt sich nicht nach ONNX
# umwandeln.
torch.backends.mha.set_fastpath_enabled(False)

# Offizielle Gewichte von htdemucs (Name = Kennung + Anfang der Prüfsumme).
WEIGHTS = "955717e8-8726e21a.th"
WEIGHTS_SHA256 = "8726e21a993978c7ba086d3872e7608d7d5bfca646ca4aca459ffda844faa8b4"
# Kopie der offiziellen Datei (die Prüfsumme stellt sicher, dass sie gleich ist).
WEIGHTS_URLS = [
    f"https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/{WEIGHTS}",
    f"https://github.com/nomadkaraoke/python-audio-separator/releases/download/model-configs/{WEIGHTS}",
]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fetch_weights(repo: Path) -> None:
    repo.mkdir(parents=True, exist_ok=True)
    target = repo / WEIGHTS
    for url in WEIGHTS_URLS:
        if target.exists() and sha256(target) == WEIGHTS_SHA256:
            break
        try:
            print("Lade", url)
            urllib.request.urlretrieve(url, target)
        except Exception as e:  # nächste Quelle versuchen
            print("  geht nicht:", e)
    if not target.exists() or sha256(target) != WEIGHTS_SHA256:
        sys.exit("Gewichte fehlen oder Prüfsumme falsch")
    (repo / "htdemucs.yaml").write_text("models: ['955717e8']\n")


class Core(torch.nn.Module):
    """htdemucs ohne STFT/iSTFT (sonst gleich wie HTDemucs.forward)."""

    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, mix, mag):
        from einops import rearrange

        m = self.m
        x = mag
        B, C, Fq, T = x.shape
        mean = x.mean(dim=(1, 2, 3), keepdim=True)
        std = x.std(dim=(1, 2, 3), keepdim=True)
        x = (x - mean) / (1e-5 + std)
        xt = mix
        meant = xt.mean(dim=(1, 2), keepdim=True)
        stdt = xt.std(dim=(1, 2), keepdim=True)
        xt = (xt - meant) / (1e-5 + stdt)
        saved, saved_t, lengths, lengths_t = [], [], [], []
        for idx, encode in enumerate(m.encoder):
            lengths.append(x.shape[-1])
            inject = None
            if idx < len(m.tencoder):
                lengths_t.append(xt.shape[-1])
                tenc = m.tencoder[idx]
                xt = tenc(xt)
                if not tenc.empty:
                    saved_t.append(xt)
                else:
                    inject = xt
            x = encode(x, inject)
            if idx == 0 and m.freq_emb is not None:
                frs = torch.arange(x.shape[-2], device=x.device)
                emb = m.freq_emb(frs).t()[None, :, :, None].expand_as(x)
                x = x + m.freq_emb_scale * emb
            saved.append(x)
        if m.crosstransformer:
            if m.bottom_channels:
                b, c, f, t = x.shape
                x = rearrange(x, "b c f t-> b c (f t)")
                x = m.channel_upsampler(x)
                x = rearrange(x, "b c (f t)-> b c f t", f=f)
                xt = m.channel_upsampler_t(xt)
            x, xt = m.crosstransformer(x, xt)
            if m.bottom_channels:
                x = rearrange(x, "b c f t-> b c (f t)")
                x = m.channel_downsampler(x)
                x = rearrange(x, "b c (f t)-> b c f t", f=f)
                xt = m.channel_downsampler_t(xt)
        for idx, decode in enumerate(m.decoder):
            skip = saved.pop(-1)
            x, pre = decode(x, skip, lengths.pop(-1))
            offset = m.depth - len(m.tdecoder)
            if idx >= offset:
                tdec = m.tdecoder[idx - offset]
                length_t = lengths_t.pop(-1)
                if tdec.empty:
                    pre = pre[:, :, 0]
                    xt, _ = tdec(pre, None, length_t)
                else:
                    skip = saved_t.pop(-1)
                    xt, _ = tdec(xt, skip, length_t)
        S = len(m.sources)
        x = x.view(B, S, -1, Fq, T)
        x = x * std[:, None] + mean[:, None]
        xt = xt.view(B, S, -1, mix.shape[-1])
        xt = xt * stdt[:, None] + meant[:, None]
        return x, xt


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "stem-model")
    out.mkdir(parents=True, exist_ok=True)
    repo = out / "weights"
    fetch_weights(repo)

    from demucs.apply import BagOfModels
    from demucs.pretrained import get_model

    bag = get_model("htdemucs", repo=repo)
    m = bag.models[0] if isinstance(bag, BagOfModels) else bag
    m.eval()
    L = int(m.segment * m.samplerate)
    assert m.sources == ["drums", "bass", "other", "vocals"], m.sources
    assert (m.nfft, m.hop_length, m.cac, L) == (4096, 1024, True, 343980)

    core = Core(m).eval()
    torch.manual_seed(0)
    mix = torch.randn(1, 2, L) * 0.3
    with torch.no_grad():
        z = m._spec(mix)
        mag = m._magnitude(z)
        ref = m(mix)
        x, xt = core(mix, mag)
        diff = (m._ispec(m._mask(z, x), L) + xt - ref).abs().max().item()
        print("Kern gegen Original:", diff)
        assert diff < 1e-4
        onnx_path = out / "htdemucs_core.onnx"
        torch.onnx.export(
            core,
            (mix, mag),
            str(onnx_path),
            input_names=["mix", "mag"],
            output_names=["spec", "wave"],
            opset_version=17,
            dynamo=False,
        )

    # Prüfen: ONNX Runtime rechnet gleich wie PyTorch.
    import onnxruntime as ort

    sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    ox, oxt = sess.run(None, {"mix": mix.numpy(), "mag": mag.numpy()})
    d = max(np.abs(ox - x.numpy()).max(), np.abs(oxt - xt.numpy()).max())
    print("ONNX gegen PyTorch:", d)
    assert d < 1e-2

    digest = sha256(onnx_path)
    (out / "htdemucs_core.onnx.sha256").write_text(digest + "\n")
    print("SHA-256:", digest, "Grösse:", onnx_path.stat().st_size)


if __name__ == "__main__":
    main()
