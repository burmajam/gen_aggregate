defmodule GenAggregate do
  @moduledoc """
  Generic Aggregate module.

  ## Example

      defmodule MyAggregate do
        use GenAggregate
      
        defmodule State, do: defstruct [:transaction, :ttl, :events, :buffer, :msg]
      
        ## Client API
      
        def start_link(ttl \\ 2_000), do: GenAggregate.start_link __MODULE__, ttl
      
        def do_something(pid, val), do: exec pid, {:do_something, val}
      
        def message(pid), do: exec pid, :get_message
      
        ## Server Callbacks
      
        def init(ttl), do: {:ok, %State{buffer: [], msg: "", ttl: ttl}} 

        def handle_exec({:do_something, val}, from, state) do
          events = [%{val: val}]
          result = {:ok, state.transaction, events}
      
          {:block, from, result, %{state | events: events}}
        end
        def handle_exec(:get_message, from, state) do
          {:noblock, from, state.msg, state}
        end
      
        defp apply_events([%{val: val} | tail], state) do
          state = %{ state | msg: state.msg <> val }
          apply_events tail, state
        end
      end

    Use it then as:
    {:ok, a} = MyAggregate.start_link
    {:ok, transaction_id, _} = MyAggregate.do_something(a, "something")
    :ok = MyAggregate.commit a, transaction_id
    MyAggregate.message(a)
    #=> "something"
  """

  def start_link(module, init_values, options \\ []) do 
    GenServer.start_link module, init_values, options
  end

  defmacro __using__(_) do
    quote do
      use GenServer
      #require Logger

      def commit(pid, transaction), do: GenServer.call(pid, {:commit, transaction})

      def exec(pid, cmd), do: GenServer.call(pid, {:cmd, cmd})

      def reply(to, payload), do: GenServer.reply to, payload

      def apply(pid, events), do: GenServer.call(pid, {:apply_stream_events, events})

      def handle_call({:cmd, cmd}, from, %{buffer: [], transaction: nil}=state) do
        #Logger.debug "Executing: #{inspect cmd}"
        lock = make_ref
        GenServer.cast self, {:execute, {cmd, from}}
        {:noreply, %{state | transaction: lock}}
      end
      def handle_call({:cmd, cmd}, from, %{}=state) do
        #Logger.debug "Buffering: #{inspect cmd}"
        buffer = [{cmd, from} | state.buffer]
        {:noreply, %{state | buffer: buffer}}
      end
      def handle_call({:commit, nil}, _from, state) do 
      {:reply, {:error, :nil_transaction}, state}
      end
      def handle_call({:commit, transaction}, _from, %{transaction: transaction}=state) do
        #Logger.debug "Commiting: #{inspect transaction}"
        state = apply_events state.events, state
        GenServer.cast self, :process_buffer
        {:reply, :ok, %{state | transaction: nil, events: []}}
      end
      def handle_call({:commit, t1}, _from, %{transaction: transaction}=state) do 
        {:reply, {:error, :wrong_transaction}, state}
      end
      def handle_call({:apply_stream_events, events_stream}, _from, state) do
        state = Enum.reduce(events_stream, state, fn({event, _event_number}, acc) -> apply_events([event], acc) end)
        {:reply, :ok, state}
      end


      def handle_cast(:process_buffer, %{buffer: []}=state), do: {:noreply, state}
      def handle_cast(:process_buffer, %{buffer: buffer, transaction: nil}=state) do
        lock = make_ref
        {cmd, from} = List.last buffer
        #Logger.debug "Processing buffered cmd: #{inspect cmd}"
        buffer = List.delete_at buffer, -1
        GenServer.cast self, {:execute, {cmd, from}}
        {:noreply, %{state | buffer: buffer, transaction: lock}}
      end
      def handle_cast(:process_buffer, state), do: {:noreply, state}
      def handle_cast({:execute, {cmd, from}}, state) do
        case handle_exec(cmd, from, state) do
          {:block, from, {:events, events}, state} when is_list(events) ->
            schedule_rollback state.transaction, state.ttl
            GenServer.reply from, {:ok, state.transaction, events}
            {:noreply, %{state | events: events}}
          {:block, from, response, state} ->
            schedule_rollback state.transaction, state.ttl
            GenServer.reply from, response
            {:noreply, state}
          {:noblock, from, response, state} ->
            GenServer.reply from, response
            {:noreply, %{state | transaction: nil}}
        end
      end

      def handle_info({:rollback, transaction}, %{transaction: transaction}=state) do 
      #Logger.warn "Rolling back transaction #{inspect transaction}"
      GenServer.cast self, :process_buffer
      {:noreply, %{state | transaction: nil}}
      end
      def handle_info(_, state), do: {:noreply, state}

      defp schedule_rollback(transaction, ttl) do 
        {:ok, _ref} = :timer.send_after ttl, self, {:rollback, transaction}
      end

      defp apply_events([], state), do: state
    end
  end
end
