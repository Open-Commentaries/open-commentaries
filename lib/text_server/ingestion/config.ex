defmodule TextServer.Ingestion.Config do
  def parse(f \\ "./commentary.toml") do
    Toml.decode_file(f)
  end
end
