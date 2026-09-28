defmodule Membrane.Instrumentation.TraceToken do
  @moduledoc """
  Compact frame identity used to correlate instrumentation events across stages.

  Create tokens with `Membrane.Instrumentation.FrameTrace.token/1` and pass them to
  `Membrane.Instrumentation.emit_frame_stage_from_token/5`. Timestamps use monotonic
  nanoseconds and are meaningful only within the originating VM.
  """

  @enforce_keys [:trace_id, :frame_id, :created_at_ns, :sampled]
  defstruct [:trace_id, :frame_id, :created_at_ns, :sampled, :pts]

  @type t :: %__MODULE__{
          trace_id: integer(),
          frame_id: integer(),
          created_at_ns: integer(),
          sampled: boolean(),
          pts: Membrane.Time.t() | nil
        }
end
