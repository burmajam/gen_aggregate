defmodule GenAggregate do

  def start_link(module, init_values, options \\ []) do 
    GenServer.start_link module, init_values, options
  end

  defmacro __using__(_) do
    quote do
      use GenServer
      require Logger

      def commit(pid, transaction), do: GenServer.call(pid, {:commit, transaction})

      def exec(pid, cmd), do: GenServer.call(pid, {:cmd, cmd})

      def reply(to, payload), do: GenServer.reply to, payload

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
      def handle_call({:commit, nil}, _from, state) do 
      {:reply, {:error, :nil_transaction}, state}
      end
      def handle_call({:commit, transaction}, _from, %{transaction: transaction}=state) do
        Logger.debug "Commiting: #{inspect transaction}"
        state = apply_events state.events, state
        GenServer.cast self, :process_buffer
        {:reply, :ok, %{state | transaction: nil, events: []}}
      end
      def handle_call({:commit, t1}, _from, %{transaction: transaction}=state) do 
        {:reply, {:error, :wrong_transaction}, state}
      end

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
      def handle_cast({:execute, {cmd, from}}, state) do
        handle_exec cmd, from, state
      end

      def handle_info({:rollback, transaction}, %{transaction: transaction}=state) do 
      Logger.warn "Rolling back transaction #{inspect transaction}"
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
