{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  ffmpeg,
  libnotify,
  pipewire,
  whisper-cpp,
  wl-clipboard,
  wtype,
  ydotool,
}:

let
  # hyprvoice links against none of this - every stage of the pipeline shells
  # out. Without the wrapper, whether dictation works depends on the PATH the
  # systemd user unit happens to inherit, and a missing binary degrades to the
  # next injection backend silently rather than failing loudly.
  runtimeInputs = [
    pipewire # pw-record captures audio; pw-cli is the readiness probe
    whisper-cpp # whisper-cli, required by the local whisper-cpp provider
    ffmpeg # internal/deps probes for it next to whisper-cli
    wtype # the injection backend that works under niri
    ydotool # upstream's first-choice backend; needs ydotoold running
    wl-clipboard # wl-copy/wl-paste for the clipboard fallback and its restore
    libnotify # notify-send for the status and error toasts
  ];
in
buildGoModule rec {
  pname = "hyprvoice";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "leonardotrapani";
    repo = "hyprvoice";
    tag = "v${version}";
    hash = "sha256-ng17y53L9cyxSjupSGKyZkBXOGneJrjprjvODYch6EE=";
  };

  vendorHash = "sha256-b1IsFlhj+xTQT/4PzL97YjVjjS7TQtcIsbeK3dLOxR4=";

  # The repo also builds test-model tooling; only the CLI/daemon is wanted.
  subPackages = [ "cmd/hyprvoice" ];

  ldflags = [
    "-s"
    "-w"
  ];

  nativeBuildInputs = [ makeWrapper ];

  # Unverified: the daemon and recording tests look like they want a control
  # socket under $HOME and a live PipeWire, neither of which the sandbox has.
  # Flip to true if you want to find out.
  doCheck = false;

  postInstall = ''
    wrapProgram $out/bin/hyprvoice \
      --prefix PATH : ${lib.makeBinPath runtimeInputs}
  '';

  meta = {
    description = "Voice-powered typing for Wayland - PipeWire capture, local or cloud transcription, wtype/ydotool injection";
    homepage = "https://github.com/leonardotrapani/hyprvoice";
    changelog = "https://github.com/leonardotrapani/hyprvoice/releases/tag/v${version}";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hyprvoice";
  };
}
