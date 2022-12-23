defmodule ReliableFIFOBroadcast do
    def start(name, processes, client \\ :none) do
        pid = spawn(ReliableFIFOBroadcast, :init, [name, processes, client])
        case :global.re_register_name(name, pid) do
            :yes -> pid
            :no  -> :error
        end
        IO.puts "registered #{name}"
        pid
    end

    # Init event must be the first
    # one after the component is created
    def init(name, processes, client) do
        start_beb(name)
        state = %{
            name: name,
            client: (if is_pid(client), do: client, else: self()),
            processes: processes,

            # Add state components below as necessary

            queue: %MapSet{},
            seq_no: 0, # Use this variable to remember the last sequence number used to identify a message
            next:
                for p <- processes, into: %{} do
                    {p, 1}
                end,
        }
        run(state)
    end

    # Helper functions: DO NOT REMOVE OR MODIFY
    defp get_beb_name() do
        {:registered_name, parent} = Process.info(self(), :registered_name)
        String.to_atom(Atom.to_string(parent) <> "_beb")
    end

    defp start_beb(name) do
        Process.register(self(), name)
        pid = spawn(BestEffortBroadcast, :init, [])
        Process.register(pid, get_beb_name())
        Process.link(pid)
    end

    defp beb_broadcast(m, dest) do
        BestEffortBroadcast.beb_broadcast(Process.whereis(get_beb_name()), m, dest)
    end
    # End of helper functions

    def run(state) do
        state = receive do
            {:broadcast, m} ->
                # add code to handle client broadcast requests

                IO.puts("#{inspect state.name}: RB-broadcast: #{inspect m}")
                # Create a new data message data_msg from the given payload m
                # the message identifier.
                data_msg = {:data, self(), state.seq_no, m}
                state = %{state | seq_no: state.seq_no + 1}

                # Use the provided beb_broadcast function to propagate data_msg to
                # all process
                beb_broadcast(data_msg, state.processes)
                state    # return the updated state

            {:data, proc, seq_no, m} ->
               # If <proc, seqno> was already delivered, do nothing.
               # Otherwise, update delivered, generate a deliver event for the
               # upper layer, and re-broadcast (echo) the received message.
               # In both cases, do not forget to return the state.
               if check_message_queue(state) do
                  state = deliver_message(state, proc, seq_no, m)
               else
                  state
               end


            # Add further message handlers as necessary

            # Message handle for delivery event if started without the client argument
            # (i.e., this process is the default client); optional, but useful for debugging
            {:deliver, pid, proc, m} ->
                IO.puts("#{inspect state.name}, #{inspect pid}: RFIFO-deliver: #{inspect m} from #{inspect proc}")
                state
        end
        run(state)
    end

    # Add auxiliary functions as necessary

    defp check_message_queue(state) do
        IO.puts("#{inspect state.next}")
        IO.puts("#{inspect Enum.find(state.queue, fn m -> elem(m, 1) == state.next[elem(m, 1)] end)}")
        Enum.find(state.queue, fn m -> elem(m, 1) == state.next[elem(m, 1)] end)
    end

    defp deliver_message(state) do
        if check_message_queue(state) do
            IO.puts("#{inspect state.queue}")
            {proc, seq_no, m} = check_message_queue(state)
            deliver_message(state, proc, seq_no, m)
        else
            state
        end
    end

    defp deliver_message(state, proc, seq_no, m) do
        # increase next
        state = %{state | next: MapSet.put(state.next, {proc, seq_no + 1})}
        IO.puts("#{state.next}")
        # remove from queue
        state = %{state | queue: MapSet.delete(state.queue, {proc, seq_no})}
        IO.puts("#{state.queue}")
        state = %{state | delivered: MapSet.put(state.delivered, {proc, seq_no})}
        IO.puts("#{state.delivered}")
        send(self(), {:deliver, proc, m})
        beb_broadcast({:data, proc, seq_no, m}, state.processes)
        deliver_message(state)
    end

end
