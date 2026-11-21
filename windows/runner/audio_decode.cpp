// Wandelt eine Audio-Datei (MP3, M4A/AAC, WAV, FLAC …) mit den Windows-
// eigenen Decodern (Media Foundation) in rohe Tondaten um: 32-Bit-Gleitkomma,
// verschachtelt (links, rechts, links …), ohne Kopf. Volti braucht das für
// „Spuren trennen“.
//
// Wird aus Dart über FFI aufgerufen (DynamicLibrary.executable(), in einem
// Hintergrund-Isolate), deshalb als C-Funktion exportiert und ohne Bezug zur
// Oberfläche.

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>

#include <cstdio>

namespace {

template <class T>
void SafeRelease(T** p) {
  if (*p) {
    (*p)->Release();
    *p = nullptr;
  }
}

// Die Konstanten sind als Aufzählung mit Vorzeichen deklariert, die
// Funktionen erwarten DWORD.
constexpr DWORD kFirstAudio = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
constexpr DWORD kAllStreams = static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS);

}  // namespace

// Rückgabe: 0 = gut, sonst ein Fehlercode (HRESULT oder 1 = Datei).
// [rate] und [channels] beschreiben die geschriebenen Daten.
extern "C" __declspec(dllexport) int VoltiDecodeAudio(const wchar_t* input,
                                                      const wchar_t* output,
                                                      int* rate,
                                                      int* channels) {
  const HRESULT co = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
  if (FAILED(hr)) {
    if (SUCCEEDED(co)) CoUninitialize();
    return hr;
  }

  IMFSourceReader* reader = nullptr;
  IMFMediaType* wanted = nullptr;
  IMFMediaType* actual = nullptr;
  FILE* out = nullptr;
  UINT32 sampleRate = 0, numChannels = 0;
  bool fileError = false;

  hr = MFCreateSourceReaderFromURL(input, nullptr, &reader);
  if (SUCCEEDED(hr)) {
    reader->SetStreamSelection(kAllStreams, FALSE);
    hr = reader->SetStreamSelection(kFirstAudio, TRUE);
  }
  // Ausgabe: unkomprimiert, 32-Bit-Gleitkomma (Abtastrate und Kanäle wie
  // in der Datei).
  if (SUCCEEDED(hr)) hr = MFCreateMediaType(&wanted);
  if (SUCCEEDED(hr)) hr = wanted->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  if (SUCCEEDED(hr)) hr = wanted->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_Float);
  if (SUCCEEDED(hr)) {
    hr = reader->SetCurrentMediaType(kFirstAudio,
                                     nullptr, wanted);
  }
  if (SUCCEEDED(hr)) {
    hr = reader->GetCurrentMediaType(kFirstAudio,
                                     &actual);
  }
  if (SUCCEEDED(hr)) {
    hr = actual->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &sampleRate);
  }
  if (SUCCEEDED(hr)) hr = actual->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &numChannels);
  if (SUCCEEDED(hr) && (sampleRate == 0 || numChannels == 0)) hr = E_FAIL;
  if (SUCCEEDED(hr) && _wfopen_s(&out, output, L"wb") != 0) fileError = true;

  while (SUCCEEDED(hr) && !fileError) {
    DWORD flags = 0;
    IMFSample* sample = nullptr;
    hr = reader->ReadSample(kFirstAudio, 0, nullptr,
                            &flags, nullptr, &sample);
    if (FAILED(hr)) break;
    if (sample) {
      IMFMediaBuffer* buffer = nullptr;
      hr = sample->ConvertToContiguousBuffer(&buffer);
      if (SUCCEEDED(hr)) {
        BYTE* data = nullptr;
        DWORD length = 0;
        hr = buffer->Lock(&data, nullptr, &length);
        if (SUCCEEDED(hr)) {
          if (length > 0 && fwrite(data, 1, length, out) != length) {
            fileError = true;
          }
          buffer->Unlock();
        }
      }
      SafeRelease(&buffer);
      SafeRelease(&sample);
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
  }

  if (out) fclose(out);
  SafeRelease(&actual);
  SafeRelease(&wanted);
  SafeRelease(&reader);
  MFShutdown();
  if (SUCCEEDED(co)) CoUninitialize();
  if (FAILED(hr)) return static_cast<int>(hr);
  if (fileError) return 1;
  *rate = static_cast<int>(sampleRate);
  *channels = static_cast<int>(numChannels);
  return 0;
}
