defmodule GenRPC.MixProject do
  use Mix.Project

  @version "3.0.0"
  @source_url "https://github.com/priestjim/gen_rpc"

  def project do
    [
      app: :gen_rpc,
      version: @version,
      description: "A scalable RPC library for Erlang-VM based languages",
      erlc_options: [:debug_info],
      deps: deps(),
      package: package(),
      docs: [main: "readme", source_url: @source_url, extras: ["README.md", "CHANGELOG.md"]]
    ]
  end

  def application do
    [
      mod: {:gen_rpc_app, []},
      registered: [:gen_rpc_dispatcher, :gen_rpc_monitor],
      extra_applications: [:crypto, :asn1, :public_key, :ssl],
      env: app_env()
    ]
  end

  # The default environment lives in src/gen_rpc.app.src (shared with rebar3)
  defp app_env do
    {:ok, [{:application, :gen_rpc, properties}]} = :file.consult("src/gen_rpc.app.src")
    Keyword.fetch!(properties, :env)
  end

  defp deps do
    [
      {:hut, "~> 1.4.0"},
      {:ssl_verify_fun, "~> 1.1.7"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(include src LICENSE README.md CHANGELOG.md mix.exs rebar.config),
      maintainers: ["Panagiotis PJ Papadomitsos"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url, "Changelog" => @source_url <> "/blob/main/CHANGELOG.md"}
    ]
  end
end
