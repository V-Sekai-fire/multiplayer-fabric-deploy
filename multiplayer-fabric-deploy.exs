#!/usr/bin/env elixir

defmodule Config do
  def world_pwd, do: File.cwd!()

  def operating_system do
    case :os.type() do
      {:unix, :darwin} -> "macos"
      {:unix, _} -> "linux"
      {:win32, _} -> "windows"
    end
  end

  def rust_log, do: "log"
  def mvsqlite_data_plane, do: "http://192.168.0.39:7000"
  def build_count, do: "001"
  def docker_gocd_agent_centos_8_groups_git, do: "abcdefgh"
  def godot_groups_editor_pipeline_dependency, do: "dependency_name"

  def label_template do
    hash = String.slice(docker_gocd_agent_centos_8_groups_git(), 0, 8)
    "docker-gocd-agent-centos-8-groups_#{hash}.#{build_count()}"
  end

  def groups_label_template,
    do: "groups-4.3.#{godot_groups_editor_pipeline_dependency()}.#{build_count()}"

  def godot_status, do: "groups-4.3"
  def git_url_docker, do: "https://github.com/V-Sekai/docker-groups.git"
  def git_url_vsekai, do: "https://github.com/V-Sekai/v-sekai-game.git"
  def android_ndk_version, do: "23.2.8568313"

  def arm64toolchain,
    do:
      "https://github.com/godotengine/buildroot/releases/download/godot-2023.08.x-4/aarch64-godot-linux-gnu_sdk-buildroot.tar.bz2"

  def cmdlinetools, do: "commandlinetools-linux-11076708_latest.zip"

  def arm64_root, do: Path.join(world_pwd(), "aarch64-godot-linux-gnu_sdk-buildroot")
  def android_sdk_root, do: Path.join(world_pwd(), "android_sdk")
  def android_home, do: android_sdk_root()
  def java_home, do: Path.join(world_pwd(), "jdk")
  def vulkan_sdk_root, do: Path.join(world_pwd(), "vulkan_sdk/")
  def emsdk_root, do: Path.join(world_pwd(), "emsdk")
  def osxcross_root, do: Path.join(world_pwd(), "osxcross")
  def mingw_prefix, do: Path.join(world_pwd(), "mingw")

  def env_vars do
    [
      {"RUST_LOG", rust_log()},
      {"MVSQLITE_DATA_PLANE", mvsqlite_data_plane()},
      {"OPERATING_SYSTEM", operating_system()},
      {"BUILD_COUNT", build_count()},
      {"DOCKER_GOCDA_AGENT_CENTOS_8_GROUPS_GIT", docker_gocd_agent_centos_8_groups_git()},
      {"GODOT_GROUPS_EDITOR_PIPELINE_DEPENDENCY", godot_groups_editor_pipeline_dependency()},
      {"LABEL_TEMPLATE", label_template()},
      {"GROUPS_LABEL_TEMPLATE", groups_label_template()},
      {"GODOT_STATUS", godot_status()},
      {"GIT_URL_DOCKER", git_url_docker()},
      {"GIT_URL_VSEKAI", git_url_vsekai()},
      {"WORLD_PWD", world_pwd()},
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

defmodule Deploy do
  defp bash(script) do
    case System.cmd("bash", ["-c", script], env: Config.env_vars(), into: IO.stream()) do
      {_, 0} -> :ok
      {_, code} -> raise "Command failed with exit code #{code}"
    end
  end

  def list_tasks do
    IO.puts("""
    Available tasks:
      run-all
      fetch-llvm-mingw-macos
      fetch-llvm-mingw
      setup-d3d12
      fetch-openjdk
      fetch-vulkan-sdk
      setup-android-sdk
      setup-rust
      setup-emscripten
      setup-arm64
      deploy-osxcross
      build-osxcross
      nil
      install-packages
      copy-binaries
      prepare-exports
      generate-build-constants
      build-platform-target <platform> <target> [arch] [precision] [osx_bundle] [extra_options]
      build-platform-templates <platform> [arch] [precision]
      all-build-platform-target
      handle-special-cases <platform> <target>
      handle-android <target>
      handle-macos <target>
      package-tpz <folder> <tpzname> <versionpy> [precision]
      is-github-actions
    """)
  end

  def run_all do
    fetch_openjdk()
    setup_android_sdk()
    setup_emscripten()
    fetch_llvm_mingw()
    build_osxcross()
    fetch_vulkan_sdk()
    build_platform_target("macos", "template_release")
    IO.puts("run-all: Success!")
  end

  def fetch_llvm_mingw_macos do
    bash("""
    if [ ! -d "${MINGW_PREFIX}" ]; then
        cd $WORLD_PWD
        mkdir -p ${MINGW_PREFIX}
        curl -o llvm-mingw.tar.xz -L https://github.com/mstorsjo/llvm-mingw/releases/download/20241030/llvm-mingw-20241030-ucrt-macos-universal.tar.xz
        tar --dereference -xf llvm-mingw.tar.xz -C ${MINGW_PREFIX} --strip 1
        rm -rf llvm-mingw.tar.xz
    fi
    """)
  end

  def fetch_llvm_mingw do
    bash("""
    if [ ! -d "${MINGW_PREFIX}" ]; then
        cd $WORLD_PWD
        mkdir -p ${MINGW_PREFIX}
        curl -o llvm-mingw.tar.xz -L https://github.com/mstorsjo/llvm-mingw/releases/download/20240917/llvm-mingw-20240917-ucrt-ubuntu-20.04-x86_64.tar.xz
        tar --dereference -xf llvm-mingw.tar.xz -C ${MINGW_PREFIX} --strip 1
        rm -rf llvm-mingw.tar.xz
    fi
    """)
  end

  def setup_d3d12 do
    bash("""
    cd $WORLD_PWD/godot
    if [ ! -d "bin/build_deps/mesa" ] || [ ! -d "bin/build_deps/agility_sdk" ]; then
        python3 misc/scripts/install_d3d12_sdk_windows.py --mingw_prefix=${MINGW_PREFIX}
    fi
    """)
  end

  def fetch_openjdk do
    bash("""
    if [ ! -d "${JAVA_HOME}" ]; then
        curl --fail --location --silent --show-error \
          "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_$(uname -m | sed -e s/86_//g)_linux_hotspot_17.0.11_9.tar.gz" \
          --output jdk.tar.gz
        mkdir -p ${JAVA_HOME}
        tar --dereference -xf jdk.tar.gz -C ${JAVA_HOME} --strip 1
        rm -rf jdk.tar.gz
    fi
    """)
  end

  def fetch_vulkan_sdk do
    bash("""
    if [ ! -d "${VULKAN_SDK_ROOT}" ]; then
        curl -L "https://github.com/godotengine/moltenvk-osxcross/releases/download/vulkan-sdk-1.3.283.0-2/MoltenVK-all.tar" -o vulkan-sdk.zip
        mkdir -p ${VULKAN_SDK_ROOT}
        tar -xf vulkan-sdk.zip -C ${VULKAN_SDK_ROOT}
        rm vulkan-sdk.zip
    fi
    """)
  end

  def setup_android_sdk do
    bash("""
    if [ ! -d "${ANDROID_SDK_ROOT}" ]; then
        mkdir -p ${ANDROID_SDK_ROOT}
        if [ ! -d "${WORLD_PWD}/#{Config.cmdlinetools()}" ]; then
            curl -LO https://dl.google.com/android/repository/#{Config.cmdlinetools()} -o ${WORLD_PWD}/#{Config.cmdlinetools()}
            cd ${WORLD_PWD} && unzip -o ${WORLD_PWD}/#{Config.cmdlinetools()}
            rm ${WORLD_PWD}/#{Config.cmdlinetools()}
            yes | ${WORLD_PWD}/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses
            yes | ${WORLD_PWD}/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} \
              "ndk;${ANDROID_NDK_VERSION}" 'cmdline-tools;latest' 'build-tools;34.0.0' 'platforms;android-34' 'cmake;3.22.1'
        fi
    fi
    """)
  end

  def setup_rust do
    bash("""
    cd $WORLD_PWD
    if [ ! -d "${RUST_ROOT}" ]; then
        mkdir -p ${RUST_ROOT}
        curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain nightly --no-modify-path
        . "$HOME/.cargo/env"
        rustup default nightly
        rustup target add aarch64-linux-android x86_64-linux-android x86_64-unknown-linux-gnu \
          aarch64-apple-ios x86_64-apple-ios x86_64-apple-darwin aarch64-apple-darwin \
          x86_64-pc-windows-gnu x86_64-pc-windows-msvc wasm32-wasi
    fi
    """)
  end

  def setup_emscripten do
    bash("""
    if [ ! -d "${EMSDK_ROOT}" ]; then
        git clone https://github.com/emscripten-core/emsdk.git $EMSDK_ROOT
        cd $EMSDK_ROOT
        ./emsdk install 4.0.11
        ./emsdk activate 4.0.11
    fi
    """)
  end

  def setup_arm64 do
    bash("""
    curl -LO "${arm64toolchain}" && \
    tar xf aarch64-godot-linux-gnu_sdk-buildroot.tar.bz2 && \
    rm -f aarch64-godot-linux-gnu_sdk-buildroot.tar.bz2 && \
    cd aarch64-godot-linux-gnu_sdk-buildroot && \
    ./relocate-sdk.sh
    """)
  end

  def deploy_osxcross do
    bash("""
    git clone https://github.com/tpoechtrager/osxcross.git || true
    cd osxcross
    ./tools/gen_sdk_package.sh
    """)
  end

  def build_osxcross do
    bash("""
    if [ ! -d "${OSXCROSS_ROOT}" ]; then
        git clone https://github.com/tpoechtrager/osxcross.git
        curl -o $OSXCROSS_ROOT/tarballs/MacOSX15.0.sdk.tar.xz -L https://github.com/V-Sekai/world/releases/download/v0.0.1/MacOSX15.0.sdk.tar.xz
        ls -l $OSXCROSS_ROOT/tarballs/
        cd $OSXCROSS_ROOT && UNATTENDED=1 ./build.sh && ./build_compiler_rt.sh
    fi
    """)
  end

  def nil_task do
    IO.puts("nil: Succeeded.")
  end

  def install_packages do
    bash("""
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
    """)
  end

  def copy_binaries do
    File.cp!("templates/windows_release_x86_64.exe", "export_windows/v_sekai_windows.exe")
    File.cp!("templates/linux_release.x86_64", "export_linuxbsd/v_sekai_linuxbsd")
  end

  def prepare_exports do
    File.rm_rf!("export_windows")
    File.rm_rf!("export_linuxbsd")
    File.mkdir!("export_windows")
    File.mkdir!("export_linuxbsd")
  end

  def generate_build_constants do
    date = System.cmd("date", ["--utc", "--iso=seconds"]) |> elem(0) |> String.trim()
    unix_time = System.cmd("date", ["+%s"]) |> elem(0) |> String.trim()
    label = Config.groups_label_template()

    content = """
    ## AUTOGENERATED BY BUILD

    const BUILD_LABEL = "#{label}"
    const BUILD_DATE_STR = "#{date}"
    const BUILD_UNIX_TIME = #{unix_time}
    """

    File.write!("v/addons/vsk_version/build_constants.gd", content)
  end

  def build_platform_target(
        platform,
        target,
        arch \\ "auto",
        precision \\ "double",
        osx_bundle \\ "yes",
        extra_options \\ ""
      ) do
    bash("""
    set -o xtrace
    cd $WORLD_PWD

    if [[ "#{platform}" == "web" && -d "$EMSDK_ROOT" ]]; then
        source "$EMSDK_ROOT/emsdk_env.sh"
    fi

    HOST_ARCH=$( uname -m )
    echo "HOST ARCHITECTURE: ${HOST_ARCH}"

    if [[ "#{arch}" == "arm64" && ${HOST_ARCH} == 'x86_64' ]]; then
        rename 'aarch64-godot-linux-gnu-' '' ${ARM64_ROOT}/bin/*
        export PATH="$ARM64_ROOT/bin:$PATH"
    fi

    cd godot

    case "#{platform}" in
        macos)
            if [ "$(uname)" = "Darwin" ]; then
                unset OSXCROSS_ROOT
            else
                export PATH=${OSXCROSS_ROOT}/target/bin/:$PATH
            fi
            scons platform=macos \
                    arch=#{arch} \
                    werror=no \
                    compiledb=yes \
                    precision=#{precision} \
                    target=#{target} \
                    test=yes \
                    vulkan=no \
                    vulkan_sdk_path=$VULKAN_SDK_ROOT/MoltenVK/MoltenVK/static/MoltenVK.xcframework \
                    osxcross_sdk=darwin24 \
                    generate_bundle=#{osx_bundle} \
                    debug_symbols=yes \
                    separate_debug_symbols=yes \
                    #{extra_options}
            ;;
        windows)
            scons platform=windows \
                arch=#{arch} \
                werror=no \
                compiledb=yes \
                precision=#{precision} \
                target=#{target} \
                test=yes \
                use_llvm=yes \
                use_mingw=yes \
                debug_symbols=yes \
                separate_debug_symbols=yes \
                #{extra_options}
            ;;
        android)
            scons platform=android \
                    arch=#{arch} \
                    werror=no \
                    compiledb=yes \
                    precision=#{precision} \
                    target=#{target} \
                    test=yes \
                    #{extra_options}
            ;;
        linuxbsd)
            if [[ "$(#{__MODULE__}.is_github_actions_cmd())" == "true" && "#{target}" == "editor" ]]; then
                DEBUG_SYMBOLS="debug_symbols=no"
            else
                DEBUG_SYMBOLS="debug_symbols=yes separate_debug_symbols=yes"
            fi
            scons platform=linuxbsd \
                    arch=#{arch} \
                    werror=no \
                    compiledb=yes \
                    precision=#{precision} \
                    target=#{target} \
                    test=yes \
                    $DEBUG_SYMBOLS \
                    #{extra_options}
            ;;
        web)
            scons platform=web \
                    arch=#{arch} \
                    werror=no \
                    optimize=size_extra \
                    compiledb=yes \
                    precision=#{precision} \
                    target=#{target} \
                    test=yes \
                    dlink_enabled=yes \
                    debug_symbols=no \
                    disable_exceptions=yes \
                    #{extra_options}
            ;;
        ios)
            if [ "$(uname)" = "Darwin" ]; then
                unset OSXCROSS_ROOT
            else
                export PATH=${OSXCROSS_ROOT}/target/bin/:$PATH
            fi
            scons platform=ios \
                    arch=#{arch} \
                    werror=no \
                    compiledb=yes \
                    precision=#{precision} \
                    target=#{target} \
                    test=yes \
                    vulkan=no \
                    vulkan_sdk_path=$VULKAN_SDK_ROOT/MoltenVK/MoltenVK/static/MoltenVK.xcframework \
                    osxcross_sdk=darwin24 \
                    generate_bundle=#{osx_bundle} \
                    debug_symbols=yes \
                    separate_debug_symbols=yes \
                    #{extra_options}
            ;;
        *)
            echo "Unsupported platform: #{platform}"
            exit 1
            ;;
    esac

    #{__MODULE__}.handle_special_cases_cmd("#{platform}", "#{target}")

    rm -rf $WORLD_PWD/godot/bin/obj

    if [[ "$(#{__MODULE__}.is_github_actions_cmd())" == "true" ]]; then COPYSYM="-l"; else COPYSYM=""; fi

    if [[ "#{target}" == "editor" ]]; then
        mkdir -p $WORLD_PWD/editors
        cp $COPYSYM -rf $WORLD_PWD/godot/bin/* $WORLD_PWD/editors
    elif [[ "#{target}" =~ template_* && \
            "#{platform}" =~ ^(mac|i)os && \
            "#{osx_bundle}" == "no" ]]; then
        true
    elif [[ "#{target}" =~ template_* ]]; then
        mkdir -p $WORLD_PWD/tpz
        cp -rf $WORLD_PWD/godot/bin/* $WORLD_PWD/tpz
    fi
    """)
  end

  def build_platform_templates(platform, arch \\ "auto", precision \\ "double") do
    build_platform_target(platform, "template_debug", arch, precision, "no")
    build_platform_target(platform, "template_release", arch, precision, "yes")
  end

  def all_build_platform_target do
    bash("""
    parallel --ungroup --jobs 1 'elixir #{__ENV__.file} build-platform-target {1} {2}' \
    ::: windows linuxbsd macos android web \
    ::: editor template_debug template_release
    """)
  end

  def handle_special_cases(platform, target) do
    case platform do
      "android" -> handle_android(target)
      "macos" -> handle_macos(target)
      _ -> :ok
    end
  end

  def handle_android(target) do
    bash("""
    cd godot
    if [ "#{target}" = "editor" ]; then
        cd platform/android/java
        ./gradlew generateGodotEditor
        ./gradlew generateGodotHorizonOSEditor
        cd ../../..
        ls -l bin/android_editor_builds/
    elif [ "#{target}" = "template_release" ] || [ "#{target}" = "template_debug" ]; then
        cd platform/android/java
        ./gradlew generateGodotTemplates
        cd ../../..
        ls -l bin/
    fi
    """)
  end

  def handle_macos(target) do
    bash("""
    cd godot
    if [ "#{target}" = "editor" ]; then
        chmod +x ./bin/*.app/Contents/MacOS/* || echo "Could not set execute permission on editor"
    fi
    """)
  end

  def package_tpz(folder, tpzname, versionpy, precision \\ "double") do
    bash("""
    cd #{folder}
    rm *.arm64.a || true
    for file in *; do
        filename=$( echo ${file} \
          | sed 's/\\(godot.\\|.double\\|.template\\|.llvm\\|.wasm32\\)//g' \
          | sed 's/linuxbsd/linux/;s/.console/_console/' \
          | sed 's/^web\\(_debug\\|_release\\)\\.\\(dlink\\)\\(.*\\)/web_\\2\\1\\3/' \
          | sed 's/\\(windows_[a-z]*\\)\\./\\1_/' \
        ) \
        && echo -e "Renaming ${file} to \\n ${filename}" \
        && mv ${file} ${filename}
    done
    cd ..
    cat #{versionpy} | tr -d ' ' | tr -s '\\n' ' ' \
      | sed -E 's/.*major=([0-9]).minor=([0-9]).*status=\\"([a-z]*)\\".*/\\1.\\2.\\3/' \
      > #{folder}/version.txt
    if [ "#{precision}" = "double" ]; then
      echo ".double" >> #{folder}/version.txt
    fi
    echo "Godot TPZ Version: $( cat #{folder}/version.txt )"
    mkdir -p tpz_temp && mv #{folder} tpz_temp/templates && cd tpz_temp \
      && zip -r ../#{tpzname}.tpz templates && cd ..
    rm -r tpz_temp
    """)
  end

  def is_github_actions do
    ci = System.get_env("CI")
    github_actions = System.get_env("GITHUB_ACTIONS")
    ci == "true" && github_actions == "true"
  end
end

# CLI dispatch
case System.argv() do
  [] ->
    Deploy.list_tasks()

  ["run-all"] ->
    Deploy.run_all()

  ["fetch-llvm-mingw-macos"] ->
    Deploy.fetch_llvm_mingw_macos()

  ["fetch-llvm-mingw"] ->
    Deploy.fetch_llvm_mingw()

  ["setup-d3d12"] ->
    Deploy.setup_d3d12()

  ["fetch-openjdk"] ->
    Deploy.fetch_openjdk()

  ["fetch-vulkan-sdk"] ->
    Deploy.fetch_vulkan_sdk()

  ["setup-android-sdk"] ->
    Deploy.setup_android_sdk()

  ["setup-rust"] ->
    Deploy.setup_rust()

  ["setup-emscripten"] ->
    Deploy.setup_emscripten()

  ["setup-arm64"] ->
    Deploy.setup_arm64()

  ["deploy-osxcross"] ->
    Deploy.deploy_osxcross()

  ["build-osxcross"] ->
    Deploy.build_osxcross()

  ["nil"] ->
    Deploy.nil_task()

  ["install-packages"] ->
    Deploy.install_packages()

  ["copy-binaries"] ->
    Deploy.copy_binaries()

  ["prepare-exports"] ->
    Deploy.prepare_exports()

  ["generate-build-constants"] ->
    Deploy.generate_build_constants()

  ["build-platform-target", platform, target | rest] ->
    [arch, precision, osx_bundle, extra_options] =
      Enum.zip(rest, ["auto", "double", "yes", ""])
      |> Enum.map(&elem(&1, 0))
      |> then(fn filled ->
        filled ++ Enum.drop(["auto", "double", "yes", ""], length(filled))
      end)

    Deploy.build_platform_target(platform, target, arch, precision, osx_bundle, extra_options)

  ["build-platform-templates", platform | rest] ->
    [arch, precision] =
      rest
      |> then(fn args ->
        args ++ Enum.drop(["auto", "double"], length(args))
      end)

    Deploy.build_platform_templates(platform, arch, precision)

  ["all-build-platform-target"] ->
    Deploy.all_build_platform_target()

  ["handle-special-cases", platform, target] ->
    Deploy.handle_special_cases(platform, target)

  ["handle-android", target] ->
    Deploy.handle_android(target)

  ["handle-macos", target] ->
    Deploy.handle_macos(target)

  ["package-tpz", folder, tpzname, versionpy | rest] ->
    precision = List.first(rest, "double")
    Deploy.package_tpz(folder, tpzname, versionpy, precision)

  ["is-github-actions"] ->
    IO.puts(if Deploy.is_github_actions(), do: "true", else: "false")

  [unknown | _] ->
    IO.puts("Unknown task: #{unknown}")
    Deploy.list_tasks()
    System.halt(1)
end
