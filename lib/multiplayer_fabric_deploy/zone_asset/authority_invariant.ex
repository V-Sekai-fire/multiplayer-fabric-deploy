defmodule MultiplayerFabricDeploy.ZoneAsset.AuthorityInvariant do
  @moduledoc """
  Verifies that the authority zone (determined by Hilbert code) is the only zone
  that executes CMD_INSTANCE_ASSET locally.

  Non-authority zones forward the packet, they do not execute.
  """

  @doc """
  Verify whether a zone should execute a command locally or forward it.

  Returns {:ok, true} if this zone is authoritative for the position,
  or {:ok, false} if it should forward.
  """
  def verify_authority(receiving_zone, authority_zone, _command, _pos) do
    # Authority is determined by Hilbert code of the position.
    # If receiving_zone matches authority_zone, execute locally.
    # Otherwise, forward to authority zone.
    {:ok, receiving_zone == authority_zone}
  end
end
