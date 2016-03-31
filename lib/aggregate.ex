defmodule Aggregate do
  use GenAggregate

  defmodule State, do: defstruct [:transaction, :ttl, :events, :buffer, :msg]

  ## Client API

  def start_link(ttl \\ 2_000), do: GenAggregate.start_link __MODULE__, ttl

  def do_something(pid, val) do 
    Logger.debug "Try #{val}"
    exec pid, {:do_something, val}
  end

  def message(pid), do: exec pid, :get_message


  ## Server Callbacks

  def init(ttl), do: {:ok, %State{buffer: [], msg: "", ttl: ttl}}

  def handle_exec({:do_something, val}, from, state) do
    Logger.debug "Doing #{val}"
    events = [%{val: val}]
    result = {:ok, state.transaction, events}
    Logger.debug "Result sent: #{inspect result}"

    schedule_rollback state.transaction, state.ttl
    reply from, result
    {:noreply, %{state | events: events}}
  end
  def handle_exec(:get_message, from, state) do
    reply from, state.msg
    {:noreply, %{state | transaction: nil}}
  end

  defp apply_events([%{val: val} = e | tail], state) do
    state = %{ state | msg: state.msg <> val }
    apply_events tail, state
  end
end
