defmodule MultiplayerFabricDeploy.HilbertCurve do
  @moduledoc """
  3D Hilbert curve implementation for zone authority routing.

  Converts 3D coordinates (x, y, z) to a 1D Hilbert index.
  This determines which zone is authoritative for a given position.

  Uses Morton encoding (Z-order curve) as a simpler space-filling curve
  that preserves locality and is easily computed with bitwise operations.
  """

  import Bitwise

  @doc """
  Convert 3D coordinates to a 1D Morton (Z-order) index.

  Args:
    - order: the recursion depth (determines grid resolution 2^order per side)
    - x, y, z: coordinates in range [0, 2^order)

  Returns:
    - index: the 1D position (Morton encoding)
  """
  def xyz_to_index(_order, x, y, z) do
    # Morton encoding (Z-order curve): interleave bits of x, y, z
    # For each bit position i, the result has z_i, y_i, x_i in sequence
    # This creates a space-filling curve that preserves locality

    morton_encode(x, y, z)
  end

  defp morton_encode(x, y, z) do
    # Interleave the 32 bits of x, y, z
    # Result: bit pattern is ...z2y2x2z1y1x1z0y0x0

    result = 0
    result = result ||| spread_bits(x) <<< 0
    result = result ||| spread_bits(y) <<< 1
    result = result ||| spread_bits(z) <<< 2

    result
  end

  # Spread bits: convert 0xABCDEF to 0x00A00B00C00D00E00F
  # This interleaves the bits so they can be combined with other coordinates
  defp spread_bits(x) do
    x = (x ||| x <<< 8) &&& 0x00FF00FF
    x = (x ||| x <<< 4) &&& 0x0F0F0F0F
    x = (x ||| x <<< 2) &&& 0x33333333
    x = (x ||| x <<< 1) &&& 0x55555555
    x
  end

  @doc """
  Inverse: convert 1D Morton index back to 3D coordinates.
  """
  def index_to_xyz(_order, index) do
    # Extract interleaved bits
    x = unspread_bits(index >>> 0)
    y = unspread_bits(index >>> 1)
    z = unspread_bits(index >>> 2)

    {x, y, z}
  end

  # Inverse of spread_bits
  defp unspread_bits(x) do
    x = (x ||| x >>> 1) &&& 0x33333333
    x = (x ||| x >>> 2) &&& 0x0F0F0F0F
    x = (x ||| x >>> 4) &&& 0x00FF00FF
    x = (x ||| x >>> 8) &&& 0x0000FFFF
    x
  end

  @doc """
  Convert floating-point world coordinates to Morton index.

  Maps physical world position to a zone authority via space-filling curve.

  Args:
    - pos: {x_float, y_float, z_float} - world coordinates
    - order: Morton curve order (2^order resolution, default 8 = 256×256×256)
    - grid_size: side length of world grid (default 10000.0)

  Returns:
    - morton_index: integer index for zone authority assignment
  """
  def world_to_hilbert(pos, opts \\ []) do
    {wx, wy, wz} = pos

    order = Keyword.get(opts, :order, 8)
    grid_size = Keyword.get(opts, :grid_size, 10000.0)

    # Convert world coords to grid coords [0, 2^order)
    max_coord = 1 <<< order

    x = clamp_world_to_grid(wx, grid_size / 2.0, max_coord)
    y = clamp_world_to_grid(wy, grid_size / 2.0, max_coord)
    z = clamp_world_to_grid(wz, grid_size / 2.0, max_coord)

    xyz_to_index(order, x, y, z)
  end

  defp clamp_world_to_grid(world_coord, half_size, grid_max) do
    # Map from [-half_size, half_size] to [0, grid_max)
    normalized = (world_coord + half_size) / (2.0 * half_size)
    clamped = max(0.0, min(1.0, normalized))
    trunc(clamped * (grid_max - 1))
  end

  @doc """
  Assign a zone ID from Morton index.

  Args:
    - morton_index: output from xyz_to_index or world_to_hilbert
    - num_zones: total number of zones managing the grid

  Returns:
    - zone_id: integer in range [0, num_zones)
  """
  def hilbert_to_zone(morton_index, num_zones) do
    Integer.mod(morton_index, num_zones)
  end
end
