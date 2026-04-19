defmodule MultiplayerFabricDeploy.Config do
  def world_pwd, do: File.cwd!()

  def data_dir, do: Path.join(System.user_home!(), ".multiplayer-fabric-deploy")
  def logs_dir, do: Path.join(data_dir(), "logs")

  def operating_system do
    case :os.type() do
      {:unix, :darwin} -> "macos"
      {:unix, _} -> "linux"
      {:win32, _} -> "windows"
    end
  end

  def rust_log, do: "log"
  def build_count, do: "001"
  def godot_git_url, do: "https://github.com/V-Sekai-fire/multiplayer-fabric-godot.git"
  def godot_branch, do: "multiplayer-fabric"
  def label_template, do: "multiplayer-fabric.#{build_count()}"
  def android_ndk_version, do: "23.2.8568313"

  def arm64toolchain,
    do:
      "https://github.com/godotengine/buildroot/releases/download/godot-2023.08.x-4/aarch64-godot-linux-gnu_sdk-buildroot.tar.bz2"

  def cmdlinetools, do: "commandlinetools-linux-11076708_latest.zip"

  def godot_dir, do: Path.join(data_dir(), "godot")

  def arm64_root, do: Path.join(world_pwd(), "aarch64-godot-linux-gnu_sdk-buildroot")
  def android_sdk_root, do: Path.join(data_dir(), "android_sdk")
  def android_home, do: android_sdk_root()
  def java_home, do: Path.join(data_dir(), "jdk")
  def vulkan_sdk_root, do: Path.join(data_dir(), "vulkan_sdk")
  def emsdk_root, do: Path.join(data_dir(), "emsdk")
  def osxcross_root, do: Path.join(world_pwd(), "osxcross")
  def mingw_prefix, do: Path.join(data_dir(), "mingw")

  def env_vars do
    [
      {"RUST_LOG", rust_log()},
      {"OPERATING_SYSTEM", operating_system()},
      {"BUILD_COUNT", build_count()},
      {"GODOT_GIT_URL", godot_git_url()},
      {"GODOT_BRANCH", godot_branch()},
      {"LABEL_TEMPLATE", label_template()},
      {"WORLD_PWD", world_pwd()},
      {"GODOT_DIR", godot_dir()},
      {"ANDROID_NDK_VERSION", android_ndk_version()},
      {"ARM64_ROOT", arm64_root()},
      {"ANDROID_SDK_ROOT", android_sdk_root()},
      {"ANDROID_HOME", android_home()},
      {"JAVA_HOME", java_home()},
      {"VULKAN_SDK_ROOT", vulkan_sdk_root()},
      {"EMSDK_ROOT", emsdk_root()},
      {"OSXCROSS_ROOT", osxcross_root()},
      {"MINGW_PREFIX", mingw_prefix()}
    ]
  end
end
