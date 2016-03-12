defmodule GenRPC.Mixfile do
  use Mix.Project

  def project do
    [app: :gen_rpc,
     version: "1.0.0",
     description: "A scalable RPC library for Erlang-VM based languages",
     package: package]
  end

  defp package do
    [files: ~w(include src LICENSE Makefile package.exs README.md TODO.md rebar.config),
     maintainers: ["Panagiotis PJ Papadomitsos"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/priestjim/gen_rpc"}]
   end
end

