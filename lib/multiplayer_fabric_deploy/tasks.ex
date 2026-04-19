defmodule MultiplayerFabricDeploy.Tasks do
  alias MultiplayerFabricDeploy.Config

  defstruct [:id, :name, :desc, :run]

  def all do
    [
      %__MODULE__{
        id: :run_all,
        name: "run-all",
        desc: "Run all setup steps and build macOS template_release",
        run: {:elixir, fn parent ->
          fetch_godot(parent)
          MultiplayerFabricDeploy.Runner.run_bash_sync(run_all_bash_script(), parent)
        end}
      },
      %__MODULE__{
        id: :fetch_godot,
        name: "fetch-godot",
        desc: "Clone or update #{Config.godot_git_url()} @ #{Config.godot_branch()}",
        run: {:elixir, &fetch_godot/1}
      },
      %__MODULE__{
        id: :fetch_openjdk,
        name: "fetch-openjdk",
        desc: "Download OpenJDK 17 for Android builds",
        run: {:bash, fetch_openjdk_script()}
      },
      %__MODULE__{
        id: :fetch_vulkan_sdk,
        name: "fetch-vulkan-sdk",
        desc: "Download MoltenVK for macOS/iOS builds",
        run: {:bash, fetch_vulkan_sdk_script()}
      },
      %__MODULE__{
        id: :setup_android_sdk,
        name: "setup-android-sdk",
        desc: "Install Android SDK, NDK #{Config.android_ndk_version()}, and build tools",
        run: {:bash, setup_android_sdk_script()}
      },
      %__MODULE__{
        id: :setup_emscripten,
        name: "setup-emscripten",
        desc: "Clone emsdk and activate Emscripten 4.0.11",
        run: {:bash, setup_emscripten_script()}
      },
      %__MODULE__{
        id: :fetch_llvm_mingw,
        name: "fetch-llvm-mingw",
        desc: "Download llvm-mingw toolchain for Linux hosts (Windows cross-compile)",
        run: {:bash, fetch_llvm_mingw_script()}
      },
      %__MODULE__{
        id: :fetch_llvm_mingw_macos,
        name: "fetch-llvm-mingw-macos",
        desc: "Download llvm-mingw toolchain for macOS hosts (Windows cross-compile)",
        run: {:bash, fetch_llvm_mingw_macos_script()}
      },
      %__MODULE__{
        id: :setup_arm64,
        name: "setup-arm64",
        desc: "Download and relocate aarch64 Godot buildroot toolchain",
        run: {:bash, setup_arm64_script()}
      },
      %__MODULE__{
        id: :build_osxcross,
        name: "build-osxcross",
        desc: "Clone osxcross and build macOS SDK cross-compiler",
        run: {:bash, build_osxcross_script()}
      },
      %__MODULE__{
        id: :setup_sccache,
        name: "setup-sccache",
        desc: "Install sccache compiler cache via cargo",
        run: {:bash, setup_sccache_script()}
      },
      %__MODULE__{
        id: :setup_rust,
        name: "setup-rust",
        desc: "Install Rust nightly with all cross-compile targets",
        run: {:bash, setup_rust_script()}
      },
      %__MODULE__{
        id: :setup_d3d12,
        name: "setup-d3d12",
        desc: "Install D3D12/Mesa/AgilitySdk for Windows builds",
        run: {:bash, setup_d3d12_script()}
      },
      %__MODULE__{
        id: :deploy_osxcross,
        name: "deploy-osxcross",
        desc: "Generate macOS SDK package via osxcross tools",
        run: {:bash, deploy_osxcross_script()}
      },
      %__MODULE__{
        id: :install_packages,
        name: "install-packages",
        desc: "Install system build dependencies (dnf or apt)",
        run: {:bash, install_packages_script()}
      },
      %__MODULE__{
        id: :prepare_exports,
        name: "prepare-exports",
        desc: "Clear and recreate export_windows / export_linuxbsd directories",
        run: {:bash, "rm -rf export_windows export_linuxbsd && mkdir -p export_windows export_linuxbsd"}
      },
      %__MODULE__{
        id: :copy_binaries,
        name: "copy-binaries",
        desc: "Copy built templates to export directories",
        run: {:bash, """
        cp templates/windows_release_x86_64.exe export_windows/multiplayer_fabric_windows.exe
        cp templates/linux_release.x86_64 export_linuxbsd/multiplayer_fabric_linuxbsd
        """}
      },
      %__MODULE__{
        id: :generate_build_constants,
        name: "generate-build-constants",
        desc: "Write build_constants.gd with label, date, and unix timestamp",
        run: {:bash, generate_build_constants_script()}
      },
      %__MODULE__{
        id: :build_macos_template,
        name: "build-macos-template",
        desc: "Build macOS template_release (double precision)",
        run: {:bash, build_platform_script("macos", "template_release")}
      },
      %__MODULE__{
        id: :build_linuxbsd_editor,
        name: "build-linuxbsd-editor",
        desc: "Build Linux/BSD editor (double precision)",
        run: {:bash, build_platform_script("linuxbsd", "editor")}
      },
      %__MODULE__{
        id: :build_windows_template,
        name: "build-windows-template",
        desc: "Build Windows template_release via llvm-mingw",
        run: {:bash, build_platform_script("windows", "template_release")}
      },
      %__MODULE__{
        id: :build_android_template,
        name: "build-android-template",
        desc: "Build Android template_release (arm64)",
        run: {:bash, build_platform_script("android", "template_release", "arm64")}
      },
      %__MODULE__{
        id: :build_web_template,
        name: "build-web-template",
        desc: "Build Web template_release with dlink and Emscripten",
        run: {:bash, build_platform_script("web", "template_release")}
      }
    ]
  end

  def fetch_godot(parent) do
    url = Config.godot_git_url()
    branch = Config.godot_branch()
    path = Config.godot_dir()

    result =
      if File.dir?(Path.join(path, ".git")) do
        send(parent, {:output_line, "Opening #{path} (#{url})..."})

        with {:open, repo} when not is_tuple(repo) <- {:open, :git.open(path)},
             _ = send(parent, {:output_line, "Fetching origin (#{url})..."}),
             {:fetch, :ok} <- {:fetch, :git.fetch(repo)},
             _ = send(parent, {:output_line, "Checking out #{branch}..."}),
             {:checkout, :ok} <- {:checkout, :git.checkout(repo, branch)},
             _ = send(parent, {:output_line, "Pulling #{url}@#{branch}..."}),
             {:pull, :ok} <- {:pull, :git.pull(repo)} do
          send(parent, {:output_line, "Up to date: #{url}@#{branch}"})
          :ok
        else
          {step, {:error, reason}} -> {:error, "#{step} failed: #{inspect(reason)}"}
          {step, other} -> {:error, "#{step} unexpected: #{inspect(other)}"}
        end
      else
        send(parent, {:output_line, "Cloning #{url} into #{path}..."})

        with {:clone, repo} when not is_tuple(repo) <- {:clone, :git.clone(url, path)},
             _ = send(parent, {:output_line, "Checking out #{branch}..."}),
             {:checkout, :ok} <- {:checkout, :git.checkout(repo, branch)} do
          send(parent, {:output_line, "Clone complete on #{branch}"})
          :ok
        else
          {step, {:error, reason}} -> {:error, "#{step} failed: #{inspect(reason)}"}
          {step, other} -> {:error, "#{step} unexpected: #{inspect(other)}"}
        end
      end

    case result do
      :ok ->
        send(parent, {:task_done, 0})

      {:error, msg} ->
        send(parent, {:output_line, "Error: #{msg}"})
        send(parent, {:task_done, 1})
    end
  end

  defp run_all_bash_script do
    """
    set -e
    #{setup_sccache_script()}
    #{fetch_openjdk_script()}
    #{setup_android_sdk_script()}
    #{setup_emscripten_script()}
    #{fetch_llvm_mingw_script()}
    #{build_osxcross_script()}
    #{fetch_vulkan_sdk_script()}
    #{build_platform_script("macos", "template_release")}
    echo "run-all: Success!"
    """
  end

  defp fetch_openjdk_script do
    """
    if [ ! -d "${JAVA_HOME}" ]; then
        curl --fail --location --silent --show-error \
          "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_$(uname -m | sed -e s/86_//g)_linux_hotspot_17.0.11_9.tar.gz" \
          --output jdk.tar.gz
        mkdir -p ${JAVA_HOME}
        tar --dereference -xf jdk.tar.gz -C ${JAVA_HOME} --strip 1
        rm -rf jdk.tar.gz
    fi
    """
  end

  defp fetch_vulkan_sdk_script do
    """
    if [ ! -d "${VULKAN_SDK_ROOT}" ]; then
        curl -L "https://github.com/godotengine/moltenvk-osxcross/releases/download/vulkan-sdk-1.3.283.0-2/MoltenVK-all.tar" -o vulkan-sdk.zip
        mkdir -p ${VULKAN_SDK_ROOT}
        tar -xf vulkan-sdk.zip -C ${VULKAN_SDK_ROOT}
        rm vulkan-sdk.zip
    fi
    """
  end

  defp setup_android_sdk_script do
    ct = Config.cmdlinetools()

    """
    if [ ! -d "${ANDROID_SDK_ROOT}" ]; then
        mkdir -p ${ANDROID_SDK_ROOT}
        if [ ! -d "${WORLD_PWD}/#{ct}" ]; then
            curl -LO https://dl.google.com/android/repository/#{ct} -o ${WORLD_PWD}/#{ct}
            cd ${WORLD_PWD} && unzip -o ${WORLD_PWD}/#{ct}
            rm ${WORLD_PWD}/#{ct}
            yes | ${WORLD_PWD}/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses
            yes | ${WORLD_PWD}/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} \
              "ndk;${ANDROID_NDK_VERSION}" 'cmdline-tools;latest' 'build-tools;34.0.0' 'platforms;android-34' 'cmake;3.22.1'
        fi
    fi
    """
  end

  defp setup_emscripten_script do
    """
    if [ ! -d "${EMSDK_ROOT}" ]; then
        git clone https://github.com/emscripten-core/emsdk.git $EMSDK_ROOT
        cd $EMSDK_ROOT
        ./emsdk install 4.0.11
        ./emsdk activate 4.0.11
    fi
    """
  end

  defp fetch_llvm_mingw_script do
    """
    if [ ! -d "${MINGW_PREFIX}" ]; then
        cd $WORLD_PWD
        mkdir -p ${MINGW_PREFIX}
        curl -o llvm-mingw.tar.xz -L https://github.com/mstorsjo/llvm-mingw/releases/download/20240917/llvm-mingw-20240917-ucrt-ubuntu-20.04-x86_64.tar.xz
        tar --dereference -xf llvm-mingw.tar.xz -C ${MINGW_PREFIX} --strip 1
        rm -rf llvm-mingw.tar.xz
    fi
    """
  end

  defp fetch_llvm_mingw_macos_script do
    """
    if [ ! -d "${MINGW_PREFIX}" ]; then
        cd $WORLD_PWD
        mkdir -p ${MINGW_PREFIX}
        curl -o llvm-mingw.tar.xz -L https://github.com/mstorsjo/llvm-mingw/releases/download/20241030/llvm-mingw-20241030-ucrt-macos-universal.tar.xz
        tar --dereference -xf llvm-mingw.tar.xz -C ${MINGW_PREFIX} --strip 1
        rm -rf llvm-mingw.tar.xz
    fi
    """
  end

  defp setup_arm64_script do
    """
    curl -LO "#{Config.arm64toolchain()}" && \
    tar xf aarch64-godot-linux-gnu_sdk-buildroot.tar.bz2 && \
    rm -f aarch64-godot-linux-gnu_sdk-buildroot.tar.bz2 && \
    cd aarch64-godot-linux-gnu_sdk-buildroot && \
    ./relocate-sdk.sh
    """
  end

  defp build_osxcross_script do
    """
    if [ ! -d "${OSXCROSS_ROOT}" ]; then
        git clone https://github.com/tpoechtrager/osxcross.git ${OSXCROSS_ROOT}
        curl -o ${OSXCROSS_ROOT}/tarballs/MacOSX15.0.sdk.tar.xz -L https://github.com/V-Sekai/world/releases/download/v0.0.1/MacOSX15.0.sdk.tar.xz
        ls -l ${OSXCROSS_ROOT}/tarballs/
        cd ${OSXCROSS_ROOT} && UNATTENDED=1 ./build.sh && ./build_compiler_rt.sh
    fi
    """
  end

  defp setup_sccache_script do
    """
    if ! which sccache > /dev/null 2>&1; then
        . "$HOME/.cargo/env" 2>/dev/null || true
        cargo install sccache --locked
    fi
    sccache --version
    """
  end

  defp setup_rust_script do
    """
    if [ ! -f "$HOME/.cargo/bin/rustup" ]; then
        curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain nightly --no-modify-path
    fi
    . "$HOME/.cargo/env"
    rustup default nightly
    rustup target add aarch64-linux-android x86_64-linux-android x86_64-unknown-linux-gnu \
      aarch64-apple-ios x86_64-apple-ios x86_64-apple-darwin aarch64-apple-darwin \
      x86_64-pc-windows-gnu x86_64-pc-windows-msvc wasm32-wasi
    """
  end

  defp setup_d3d12_script do
    """
    cd ${GODOT_DIR}
    if [ ! -d "bin/build_deps/mesa" ] || [ ! -d "bin/build_deps/agility_sdk" ]; then
        python3 misc/scripts/install_d3d12_sdk_windows.py --mingw_prefix=${MINGW_PREFIX}
    fi
    """
  end

  defp deploy_osxcross_script do
    """
    git clone https://github.com/tpoechtrager/osxcross.git || true
    cd osxcross
    ./tools/gen_sdk_package.sh
    """
  end

  defp install_packages_script do
    """
    if dnf >/dev/null 2>&1; then
        dnf install -y hyperfine vulkan xz bzip2 file gcc gcc-c++ zlib-devel libmpc-devel \
          mpfr-devel gmp-devel clang just parallel scons mold pkgconfig libX11-devel \
          libXcursor-devel libXrandr-devel libXinerama-devel libXi-devel wayland-devel \
          mesa-libGL-devel mesa-libGLU-devel alsa-lib-devel pulseaudio-libs-devel \
          libudev-devel libstdc++-static libatomic-static cmake ccache patch \
          libxml2-devel openssl openssl-devel git unzip
    else
        sudo apt install -y build-essential hyperfine vulkan-tools xz-utils bzip2 file gcc \
          zlib1g-dev libmpc-dev libmpfr-dev libgmp-dev clang just parallel scons mold \
          pkg-config libx11-dev libxcursor-dev libxrandr-dev libxinerama-dev libxi-dev \
          libwayland-dev libgl1-mesa-dev libglu1-mesa-dev libasound2-dev libpulse-dev \
          libudev-dev cmake ccache patch libxml2-dev openssl libssl-dev git unzip
    fi
    """
  end

  defp generate_build_constants_script do
    """
    mkdir -p v/addons/vsk_version
    cat > v/addons/vsk_version/build_constants.gd << 'EOF'
    ## AUTOGENERATED BY BUILD
    EOF
    echo "" >> v/addons/vsk_version/build_constants.gd
    echo "const BUILD_LABEL = \\"${LABEL_TEMPLATE}\\"" >> v/addons/vsk_version/build_constants.gd
    echo "const BUILD_DATE_STR = \\"$(date --utc --iso=seconds)\\"" >> v/addons/vsk_version/build_constants.gd
    echo "const BUILD_UNIX_TIME = $(date +%s)" >> v/addons/vsk_version/build_constants.gd
    """
  end

  defp build_platform_script(platform, target, arch \\ "auto", precision \\ "double") do
    """
    set -o xtrace

    if [[ "#{platform}" == "web" && -d "${EMSDK_ROOT}" ]]; then
        source "${EMSDK_ROOT}/emsdk_env.sh"
    fi

    HOST_ARCH=$(uname -m)
    echo "HOST ARCHITECTURE: ${HOST_ARCH}"

    if [[ "#{arch}" == "arm64" && ${HOST_ARCH} == 'x86_64' ]]; then
        rename 'aarch64-godot-linux-gnu-' '' ${ARM64_ROOT}/bin/*
        export PATH="${ARM64_ROOT}/bin:${PATH}"
    fi

    sccache --start-server 2>/dev/null || true
    echo "sccache $(sccache --version): cache dir $(sccache --show-stats 2>/dev/null | grep 'Cache location' | awk '{print $NF}' || echo unknown)"
    SCCACHE_FLAGS="c_compiler_launcher=sccache cpp_compiler_launcher=sccache"

    cd ${GODOT_DIR}

    #{platform_scons(platform, target, arch, precision)}

    #{post_build_script(platform, target)}

    sccache --show-stats 2>/dev/null || true
    """
  end

  defp platform_scons("macos", target, arch, precision) do
    """
    if [ "$(uname)" = "Darwin" ]; then unset OSXCROSS_ROOT
    else export PATH=${OSXCROSS_ROOT}/target/bin/:$PATH; fi
    scons platform=macos arch=#{arch} werror=no compiledb=yes precision=#{precision} \\
        target=#{target} test=yes vulkan=no \\
        vulkan_sdk_path=${VULKAN_SDK_ROOT}/MoltenVK/MoltenVK/static/MoltenVK.xcframework \\
        osxcross_sdk=darwin24 generate_bundle=yes debug_symbols=yes separate_debug_symbols=yes \\
        $SCCACHE_FLAGS
    """
  end

  defp platform_scons("windows", target, arch, precision) do
    """
    scons platform=windows arch=#{arch} werror=no compiledb=yes precision=#{precision} \\
        target=#{target} test=yes use_llvm=yes use_mingw=yes \\
        debug_symbols=yes separate_debug_symbols=yes \\
        $SCCACHE_FLAGS
    """
  end

  defp platform_scons("android", target, arch, precision) do
    """
    scons platform=android arch=#{arch} werror=no compiledb=yes precision=#{precision} \\
        target=#{target} test=yes \\
        $SCCACHE_FLAGS
    """
  end

  defp platform_scons("linuxbsd", target, arch, precision) do
    debug =
      if target == "editor",
        do: "debug_symbols=no",
        else: "debug_symbols=yes separate_debug_symbols=yes"

    """
    scons platform=linuxbsd arch=#{arch} werror=no compiledb=yes precision=#{precision} \\
        target=#{target} test=yes #{debug} \\
        $SCCACHE_FLAGS
    """
  end

  defp platform_scons("web", target, arch, precision) do
    """
    scons platform=web arch=#{arch} werror=no optimize=size_extra compiledb=yes \\
        precision=#{precision} target=#{target} test=yes \\
        dlink_enabled=yes debug_symbols=no disable_exceptions=yes \\
        $SCCACHE_FLAGS
    """
  end

  defp platform_scons("ios", target, arch, precision) do
    """
    if [ "$(uname)" = "Darwin" ]; then unset OSXCROSS_ROOT
    else export PATH=${OSXCROSS_ROOT}/target/bin/:$PATH; fi
    scons platform=ios arch=#{arch} werror=no compiledb=yes precision=#{precision} \\
        target=#{target} test=yes vulkan=no \\
        vulkan_sdk_path=${VULKAN_SDK_ROOT}/MoltenVK/MoltenVK/static/MoltenVK.xcframework \\
        osxcross_sdk=darwin24 generate_bundle=yes debug_symbols=yes separate_debug_symbols=yes \\
        $SCCACHE_FLAGS
    """
  end

  defp post_build_script(platform, target) do
    android_post =
      case target do
        "editor" ->
          """
          cd platform/android/java
          ./gradlew generateGodotEditor
          ./gradlew generateGodotHorizonOSEditor
          cd ../../..
          ls -l bin/android_editor_builds/
          """

        t when t in ["template_release", "template_debug"] ->
          """
          cd platform/android/java
          ./gradlew generateGodotTemplates
          cd ../../..
          ls -l bin/
          """

        _ ->
          ""
      end

    macos_post =
      if target == "editor",
        do: "chmod +x ./bin/*.app/Contents/MacOS/* || echo 'Could not set execute permission'",
        else: ""

    copy_post = """
    rm -rf ${GODOT_DIR}/bin/obj
    if [[ "#{target}" == "editor" ]]; then
        mkdir -p ${WORLD_PWD}/editors
        cp -rf ${GODOT_DIR}/bin/* ${WORLD_PWD}/editors
    elif [[ "#{target}" =~ template_* ]]; then
        mkdir -p ${WORLD_PWD}/tpz
        cp -rf ${GODOT_DIR}/bin/* ${WORLD_PWD}/tpz
    fi
    """

    case platform do
      "android" -> android_post <> copy_post
      "macos" -> macos_post <> copy_post
      _ -> copy_post
    end
  end
end
