defmodule OpenTelemetryAPIExperimental.Histogram do
  @moduledoc """

  """

  defmacro create(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      :otel_meter.create_histogram(
        :opentelemetry_experimental.get_meter(__MODULE__),
        name,
        opts
      )
    end
  end

  defmacro record(name, number, attributes) do
    quote bind_quoted: [name: name, number: number, attributes: attributes] do
      :otel_histogram.record(
        :opentelemetry_experimental.get_meter(__MODULE__),
        name,
        number,
        attributes
      )
    end
  end
end
