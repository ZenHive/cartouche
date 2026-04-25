defmodule Cartouche.HTTP do
  @moduledoc """
  HTTP helpers used by cartouche's RPC transports.
  """

  @doc """
  Normalizes the result of a `Finch` request.

  Any non-2xx status codes are wrapped in `{:error, _}`.
  Other Finch errors abstract away the details of Finch.
  """
  @spec normalize_finch_result({:ok, Finch.Response.t()} | {:error, term()}) ::
          {:ok, Finch.Response.t()} | {:error, Finch.Response.t() | String.t()}
  def normalize_finch_result(finch_result) do
    case finch_result do
      {:ok, %Finch.Response{status: code} = resp} when code >= 200 and code < 300 ->
        {:ok, resp}

      {:ok, %Finch.Response{status: _} = resp} ->
        {:error, resp}

      {:error, %Finch.Error{reason: reason}} ->
        {:error, "[Cartouche] HTTP client error: #{inspect(reason)}"}

      {:error, error} ->
        {:error, "[Cartouche] Unknown error: #{inspect(error)}"}
    end
  end
end
