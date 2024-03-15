defmodule ExRTCScore.Utils do
  @moduledoc false

  @doc "Fill `nil` fields in `struct` with corresponding values from `defaults`"
  @spec put_defaults_if_nil(struct(), map() | struct()) :: struct()
  def put_defaults_if_nil(struct, defaults) do
    defaults
    |> then(&if(is_struct(&1), do: Map.from_struct(&1), else: &1))
    |> Enum.reduce(struct, fn {k, v}, struct ->
      Map.update!(struct, k, &if(is_nil(&1), do: v, else: &1))
    end)
  end
end
