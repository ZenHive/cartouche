defmodule Cartouche.HTTPTest do
  use ExUnit.Case, async: true

  alias Cartouche.HTTP

  describe "normalize_finch_result/1" do
    test "wraps 2xx responses in {:ok, response}" do
      resp = %Finch.Response{status: 200, body: "ok", headers: []}
      assert HTTP.normalize_finch_result({:ok, resp}) == {:ok, resp}
    end

    test "wraps non-2xx responses in {:error, response}" do
      resp = %Finch.Response{status: 500, body: "boom", headers: []}
      assert HTTP.normalize_finch_result({:ok, resp}) == {:error, resp}
    end

    test "maps Finch.Error reasons into an error string" do
      err = %Finch.Error{reason: :timeout}

      assert {:error, "[Cartouche] HTTP client error: :timeout"} =
               HTTP.normalize_finch_result({:error, err})
    end

    test "maps unknown errors into an error string" do
      assert {:error, "[Cartouche] Unknown error: :nope"} =
               HTTP.normalize_finch_result({:error, :nope})
    end
  end
end
