defmodule MultiplayerFabricDeploy.ConfigTest do
  use ExUnit.Case, async: true

  alias MultiplayerFabricDeploy.Config

  @home System.user_home!()
  @data_dir Path.join(@home, ".multiplayer-fabric-deploy")

  test "data_dir is under home" do
    assert Config.data_dir() == @data_dir
  end

  test "logs_dir is under data_dir" do
    assert Config.logs_dir() == Path.join(@data_dir, "logs")
  end

  test "java_home is under data_dir, not cwd" do
    refute String.starts_with?(Config.java_home(), File.cwd!())
    assert String.starts_with?(Config.java_home(), @data_dir)
  end

  test "android_sdk_root is under data_dir, not cwd" do
    refute String.starts_with?(Config.android_sdk_root(), File.cwd!())
    assert String.starts_with?(Config.android_sdk_root(), @data_dir)
  end

  test "vulkan_sdk_root is under data_dir, not cwd" do
    refute String.starts_with?(Config.vulkan_sdk_root(), File.cwd!())
    assert String.starts_with?(Config.vulkan_sdk_root(), @data_dir)
  end

  test "emsdk_root is under data_dir, not cwd" do
    refute String.starts_with?(Config.emsdk_root(), File.cwd!())
    assert String.starts_with?(Config.emsdk_root(), @data_dir)
  end

  test "mingw_prefix is under data_dir, not cwd" do
    refute String.starts_with?(Config.mingw_prefix(), File.cwd!())
    assert String.starts_with?(Config.mingw_prefix(), @data_dir)
  end

  test "godot_dir is under data_dir, not cwd" do
    refute String.starts_with?(Config.godot_dir(), File.cwd!())
    assert String.starts_with?(Config.godot_dir(), @data_dir)
  end

  test "arm64_root remains under world_pwd (per-project checkout)" do
    assert String.starts_with?(Config.arm64_root(), File.cwd!())
  end

  test "env_vars includes all expected keys" do
    keys = Config.env_vars() |> Enum.map(&elem(&1, 0))

    assert "JAVA_HOME" in keys
    assert "ANDROID_SDK_ROOT" in keys
    assert "ANDROID_HOME" in keys
    assert "VULKAN_SDK_ROOT" in keys
    assert "EMSDK_ROOT" in keys
    assert "MINGW_PREFIX" in keys
  end
end
