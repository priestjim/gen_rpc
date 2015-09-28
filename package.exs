defmodule FS.Mixfile do
  use Mix.Project

  def project do
    [app: :gen_rpc,
     version: "0.1.0",
     description: "A Elixir wrapper of gen_rpc library for out-of-band messaging",
     package: package]
  end

  defp package do
    [files: ~w(c_src include priv src LICENSE Makefile package.exs README.md rebar.config),
     contributors: ["priestjim"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/priestjim/gen_rpc"}]
   end
end

