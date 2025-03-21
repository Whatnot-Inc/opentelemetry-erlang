-module(otel_aggregation).

-export([maybe_init_aggregate/4,
         default_mapping/0,
         temporality_mapping/0,
         instrument_temporality/1]).

-include_lib("opentelemetry_api_experimental/include/otel_metrics.hrl").
-include("otel_metrics.hrl").
-include("otel_view.hrl").

-type temporality() :: ?AGGREGATION_TEMPORALITY_UNSPECIFIED |
                       ?AGGREGATION_TEMPORALITY_DELTA |
                       ?AGGREGATION_TEMPORALITY_CUMULATIVE.

%% -type t() :: drop | sum | last_value | histogram.
-type t() :: otel_aggregation_drop:t() | otel_aggregation_sum:t() |
             otel_aggregation_last_value:t() | otel_aggregation_histogram_explicit:t().

-type key() :: {atom(), opentelemetry:attributes_map(), reference()}.

-type options() :: map().

-export_type([t/0,
              key/0,
              options/0,
              temporality/0]).

%% Returns the aggregation's record as it is seen and updated by
%% the aggregation module in the metrics table.
-callback init(ViewAggregation, Attributes) -> Aggregation when
      ViewAggregation :: #view_aggregation{},
      Attributes :: opentelemetry:attributes_map(),
      Aggregation :: t().

-callback aggregate(Table, ViewAggregation, Value, Attributes) -> boolean() when
      Table :: ets:table(),
      ViewAggregation :: #view_aggregation{},
      Value :: number(),
      Attributes :: opentelemetry:attributes_map().

-callback checkpoint(Table, ViewAggregation, CollectionStartTime) -> ok when
      Table :: ets:table(),
      ViewAggregation :: #view_aggregation{},
      CollectionStartTime :: integer().

-callback collect(Table, ViewAggregation, CollectionStartTime) -> tuple() when
      Table :: ets:table(),
      ViewAggregation :: #view_aggregation{},
      CollectionStartTime :: integer().

maybe_init_aggregate(MetricsTab, ViewAggregation=#view_aggregation{aggregation_module=AggregationModule,
                                                                   attribute_keys=AttributeKeys},
                     Value, Attributes) ->
    FilteredAttributes = filter_attributes(AttributeKeys, Attributes),
    case AggregationModule:aggregate(MetricsTab, ViewAggregation, Value, FilteredAttributes) of
        true ->
            ok;
        false ->
            %% entry doesn't exist, create it and rerun the aggregate function
            Metric = AggregationModule:init(ViewAggregation, FilteredAttributes),
            %% don't overwrite a possible concurrent measurement doing the same
            _ = ets:insert_new(MetricsTab, Metric),
            AggregationModule:aggregate(MetricsTab, ViewAggregation, Value, FilteredAttributes)
    end.

filter_attributes(undefined, Attributes) ->
    Attributes;
filter_attributes(Keys, Attributes) ->
    maps:with(Keys, Attributes).

-spec default_mapping() -> #{otel_instrument:kind() => module()}.
default_mapping() ->
    #{?KIND_COUNTER => otel_aggregation_sum,
      ?KIND_OBSERVABLE_COUNTER => otel_aggregation_sum,
      ?KIND_HISTOGRAM => otel_aggregation_histogram_explicit,
      ?KIND_OBSERVABLE_GAUGE => otel_aggregation_last_value,
      ?KIND_UPDOWN_COUNTER => otel_aggregation_sum,
      ?KIND_OBSERVABLE_UPDOWNCOUNTER => otel_aggregation_sum}.

temporality_mapping() ->
    #{?KIND_COUNTER =>?AGGREGATION_TEMPORALITY_DELTA,
      ?KIND_OBSERVABLE_COUNTER => ?AGGREGATION_TEMPORALITY_CUMULATIVE,
      ?KIND_UPDOWN_COUNTER => ?AGGREGATION_TEMPORALITY_DELTA,
      ?KIND_OBSERVABLE_UPDOWNCOUNTER => ?AGGREGATION_TEMPORALITY_CUMULATIVE,
      ?KIND_HISTOGRAM => ?AGGREGATION_TEMPORALITY_UNSPECIFIED,
      ?KIND_OBSERVABLE_GAUGE => ?AGGREGATION_TEMPORALITY_UNSPECIFIED}.

instrument_temporality(#instrument{kind=?KIND_COUNTER}) ->
    ?AGGREGATION_TEMPORALITY_DELTA;
instrument_temporality(#instrument{kind=?KIND_OBSERVABLE_COUNTER}) ->
    ?AGGREGATION_TEMPORALITY_CUMULATIVE;
instrument_temporality(#instrument{kind=?KIND_UPDOWN_COUNTER}) ->
    ?AGGREGATION_TEMPORALITY_DELTA;
instrument_temporality(#instrument{kind=?KIND_OBSERVABLE_UPDOWNCOUNTER}) ->
    ?AGGREGATION_TEMPORALITY_CUMULATIVE;
instrument_temporality(#instrument{kind=?KIND_HISTOGRAM}) ->
    ?AGGREGATION_TEMPORALITY_UNSPECIFIED;
instrument_temporality(#instrument{kind=?KIND_OBSERVABLE_GAUGE}) ->
    ?AGGREGATION_TEMPORALITY_UNSPECIFIED.
