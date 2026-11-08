#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Schaltet die Windows-Komfortfunktionen für Stift und Touch ab, die eine
// Zeichen-App ausbremsen: Kreise beim Antippen, "Gedrückt halten =
// Rechtsklick" und Wischgesten (Flicks). Für jede davon wartet Windows sonst
// ab, was der Stift vorhat, bevor die Eingabe bei Volti ankommt.
void DisablePenDelays(HWND hwnd) {
  if (!hwnd) return;
  BOOL off = FALSE;
  const FEEDBACK_TYPE feedbacks[] = {
      FEEDBACK_PEN_BARRELVISUALIZATION, FEEDBACK_PEN_TAP,
      FEEDBACK_PEN_DOUBLETAP,           FEEDBACK_PEN_PRESSANDHOLD,
      FEEDBACK_PEN_RIGHTTAP,            FEEDBACK_TOUCH_CONTACTVISUALIZATION,
      FEEDBACK_TOUCH_TAP,               FEEDBACK_TOUCH_DOUBLETAP,
      FEEDBACK_TOUCH_PRESSANDHOLD,      FEEDBACK_TOUCH_RIGHTTAP,
      FEEDBACK_GESTURE_PRESSANDTAP,
  };
  for (const auto feedback : feedbacks) {
    ::SetWindowFeedbackSetting(hwnd, feedback, 0, sizeof(off), &off);
  }
  // Werte aus tpcshrd.h (hier direkt, damit der Build nicht von der
  // Windows-SDK-Version abhängt).
  constexpr DWORD kDisablePressAndHold = 0x00000001;
  constexpr DWORD kDisablePenTapFeedback = 0x00000008;
  constexpr DWORD kDisablePenBarrelFeedback = 0x00000010;
  constexpr DWORD kDisableFlicks = 0x00010000;
  constexpr DWORD kDisableSmoothScrolling = 0x00080000;
  constexpr DWORD kDisableFlickFallbackKeys = 0x00100000;
  const DWORD tablet_flags = kDisablePressAndHold | kDisablePenTapFeedback |
                             kDisablePenBarrelFeedback | kDisableFlicks |
                             kDisableSmoothScrolling |
                             kDisableFlickFallbackKeys;
  const wchar_t* kProperty = L"MicrosoftTabletPenServiceProperty";
  const ATOM atom = ::GlobalAddAtom(kProperty);
  ::SetProp(hwnd, kProperty,
            reinterpret_cast<HANDLE>(static_cast<ULONG_PTR>(tablet_flags)));
  ::GlobalDeleteAtom(atom);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Stift-Verzögerungen von Windows abschalten (Hauptfenster und Inhalt).
  DisablePenDelays(GetHandle());
  DisablePenDelays(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
