defmodule SomethingsDone, do: defstruct [:a]

defmodule Aggregate do
  use GenServer
  require Logger

  ## custom
  defmodule State, do: defstruct [:transaction, :ttl, :events, :buffer, :msg]

  def start_link, do: GenServer.start_link __MODULE__, :ok, []

  def do_something(pid, val) do 
    Logger.debug "Try #{val}"
    GenServer.call(pid, {:cmd, {:do_something, val}})
  end

  def commit(pid, transaction, events), do: GenServer.call(pid, {:commit, transaction, events})

  def message(pid), do: GenServer.call(pid, {:cmd, :get_message})


  def init(:ok), do: {:ok, %State{buffer: [], msg: "", ttl: 1_000}}
  ## end custom

  def handle_call({:cmd, cmd}, from, %{buffer: [], transaction: nil}=state) do
    Logger.debug "Executing: #{inspect cmd}"
    lock = make_ref
    GenServer.cast self, {:execute, {cmd, from}}
    {:noreply, %{state | transaction: lock}}
  end
  def handle_call({:cmd, cmd}, from, %{}=state) do
    Logger.debug "Buffering: #{inspect cmd}"
    buffer = [{cmd, from} | state.buffer]
    {:noreply, %{state | buffer: buffer}}
  end
  def handle_call({:commit, nil, _events}, _from, state) do 
    {:reply, {:error, :nil_transaction}, state}
  end
  def handle_call({:commit, transaction, events}, _from, %{transaction: transaction}=state) do
    Logger.debug "Commiting: #{inspect transaction}"
    state = apply_events events, state
    GenServer.cast self, :process_buffer
    {:reply, :ok, %{state | transaction: nil, events: []}}
  end
  def handle_call({:commit, t1, _events}, _from, %{transaction: transaction}=state) do 
    {:reply, {:error, :wrong_transaction}, state}
  end

  ## custom
  def handle_cast({:execute, {{:do_something, val}, from}}, state) do
    Logger.debug "Doing #{val}"
    events = [%SomethingsDone{a: val}]
    result = {:ok, state.transaction, events}
    Logger.debug "Result sent: #{inspect result}"

    {:ok, _ref} = :timer.send_after state.ttl, self, {:rollback, state.transaction}
    GenServer.reply from, result
    {:noreply, %State{state | events: events}}
  end
  def handle_cast({:execute, {:get_message, from}}, state) do
    result = state.msg

    GenServer.reply from, result
    {:noreply, %State{state | transaction: nil}}
  end
  ## end custom

  def handle_cast(:process_buffer, %{buffer: []}=state), do: {:noreply, state}
  def handle_cast(:process_buffer, %{buffer: buffer, transaction: nil}=state) do
    lock = make_ref
    {cmd, from} = List.last buffer
    Logger.debug "Processing buffered cmd: #{inspect cmd}"
    buffer = List.delete_at buffer, -1
    GenServer.cast self, {:execute, {cmd, from}}
    {:noreply, %{state | buffer: buffer, transaction: lock}}
  end
  def handle_cast(:process_buffer, state), do: {:noreply, state}

  def handle_info({:rollback, transaction}, %{transaction: transaction}=state) do 
    Logger.warn "Rolling back transaction #{inspect transaction}"
    GenServer.cast self, :process_buffer
    {:noreply, %{state | transaction: nil}}
  end
  def handle_info(_, state), do: {:noreply, state}

  defp apply_events([], state), do: state
  ## custom
  defp apply_events([%SomethingsDone{} = e | tail], state) do
    state = %State{ state | msg: state.msg <> e.a }
    apply_events tail, state
  end
  ## end custom
end
