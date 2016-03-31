defmodule SomethingsDone, do: defstruct [:a]

defmodule Aggregate do
  use GenAggregate

  defmodule State, do: defstruct [:transaction, :ttl, :events, :buffer, :msg]

  def start_link(ttl \\ 2_000), do: GenServer.start_link __MODULE__, ttl, []

  def do_something(pid, val) do 
    Logger.debug "Try #{val}"
    GenServer.call(pid, {:cmd, {:do_something, val}})
  end

  def message(pid), do: GenServer.call(pid, {:cmd, :get_message})


  def init(ttl), do: {:ok, %State{buffer: [], msg: "", ttl: ttl}}

  def handle_cast({:execute, {{:do_something, val}, from}}, state) do
    Logger.debug "Doing #{val}"
    events = [%SomethingsDone{a: val}]
    result = {:ok, state.transaction, events}
    Logger.debug "Result sent: #{inspect result}"

    schedule_rollback state.transaction, state.ttl
    GenServer.reply from, result
    {:noreply, %State{state | events: events}}
  end
  def handle_cast({:execute, {:get_message, from}}, state) do
    result = state.msg

    GenServer.reply from, result
    {:noreply, %State{state | transaction: nil}}
  end

  defp apply_events([%SomethingsDone{} = e | tail], state) do
    state = %State{ state | msg: state.msg <> e.a }
    apply_events tail, state
  end
end
